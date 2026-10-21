// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type SetDeallocating = fn (u64)
type DeallocatingProbe = fn (u64, u64, u64, &u64)
type DeallocatingAllocate = fn (u64, u64, u64) u64
type DeallocatingFree = fn (u64, u64, u64)

fn deallocating_header(entry u64, probe DeallocatingProbe, owner u64, span u64, metadata u64, bits u64) {
	C.memset(voidptr(span), 0xa5, 160)
	unsafe { *(&u64(owner)) = metadata; *(&u64(owner + 8)) = bits }
	mut result := [u64(0x1234), 0, 0, 0, 0x5678]!
	probe(owner, 0, entry, unsafe { &result[1] })
	assert result[0] == 0x1234 && result[2] == 0x5020 && result[3] == 0x5021 && result[4] == 0x5678
	assert read64(owner) == metadata && read64(owner + 8) == bits | 0x100000000
	for i in u64(0) .. 160 {
		if span + i >= owner && span + i < owner + 16 { continue }
		assert unsafe { *(&u8(span + i)) } == 0xa5
	}
}

fn deallocating_headers(entry u64, probe DeallocatingProbe, native bool) {
	page := usize(C.getpagesize())
	protected := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert protected != u64(-1)
	bytes := u64(unsafe { C.__builtin_alloca(192) }); span := (bytes + 15) & ~u64(15)
	for metadata in [u64(0), 1, 0x12345678, protected]! {
		for offset in [u64(8), 16, 64, 128]! {
			for _ in 0 .. 128 { deallocating_header(entry, probe, span + offset, span, metadata, 5) }
			if native { deallocating_header(entry, probe, span + offset, span, metadata, 3) }
		}
	}
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
	owner := base + u64(page) - 16
	unsafe { *(&u64(owner)) = protected; *(&u64(owner + 8)) = 5 }
	call := unsafe { SetDeallocating(voidptr(entry)) }; call(owner)
	assert read64(owner) == protected && read64(owner + 8) == 0x100000005
	assert C.munmap(voidptr(base), page * 2) == 0 && C.munmap(voidptr(protected), page) == 0
}

fn deallocating_worker(entry u64) {
	bytes := u64(unsafe { C.__builtin_alloca(48) }); owner := (bytes + 15) & ~u64(15)
	call := unsafe { SetDeallocating(voidptr(entry)) }
	for _ in 0 .. 1000 {
		assert swift_stack_initialize(0, owner) == owner
		call(owner)
		assert read64(owner) == 0 && read64(owner + 8) == 0x100000005
	}
}

fn deallocating_heap(entry u64, allocate DeallocatingAllocate, deallocate DeallocatingFree, metadata u64, native bool) {
	owner := allocate(metadata, 32, 15); original_metadata := read64(owner)
	unsafe { *(&u64(owner + 16)) = 0x12345678; *(&u64(owner + 24)) = 0x87654321 }
	call := unsafe { SetDeallocating(voidptr(entry)) }; call(owner)
	assert read64(owner) == original_metadata && read64(owner + 8) == 0x100000003
	assert read64(owner + 16) == 0x12345678 && read64(owner + 24) == 0x87654321
	if !native {
		assert ios_runtime.swift_heap[owner].deiniting
		if _ := swift_set_deallocating_checked(owner) { assert false }
		if _ := swift_buffer_refs(owner, 1) { assert false }
		if _ := swift_buffer_refs(owner, -1) { assert false }
		if _ := swift_heap_deallocate_checked(owner, 32, 15, true) { assert false }
	}
	// Metadata points at a trapping destructor. setDeallocating must not call it.
	deallocate(owner, 32, 15)
}

fn deallocating_reject(owner u64) {
	if _ := swift_set_deallocating_checked(owner) { assert false, 'invalid transition accepted' }
}

fn deallocating_suite(probe DeallocatingProbe, metadata u64) {
	entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_setDeallocating') or { panic(err) }
	before := ios_runtime.swift_heap_sequence
	deallocating_headers(entry, probe, false)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn deallocating_worker(entry) }; workers.wait()
	assert ios_runtime.swift_heap_sequence == before && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
	for _ in 0 .. 128 { deallocating_heap(entry, swift_heap_allocate, swift_heap_deallocate, metadata, false) }
	shared := swift_heap_allocate(metadata, 32, 15)
	assert swift_buffer_refs(shared, 1) or { panic(err) } == 2
	deallocating_reject(shared)
	assert read64(shared + 8) == 0x200000003 && !ios_runtime.swift_heap[shared].deiniting
	assert swift_buffer_refs(shared, -1) or { panic(err) } == 1
	// A registered heap object must never take the borrowed-stack path.
	unsafe { *(&u64(shared + 8)) = 5 }
	deallocating_reject(shared)
	assert read64(shared + 8) == 5 && !ios_runtime.swift_heap[shared].deiniting
	unsafe { *(&u64(shared + 8)) = 3 }
	swift_heap_deallocate_checked(shared, 32, 15, true) or { panic(err) }
	managed := swift_string_utf8(0, 0xe000000000000000) or { panic(err) }
	for bits in [u64(3), 5, 0x200000003]! {
		unsafe { *(&u64(managed + 8)) = bits }
		deallocating_reject(managed)
		assert read64(managed + 8) == bits && ios_runtime.swift_buffers[managed] == 1
	}
	unsafe { *(&u64(managed + 8)) = 3 }
	assert swift_buffer_refs(managed, -1) or { panic(err) } == 0
	for owner in [u64(0), 1, 7, ~u64(0) - 7, ~u64(0) - 15]! { deallocating_reject(owner) }
	mut header := [u64(0), 0, 0x12345678]!
	for bits in [u64(0), 1, 3, 7, 0x200000005, 0x100000005, 0x8000000000000005, ~u64(0)]! {
		header[1] = bits; deallocating_reject(u64(unsafe { &header[0] })); assert header == [u64(0), bits, 0x12345678]!
	}
	header[1] = 5; owner := u64(unsafe { &header[0] }); swift_set_deallocating(owner); deallocating_reject(owner)
	if _ := swift_buffer_refs(owner, 1) { assert false }
	if _ := swift_heap_deallocate_checked(owner, 24, 7, false) { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_setDeallocating') { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_setDeallocating') { assert false }
	assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arc_code == 0
}

fn test_swift_set_deallocating() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	for i, word in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0203f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), word) }
	write32(code + 64, 0xd4200000) // BRK: no automatic destructor invocation.
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 68)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert words != u64(-1)
	metadata := words + 24
	unsafe { *(&u64(metadata)) = 0x400; *(&u64(metadata - 16)) = code + 64 }
	assert C.mprotect(voidptr(words), page, C.PROT_READ) == 0
	probe := unsafe { DeallocatingProbe(voidptr(code)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, c'swift_setDeallocating')); assert entry != 0
		allocate := unsafe { DeallocatingAllocate(C.dlsym(lib, c'swift_allocObject')) }
		deallocate := unsafe { DeallocatingFree(C.dlsym(lib, c'swift_deallocObject')) }
		assert voidptr(allocate) != unsafe { nil } && voidptr(deallocate) != unsafe { nil }
		deallocating_headers(entry, probe, true)
		for _ in 0 .. 128 { deallocating_heap(entry, allocate, deallocate, metadata, true) }
		println('IOS-SET-DEALLOCATING-NATIVE: ordinary one-argument void ABI, unique heap3 and stack5 transition to deiniting, exact header/property preservation, protected metadata and guarded page end, no destructor/free, manual heap deallocation, preserved x20/x21')
	}
	entry := u64(unsafe { voidptr(swift_set_deallocating) })
	deallocating_headers(entry, probe, false)
	for _ in 0 .. 2 { objc_start(); deallocating_suite(probe, metadata); objc_stop(); assert ios_runtime.swift_heap.len == 0 }
	deallocating_headers(entry, probe, false)
	assert C.munmap(voidptr(words), page) == 0 && C.munmap(voidptr(code), page) == 0
	println('IOS-SET-DEALLOCATING: exact Core-only transition, borrowed stack5 without registration/allocation and registered heap3 with coherent deiniting state, caller-owned destruction/deallocation, no metadata reads/destructor/ARC thunk, eight private frame workers, invalid/shared/deiniting/side-table states rejected unchanged, two drained runtime lifetimes')
}
