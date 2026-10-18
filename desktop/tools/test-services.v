// SPDX-License-Identifier: GPL-2.0-or-later
// Native service integration and memory checks, independent of ui2 and QEMU.
module main

import os

fn run(program string, args []string) ! {
	mut process := os.new_process(program)
	defer { process.close() }
	process.set_args(args)
	process.run()
	process.wait()
	if process.code != 0 { return error('${program} failed (${process.code})') }
}

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	os.chdir(root)!
	compiler := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	output := root + '/build/session-runtime'
	run(compiler, ['-nocache', 'run', root + '/desktop/tools/build-services.v', '--arch=native',
		'--output=' + output])!
	os.setenv('VINIX_SESSION_BIN_DIR', output, true)
	for test in ['authorization', 'migration', 'lifecycle', 'poll_memory'] {
		binary := output + '/check-' + test
		mut flags := ['-new-compiler', '-cc', 'clang', '-gc', 'none', '-manualfree', '-enable-globals',
			'-d', 'no_segfault_handler', '-path', '@vlib|@vmodules|' + root, '-stats']
		if test == 'poll_memory' { flags << ['-d', 'track_heap'] }
		run(compiler, [...flags, '-o', binary, root + '/desktop/sessiondaemon/' + test + '_test.v'])!
	}
	// Exercise the compositor's real startup wrapper without a UI dependency.
	client := output + '/control-start'
	os.mkdir_all(client)!
	os.write_file(client + '/v.mod', "Module { name: 'session_control_start_checks' }")!
	os.cp(root + '/desktop/session_service.c.v', client + '/session_service.c.v')!
	os.cp(root + '/desktop/tools/tests/session_control_start_test.v', client + '/control_start_test.v')!
	run(compiler, ['-new-compiler', '-cc', 'clang', '-gc', 'none', '-manualfree', '-enable-globals',
		'-d', 'no_segfault_handler', '-path', '@vlib|@vmodules|' + root, '-stats', '-o',
		output + '/check-control-start', client + '/control_start_test.v'])!
	println('Session services: authorization, migration, persistence, restart, crash cleanup and allocation checks passed')
}
