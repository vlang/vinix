// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import cachecli
import generators
import guesthost
import hosttest
import os
import sourcecommand

fn checked_in(command []string, directory string) ! {
	previous := os.getwd()
	os.chdir(directory)!
	defer { os.chdir(previous) or {} }
	checked(command)!
}

pub fn atl_configuration_cli(argv []string) !int {
	args := parse_arguments(argv, ['--state-dir', '--kernel-dir', '--linux-host', '--baseline-rev'], []string{}, []string{}, 0, 0, 'usage: atl-configuration --state-dir NEW_DIR --kernel-dir KERNEL_DIR [--linux-host LIMA --baseline-rev REV]')!
	state := hosttest.module_resolve(required_value(args, '--state-dir')!)!
	kernel := hosttest.module_resolve(required_value(args, '--kernel-dir')!)!
	baseline_rev := args.value('--baseline-rev', '8f7239d1')
	if os.exists(state) || os.is_link(state) { return error('state directory already exists: ' + state) }
	posix_parents(posix_parent(state))!; os.mkdir(state)!
	support := root() + '/build-support/android'
	art := root() + '/build-aarch64-android/aarch64/art-runtime'
	native := root() + '/build-aarch64-userland/staging'
	directories := [art + '/usr/lib/art', root() + '/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib', native + '/lib', native + '/usr/lib', root() + '/build-aarch64-x11/staging/usr/lib']
	provider := state + '/src/libandroid/configuration.c'
	original := root() + '/build-aarch64-android/source/atl/src/libandroid/configuration.c'
	copy_tree(original, provider, false)!
	patch_source := os.read_file(support + '/atl-configuration.patch')!
	patch := patch_source.all_before('\n--- a/') + '\n'
	if !patch.starts_with('--- a/src/libandroid/configuration.c\n') { return error('ATL configuration provider patch shape changed') }
	os.write_file(state + '/configuration.patch', patch)!
	checked_in(['patch', '--batch', '--fuzz=0', '-p1', '-i', state + '/configuration.patch'], state)!
	mut versions := os.ls(native + '/usr/lib/gcc/aarch64-alpine-linux-musl')!; versions.sort()
	if versions.len == 0 { return error('native GCC runtime directory is empty') }
	cc := [os.getenv_opt('CC') or { '/opt/homebrew/opt/llvm/bin/clang' }, '--target=aarch64-linux-musl', '--sysroot=' + root() + '/build-aarch64-userland/sysroot', '--gcc-install-dir=' + native + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()]
	flags := ['-O2', '-Wall', '-Wextra', '-Werror', '-I' + art + '/usr/include']
	object := state + '/configuration.o'
	checked([...cc, ...flags, '-D_LARGEFILE64_SOURCE', '-c', provider, '-o', object])!
	baseline := sourcecommand.capture(['git', '-C', root(), 'show', baseline_rev + ':build-support/android/atl-configuration-test.c'], os.environ(), -1, 16 * 1024 * 1024, cachecli.cancelled)!
	if baseline.status != 0 { return error('cannot load frozen configuration baseline: ' + baseline.stderr) }
	os.write_file_array(state + '/baseline.c', baseline.stdout.bytes())!
	generators.generate_module(support + '/atlconfiguration', state + '/probe.c', 'arm64', ['nofloat'])!
	generators.generate_module(support + '/atlconfiguration', state + '/probe-x86.c', 'amd64', ['nofloat'])!
	checked([os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }, ...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I' + support, '-c', state + '/probe-x86.c', '-o', state + '/probe-x86.o'])!
	mut library_flags := []string{}
	for directory in directories { library_flags << ['-L' + directory, '-Wl,-rpath-link,' + directory] }
	mut programs := map[string]string{}
	for index, tag in ['c', 'v'] {
		source := state + if index == 0 { '/baseline.c' } else { '/probe.c' }
		program := state + '/probe-' + tag
		checked([...cc, ...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I' + support, source, object, ...library_flags, '-landroidfw', '-lpng', '-fuse-ld=lld', '-Wl,-z,max-page-size=65536', '-o', program])!
		programs[tag] = program
	}
	golden := 'ATL-CONFIGURATION-PASS snapshot=asset-manager owned-copy=verified matching=androidfw\n'
	if '--linux-host' in args.options {
		for tag, program in programs {
			output := probe_command(['limactl', 'shell', args.value('--linux-host', ''), native + '/lib/ld-musl-aarch64.so.1', '--library-path', directories.join(':'), program], true, '')!
			if output != golden { return error('native configuration result differed: ' + output) }
			os.write_file(state + '/linux-' + tag + '.log', output)!
		}
	}
	mut files := map[string]string{'bin/busybox': native + '/bin/busybox', 'lib/ld-musl-aarch64.so.1': native + '/lib/ld-musl-aarch64.so.1'}
	mut names := []string{}
	for tag, program in programs { files['probe-' + tag] = program; names << needed_libraries(program, 'aarch64-linux-musl-readelf')! }
	dependencies(names, directories, 'aarch64-linux-musl-readelf', 'lib/', []string{}, mut files)!
	mut script := '#!/bin/sh\nset -eu\nexport PATH=/bin LD_LIBRARY_PATH=/lib\nmount -t proc proc /proc 2>/dev/null || true\n'
	for tag, _ in programs { script += '/probe-' + tag + '\necho ATL-NATIVE-PASS:' + tag + '\n' }
	script += 'echo ATL-NATIVE-GUEST-PASS\nwhile :; do sleep 60; done\n'
	guest := guest_root(state, files, script)!
	archive := state + '/initramfs.tar.gz'; guest_archive(guest, archive, true)!
	mut plan := android_arm_plan(state, kernel, archive)
	// The saved configuration controller inherited these desktop variables.
	for key in ['VINIX_QEMU_PERSIST_DISK', 'VINIX_BOOT_HYPRLAND', 'VINIX_UI2_SOURCE'] { if value := os.getenv_opt(key) { plan.environment[key] = value } }
	expected := [golden.trim_right('\n'), 'ATL-NATIVE-PASS:c', 'ATL-NATIVE-PASS:v', 'ATL-NATIVE-GUEST-PASS']
	status := guesthost.boot_from_cancelled(plan.command, plan.environment, state, expected, ['KERNEL PANIC', 'Assertion failed'], 300, true, '', cachecli.cancelled)!
	mut hashes := map[string]ah.Value{}
	for name, source in files { hashes[name] = ah.digest(source)! }
	metadata := ah.Value({'baseline_revision': ah.Value(baseline_rev), 'result': ah.Value(status), 'expected_markers': ah.Value(expected.map(ah.Value(it))), 'configuration_probe_digest': ah.Value(ah.configuration_probe_digest(support)!), 'provider_source_sha256': ah.Value(ah.digest(original)!), 'provider_patch_sha256': ah.Value(ah.digest(state + '/configuration.patch')!), 'provider_header_sha256': ah.Value(ah.digest(art + '/usr/include/androidfw/androidfw_c_api.h')!), 'provider_library_sha256': ah.Value(ah.digest(art + '/usr/lib/art/libandroidfw.so')!), 'kernel_sha256': ah.Value(ah.digest(kernel + '/bin/vinix')!), 'files': ah.Value(hashes)})
	write_receipt(state + '/validation.json', metadata)!
	return status
}
