// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import corevm
import hosttest
import json2
import os
import strconv

fn run() int {
	probe := os.args.len > 1 && os.args[1] == '--probe'
	args := if probe { os.args[2..] } else { os.args[1..] }
	if args.len < 7 || args[5] != '--' { eprintln('usage: recorded-console [--probe] LOG RESULT CWD SECONDS PASS -- COMMAND ...'); return 2 }
	seconds := strconv.atof64(args[3]) or { eprintln(err); return 2 }
	guard := corevm.own_commands()
	defer { guard.close() }
	result := corevm.capture_policy(args[6..], os.environ(), args[2], seconds, false, false, corevm.CapturePolicy{
		pass: args[4]
		failures: if probe { ['KERNEL PANIC', 'QEMU CORE FAIL'] } else { ['KERNEL PANIC'] }
		pass_lookback: 4096
		failure_lookback: 16384
		settle: 0
		log: args[0]
		complete_lines: probe
		alternate_prefix: if probe { 'SOCKET-OPS-DONE result=' } else { '' }
		boot_disk: if probe { os.getenv('VINIX_BOOT_DISK') } else { '' }
		drain_on_close: if probe { 5 } else { 0 }
		terminate_grace: if probe { 3 } else { 2 }
	}) or { eprintln(err); return if err.msg() == 'Core guest run interrupted' { err.code() } else { 1 } }
	hosttest.write_json(args[1], {'has_status': json2.Any(result.has_status), 'status': json2.Any(result.status), 'forced': json2.Any(result.forced), 'finished': json2.Any(result.finished), 'actual_qemu_ps': json2.Any(result.actual_qemu_ps.map(json2.Any(it)))}) or { eprintln(err); return 1 }
	return 0
}

fn main() { exit(run()) }
