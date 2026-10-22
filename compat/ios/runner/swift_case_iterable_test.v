// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_recurse_64(u32, &u64, &u64, &u32, &i32, &u32) i32

type CaseIterableArray = fn (u64, u64) SwiftAssociatedMetadata
type CaseIterableWitness = fn (u64, u64, u64) u64
type CaseIterableDefault = fn (u64) u64

struct CaseIterableApi {
	native            bool
	descriptor        u64
	module_descriptor u64
	collection        u64
	array_conformance u64
	elements          [3]u64
	array             CaseIterableArray @[required]
	witness           CaseIterableWitness @[required]
}

enum CaseIterablePage {
	readonly
	executable
	native_descriptor
}

fn case_iterable_symbols() [5]string {
	return ['_$ss12CaseIterableMp', '_$ss12CaseIterableTL', '_$ss12CaseIterableP8AllCasesAB_SlTn',
		'_$s8AllCasess12CaseIterablePTl', '_$ss12CaseIterableP8allCases03AllD0QzvgZTq']!
}

// Symbolic names contain unaligned rel32 fields. Read bytes rather than
// dereferencing an i32, including on hosts that permit unaligned accesses.
fn case_iterable_relative(field u64) u64 {
	mut bits := u32(0)
	for i in u64(0) .. 4 { bits |= u32(unsafe { *(&u8(field + i)) }) << (i * 8) }
	return if bits == 0 { u64(0) } else { u64(i64(field) + i64(i32(bits))) }
}

fn case_iterable_text(address u64) string {
	assert address != 0
	return unsafe { (&u8(address)).vstring() }
}

fn case_iterable_permissions(address u64, bytes u64, kind CaseIterablePage) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [64]i32{}
		mut count := u32(C.VM_REGION_SUBMAP_INFO_COUNT_64)
		mut depth := u32(999)
		task := C.mach_task_self()
		// Query the leaf mapping: the shared cache's outer region can report
		// different permissions from the descriptor/accessor's actual submap.
		assert C.vm_region_recurse_64(task, &start, &size, &depth,
			unsafe { &info[0] }, &count) == 0
		assert start <= address && address + bytes <= start + size
		if kind == .native_descriptor {
			// Apple's declaration shares an RX text mapping. Vinix's dedicated
			// declaration page must still pass the exact R-only check below.
			assert info[0] & C.PROT_READ != 0 && info[0] & C.PROT_WRITE == 0
		} else {
			assert info[0] == if kind == .executable { C.PROT_READ | C.PROT_EXEC } else { C.PROT_READ }
		}
	} $else {
		maps := os.read_file('/proc/self/maps') or { panic(err) }
		mut found := false
		for line in maps.split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert address + bytes <= end
				assert fields[1] == if kind == .executable { 'r-xp' } else { 'r--p' }
				found = true
				break
			}
		}
		assert found
	}
}

fn case_iterable_dependent_name(address u64, descriptor u64, suffix string) {
	assert C.memcmp(unsafe { voidptr(address) }, c'8AllCases', 9) == 0
	assert unsafe { *(&u8(address + 9)) } == 1
	assert case_iterable_relative(address + 10) == descriptor
	assert case_iterable_text(address + 14) == suffix
}

fn case_iterable_graph(api CaseIterableApi) u64 {
	descriptor := api.descriptor
	assert descriptor != 0 && descriptor & 3 == 0
	case_iterable_permissions(descriptor, 72, if api.native { .native_descriptor } else { .readonly })
	assert read32(descriptor) == 0x30043
	assert case_iterable_relative(descriptor + 4) == api.module_descriptor
	assert read32(api.module_descriptor) & 31 == 0
	assert case_iterable_text(case_iterable_relative(api.module_descriptor + 8)) == 'Swift'
	assert case_iterable_text(case_iterable_relative(descriptor + 8)) == 'CaseIterable'
	assert read32(descriptor + 12) == 2 && read32(descriptor + 16) == 3
	assert case_iterable_text(case_iterable_relative(descriptor + 20)) == 'AllCases'
	assert read32(descriptor + 24) == 1
	assert case_iterable_text(case_iterable_relative(descriptor + 28)) == 'x'
	case_iterable_dependent_name(case_iterable_relative(descriptor + 32), descriptor, '_7ElementSTQZ')
	assert read32(descriptor + 36) == 0x80
	case_iterable_dependent_name(case_iterable_relative(descriptor + 40), descriptor, 'Qz')
	assert case_iterable_relative(descriptor + 44) == api.collection
	assert case_iterable_text(case_iterable_relative(api.collection + 8)) == 'Collection'
	assert read32(descriptor + 48) == 0x20050008
	assert read32(descriptor + 56) == 0xdf690007
	assert read32(descriptor + 64) == 0x8ed40003
	assert case_iterable_relative(descriptor + 68) == 0
	assert case_iterable_text(case_iterable_relative(descriptor + 60)) == 'SayxG'
	// The associated-conformance default is a symbolic type-relative accessor
	// name, not an immediately callable pointer or an ordinary C string.
	name := case_iterable_relative(descriptor + 52)
	assert unsafe { *(&u8(name)) } == 8
	assert unsafe { *(&u8(name + 5)) } == 0
	accessor := case_iterable_relative(name + 1)
	assert accessor != 0
	case_iterable_permissions(accessor, 8, .executable)
	return accessor
}

fn case_iterable_defaults_worker(api CaseIterableApi, accessor u64, metadata []u64) {
	call := unsafe { CaseIterableDefault(voidptr(accessor)) }
	for _ in 0 .. 64 {
		for value in metadata {
			expected := api.witness(api.array_conformance, value, 0)
			assert expected != 0 && call(value) == expected
			assert case_iterable_relative(read64(expected)) == api.collection
		}
	}
}

fn case_iterable_defaults(api CaseIterableApi, accessor u64) []u64 {
	mut metadata := []u64{}
	for element in api.elements {
		assert element != 0
		array := api.array(0, element)
		assert array.metadata != 0 && array.state == 0
		assert api.array(0xff, element).metadata == array.metadata
		metadata << array.metadata
	}
	// A nested specialization distinguishes AllCases metadata from Self and
	// catches a default that constructs another Array around its argument.
	metadata << api.array(0, metadata[0]).metadata
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn case_iterable_defaults_worker(api, accessor, metadata) }
	workers.wait()
	return metadata
}

fn case_iterable_resolve(descriptor_first bool) u64 {
	library := '/usr/lib/swift/libswiftCore.dylib'
	symbols := case_iterable_symbols()
	mut descriptor := u64(0)
	for _ in 0 .. 64 {
		if !descriptor_first {
			assert runtime_symbol(library, '_$sSlMp') or { panic(err) } != 0
		}
		descriptor = runtime_symbol(library, symbols[0]) or { panic(err) }
		for i, symbol in symbols {
			offsets := [u64(0), 40, 48, 56, 64]!
			assert runtime_symbol(library, symbol) or { panic(err) } == descriptor + offsets[i]
		}
	}
	return descriptor
}

fn case_iterable_unmapped(address u64, page usize) {
	$if macos {
		assert C.mprotect(unsafe { voidptr(address) }, page, C.PROT_READ) == -1
	} $else {
		mut residency := u8(0)
		assert C.mincore(unsafe { voidptr(address) }, page, &residency) == -1
	}
}

fn test_swift_case_iterable() {
	if _ := swift_case_iterable_arena_checked() {
		assert false
	}
	if _ := swift_case_iterable_default_conformance_checked(0) {
		assert false
	}
	for symbol in case_iterable_symbols() {
		assert swift_case_iterable_symbol(symbol) == none
	}
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		descriptor := u64(C.dlsym(lib, c'$ss12CaseIterableMp'))
		array_descriptor := u64(C.dlsym(lib, c'$sSaMn'))
		assert array_descriptor != 0
		api := CaseIterableApi{
			native:            true
			descriptor:        descriptor
			module_descriptor: case_iterable_relative(array_descriptor + 4)
			collection:        u64(C.dlsym(lib, c'$sSlMp'))
			array_conformance: u64(C.dlsym(lib, c'$sSayxGSlsMc'))
			elements:          [u64(C.dlsym(lib, c'$sSiN')), u64(C.dlsym(lib, c'$sSbN')),
				u64(C.dlsym(lib, c'$sSSN'))]!
			array:             unsafe { CaseIterableArray(C.dlsym(lib, c'$sSaMa')) }
			witness:           unsafe { CaseIterableWitness(C.dlsym(lib, c'swift_getWitnessTable')) }
		}
		for i, symbol in case_iterable_symbols() {
			offsets := [u64(0), 40, 48, 56, 64]!
			name := symbol[1..]
			assert u64(C.dlsym(lib, &char(name.str))) == descriptor + offsets[i]
		}
		case_iterable_defaults(api, case_iterable_graph(api))
		println('IOS-SWIFT-CASE-ITERABLE-NATIVE: canonical Swift/Collection graph, symbolic generic paths and defaults, all five aliases, readable non-writable descriptor and executable accessor, Array<Int>/Bool/String and nested associated-conformance defaults, eight workers')
	}
	page := usize(C.getpagesize())
	for cycle in 0 .. 2 {
		objc_start()
		for symbol in ['_$ss12CaseIterableMpunknown', '_$ss12CaseIterableP8AllCasesAB_SlTN',
			'_$ss12CaseIterableP8allCasesunknown']! {
			assert swift_case_iterable_symbol(symbol) == none
		}
		for symbol in case_iterable_symbols() {
			assert runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', symbol) == none
		}
		assert ios_runtime.swift_case_iterable_arena == 0
		assert ios_runtime.swift_collection_arena == 0 && ios_runtime.swift_array_arena == 0
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn case_iterable_resolve(cycle == 0) }
		resolved := resolvers.wait()
		for descriptor in resolved {
			assert descriptor != 0 && descriptor == resolved[0]
		}
		arena := ios_runtime.swift_case_iterable_arena
		assert resolved[0] == arena + u64(page)
		case_iterable_permissions(arena, u64(page), .executable)
		case_iterable_permissions(arena + u64(page), u64(page), .readonly)
		library := '/usr/lib/swift/libswiftCore.dylib'
		api := CaseIterableApi{
			descriptor:        resolved[0]
			module_descriptor: ios_runtime.swift_array_arena + u64(page) + 224
			collection:        runtime_symbol(library, '_$sSlMp') or { panic(err) }
			array_conformance: runtime_symbol(library, '_$sSayxGSlsMc') or { panic(err) }
			elements:          [runtime_symbol(library, '_$sSiN') or { panic(err) },
				runtime_symbol(library, '_$sSbN') or { panic(err) },
				runtime_symbol(library, '_$sSSN') or { panic(err) }]!
			array:             swift_array_access
			witness:           swift_witness_table
		}
		accessor := case_iterable_graph(api)
		assert accessor == arena
		metadata := case_iterable_defaults(api, accessor)
		// Existing complete-metadata witness lookup must use the exported
		// resilient base and AllCases requirement to find the table's slot.
		mut table := [u64(0), swift_collection_table_checked(metadata[0]) or { panic(err) },
			metadata[0], u64(0)]!
		for request in [u64(0), 0xff, 0x100, 0x1ff]! {
			result := swift_associated_type(request, u64(unsafe { &table[0] }), api.elements[0], api.descriptor + 40, api.descriptor + 56)
			assert result.metadata == metadata[0] && result.state == 0
		}
		collection_data := ios_runtime.swift_collection_arena + u64(page)
		slice_metadata := table[1] - 320 + 8
		for invalid in [u64(0), 1, 8, api.elements[0], slice_metadata, collection_data + 1024]! {
			if _ := swift_case_iterable_default_conformance_checked(invalid) {
				assert false
			}
		}
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_case_iterable_retired && ios_runtime.swift_case_iterable_arena == 0
		assert ios_runtime.swift_collection_arena == 0 && ios_runtime.swift_array_sequence_arena == 0
		assert ios_runtime.swift_array_arena == 0 && ios_runtime.swift_integer_arena == 0
		assert ios_runtime.swift_collection_metadata.len == 0 && ios_runtime.swift_array_sequence_metadata.len == 0
		assert ios_runtime.swift_array_metadata.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		case_iterable_unmapped(arena, page)
		case_iterable_unmapped(arena + u64(page), page)
		for symbol in case_iterable_symbols() {
			assert swift_case_iterable_symbol(symbol) == none
		}
		if _ := swift_case_iterable_arena_checked() {
			assert false
		}
		if _ := swift_case_iterable_default_conformance_checked(metadata[0]) {
			assert false
		}
		assert ios_runtime.swift_case_iterable_arena == 0 && ios_runtime.swift_collection_arena == 0 && ios_runtime.swift_array_arena == 0
	}
	println('IOS-SWIFT-CASE-ITERABLE: native descriptor graph and five aliases, unaligned symbolic references, canonical Swift/Collection dependencies, RO data and RX default accessor, exact Array associated-conformance defaults and complete associated-type slots, cold descriptor/dependency-first eight-worker publication, unsupported/nil/retired rejection, two drained and unmapped lifetimes')
}
