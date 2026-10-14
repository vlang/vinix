// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type StackInitialize = fn (u64, u64) u64
type StackProbe = fn (u64, u64, u64, &u64)
type StackSign = fn (u64, u64) u64

fn stack_header_case(entry u64, probe StackProbe, sign StackSign, metadata u64, storage u64, span u64, native bool) {
	C.memset(voidptr(span), 0xa5, 160)
	mut result := [u64(0x1234), 0, 0, 0, 0x5678]!
	probe(metadata, storage, entry, unsafe { &result[1] })
	assert result == [u64(0x1234), storage, 0x5020, 0x5021, 0x5678]!
	mut expected := metadata
	$if macos { if native && metadata != 0 { expected = sign(metadata, storage | (u64(27361) << 48)) } }
	assert read64(storage) == expected && read64(storage + 8) == 5
	for i in u64(0) .. 160 {
		if span + i >= storage && span + i < storage + 16 { continue }
		assert unsafe { *(&u8(span + i)) } == 0xa5
	}
}

fn stack_cases(entry u64, probe StackProbe, sign StackSign, native bool) {
	page := usize(C.getpagesize())
	protected := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert protected != u64(-1)
	span := u64(unsafe { C.__builtin_alloca(192) }); aligned := (span + 15) & ~u64(15)
	// Metadata has no readable-span requirement for this initializer.
	for metadata in [u64(0), 1, 8, 0x12345678, protected]! {
		for offset in [u64(8), 16, 64, 128]! {
			for _ in 0 .. 128 { stack_header_case(entry, probe, sign, metadata, aligned + offset, aligned, native) }
		}
	}
	// The writable header can end exactly at a protected following page.
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
	initialize := unsafe { StackInitialize(voidptr(entry)) }
	storage := base + u64(page) - 16
	C.memset(voidptr(storage - 16), 0xa5, 32)
	assert initialize(protected, storage) == storage && read64(storage + 8) == 5
	for i in u64(0) .. 16 { assert unsafe { *(&u8(storage - 16 + i)) } == 0xa5 }
	assert C.munmap(voidptr(base), page * 2) == 0 && C.munmap(voidptr(protected), page) == 0
}

fn stack_worker(entry u64) {
	initialize := unsafe { StackInitialize(voidptr(entry)) }
	bytes := u64(unsafe { C.__builtin_alloca(48) }); storage := (bytes + 15) & ~u64(15)
	for _ in 0 .. 1000 { assert initialize(0, storage) == storage && read64(storage) == 0 && read64(storage + 8) == 5 }
}

fn stack_reject(storage u64) {
	if _ := swift_stack_initialize_checked(0, storage) { assert false, 'invalid stack header storage accepted' }
}

fn stack_suite(probe StackProbe, sign StackSign) {
	entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_initStackObject') or { panic(err) }
	before := ios_runtime.swift_heap_sequence
	stack_cases(entry, probe, sign, false)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn stack_worker(entry) }; workers.wait()
	assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_heap_sequence == before && ios_runtime.live == 0
	for invalid in [u64(0), 1, 7, ~u64(0) - 7, ~u64(0) - 15]! { stack_reject(invalid) }
	page := usize(C.getpagesize()); storage := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert storage != u64(-1)
	assert swift_stack_initialize(0, storage) == storage
	// No heap provenance is invented for borrowed frame memory. Existing ARC,
	// object-type and deallocation routes reject it before reading its header.
	if _ := swift_buffer_refs(storage, 1) { assert false }
	if _ := swift_buffer_refs(storage, -1) { assert false }
	if _ := swift_heap_deallocate_checked(storage, 16, 7, false) { assert false }
	if _ := swift_heap_deallocate_checked(storage, 16, 7, true) { assert false }
	if _ := swift_object_type_query(storage) { assert false }
	assert read64(storage) == 0 && read64(storage + 8) == 5
	assert C.munmap(voidptr(storage), page) == 0
	if _ := swift_buffer_refs(storage, 1) { assert false }
	if _ := swift_heap_deallocate_checked(storage, 16, 7, false) { assert false }
	if _ := swift_object_type_query(storage) { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_initStackObject') { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_initStackObject') { assert false }
}

fn test_swift_stack_initialization() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	for i, word in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0203f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), word) }
	write32(code + 64, 0xdac10820); write32(code + 68, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 72)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { StackProbe(voidptr(code)) }; sign := unsafe { StackSign(voidptr(code + 64)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, c'swift_initStackObject')); assert entry != 0
		stack_cases(entry, probe, sign, true)
		println('IOS-STACK-NATIVE: two-argument pointer result, exact metadata/PAC and refcount5 header writes, nil/arbitrary/protected metadata without reads, preserved property/guard bytes, multiple header offsets and guarded page end, repeated initialization with x20/x21 preserved')
	}
	// Header initialization has no runtime, registry or metadata dependency.
	stack_cases(u64(unsafe { voidptr(swift_stack_initialize) }), probe, sign, false)
	for _ in 0 .. 2 { objc_start(); stack_suite(probe, sign); objc_stop(); assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arc_code == 0 }
	stack_cases(u64(unsafe { voidptr(swift_stack_initialize) }), probe, sign, false)
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-STACK: exact Core-only borrowed header initialization, raw metadata and refcount5, untouched caller properties, no allocation/registry/ARC/destructor, runtime-independent calls, protected metadata/page boundaries, eight private frame workers, rejected stack ARC/type/deallocation before and after caller unmapping, two empty runtime lifetimes')
}
