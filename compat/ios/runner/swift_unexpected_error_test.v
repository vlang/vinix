// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.pipe(&i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.mincore(voidptr, usize, &u8) i32
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFRelease(voidptr)

type UnexpectedErrorCall = fn (u64, u64, u64, u64, u64)
type UnexpectedErrorSignal = fn (i32, voidptr) voidptr

fn unexpected_error_trapped(number i32) { C._exit(100 + number) }
fn unexpected_error_returns(_owner u64, _file u64, _count u64, _ascii u64, _line u64) {}
fn unexpected_error_read(descriptor i32) string {
	mut bytes := []u8{}
	for {
		mut buffer := [256]u8{}
		count := C.read(descriptor, unsafe { &buffer[0] }, 256)
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0
		bytes << buffer[..int(count)]
	}
	C.close(descriptor)
	return bytes.bytestr()
}
fn unexpected_error_output(entry u64, owner u64, file u64, count u64, ascii u64, line u64, broken bool, expected_status i32) string {
	mut descriptors := [2]i32{}
	assert C.pipe(unsafe { &descriptors[0] }) == 0
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		C.close(descriptors[0])
		assert C.dup2(descriptors[1], 2) == 2
		C.close(descriptors[1])
		if broken { C.close(2) }
		signal := unsafe { UnexpectedErrorSignal(voidptr(C.signal)) }
		signal(i32(C.SIGTRAP), unsafe { voidptr(unexpected_error_trapped) })
		signal(i32(C.SIGSEGV), unsafe { voidptr(unexpected_error_trapped) })
		call := unsafe { UnexpectedErrorCall(voidptr(entry)) }
		call(owner, file, count, ascii, line)
		C._exit(99) // Positive control; Never must not reach this return.
	}
	C.close(descriptors[1])
	output := unexpected_error_read(descriptors[0])
	mut status := i32(0)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child
	assert status == expected_status, 'wrong unexpected error termination: ' + status.str()
	return output
}
fn unexpected_error_text(native bool, value string) u64 {
	$if macos { if native { return u64(C.CFStringCreateWithBytes(unsafe { nil }, value.str, i64(value.len), 0x08000100, false)) } }
	return owned_string(value)
}
fn unexpected_error_drop(native bool, owner u64) {
	$if macos { if native { C.CFRelease(unsafe { voidptr(owner) }); return } }
	objc_release(owner)
}
fn unexpected_error_owner(native bool, described bool) u64 {
	domain := unexpected_error_text(native, 'Fortnite π')
	mut info := u64(0)
	if described {
		$if macos { if native { info = u64(C.CFDictionaryCreateMutable(unsafe { nil }, 0, unsafe { &C.kCFTypeDictionaryKeyCallBacks }, unsafe { &C.kCFTypeDictionaryValueCallBacks })) } }
		if !native { info = cf_dictionary_mutable(0, 0, cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'), cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks')) }
		key := unexpected_error_text(native, 'NSLocalizedDescription')
		value := unexpected_error_text(native, 'Description π')
		$if macos { if native { C.CFDictionarySetValue(unsafe { voidptr(info) }, unsafe { voidptr(key) }, unsafe { voidptr(value) }) } }
		if !native { cf_dictionary_set(info, key, value) }
		unexpected_error_drop(native, key); unexpected_error_drop(native, value)
	}
	mut owner := u64(0)
	$if macos { if native { owner = u64(C.CFErrorCreate(unsafe { nil }, unsafe { voidptr(domain) }, -7, unsafe { voidptr(info) })) } }
	if !native {
		owner = objc_allocate(cf_error_type_id())
		mut header := obj_header(owner)
		header.number = -7; header.fields[0] = objc_retain(domain); header.fields[1] = objc_retain(info)
	}
	unexpected_error_drop(native, domain)
	if info != 0 { unexpected_error_drop(native, info) }
	return owner
}
fn unexpected_error_cases(entry u64, native bool, boundary u64) {
	for described in [false, true]! {
		owner := unexpected_error_owner(native, described)
		description := if described { 'Description π" UserInfo={NSLocalizedDescription=Description π}' } else { '(null)"' }
		message := "Fatal error: 'try!' expression unexpectedly raised an error: Error Domain=Fortnite π Code=-7 \"" + description + '\n'
		for file in ['Fortnite.swift', 'Fortnite π.swift', '', 'Fort\x00nite.swift']! {
			address := boundary - u64(file.len)
			if file.len != 0 { unsafe { C.memcpy(voidptr(address), file.str, usize(file.len)) } }
			visible := file.all_before('\x00')
			for line in [u64(0), 42, 0xffffffff]! {
				for ascii in [u64(0), 1]! {
					assert unexpected_error_output(entry, owner, address, u64(file.len), ascii, line, false, 105 * 256) == visible + ':' + line.str() + ': ' + message
				}
			}
		}
		assert unexpected_error_output(entry, owner, u64(c'closed.swift'), 12, 1, 7, true, 105 * 256) == ''
		unexpected_error_drop(native, owner)
	}
}
fn unexpected_error_resolver() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_unexpectedError') or { panic(err) }
}

fn test_swift_unexpected_error() {
	$if !arm64 { return }
	assert unexpected_error_output(u64(unsafe { voidptr(unexpected_error_returns) }), 0, 0, 0, 0, 0, false, 99 * 256) == ''
	page := usize(C.getpagesize())
	memory := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert memory != unsafe { voidptr(-1) }
	boundary := u64(memory) + u64(page)
	assert C.mprotect(unsafe { voidptr(boundary) }, page, C.PROT_NONE) == 0
	defer { assert C.munmap(memory, page * 2) == 0 }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		assert C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', C.RTLD_NOW) != unsafe { nil }
		entry := u64(C.dlsym(core, c'swift_unexpectedError'))
		assert entry != 0
		unexpected_error_cases(entry, true, boundary)
		println('IOS-UNEXPECTED-ERROR-NATIVE: five-register ABI, concrete CFError diagnostics, bounded/NUL/Unicode filenames, ASCII bits, line extrema, closed stderr and actual BRK/SIGTRAP')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn unexpected_error_resolver() }
		resolved := workers.wait()
		for address in resolved { assert address != 0 && address == resolved[0] }
		arena := ios_runtime.swift_fatal_code
		assert resolved[0] == arena + 224
		assert read32(resolved[0] + 16) == 0xd4200020 && read32(resolved[0] + 20) == 0x17ffffff
		unexpected_error_cases(resolved[0], false, boundary)
		for value in [u64(0), u64(1), boundary, ~u64(0)]! {
			assert unexpected_error_output(resolved[0], value, boundary, 0, 1, 7, false, 105 * 256) == 'Vinix Swift runtime: Fatal error: unexpected error reflection is not implemented for this value\n'
		}
		for pair in [[u64(0), 1, 0]!, [boundary, u64(0x80000000), 0]!, [boundary, u64(0), 0x100000000]!]! {
			owner := unexpected_error_owner(false, false)
			assert unexpected_error_output(resolved[0], owner, pair[0], pair[1], 1, pair[2], false, 105 * 256) == 'Vinix Swift runtime: Fatal error: invalid assertion arguments\n'
			objc_release(owner)
		}
		// Exercise the returning reporter in this process to check both consumed
		// CFError ownership and temporary String cleanup before the entry traps.
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		saved := C.dup(2); assert saved >= 0
		assert C.dup2(descriptors[1], 2) == 2; C.close(descriptors[1])
		owner := unexpected_error_owner(false, true)
		swift_unexpected_error_report(owner, u64(c'owned.swift'), 11, 1, 42)
		assert C.dup2(saved, 2) == 2; C.close(saved)
		assert unexpected_error_read(descriptors[0]).starts_with("owned.swift:42: Fatal error: 'try!' expression unexpectedly raised an error: ")
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_unexpectedErrorExtra') == none
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', '_swift_unexpectedError') == none
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop()
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1 }
		$else { mut resident := u8(0); assert C.mincore(unsafe { voidptr(arena) }, page, unsafe { &resident }) == -1 }
	}
	println('IOS-UNEXPECTED-ERROR: exact CFError diagnostics and Never trap, protected boundary/opaque rejection, consumed ownership, eight cold publishers and two drained/unmapped assertion arenas')
}
