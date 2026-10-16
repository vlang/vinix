// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import hosttest

fn main() {
	if os.args.len != 3 {
		eprintln('Usage: generate_sched_mm.v ORIGINAL/include/linux/sched/mm.h OUTPUT/linux/sched/mm.h')
		exit(2)
	}
	provenance := hosttest.generate_sched_mm(os.args[1], os.args[2]) or {
		eprintln('Linux scheduler/MM declaration generation failed: ' + err.msg())
		exit(1)
	}
	println(json2.encode(provenance, prettify: true, indent_string: '  '))
}
