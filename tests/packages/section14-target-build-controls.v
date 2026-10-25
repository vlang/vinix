// SPDX-License-Identifier: GPL-2.0-or-later
// Resealed negative controls on a complete disposable hosted-options bundle.
module main

import crypto.sha256
import hosttest
import json2
import os

const reviewed_seal = 'c5b72beb336e451695c58094d8f77ed850014ee180fe609bf5d05582b267834d'

struct Control {
	name string
	expected_refusal string
	exit_code int
	stdout string
	stderr string
	mutated_manifest_sha256 string
}

struct Receipt {
	format int = 1
	baseline string
	baseline_manifest_sha256 string
	checker_sha256 string
	helper_sha256 string
	disposable_copy string
	controls []Control
	restored_copy_manifest_sha256 string
	baseline_manifest_sha256_after string
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(checker string, bundle string, log string) !hosttest.Result {
	return hosttest.capture([checker, '--check=' + bundle], log, 300, os.environ())
}

fn accepted(checker string, bundle string, log string) ! {
	result := command(checker, bundle, log)!
	if result.code != 0 { return error('baseline/restoration refused: ' + log + '\n' + result.stdout + result.stderr) }
}

fn reseal(root string) !string {
	mut paths := os.walk_ext(root, '', hidden: true)
	paths.sort()
	mut lines := []string{}
	for path in paths {
		if os.is_file(path) && path != root + '/bundle.sha256' {
			lines << digest(path)! + '\t' + path[root.len + 1..]
		}
	}
	os.write_file(root + '/bundle.sha256', lines.join('\n') + '\n')!
	return digest(root + '/bundle.sha256')!
}

fn number(data []u8, start int, length int) u64 {
	mut result := u64(0)
	for index in 0 .. length { result |= u64(data[start + index]) << (8 * index) }
	return result
}

fn interpreter_header(data []u8) !int {
	offset := int(number(data, 32, 8))
	size := int(number(data, 54, 2))
	count := int(number(data, 56, 2))
	for index in 0 .. count {
		start := offset + size * index
		if number(data, start, 4) == 3 { return start }
	}
	return error('baseline bridge lacks PT_INTERP')
}

fn duplicate_interpreter(mut data []u8) ! {
	original := interpreter_header(data)!
	offset := int(number(data, 32, 8))
	size := int(number(data, 54, 2))
	count := int(number(data, 56, 2))
	for index in 0 .. count {
		start := offset + size * index
		if number(data, start, 4) in [u64(1), 3] { continue }
		for byte in 0 .. 4 { data[start + byte] = if byte == 0 { u8(3) } else { u8(0) } }
		for field in [8, 32] {
			for byte in 0 .. 8 { data[start + field + byte] = data[original + field + byte] }
		}
		return
	}
	return error('baseline bridge lacks a spare program header')
}

fn run(bundle string, output string) ! {
	baseline := os.real_path(bundle)
	out := os.abs_path(output)
	if os.exists(out) { return error('control output must be new') }
	mut ancestor := os.dir(out)
	for !os.exists(ancestor) { ancestor = os.dir(ancestor) }
	parent := os.real_path(ancestor)
	if out == baseline || out.starts_with(baseline + '/') || parent == baseline || parent.starts_with(baseline + '/') {
		return error('control output must be outside the baseline')
	}
	if digest(baseline + '/bundle.sha256')! != reviewed_seal { return error('unexpected baseline seal') }
	os.mkdir_all(out)!
	os.cp(@FILE, out + '/controls.v')!
	os.cp(os.executable(), out + '/controls')!
	checker := baseline + '/runner'
	accepted(checker, baseline, out + '/baseline-before.log')!
	copy := out + '/disposable-bundle'
	os.cp_all(baseline, copy, true)!
	accepted(checker, copy, out + '/copy-before.log')!
	manifest := os.read_file(copy + '/bundle.sha256')!
	bridge := copy + '/aarch64/bridge/bridge'
	bridge_bytes := os.read_bytes(bridge)!
	other_bridge := copy + '/x86_64/bridge/bridge'
	other_bytes := os.read_bytes(other_bridge)!
	hidden := copy + '/source/ui2/linux/.gitkeep'
	hidden_bytes := os.read_bytes(hidden)!
	addition := copy + '/source/.section14-negative-control'
	alias := copy + '/section14-negative-alias'
	mut controls := []Control{}
	for name, expected in {
		'bridge-et-exec': 'unexpected ELF64 executable architecture'
		'bridge-wrong-interpreter': 'unexpected ELF interpreter'
		'bridge-duplicate-interpreter': 'missing or duplicate ELF interpreter'
		'hidden-source-added': 'input count changed'
		'hidden-source-removed': 'input count changed'
		'bundle-symlink': 'unexpected bundle symlink'
		'missing-bridge-output': 'missing hosted bridge artifact: bridge/bridge'
	} {
		mut changed := bridge_bytes.clone()
		match name {
			'bridge-et-exec' { changed[16] = 2; os.write_file_array(bridge, changed)! }
			'bridge-wrong-interpreter' {
				start := int(number(changed, interpreter_header(changed)! + 8, 8))
				changed[start] = `!`
				os.write_file_array(bridge, changed)!
			}
			'bridge-duplicate-interpreter' { duplicate_interpreter(mut changed)!; os.write_file_array(bridge, changed)! }
			'hidden-source-added' { os.write_file(addition, 'must be inventoried\n')! }
			'hidden-source-removed' { os.rm(hidden)! }
			'bundle-symlink' { os.symlink(hidden, alias)! }
			'missing-bridge-output' { os.rm(other_bridge)! }
			else { return error('unknown control') }
		}
		seal := reseal(copy)!
		os.cp(copy + '/bundle.sha256', out + '/' + name + '-manifest.sha256')!
		if name.starts_with('bridge-') { os.write_file_array(out + '/' + name + '.elf', changed)! }
		result := command(checker, copy, out + '/' + name + '.log')!
		if result.code == 0 || !((result.stdout + result.stderr).contains(expected)) {
			return error('negative control did not refuse as expected: ' + name + '\n' + result.stdout + result.stderr)
		}
		controls << Control{name: name, expected_refusal: expected, exit_code: result.code,
			stdout: result.stdout, stderr: result.stderr, mutated_manifest_sha256: seal}
		if os.is_link(alias) { os.rm(alias)! }
		if os.exists(addition) { os.rm(addition)! }
		os.write_file_array(bridge, bridge_bytes)!
		os.write_file_array(other_bridge, other_bytes)!
		os.write_file_array(hidden, hidden_bytes)!
		os.write_file(copy + '/bundle.sha256', manifest)!
		accepted(checker, copy, out + '/' + name + '-restored.log')!
		println('SECTION14 TARGET CONTROL passed ' + name + ': ' + expected)
	}
	accepted(checker, baseline, out + '/baseline-after.log')!
	receipt := Receipt{baseline: baseline, baseline_manifest_sha256: reviewed_seal,
		checker_sha256: digest(checker)!, helper_sha256: digest(@FILE)!, disposable_copy: copy,
		controls: controls, restored_copy_manifest_sha256: digest(copy + '/bundle.sha256')!,
		baseline_manifest_sha256_after: digest(baseline + '/bundle.sha256')!}
	if receipt.baseline_manifest_sha256_after != reviewed_seal || receipt.restored_copy_manifest_sha256 != reviewed_seal {
		return error('baseline or restored seal changed')
	}
	os.write_file(out + '/controls.json', json2.encode(receipt) + '\n')!
	println('SECTION14 TARGET CONTROLS receipt ' + digest(out + '/controls.json')!)
}

fn main() {
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') { eprintln('use --bundle=SEALED_BUNDLE --out=NEW_DIRECTORY'); exit(1) }
		options[argument.all_before('=')] = argument.all_after('=')
	}
	run(options['--bundle'] or { eprintln('--bundle is required'); exit(1) },
		options['--out'] or { eprintln('--out is required'); exit(1) }) or { eprintln(err); exit(1) }
}
