// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import encoding.binary
import graphicsbuild
import hosttest
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	r := sourcecommand.capture_full(argv, environment, -1, 16 * 1024 * 1024, cachecli.cancelled)!
	text := r.stdout + r.stderr
	os.write_file(log, text)!
	if r.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('graphics qualification failed: ' + log)
	}
	return r
}

fn elf(path string, machine u16) !json2.Any {
	bytes := os.read_bytes(path)!
	assert bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
	assert binary.little_endian_u16_at(bytes, 18) == machine
	return json2.Any({'path': json2.Any(path), 'sha256': json2.Any(sha256.sum(bytes).hex())})
}

fn qualify() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] { return error('expected new evidence and profile') }
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut environment := os.environ()
	for key, value in {'V': compiler, 'VINIX_V_COMPILER': compiler, 'VTMP': work + '/tmp',
		'TMPDIR': work + '/tmp', 'V_C_ERROR_BUG_REPORT_DISABLED': '1', 'V_MACOS_V3_NO_FALLBACK': '1',
		'ASAN_OPTIONS': 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1',
		'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'} { environment[key] = value }
	mut flags := []string{}
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '--target=x86_64-apple-macos13', '-ldflags', '--target=x86_64-apple-macos13']
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined', '-cflags', '-fno-omit-frame-pointer',
			'-cflags', '-O1', '-ldflags', '-fsanitize=address,undefined']
	}
	mut receipts := []json2.Any{}
	for name, path in {'main': root + '/build-support/graphics-tools/main.v',
		'check': root + '/build-support/graphics-tools/check.v',
		'generator': root + '/tests/linuxkpi/generate_module.v'} {
		output := work + '/' + name
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', output, path], environment, output + '-build.log')!
		receipts << json2.Any({'name': json2.Any(name), 'sha256': json2.Any(sha256.sum(os.read_bytes(output)!).hex())})
	}
	checked([work + '/check', work + '/fixtures'], environment, work + '/checks.log')!
	checked([work + '/main', '--help'], environment, work + '/help.log')!
	// Cached upstream archives are inspected and extracted as data. No SDK code runs.
	mesa := root + '/build-aarch64-venus/downloads/mesa-25.0.5.tar.xz'
	manifest := root + '/build-support/venus/packages.sha256'
	data := work + '/real-data'
	os.mkdir_all(data + '/downloads')!
	packages := graphicsbuild.manifest(os.read_file(manifest)!)!
	for package in packages {
		os.symlink(root + '/build-aarch64-venus/downloads/' + package.name, data + '/downloads/' + package.name)!
	}
	checked([work + '/main', 'venus-prepare', mesa, data, manifest], environment, work + '/real-prepare.log')!
	assert packages.len == 34
	assert os.is_file(data + '/sysroot/usr/include/xf86drm.h')
	assert os.is_file(data + '/sysroot/lib/ld-musl-aarch64.so.1')
	assert os.is_file(data + '/mesa-25.0.5/include/drm-uapi/virtgpu_drm.h')
	private := data + '/private'
	os.mkdir(private)!
	checked([work + '/main', 'libraries', data + '/sysroot/usr/lib', private], environment, work + '/real-libraries.log')!
	mut libraries := 0
	for name in os.ls(data + '/sysroot/usr/lib')! {
		if !name.contains('.so') { continue }
		from, to := data + '/sysroot/usr/lib/' + name, private + '/' + name
		if os.is_link(from) {
			assert os.readlink(from)! == os.readlink(to)!, name
		} else {
			assert sha256.sum(os.read_bytes(from)!).hex() == sha256.sum(os.read_bytes(to)!).hex(), name
			assert os.stat(from)!.mode & 0o7777 == os.stat(to)!.mode & 0o7777
			assert os.stat(from)!.mtime == os.stat(to)!.mtime
		}
		libraries++
	}
	clang := '/opt/homebrew/opt/llvm/bin/clang'
	for arch in ['arm64', 'amd64'] {
		output := work + '/venus-available-' + arch
		checked([work + '/generator', root + '/build-support/venus/availablecore', output + '.c', '--arch', arch], environment, output + '-generate.log')!
		triple := if arch == 'arm64' { 'aarch64' } else { 'x86_64' }
		sdk := root + if arch == 'arm64' { '/build-aarch64-userland/staging' } else { '/build-amd64-desktop/initramfs-root' }
		gcc := sdk + '/usr/lib/gcc/' + triple + '-alpine-linux-musl/14.2.0'
		checked([clang, '--target=' + triple + '-linux-musl', '--sysroot=' + sdk,
			'--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-static', '-O2', '-Wall', '-Wextra', '-Werror',
			'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
			'-I' + data + '/mesa-25.0.5/include/drm-uapi', '-isystem', data + '/sysroot/usr/include',
			output + '.c', '-o', output], environment, output + '-link.log')!
		receipts << elf(output, if arch == 'arm64' { u16(183) } else { u16(62) })!
	}
	x11 := root + '/build-aarch64-x11/sysroot'
	vnc := work + '/vinix-vnc-window-arm64'
	checked([work + '/generator', root + '/build-support/qemu-system/vnccore', vnc + '.c', '--arch', 'arm64'], environment, vnc + '-generate.log')!
	checked([clang, '--target=aarch64-linux-musl', '--sysroot=' + x11,
		'--gcc-install-dir=' + root + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0',
		'-static-libgcc', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label',
		'-Wno-unused-parameter', '-I' + x11 + '/usr/include', vnc + '.c', '-fuse-ld=lld',
		'-L' + x11 + '/usr/lib', '-L' + x11 + '/lib', '-Wl,-rpath-link,' + x11 + '/usr/lib',
		'-Wl,-rpath-link,' + x11 + '/lib', '-lX11', '-lxcb', '-o', vnc], environment, vnc + '-link.log')!
	receipts << elf(vnc, 183)!
	for path in ['scripts/build-venus-aarch64.sh', 'scripts/build-asahi-aarch64.sh', 'scripts/build-hyprland-aarch64.sh',
		'scripts/build-qemu-system-aarch64.sh', 'scripts/build-chromium-aarch64.sh',
		'scripts/build-libreoffice-aarch64.sh', 'scripts/build-x86-translation-aarch64.sh'] {
		checked(['/bin/bash', '-n', root + '/' + path], environment, work + '/' + os.file_name(path) + '-syntax.log')!
	}
	os.write_file(work + '/real-data.json', json2.encode(json2.Any({'mesa_blake2b': json2.Any(graphicsbuild.mesa_digest),
		'packages': json2.Any(packages.len), 'private_libraries': json2.Any(libraries)}), prettify: true) + '\n')!
	// This tree contains symlinks into shared SDK caches. Never follow them on cleanup.
	hosttest.remove_work_dir(data)!
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({'status': json2.Any('PASS'),
		'profile': json2.Any(profile), 'receipts': json2.Any(receipts),
		'limits': json2.Any('Native macOS behavior; actual cached Mesa/34 Alpine archives and library metadata; two real static musl Venus probes and one dynamic ARM musl VNC ELF. No Python, Mesa generators, graphics apps, probe ELF or Vinix guest executes. Sanitizers apply to host tools only.')}), prettify: true) + '\n')!
	println('PASS native graphics build qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	qualify() or { eprintln(err); exit(1) }
}
