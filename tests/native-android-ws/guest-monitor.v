// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve an unresponsive owned guest's RAM without terminating or relaunching.
module main

import json2
import qmpclient
import os
import time

fn main() {
	if os.args.len != 4 || os.args[2] !in ['status', 'pause'] {
		panic('usage: guest-monitor OWNED_VM_ROOT status|pause FRESH_EXTERNAL_REPORT')
	}
	root, report := os.abs_path(os.args[1]), os.abs_path(os.args[3])
	if os.exists(report) || os.is_link(report) || report.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external report required')
	}
	pid := os.read_file(root + '/qemu.pid')!.trim_space().int()
	if pid <= 1 { panic('valid owned QEMU pid required') }
	identity := os.exec(['/bin/ps', '-p', pid.str(), '-o', 'command='])
	if identity.exit_code != 0 || !identity.output.contains('qemu-system-aarch64 ')
		|| !identity.output.contains(' -qmp unix:' + root + '/qmp.sock,')
		|| !identity.output.contains(' -pidfile ' + root + '/qemu.pid') {
		panic('owned QEMU command line differs')
	}
	mut monitor := qmpclient.connect_checked(root + '/qmp.sock', time.sys_mono_now() + u64(5 * time.second), unsafe { nil })!
	defer { monitor.close() }
	before := monitor.request('query-status', map[string]json2.Any{})!
	if os.args[2] == 'pause' { monitor.command('stop', map[string]json2.Any{})! }
	after := monitor.request('query-status', map[string]json2.Any{})!
	if os.args[2] == 'pause' && after.as_map()['status']!.str() != 'paused' {
		panic('guest did not acknowledge pause')
	}
	os.write_file(report, json2.encode({
		'pid': json2.Any(pid), 'command': json2.Any(identity.output.trim_space()),
		'action': json2.Any(os.args[2]), 'before': before, 'after': after
	}, prettify: true))!
	println('OWNED-GUEST-MONITOR-PASS action=' + os.args[2] + ' pid=' + pid.str())
}
