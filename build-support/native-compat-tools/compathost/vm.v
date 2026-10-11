// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import guesthost
import hosttest
import json2
import os
import policyhost
import strconv

fn timeout_option(parsed hosttest.Arguments, fallback int) !int {
	value := if '--timeout' in parsed.options { strconv.atoi(parsed.options['--timeout']) or { return error_with_code('Invalid timeout', 2) } } else { fallback }
	if value <= 0 { return error_with_code('Timeout must be positive', 2) }
	return value
}

fn install_files(files map[string]string, rootfs string) !map[string]string {
	mut hashes := map[string]string{}
	for name, source in files {
		destination := rootfs + '/' + name
		os.mkdir_all(os.dir(destination))!
		hosttest.module_copy_file_preserving_stat(source, destination)!
		hashes[name] = hosttest.sha(destination)!
	}
	return hashes
}

fn guest_archive(work string) !string {
	// The ISO builder appends its image ID to an uncompressed ustar archive.
	archive := work + '/initramfs.tar'
	mut env := policyhost.environment()
	env['COPYFILE_DISABLE'] = '1'
	fixturehost.inherited_command_environment_preferred(['tar', '--format=ustar', '-cf', archive, '-C', work + '/root', '.'], env, policyhost.caller_arch())!
	return archive
}

// Snapshot the requested kernel; each runtime owns its archive, ISO, variables
// image and QMP socket. The desktop launcher starts a Python package server.
fn runtime_guest(work string, kernel_dir string, inputs map[string]json2.Any, expected []string, failures []string, timeout int, build_only bool) !int {
	kernel := work + '/kernel/bin/vinix'
	os.mkdir_all(os.dir(kernel))!
	hosttest.module_copy_file_preserving_stat(resolve(kernel_dir)! + '/bin/vinix', kernel)!
	header := os.read_bytes(kernel)!
	if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || header[18] != 183 || header[19] != 0 {
		return error('Runtime guest requires a little-endian ARM ELF64 kernel')
	}
	archive := guest_archive(work)!
	mut receipt := inputs.clone()
	receipt['kernel_sha256'] = hosttest.sha(kernel)!
	receipt['archive_sha256'] = hosttest.sha(archive)!
	receipt['runner_sha256'] = hosttest.sha(root() + '/build-support/native-compat-tools/compathost/vm.v')!
	receipt['kernel_rebuilt'] = false
	hosttest.write_json(work + '/inputs.json', receipt)!
	if build_only { return 0 }
	configured := guesthost.launch(work + '/root/sbin/init', archive, work, work + '/kernel', 'aarch64', true)!
	mut argv := configured.command.clone()
	for index, argument in argv { if argument == '-smp' { argv[index + 1] = '2' } }
	receipt['command'] = hosttest.strings(argv)
	receipt['iso_sha256'] = hosttest.sha(work + '/test.iso')!
	hosttest.write_json(work + '/inputs.json', receipt)!
	result := guesthost.boot(argv, configured.env, work, expected, failures, timeout, true)!
	receipt['exit_code'] = result
	receipt['expected_markers'] = hosttest.strings(expected)
	hosttest.write_json(work + '/results.json', receipt)!
	return result
}

fn robust_guest(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--work', value: true},
		hosttest.Option{name: '--kernel-dir', value: true}, hosttest.Option{name: '--native-root', value: true},
		hosttest.Option{name: '--translator-root', value: true}, hosttest.Option{name: '--timeout', value: true},
		hosttest.Option{name: '--build-only'}], 0,
		'Usage: run-robust-vm --work FRESH-DIR --kernel-dir DIR [--native-root DIR] [--translator-root DIR] [--timeout SECONDS] [--build-only]',
		'Exercise both actual Steam x86 ABIs through an isolated ARM linux-user guest.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--work', '--kernel-dir'])!
	timeout := timeout_option(parsed, 600)!
	work := hosttest.work_dir(parsed.options['--work'], 'vinix-steam-guest-')!
	robust_native(work + '/sources')!
	native := resolve(if '--native-root' in parsed.options { parsed.options['--native-root'] } else { root() + '/build-aarch64-userland/staging' })!
	translator := resolve(if '--translator-root' in parsed.options { parsed.options['--translator-root'] } else { root() + '/build-aarch64-steam/translator-only/staging' })!
	mut files := {'bin/busybox': native + '/bin/busybox', 'lib/ld-musl-aarch64.so.1': native + '/lib/ld-musl-aarch64.so.1'}
	mut variants := []string{}
	mut script := '#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1\nunset LD_PRELOAD LD_LIBRARY_PATH\nmount -t proc proc /proc 2>/dev/null || true\n'
	for arch in ['i386', 'x86_64'] {
		files['usr/bin/qemu-' + arch] = translator + '/usr/bin/qemu-' + arch
		for label in ['original', 'v'] {
			name := arch + '-' + label
			files['usr/bin/' + name] = work + '/sources/' + arch + '-native/' + label
			variants << 'STEAM-ROBUST-PASS:' + name
			script += 'echo STEAM-ROBUST-BEGIN:' + name + '\n/usr/bin/qemu-' + arch + ' -B 0x100000000 /usr/bin/' + name + '\necho STEAM-ROBUST-PASS:' + name + '\n'
		}
	}
	script += 'echo STEAM-ROBUST-ALL-PASS\nwhile :; do sleep 60; done\n'
	variants << 'STEAM-ROBUST-ALL-PASS'
	rootfs := work + '/root'
	hashes := install_files(files, rootfs)!
	for name in ['dev', 'proc', 'tmp', 'sbin'] { os.mkdir_all(rootfs + '/' + name)! }
	for name in ['sh', 'mount', 'sleep'] { os.symlink('busybox', rootfs + '/bin/' + name)! }
	write(rootfs + '/sbin/init', script)!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	mut sources := map[string]string{}
	for directory in ['/build-support/steam/robustcore', '/tests/steam/robustfixture', '/tests/steam/robustbare'] {
		for path in os.glob(root() + directory + '/*.v')! { sources[path[root().len + 1..]] = hosttest.sha(path)! }
	}
	return runtime_guest(work, parsed.options['--kernel-dir'], {
		'original_revision': json2.Any(original)
		'files': json2.Any(hosttest.string_map(hashes))
		'sources': json2.Any(hosttest.string_map(sources))
	}, variants, ['STEAM ROBUST ABI FIXTURE: FAIL', 'KERNEL PANIC'], timeout, '--build-only' in parsed.options)!
}

pub fn shared_libraries(dynamic string) []string {
	mut result := []string{}
	for line in dynamic.split('\n') {
		if line.contains('Shared library: [') && line.all_after('Shared library: [').contains(']') {
			result << line.all_after('Shared library: [').all_before(']')
		}
	}
	return result
}

fn office_guest(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--state-dir', value: true},
		hosttest.Option{name: '--kernel-dir', value: true}, hosttest.Option{name: '--fixtures', value: true},
		hosttest.Option{name: '--timeout', value: true}, hosttest.Option{name: '--build-only'}], 0,
		'Usage: run-vm --state-dir FRESH-DIR --kernel-dir DIR --fixtures DIR [--timeout SECONDS] [--build-only]',
		'Execute Windows64 C/V licensing goldens in staged Wine on Vinix.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--state-dir', '--kernel-dir', '--fixtures'])!
	timeout := timeout_option(parsed, 900)!
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-office-guest-')!
	rootfs := work + '/root'
	stage := root() + '/build-aarch64-x86-translation/staging'
	runtime := stage + '/usr/libexec/vinix-x86_64/root'
	native := root() + '/build-aarch64-userland/staging'
	mut files := {'bin/busybox': native + '/bin/busybox', 'lib/ld-musl-aarch64.so.1': native + '/lib/ld-musl-aarch64.so.1',
		'usr/bin/qemu-x86_64': stage + '/usr/bin/qemu-x86_64', 'usr/bin/run-x86-64': root() + '/build-support/x86-translation/run-x86-64',
		'usr/bin/wineserver': root() + '/build-support/x86-translation/run-wine-x86-64',
		'runtime/usr/bin/wine': runtime + '/usr/bin/wine', 'runtime/usr/bin/wineserver': runtime + '/usr/bin/wineserver',
		'runtime/lib/ld-musl-x86_64.so.1': runtime + '/lib/ld-musl-x86_64.so.1'}
	fixtures := resolve(parsed.options['--fixtures'])!
	for variant in ['c', 'v'] { files['test-' + variant + '.exe'] = fixtures + '/fixture-' + variant + '.exe' }
	for source in os.walk_ext(runtime + '/usr/share/wine', '') {
		if os.is_file(source) { files['runtime/usr/share/wine/' + source[(runtime + '/usr/share/wine/').len..]] = source }
	}
	mut pending := []string{}
	for kind in ['windows', 'unix'] {
		directory := runtime + '/usr/lib/wine/x86_64-' + kind
		for name in os.ls(directory)! {
			source := directory + '/' + name
			if os.is_file(source) {
				files['runtime/usr/lib/wine/x86_64-' + kind + '/' + name] = source
				if kind == 'unix' && name in ['ntdll.so', 'win32u.so'] { pending << source }
			}
		}
	}
	pending << [runtime + '/usr/bin/wine', runtime + '/usr/bin/wineserver']
	mut seen := map[string]bool{}
	for pending.len > 0 {
		source := pending.pop()
		for name in shared_libraries(output(['aarch64-linux-musl-readelf', '-d', source])!) {
			if name in seen { continue }
			seen[name] = true
			mut dependency := ''
			for directory in ['/lib', '/usr/lib', '/usr/lib/wine/x86_64-unix'] {
				if os.is_file(runtime + directory + '/' + name) { dependency = runtime + directory + '/' + name; break }
			}
			if dependency == '' { return error('Missing staged Wine dependency: ' + name) }
			files['runtime/lib/' + name] = dependency
			pending << dependency
		}
	}
	hashes := install_files(files, rootfs)!
	for name in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root/.wine/drive_c/windows/system32', 'root/.wine/dosdevices', 'etc', 'runtime/share'] {
		os.mkdir_all(rootfs + '/' + name)!
	}
	os.chmod(rootfs + '/tmp', 0o1777)!
	for name in ['sh', 'sleep', 'mount', 'mkdir'] { os.symlink('busybox', rootfs + '/bin/' + name)! }
	os.symlink('../usr/share/wine', rootfs + '/runtime/share/wine')!
	write(rootfs + '/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
	write(rootfs + '/etc/group', 'root:x:0:\n')!
	write(rootfs + '/root/.wine/.update-timestamp', 'disable\n')!
	os.symlink('../drive_c', rootfs + '/root/.wine/dosdevices/c:')!
	os.symlink('/', rootfs + '/root/.wine/dosdevices/z:')!
	for name in os.ls(rootfs + '/runtime/usr/lib/wine/x86_64-windows')! {
		os.symlink('/runtime/usr/lib/wine/x86_64-windows/' + name, rootfs + '/root/.wine/drive_c/windows/system32/' + name)!
	}
	mut script := '#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin HOME=/root USER=root VINIX_ALLOW_WX=1\n'
	script += 'export VINIX_X86_64_ROOT=/runtime WINEPREFIX=/root/.wine WINEARCH=win64 WINEDEBUG=+seh\n'
	script += 'export WINEDLLPATH=/runtime/usr/lib/wine/x86_64-unix:/runtime/usr/lib/wine/x86_64-windows\n'
	script += 'export WINELOADERNOEXEC=1 WINESERVER=/usr/bin/wineserver WINEDLLOVERRIDES=winemenubuilder.exe=d\n'
	script += 'mount -t proc proc /proc 2>/dev/null || true\nulimit -s 32768\n'
	for variant in ['c', 'v'] {
		script += 'echo OFFICE-NATIVE-BEGIN:' + variant + '\nset +e\n/usr/bin/run-x86-64 /runtime/usr/bin/wine /test-' + variant + '.exe\nresult=$?\nset -e\n'
		script += 'if [ "$result" -ne 73 ]; then echo "OFFICE-NATIVE-ERROR:' + variant + ':exit=$result"; exit 1; fi\n'
		script += 'echo OFFICE-NATIVE-PASS:' + variant + '\n'
	}
	script += 'echo OFFICE-NATIVE-GUEST-PASS\nwhile :; do sleep 60; done\n'
	write(rootfs + '/sbin/init', script)!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	return runtime_guest(work, parsed.options['--kernel-dir'], {
		'files': json2.Any(hosttest.string_map(hashes))
		'fixture_success_exit': json2.Any(73)
	}, ['OFFICE-NATIVE-PASS:c', 'OFFICE-NATIVE-PASS:v', 'OFFICE-NATIVE-GUEST-PASS'],
		['KERNEL PANIC', 'Office ABI assertion', 'OFFICE-NATIVE-ERROR:'], timeout, '--build-only' in parsed.options)!
}
