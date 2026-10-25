// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve failed337 and derive a fresh339 retry with absolute baseline inputs.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const root = state + 'maps339-recovery-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && !os.exists(root) && hash(compiler)! == compiler_pin
	os.mkdir(root)!
	os.cp(@FILE, root + '/recover.v')!
	os.cp(os.executable(), root + '/recover')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	inputs := {
		'generate': 'a00fa8bc380ba3e584ab1acfd253cd1eb08858e15a88926571378e2c59aa16d5'
		'receipt-generate': '1c97c52db1985b91fbd8ab743f2828b09e76f6fd68dd14e341d813e6838bbe2f'
	}
	for label, pin in inputs {
		before := 'tests/native-android-ws/maps337-' + label + '.v'
		after := before.replace('337', '339')
		assert hash(before)! == pin && !os.exists(after)
		mut text := os.read_file(before)!.replace('337', '339')
		if label == 'generate' {
			old := "\ttext = once(text, \"config.replace('339', '333')\", \"config.replace('339', '335')\")"
			new := "\ttext = once(text, \"previous + '/prelaunch/inputs/' + config.replace('339', '333')\", \"previous + '/prelaunch/inputs/Users/alex/code/vinix/' + config.replace('339', '335')\")"
			assert text.count(old) == 1
			text = text.replace(old, new)
		}
		os.write_file(after, text)!
		os.cp(before, root + '/maps337-' + label + '.v')!
		os.cp(after, root + '/maps339-' + label + '.v')!
		os.mkdir(root + '/' + label + '-generated-c')!
		os.setenv('VTMP', root + '/' + label + '-generated-c', true)
		argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-cflags', '-O2', '-o', 'build/android-maps/maps339-' + label, after]
		started := time.utc().str()
		result := os.exec(argv)
		os.write_file(root + '/' + label + '-build.log', result.output)!
		os.write_file(root + '/' + label + '-build-receipt.json', json2.encode({
			'argv': json2.Any(argv)
			'started_utc': json2.Any(started)
			'completed_utc': json2.Any(time.utc().str())
			'exit_code': json2.Any(result.exit_code)
			'original_source_sha256': json2.Any(pin)
			'generated_source_sha256': json2.Any(hash(after)!)
			'compiler_sha256': json2.Any(compiler_pin)
		}, prettify: true) + '\n')!
		assert result.exit_code == 0 && hash(before)! == pin && hash(compiler)! == compiler_pin, result.output
	}
	println('MAPS339-RECOVERY-GENERATORS-PASS')
}
