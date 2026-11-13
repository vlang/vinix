// SPDX-License-Identifier: GPL-2.0-or-later
// Build a tiny input-test ISO with the release's native musl SDK.
import os

fn checked(args []string) ! {
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..])
	child.run()
	child.wait()
	if child.code != 0 { return error('${args[0]} exited with ${child.code}') }
}

fn build() ! {
	if os.args.len != 4 {
		return error('Usage: v run tests/default-qemu/build.v RELEASE.iso KERNEL NEW-DIR')
	}
	release := os.abs_path(os.args[1])
	kernel := os.abs_path(os.args[2])
	work := os.abs_path(os.args[3])
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	if os.exists(work) { return error('output directory must be new: ${work}') }
	os.mkdir_all(work + '/sysroot')!
	os.mkdir_all(work + '/root/sbin')!
	checked(['xorriso', '-osirrox', 'on', '-indev', release, '-extract', '/boot/initramfs.tar.gz',
		work + '/release.tar.gz'])!
	checked(['tar', '-xzf', work + '/release.tar.gz', '-C', work + '/sysroot', './usr/include',
		'./usr/lib', './lib'])!
	configured := os.getenv('V')
	v := if configured != '' { configured } else { os.find_abs_path_of_executable('v')! }
	checked([v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-o', work + '/guest.c',
		root + '/tests/default-qemu/entry.v'])!
	gccroot := work + '/sysroot/usr/lib/gcc/x86_64-alpine-linux-musl'
	versions := os.ls(gccroot)!.sorted()
	if versions.len == 0 { return error('release has no native musl SDK') }
	checked(['clang', '--target=x86_64-linux-musl', '--sysroot=' + work + '/sysroot',
		'--gcc-install-dir=' + gccroot + '/' + versions.last(), '-static', '-fuse-ld=lld', '-O2',
		work + '/guest.c', '-o', work + '/root/sbin/init'])!
	checked(['tar', '--format=ustar', '-cf', work + '/initramfs.tar', '-C', work + '/root', '.'])!
	os.setenv('VINIX_AMD64_KERNEL', kernel, true)
	os.setenv('VINIX_AMD64_INITRAMFS', work + '/initramfs.tar', true)
	os.setenv('VINIX_AMD64_ISO_BUILD_DIR', work + '/iso-build', true)
	os.setenv('VINIX_AMD64_ISO', work + '/input-amd64.iso', true)
	checked([root + '/build-support/build-amd64-iso.sh'])!
	println('Input fixture: ${work}/input-amd64.iso')
}

fn main() {
	build() or {
		eprintln(err)
		exit(1)
	}
}
