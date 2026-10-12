// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import crypto.sha256
import hosttest
import json2
import os
import sourcecommand

fn invoke(command []string) !sourcecommand.Output {
	return sourcecommand.capture(command, os.environ(), 30, 4 * 1024 * 1024, unsafe { nil })!
}

fn cases(work string) ! {
	os.mkdir(work)!
	tool := os.getenv('VINIX_CAMPAIGN_NATIVE_TOOL')
	for mode in ['success', 'failure', 'missing', 'duplicate'] {
		state := work + '/' + mode
		os.mkdir(state)!
		command := [os.executable(), '--emit', mode]
		hosttest.write_json(state + '/run.json', {
			'run_command':     json2.Any(command.map(json2.Any(it)))
			'run_environment': json2.Any({
				'VINIX_CAMPAIGN_CHILD_VALUE': json2.Any('kept environment')
			})
			'untouched':       json2.Any('retained field')
		})!
		result := invoke([tool, if mode == 'failure' { 'core-recorded' } else { 'core-supplement' },
			state + '/origin', '--state-dir', state])!
		assert result.status == if mode == 'success' {
			0
		} else if mode == 'failure' {
			7
		} else {
			1
		}, result.str()
		manifest := campaignhost.read_json(state + '/run.json')!
		assert manifest['exit_code']!.int() == result.status
		assert manifest['untouched']!.str() == 'retained field'
		bytes := os.read_bytes(state + '/serial.log')!
		assert manifest['serial_sha256']!.str() == sha256.sum(bytes).hex()
		assert bytes.bytestr().contains('kept environment\n') && bytes.bytestr().contains('child stderr\n')
		assert manifest['run_command']!.as_array().map(it.str()) == command
		assert manifest['finished_utc']!.str().ends_with('+00:00')
	}
	counts := campaignhost.allocation_report('a.v:1:2 allocation (string)\na.v:99:4 allocation (string)\nb.v:2:3 array\n.v:1:2 ignored\na.v:1:2 \nbad :1:2 ignored\naarch64: 7 source files, 3 allocation sites\nx86_64: compiler failed\nNEW: a.v: 2, allowed 1\n'.bytes())
	assert counts.counts == {
		'a.v allocation (string)': 2
		'b.v array':               1
	}
	assert counts.architectures.len == 2 && counts.warnings.len == 1
	deltas := campaignhost.allocation_deltas({
		'a': 3
		'b': 1
	}, {
		'a': 2
		'c': 4
	})
	assert deltas['a']!.int() == -1 && deltas['b']!.int() == -1 && deltas['c']!.int() == 4
	assert campaignhost.native_command(['python3', '/private/tree/tests/qemu-core/run_vm.py', '--arch',
		'amd64'])! == ['__native_core_harness__', '/private/tree', 'max', '--arch', 'amd64']
	assert campaignhost.native_command(['python3', '/private/tree/core-x86_64-four-level/run_vm.py'])![2] == 'max,-la57'
	campaignhost.native_command(['python3', '/arbitrary/program.py']) or {
		assert err.msg().contains('needs a native replacement')
		println('RECORDED CORE / actual children / full exit logs and hashes / supplementary verdicts / exact allocation-site parser / retired harness admission: PASS')
		return
	}
	return error('unknown interpreter command was admitted')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--emit' {
		println(os.getenv('VINIX_CAMPAIGN_CHILD_VALUE'))
		flush_stdout()
		eprintln('child stderr')
		flush_stderr()
		if os.args[2] !in ['missing', 'failure'] { println('PAGETABLE CHECK: PASS') }
		if os.args[2] == 'duplicate' { println('PAGETABLE CHECK: PASS') }
		exit(if os.args[2] == 'failure' { 7 } else { 0 })
	}
	if os.args.len != 2 {
		eprintln('usage: test-campaign NEW_STATE')
		exit(2)
	}
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
