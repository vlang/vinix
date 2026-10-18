// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type ExecutablePath = fn (&char, &u32) i32

fn ep_reader(get ExecutablePath, expected string) {
	mut buffer := [32768]u8{}
	for _ in 0 .. 256 {
		mut size := u32(buffer.len)
		darwin_set_errno(42)
		assert get(unsafe { &char(&buffer[0]) }, &size) == 0
		assert size == u32(buffer.len) && unsafe { *C.ios_errno_address() } == 42
		assert unsafe { C.memcmp(&buffer[0], expected.str, usize(expected.len)) } == 0
		assert buffer[expected.len] == 0
	}
}

fn ep_cases(get ExecutablePath, expected string) {
	page := u64(C.getpagesize())
	required := u32(expected.len + 1)
	length := (u64(required) + 32 + page - 1) & ~(page - 1)
	mapping := C.mmap(unsafe { nil }, usize(length + page), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != unsafe { voidptr(-1) }
	defer { assert C.munmap(mapping, usize(length + page)) == 0 }
	base := u64(mapping)
	assert C.mprotect(unsafe { voidptr(base + length) }, usize(page), C.PROT_NONE) == 0
	buffer := base + length - u64(required)
	mut words := [u32(0x12345678), 0, 0x87654321]!
	for capacity in [required, required + 32, u32(0xffffffff)]! {
		unsafe { C.memset(mapping, 0xa5, usize(length)) }
		words[1] = capacity
		darwin_set_errno(42)
		assert get(unsafe { &char(buffer) }, unsafe { &words[1] }) == 0
		assert words[1] == capacity && words[0] == 0x12345678 && words[2] == 0x87654321
		assert unsafe { *C.ios_errno_address() } == 42
		assert unsafe { C.memcmp(voidptr(buffer), expected.str, usize(expected.len)) } == 0
		assert unsafe { *(&u8(buffer + u64(required) - 1)) } == 0
		assert unsafe { *(&u8(buffer - 1)) } == 0xa5
	}
	for capacity in [u32(0), 1, required - 1]! {
		for address in [u64(0), base + length]! {
			words[1] = capacity
			darwin_set_errno(42)
			assert get(unsafe { &char(address) }, unsafe { &words[1] }) == -1
			assert words[1] == required && words[0] == 0x12345678 && words[2] == 0x87654321
			assert unsafe { *C.ios_errno_address() } == 42
		}
	}
	// A failure writes exactly four bytes. Success need not write to size at all.
	size_mapping := C.mmap(unsafe { nil }, usize(2 * page), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert size_mapping != unsafe { voidptr(-1) }
	defer { assert C.munmap(size_mapping, usize(2 * page)) == 0 }
	size_base := u64(size_mapping)
	assert C.mprotect(unsafe { voidptr(size_base + page) }, usize(page), C.PROT_NONE) == 0
	size := unsafe { &u32(size_base + page - 4) }
	unsafe { *size = 0 }
	assert get(unsafe { nil }, size) == -1 && unsafe { *size == required }
	assert C.mprotect(size_mapping, usize(page), C.PROT_READ) == 0
	assert get(unsafe { &char(buffer) }, size) == 0 && unsafe { *size == required }
	previous := os.getwd()
	os.chdir('/') or { panic(err) }
	words[1] = required
	assert get(unsafe { &char(buffer) }, unsafe { &words[1] }) == 0
	assert unsafe { C.memcmp(voidptr(buffer), expected.str, usize(expected.len)) } == 0
	os.chdir(previous) or { panic(err) }
	unsafe { previous.free() }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn ep_reader(get, expected) }
	workers.wait()
	unsafe { workers.free() }
}

fn ep_profile(get ExecutablePath, path string, guarded bool) {
	image_runtime_start(macho.Image{}, macho.Layout{}, 0)
	assert !image_runtime.started
	if guarded {
		page := u64(C.getpagesize())
		length := (u64(path.len) + page - 1) & ~(page - 1)
		mapping := C.mmap(unsafe { nil }, usize(length + page), C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		assert mapping != unsafe { voidptr(-1) }
		base := u64(mapping)
		source := base + length - u64(path.len)
		unsafe { C.memcpy(voidptr(source), path.str, usize(path.len)) }
		assert C.mprotect(mapping, usize(length), C.PROT_READ) == 0
		assert C.mprotect(unsafe { voidptr(base + length) }, usize(page), C.PROT_NONE) == 0
		// Borrow a guarded non-terminated view only for this test; the loader's
		// normal path is owned. Clear the view before runtime teardown frees it.
		image_runtime.path = unsafe { tos(&u8(source), path.len) }
		ep_cases(get, path)
		image_runtime.path = ''
		image_runtime_stop()
		assert C.munmap(mapping, usize(length + page)) == 0
	} else {
		image_runtime.path = path.clone()
		ep_cases(get, path)
		image_runtime_stop()
	}
	assert image_runtime == unsafe { nil }
}

fn ep_rejection(mode string) {
	if mode != 'uninitialized' {
		image_runtime_start(macho.Image{}, macho.Layout{}, 0)
		if mode != 'empty' { image_runtime.path = '/opt/ios/Game.app/Game'.clone() }
		if mode == 'retired' { image_runtime_stop() }
		if mode == 'overflow' {
			unsafe { image_runtime.path.free() }
			image_runtime.path = unsafe { tos(&u8(c'x'), int(u64(0xffffffff))) }
		}
	}
	mut buffer := [128]u8{}
	mut size := u32(buffer.len)
	darwin_ns_get_executable_path(if mode == 'buffer' {
		unsafe { nil }
	} else {
		unsafe { &char(&buffer[0]) }
	},
		if mode == 'size' { unsafe { nil } } else { &size })
	assert false, 'invalid executable path state unexpectedly succeeded'
}

fn test_executable_path() {
	mode := os.getenv('VINIX_IOS_EXECUTABLE_PATH_CHILD')
	if mode != '' { ep_rejection(mode) }
	assert image_runtime == unsafe { nil }
	entry := libsystem_symbol('/usr/lib/libSystem.B.dylib', '__NSGetExecutablePath') or { panic(err) }
	assert entry == u64(unsafe { voidptr(darwin_ns_get_executable_path) })
	assert runtime_symbol('/usr/lib/libSystem.B.dylib', '__NSGetExecutablePath') or { panic(err) } == entry
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
		'/System/Library/Frameworks/Foundation.framework/Foundation']! {
		if _ := runtime_symbol(library, '__NSGetExecutablePath') {
			assert false
		}
	}
	get := unsafe { ExecutablePath(voidptr(entry)) }
	long_path := '/Applications/Привет.app/' + 'a'.repeat(8192) + '/FortniteClient-IOS-Shipping'
	ep_profile(get, long_path, true)
	unsafe { long_path.free() }
	ep_profile(get, '/opt/ios/Second.app/новый', false)
	$if macos {
		handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
		assert handle != unsafe { nil }
		native := unsafe { ExecutablePath(C.dlsym(handle, c'_NSGetExecutablePath')) }
		mut required := u32(0)
		assert native(unsafe { nil }, &required) == -1 && required > 1
		mut bytes := []u8{len: int(required)}
		assert native(unsafe { &char(bytes.data) }, &required) == 0
		path := unsafe { tos(bytes.data, int(required) - 1).clone() }
		ep_cases(native, path)
		unsafe {
			path.free()
			bytes.free()
		}
	}
	for rejected in ['uninitialized', 'empty', 'retired', 'size', 'buffer', 'overflow']! {
		mut child := os.new_process(os.executable())
		mut environment := os.environ()
		environment['VINIX_IOS_EXECUTABLE_PATH_CHILD'] = rejected
		child.set_environment(environment)
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait()
		code := child.code
		child.close()
		message := match rejected {
			'size' { 'executable path requires a size pointer' }
			'buffer' { 'executable path requires a sufficient output buffer' }
			'overflow' { 'executable path exceeds the 32-bit buffer size' }
			else { 'executable path requires a configured main image' }
		}
		assert code != 0 && output.contains('iOS: ' + message), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	assert image_runtime == unsafe { nil }
	println('IOS-EXECUTABLE-PATH: scoped signed 32-bit C ABI, guarded read-only source and exact output/size, unchanged successful size/errno, null/protected undersized buffers, long UTF-8 main image paths, stable cwd, eight readers, two retired runtimes and explicit invalid-state rejection')
}
