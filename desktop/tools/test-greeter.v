// SPDX-License-Identifier: GPL-2.0-or-later
// Build the real desktop login state and scene in the headless host backend.
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	work := os.join_path(os.temp_dir(), 'vinix-greeter-${os.getpid()}')
	defer { if os.getenv('VINIX_GREETER_KEEP') != '1' { os.rmdir_all(work) or {} } }
	println('Greeter check artifacts: ' + work)
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or { root + '/../ui2' }
	app := work + '/app'
	workflowbuild.stage(root, ui, app, false)!
	controls := app + '/modules/ui2/ui/control_state.c.v'
	if os.is_file(controls) {
		os.write_file(controls, os.read_file(controls)!.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {'))!
	}
	os.rm(app + '/main.v')!
	os.cp(root + '/desktop/tools/tests/greeter_test.v', app + '/greeter_test.v')!
	v := os.getenv_opt('V') or { 'v' }
	workflowbuild.run(v, ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none', '-manualfree',
		'-enable-globals', '-d', 'ui2_headless', '-d', 'no_segfault_handler', '-path',
		'@vlib|' + app + '/modules|' + root + '|' + root + '/tools/accounts|' + root + '/tools/packages|@vmodules|' + root + '/../../third_party',
		'-o', app + '/test.c', app + '/greeter_test.v'])!
	mut source := os.read_file(app + '/test.c')!
	$if macos { source = source.replace('ptrdiff_t offset);', 'int64_t offset);') }
	os.write_file(app + '/test.c', source)!
	compiler := os.real_path(os.find_abs_path_of_executable(v)!)
	mut flags := ['-w', '-O0', '-I', app]
	if os.getenv('VINIX_GREETER_SANITIZE') == '1' { flags << ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] }
	$if macos { flags << ['-x', 'objective-c', '-framework', 'Cocoa', '-framework', 'QuartzCore'] }
	flags << app + '/test.c'
	$if macos { flags << ['-x', 'none'] }
	flags << [app + '/presenter.o', os.dir(compiler) + '/vlib/os/execute_capture_nix.c', '-lpthread', '-lm', '-o', app + '/test']
	workflowbuild.run('clang', flags)!
	workflowbuild.run(app + '/test', [])!
}
