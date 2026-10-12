// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import allocationhost
import cachecli
import comparecore
import guesthost
import hosttest
import json2
import os
import sourcecommand
import time

pub const verification_flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-pthread']

pub fn verification_script(version string) !string {
	return match version {
		'v3' { $embed_file('verify-v3-init.txt').to_string() }
		'v4' { $embed_file('verify-v4-init.txt').to_string() }
		'v6' { $embed_file('verify-v4-init.txt').to_string() }
		else { return error('invalid x86 verification version') }
	}
}

fn copy_tree(source string, destination string) ! {
	os.mkdir(destination)!
	for name in os.ls(source)! {
		from := source + '/' + name
		to := destination + '/' + name
		if os.is_link(from) { os.symlink(os.readlink(from)!, to)!; hosttest.module_copy_link_stat(from, to)! }
		else if os.is_dir(from) { copy_tree(from, to)! }
		else if os.is_file(from) { hosttest.module_copy_file_preserving_stat(from, to)! }
		else { return error('unsupported verification rootfs entry: ' + from) }
	}
	hosttest.module_copy_directory_stat(source, destination)!
}

fn ordered_tree(path string, name string, mut names []string) ! {
	names << name
	if os.is_dir(path) && !os.is_link(path) {
		mut entries := os.ls(path)!
		entries.sort()
		for entry in entries { ordered_tree(path + '/' + entry, name + '/' + entry, mut names)! }
	}
}

pub fn timestamped_archive(rootfs string, destination string) ! {
	mut names := []string{}
	ordered_tree(rootfs, '.', mut names)!
	list := destination + '.members'
	defer { os.rm(list) or {} }
	os.write_file(list, names.join('\x00') + '\x00')!
	mut env := os.environ()
	env['COPYFILE_DISABLE'] = '1'
	checked(['tar', '--format=ustar', '--no-recursion', '--null', '-cf', destination, '-C', rootfs, '-T', list], '', env, destination + '.log')!
}

fn x86_state(context Context, version string) string {
	return if context.state != os.dir(context.origin) { context.state } else { context.root + '/third_party/useralloc-libc/build/useralloc/' + if version == 'v3' { 'verify-x86-v3' } else { 'verify-x86-' + version + '-final' } }
}

pub fn prepare_x86(context Context, version string) !int {
	state := x86_state(context, version)
	os.mkdir(state)!
	base := context.root + '/third_party/useralloc-libc/build/useralloc'
	rootfs := state + '/rootfs'
	suffix := if version == 'v3' { '-v3' } else { '-' + version + '-final' }
	if version == 'v3' { copy_tree(base + '/optimized' + suffix, rootfs)! }
	else { captured(['cp', '-cR', base + '/optimized' + suffix, rootfs])! }
	for directory in ['dev', 'proc', 'sys', 'tmp', 'root', 'sbin'] { mkdirs(rootfs + '/' + directory)! }
	os.chmod(rootfs + '/tmp', 0o1777)!
	source := context.root + '/tests/user-alloc/verify.c'
	clock := if version == 'v3' { context.root + '/third_party/useralloc-vm-next/tests/user-alloc/clock.c' } else { context.root + '/tests/user-alloc/clock.c' }
	copy_file(source, rootfs + '/root/verify.c')!
	copy_file(clock, rootfs + '/root/clock.c')!
	if version != 'v3' { copy_file(context.root + '/tests/user-alloc/verify-all-classes.c', rootfs + '/root/verify-all-classes.c')! }
	mut manifests := map[string]json2.Any{}
	for policy in ['optimized', 'disabled'] {
		stage := base + '/' + policy + suffix
		target := rootfs + '/root/libcs/' + policy
		if os.exists(target) { return error('verification policy target already exists') }
		mkdirs(target)!
		manifest := read_json(stage + '/usr/share/vinix/musl-build.json')!
		for name, field in {'libc.so': 'libc_so_sha256', 'libc.a': 'libc_a_sha256'} {
			path := stage + '/' + if name == 'libc.so' { 'lib/ld-musl-x86_64.so.1' } else { 'usr/lib/libc.a' }
			checked_hash(path, manifest[field]!.str())!
			copy_file(path, target + '/' + name)!
		}
		copy_file(stage + '/usr/share/vinix/musl-build.json', target + '/build.json')!
		manifests[policy] = manifest.clone()
	}
	init := rootfs + '/sbin/init'
	os.rm(init) or { if os.exists(init) || os.is_link(init) { return err } }
	os.write_file(init, verification_script(version)!)!
	os.chmod(init, 0o755)!
	timestamped_archive(rootfs, state + '/initramfs.tar')!
	mut config := map[string]json2.Any{'source_sha256': json2.Any(digest(source)!), 'clock_source_sha256': json2.Any(digest(clock)!), 'compile_flags': json2.Any(verification_flags.map(json2.Any(it))), 'libc_builds': json2.Any(manifests)}
	if version != 'v3' { config['supplemental_source_sha256'] = digest(context.root + '/tests/user-alloc/verify-all-classes.c')! }
	write_json(state + '/config.json', config)!
	println('Prepared ' + state)
	flush_stdout()
	return 0
}

pub fn x86_verdict(raw []u8, version string) !bool {
	output := guesthost.replacement_text(raw)
	lines := comparecore.lines(output).filter(it.starts_with('UALLOC-') || it.starts_with('CLOCK-'))
	if ['KERNEL PANIC', 'FATAL EXCEPTION', 'UALLOC-FAIL', 'CLOCK-FAIL'].any(output.contains(it)) { return error('Guest failed') }
	if !output.contains('UALLOC-VERIFY-COMPLETE') { return false }
	if !output.contains('CLOCK-DONE ') { return error('Guest clock record missing') }
	mut markers := ['UALLOC-DONE ', 'UALLOC-MODE-COMPLETE ']
	if version != 'v3' { markers << ['UALLOC-SUPPLEMENT-DONE ', 'UALLOC-ALL-CLASSES ', 'UALLOC-THREAD-TRANSITIONS ', 'UALLOC-ORIGINAL-COMPLETE '] }
	for marker in markers { if lines.filter(it.starts_with(marker)).len != 4 { return error('Guest verification marker count differs: ' + marker) } }
	if version == 'v6' { verification_records(raw, 'x86_64')! }
	return true
}

struct VerificationDone {}
fn (done VerificationDone) msg() string { return 'verification completed' }
fn (done VerificationDone) code() int { return 0 }

struct VerificationWatch {
	state string
	version string
}

fn verify_watch(pid int, pointer voidptr) ! {
	context := unsafe { &VerificationWatch(pointer) }
	seconds := if context.version == 'v3' { 900 } else { 3600 }
	deadline := time.sys_mono_now() + u64(seconds) * u64(time.second)
	mut printed := 0
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		raw := os.read_bytes(context.state + '/serial.log') or { []u8{} }
		lines := comparecore.lines(guesthost.replacement_text(raw)).filter(it.starts_with('UALLOC-') || it.starts_with('CLOCK-'))
		for line in lines[if printed < lines.len { printed } else { lines.len }..] { println(line); flush_stdout() }
		printed = lines.len
		if x86_verdict(raw, context.version)! {
			println(if context.version == 'v3' { 'All four allocator modes verified' } else { 'All four allocator modes and supplemental suites verified' })
			flush_stdout()
			return VerificationDone{}
		}
		if sourcecommand.child_exited(pid)! { return error('QEMU exited') }
		time.sleep(250 * time.millisecond)
	}
	return error('Guest verification timeout')
}

pub fn run_x86(context Context, version string, kernel_path string) !int {
	state := x86_state(context, version)
	mut config := read_json(state + '/config.json')!
	kernel := resolve(kernel_path)!
	iso := state + '/vinix.iso'
	if version == 'v6' { checked_hash(kernel, core_kernel('x86_64')!)! }
	if version in ['v3', 'v6'] {
		mut env := os.environ()
		for key, value in {'VINIX_AMD64_ISO_BUILD_DIR': state + '/iso-build', 'VINIX_AMD64_KERNEL': kernel, 'VINIX_AMD64_INITRAMFS': state + '/initramfs.tar', 'VINIX_AMD64_ISO': iso} { env[key] = value }
		checked([context.root + '/build-support/build-amd64-iso.sh'], '', env, state + '/image-build.log')!
		if version == 'v6' {
			checked(['xorriso', '-osirrox', 'on', '-indev', iso, '-extract', '/boot/vinix', state + '/boot-kernel', '-extract', '/boot/initramfs.tar', state + '/embedded-initramfs.tar'], '', os.environ(), state + '/image-extract.log')!
			checked_hash(state + '/boot-kernel', digest(kernel)!)!
			mut paths := ['sbin/init', 'root/verify.c', 'root/verify-all-classes.c', 'root/clock.c', 'lib/ld-musl-x86_64.so.1', 'usr/lib/libc.a']
			for policy in ['optimized', 'disabled'] { for name in ['libc.so', 'libc.a', 'build.json'] { paths << 'root/libcs/' + policy + '/' + name } }
			mut files := map[string]json2.Any{}
			for path in paths {
				bytes := archive_bytes(state + '/embedded-initramfs.tar', './' + path)!
				if bytes != os.read_bytes(state + '/rootfs/' + path)! { return error('embedded x86 input differs: ' + path) }
				files[path] = hosttest.text_sha(bytes.bytestr())
			}
			write_json(state + '/embedded-input-check.json', {'match': json2.Any(true), 'files_sha256': json2.Any(files), 'kernel_sha256': json2.Any(digest(state + '/boot-kernel')!), 'iso_sha256': json2.Any(digest(iso)!)})!
		}
	} else {
		proof := read_json(state + '/embedded-input-check.json')!
		if !gate_passed(proof['match']!, json2.Any(true)) { return error('completed ISO input proof failed') }
		checked_hash(iso, proof['iso_sha256']!.str())!
		checked_hash(state + '/boot-kernel', digest(kernel)!)!
	}
	qemu := resolve(os.find_abs_path_of_executable('qemu-system-x86_64')!)!
	firmware := os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd'
	command := allocationhost.vm_command(qemu, firmware, iso, state + '/serial.log', .saved_final, 2)
	// The v3 attempt retains its obsolete pre-extraction kernel path.
	config['kernel_sha256'] = digest(if version == 'v3' { state + '/iso-build/iso-root/boot/vinix' } else { state + '/boot-kernel' })!
	versions := captured([qemu, '--version'])!.split_into_lines()
	if versions.len == 0 { return error('QEMU version missing') }
	config['qemu_version'] = versions[0]
	config['argv'] = command.map(json2.Any(it))
	write_json(state + '/config.json', config)!
	watch := VerificationWatch{state, version}
	sourcecommand.run_logged_owned(command, os.environ(), cachecli.cancelled, state + '/qemu.log', false, '', verify_watch, unsafe { &watch }, 5) or {
		if err is VerificationDone { return 0 }
		return err
	}
	return error('verification returned without a verdict')
}
