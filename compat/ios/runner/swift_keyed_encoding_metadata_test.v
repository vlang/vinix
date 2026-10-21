// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>

$if macos {
	#include <mach/mach.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type KemAccess = fn (u64, u64, u64) SwiftAssociatedMetadata
type KemCopy = fn (u64, u64, u64) u64
type KemDestroy = fn (u64, u64)
type KemGet = fn (u64, u32, u64) u32
type KemStore = fn (u64, u32, u32, u64)
type KemAllocate = fn (i64, u64) SwiftArrayAllocation
type KemRetain = fn (u64) u64
type KemRelease = fn (u64)
type KemFactory = fn (u64, u64, u64) u64

fn kem_relative(p u64) u64 { return u64(i64(p) + i64(i32(read32(p)))) }
fn kem_function(table u64, slot int) u64 { return read64(table + u64(slot * 8)) & 0x0000ffffffffffff }

fn kem_protocol(p u64) u64 {
	value := kem_relative(p)
	return if value & 1 == 0 { value } else { read64(value - 1) }
}
fn kem_graph(d u64) {
	assert read32(d) & 0xffff == 0xd1
	assert unsafe { (&char(kem_relative(d + 8))).vstring() } == 'KeyedEncodingContainer'
	module_descriptor := kem_relative(d + 4)
	assert read32(module_descriptor) == 0 && unsafe { (&char(kem_relative(module_descriptor + 8))).vstring() } == 'Swift'
	assert read32(d + 20) == 1 && read32(d + 24) == 4
	assert read32(d + 36) == 0x10001 && read32(d + 40) == 2
	assert read32(d + 44) == 0x80 && read32(d + 48) == 0x80
	assert unsafe { (&char(kem_relative(d + 52))).vstring() } == 'x'
	assert kem_relative(d + 12) & 3 == 0 && kem_relative(d + 28) & 7 == 0
	pattern := kem_relative(d + 32)
	// Native patterns may also carry extra data and trailing specialization flags.
	assert read32(pattern) != 0 && read32(pattern + 8) >> 21 == 0x200
	protocol := kem_protocol(d + 56)
	assert read32(protocol) == 0x30043 && read32(protocol + 12) == 2 && read32(protocol + 16) == 6
	assert unsafe { (&char(kem_relative(protocol + 8))).vstring() } == 'CodingKey'
	for i, name in ['CustomDebugStringConvertible', 'CustomStringConvertible']! {
		r := protocol + 24 + u64(i * 12)
		assert read32(r) == 0x80
		parent := kem_protocol(r + 8)
		assert read32(parent) == 0x30043 && read32(parent + 12) == 0 && read32(parent + 16) == 1
		assert read32(parent + 24) & 0xffff == 0x13
		assert unsafe { (&char(kem_relative(parent + 8))).vstring() } == name
	}
	for i, flags in [u32(0), 0, 0xdcb00013, 0x32b70002, 0xbeb70013, 0xf36c0002]! { assert read32(protocol + 48 + u64(i * 8)) == flags }
}

fn kem_mapping(address u64, protection int) {
	$if macos {
		mut start := address;mut size := u64(0);mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object := u32(0);task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if protection == 0 { assert status != 0 || start > address }
		else { assert status == 0 && start <= address && address + 60 <= start + size && info[0] == protection }
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields();if fields.len < 2 { continue };range := fields[0].split('-');if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) };end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end { assert protection != 0 && fields[1] == if protection == C.PROT_READ { 'r--p' } else { 'r-xp' };found = true;break }
		}
		assert found == (protection != 0)
	}
}

fn kem_metadata(access KemAccess, key u64, table u64) u64 {
	m := access(0, key, table).metadata
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
		r := access(request, key, table);assert r.metadata == m && r.state == 0
	}
	assert read64(m) == 0x200 && read64(m + 16) == key && read64(m + 24) == table && read32(m + 32) == 0
	d := read64(m + 8);w := read64(m - 8);kem_graph(d)
	assert read32(d) & 0xffff == 0xd1 && read32(d + 20) == 1 && read32(d + 24) == 4
	assert unsafe { (&char(kem_relative(d + 8))).vstring() } == 'KeyedEncodingContainer'
	assert read32(d + 36) == 0x10001 && read32(d + 40) == 2 && read32(d + 44) == 0x80 && read32(d + 48) == 0x80
	assert read64(w + 64) == 8 && read64(w + 72) == 8 && read32(w + 80) == 0x02010007 && read32(w + 84) == 0x7fffffff
	return m
}
fn kem_enums(metadata u64) []u8 {
	w := read64(metadata - 8)
	get := unsafe { KemGet(voidptr(kem_function(w, 6))) };store := unsafe { KemStore(voidptr(kem_function(w, 7))) }
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
fn kem_ownership(metadata u64, allocate KemAllocate, retain KemRetain, release KemRelease, integer u64) {
	w := read64(metadata - 8);owner := allocate(1, integer).owner
	mut source := [u64(0xCAFE), owner, 0xBEEF]!
	mut destination := [u64(0xCAFE), 0, 0xBEEF]!
	src := u64(unsafe { &source[1] });dst := u64(unsafe { &destination[1] })
	destroy := unsafe { KemDestroy(voidptr(kem_function(w, 1))) }
	for slot in [0, 2]! {
		initialize := unsafe { KemCopy(voidptr(kem_function(w, slot))) }
		assert initialize(dst, src, metadata) == dst && destination[1] == owner && read64(owner + 8) == 0x200000003
		destroy(dst, metadata);assert destination[1] == owner && read64(owner + 8) == 3
	}
	for slot in [3, 5]! {
		destination[1] = allocate(1, integer).owner
		if slot == 5 { retain(owner) }
		assign := unsafe { KemCopy(voidptr(kem_function(w, slot))) }
		assert assign(dst, src, metadata) == dst && read64(owner + 8) == 0x200000003
		destroy(dst, metadata);assert read64(owner + 8) == 3
	}
	copy_self := unsafe { KemCopy(voidptr(kem_function(w, 3))) };assert copy_self(src, src, metadata) == src && read64(owner + 8) == 3
	take := unsafe { KemCopy(voidptr(kem_function(w, 4))) };assert take(dst, src, metadata) == dst && source[1] == owner
	retain(owner);take_self := unsafe { KemCopy(voidptr(kem_function(w, 5))) };assert take_self(dst, dst, metadata) == dst && read64(owner + 8) == 3
	assert source[0] == 0xCAFE && source[2] == 0xBEEF && destination[0] == 0xCAFE && destination[2] == 0xBEEF
	release(owner)
}
fn kem_worker(key u64, witness u64) u64 {
	mut result := u64(0)
	for _ in 0 .. 128 { result = swift_keyed_encoding_metadata_access(0x1ff, key, witness).metadata }
	return result
}
struct KemReentry {
	destination u64
	expected u64
	key u64
	witness u64
	metadata u64
mut:
	calls int
}
fn kem_reentry_reader(state &KemReentry) {
	assert read64(state.destination) == state.expected
	assert kem_worker(state.key, state.witness) == state.metadata
	mut copy := u64(0)
	swift_keyed_container_copy(u64(unsafe { &copy }), state.destination, state.metadata)
	swift_keyed_container_destroy(u64(unsafe { &copy }), state.metadata)
}
fn kem_reentry_destroy(owner u64) {
	mut state := unsafe { &KemReentry(read64(owner + 16)) }
	worker := spawn kem_reentry_reader(state);worker.wait();state.calls++
	swift_heap_deallocate(owner, 32, 7)
}
fn kem_reentry(metadata u64, key u64, witness u64) {
	page := usize(C.getpagesize());code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert code != u64(-1)
	write32(code, 0xaa1403e0);write32(code + 4, 0x58000070);write32(code + 8, 0xd61f0200);write32(code + 12, 0xd503201f)
	unsafe { *(&u64(code + 16)) = u64(voidptr(kem_reentry_destroy));*(&u64(code + 112)) = code;*(&u64(code + 128)) = 0x400 }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 24));assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	for take in [false, true]! {
		mut source := swift_array_allocate(1, swift_integer_metadata()).owner
		mut destination := swift_heap_allocate(code + 128, 32, 7)
		state := unsafe { &KemReentry(C.__builtin_alloca(sizeof(KemReentry))) }
		unsafe { *state = KemReentry{u64(&destination), source, key, witness, metadata, 0};*(&u64(destination + 16)) = u64(state) }
		if take { swift_retain(source);swift_keyed_container_assign_take(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) }
		else { swift_keyed_container_assign_copy(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) }
		assert state.calls == 1 && destination == source
		swift_release(source);swift_release(destination)
	}
	assert C.munmap(voidptr(code), page) == 0
}
fn test_swift_keyed_encoding_metadata() {
	page := usize(C.getpagesize());guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert guard != u64(-1)
	mut native_snapshot := []u8{}
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert core != unsafe { nil }
		access := unsafe { KemAccess(C.dlsym(core, c'$ss22KeyedEncodingContainerVMa')) }
		integer := u64(C.dlsym(core, c'$sSiN'))
		metadata := kem_metadata(access, integer, guard + 8)
		kem_ownership(metadata, unsafe { KemAllocate(C.dlsym(core, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) }, unsafe { KemRetain(C.dlsym(core, c'swift_retain')) }, unsafe { KemRelease(C.dlsym(core, c'swift_release')) }, integer)
		native_snapshot = kem_enums(metadata)
		println('NATIVE-KEYED-ENCODING-METADATA: complete request responses, generic descriptor and box layout; eight native-reference witnesses, exact ownership and guarded enum bytes')
	}
	assert swift_keyed_container_metadata_symbol('_$ss22KeyedEncodingContainerVMa') == none
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn kem_worker(guard, guard + 8) }
		values := publishers.wait();metadata := values[0]
		for m in values { assert m == metadata };unsafe { publishers.free();values.free() }
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss22KeyedEncodingContainerVMa') or { panic(err) }
		access := unsafe { KemAccess(voidptr(entry)) };assert kem_metadata(access, guard, guard + 8) == metadata
		d := read64(metadata + 8)
		assert swift_keyed_container_metadata_symbol('_$ss22KeyedEncodingContainerVMn') == none
		decoding := swift_keyed_container_metadata_access(0, guard, guard + 8).metadata
		decoding_descriptor := read64(decoding + 8)
		assert decoding != metadata && decoding_descriptor != d
		assert kem_relative(decoding_descriptor + 56) == kem_relative(d + 56)
		assert read64(decoding - 8) == read64(metadata - 8)
		if _ := swift_keyed_container_instantiate_checked(d, guard, kem_relative(d + 32)) { assert false }
		assert kem_relative(d + 12) == entry
		assert kem_metadata(access, guard + 16, guard + 8) != metadata && kem_metadata(access, guard, guard + 24) != metadata
		mut arguments := [guard, guard + 8]!
		pattern := kem_relative(d + 32);factory := unsafe { KemFactory(voidptr(kem_relative(pattern))) }
		assert factory(d, u64(unsafe { &arguments[0] }), pattern) == metadata
		kem_mapping(d, C.PROT_READ);kem_mapping(metadata, C.PROT_READ);kem_mapping(entry, C.PROT_READ | C.PROT_EXEC)

		for tail in [false, true]! {
			region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert region != u64(-1)
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
			args := region + u64(page) + if tail { u64(page) - 16 } else { u64(0) }
			unsafe { *(&u64(args)) = guard;*(&u64(args + 8)) = guard + 8 }
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ) == 0
			assert factory(d, args, pattern) == metadata
			assert C.munmap(voidptr(region), page * 3) == 0
		}

		kem_ownership(metadata, swift_array_allocate, swift_retain, swift_release, swift_integer_metadata())
		snapshot := kem_enums(metadata);if native_snapshot.len != 0 { assert snapshot == native_snapshot }
		kem_reentry(metadata, guard, guard + 8)
		for bad in [[u64(0), guard]!, [guard, u64(0)]!, [guard + 1, guard]!, [guard, guard + 1]!]! {
			if _ := swift_keyed_encoding_metadata_checked(0, bad[0], bad[1]) { assert false }
		}
		if _ := swift_keyed_encoding_instantiate_checked(guard, guard, guard) { assert false }
		for symbol in ['_$ss22KeyedEncodingContainerVN', '_$ss22KeyedEncodingContainerVMn', '_$ss9CodingKeyMp']! { assert swift_keyed_container_metadata_symbol(symbol) == none }
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$ss22KeyedEncodingContainerVMa') == none
		ios_runtime.swift_concurrency_retired = true
		assert swift_keyed_container_metadata_symbol('_$ss22KeyedEncodingContainerVMa') == none
		if _ := swift_keyed_encoding_metadata_checked(0, guard, guard + 8) { assert false }
		ios_runtime.swift_concurrency_retired = false
		mut retired := [ios_runtime.swift_keyed_container_arena]
		for base, _ in ios_runtime.swift_keyed_container_metadata { retired << base }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		objc_stop();kem_mapping(d, 0);kem_mapping(metadata, 0);kem_mapping(entry, 0);assert ios_runtime.swift_keyed_container_arena == 0 && ios_runtime.swift_keyed_container_metadata.len == 0
		for base in retired { assert C.mprotect(voidptr(base), page, C.PROT_READ) == -1 }
		assert swift_keyed_container_metadata_symbol('_$ss22KeyedEncodingContainerVMa') == none
	}
	assert C.munmap(voidptr(guard), page) == 0
	println('IOS-KEYED-ENCODING-METADATA: canonical borrowed K/witness pairs, descriptor factory, eight value witnesses and native enum bytes; eight cold publishers, unlocked destructor reentry and two drained/unmapped lifetimes')
}
