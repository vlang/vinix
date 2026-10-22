// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.pipe(&i32) i32
fn C.dup2(i32, i32) i32

// A deleted slot may have any method signature. Poison all argument registers
// to prove that this no-argument runtime entry never inspects method inputs.
type DeletedMethodCall = fn (u64, u64, u64, u64, u64, u64, u64, u64)
type DeletedMethodSignal = fn (i32, voidptr) voidptr

fn deleted_method_trapped(number i32) { C._exit(100 + number) }
fn deleted_method_returns(_a u64, _b u64, _c u64, _d u64, _e u64, _f u64, _g u64, _h u64) {}

fn deleted_method_output(entry u64, poison u64, closed bool, expected_status i32) string {
	mut descriptors := [2]i32{}
	assert C.pipe(unsafe { &descriptors[0] }) == 0
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		C.close(descriptors[0])
		assert C.dup2(descriptors[1], 2) == 2
		C.close(descriptors[1])
		if closed { C.close(2) }
		signal := unsafe { DeletedMethodSignal(voidptr(C.signal)) }
		signal(i32(C.SIGABRT), unsafe { voidptr(deleted_method_trapped) })
		signal(i32(C.SIGTRAP), unsafe { voidptr(deleted_method_trapped) })
		signal(i32(C.SIGSEGV), unsafe { voidptr(deleted_method_trapped) })
		call := unsafe { DeletedMethodCall(voidptr(entry)) }
		call(poison, poison, poison, poison, poison, poison, poison, poison)
		C._exit(99) // Positive control: a returning entry reaches this status.
	}
	C.close(descriptors[1])
	mut bytes := []u8{}
	for {
		mut buffer := [128]u8{}
		count := C.read(descriptors[0], unsafe { &buffer[0] }, 128)
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0
		bytes << buffer[..int(count)]
	}
	C.close(descriptors[0])
	mut status := i32(0)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child
	assert status == expected_status, 'wrong deleted method termination: ' + status.str()
	return bytes.bytestr()
}

fn deleted_method_cases(entry u64, inaccessible u64) {
	for poison in [u64(0), 1, inaccessible, ~u64(0)]! {
		assert deleted_method_output(entry, poison, false, 106 * 256) == 'Fatal error: Call of deleted method\n'
		assert deleted_method_output(entry, poison, true, 106 * 256) == ''
	}
}

fn deleted_method_resolver() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_deletedMethodError') or { panic(err) }
}

fn test_swift_deleted_method() {
	$if !arm64 { return }
	assert deleted_method_output(u64(unsafe { voidptr(deleted_method_returns) }), 0, false, 99 * 256) == ''
	page := usize(C.getpagesize())
	memory := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert memory != unsafe { voidptr(-1) }
	defer { assert C.munmap(memory, page) == 0 }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		entry := u64(C.dlsym(core, c'swift_deletedMethodError'))
		assert entry != 0
		deleted_method_cases(entry, u64(memory))
		println('IOS-SWIFT-DELETED-METHOD-NATIVE: exact diagnostic, ignored method arguments, closed stderr and actual SIGABRT')
	}
	mut previous := u64(0)
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn deleted_method_resolver() }
		resolved := workers.wait()
		for entry in resolved { assert entry != 0 && entry == resolved[0] }
		if previous != 0 { assert resolved[0] == previous }
		previous = resolved[0]
		assert ios_runtime.swift_fatal_code == 0
		deleted_method_cases(resolved[0], u64(memory))
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_deletedMethodErrorExtra') == none
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_deletedmethodError') == none
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', '_swift_deletedMethodError') == none
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_fatal_code == 0
	}
	println('IOS-SWIFT-DELETED-METHOD: exact diagnostic and SIGABRT, protected/opaque arguments, closed stderr, eight concurrent resolvers, two drained lifetimes and no assertion arena')
}
