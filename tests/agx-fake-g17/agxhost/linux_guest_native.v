// SPDX-License-Identifier: GPL-2.0-or-later
// Native filesystem/process primitives for the maintained LinuxKPI workflow.
@[has_globals]
module agxhost

import hosttest
import json2
import os
import time

// A command owns one supervisor. The callback-era entry remains available to
// its existing callers; native callers execute that same workflow in-process.
__global guest_native_owner = &NativeGuestOwner(unsafe { nil })

struct NativeGuestOwner {
	hooks LinuxGuestNativeHooks
mut:
	child    &os.Process = unsafe { nil }
	log      os.File
	log_open bool
	retiring bool
}

// Native workflow tests replace preparation steps while the original marker,
// deadline and process-retirement policy still observes real child processes.
pub struct LinuxGuestNativeHooks {
pub:
	generate fn (string,string,string,[]string,voidptr) !bool = unsafe { nil }
	run fn ([]string,map[string]string,bool,voidptr) !bool = unsafe { nil }
	iso fn (string,map[string]string,voidptr) !bool = unsafe { nil }
	context voidptr
}

fn guest_native_generate(source string, output string, arch string, defines []string) ! {
	owner := unsafe { guest_native_owner }
	if owner.hooks.generate != unsafe { nil } && owner.hooks.generate(source,output,arch,defines,owner.hooks.context)! { return }
	hosttest.generate_module(source,output,arch,defines)!
}

fn guest_native_active() bool { return unsafe { guest_native_owner != nil } }

fn (mut owner NativeGuestOwner) output() ! {
	if unsafe { owner.child == nil } { return }
	// A bounded drain keeps even a verbose failing child from starving the
	// maintained deadline and serial checks. Both streams share this one pipe.
	for _ in 0 .. 64 {
		text := owner.child.stdout_read()
		if text == '' { break }
		owner.log.write_string(text)!
	}
	owner.log.flush()
}

fn (mut owner NativeGuestOwner) poll() !json2.Any {
	if unsafe { owner.child == nil } { return json2.Null{} }
	if owner.child.pid <= 0 { return error('guest process was not started') }
	owner.output()!
	alive := owner.child.is_alive()
	owner.output()!
	return if alive { json2.Any(json2.Null{}) } else { json2.Any(owner.child.code) }
}

fn (mut owner NativeGuestOwner) wait(timeout f64) !int {
	deadline := vm_now() + timeout
	for {
		result := owner.poll()!
		if result !is json2.Null { return result.int() }
		if timeout >= 0 && vm_now() >= deadline {
			return GuestBindingFailure{{
				'binding_kind': json2.Any('TimeoutExpired')
			}}
		}
		time.sleep(10 * time.millisecond)
	}
	return 0
}

fn (mut owner NativeGuestOwner) retire() {
	if unsafe { owner.child != nil } {
		// Only this command's unreaped child can receive a signal. Process.is_alive
		// updates its state when it reaps; already reaped PIDs are never signalled.
		if owner.child.pid > 0 && owner.child.is_alive() {
			unsafe { C.kill(i32(owner.child.pid), C.SIGKILL) }
			owner.child.wait()
		}
		owner.output() or {}
		owner.child.close()
	}
	if owner.log_open {
		owner.log.close()
		owner.log_open = false
	}
}

// The supervisor dispatch uses ordinary host primitives, never an interpreter.
// All marker selection, failure detection and final reread stay in linux_guest.
fn guest_native_dispatch(method string, row map[string]json2.Any) !json2.Any {
	mut owner := unsafe { guest_native_owner }
	if !owner.retiring && method !in ['retiring', 'terminate', 'kill', 'wait'] {
		vm_interrupt_check()!
	}
	match method {
		'metadata' { return guest_metadata()! }
		'path' { return row['path']! }
		'join' { return guest_path(os.join_path(guest_decode(row['base']!)!, row['name']!.str())) }
		'resolve' { return guest_path(hosttest.module_resolve(guest_decode(row['path']!)!)!) }
		'parent_parent' { return guest_path(os.dir(os.dir(guest_decode(row['path']!)!))) }
		'mkdir' {
			path := guest_decode(row['path']!)!
			native_mkdir(path, row['parents']!.bool(), row['exist_ok']!.bool())!
		}
		'contains' { return row['haystack']!.str().contains(row['needle']!.str()) }
		'which' {
			found := os.find_abs_path_of_executable(row['name']!.str()) or { return json2.Null{} }
			return found
		}
		'exists' { return os.exists(guest_decode(row['path']!)!) }
		'read_text' { return os.read_file(guest_decode(row['path']!)!)! }
		'copytree' {
			destination := guest_decode(row['destination']!)!
			native_mkdir(os.dir(destination), true, true)!
			hosttest.module_copy_tree(guest_decode(row['source']!)!, destination)!
		}
		'archive' {
			mut environment := os.environ()
			environment['COPYFILE_DISABLE'] = '1'
			guest_native_run(['tar', '--format=ustar', '-cf', guest_decode(row['path']!)!, '-C',
				guest_decode(row['rootfs']!)!, '.'], environment, false)!
		}
		'run' {
			mut environment := os.environ()
			entries := row['environment']!
			if entries !is json2.Null {
				environment = map[string]string{}
				for pair in entries.as_array() {
					values := pair.as_array()
					environment[guest_decode(values[0])!] = guest_decode(values[1])!
				}
			}
			encoded_argv := row['argv']!.as_array()
			mut argv := []string{cap: encoded_argv.len}
			for item in encoded_argv { argv << guest_decode(item)! }
			guest_native_run(argv, environment, row['quiet']!.bool())!
		}
		'start' {
			if unsafe { owner.child != nil } { return error('guest process already owned') }
			encoded_argv := row['argv']!.as_array()
			mut argv := []string{cap: encoded_argv.len}
			for item in encoded_argv { argv << guest_decode(item)! }
			if argv.len == 0 { return error('empty QEMU command') }
			owner.log = os.create(guest_decode(row['log']!)!)!
			owner.log_open = true
			owner.child = os.new_process(argv[0])
			owner.child.set_args(argv[1..])
			owner.child.set_redirect_stdio_merged()
			owner.child.set_environment(os.environ())
			owner.child.run()
			if owner.child.pid <= 0 { return error('cannot start QEMU: ' + argv[0]) }
		}
		'poll' { return owner.poll()! }
		'terminate', 'kill' {
			if unsafe { owner.child != nil } && owner.child.is_alive() {
				if unsafe { C.kill(i32(owner.child.pid), if method == 'kill' {
					C.SIGKILL
				} else {
					C.SIGTERM
				}) } < 0 && C.errno != C.ESRCH {
					return vm_os_error()
				}
			}
		}
		'wait' {
			timeout := row['timeout']!
			return owner.wait(if timeout is json2.Null { -1 } else { timeout.f64() })!
		}
		'retiring' {
			owner.retiring = true
			unsafe {
				C.signal(C.SIGINT, C.SIG_IGN)
				C.signal(C.SIGTERM, C.SIG_IGN)
			}
		}
		'print' {
			for item in row['lines']!.as_array() { println(guest_decode(item)!) }
		}
		else { return error('unknown native guest primitive: ' + method) }
	}
	return json2.Null{}
}

fn guest_native_run(argv []string, environment map[string]string, quiet bool) ! {
	if guest_native_active() {
		owner := unsafe { guest_native_owner }
		if owner.hooks.run != unsafe { nil } && owner.hooks.run(argv,environment,quiet,owner.hooks.context)! { return }
	}
	result := hosttest.capture(argv, '', -1, environment)!
	if !quiet { print(result.stdout) }
	eprint(result.stderr)
	if result.code != 0 { return CommandFailure{argv, result} }
}

const native_limine_commit = 'ee5d29cd0a8034612dcd1df3f00052480db785c5'
const native_limine_files = {
	'BOOTX64.EFI':        'c1d6c34cf827e0c5cb0f3546d2db8568dd29aae26833a6332db5532b823503c3'
	'limine-uefi-cd.bin': '7751a48fde8ec040f3ac079a9893dbbe0687af3e3c0a96619d69ae2eba9b1478'
	'limine-bios-cd.bin': 'f1b97df69d0a2723a8a849e915665b1a9a7c5988f2245400aac9891adb4725c1'
	'limine-bios.sys':    '39f4619ae75e31432aea0ddd14ad3206f7c5b2b637e879bec090fc8bb546f309'
	'limine.c':           'e015228283ad9a373b88041a18f8714eba109f4f08b2f3a39d7bf3a8d12de32f'
	'limine-bios-hdd.h':  '21303b2f510e50dffec4fd2fb3a3e4acf889db8cf48c2ae6882b0a2b173e2e10'
}

fn guest_native_install(source string, destination string) ! {
	os.cp(source, destination)!
	os.chmod(destination, 0o644)!
}

// The existing hybrid image contract is assembled by V with the original six
// pinned bootloader inputs. Each invocation has a fresh caller-owned workspace.
fn guest_native_iso(root string, environment map[string]string) ! {
	owner := unsafe { guest_native_owner }
	if owner.hooks.iso != unsafe { nil } && owner.hooks.iso(root,environment,owner.hooks.context)! { return }
	build := environment['VINIX_AMD64_ISO_BUILD_DIR'] or { return error('missing ISO build directory') }
	kernel := environment['VINIX_AMD64_KERNEL'] or { return error('missing kernel') }
	archive := environment['VINIX_AMD64_INITRAMFS'] or { return error('missing initramfs') }
	output := environment['VINIX_AMD64_ISO'] or { return error('missing ISO output') }
	if build in ['', '/', root] { return error('unsafe ISO build directory') }
	for path in [kernel, archive, root + '/build-support/limine.conf'] {
		if !os.is_file(path) { return error('missing ISO input: ' + path) }
	}
	os.mkdir_all(build + '/limine')!
	for name, expected in native_limine_files {
		path := build + '/limine/' + name
		if !os.is_file(path) || os.file_size(path) == 0 {
			guest_native_run(['curl', '-fL', '--retry', '3',
				'https://raw.githubusercontent.com/limine-bootloader/limine/' + native_limine_commit + '/' + name,
				'-o', path], environment, true)!
		}
		if hosttest.sha(path)! != expected {
			return error('pinned Limine checksum mismatch: ' + name)
		}
	}
	tool := build + '/limine/limine-native'
	// Recompile the checked source instead of trusting an executable in a cache.
	guest_native_run(['cc', '-O2', '-std=c99', '-o', tool, build + '/limine/limine.c'], environment, true)!
	staging := private_directory(build, '.iso-staging.')!
	defer { hosttest.remove_work_dir(staging) or {} }
	image := staging + '/iso-root'
	identity := staging + '/image-id'
	os.mkdir_all(image + '/boot')!
	os.mkdir_all(image + '/EFI/BOOT')!
	os.mkdir(identity)!
	guest_native_install(kernel, image + '/boot/vinix')!
	guest_native_install(archive, image + '/boot/initramfs.tar')!
	config := os.read_file(root + '/build-support/limine.conf')!
	additional := environment['VINIX_CMDLINE'] or { '' }
	os.write_file(image + '/boot/limine.conf', config + '    cmdline: vinix.disk=auto' + if additional != '' {
		' ' + additional
	} else {
		''
	} + '\n')!
	os.write_file(identity + '/.vinix-image-id', hosttest.sha(archive)![..16] + '\n')!
	mut tar_environment := environment.clone()
	tar_environment['COPYFILE_DISABLE'] = '1'
	guest_native_run(['tar', '--format=ustar', '-rf', image + '/boot/initramfs.tar', '-C', identity,
		'./.vinix-image-id'], tar_environment, true)!
	for name in ['limine-uefi-cd.bin', 'limine-bios-cd.bin', 'limine-bios.sys'] {
		guest_native_install(build + '/limine/' + name, image + '/boot/' + name)!
	}
	guest_native_install(build + '/limine/BOOTX64.EFI', image + '/EFI/BOOT/BOOTX64.EFI')!
	os.mkdir_all(os.dir(output))!
	temporary := staging + '/test.iso'
	guest_native_run(['xorriso', '-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J', '-b',
		'boot/limine-bios-cd.bin', '-no-emul-boot', '-boot-load-size', '4', '-boot-info-table',
		'--efi-boot', 'boot/limine-uefi-cd.bin', '-efi-boot-part', '--efi-boot-image',
		'--protective-msdos-label', image, '-o', temporary], environment, true)!
	guest_native_run([tool, 'bios-install', temporary], environment, true)!
	os.mv(temporary, output)!
}

pub fn linux_guest_native(row map[string]json2.Any) !int {
	return linux_guest_native_with_hooks(row,LinuxGuestNativeHooks{})!
}

pub fn linux_guest_native_with_hooks(row map[string]json2.Any, hooks LinuxGuestNativeHooks) !int {
	if guest_native_active() { return error('a native guest supervisor is already active') }
	mut owner := NativeGuestOwner{ hooks: hooks }
	unsafe {
		C.__atomic_store_n(&i32(C.VINIX_AGX_VM_INTERRUPTED), i32(0), C.__ATOMIC_RELAXED)
		guest_native_owner = &owner
	}
	previous_int := unsafe { C.signal(C.SIGINT, voidptr(vm_native_signal)) }
	previous_term := unsafe { C.signal(C.SIGTERM, voidptr(vm_native_signal)) }
	defer {
		// Cleanup must continue through additional interrupts. The command retains
		// this child and its log until wait/close complete, including error returns.
		unsafe {
			C.signal(C.SIGINT, C.SIG_IGN)
			C.signal(C.SIGTERM, C.SIG_IGN)
		}
		owner.retire()
		unsafe {
			guest_native_owner = nil
			C.signal(C.SIGINT, previous_int)
			C.signal(C.SIGTERM, previous_term)
		}
	}
	return linux_guest(row)!
}
