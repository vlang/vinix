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

fn sequence_requirement_symbols() [11]string {
	return ['_$sSTMp', '_$sSTTL', '_$sST8IteratorST_StTn', '_$s7ElementSTTl', '_$s8IteratorSTTl',
		'_$sST12makeIterator0B0QzyFTq', '_$sST19underestimatedCountSivgTq',
		'_$sST31_customContainsEquatableElementySbSg0D0QzFTq',
		'_$sST22_copyToContiguousArrays0cD0Vy7ElementQzGyFTq',
		'_$sST13_copyContents12initializing8IteratorQz_SitSry7ElementQzG_tFTq',
		'_$sST32withContiguousStorageIfAvailableyqd__Sgqd__SRy7ElementQzGKXEKlFTq']!
}

fn sequence_requirement_offsets() [11]u64 {
	return [u64(0), 40, 48, 56, 64, 72, 80, 88, 96, 104, 112]!
}

fn sequence_requirement_iterator_symbols() [4]string {
	return ['_$sStMp', '_$sStTL', '_$s7ElementStTl', '_$sSt4next7ElementQzSgyFTq']!
}

fn sequence_requirement_relative(field u64) u64 {
	bits := read32(field)
	return if bits == 0 { u64(0) } else { u64(i64(field) + i64(i32(bits))) }
}

fn sequence_requirement_text(address u64) string {
	assert address != 0
	return unsafe { (&u8(address)).vstring() }
}

fn sequence_requirement_readonly(address u64, bytes u64, native bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [64]i32{}
		mut count := u32(C.VM_REGION_SUBMAP_INFO_COUNT_64)
		mut depth := u32(999)
		assert C.vm_region_recurse_64(C.mach_task_self(), &start, &size, &depth,
			unsafe { &info[0] }, &count) == 0
		assert start <= address && address + bytes <= start + size
		if native {
			assert info[0] & C.PROT_READ != 0 && info[0] & C.PROT_WRITE == 0
		} else {
			assert info[0] == C.PROT_READ
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert address + bytes <= end && fields[1] == 'r--p'
				found = true
				break
			}
		}
		assert found
	}
}

fn sequence_requirement_graph(descriptor u64, iterator u64, module_descriptor u64, native bool) {
	assert descriptor != 0 && iterator != 0 && descriptor & 3 == 0 && iterator & 3 == 0
	sequence_requirement_readonly(descriptor, 120, native)
	sequence_requirement_readonly(iterator, 40, native)
	for protocol in [descriptor, iterator]! {
		assert read32(protocol) == 0x30043
		assert sequence_requirement_relative(protocol + 4) == module_descriptor
	}
	assert read32(module_descriptor) & 31 == 0
	assert sequence_requirement_text(sequence_requirement_relative(module_descriptor + 8)) == 'Swift'
	assert sequence_requirement_text(sequence_requirement_relative(descriptor + 8)) == 'Sequence'
	assert read32(descriptor + 12) == 2 && read32(descriptor + 16) == 9
	assert sequence_requirement_text(sequence_requirement_relative(descriptor + 20)) == 'Element Iterator'
	assert read32(descriptor + 24) == 1 && read32(descriptor + 36) == 0x80
	assert sequence_requirement_text(sequence_requirement_relative(descriptor + 28)) == '7ElementSTQz'
	assert sequence_requirement_text(sequence_requirement_relative(descriptor + 32)) == '8IteratorST_7ElementStQZ'
	assert sequence_requirement_text(sequence_requirement_relative(descriptor + 40)) == '8IteratorSTQz'
	assert sequence_requirement_relative(descriptor + 44) == iterator
	assert sequence_requirement_text(sequence_requirement_relative(iterator + 8)) == 'IteratorProtocol'
	assert read32(iterator + 12) == 0 && read32(iterator + 16) == 2
	assert sequence_requirement_text(sequence_requirement_relative(iterator + 20)) == 'Element'
	assert read32(iterator + 24) & 15 == 7 && read32(iterator + 32) & 31 == 0x11
	// These are declaration aliases, never callable dispatch thunks. The
	// remaining native generic default callbacks are outside this increment.
	for i, flags in [u32(0x6d280011), 0x44000013, 0x01300011, 0x37910011, 0x8bad0011, 0x888a0011]! {
		assert read32(descriptor + 72 + u64(i * 8)) == flags
	}
	assert read32(descriptor + 76) == 0 // makeIterator has no native default.
}

fn sequence_requirement_resolve(first int) u64 {
	library := '/usr/lib/swift/libswiftCore.dylib'
	symbols := sequence_requirement_symbols()
	offsets := sequence_requirement_offsets()
	if first == 2 {
		assert runtime_symbol(library, '_$sSaMn') or { panic(err) } != 0
	}
	mut descriptor := u64(0)
	for _ in 0 .. 64 {
		mut requirement := u64(0)
		if first == 1 { requirement = runtime_symbol(library, symbols[5]) or { panic(err) } }
		descriptor = runtime_symbol(library, symbols[0]) or { panic(err) }
		if first == 1 {
			assert requirement == descriptor + 72
		}
		for i, symbol in symbols {
			assert runtime_symbol(library, symbol) or { panic(err) } == descriptor + offsets[i]
		}
	}
	return descriptor
}

fn sequence_requirement_empty() {
	assert ios_runtime.swift_array_sequence_arena == 0 && ios_runtime.swift_array_arena == 0
	assert ios_runtime.swift_array_sequence_metadata.len == 0 && ios_runtime.swift_array_metadata.len == 0
	assert ios_runtime.swift_collection_arena == 0 && ios_runtime.swift_metadata_arena == 0
	assert ios_runtime.swift_hash_code == 0
}

fn sequence_requirement_rejected() {
	for symbol in sequence_requirement_symbols() {
		assert swift_array_sequence_symbol(symbol) == none
	}
	for symbol in sequence_requirement_iterator_symbols() {
		assert swift_array_sequence_symbol(symbol) == none
	}
	assert swift_array_sequence_symbol('_$sSayxGSTsMc') == none
	if _ := swift_array_sequence_arena_checked() {
		assert false
	}
}

fn sequence_requirement_unmapped(address u64, page usize) {
	$if macos {
		assert C.mprotect(unsafe { voidptr(address) }, page, C.PROT_READ) == -1
	} $else {
		mut residency := u8(0)
		assert C.mincore(unsafe { voidptr(address) }, page, &residency) == -1
	}
}

fn test_swift_sequence_requirement() {
	sequence_requirement_rejected()
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		descriptor := u64(C.dlsym(core, c'$sSTMp'))
		iterator := u64(C.dlsym(core, c'$sStMp'))
		array := u64(C.dlsym(core, c'$sSaMn'))
		assert array != 0
		sequence_requirement_graph(descriptor, iterator, sequence_requirement_relative(array + 4), true)
		for i, symbol in sequence_requirement_symbols() {
			name := symbol[1..]
			assert u64(C.dlsym(core, name.str)) == descriptor + sequence_requirement_offsets()[i]
		}
		for i, symbol in sequence_requirement_iterator_symbols() {
			name := symbol[1..]
			offsets := [u64(0), 16, 24, 32]!
			assert u64(C.dlsym(core, name.str)) == iterator + offsets[i]
		}
		conformance := u64(C.dlsym(core, c'$sSayxGSTsMc'))
		assert conformance != 0 && sequence_requirement_relative(conformance) == descriptor
		println('IOS-SWIFT-SEQUENCE-REQUIREMENT-NATIVE: existing canonical Sequence/IteratorProtocol graph and Array conformance identity, six method requirement aliases and exact discriminators, null makeIterator default, readable non-writable declarations; generic default callback synthesis excluded')
	}
	page := usize(C.getpagesize())
	library := '/usr/lib/swift/libswiftCore.dylib'
	for cycle in 0 .. 2 {
		objc_start()
		for symbol in ['_$sST12makeIterator0B0QzyFTqunknown', '$sST12makeIterator0B0QzyFTq',
			'_$sST12makeIterator0B0QzyFTj', '_$sST19underestimatedCountSivgTj']! {
			assert swift_array_sequence_symbol(symbol) == none
		}
		for symbol in sequence_requirement_symbols() {
			assert runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', symbol) == none
		}
		sequence_requirement_empty()
		ios_runtime.swift_concurrency_retired = true
		sequence_requirement_rejected()
		sequence_requirement_empty()
		ios_runtime.swift_concurrency_retired = false
		ios_runtime.swift_array_sequence_retired = true
		sequence_requirement_rejected()
		sequence_requirement_empty()
		ios_runtime.swift_array_sequence_retired = false
		mut workers := []thread u64{}
		for i in 0 .. 8 { workers << spawn sequence_requirement_resolve((i + cycle) % 3) }
		resolved := workers.wait()
		for descriptor in resolved {
			assert descriptor != 0 && descriptor == resolved[0]
		}
		descriptor := resolved[0]
		arena := ios_runtime.swift_array_sequence_arena
		array_arena := ios_runtime.swift_array_arena
		assert arena != 0 && array_arena != 0 && descriptor == arena + u64(page) + 256
		sequence_requirement_readonly(arena + u64(page), u64(page), false)
		iterator := runtime_symbol(library, '_$sStMp') or { panic(err) }
		sequence_requirement_graph(descriptor, iterator, array_arena + u64(page) + 224, false)
		for i, symbol in sequence_requirement_iterator_symbols() {
			offsets := [u64(0), 16, 24, 32]!
			assert runtime_symbol(library, symbol) or { panic(err) } == iterator + offsets[i]
		}
		conformance := runtime_symbol(library, '_$sSayxGSTsMc') or { panic(err) }
		assert sequence_requirement_relative(conformance) == descriptor
		// Retirement checks must precede the cached-arena fast path as well.
		ios_runtime.swift_array_sequence_retired = true
		sequence_requirement_rejected()
		assert ios_runtime.swift_array_sequence_arena == arena && ios_runtime.swift_array_arena == array_arena
		ios_runtime.swift_array_sequence_retired = false
		ios_runtime.swift_concurrency_retired = true
		sequence_requirement_rejected()
		assert ios_runtime.swift_array_sequence_arena == arena && ios_runtime.swift_array_arena == array_arena
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_array_sequence_metadata.len == 0 && ios_runtime.swift_array_metadata.len == 0
		assert ios_runtime.swift_collection_arena == 0 && ios_runtime.swift_metadata_arena == 0
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_array_sequence_retired
		sequence_requirement_empty()
		for base in [arena, array_arena]! {
			for i in 0 .. 3 { sequence_requirement_unmapped(base + u64(page) * u64(i), page) }
		}
		sequence_requirement_rejected()
		sequence_requirement_empty()
	}
	println('IOS-SWIFT-SEQUENCE-REQUIREMENT: six canonical method requirement aliases with exact native flags and null makeIterator default, existing Sequence/IteratorProtocol graph and Array conformance identity, full read-only descriptor page, cold requirement/descriptor/dependency-first eight-worker publication, nil/unknown/library/own/global-retired rejection without allocation, two empty and fully unmapped six-page lifetimes; generic default callback synthesis excluded')
}
