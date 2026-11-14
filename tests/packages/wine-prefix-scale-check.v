// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import json2
import os
import plainiso

fn run() ! {
	if os.args.len != 4 { return error('usage: CHECK FRESH_WORK X86_KERNEL SCALE_GUEST') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('fresh scale guest directory required') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, 'x86_64', '')!
	os.mkdir_all(work)!
	outcome := hwhost.run_scenario(hwhost.Host{...host, root: plainiso.prepare(root, work)!},
		hwhost.Scenario{name: 'wine-migration-scale', arches: ['x86_64'], ending: .running,
			required: ['WINE MIGRATION SCALE PASS rows=741', 'HWTEST PASS wine-migration-scale'],
			forbidden: ['HWTEST FAIL', 'Kernel panic']},
		hwhost.Run{kernel: os.args[2], guest: os.args[3], state: work + '/boot', timeout: 120, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	if !outcome.passed || outcome.interrupted { return error('migration scale guest failed: ' + outcome.reason) }
	println('WINE MIGRATION SCALE GUEST PASS')
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
