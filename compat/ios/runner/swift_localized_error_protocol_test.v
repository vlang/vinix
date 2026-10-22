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

type LepProbe = fn (u64, u64, u64)

fn lep_libraries() [2]string {
	return ['/System/Library/Frameworks/Foundation.framework/Foundation',
		'/usr/lib/swift/libswiftFoundation.dylib']!
}

fn lep_symbols() [7]string {
	return ['_$s10Foundation14LocalizedErrorMp', '_$s10Foundation14LocalizedErrorTL',
		'_$s10Foundation14LocalizedErrorPs0C0Tb',
		'_$s10Foundation14LocalizedErrorP16errorDescriptionSSSgvgTq',
		'_$s10Foundation14LocalizedErrorP13failureReasonSSSgvgTq',
		'_$s10Foundation14LocalizedErrorP18recoverySuggestionSSSgvgTq',
		'_$s10Foundation14LocalizedErrorP10helpAnchorSSSgvgTq']!
}

fn lep_defaults() [4]string {
	return ['_$s10Foundation14LocalizedErrorP16errorDescriptionSSSgvg',
		'_$s10Foundation14LocalizedErrorP13failureReasonSSSgvg',
		'_$s10Foundation14LocalizedErrorP18recoverySuggestionSSSgvg',
		'_$s10Foundation14LocalizedErrorP10helpAnchorSSSgvg']!
}

fn lep_extensions() [4]string {
	return ['_$s10Foundation14LocalizedErrorPAAE16errorDescriptionSSSgvg',
		'_$s10Foundation14LocalizedErrorPAAE13failureReasonSSSgvg',
		'_$s10Foundation14LocalizedErrorPAAE18recoverySuggestionSSSgvg',
		'_$s10Foundation14LocalizedErrorPAAE10helpAnchorSSSgvg']!
}

fn lep_offsets() [7]u64 { return [u64(0), 28, 36, 44, 52, 60, 68]! }

fn lep_relative(field u64) u64 {
	bits := read32(field)
	return if bits == 0 { u64(0) } else { u64(i64(field) + i64(i32(bits))) }
}

fn lep_text(address u64) string {
	assert address != 0
	return unsafe { (&u8(address)).vstring() }
}

fn lep_permissions(address u64, bytes u64, executable bool, native bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [64]i32{}
		mut count := u32(C.VM_REGION_SUBMAP_INFO_COUNT_64)
		mut depth := u32(999)
		assert C.vm_region_recurse_64(C.mach_task_self(), &start, &size, &depth,
			unsafe { &info[0] }, &count) == 0
		assert start <= address && address + bytes <= start + size
		if native && !executable {
			// Apple's declaration lives in the shared cache's RX leaf mapping.
			assert info[0] & C.PROT_READ != 0 && info[0] & C.PROT_WRITE == 0
		} else {
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
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
				assert address + bytes <= end
				assert fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
				break
			}
		}
		assert found
	}
}

fn lep_graph(descriptor u64, module_descriptor u64, error_protocol u64, native bool) [4]u64 {
	assert descriptor != 0 && descriptor & 3 == 0
	lep_permissions(descriptor, 76, false, native)
	assert read32(descriptor) == 0x30043
	assert lep_relative(descriptor + 4) == module_descriptor
	assert read32(module_descriptor) == 0 && read32(module_descriptor + 4) == 0
	assert lep_text(lep_relative(module_descriptor + 8)) == 'Foundation'
	assert lep_text(lep_relative(descriptor + 8)) == 'LocalizedError'
	assert read32(descriptor + 12) == 1 && read32(descriptor + 16) == 5
	assert read32(descriptor + 20) == 0
	assert read32(descriptor + 24) == 0x80
	assert lep_text(lep_relative(descriptor + 28)) == 'x'
	// Native inheritance uses an indirect relative reference to Swift.Error.
	inherited := lep_relative(descriptor + 32)
	assert inherited & 1 == 1 && read64(inherited - 1) == error_protocol
	assert error_protocol != 0 && read32(error_protocol) == 0x70043
	assert lep_text(lep_relative(error_protocol + 8)) == 'Error'
	assert read32(error_protocol + 12) == 0 && read32(error_protocol + 16) == 4
	assert read32(error_protocol + 20) == 0
	assert lep_text(lep_relative(lep_relative(error_protocol + 4) + 8)) == 'Swift'
	mut defaults := [4]u64{}
	for i, flags in [u32(0), 0xb1700013, 0x636e0013, 0xa3140013, 0xadc30013]! {
		requirement := descriptor + 36 + u64(i * 8)
		assert read32(requirement) == flags
		entry := lep_relative(requirement + 4)
		if i == 0 {
			assert entry == 0
		} else {
			assert entry != 0
			lep_permissions(entry, 12, true, native)
			if native {
				assert read32(entry) == 0xd2800000 && read32(entry + 4) == 0xd2800001
				assert read32(entry + 8) == 0xd65f03c0
			}
			for previous in 0 .. i - 1 {
				assert defaults[previous] != entry
			}
			defaults[i - 1] = entry
		}
	}
	return defaults
}

fn lep_pair(load bool, vector bool, first u32, second u32, base u32, offset int) u32 {
	width := if vector { 16 } else { 8 }
	assert offset % width == 0 && offset >= 0 && offset / width < 64
	op := if vector { u32(0xad000000) } else { u32(0xa9000000) }
	return op | (if load { u32(0x00400000) } else { u32(0) }) | (u32(offset / width) << 15) | (second << 10) | (base << 5) | first
}

fn lep_probe_code(code u64) {
	mut ops := [u32(0xa9bc7bfd)]
	defer { unsafe { ops.free() } }
	for i in 0 .. 3 {
		ops << lep_pair(false, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16)
	}
	ops << [u32(0xaa0003f0), 0xaa0103f4, 0xaa0203f3] // Entry, borrowed Self and output.
	for register in u32(0) .. 9 {
		if register != 1 { ops << u32(0xaa0103e0) | register }
	}
	ops << u32(0xd2800000 | (0x7654 << 5) | 21)
	distance := u32(256 - ops.len * 4)
	ops << u32(0x10000017 | ((distance & 3) << 29) | ((distance >> 2) << 5))
	for i in 0 .. 4 { ops << lep_pair(true, true, u32(i * 2), u32(i * 2 + 1), 23, i * 32) }
	ops << u32(0xd63f0200) // blr x16.
	ops << lep_pair(false, false, 0, 1, 19, 0)
	ops << lep_pair(false, false, 20, 21, 19, 16)
	ops << u32(0xf9001268) // str x8,[x19,#32].
	for i in 0 .. 4 {
		ops << lep_pair(false, true, u32(i * 2), u32(i * 2 + 1), 19, 48 + i * 32)
	}
	for i in 0 .. 3 {
		ops << lep_pair(true, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16)
	}
	ops << [u32(0xa8c47bfd), 0xd65f03c0]
	assert ops.len * 4 <= 256
	for i, op in ops { write32(code + u64(i * 4), op) }
	for i in 0 .. 16 {
		unsafe { *(&u64(code + 256 + u64(i * 8))) = u64(0x12340000 + i) }
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 384))
}

fn lep_call(entry u64, self u64, probe LepProbe) {
	mut output := [26]u64{}
	output[0] = 0xcafe
	output[6] = 0xdead
	output[23] = 0xbeef
	output[24] = 0xface
	output[25] = 0xbabe
	probe(entry, self, u64(unsafe { &output[1] }))
	assert output[1] == 0 && output[2] == 0 // Optional<String>.none in x0/x1.
	assert output[3] == self && output[4] == 0x7654 && output[5] == self
	for i in 0 .. 16 {
		assert output[7 + i] == u64(0x12340000 + i)
	}
	assert output[0] == 0xcafe && output[6] == 0xdead && output[23] == 0xbeef
	assert output[24] == 0xface && output[25] == 0xbabe
}

fn lep_call_worker(entries [4]u64, self u64, probe LepProbe) {
	for _ in 0 .. 32 {
		for entry in entries { lep_call(entry, self, probe) }
	}
}

fn lep_call_cases(entries [4]u64, guard u64, self u64, probe LepProbe) {
	values := [u64(0), 1, ~u64(0), guard, self]!
	for value in values {
		for entry in entries { lep_call(entry, value, probe) }
	}
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn lep_call_worker(entries, values[i % values.len], probe) }
	workers.wait()
	unsafe { workers.free() }
	assert read64(self) == 0x0123456789abcdef
}

fn lep_resolve(first int, alias int) u64 {
	library := lep_libraries()[alias]
	symbols := lep_symbols()
	if first == 1 {
		assert runtime_symbol(library, symbols[3]) or { panic(err) } != 0
	} else if first == 2 {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss5ErrorMp') or { panic(err) } != 0
	} else if first == 3 {
		assert runtime_symbol(library, '_$s10Foundation4DateVMn') or { panic(err) } != 0
	} else if first == 4 {
		assert runtime_symbol(library, lep_extensions()[0]) or { panic(err) } != 0
	}
	mut descriptor := u64(0)
	for _ in 0 .. 64 {
		descriptor = runtime_symbol(library, symbols[0]) or { panic(err) }
		for i, symbol in symbols {
			assert runtime_symbol(library, symbol) or { panic(err) } == descriptor + lep_offsets()[i]
		}
	}
	return descriptor
}

fn lep_arenas() [5]u64 {
	return [ios_runtime.swift_localized_error_protocol_arena, ios_runtime.swift_foundation_arena,
		ios_runtime.swift_error_arena, ios_runtime.swift_metadata_arena,
		ios_runtime.swift_integer_arena]!
}

fn lep_empty() {
	for arena in lep_arenas() {
		assert arena == 0
	}
	assert ios_runtime.swift_array_arena == 0 && ios_runtime.swift_bool_metadata_arena == 0
	assert ios_runtime.swift_hash_code == 0
}

fn lep_rejected() {
	for symbol in lep_symbols() {
		assert swift_localized_error_protocol_symbol(symbol) == none
	}
	for symbol in lep_defaults() {
		assert swift_localized_error_protocol_symbol(symbol) == none
	}
	if _ := swift_localized_error_protocol_arena_checked() {
		assert false
	}
}

fn lep_unmapped(address u64, page usize) {
	$if macos {
		assert C.mprotect(voidptr(address), page, C.PROT_READ) == -1
	} $else {
		mut residency := u8(0)
		assert C.mincore(voidptr(address), page, &residency) == -1
	}
}

fn test_swift_localized_error_protocol() {
	lep_rejected()
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	lep_probe_code(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { LepProbe(voidptr(code)) }
	guard := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	assert C.mprotect(voidptr(guard + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	self := guard + u64(page * 2) - 8
	unsafe { *(&u64(self)) = 0x0123456789abcdef }
	assert C.mprotect(voidptr(guard + u64(page)), page, C.PROT_READ) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		error_protocol := u64(C.dlsym(core, c'$ss5ErrorMp'))
		mut canonical := u64(0)
		for library in lep_libraries() {
			handle := C.dlopen(library.str, C.RTLD_NOW)
			assert handle != unsafe { nil }
			descriptor := u64(C.dlsym(handle, c'$s10Foundation14LocalizedErrorMp'))
			assert descriptor != 0
			if canonical == 0 {
				canonical = descriptor
			} else {
				assert descriptor == canonical
			}
			date := u64(C.dlsym(handle, c'$s10Foundation4DateVMn'))
			url := u64(C.dlsym(handle, c'$s10Foundation3URLVMn'))
			assert date != 0 && url != 0
			module_descriptor := lep_relative(date + 4)
			assert lep_relative(url + 4) == module_descriptor
			entries := lep_graph(descriptor, module_descriptor, error_protocol, true)
			for i, symbol in lep_symbols() {
				name := symbol[1..]
				assert u64(C.dlsym(handle, name.str)) == descriptor + lep_offsets()[i]
			}
			for i, symbol in lep_defaults() {
				name := symbol[1..]
				// dladdr names these private callbacks, but they are not public
				// dlsym exports. Invoke only the descriptor's executable target.
				assert C.dlsym(handle, name.str) == unsafe { nil }
				for extension in lep_extensions() {
					extension_name := extension[1..]
					extension_entry := u64(C.dlsym(handle, extension_name.str))
					assert extension_entry != 0 && extension_entry != entries[i]
				}
			}
			lep_call_cases(entries, guard, self, probe)
		}
		println('IOS-SWIFT-LOCALIZED-ERROR-PROTOCOL-NATIVE: canonical Foundation module shared with Date/URL, indirect canonical Error inheritance, five exact requirements and seven declaration aliases; four distinct private executable nil defaults preserve x8/x20/x21 and vectors with guarded ignored inputs through both Foundation libraries')
	}
	for cycle in 0 .. 2 {
		objc_start()
		for symbol in ['_$s10Foundation14LocalizedErrorMpunknown', '$s10Foundation14LocalizedErrorMp',
			'_$s10Foundation14LocalizedErrorPs5ErrorTb',
			'_$s10Foundation14LocalizedErrorP16errorDescriptionSSSgvgTj',
			'_$s10Foundation14LocalizedErrorP16errorDescriptionSSSgvgunknown']! {
			assert swift_localized_error_protocol_symbol(symbol) == none
		}
		for symbol in lep_symbols() {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
			assert runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', symbol) == none
		}
		for symbol in lep_defaults() {
			assert swift_localized_error_protocol_symbol(symbol) == none
			for alias in lep_libraries() {
				assert runtime_symbol(alias, symbol) == none
			}
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
			assert runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', symbol) == none
		}
		lep_empty()
		ios_runtime.swift_concurrency_retired = true
		lep_rejected()
		lep_empty()
		ios_runtime.swift_concurrency_retired = false
		ios_runtime.swift_localized_error_protocol_retired = true
		lep_rejected()
		lep_empty()
		ios_runtime.swift_localized_error_protocol_retired = false
		mut workers := []thread u64{}
		for i in 0 .. 8 { workers << spawn lep_resolve((i + cycle) % 5, i % 2) }
		resolved := workers.wait()
		for descriptor in resolved {
			assert descriptor != 0 && descriptor == resolved[0]
		}
		arenas := lep_arenas()
		for arena in arenas {
			assert arena != 0
		}
		descriptor := resolved[0]
		assert descriptor == arenas[0] + u64(page)
		lep_permissions(arenas[0], u64(page), true, false)
		lep_permissions(descriptor, u64(page), false, false)
		library := lep_libraries()[cycle]
		error_protocol := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss5ErrorMp') or { panic(err) }
		assert error_protocol == arenas[2] + u64(page) + 240
		module_descriptor := arenas[1] + u64(page) + 64
		entries := lep_graph(descriptor, module_descriptor, error_protocol, false)
		for symbol in ['_$s10Foundation4DateVMn', '_$s10Foundation3URLVMn']! {
			nominal := runtime_symbol(library, symbol) or { panic(err) }
			assert lep_relative(nominal + 4) == module_descriptor
		}
		for i, symbol in lep_defaults() {
			assert entries[i] == arenas[0] + u64(i * 16)
			for alias in lep_libraries() {
				assert runtime_symbol(alias, symbol) == none
				for extension in lep_extensions() {
					assert runtime_symbol(alias, extension) or { panic(err) } != entries[i]
				}
			}
		}
		ios_runtime.swift_localized_error_protocol_retired = true
		lep_rejected()
		assert lep_arenas() == arenas
		ios_runtime.swift_localized_error_protocol_retired = false
		ios_runtime.swift_concurrency_retired = true
		lep_rejected()
		assert lep_arenas() == arenas
		ios_runtime.swift_concurrency_retired = false
		lep_call_cases(entries, guard, self, probe)
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_objc_metadata.len == 0 && ios_runtime.live == 0
		assert ios_runtime.swift_array_arena == 0 && ios_runtime.swift_bool_metadata_arena == 0
		assert ios_runtime.swift_hash_code == 0
		objc_stop()
		assert ios_runtime.swift_localized_error_protocol_retired
		lep_empty()
		assert ios_runtime.live == 0
		for arena in arenas {
			lep_unmapped(arena, page)
			lep_unmapped(arena + u64(page), page)
		}
		lep_rejected()
		lep_empty()
		unsafe {
			resolved.free()
			workers.free()
		}
	}
	assert C.munmap(voidptr(guard), page * 3) == 0
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-SWIFT-LOCALIZED-ERROR-PROTOCOL: exact inherited declaration and canonical Foundation/Error identities, seven data aliases and four independent nil default getters, guarded Swift ABI and concurrent publication through both Foundation libraries, exact RO/RX pages, allocation-free rejected lookups and two fully drained/unmapped lifetimes')
}
