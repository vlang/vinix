// SPDX-License-Identifier: GPL-2.0-or-later
// Host preparation only. Guest execution belongs to the evidence runner.
module main

import os
import crypto.sha256
import json2
import time

fn recorded(label string, argv []string, output string) ! {
	base := 'build/android-maps/compound284'
	path := base + '/' + label
	assert !os.exists(path + '-before.json')
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'completed_utc': json2.Any(''), 'VROOT': json2.Any(os.getenv('VROOT')), 'V': json2.Any(os.getenv('V')), 'VINIX_V_COMPILER': json2.Any(os.getenv('VINIX_V_COMPILER')), 'source_sha256': json2.Any(sha256.sum(os.read_bytes('tests/native-android-ws/queue-pump-build.v')!).hex()), 'runner_source_sha256': json2.Any(sha256.sum(os.read_bytes(@FILE)!).hex()), 'command_binary_sha256': json2.Any(sha256.sum(os.read_bytes(os.real_path(argv[0]))!).hex()), 'output_sha256': json2.Any('')}
	os.write_file(path + '-before.json', json2.encode(receipt, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(path + '.log', r.output)!
	print(r.output)
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	if output != '' && r.exit_code == 0 { receipt['output_sha256'] = sha256.sum(os.read_bytes(output)!).hex() }
	os.write_file(path + '-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	assert r.exit_code == 0
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len == 2 && os.args[1] in ['freeze', 'build', 'prepare-runs', 'verify', '--self-test']
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', os.abs_path('build/android-maps/queue284-tools/v_old276'), true)
	os.setenv('VINIX_V_COMPILER', os.getenv('V'), true)
	tool := 'build/android-maps/queue-pump-build284'
	if os.args[1] in ['freeze', '--self-test'] {
		assert !os.exists(tool), 'preserve the previous tool binary; use a fresh destination'
		os.mkdir_all(os.dir(tool))!
		os.mkdir_all('build/android-maps/compound284')!
		recorded('preparation-tool-compiler', ['build/android-maps/queue284-tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', tool, 'tests/native-android-ws/queue-pump-build.v'], tool)!
		recorded('preparation-tool-self-test', [tool, '--self-test'], '')!
		probe := os.exec([tool, '--assertion-probe'])
		assert probe.exit_code != 0 && probe.output.contains('assert false')
		os.write_file('build/android-maps/compound284/preparation-tool-assertion-probe.log', probe.output)!
		if os.args[1] == '--self-test' { return }
	}
	r := os.exec([tool, os.args[1]])
	os.write_file('build/android-maps/compound284/preparation-' + os.args[1] + '.log', r.output)!
	print(r.output)
	assert r.exit_code == 0
}
