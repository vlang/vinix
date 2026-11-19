// SPDX-License-Identifier: GPL-2.0-or-later
// Build gpucheck as a static program for an AArch64 Vinix machine.
//
//   v run tools/gpucheck/build.v OUTPUT [SOURCE]
//
// SOURCE replaces tools/gpucheck/gpucheck.v, for negative controls.
//
// The C compiler needs the musl sysroot of the userland build
// (VINIX_AARCH64_SYSROOT, by default build-aarch64-userland/sysroot), as
// tools/hwcheck/build does. gpucheck is for the M1, so only AArch64 is built.
// V's segfault handler is a prebuilt object for the host, so it is left out.
import os

fn main() {
	if os.args.len !in [2, 3] {
		eprintln('usage: v run tools/gpucheck/build.v OUTPUT [SOURCE]')
		exit(2)
	}
	output := os.abs_path(os.args[1])
	repo := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	source := if os.args.len == 3 { os.abs_path(os.args[2]) } else { '${repo}/tools/gpucheck/gpucheck.v' }
	vexe := os.getenv_opt('VEXE') or { 'v' }
	sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { '${repo}/build-aarch64-userland/sysroot' }
	work := os.join_path(os.temp_dir(), 'vinix-gpucheck-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	for command in [
		[vexe, '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-d', 'no_backtrace', '-d',
			'no_segfault_handler', '-o', '${work}/gpucheck.c', source],
		[os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=${sysroot}',
			'-static', '-O1', '-w', '-fno-stack-protector', '-L${sysroot}/lib', '-fuse-ld=lld',
			'-o', output, '${work}/gpucheck.c', '-lm', '-lpthread'],
	] {
		result := os.exec(command)
		if result.exit_code != 0 {
			eprintln('${command.join(' ')}:\n${result.output}')
			exit(1)
		}
	}
	println(output)
}
