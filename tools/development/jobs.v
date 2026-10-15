// SPDX-License-Identifier: GPL-2.0-or-later
module main

import jobcore
import json2
import os
import time

fn dispatch() ! {
	args := os.args[1..]
	if args.len == 0 || args == ['--help'] {
		println('Usage: vinix-jobs init PLAN.json FRESH-STATE | run-due|watch|status|service-unit STATE | acknowledge-interrupted STATE JOB')
		return
	}
	if args.len == 3 && args[0] == 'init' {
		jobcore.initialise(os.read_file(args[1])!, args[2])!
		return
	}
	if args.len == 3 && args[0] == 'acknowledge-interrupted' {
		jobcore.acknowledge(args[1], args[2])!
		return
	}
	if args.len != 2 { return error('invalid arguments; use --help') }
	os.signal_opt(.int, jobcore.signal_stop)!
	os.signal_opt(.term, jobcore.signal_stop)!
	match args[0] {
		'watch' { jobcore.watch(args[1])! }
		'status' { println(json2.encode(jobcore.inspect(args[1])!, prettify: true)) }
		'service-unit' { print(jobcore.service_unit(args[1])!) }
		'run-due' {
			state := jobcore.run_due(args[1], time.now().unix())!
			if state.jobs.values().any(it.in_flight || it.exit_code != 0) { exit(1) }
		}
		else { return error('unknown job action') }
	}
}

fn main() {
	dispatch() or {
		eprintln(err)
		exit(1)
	}
}
