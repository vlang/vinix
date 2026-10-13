// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <dlfcn.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type EmptyStringCreate = fn () SwiftStringWords
type EmptyStringProbe = fn (u64, u64, &u64)

fn empty_string_check(create EmptyStringCreate, probe EmptyStringProbe) {
	for input in [u64(0), 1, 0xffffffffffffffff]! {
		words := create()
		assert words.first == 0 && words.second == 0xe000000000000000
		mut output := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
		probe(input, u64(unsafe { voidptr(create) }), unsafe { &output[1] })
		assert output[0] == 0x1234 && output[5] == 0x5678
		assert output[1] == 0 && output[2] == 0xe000000000000000
		assert output[3] == 0x5020 && output[4] == 0x5021
	}
}

fn empty_string_lookup() EmptyStringCreate {
	address := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sS2SycfC') or { panic(err) }
	assert address == u64(unsafe { voidptr(swift_string_empty) })
	for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
		if _ := runtime_symbol(library, '_$sS2SycfC') { assert false }
	}
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sS2SycfC') { assert false }
	return unsafe { EmptyStringCreate(voidptr(address)) }
}

fn test_swift_empty_string() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	// Capture both result registers and the Swift context/error registers.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0103f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 56) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { EmptyStringProbe(voidptr(code)) }
	$if macos {
		library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert library != unsafe { nil }
		entry := C.dlsym(library, c'$sS2SycfC'); assert entry != unsafe { nil }
		empty_string_check(unsafe { EmptyStringCreate(entry) }, probe)
		println('IOS-EMPTY-STRING-NATIVE: installed zero-argument constructor returns canonical0/e000000000000000 in both direct and guarded raw x0/x1 calls, ignoring input and preserving x20/x21')
	}
	empty_string_check(empty_string_lookup(), probe)
	for _ in 0 .. 2 {
		objc_start()
		create := empty_string_lookup()
		for _ in 0 .. 10000 {
			words := create(); assert words.first == 0 && words.second == 0xe000000000000000
		}
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_metadata_arena == 0
		empty_string_check(create, probe)
		words := create()
		literal := swift_string_literal(unsafe { nil }, 0, true)
		assert literal.first == words.first && literal.second == words.second
		buffer := swift_string_utf8_cstring(words.first, words.second)
		assert read64(buffer + 16) == 1 && unsafe { *(&u8(buffer + 32)) } == 0
		swift_release(buffer)
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop(); assert ios_runtime.live == 0
		empty_string_check(empty_string_lookup(), probe)
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-EMPTY-STRING: scoped constructor, canonical two-word result and preserved Swift context across guarded calls before/during/after two drained lifetimes; 20000 allocation-free constructions and existing empty-literal/UTF8 ownership integration')
}
