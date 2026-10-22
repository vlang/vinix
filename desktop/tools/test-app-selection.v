// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze unrelated desktop sources so concurrent edits cannot affect setup checks.
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	v := os.getenv_opt('V') or { 'v' }
	work := os.join_path(os.temp_dir(), 'vinix-app-selection-${os.getpid()}')
	defer { if os.getenv('VINIX_SETUP_KEEP') != '1' { os.rmdir_all(work) or {} } }
	os.mkdir_all('${work}/source')!
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', '-o', '${work}/source.tar'])!
	workflowbuild.run('tar', ['-xf', '${work}/source.tar', '-C', '${work}/source'])!
	for name in ['main.v', 'app_selection.v', 'app_selection_release.v', 'app_selection_catalogue.v', 'app_selection_runtime.v',
		'software_app.v', 'software_release.v',
		'app_icon.v', 'font_data.v', 'app.v', 'wine_app.v', 'zed_app.v', 'session_paste.v'] {
		os.cp('${root}/desktop/${name}', '${work}/source/desktop/${name}')!
	}
	for directory in ['assets', 'translations'] {
		os.cp_all('${root}/desktop/${directory}', '${work}/source/desktop/${directory}', true)!
	}
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or { if os.is_file('${root}/../ui2/v.mod') {
		'${root}/../ui2'
	} else {
		'${root}/third_party/ui2'
	} }
	app := '${work}/app'
	println('Setup check artifacts: ${work}')
	workflowbuild.stage('${work}/source', ui, app, false)!
	// Some ui2 revisions leave native control-state branches active in headless
	// macOS builds. Guard only the staged dependency, leaving the checkout intact.
	controls := '${app}/modules/ui2/ui/control_state.c.v'
	if os.is_file(controls) {
		os.write_file(controls, os.read_file(controls)!.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {'))!
	}
	os.rm('${app}/main.v')!
	mut tests := os.args[1..].clone()
	if tests.len == 0 {
		tests = ['app_selection', 'app_selection_release', 'app_icon', 'app_selection_i18n', 'i18n_apps', 'registration']
	}
	for name in tests {
		os.cp('${root}/desktop/tools/tests/${name}_test.v', '${app}/${name}_test.v')!
		args := ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none', '-manualfree',
			'-enable-globals', '-d', 'ui2_headless', '-d', 'no_segfault_handler', '-path',
			'@vlib|${app}/modules|@vmodules|${root}|${root}/tools/accounts|${root}/third_party', '${app}/${name}_test.v']
		setup_test(v, args, app, name)!
		os.rm('${app}/${name}_test.v')!
	}
}

fn setup_test(v string, args []string, work string, name string) ! {
	mut generate := args.clone()
	generate.insert(generate.len - 1, ['-o', '${work}/test.c'])
	workflowbuild.run(v, generate)!
	mut source := os.read_file('${work}/test.c')!
	source = source.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')
	$if macos {
		source = source.replace('ptrdiff_t offset);', 'int64_t offset);')
	}
	os.write_file('${work}/test.c', source)!
	compiler := os.real_path(os.find_abs_path_of_executable(v)!)
	mut flags := ['-w', '-O0', '-I', work]
	$if macos {
		flags << ['-x', 'objective-c', '-framework', 'Cocoa', '-framework', 'QuartzCore']
	}
	flags << '${work}/test.c'
	$if macos {
		flags << ['-x', 'none']
	}
	flags << ['${work}/presenter.o', '${os.dir(compiler)}/vlib/os/execute_capture_nix.c', '-lpthread',
		'-lm', '-o', '${work}/test']
	workflowbuild.run('clang', flags)!
	println('Running ${name}')
	workflowbuild.run('${work}/test', [])!
}
