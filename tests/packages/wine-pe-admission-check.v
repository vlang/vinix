// SPDX-License-Identifier: GPL-2.0-or-later
// Host admission/lifetime qualification; never executes a Windows program.
module main

import crypto.sha256
import json2
import os

struct Input {
	kind string
	target string
	sha256 string
}

struct Run {
	name string
	argv []string
	compile_exit int
	run_exit int
	expected string
}

struct Receipt {
	format int = 1
	scope string = 'host local PE receipt admission; synthetic controls and optional real producer admission; no Wine execution, publisher authentication or hermetic build claim'
	compiler string
	backend string
	inputs map[string]Input
	outputs map[string]string
	runs []Run
	real_receipt string
}

struct Summary {
	format int = 1
	scope string = 'host local PE receipt admission only; no Windows execution or publisher trust claim'
	proof_sha256 string
	input_inventory_sha256 string
	input_count int
	sources map[string]string
	tools map[string]string
	outputs map[string]string
	runs []Run
	real_receipt string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: 32}
	defer { unsafe { buffer.free(); sum.free(); hash.free(); free(hash) } }
	for {
		n := file.read(mut buffer) or {
			if file.eof() { unsafe { err.free() }; break }
			unsafe { err.free() }
			return error('cannot hash host input: ' + path)
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn inventory(path string, selected bool, depth int, mut inputs map[string]Input) ! {
	if depth > 256 || inputs.len > 100000 { return error('host input inventory exceeds its bound') }
	if os.is_link(path) {
		target := os.readlink(path)!
		resolved := os.real_path(path)
		defer { unsafe { resolved.free() } }
		inputs[path] = Input{kind: 'symlink', target: target, sha256: if os.is_file(resolved) { digest(resolved)! } else { '' }}
	} else if os.is_dir(path) {
		inputs[path] = Input{kind: 'directory'}
		names := os.ls(path)!
		defer { unsafe { names.free() } }
		for name in names {
			next := path + '/' + name
			defer { unsafe { next.free() } }
			inventory(next, selected, depth + 1, mut inputs)!
		}
	} else if !selected || path.ends_with('.v') {
		if !os.is_file(path) { return error('host input is not an ordinary file: ' + path) }
		inputs[path] = Input{kind: 'file', sha256: digest(path)!}
	}
}

fn capture(v string, cc string, root string) !map[string]Input {
	mut inputs := map[string]Input{}
	for module_name in ['wineadapter', 'pkgprotocol', 'appsdk']! {
		inventory(root + '/tools/packages/' + module_name, true, 0, mut inputs)!
	}
	for path in [v, cc, '/usr/bin/ld', os.executable(), @FILE,
		root + '/desktop/tools/tests/heap_tracker.h'] {
		inputs[path] = Input{kind: 'file', sha256: digest(path)!}
	}
	for name in ['vlib', 'thirdparty']! {
		inventory(os.dir(v) + '/' + name, false, 0, mut inputs)!
	}
	return inputs
}

fn same(before map[string]Input, after map[string]Input) ! {
	if before.len != after.len { return error('host input inventory changed') }
	for path, input in before {
		defer { unsafe { path.free() } }
		other := after[path] or { return error('host input disappeared: ' + path) }
		if input.kind != other.kind || input.target != other.target || input.sha256 != other.sha256 {
			return error('host input changed: ' + path)
		}
	}
}

fn invoke(argv []string, log string) !int {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	defer { unsafe { output.free() } }
	child.wait()
	os.write_file(log, output)!
	return child.code
}

fn freeze(root string, directory string, inputs map[string]Input) ! {
	for path, input in inputs {
		defer { unsafe { path.free() } }
		if input.kind != 'file' || !path.starts_with(root + '/') { continue }
		relative := path[root.len + 1..]
		if !relative.starts_with('tools/packages/') && relative != 'desktop/tools/tests/heap_tracker.h' { continue }
		target := directory + '/' + relative
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if digest(target)! != input.sha256 { return error('frozen host source copy differs') }
	}
	os.write_file(directory + '/v.mod', "Module { name: 'pe_admission_check' }\n")!
	// Bind the copied test to the copied header rather than the caller's module root.
	test_path := directory + '/tools/packages/wineadapter/pe_proof_test.v'
	test_source := os.read_file(test_path)!
	defer { unsafe { test_source.free() } }
	os.write_file(test_path, test_source.replace('@VMODROOT/../../../desktop/tools/tests/heap_tracker.h',
		directory + '/desktop/tools/tests/heap_tracker.h'))!
}

fn check() ! {
	$if !prod { return error('compile this source-capturing driver with -prod; its checks use explicit errors') }
	if os.args.len !in [5, 8]! { return error('usage: wine-pe-admission-check V CLANG WORKTREE NEW_OUTPUT [REAL_PE_DIRECTORY PROGRAM_SOURCE PRODUCER_SOURCE]') }
	v := os.real_path(os.args[1])
	cc := os.real_path(os.args[2])
	root := os.real_path(os.args[3])
	out := os.abs_path(os.args[4])
	if os.exists(out) { return error('PE admission qualification requires a new output directory') }
	compiled_source := $embed_file('wine-pe-admission-check.v').to_string()
	if digest(@FILE)! != sha256.hexhash(compiled_source) { return error('PE admission driver source differs from compiled bytes') }
	mut inputs := capture(v, cc, root)!
	mut real_receipt := ''
	if os.args.len == 8 {
		real_receipt = os.real_path(os.args[5])
		for path in [real_receipt + '/proof.json', os.real_path(os.args[6]), os.real_path(os.args[7])] {
			inputs[path] = Input{kind: 'file', sha256: digest(path)!}
		}
	}
	os.mkdir_all(out)!; os.chmod(out, 0o700)!
	os.write_file(out + '/inputs-before-build.json', json2.encode(inputs) + '\n')!
	mut runs := []Run{}
	for name in ['normal', 'prod', 'sanitized', 'disabled-command-guard']! {
		directory := out + '/' + name
		frozen := directory + '/source'
		freeze(root, frozen, inputs)!
		if name == 'disabled-command-guard' {
			path := frozen + '/tools/packages/wineadapter/pe_proof.c.v'
			original := os.read_file(path)!
			guard := 'if record.commands != expected_commands {'
			if original.count(guard) != 1 { return error('command guard negative control site differs') }
			os.write_file(path, original.replace(guard, 'if false && record.commands != expected_commands {'))!
		}
		mut argv := [v, '-backend', 'c', '-cc', cc, '-nocache', '-gc', 'none', '-manualfree',
			'-d', 'track_heap', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-keepc',
			'-path', frozen + '|@vlib|@vmodules']
		if name in ['prod', 'disabled-command-guard']! { argv << '-prod' }
		if name == 'sanitized' { argv << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined'] }
		argv << ['-o', directory + '/check', frozen + '/tools/packages/wineadapter/pe_proof_test.v']
		code := invoke(argv, directory + '/compile.log')!
		if code != 0 { return error('PE admission test compilation failed: ' + name) }
		run_code := invoke([directory + '/check'], directory + '/run.log')!
		log := os.read_file(directory + '/run.log')!
		if name == 'disabled-command-guard' {
			if run_code == 0 || !log.contains('changed or malformed PE proof admitted') {
				return error('disabled command guard was not caught by resealed control')
			}
		} else {
			if run_code != 0 { return error('PE admission test execution failed: ' + name) }
			for marker in [
				'PE ADMISSION descriptor counter detects a live descriptor above a free gap PASS',
				'PE ADMISSION every truncated JSON prefix and malformed Unicode retain zero tracked V bytes PASS',
				'PE ADMISSION resealed schema/input/output/command/path/overlap/header refusals retain zero tracked V bytes and descriptors PASS',
				'PE ADMISSION 1000 complete captures and double closes retain zero tracked V bytes and descriptors PASS',
			]! {
				if log.count(marker) != 1 { return error('PE admission test success marker differs: ' + name) }
			}
			if log.contains('AddressSanitizer') || log.contains('runtime error:') { return error('PE admission sanitizer diagnostic') }
		}
		runs << Run{name: name, argv: argv, compile_exit: code, run_exit: run_code,
			expected: if name == 'disabled-command-guard' { 'resealed command refusal must fail' } else { '1000 success, all measured refusals and decoder prefixes retain zero tracked V bytes' }}
	}
	if os.args.len == 8 {
		source := 'module main\nimport json2\nimport os\nimport tools.packages.wineadapter\nfn main() { check() or { eprintln(err); exit(1) } }\nfn check() ! {\n if os.args.len != 5 { return error("real PE admission arguments differ") }\n mut proof := wineadapter.admit_local_pe_proof(os.args[1], os.args[2], os.args[3])!\n defer { proof.close() }\n if proof.artifacts.len < 15 { return error("real PE artifact inventory is incomplete") }\n os.write_file(os.args[4], json2.encode(proof.artifacts) + "\\n")!\n println("REAL LOCAL PE RECEIPT ADMISSION PASS")\n}\n'
		os.write_file(out + '/real-admit.v', source)!
		argv := [v, '-backend', 'c', '-cc', cc, '-nocache', '-prod', '-gc', 'none', '-manualfree', '-keepc',
			'-path', out + '/prod/source|@vlib|@vmodules', '-o', out + '/real-admit', out + '/real-admit.v']
		code := invoke(argv, out + '/real-compile.log')!
		if code != 0 { return error('real PE admission compilation failed') }
		run_code := invoke([out + '/real-admit', real_receipt, os.real_path(os.args[6]), os.real_path(os.args[7]), out + '/real-artifacts.json'], out + '/real-run.log')!
		if run_code != 0 { return error('real PE receipt admission failed') }
		runs << Run{name: 'real-producer-receipt', argv: argv, compile_exit: code, run_exit: run_code,
			expected: 'admit real producer receipt and retain returned complete ordinary-file artifact pins; never execute PE'}
	}
	mut after := capture(v, cc, root)!
	// The optional real receipt is not part of the module/compiler inventory.
	if real_receipt != '' {
		for path in [real_receipt + '/proof.json', os.real_path(os.args[6]), os.real_path(os.args[7])] {
			after[path] = Input{kind: 'file', sha256: digest(path)!}
		}
	}
	same(inputs, after)!
	os.write_file(out + '/inputs-verified.json', json2.encode(after) + '\n')!
	mut outputs := map[string]string{}
	for path in os.walk_ext(out, '') { if os.is_file(path) { outputs[path[out.len + 1..]] = digest(path)! } }
	os.write_file(out + '/proof.json', json2.encode(Receipt{compiler: v, backend: cc, inputs: inputs,
		outputs: outputs, runs: runs, real_receipt: real_receipt}) + '\n')!
	mut sources := map[string]string{}
	mut tool_pins := map[string]string{}
	for path, input in inputs {
		defer { unsafe { path.free() } }
		if input.kind != 'file' { continue }
		if path.starts_with(root + '/tools/packages/') || path == root + '/desktop/tools/tests/heap_tracker.h' {
			sources[path[root.len + 1..]] = input.sha256
		} else if path in [v, cc, '/usr/bin/ld', os.executable(), @FILE] {
			tool_pins[path] = input.sha256
		}
	}
	mut retained_outputs := map[string]string{}
	for path, value in outputs {
		defer { unsafe { path.free() } }
		if !path.contains('/source/') { retained_outputs[path] = value }
	}
	os.write_file(out + '/summary.json', json2.encode(Summary{proof_sha256: digest(out + '/proof.json')!,
		input_inventory_sha256: digest(out + '/inputs-before-build.json')!, input_count: inputs.len,
		sources: sources, tools: tool_pins, outputs: retained_outputs, runs: runs, real_receipt: real_receipt}) + '\n')!
	println('PE ADMISSION normal+prod+ASan/UBSan zero allocations and descriptors; prod disabled-guard control PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
