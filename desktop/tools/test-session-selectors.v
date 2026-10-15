// SPDX-License-Identifier: GPL-2.0-or-later
// Run with V set to the compiler executable. The memory fixture is isolated
// from the unrelated main programs in tools/tests and needs no UI backend.
module main

import os

fn selector_check_run(compiler string, arguments []string) ! {
	mut process := os.new_process(compiler)
	defer { process.close() }
	process.set_args(arguments)
	process.run()
	process.wait()
	if process.code != 0 { return error('session selector check failed') }
}

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	compiler := os.getenv_opt('V') or { 'v' }
	flags := ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none', '-manualfree', '-path',
		'@vlib|${root}|@vmodules', '-stats']
	mut unit_arguments := flags.clone()
	unit_arguments << '${root}/desktop/sessioncore/selectors_test.v'
	selector_check_run(compiler, unit_arguments)!
	work := os.join_path(os.temp_dir(), 'vinix-session-selectors-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all('${work}/tools/tests')!
	os.write_file('${work}/v.mod', "Module { name: 'session_selector_checks' }")!
	os.cp('${root}/desktop/tools/tests/heap_tracker.h', '${work}/tools/tests/heap_tracker.h')!
	os.cp('${root}/desktop/tools/tests/session_selectors_memory_test.v', '${work}/selectors_memory_test.v')!
	mut memory_arguments := flags.clone()
	memory_arguments << ['-d', 'track_heap', '${work}/selectors_memory_test.v']
	selector_check_run(compiler, memory_arguments)!
}
