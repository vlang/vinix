// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFDictionary.h>
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.object_getClass(voidptr) voidptr
type IsaMaskDecode = fn (u64, &u64) u64

fn isa_mask_native(decode IsaMaskDecode) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert lib != unsafe { nil }
		cell := u64(C.dlsym(lib, c'swift_isaMask')); assert cell != 0 && cell & 7 == 0
		mask := read64(cell); assert mask != 0 && mask & 7 == 0
		mut got := cell
		owner := C.CFDictionaryCreateMutable(unsafe { nil }, 0, unsafe { nil }, unsafe { nil })
		assert owner != unsafe { nil }
		refs := C.CFGetRetainCount(owner); header := read64(u64(owner))
		for _ in 0 .. 256 { assert decode(u64(owner), unsafe { &got }) == u64(C.object_getClass(owner)) }
		assert read64(cell) == mask && read64(u64(owner)) == header && C.CFGetRetainCount(owner) == refs
		C.CFRelease(owner)
		println('NATIVE-ISA-MASK: exported aligned uintptr_t data cell, GOT address/load/AND decodes native Objective-C class without changing header or ownership')
	}
}

fn isa_mask_worker(cell u64, decode IsaMaskDecode) {
	mut got := cell
	mut header := [u64(0x0000ffff12345678), 3]!
	for _ in 0 .. 1000 {
		assert swift_isa_mask_address() == cell && decode(u64(unsafe { &header[0] }), unsafe { &got }) == header[0]
	}
	assert header == [u64(0x0000ffff12345678), 3]!
}

fn isa_mask_suite(cell u64, decode IsaMaskDecode, dispatch IsaMaskDecode, method u64) {
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_isaMask') or { panic(err) } == cell
	assert cell & 7 == 0 && read64(cell) == ~u64(7)
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_isaMask') { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_isaMask') { assert false }
	mut got := cell
	// Full-width addresses must survive even when outside Darwin's packed-isa
	// range. Decode never dereferences the resulting synthetic metadata.
	mut header := [u64(0), 3]!
	for bits in [u64(0), 8, 0x1000000000, 0x0000ffff12345678, 0x007fffff12345678, 0xffff000012345678]! {
		header[0] = bits
		assert decode(u64(unsafe { &header[0] }), unsafe { &got }) == bits
		assert header == [bits, u64(3)]!
	}
	// Borrowed Swift frame objects use the same raw metadata pointer. The
	// fixture vtable slot and x20 dispatch reproduce Fortnite's five consumers.
	mut metadata := [16]u64{}
	metadata[12] = method
	cls := u64(unsafe { &metadata[0] }); assert cls & 7 == 0
	mut stack := [u64(0), 0, 0x123456789abcdef0]!
	owner := u64(unsafe { &stack[0] })
	assert swift_stack_initialize(cls, owner) == owner
	for _ in 0 .. 256 { assert decode(owner, unsafe { &got }) == cls && dispatch(owner, unsafe { &got }) == stack[2] }
	assert stack == [cls, u64(5), 0x123456789abcdef0]!
	before := if ios_runtime != unsafe { nil } { ios_runtime.swift_heap_sequence } else { u64(0) }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn isa_mask_worker(cell, decode) }; workers.wait()
	if ios_runtime != unsafe { nil } {
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_heap_sequence == before && ios_runtime.live == 0
	}
}

fn test_swift_isa_mask() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	// A C-callable wrapper saves x20, installs Swift self and calls the actual
	// load/AND/vtable consumer. The virtual target reads the payload via x20.
	for i, word in [u32(0xa9be7bfd), 0xf9000bf4, 0xaa0003f4, 0x9400000d, 0xf9400bf4, 0xa8c27bfd, 0xd65f03c0]! { write32(code + u64(i * 4), word) }
	for i, word in [u32(0xf9400288), 0xf9400029, 0xf9400129, 0x8a080128, 0xf9403102, 0xd61f0040]! { write32(code + 64 + u64(i * 4), word) }
	write32(code + 128, 0xf9400a80); write32(code + 132, 0xd65f03c0)
	for i, word in [u32(0xf9400008), 0xf9400029, 0xf9400129, 0x8a080120, 0xd65f03c0]! { write32(code + 192 + u64(i * 4), word) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 212)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	decode := unsafe { IsaMaskDecode(voidptr(code + 192)) }; dispatch := unsafe { IsaMaskDecode(voidptr(code)) }
	isa_mask_native(decode)
	cell := swift_isa_mask_address()
	isa_mask_suite(cell, decode, dispatch, code + 128)
	for _ in 0 .. 2 {
		objc_start(); isa_mask_suite(cell, decode, dispatch, code + 128)
		mut got := cell
		cls := ios_runtime.names['NSObject']; owner := objc_allocate(cls)
		assert decode(owner, unsafe { &got }) == cls && obj_header(owner).refs == 1
		objc_release(owner)
		// Use a real registered Swift heap header and deallocate its uninitialized
		// storage without requiring a destructor call from synthetic metadata.
		mut metadata := [u64(code + 128), 0, 0x400]!
		metadata_address := u64(unsafe { &metadata[2] })
		heap := swift_heap_allocate(metadata_address, 32, 15)
		assert decode(heap, unsafe { &got }) == metadata_address && read64(heap + 8) == 3
		swift_heap_deallocate_uninitialized(heap, 32, 15)
		objc_stop(); assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arc_code == 0
		assert swift_isa_mask_address() == cell && read64(cell) == ~u64(7)
	}
	isa_mask_suite(cell, decode, dispatch, code + 128)
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-ISA-MASK: Core-only stable 64-bit data cell, full-address raw isa decoding, GOT double load and x20 vtable dispatch, borrowed Swift stack/registered heap/Objective-C headers, eight concurrent readers, no ARC/header changes, runtime-independent address across two empty lifetimes')
}
