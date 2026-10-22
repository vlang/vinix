// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual registration and keyboard code under both host modes.
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	work := os.join_path(root, 'build', 'registration-secrets-${os.getpid()}')
	os.mkdir_all('${work}/source')!
	println('Registration secret check artifacts: ${work}')
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', 'tools/accounts', 'tools/packages',
		'-o', '${work}/source.tar'])!
	workflowbuild.run('tar', ['-xf', '${work}/source.tar', '-C', '${work}/source'])!
	for name in ['input.v', 'keyboard_events.v', 'registration.v', 'registration_store.v'] {
		os.cp('${root}/desktop/${name}', '${work}/source/desktop/${name}')!
	}
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or {
		if os.is_file('${root}/../ui2/v.mod') { '${root}/../ui2' } else { '${root}/third_party/ui2' }
	}
	app := '${work}/app'
	workflowbuild.stage('${work}/source', ui, app, false)!
	controls := '${app}/modules/ui2/ui/control_state.c.v'
	if os.is_file(controls) {
		os.write_file(controls, os.read_file(controls)!.replace('$else $if macos {',
			'$else $if macos && !ui2_headless ? {'))!
	}
	os.rm('${app}/main.v')!
	v := os.getenv_opt('V') or { 'v' }
	for name in ['registration_secret', 'registration'] {
		os.cp('${root}/desktop/tools/tests/${name}_test.v', '${app}/${name}_test.v')!
		workflowbuild.run(v, ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none',
			'-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'no_segfault_handler',
			'-path', '@vlib|${app}/modules|${work}/source|${work}/source/tools/accounts|${work}/source/tools/packages|@vmodules|${root}/third_party',
			'-o', '${app}/${name}.c', '${app}/${name}_test.v'])!
		mut source := os.read_file('${app}/${name}.c')!
		source = source.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')
		$if macos { source = source.replace('ptrdiff_t offset);', 'int64_t offset);') }
		os.write_file('${app}/${name}.c', source)!
		compiler := os.real_path(os.find_abs_path_of_executable(v)!)
		for sanitize in [false, true]! {
			mode := if sanitize { 'asan-ubsan' } else { 'normal' }
			mut flags := ['-w', if sanitize { '-O0' } else { '-O1' }, '-g', '-I', app]
			if sanitize {
				flags << ['-fsanitize=address,undefined', '-fno-sanitize-recover=all',
					'-fno-omit-frame-pointer']
			}
			$if macos { flags << ['-x', 'objective-c', '-framework', 'Cocoa', '-framework', 'QuartzCore'] }
			flags << '${app}/${name}.c'
			$if macos { flags << ['-x', 'none'] }
			flags << ['${app}/presenter.o', '${os.dir(compiler)}/vlib/os/execute_capture_nix.c',
				'-lpthread', '-lm', '-o', '${app}/${name}-${mode}']
			workflowbuild.run('clang', flags)!
			println('Running ${name} ${mode}')
			workflowbuild.run('${app}/${name}-${mode}', [])!
		}
		os.rm('${app}/${name}_test.v')!
	}
	println('PASS registration secrets: 6 focused + 7 legacy tests, normal and ASan/UBSan')
}
