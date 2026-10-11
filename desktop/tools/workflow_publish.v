// SPDX-License-Identifier: GPL-2.0-or-later
// Build committed sources and publish through the existing QEMU app store.
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	for app in os.args[1..] {
		if app !in ['files', 'activity', 'settings'] { eprintln('unsupported app: ${app}'); exit(2) }
	}
	if os.args.len < 2 { eprintln('usage: workflow_publish.v files|activity|settings'); exit(2) }
	work := os.join_path(os.temp_dir(), 'vinix-app-publish-${os.getpid()}')
	os.mkdir_all('${work}/source') or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', 'build-support/aarch64-cc-shim', '-o', '${work}/source.tar']) or { panic(err) }
	workflowbuild.run('tar', ['-xf', '${work}/source.tar', '-C', '${work}/source']) or { panic(err) }
	source := '${work}/source'
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or { if os.is_file('${root}/../ui2/v.mod') { '${root}/../ui2' } else { '${root}/third_party/ui2' } }
	appdir := '${work}/app'
	workflowbuild.stage(source, ui, appdir, true) or { eprintln(err); exit(1) }
	v := os.getenv_opt('V') or { '/Users/alex/code/v/v' }
	workflowbuild.run(v, ['-new-compiler', '-no-memory-limit', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-manualfree', '-enable-globals', '-prod', '-d', 'glibc', '-d', 'ui2_headless', '-path', '@vlib|${appdir}/modules|@vmodules|${source}|${root}/third_party', '-o', '${appdir}/desktop.c', appdir]) or { eprintln(err); exit(1) }
	generated := os.read_file('${appdir}/desktop.c') or { panic(err) }
	os.write_file('${appdir}/desktop.c', generated.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')) or { panic(err) }
	sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { '${root}/build-aarch64-userland/staging' }
	versions := os.ls('${sysroot}/usr/lib/gcc/aarch64-alpine-linux-musl') or { panic(err) }
	mut ordered := versions.clone()
	ordered.sort()
	if ordered.len == 0 { panic('GCC runtime missing') }
	gcc := '${sysroot}/usr/lib/gcc/aarch64-alpine-linux-musl/${ordered.last()}'
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	binary := '${work}/vinix-desktop'
	workflowbuild.run('${llvm}/clang', ['--target=aarch64-linux-musl', '-static', '-nostdinc', '-nostdlib', '-isystem', '${source}/build-support/aarch64-cc-shim', '-isystem', '${gcc}/include', '-isystem', '${sysroot}/usr/include', '-I', appdir, '-D_GNU_SOURCE', '-O2', '-fno-stack-protector', '-w', '${sysroot}/usr/lib/crt1.o', '${sysroot}/usr/lib/crti.o', '${gcc}/crtbeginT.o', '${appdir}/desktop.c', '${appdir}/execinfo.c', '${appdir}/presenter.c', '-L${sysroot}/usr/lib', '-L${gcc}', '-lgcc_eh', '-lc', '-lgcc', '-lm', '${gcc}/crtend.o', '${sysroot}/usr/lib/crtn.o', '-fuse-ld=lld', '-B${llvm}', '-o', binary]) or { eprintln(err); exit(1) }
	workflowbuild.run('${llvm}/llvm-strip', [binary]) or { panic(err) }
	for app in os.args[1..] {
		dest := '${root}/build-aarch64-desktop-apps/${app}-live'
		os.mkdir_all(dest) or { panic(err) }
		os.cp(binary, '${dest}/.vinix-${app}.${os.getpid()}') or { panic(err) }
		os.chmod('${dest}/.vinix-${app}.${os.getpid()}', 0o755) or { panic(err) }
		os.rename('${dest}/.vinix-${app}.${os.getpid()}', '${dest}/vinix-${app}') or { panic(err) }
		result := os.exec(['cksum', '${dest}/vinix-${app}']) or { panic(err) }
		fields := result.output.split(' ')
		if result.exit_code != 0 || fields.len < 2 { panic('checksum failed') }
		os.write_file('${dest}/.version.${os.getpid()}', '${fields[0]} ${fields[1]}\n') or { panic(err) }
		os.rename('${dest}/.version.${os.getpid()}', '${dest}/version') or { panic(err) }
		println('Published ${app}: ${dest}/vinix-${app}')
	}
}
