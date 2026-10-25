// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze unrelated desktop sources so concurrent edits cannot affect setup checks.
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	v := os.real_path(os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!)
	// A delegated `v run` restores its caller environment. Restore the selected
	// compiler's root too, so child builds use its adjacent pinned vlib.
	os.setenv('VEXE', v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', v, true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	work := os.join_path(os.temp_dir(), 'vinix-app-selection-${os.getpid()}')
	defer { if os.getenv('VINIX_SETUP_KEEP') != '1' { os.rmdir_all(work) or {} } }
	os.mkdir_all('${work}/source')!
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', '-o', '${work}/source.tar'])!
	workflowbuild.run('tar', ['-xf', '${work}/source.tar', '-C', '${work}/source'])!
	for name in ['main.v', 'app_selection.v', 'app_selection_release.v', 'app_selection_migration.v', 'app_selection_catalogue.v', 'app_selection_runtime.v', 'app_selection_download.v', 'session_hub.v',
		'software_app.v', 'software_release.v',
		'app_icon.v', 'font_data.v', 'app.v', 'wine_app.v', 'zed_app.v', 'session_paste.v'] {
		os.cp('${root}/desktop/${name}', '${work}/source/desktop/${name}')!
	}
	os.cp(root + '/desktop/packagecore/release.c.v', work + '/source/desktop/packagecore/release.c.v')!
	os.cp(root + '/desktop/tools/test-app-selection.v', work + '/source/desktop/tools/test-app-selection.v')!
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
		tests = ['app_selection', 'app_selection_release', 'app_selection_migration', 'app_selection_release_routing', 'app_icon', 'app_selection_i18n', 'i18n_apps', 'registration']
	}
	if os.getenv('VINIX_SETUP_PRODUCTION') == '1' && (tests.len != 1 || tests[0] != 'app_selection_release_routing') {
		panic('production checks require the explicit app_selection_release_routing suite; historical suites use assertions')
	}
	if 'app_selection_migration' in tests || 'app_selection_release_routing' in tests {
		os.mkdir_all(work + '/bin')!
		workflowbuild.run(v, ['-backend', 'c', '-o', work + '/bin/pkg', root + '/desktop/tools/tests/fixtures/setup-pkg/main.v'])!
		// Use and retain the same C backend as the target broker.
		workflowbuild.run(v, ['-backend', 'c', '-keepc', '-no-skip-unused', '-gc', 'none', '-manualfree', '-enable-globals', '-path', '@vlib|' + root + '|@vmodules',
			'-o', work + '/session-broker', root + '/desktop/services/session/main.v'])!
		os.setenv('PATH', work + '/bin:' + os.getenv('PATH'), true)
		os.setenv('VINIX_SETUP_TOOL_LOG', work + '/tool.log', true)
		os.setenv('VINIX_SETUP_BROKER', work + '/session-broker', true)
	}
	for name in tests {
		os.cp('${root}/desktop/tools/tests/${name}_test.v', '${work}/source/desktop/tools/tests/${name}_test.v')!
		os.cp('${root}/desktop/tools/tests/${name}_test.v', '${app}/${name}_test.v')!
		mut args := ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none', '-manualfree',
			'-enable-globals', '-d', 'ui2_headless', '-d', 'no_segfault_handler', '-path',
			'@vlib|${app}/modules|@vmodules|${work}/source|${root}|${root}/tools/accounts|${root}/third_party', '${app}/${name}_test.v']
		if os.getenv('VINIX_SETUP_PRODUCTION') == '1' { args.insert(0, '-prod') }
		setup_test(v, args, app, name)!
		os.rm('${app}/${name}_test.v')!
	}
	println('Setup checks PASS: ${tests.len} suites')
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
	if os.getenv('VINIX_SETUP_SANITIZE') == '1' {
		flags << ['-fsanitize=address,undefined', '-fno-sanitize-recover=all', '-fno-omit-frame-pointer']
	}
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
	if name in ['app_selection_migration', 'app_selection_release_routing'] && os.getenv('VINIX_SETUP_KEEP') == '1' {
		stem := if name == 'app_selection_migration' { 'migration' } else { 'release-routing' }
		os.cp('${work}/test.c', '${work}/${stem}.c')!
		os.cp('${work}/test', '${work}/${stem}')!
	}
	println('PASS ${name}')
}
