// SPDX-License-Identifier: GPL-2.0-or-later
// Cross-build a frozen desktop and the native Emacs launcher without sharing app caches.
module main

import os
import workflowbuild

fn compile_arm(v string, source string, destination string, module_path string, includes string,
	extras []string) ! {
	root := os.real_path('.')
	generated := destination + '.c'
	workflowbuild.run(v, ['-new-compiler', '-no-memory-limit', '-os', 'linux', '-arch', 'arm64',
		'-gc', 'none', '-manualfree', '-enable-globals', '-prod', '-d', 'glibc', '-d',
		'no_segfault_handler', '-d', 'ui2_headless', '-path', module_path, '-o', generated, source])!
	text := os.read_file(generated)!
	os.write_file(generated, text.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1'))!
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { '${root}/build-aarch64-userland/staging' }
	mut versions := os.ls('${sdk}/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := '${sdk}/usr/lib/gcc/aarch64-alpine-linux-musl/${versions.last()}'
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	workflowbuild.run('${llvm}/clang', ['--target=aarch64-linux-musl', '-static', '-nostdinc',
		'-nostdlib', '-isystem', '${root}/build-support/aarch64-cc-shim', '-isystem', '${gcc}/include',
		'-isystem', '${sdk}/usr/include', '-I', includes, '-D_GNU_SOURCE', '-O1', '-fno-stack-protector',
		'-w', '${sdk}/usr/lib/crt1.o', '${sdk}/usr/lib/crti.o', '${gcc}/crtbeginT.o', generated,
		...extras, '-L${sdk}/usr/lib', '-L${gcc}', '-lgcc_eh', '-lc', '-lgcc', '-lm', '-lpthread',
		'${gcc}/crtend.o', '${sdk}/usr/lib/crtn.o', '-fuse-ld=lld', '-B${llvm}', '-o', destination])!
	workflowbuild.run('${llvm}/llvm-strip', [destination])!
}

fn main() {
	root := os.real_path('.')
	work := '${root}/build/emacs/' + if '--check' in os.args { 'check' } else { 'build' }
	os.mkdir_all('${work}/source')!
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', 'tools/accounts', 'tools/packages',
		'-o', '${work}/source.tar'])!
	workflowbuild.run('tar', ['-xf', '${work}/source.tar', '-C', '${work}/source'])!
	for name in ['app.v', 'wine_app.v', 'emacs_app.v', 'taskbar_pin.v', 'start_menu.v'] {
		os.cp('${root}/desktop/${name}', '${work}/source/desktop/${name}')!
	}
	os.cp_all('${root}/desktop/translations', '${work}/source/desktop/translations', true)!
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or { '${root}/../ui2' }
	app := '${work}/app'
	workflowbuild.stage('${work}/source', ui, app, '--check' !in os.args)!
	v := os.getenv_opt('V') or { 'v' }
	module_path := '@vlib|${app}/modules|@vmodules|${work}/source|${root}|${root}/third_party'
	if '--check' in os.args {
		controls := '${app}/modules/ui2/ui/control_state.c.v'
		if os.is_file(controls) {
			os.write_file(controls, os.read_file(controls)!.replace('$else $if macos {',
				'$else $if macos && !ui2_headless ? {'))!
		}
		os.rm('${app}/main.v')!
		for name in ['utilities', 'start_menu_paging', 'taskbar_pinning'] {
			if name == 'utilities' {
				os.setenv('VTEST_ONLY_FN', 'test_available_utility_applications_and_shortcut_layouts', true)
			} else { os.unsetenv('VTEST_ONLY_FN') }
			path := '${app}/${name}_test.v'
			os.cp('${root}/desktop/tools/tests/${name}_test.v', path)!
			workflowbuild.test(v, ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none',
				'-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'no_segfault_handler',
				'-path', module_path, path], app, name)!
			os.rm(path)!
		}
		return
	}
	if '--clients-only' !in os.args {
		compile_arm(v, app, '${work}/vinix-desktop', module_path, app,
			['${app}/execinfo.c', '${app}/presenter.c'])!
	}
	staging := '${root}/build/emacs/staging/usr/bin'
	os.mkdir_all(staging)!
	compile_arm(v, '${root}/build-support/emacs/run.v', '${staging}/run-emacs',
		'@vlib|@vmodules|${root}|${root}/build-support/emacs', app, ['${app}/execinfo.c'])!
	os.symlink('vinix-desktop', '${staging}/vinix-emacs') or {}
	compile_arm(v, '${root}/tests/emacs/guest.v', '${work}/init',
		'@vlib|@vmodules|${root}', app, ['${app}/execinfo.c'])!
	println('Built ${work}/vinix-desktop and ${staging}/run-emacs')
}
