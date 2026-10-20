// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>
$if macos {
	#include <mach/mach.h>
}
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) int
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type DclLookup = fn (u64, u64, u64, u64) u64
type DclState = fn (u64, u64, u64, u64, u64) u64
type DclArray = fn (u64, u64) SwiftAssociatedMetadata
type DclStorage = fn (u64, u64, u64, u64) SwiftAssociatedMetadata

fn dcl_relative(field u64) u64 {
	delta := i32(read32(field))
	return if delta == 0 { u64(0) } else { u64(i64(field) + i64(delta)) }
}

fn dcl_declaration(d u64, native bool) {
	assert read32(d) & 0xffff == 0xd0
	parent := dcl_relative(d + 4)
	assert read32(parent) == 0 && unsafe { (&char(dcl_relative(parent + 8))).vstring() } == 'Swift'
	assert unsafe { (&char(dcl_relative(d + 8))).vstring() } == '_DictionaryStorage'
	assert read32(d + 24) == 3 && read32(d + 28) == 26 && read32(d + 32) == 4
	assert read32(d + 36) == 0 && read32(d + 40) == 25
	assert read32(d + 52) == 0x10002 && read32(d + 56) == 3
	assert read32(d + 60) == 0x8080 && read32(d + 64) == 0x80
	assert unsafe { (&char(dcl_relative(d + 68))).vstring() } == 'x'
	protocol := dcl_relative(d + 72)
	assert unsafe { (&char(dcl_relative(protocol + 8))).vstring() } == 'Hashable'
	super_type := dcl_relative(d + 20)
	assert super_type != 0
	if native {
		assert unsafe { *(&u8(super_type)) } == 1
		mut bits := u32(0)
		for i in u64(0) .. 4 { bits |= u32(unsafe { *(&u8(super_type + 1 + i)) }) << (i * 8) }
		super_descriptor := u64(i64(super_type + 1) + i64(i32(bits)))
		assert unsafe { (&char(dcl_relative(super_descriptor + 8))).vstring() } == '__RawDictionaryStorage'
	} else {
		assert read32(d) == 0xd0
		for offset in [u64(12), 16, 44, 48]! { assert read32(d + offset) == 0 }
		assert unsafe { (&char(super_type)).vstring() } == 's22__RawDictionaryStorageC'
	}
}

fn dcl_context(lookup DclLookup, state DclState, access DclArray, descriptor u64, key u64, value u64, guard u64, native bool) {
	// Key lookup borrows only one readable word and leaves Value/Hashable
	// inaccessible. Value lookup borrows only its selected word, even when the
	// Key word is on the preceding protected page.
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page * 3), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(voidptr(region), usize(page), C.PROT_NONE) == 0
	assert C.mprotect(voidptr(region + page * 2), usize(page), C.PROT_NONE) == 0
	key_args := region + page * 2 - 8
	value_args := region + page - 8
	unsafe { *(&u64(key_args)) = key; *(&u64(value_args + 8)) = value }
	inner_key_response := access(0, key)
	inner_value_response := access(0, value)
	inner_key := inner_key_response.metadata
	inner_value := inner_value_response.metadata
	outer_key_response := access(0, inner_key)
	outer_value_response := access(0, inner_value)
	outer_key := outer_key_response.metadata
	outer_value := outer_value_response.metadata
	for pair in [['x', key.hex()]!, ['q_', value.hex()]!, ['SayxG', inner_key.hex()]!, ['Sayq_G', inner_value.hex()]!, ['SaySayxGG', outer_key.hex()]!, ['SaySayq_GG', outer_value.hex()]!]! {
		expected := strconv.parse_uint(pair[1], 16, 64) or { panic(err) }
		args := if pair[0].contains('q_') { value_args } else { key_args }
		for _ in 0 .. 32 {
			assert lookup(u64(pair[0].str), u64(pair[0].len), descriptor, args) == expected
			for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
				assert state(request, u64(pair[0].str), u64(pair[0].len), descriptor, args) == expected
			}
		}
	}
	assert lookup(u64(c'Si'), 2, guard, guard) != 0
	if !native {
		// The compatibility helper borrows complete child identities without
		// inspecting them. Native lookup checks child completion, so invalid
		// inaccessible/null metadata is tested only on our guarded subset.
		unsafe { *(&u64(key_args)) = guard; *(&u64(value_args + 8)) = guard }
		assert lookup(u64('x'.str), 1, descriptor, key_args) == guard
		assert lookup(u64(c'q_'), 2, descriptor, value_args) == guard
		unsafe { *(&u64(key_args)) = 0; *(&u64(value_args + 8)) = 0 }
		assert lookup(u64('x'.str), 1, descriptor, key_args) == 0
		assert lookup(u64(c'q_'), 2, descriptor, value_args) == 0
	}
	assert C.munmap(voidptr(region), usize(page * 3)) == 0
}

fn dcl_reader(descriptor u64, key u64, value u64) {
	mut arguments := [key, value]!
	for _ in 0 .. 128 {
		assert (runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss18_DictionaryStorageCMn') or { panic(err) }) == descriptor
		assert swift_mangled_lookup(u64('x'.str), 1, descriptor, u64(unsafe { &arguments[0] })) == key
		assert swift_mangled_lookup(u64(c'q_'), 2, descriptor, u64(unsafe { &arguments[0] })) == value
	}
}

fn dcl_permissions(address u64) {
	$if macos {
		mut start := address; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + 155 <= start + size && info[0] == C.PROT_READ
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields(); if fields.len < 2 { continue }
			bounds := fields[0].split('-'); if bounds.len != 2 { continue }
			start := strconv.parse_uint(bounds[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(bounds[1], 16, 64) or { panic(err) }
			if address >= start && address < end { assert address + 155 <= end && fields[1] == 'r--p'; found = true; break }
		}
		assert found
	}
}

fn dcl_invalid(descriptor u64, guard u64) {
	for name in ['x', 'q_', 'Sayq_G']! {
		assert swift_mangled_lookup(u64(name.str), u64(name.len), descriptor, 0) == 0
		for context in [u64(1), guard, descriptor + 4]! {
			if _ := swift_mangled_lookup_checked(u64(name.str), u64(name.len), context, guard) { assert false }
		}
		for args in [u64(1), ~u64(0)]! {
			if _ := swift_mangled_lookup_checked(u64(name.str), u64(name.len), descriptor, args) { assert false }
		}
	}
	for context in [swift_array_arena() + u64(C.getpagesize()) + 160, swift_array_class_descriptor()]! {
		if _ := swift_mangled_lookup_checked(u64(c'q_'), 2, context, guard) { assert false }
	}
	if _ := swift_mangled_lookup_checked(u64(c'q_'), 2, descriptor, ~u64(0) - 7) { assert false }
	for name in ['q', 'q0_', 'q1_', 'qd__', 'q_G', 'Sayq_', 'q_x']! {
		if actual := swift_mangled_lookup_checked(u64(name.str), u64(name.len), descriptor, guard) { assert actual == 0 }
	}
	if _ := swift_mangled_nominal(descriptor) { assert false }
	// A bare symbolic reference to this generic class cannot use the
	// nongeneric accessor ABI, and generic suffixes must fail before witnesses.
	expression := u64(C.__builtin_alloca(32))
	unsafe { *(&u8(expression)) = 2; *(&u64(expression + 16)) = descriptor }
	for i in 0 .. 4 { unsafe { *(&u8(expression + 1 + u64(i))) = u8(u32(15) >> u32(i * 8)) } }
	C.memcpy(voidptr(expression + 5), c'yxq_G', 6)
	for length in [u64(5), 10]! { if _ := swift_mangled_lookup_checked(expression, length, descriptor, guard) { assert false } }
	for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$ss18_DictionaryStorageCMn') == none }
	for symbol in ['$ss18_DictionaryStorageCMn', '_$ss18_DictionaryStorageCMa', '_swift_getGenericMetadata']! { assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none }
}

fn test_swift_dictionary_storage_class() {
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		descriptor := u64(C.dlsym(core, c'$ss18_DictionaryStorageCMn'))
		dcl_declaration(descriptor, true)
		lookup := unsafe { DclLookup(C.dlsym(core, c'swift_getTypeByMangledNameInContext')) }
		state := unsafe { DclState(C.dlsym(core, c'swift_getTypeByMangledNameInContextInMetadataState')) }
		access := unsafe { DclArray(C.dlsym(core, c'$sSaMa')) }
		storage := unsafe { DclStorage(C.dlsym(core, c'$ss18_DictionaryStorageCMa')) }
		key := u64(C.dlsym(core, c'$sSSN')); value := u64(C.dlsym(core, c'$sSiN'))
		string_hashable := u64(C.dlsym(core, c'$sSSSHsWP'))
		integer_hashable := u64(C.dlsym(core, c'$sSiSHsWP'))
		assert string_hashable != 0 && integer_hashable != 0
		nested_response := access(0, value)
		nested := nested_response.metadata
		for pair in [[key, value]!, [value, key]!, [key, nested]!]! {
			dcl_context(lookup, state, access, descriptor, pair[0], pair[1], guard, true)
			hashable := if pair[0] == key { string_hashable } else { integer_hashable }
			complete := storage(0, pair[0], pair[1], hashable)
			canonical := complete.metadata
			assert read64(canonical + 64) == descriptor && read64(canonical + 176) == pair[0] && read64(canonical + 184) == pair[1] && read64(canonical + 192) == hashable
		}
		println('NATIVE-DICTIONARY-STORAGE-CLASS: Swift class identity/bounds/superclass and Key Hashable signature, metadata argument words22/23/24, bounded Key/Value and nested Array substitution across six request states, protected selected-word boundaries with complete children')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn dcl_publish() }
		published := publishers.wait()
		descriptor := published[0]
		for address in published { assert address == descriptor }
		dcl_declaration(descriptor, false)
		dcl_permissions(descriptor)
		assert descriptor == ios_runtime.swift_dictionary_metadata_arena + u64(page) + 640
		lookup := DclLookup(swift_mangled_lookup)
		state := DclState(swift_mangled_state_lookup)
		access := DclArray(swift_array_access)
		key := swift_string_metadata(); value := swift_integer_metadata()
		nested_response := access(0, value)
		nested := nested_response.metadata
		for pair in [[key, value]!, [value, key]!, [key, nested]!]! {
			dcl_context(lookup, state, access, descriptor, pair[0], pair[1], guard, false)
			mut readers := []thread{}
			for _ in 0 .. 8 { readers << spawn dcl_reader(descriptor, pair[0], pair[1]) }
			readers.wait(); unsafe { readers.free() }
		}
		dcl_invalid(descriptor, guard)
		assert descriptor != read64(swift_dictionary_metadata_access(0, key, value, guard).metadata + 8)
		// Publishing a declaration creates no storage-class specialization or
		// owner: generic value metadata remains independently owned/canonical.
		assert ios_runtime.swift_dictionary_metadata.len == 1 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_dictionary_metadata_arena
		objc_stop()
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss18_DictionaryStorageCMn') == none
		if _ := swift_mangled_generic_type_checked(descriptor, guard, true) { assert false }
		for offset in 0 .. 3 { assert C.mprotect(voidptr(arena + u64(offset * int(page))), page, C.PROT_READ) == -1 }
		assert ios_runtime.swift_dictionary_metadata_arena == 0 && ios_runtime.swift_dictionary_metadata.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		unsafe { publishers.free(); published.free() }
	}
	assert C.munmap(voidptr(guard), page) == 0
	println('IOS-DICTIONARY-STORAGE-CLASS: canonical sealed nominal declaration distinct from value/owner metadata, guarded Key/Value and nested Array context lookup with opaque children, explicit unsupported instantiation and invalid/lifetime rejection, eight publishers/readers and two drained/unmapped lifetimes without new owner/cache')
}

fn dcl_publish() u64 { return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss18_DictionaryStorageCMn') or { panic(err) } }
