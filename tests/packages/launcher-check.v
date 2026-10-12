// SPDX-License-Identifier: GPL-2.0-or-later
// Stage current desktop code with the existing V-only host fixture builder.
module main

import os
import desktop.tools.workflowbuild

fn check() ! {
	if os.args.len != 2 { return error('usage: launcher-check WORK_DIRECTORY') }
	repository := os.dir(os.dir(os.dir(@FILE)))
	work := os.args[1] + '/launcher-desktop'
	v := os.getenv_opt('V') or { 'v' }
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or {
		if os.is_file(repository + '/../ui2/v.mod') {
			repository + '/../ui2'
		} else {
			repository + '/third_party/ui2'
		}
	}
	workflowbuild.stage(repository, ui, work, false)!
	os.rm(work + '/main.v')!
	os.cp(repository + '/desktop/tools/tests/package_launcher_test.v', work + '/package_launcher_test.v')!
	os.cp(repository + '/desktop/tools/tests/heap_tracker.h', work + '/heap_tracker.h')!
	workflowbuild.test(v, ['-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless',
		'-d', 'no_segfault_handler',
		'-d', 'track_heap', '-path',
		'@vlib|' + work + '/modules|@vmodules|' + repository + '|' + repository + '/third_party',
		work + '/package_launcher_test.v'], work, 'package launchers')!
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
