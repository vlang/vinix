// SPDX-License-Identifier: GPL-2.0-or-later
// Check account homes and legacy registration against an isolated desktop.
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	work := os.join_path(os.temp_dir(), 'vinix-session-home-${os.getpid()}')
	os.mkdir_all('${work}/source')!
	defer {
		if os.getenv('VINIX_SESSION_HOME_KEEP') != '1' { os.rmdir_all(work) or {} }
	}
	println('Session home check artifacts: ${work}')
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', 'tools/accounts', 'tools/packages',
		'-o', '${work}/source.tar'])!
	workflowbuild.run('tar', ['-xf', '${work}/source.tar', '-C', '${work}/source'])!
	for name in ['platform.c.v', 'main.v', 'terminal.v', 'registration.v', 'registration_store.v'] {
		os.cp('${root}/desktop/${name}', '${work}/source/desktop/${name}')!
	}
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or {
		if os.is_file('${root}/../ui2/v.mod') { '${root}/../ui2' } else { '${root}/third_party/ui2' }
	}
	app := '${work}/app'
	workflowbuild.stage('${work}/source', ui, app, false)!
	// Match the other host desktop checks when ui2 exposes its native macOS
	// control-state branch alongside the headless backend.
	controls := '${app}/modules/ui2/ui/control_state.c.v'
	if os.is_file(controls) {
		os.write_file(controls, os.read_file(controls)!.replace('$else $if macos {',
			'$else $if macos && !ui2_headless ? {'))!
	}
	os.rm('${app}/main.v')!
	v := os.getenv_opt('V') or { 'v' }
	for name in ['session_home', 'registration'] {
		os.cp('${root}/desktop/tools/tests/${name}_test.v', '${app}/${name}_test.v')!
		session_home_test(v, ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none',
			'-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'no_segfault_handler',
			'-path', '@vlib|${app}/modules|${work}/source|${work}/source/tools/accounts|${work}/source/tools/packages|@vmodules|${root}/third_party',
			'${app}/${name}_test.v'], app, name)!
		os.rm('${app}/${name}_test.v')!
	}
}

fn session_home_test(v string, args []string, work string, name string) ! {
	mut generate := args.clone()
	generate.insert(generate.len - 1, ['-o', '${work}/test.c'])
	workflowbuild.run(v, generate)!
	mut source := os.read_file('${work}/test.c')!
	source = source.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')
	$if macos { source = source.replace('ptrdiff_t offset);', 'int64_t offset);') }
	os.write_file('${work}/test.c', source)!
	compiler := os.real_path(os.find_abs_path_of_executable(v)!)
	mut flags := ['-w', '-O0', '-I', work]
	$if macos { flags << ['-x', 'objective-c', '-framework', 'Cocoa', '-framework', 'QuartzCore'] }
	flags << '${work}/test.c'
	$if macos { flags << ['-x', 'none'] }
	flags << ['${work}/presenter.o', '${os.dir(compiler)}/vlib/os/execute_capture_nix.c',
		'-lpthread', '-lm', '-o', '${work}/test']
	workflowbuild.run('clang', flags)!
	println('Running ${name}')
	workflowbuild.run('${work}/test', [])!
}
