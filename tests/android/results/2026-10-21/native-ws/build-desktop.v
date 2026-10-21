// SPDX-License-Identifier: GPL-2.0-or-later
// Preserved macOS/HVF investigation helper; run from the repository root.
import os
import workflowbuild

fn main() {
	root := os.getwd()
	appdir := root + '/build/android-native-ws/desktop'
	if os.args.len == 1 {
		workflowbuild.stage(root, root + '/../ui2', appdir, true)!
		workflowbuild.run('v', ['-new-compiler', '-no-memory-limit', '-os', 'linux', '-arch', 'arm64',
			'-gc', 'none', '-manualfree', '-enable-globals', '-prod', '-d', 'glibc', '-d',
			'ui2_headless', '-path',
			'@vlib|${appdir}/modules|@vmodules|${root}|${root}/third_party|${root}/tools/accounts',
			'-o', appdir + '/desktop.c', appdir])!
		generated := os.read_file(appdir + '/desktop.c')!
		os.write_file(appdir + '/desktop.c', generated.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1'))!
	}
	sysroot := root + '/build-aarch64-userland/staging'
	mut versions := os.ls(sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
	llvm := '/opt/homebrew/opt/llvm/bin'
	workflowbuild.run(llvm + '/clang', ['--target=aarch64-linux-musl', '-static', '-nostdinc',
		'-nostdlib', '-isystem', root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include',
		'-isystem', sysroot + '/usr/include', '-I', appdir, '-D_GNU_SOURCE', '-include',
		'/Users/alex/code/v/vlib/builtin/segfault_handler_nix.h', '-O2', '-fno-stack-protector',
		'-w', sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o', gcc + '/crtbeginT.o',
		appdir + '/desktop.c', appdir + '/execinfo.c', appdir + '/presenter.c',
		'-L' + sysroot + '/usr/lib', '-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm', gcc + '/crtend.o',
		sysroot + '/usr/lib/crtn.o', '-fuse-ld=lld', '-B' + llvm, '-o',
		root + '/build/android-native-ws/vinix-desktop'])!
}
