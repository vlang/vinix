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

fn custom_debug_symbols() [3]string {
	return ['_$ss28CustomDebugStringConvertibleMp', '_$ss28CustomDebugStringConvertibleTL',
		'_$ss28CustomDebugStringConvertibleP16debugDescriptionSSvgTq']!
}

fn custom_debug_relative(field u64) u64 {
	bits := read32(field)
	return if bits == 0 { u64(0) } else { u64(i64(field) + i64(i32(bits))) }
}

fn custom_debug_text(address u64) string {
	assert address != 0
	return unsafe { (&u8(address)).vstring() }
}

fn custom_debug_permissions(address u64, bytes u64, native bool) {
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
			// Apple's declarations can share an RX text mapping. Compatibility
			// declarations have a dedicated page and must be exactly read-only.
			assert info[0] & C.PROT_READ != 0 && info[0] & C.PROT_WRITE == 0
		} else {
			assert info[0] == C.PROT_READ
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
				assert address + bytes <= end && fields[1] == 'r--p'
				found = true
				break
			}
		}
		assert found
	}
}

fn custom_debug_graph(descriptor u64, module_descriptor u64, native bool) {
	assert descriptor != 0 && descriptor & 3 == 0
	custom_debug_permissions(descriptor, 32, native)
	assert read32(descriptor) == 0x30043
	assert custom_debug_relative(descriptor + 4) == module_descriptor
	assert read32(module_descriptor) & 31 == 0
	assert custom_debug_text(custom_debug_relative(module_descriptor + 8)) == 'Swift'
	assert custom_debug_text(custom_debug_relative(descriptor + 8)) == 'CustomDebugStringConvertible'
	assert read32(descriptor + 12) == 0 // No generic signature requirements.
	assert read32(descriptor + 16) == 1 // One instance property getter.
	assert read32(descriptor + 20) == 0 // No associated type names.
	// Measured native getter discriminator, independent of the builder.
	assert read32(descriptor + 24) == 0x081a0013
	assert read32(descriptor + 24) & 15 == 3 && read32(descriptor + 24) & 16 != 0
	assert read32(descriptor + 28) == 0 // No default getter implementation.
}

fn custom_debug_resolve(alias_first bool, dependency_first bool) u64 {
	library := '/usr/lib/swift/libswiftCore.dylib'
	symbols := custom_debug_symbols()
	if dependency_first { assert runtime_symbol(library, '_$sSaMn') or { panic(err) } != 0 }
	mut descriptor := u64(0)
	for _ in 0 .. 64 {
		mut base := u64(0)
		if alias_first { base = runtime_symbol(library, symbols[1]) or { panic(err) } }
		descriptor = runtime_symbol(library, symbols[0]) or { panic(err) }
		if !alias_first { base = runtime_symbol(library, symbols[1]) or { panic(err) } }
		assert base == descriptor + 16
		assert runtime_symbol(library, symbols[2]) or { panic(err) } == descriptor + 24
	}
	return descriptor
}

fn custom_debug_unmapped(address u64, page usize) {
	$if macos {
		assert C.mprotect(unsafe { voidptr(address) }, page, C.PROT_READ) == -1
	} $else {
		mut residency := u8(0)
		assert C.mincore(unsafe { voidptr(address) }, page, &residency) == -1
	}
}

fn test_swift_custom_debug() {
	if _ := swift_custom_debug_arena_checked() { assert false }
	for symbol in custom_debug_symbols() { assert swift_custom_debug_symbol(symbol) == none }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		descriptor := u64(C.dlsym(lib, c'$ss28CustomDebugStringConvertibleMp'))
		assert descriptor != 0
		array_descriptor := u64(C.dlsym(lib, c'$sSaMn'))
		assert array_descriptor != 0
		custom_debug_graph(descriptor, custom_debug_relative(array_descriptor + 4), true)
		for i, symbol in custom_debug_symbols() {
			offsets := [u64(0), 16, 24]!
			name := symbol[1..]
			assert u64(C.dlsym(lib, &char(name.str))) == descriptor + offsets[i]
		}
		println('IOS-SWIFT-CUSTOM-DEBUG-NATIVE: canonical Swift parent, unique protocol flags, one instance getter without associated types/generic requirements/default, all three aliases, readable non-writable leaf mapping')
	}
	page := usize(C.getpagesize())
	for cycle in 0 .. 2 {
		objc_start()
		for symbol in ['_$ss28CustomDebugStringConvertibleMpunknown', '_$ss28CustomDebugStringConvertible',
			'_$ss28CustomDebugStringConvertibleP11descriptionSSvgTq',
			'_$ss28CustomDebugStringConvertibleP16debugDescriptionSSvgTj']! {
			assert swift_custom_debug_symbol(symbol) == none
		}
		for symbol in custom_debug_symbols() {
			assert runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', symbol) == none
		}
		assert ios_runtime.swift_custom_debug_arena == 0 && ios_runtime.swift_array_arena == 0
		ios_runtime.swift_concurrency_retired = true
		for symbol in custom_debug_symbols() { assert swift_custom_debug_symbol(symbol) == none }
		if _ := swift_custom_debug_arena_checked() { assert false }
		assert ios_runtime.swift_custom_debug_arena == 0 && ios_runtime.swift_array_arena == 0
		ios_runtime.swift_concurrency_retired = false
		mut workers := []thread u64{}
		for i in 0 .. 8 { workers << spawn custom_debug_resolve(i % 2 == 0, cycle == 1) }
		resolved := workers.wait()
		for descriptor in resolved { assert descriptor != 0 && descriptor == resolved[0] }
		arena := ios_runtime.swift_custom_debug_arena
		array_arena := ios_runtime.swift_array_arena
		assert arena == resolved[0] && array_arena != 0
		custom_debug_permissions(arena, u64(page), false)
		custom_debug_graph(arena, array_arena + u64(page) + 224, false)
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_custom_debug_retired && ios_runtime.swift_custom_debug_arena == 0
		assert ios_runtime.swift_array_arena == 0 && ios_runtime.swift_array_metadata.len == 0 && ios_runtime.live == 0
		custom_debug_unmapped(arena, page)
		custom_debug_unmapped(array_arena + u64(page), page)
		for symbol in custom_debug_symbols() { assert swift_custom_debug_symbol(symbol) == none }
		if _ := swift_custom_debug_arena_checked() { assert false }
		assert ios_runtime.swift_custom_debug_arena == 0 && ios_runtime.swift_array_arena == 0
	}
	println('IOS-SWIFT-CUSTOM-DEBUG: native descriptor/header/getter discriminator parity, canonical Swift parent, three exact aliases and no default witnesses, full read-only declaration page, cold alias/descriptor/dependency-first eight-worker resolution, unknown/library/nil/retired rejection without allocation, two drained and unmapped lifetimes')
}
