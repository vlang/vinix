// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module glvm

import agxhost
import crypto.sha256
import glhost
import hosttest
import json2
import os
import policyhost
import strconv

pub fn command(arguments []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	return checked(arguments) or {
		eprintln(err.msg())
		if err is glhost.ArgumentError { return 2 }
		if err is agxhost.NativeFailure && err.kind == 'KeyboardInterrupt' { return 130 }
		if err.msg() == 'Host test interrupted' { return 130 }
		if err.msg() == 'Native AGX guest interrupted' { return err.code() }
		return 1
	}
}

fn checked(arguments []string) !int {
	args := hosttest.parse_arguments(arguments, [
		hosttest.Option{'--kernel-dir', true, []string{}},
		hosttest.Option{'--state-dir', true, []string{}},
		hosttest.Option{'--timeout', true, []string{}},
	], 0,
		'usage: run-vm --kernel-dir DIRECTORY --state-dir NEW_DIRECTORY [--timeout SECONDS]',
		'Build native V and the exact Mesa runtime, then run the eight guest checks.') or { return glhost.argument_error(err.msg()) }
	for key in ['--kernel-dir', '--state-dir'] {
		if key !in args.options { return glhost.argument_error('missing required ' + key) }
	}
	seconds := strconv.atoi(args.options['--timeout'] or { '1800' }) or { return glhost.argument_error('invalid integer for --timeout') }
	state := hosttest.module_resolve(args.options['--state-dir'])!
	os.mkdir_all(os.dir(state))!
	os.mkdir(state)!
	kernel := hosttest.module_resolve(args.options['--kernel-dir'])!
	prepare(state)!
	harness := state + '/harness'
	os.mkdir_all(harness + '/scripts')!
	os.symlink(kernel, harness + '/kernel')!
	marker := 'SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"'
	text := os.read_file(glhost.root() + '/scripts/run-aarch64.sh')!
	if !text.contains(marker) { return error('QEMU runner root declaration changed') }
	os.write_file(harness + '/scripts/run-aarch64.sh', text.replace_once(marker, 'SCRIPT_DIR=' + hosttest.shell_quote(glhost.root())))!
	os.chmod(harness + '/scripts/run-aarch64.sh', 0o755)!
	for key, value in {
		'VINIX_KERNEL_DIR':       kernel
		'VINIX_ASAHI_STAGING':    state + '/native'
		'VINIX_INITRAMFS':        state + '/initramfs.tar'
		'VINIX_QEMU_HOST_SOURCE': '0'
		'VINIX_QEMU_AUDIO':       'off'
	} {
		os.setenv(key, value, true)
	}
	mut out := agxhost.Transcript{ inherit: true, host_arch: policyhost.caller_arch() }
	status := out.vm_native_test(harness, seconds.str())!
	os.write_file(state + '/validation.json', json2.encode({
		'guest_exit_status':               json2.Any(status)
		'original_implementation_lines':   json2.Any(557)
		'retained_implementation_C_lines': json2.Any(0)
		'kernel_sha256':                   json2.Any(sha256.sum(os.read_bytes(kernel + '/bin/vinix')!).hex())
		'native_binary_sha256':            json2.Any(sha256.sum(os.read_bytes(state + '/native/usr/bin/gl-triangle-agx')!).hex())
		'runtime_archive_sha256':          json2.Any(sha256.sum(os.read_bytes(state + '/initramfs.tar')!).hex())
	}, prettify: true) + '\n')!
	return status
}

fn copy(source string, destination string) ! {
	hosttest.module_copy_file_preserving_stat(source, destination)!
}

pub fn prepare(state string) ! {
	root := glhost.root()
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root + '/build-aarch64-userland/staging' }
	gpu_sysroot := os.getenv_opt('VINIX_GPU_SYSROOT') or { root + '/build-aarch64-x11/sysroot' }
	gpu := os.getenv_opt('VINIX_ASAHI_STAGING') or { root + '/build-aarch64-asahi/staging' }
	gcc_dir := sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl'
	versions := os.ls(gcc_dir)!
	if versions.len == 0 { return error('no AArch64 GCC install directory') }
	gcc := gcc_dir + '/' + versions[0]
	cc, shim := llvm + '/clang', root + '/build-support/aarch64-cc-shim'
	examples := state + '/examples'
	glhost.stage(examples, 'arm64')!
	native := state + '/native/usr/bin'
	os.mkdir_all(native)!
	os.symlink(gpu + '/usr/lib', state + '/native/usr/lib')!
	binary := native + '/gl-triangle-agx'
	glhost.run([cc, '--target=aarch64-linux-musl', '--sysroot=' + gpu_sysroot,
		'--gcc-install-dir=' + gcc, '-static-libgcc', '-isystem', shim, '-fuse-ld=lld', '-O2',
		'-Wall', '-Wextra', '-Werror', '-D__vinix__', '-fwrapv', '-fno-strict-aliasing',
		'-I' + gpu + '/usr/include', examples + '/egl_triangle.c', '-L' + gpu + '/usr/lib',
		'-Wl,-rpath-link,' + gpu + '/usr/lib', '-Wl,-dynamic-linker,/lib/ld-musl-aarch64.so.1',
		'-o', binary, '-lEGL', '-lGLESv2', '-Wl,--no-as-needed', '-lvinix-agx-fault', '-Wl,--as-needed',
		'-ldl', '-lpthread', '-lm'])!
	stage := state + '/rootfs'
	for dir in ['sbin', 'bin', 'dev', 'proc', 'sys', 'tmp', 'root', 'lib', 'usr/bin', 'usr/lib/dri'] {
		os.mkdir_all(stage + '/' + dir)!
	}
	glhost.run([cc, '--target=aarch64-linux-musl', '-static', '-nostdinc', '-nostdlib', '-isystem',
		shim, '-isystem', gcc + '/include', '-isystem', sysroot + '/usr/include', '-O2',
		sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o', gcc + '/crtbeginT.o',
		root + '/tests/gl-triangle/guest_init.c', '-L' + sysroot + '/usr/lib', '-L' + gcc, '-lc',
		'-lgcc', gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o', '-fuse-ld=lld', '-B' + llvm, '-o',
		stage + '/sbin/init'])!
	copy(sysroot + '/bin/busybox', stage + '/bin/busybox')!
	for name in ['sh', 'env'] { os.symlink('busybox', stage + '/bin/' + name)! }
	copy(binary, stage + '/usr/bin/gl-triangle-agx')!
	copy(root + '/gl-triangle/run-gl-triangle-agx', stage + '/usr/bin/run-gl-triangle-agx')!
	copy(gpu + '/lib/ld-musl-aarch64.so.1', stage + '/lib/ld-musl-aarch64.so.1')!
	os.symlink('../../lib/ld-musl-aarch64.so.1', stage + '/usr/lib/libc.musl-aarch64.so.1')!
	search := [gpu + '/usr/lib', gpu + '/lib', gpu_sysroot + '/usr/lib', gpu_sysroot + '/lib',
		sysroot + '/usr/lib', sysroot + '/lib']
	mut queue := [stage + '/bin/busybox', stage + '/usr/bin/gl-triangle-agx']
	mut seen := map[string]bool{}
	for pair in [['usr/lib/libgallium-25.0.5.so', 'usr/lib/libgallium-25.0.5.so'],
		['usr/lib/dri/libdril_dri.so', 'usr/lib/dri/libdril_dri.so']] {
		copy(gpu + '/' + pair[0], stage + '/' + pair[1])!
		queue << stage + '/' + pair[1]
	}
	os.symlink('libdril_dri.so', stage + '/usr/lib/dri/asahi_dri.so')!
	for queue.len > 0 {
		file := queue.pop()
		if file in seen { continue }
		seen[file] = true
		for name in needed_libraries(glhost.output([llvm + '/llvm-readelf', '-d', file])!) {
			destination := stage + '/usr/lib/' + name
			if os.exists(destination) { continue }
			mut found := false
			for directory in search {
				if os.is_file(directory + '/' + name) {
					copy(directory + '/' + name, destination)!
					found = true
					break
				}
			}
			if !found { return error('Missing exact Mesa dependency: ' + name) }
			queue << destination
		}
	}
	mut env := policyhost.environment()
	env['COPYFILE_DISABLE'] = '1'
	policyhost.owned_inherited_environment(['tar', '--format=ustar', '-cf', state + '/initramfs.tar',
		'-C', stage, '.'], env, policyhost.caller_arch(), '')!
}

pub fn needed_libraries(dynamic string) []string {
	mut names := []string{}
	for fragment in dynamic.split('Shared library: [')[1..] {
		if end := fragment.index(']') {
			if end > 0 { names << fragment[..end] }
		}
	}
	return names
}
