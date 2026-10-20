// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type KcmAccess = fn (u64, u64, u64) SwiftAssociatedMetadata
type KcmCopy = fn (u64, u64, u64) u64
type KcmDestroy = fn (u64, u64)
type KcmGet = fn (u64, u32, u64) u32
type KcmStore = fn (u64, u32, u32, u64)
type KcmAllocate = fn (i64, u64) SwiftArrayAllocation
type KcmRetain = fn (u64) u64
type KcmRelease = fn (u64)
type KcmFactory = fn (u64, u64, u64) u64

fn kcm_relative(p u64) u64 { return u64(i64(p) + i64(i32(read32(p)))) }
fn kcm_function(table u64, slot int) u64 { return read64(table + u64(slot * 8)) & 0x0000ffffffffffff }
fn kcm_metadata(access KcmAccess, key u64, table u64) u64 {
	m := access(0, key, table).metadata
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
		r := access(request, key, table);assert r.metadata == m && r.state == 0
	}
	assert read64(m) == 0x200 && read64(m + 16) == key && read64(m + 24) == table && read32(m + 32) == 0
	d := read64(m + 8);w := read64(m - 8)
	assert read32(d) & 0xffff == 0xd1 && read32(d + 20) == 1 && read32(d + 24) == 4
	assert unsafe { (&char(kcm_relative(d + 8))).vstring() } == 'KeyedDecodingContainer'
	assert read32(d + 36) == 0x10001 && read32(d + 40) == 2 && read32(d + 44) == 0x80 && read32(d + 48) == 0x80
	assert read64(w + 64) == 8 && read64(w + 72) == 8 && read32(w + 80) == 0x02010007 && read32(w + 84) == 0x7fffffff
	return m
}
fn kcm_enums(metadata u64) []u8 {
	w := read64(metadata - 8)
	get := unsafe { KcmGet(voidptr(kcm_function(w, 6))) };store := unsafe { KcmStore(voidptr(kcm_function(w, 7))) }
	page := usize(C.getpagesize());region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1) && C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	mut snapshot := []u8{}
	for cases in [u32(0), 1, 17, 0x7fffffff, 0x80000000, 0xffffffff]! {
		length := 8 + int(cases > 0x7fffffff)
		for tag in [u32(0), 1, 17, 0x7fffffff, 0x80000000, 0xffffffff]! {
			if tag > cases { continue }
			value := region + u64(page * 2) - u64(length)
			C.memset(voidptr(value), 0xa5, usize(length));store(value, tag, cases, metadata)
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ) == 0
			assert get(value, cases, metadata) == tag
			for i in 0 .. length { snapshot << unsafe { *(&u8(value + u64(i))) } }
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
		}
	}
	assert C.munmap(voidptr(region), page * 3) == 0
	return snapshot
}
fn kcm_ownership(metadata u64, allocate KcmAllocate, retain KcmRetain, release KcmRelease, integer u64) {
	w := read64(metadata - 8);owner := allocate(1, integer).owner
	mut source := [u64(0xCAFE), owner, 0xBEEF]!
	mut destination := [u64(0xCAFE), 0, 0xBEEF]!
	src := u64(unsafe { &source[1] });dst := u64(unsafe { &destination[1] })
	destroy := unsafe { KcmDestroy(voidptr(kcm_function(w, 1))) }
	for slot in [0, 2]! {
		initialize := unsafe { KcmCopy(voidptr(kcm_function(w, slot))) }
		assert initialize(dst, src, metadata) == dst && destination[1] == owner && read64(owner + 8) == 0x200000003
		destroy(dst, metadata);assert destination[1] == owner && read64(owner + 8) == 3
	}
	for slot in [3, 5]! {
		destination[1] = allocate(1, integer).owner
		if slot == 5 { retain(owner) }
		assign := unsafe { KcmCopy(voidptr(kcm_function(w, slot))) }
		assert assign(dst, src, metadata) == dst && read64(owner + 8) == 0x200000003
		destroy(dst, metadata);assert read64(owner + 8) == 3
	}
	copy_self := unsafe { KcmCopy(voidptr(kcm_function(w, 3))) };assert copy_self(src, src, metadata) == src && read64(owner + 8) == 3
	take := unsafe { KcmCopy(voidptr(kcm_function(w, 4))) };assert take(dst, src, metadata) == dst && source[1] == owner
	retain(owner);take_self := unsafe { KcmCopy(voidptr(kcm_function(w, 5))) };assert take_self(dst, dst, metadata) == dst && read64(owner + 8) == 3
	assert source[0] == 0xCAFE && source[2] == 0xBEEF && destination[0] == 0xCAFE && destination[2] == 0xBEEF
	release(owner)
}
fn kcm_worker(key u64, witness u64) u64 {
	mut result := u64(0)
	for _ in 0 .. 128 { result = swift_keyed_container_metadata_access(0x1ff, key, witness).metadata }
	return result
}
struct KcmReentry {
	destination u64
	expected u64
	key u64
	witness u64
	metadata u64
mut:
	calls int
}
fn kcm_reentry_reader(state &KcmReentry) {
	assert read64(state.destination) == state.expected
	assert kcm_worker(state.key, state.witness) == state.metadata
	mut copy := u64(0)
	swift_keyed_container_copy(u64(unsafe { &copy }), state.destination, state.metadata)
	swift_keyed_container_destroy(u64(unsafe { &copy }), state.metadata)
}
fn kcm_reentry_destroy(owner u64) {
	mut state := unsafe { &KcmReentry(read64(owner + 16)) }
	worker := spawn kcm_reentry_reader(state);worker.wait();state.calls++
	swift_heap_deallocate(owner, 32, 7)
}
fn kcm_reentry(metadata u64, key u64, witness u64) {
	page := usize(C.getpagesize());code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert code != u64(-1)
	write32(code, 0xaa1403e0);write32(code + 4, 0x58000070);write32(code + 8, 0xd61f0200);write32(code + 12, 0xd503201f)
	unsafe { *(&u64(code + 16)) = u64(voidptr(kcm_reentry_destroy));*(&u64(code + 112)) = code;*(&u64(code + 128)) = 0x400 }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 24));assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	for take in [false, true]! {
		mut source := swift_array_allocate(1, swift_integer_metadata()).owner
		mut destination := swift_heap_allocate(code + 128, 32, 7)
		state := unsafe { &KcmReentry(C.__builtin_alloca(sizeof(KcmReentry))) }
		unsafe { *state = KcmReentry{u64(&destination), source, key, witness, metadata, 0};*(&u64(destination + 16)) = u64(state) }
		if take { swift_retain(source);swift_keyed_container_assign_take(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) }
		else { swift_keyed_container_assign_copy(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) }
		assert state.calls == 1 && destination == source
		swift_release(source);swift_release(destination)
	}
	assert C.munmap(voidptr(code), page) == 0
}
fn test_swift_keyed_container_metadata() {
	page := usize(C.getpagesize());guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert guard != u64(-1)
	mut native_snapshot := []u8{}
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert core != unsafe { nil }
		access := unsafe { KcmAccess(C.dlsym(core, c'$ss22KeyedDecodingContainerVMa')) }
		integer := u64(C.dlsym(core, c'$sSiN'))
		metadata := kcm_metadata(access, integer, guard + 8)
		kcm_ownership(metadata, unsafe { KcmAllocate(C.dlsym(core, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) }, unsafe { KcmRetain(C.dlsym(core, c'swift_retain')) }, unsafe { KcmRelease(C.dlsym(core, c'swift_release')) }, integer)
		native_snapshot = kcm_enums(metadata)
		println('NATIVE-KEYED-CONTAINER-METADATA: complete request responses, generic descriptor and box layout; eight native-reference witnesses, exact ownership and guarded enum bytes')
	}
	assert swift_keyed_container_metadata_symbol('_$ss22KeyedDecodingContainerVMa') == none
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn kcm_worker(guard, guard + 8) }
		values := publishers.wait();metadata := values[0]
		for m in values { assert m == metadata };unsafe { publishers.free();values.free() }
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss22KeyedDecodingContainerVMa') or { panic(err) }
		access := unsafe { KcmAccess(voidptr(entry)) };assert kcm_metadata(access, guard, guard + 8) == metadata
		d := read64(metadata + 8)
		assert kcm_relative(d + 12) == entry
		assert kcm_metadata(access, guard + 16, guard + 8) != metadata && kcm_metadata(access, guard, guard + 24) != metadata
		mut arguments := [guard, guard + 8]!
		pattern := kcm_relative(d + 32);factory := unsafe { KcmFactory(voidptr(kcm_relative(pattern))) }
		assert factory(d, u64(unsafe { &arguments[0] }), pattern) == metadata
		kcm_ownership(metadata, swift_array_allocate, swift_retain, swift_release, swift_integer_metadata())
		snapshot := kcm_enums(metadata);if native_snapshot.len != 0 { assert snapshot == native_snapshot }
		kcm_reentry(metadata, guard, guard + 8)
		for bad in [[u64(0), guard]!, [guard, u64(0)]!, [guard + 1, guard]!, [guard, guard + 1]!]! {
			if _ := swift_keyed_container_metadata_checked(0, bad[0], bad[1]) { assert false }
		}
		if _ := swift_keyed_container_instantiate_checked(guard, guard, guard) { assert false }
		for symbol in ['_$ss22KeyedDecodingContainerVMn', '_$ss22KeyedEncodingContainerVMa', '_$ss9CodingKeyMp']! { assert swift_keyed_container_metadata_symbol(symbol) == none }
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$ss22KeyedDecodingContainerVMa') == none
		ios_runtime.swift_concurrency_retired = true
		assert swift_keyed_container_metadata_symbol('_$ss22KeyedDecodingContainerVMa') == none
		if _ := swift_keyed_container_metadata_checked(0, guard, guard + 8) { assert false }
		ios_runtime.swift_concurrency_retired = false
		mut retired := [entry]
		for base, _ in ios_runtime.swift_keyed_container_metadata { retired << base }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		objc_stop();assert ios_runtime.swift_keyed_container_arena == 0 && ios_runtime.swift_keyed_container_metadata.len == 0
		for base in retired { assert C.mprotect(voidptr(base), page, C.PROT_READ) == -1 }
		assert swift_keyed_container_metadata_symbol('_$ss22KeyedDecodingContainerVMa') == none
	}
	assert C.munmap(voidptr(guard), page) == 0
	println('IOS-KEYED-CONTAINER-METADATA: canonical borrowed K/witness pairs, descriptor factory, eight value witnesses and native enum bytes; eight cold publishers, unlocked destructor reentry and two drained/unmapped lifetimes')
}
