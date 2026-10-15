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

const localized_default_symbols = [
	'_$s10Foundation14LocalizedErrorPAAE16errorDescriptionSSSgvg',
	'_$s10Foundation14LocalizedErrorPAAE13failureReasonSSSgvg',
	'_$s10Foundation14LocalizedErrorPAAE18recoverySuggestionSSSgvg',
	'_$s10Foundation14LocalizedErrorPAAE10helpAnchorSSSgvg',
]!

type LocalizedProbe = fn (u64, u64, u64)

fn localized_pair(load bool, vector bool, first u32, second u32, base u32, offset int) u32 {
	width := if vector { 16 } else { 8 }
	assert offset % width == 0 && offset >= 0 && offset / width < 64
	op := if vector { u32(0xad000000) } else { u32(0xa9000000) }
	return op | (if load { u32(0x00400000) } else { u32(0) }) | (u32(offset / width) << 15) | (second << 10) | (base << 5) | first
}

fn localized_code(code u64) {
	mut ops := [u32(0xa9bc7bfd)]
	for i in 0 .. 3 {
		ops << localized_pair(false, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16)
	}
	ops << [u32(0xaa0003f0), 0xaa0103f4, 0xaa0203f3] // Entry, borrowed Self and output.
	for register in u32(0) .. 9 {
		if register != 1 { ops << u32(0xaa0103e0) | register } // All inputs point at the guard.
	}
	ops << u32(0xd2800000 | (0x7654 << 5) | 21)
	distance := u32(256 - ops.len * 4)
	ops << u32(0x10000017 | ((distance & 3) << 29) | ((distance >> 2) << 5))
	for i in 0 .. 4 { ops << localized_pair(true, true, u32(i * 2), u32(i * 2 + 1), 23, i * 32) }
	ops << u32(0xd63f0200) // blr x16.
	ops << localized_pair(false, false, 0, 1, 19, 0)
	ops << localized_pair(false, false, 20, 21, 19, 16)
	ops << u32(0xf9001268) // str x8,[x19,#32]; no indirect result write.
	for i in 0 .. 4 {
		ops << localized_pair(false, true, u32(i * 2), u32(i * 2 + 1), 19, 48 + i * 32)
	}
	for i in 0 .. 3 {
		ops << localized_pair(true, false, u32(19 + i * 2), u32(20 + i * 2), 31, 16 + i * 16)
	}
	ops << [u32(0xa8c47bfd), 0xd65f03c0]
	assert ops.len * 4 <= 256
	for i, op in ops { write32(code + u64(i * 4), op) }
	for i in 0 .. 16 {
		unsafe { *(&u64(code + 256 + u64(i * 8))) = u64(0x12340000 + i) }
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 384))
}

fn localized_call(entry u64, self u64, probe LocalizedProbe) {
	mut output := [26]u64{}
	output[0] = 0xcafe
	output[6] = 0xdead
	output[23] = 0xbeef
	output[24] = 0xface
	output[25] = 0xbabe
	probe(entry, self, u64(unsafe { &output[1] }))
	assert output[1] == 0 && output[2] == 0 // Optional<String>.none, not an empty String.
	assert output[3] == self && output[4] == 0x7654 && output[5] == self
	for i in 0 .. 16 {
		assert output[7 + i] == u64(0x12340000 + i)
	}
	assert output[0] == 0xcafe && output[6] == 0xdead && output[23] == 0xbeef
	assert output[24] == 0xface && output[25] == 0xbabe
}

fn localized_worker(entry u64, self u64, probe LocalizedProbe) {
	for _ in 0 .. 128 { localized_call(entry, self, probe) }
}

fn localized_cases(entry u64, probe LocalizedProbe) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	self := region + u64(page * 2) - 8
	unsafe { *(&u64(self)) = 0x0123456789abcdef }
	assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ) == 0
	for value in [u64(0), 1, ~u64(0), region, self]! {
		localized_call(entry, value, probe)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn localized_worker(entry, value, probe) }
		workers.wait()
		unsafe { workers.free() }
	}
	assert read64(self) == 0x0123456789abcdef
	assert C.munmap(voidptr(region), page * 3) == 0
}

fn localized_publish(index int) u64 {
	library := if index < 4 {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	} else {
		'/usr/lib/swift/libswiftFoundation.dylib'
	}
	mut entry := u64(0)
	for _ in 0 .. 256 {
		entry = runtime_symbol(library, localized_default_symbols[index % 4]) or { panic(err) }
	}
	return entry
}

fn test_swift_localized_error() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	localized_code(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { LocalizedProbe(voidptr(code)) }
	$if macos {
		mut native_entries := [4]u64{}
		for alias, library in [
			'/System/Library/Frameworks/Foundation.framework/Foundation',
			'/usr/lib/swift/libswiftFoundation.dylib',
		]! {
			handle := C.dlopen(library.str, 2)
			assert handle != unsafe { nil }
			for index, symbol in localized_default_symbols {
				name := symbol[1..]
				entry := u64(C.dlsym(handle, name.str))
				assert entry != 0
				if alias == 0 {
					native_entries[index] = entry
				} else {
					assert entry == native_entries[index]
				}
				for previous in 0 .. index {
					assert entry != native_entries[previous]
				}
				localized_cases(entry, probe)
			}
		}
		println('IOS-LOCALIZED-ERROR-NATIVE: four defaults return nil Optional<String> in x0/x1, preserve x8/x20/x21 and vectors, ignore guarded metadata/witness/Self/result inputs, unchanged read-only Self and concurrent callers through both Foundation names')
	}
	for symbol in localized_default_symbols {
		if _ := swift_foundation_symbol(symbol) {
			assert false
		}
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for i in 0 .. 8 { publishers << spawn localized_publish(i) }
		entries := publishers.wait()
		arena := ios_runtime.swift_foundation_arena
		for index, value in entries {
			assert value == arena + 256 + u64((index % 4) * 16)
		}
		localized_mapping(arena + u64(page), true, false)
		for index, symbol in localized_default_symbols {
			entry := entries[index]
			localized_mapping(entry, true, true)
			assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', symbol) or { panic(err) } == entry
			localized_cases(entry, probe)
			if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) {
				assert false
			}
			if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', symbol) {
				assert false
			}
		}
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		for entry in entries { localized_mapping(entry, false, false) }
		localized_mapping(arena + u64(page), false, false)
		for symbol in localized_default_symbols {
			if _ := swift_foundation_symbol(symbol) {
				assert false
			}
		}
		unsafe {
			entries.free()
			publishers.free()
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-LOCALIZED-ERROR: four exact default getter exports, register nil Optional<String> and unchanged Swift contexts/vectors without input access, ARC or allocation; canonical concurrent aliases, sealed Foundation pages and two unmapped retirements')
}

fn localized_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 12 <= start + size && info[0] == (C.PROT_READ | if executable {
				C.PROT_EXEC
			} else {
				0
			})
		} else {
			assert status != 0 || start > address
		}
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
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
				assert mapped && address + 12 <= end && fields[1] == if executable {
					'r-xp'
				} else {
					'r--p'
				}
				found = true
				break
			}
		}
		assert found == mapped
	}
}
