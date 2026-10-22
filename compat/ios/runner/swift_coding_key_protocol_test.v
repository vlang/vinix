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

fn ckp_symbols() [8]string {
	return ['_$ss9CodingKeyMp', '_$ss9CodingKeyTL', '_$ss9CodingKeyPs28CustomDebugStringConvertibleTb',
		'_$ss9CodingKeyPs23CustomStringConvertibleTb', '_$ss9CodingKeyP11stringValueSSvgTq',
		'_$ss9CodingKeyP11stringValuexSgSS_tcfCTq', '_$ss9CodingKeyP8intValueSiSgvgTq',
		'_$ss9CodingKeyP8intValuexSgSi_tcfCTq']!
}

fn ckp_offsets() [8]u64 { return [u64(0), 40, 48, 56, 64, 72, 80, 88]! }

fn ckp_relative(field u64) u64 {
	bits := read32(field)
	return if bits == 0 { u64(0) } else { u64(i64(field) + i64(i32(bits))) }
}

fn ckp_protocol(field u64) u64 {
	address := ckp_relative(field)
	return if address & 1 == 0 { address } else { read64(address - 1) }
}

fn ckp_text(address u64) string {
	assert address != 0
	return unsafe { (&u8(address)).vstring() }
}

fn ckp_permissions(address u64, bytes u64, native bool) {
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
			// Installed Swift declarations share an RX cache mapping. Our
			// separately sealed data page must be exactly read-only.
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

fn ckp_graph(descriptor u64, module_descriptor u64, debug_protocol u64, description_protocol u64, native bool) {
	assert descriptor != 0 && descriptor & 3 == 0
	ckp_permissions(descriptor, 96, native)
	assert read32(descriptor) == 0x30043
	assert ckp_relative(descriptor + 4) == module_descriptor
	assert read32(module_descriptor) & 31 == 0
	assert ckp_text(ckp_relative(module_descriptor + 8)) == 'Swift'
	assert ckp_text(ckp_relative(descriptor + 8)) == 'CodingKey'
	assert read32(descriptor + 12) == 2 && read32(descriptor + 16) == 6
	assert read32(descriptor + 20) == 0
	for i, parent in [debug_protocol, description_protocol]! {
		requirement := descriptor + 24 + u64(i * 12)
		assert read32(requirement) == 0x80
		assert ckp_text(ckp_relative(requirement + 4)) == 'x'
		assert ckp_protocol(requirement + 8) == parent
	}
	assert ckp_relative(descriptor + 28) == ckp_relative(descriptor + 40)
	for i, parent in [debug_protocol, description_protocol]! {
		assert read32(parent) == 0x30043
		assert ckp_text(ckp_relative(parent + 8)) == if i == 0 {
			'CustomDebugStringConvertible'
		} else {
			'CustomStringConvertible'
		}
	}
	// Exact independently measured native discriminators. Extension getters
	// are separate exports and supply none of these default witness fields.
	for i, flags in [u32(0), 0, 0xdcb00013, 0x32b70002, 0xbeb70013, 0xf36c0002]! {
		requirement := descriptor + 48 + u64(i * 8)
		assert read32(requirement) == flags
		assert read32(requirement + 4) == 0
	}
}

fn ckp_resolve(first int) u64 {
	library := '/usr/lib/swift/libswiftCore.dylib'
	symbols := ckp_symbols()
	offsets := ckp_offsets()
	if first == 2 {
		assert runtime_symbol(library, '_$ss28CustomDebugStringConvertibleMp') or { panic(err) } != 0
		assert runtime_symbol(library, '_$ss23CustomStringConvertibleMp') or { panic(err) } != 0
	}
	if first == 3 {
		for symbol in ['_$ss22KeyedDecodingContainerVMn', '_$ss22KeyedEncodingContainerVMn']! {
			assert runtime_symbol(library, symbol) or { panic(err) } != 0
		}
	}
	mut descriptor := u64(0)
	for _ in 0 .. 64 {
		mut alias := u64(0)
		if first == 1 { alias = runtime_symbol(library, symbols[2]) or { panic(err) } }
		descriptor = runtime_symbol(library, symbols[0]) or { panic(err) }
		if first == 1 {
			assert alias == descriptor + 48
		}
		for i, symbol in symbols {
			assert runtime_symbol(library, symbol) or { panic(err) } == descriptor + offsets[i]
		}
	}
	return descriptor
}

fn ckp_empty() {
	assert ios_runtime.swift_coding_key_protocol_arena == 0
	assert ios_runtime.swift_custom_debug_arena == 0 && ios_runtime.swift_array_arena == 0
	assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_keyed_container_arena == 0
	assert ios_runtime.swift_hash_code == 0
}

fn ckp_unmapped(address u64, page usize) {
	$if macos {
		assert C.mprotect(unsafe { voidptr(address) }, page, C.PROT_READ) == -1
	} $else {
		mut residency := u8(0)
		assert C.mincore(unsafe { voidptr(address) }, page, &residency) == -1
	}
}

fn test_swift_coding_key_protocol() {
	if _ := swift_coding_key_protocol_arena_checked() {
		assert false
	}
	for symbol in ckp_symbols() {
		assert swift_coding_key_protocol_symbol(symbol) == none
	}
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		descriptor := u64(C.dlsym(core, c'$ss9CodingKeyMp'))
		array := u64(C.dlsym(core, c'$sSaMn'))
		debug := u64(C.dlsym(core, c'$ss28CustomDebugStringConvertibleMp'))
		description := u64(C.dlsym(core, c'$ss23CustomStringConvertibleMp'))
		assert descriptor != 0 && array != 0 && debug != 0 && description != 0
		ckp_graph(descriptor, ckp_relative(array + 4), debug, description, true)
		for i, symbol in ckp_symbols() {
			name := symbol[1..]
			assert u64(C.dlsym(core, name.str)) == descriptor + ckp_offsets()[i]
		}
		for symbol in [c'$ss22KeyedDecodingContainerVMn', c'$ss22KeyedEncodingContainerVMn']! {
			nominal := u64(C.dlsym(core, symbol))
			assert nominal != 0 && ckp_protocol(nominal + 56) == descriptor
		}
		println('IOS-SWIFT-CODING-KEY-NATIVE: canonical Swift module and inherited protocol identities, two Self constraints, six exact requirement discriminators without default witnesses, eight aliases and both keyed-container constraints, readable non-writable leaf mapping')
	}
	page := usize(C.getpagesize())
	for cycle in 0 .. 2 {
		objc_start()
		for symbol in ['_$ss9CodingKeyMpunknown', '_$ss9CodingKey', '$ss9CodingKeyMp',
			'_$ss9CodingKeyP11stringValueSSvgTj', '_$ss9CodingKeyP8intValueSiSgvgTj']! {
			assert swift_coding_key_protocol_symbol(symbol) == none
		}
		for symbol in ckp_symbols() {
			assert runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', symbol) == none
		}
		ckp_empty()
		ios_runtime.swift_concurrency_retired = true
		for symbol in ckp_symbols() {
			assert swift_coding_key_protocol_symbol(symbol) == none
		}
		if _ := swift_coding_key_protocol_arena_checked() {
			assert false
		}
		ckp_empty()
		ios_runtime.swift_concurrency_retired = false
		ios_runtime.swift_coding_key_protocol_retired = true
		for symbol in ckp_symbols() {
			assert swift_coding_key_protocol_symbol(symbol) == none
		}
		if _ := swift_coding_key_protocol_arena_checked() {
			assert false
		}
		ckp_empty()
		ios_runtime.swift_coding_key_protocol_retired = false
		mut workers := []thread u64{}
		for i in 0 .. 8 { workers << spawn ckp_resolve(if cycle == 0 { i % 3 } else { 3 }) }
		resolved := workers.wait()
		for descriptor in resolved {
			assert descriptor != 0 && descriptor == resolved[0]
		}
		descriptor := resolved[0]
		assert descriptor == ios_runtime.swift_coding_key_protocol_arena
		ckp_permissions(descriptor, u64(page), false)
		library := '/usr/lib/swift/libswiftCore.dylib'
		debug := runtime_symbol(library, '_$ss28CustomDebugStringConvertibleMp') or { panic(err) }
		description := runtime_symbol(library, '_$ss23CustomStringConvertibleMp') or { panic(err) }
		array_arena := ios_runtime.swift_array_arena
		string_arena := ios_runtime.swift_metadata_arena
		assert debug == ios_runtime.swift_custom_debug_arena && array_arena != 0 && string_arena != 0
		ckp_graph(descriptor, array_arena + u64(page) + 224, debug, description, false)
		for symbol in ['_$ss22KeyedDecodingContainerVMn', '_$ss22KeyedEncodingContainerVMn']! {
			nominal := runtime_symbol(library, symbol) or { panic(err) }
			assert ckp_protocol(nominal + 56) == descriptor
			ckp_permissions(nominal, 60, false)
		}
		keyed_arena := ios_runtime.swift_keyed_container_arena
		assert keyed_arena != 0 && ios_runtime.swift_keyed_container_metadata.len == 0
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.live == 0
		assert ios_runtime.swift_hash_code == 0
		objc_stop()
		assert ios_runtime.swift_coding_key_protocol_retired && ios_runtime.swift_custom_debug_retired
		ckp_empty()
		assert ios_runtime.swift_keyed_container_metadata.len == 0 && ios_runtime.swift_array_metadata.len == 0
		assert ios_runtime.live == 0
		for arena in [descriptor, debug, array_arena, string_arena, keyed_arena]! {
			ckp_unmapped(arena, page)
		}
		for arena in [array_arena, string_arena, keyed_arena]! {
			ckp_unmapped(arena + u64(page), page)
		}
		ckp_unmapped(array_arena + u64(page * 2), page)
		ckp_unmapped(keyed_arena + u64(page * 2), page)
		for symbol in ckp_symbols() {
			assert swift_coding_key_protocol_symbol(symbol) == none
		}
		if _ := swift_coding_key_protocol_arena_checked() {
			assert false
		}
		ckp_empty()
	}
	println('IOS-SWIFT-CODING-KEY: native 96-byte declaration graph and six exact flags/no default witnesses, canonical inherited protocol and keyed-container constraint identities, eight aliases, full read-only page, cold descriptor/alias/dependency/nominal-first eight-worker publication, nil/unknown/library/retired rejection without allocation, two drained and fully unmapped dependency lifetimes')
}
