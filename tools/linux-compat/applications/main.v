// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os

fn main() {
	if os.args.len > 2 || (os.args.len == 2 && os.args[1] !in ['--check', '--require-complete']) {
		eprintln('Usage: applications [--check|--require-complete]')
		exit(2)
	}
	root := os.real_path(os.dir(@FILE) + '/../../..')
	index := application_index(root) or { eprintln(err.msg()); exit(1) }
	if os.args.len == 2 && os.args[1] == '--require-complete' {
		if !index.complete_support_qualified {
			eprintln('Linux application support remains incomplete: failed/unsupported workloads or unqualified install/update/desktop lifecycle')
			exit(1)
		}
		return
	}
	for path, value in {
		'docs/linux-application-coverage.json': json2.encode(index, prettify: true) + '\n'
		'docs/linux-application-coverage.md': application_markdown(index)
	} {
		if os.args.len == 2 {
			if os.read_file(root + '/' + path) or { '' } != value { eprintln('Stale application index: ' + path); exit(1) }
		} else { os.write_file(root + '/' + path, value) or { eprintln(err.msg()); exit(1) } }
	}
	println('Linux application evidence index: PASS (' + index.applications.len.str() + ' verdicts)')
}
