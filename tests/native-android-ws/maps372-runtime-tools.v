// SPDX-License-Identifier: GPL-2.0-or-later
// Derive fresh Maps372 receipt tools from the retained, qualified Maps370 tools.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/maps372-runtime-tools-2026-10-26'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const references = {
	'maps370-replay-receipt.v': 'd0db25fa6b9604f42c29a0338d4810b8afcb45b53651945760757b4f1258a2e4'
	'maps370-replacement-pins.v': '293deb49c81fcbc772d840c80d5df9c1a2f4fb0afe51b5bb1118060cf52bab1a'
	'maps370-wrapper-peer-readback.v': '80800b06c945e8ddf0c8b9d5d96365529ded3a4c0d0b07e194aacd51283edacd'
}

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn once(text string, before string, after string) !string {
	if text.count(before) != 1 { return error('unique replacement required: ' + before) }
	return text.replace(before, after)
}

fn derive(input string, name string) !string {
	mut text := input
	for token in ['maps370', 'Maps370', 'MAPS370', 'runner370', 'source370', "'370'",
		"'0370'", "'370x'", 'non370', 'prepare 370', 'run 370'] {
		text = text.replace(token, token.replace('370', '372'))
	}
	if name != 'maps370-wrapper-peer-readback.v' {
		for before, after in {
			'intent-uri369-framework-build-2026-10-26': 'intent-uri371-framework-build-2026-10-26'
			'9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93': '71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750'
			'74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b': '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
		} { text = once(text, before, after)! }
		text = text.replace('Framework369', 'Framework371').replace('qualified351/369', 'qualified351/371')
	}
	assert !text.contains('370'), 'old replay label remains: ' + name
	if name == 'maps370-replay-receipt.v' {
		text = once(text, "'369', '0372', '372x'", "'369', '370', '371', '0372', '372x'")!
		text = once(text, 'assert stages_rejected == 10', 'assert stages_rejected == 12')!
	}
	return text
}

fn self_test() ! {
	for name, pin in references {
		path := repo + '/tests/native-android-ws/' + name
		assert hash(path)! == pin
		before := os.read_file(path)!
		after := derive(before, name)!
		assert after != before && hash(path)! == pin
		if name == 'maps370-replay-receipt.v' {
			assert after.contains("number != '372'")
			assert after.contains('assert stages_rejected == 12')
			for function in ['clean', 'replacement_identity', 'select_runner_pin', 'command', 'build_closure'] {
				marker := '\nfn ' + function + '('
				assert before.count(marker) == 1 && after.count(marker) == 1
				assert before.all_after(marker).all_before('\nfn ') == after.all_after(marker).all_before('\nfn '),
					'unchanged receipt function required: ' + function
			}
		}
	}
	once('duplicate duplicate', 'duplicate', 'changed') or {
		println('MAPS372-RUNTIME-TOOLS-SELF-TEST-PASS')
		return
	}
	return error('duplicate replacement was accepted')
}

fn command(label string, argv []string) ! {
	program_pin := hash(argv[0])!
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	write_json(root + '/' + label + '.json', {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(result.exit_code)
		'program_sha256_before': json2.Any(program_pin)
		'program_sha256_after': json2.Any(hash(argv[0])!)
		'output_sha256': json2.Any(hash(root + '/' + label + '.log')!)
	})!
	assert hash(argv[0])! == program_pin && result.exit_code == 0, result.output
	print(result.output)
}

fn inventory(path string, relative string, mut entries map[string]string) ! {
	for name in os.ls(path)! {
		key := if relative == '' { name } else { relative + '/' + name }
		full := path + '/' + name
		assert !os.is_link(full)
		match os.lstat(full)!.get_filetype() {
			.directory { inventory(full, key, mut entries)! }
			.regular { entries[key] = hash(full)! }
			else { return error('ordinary evidence entry required: ' + full) }
		}
	}
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo && os.real_path(state) == state
	assert hash(compiler)! == compiler_pin
	self_test()!
	if os.args.len == 2 && os.args[1] == '--self-test' { return }
	assert os.args.len == 1, 'usage: maps372-runtime-tools [--self-test]'
	outputs := ['maps372-replay-receipt-recorded', 'maps372-wrapper-peer-readback']
	for path in [root, state + '/maps372-replay-receipt-build-2026-10-26',
		state + '/maps372-replay-receipt-build-2026-10-26-selftest',
		state + '/maps372-replacement-pins-write-2026-10-26',
		state + '/maps372-replacement-pins-2026-10-26.json'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	for name in outputs {
		assert !os.exists(repo + '/build/android-maps/' + name)
	}
	os.mkdir(root)!
	os.cp(@FILE, root + '/generator.v')!
	os.cp(os.executable(), root + '/generator')!
	os.mkdir(root + '/generated-c')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', root + '/generated-c', true)
	mut generated := map[string]string{}
	for name, pin in references {
		original := repo + '/tests/native-android-ws/' + name
		assert hash(original)! == pin
		os.cp(original, root + '/' + name)!
		target := root + '/' + name.replace('370', '372')
		os.write_file(target, derive(os.read_file(original)!, name)!)!
		generated[target] = hash(target)!
	}
	wrapper := root + '/maps372-replay-receipt.v'
	command('wrapper-bootstrap', [compiler, '-nocache', '-cc', '/usr/bin/cc', '-o',
		root + '/wrapper-bootstrap', wrapper])!
	command('wrapper-build', [root + '/wrapper-bootstrap', 'build',
		state + '/maps372-replay-receipt-build-2026-10-26', repo + '/build/android-maps/' + outputs[0]])!
	os.setenv('VTMP', root + '/generated-c', true)
	command('pin-writer-bootstrap', [compiler, '-nocache', '-cc', '/usr/bin/cc', '-o',
		root + '/pin-writer-bootstrap', root + '/maps372-replacement-pins.v'])!
	command('pin-writer-run', [root + '/pin-writer-bootstrap'])!
	os.setenv('VTMP', root + '/generated-c', true)
	command('wrapper-reader-build', [compiler, '-nocache', '-cc', '/usr/bin/cc', '-o',
		repo + '/build/android-maps/' + outputs[1], root + '/maps372-wrapper-peer-readback.v'])!
	for path, pin in generated { assert hash(path)! == pin }
	write_json(root + '/derivation.json', {
		'reference_source_sha256': json2.decode[json2.Any](json2.encode(references))!
		'generated_source_sha256': json2.decode[json2.Any](json2.encode(generated))!
		'compiler_sha256': json2.Any(compiler_pin)
		'scope': json2.Any('Exact fresh372 labels, final qualified371 framework identities, and old370/371 stage rejection only. Original wrapper build, environment, identity and nonzero-status self-tests preserved. No guest launch.')
	})!
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	write_json(root + '/sha256.json', entries)!
	println('MAPS372-RUNTIME-TOOLS-PASS manifest=' + hash(root + '/sha256.json')!)
}
