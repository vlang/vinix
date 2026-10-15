// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import vmcore

fn dispatch() ! {
	args := os.args[1..]
	if args.len == 0 || args == ['--help'] {
		println('Usage: vinix-vm init CONFIG.json FRESH-STATE | start|status|pause|resume|reset|shutdown|stop|snapshot-recover STATE | guest-ping|guest-info|guest-osinfo|guest-network STATE | snapshot-create|snapshot-restore|snapshot-delete STATE NAME')
		return
	}
	if args.len == 3 && args[0] == 'init' {
		vmcore.initialise(os.read_file(args[1])!, args[2])!
		return
	}
	if args.len == 3 && args[0].starts_with('snapshot-') {
		vmcore.snapshot(args[0], args[1], args[2])!
		return
	}
	if args.len != 2 { return error('invalid arguments; use --help') }
	if args[0].starts_with('guest-') {
		println(vmcore.guest(args[0], args[1])!)
		return
	}
	if args[0] == 'snapshot-recover' {
		vmcore.snapshot_recover(args[1])!
		return
	}
	if args[0] == 'start' {
		os.signal_opt(.int, vmcore.request_stop)!
		os.signal_opt(.term, vmcore.request_stop)!
		exit(vmcore.start(args[1])!)
	}
	println(json2.encode(vmcore.control(args[0], args[1])!, prettify: true))
}

fn main() {
	dispatch() or {
		eprintln(err)
		exit(1)
	}
}
