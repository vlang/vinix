// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFDictionary.h>
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFDictionaryGetCount(voidptr) i64
fn C.CFGetTypeID(voidptr) u64
fn C.CFDictionaryGetTypeID() u64
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type McProbe = fn (u64, u64, u64, u64, &u64)
type McLookup = fn (u64, u64, u64) u64
type McUTF8 = fn (u64, u64) u64
type McRelease = fn (u64)
type McCopy = fn (u64, u64, u64) u64
type McDestroy = fn (u64, u64)

struct McApi {
	native          bool
	metadata        u64
	table           u64
	descriptor      u64
	protocol        u64
	string_metadata u64
	lookup          u64
	utf8            u64
	release         u64
}

fn mc_symbol(native bool, symbol string) u64 {
	if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		address := u64(C.dlsym(core, symbol[1..].str))
		assert address != 0
		return address
	}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
}

fn mc_api(native bool) McApi {
	return McApi{ native: native, metadata: mc_symbol(native, '_$ss11_MergeErrorON'), table: mc_symbol(native, '_$ss11_MergeErrorOs0B0sWP'), descriptor: mc_symbol(native, '_$ss11_MergeErrorOs0B0sMc'), protocol: mc_symbol(native, '_$ss5ErrorMp'), string_metadata: mc_symbol(native, '_$sSSN'), lookup: mc_symbol(native, '_swift_getWitnessTable'), utf8: mc_symbol(native, '_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg'), release: mc_symbol(native, '_swift_bridgeObjectRelease') }
}

fn mc_relative(address u64) u64 { return u64(i64(address) + i64(i32(read32(address)))) }

fn mc_entry(api McApi, slot int) u64 {
	address := read64(api.table + u64(slot * 8))
	return if api.native { address & 0x0000ffffffffffff } else { address }
}

fn mc_call(api McApi, probe u64, receiver u64, slot int) [4]u64 {
	mut output := [4]u64{}
	unsafe { McProbe(voidptr(probe))(receiver, api.metadata, api.table, mc_entry(api, slot), &output[0]) }
	assert output[2] == receiver && output[3] == 0x5121
	return output
}

fn mc_text(api McApi, words SwiftStringWords) {
	array := unsafe { McUTF8(voidptr(api.utf8))(words.first, words.second) }
	assert read64(array + 16) == 18 && C.memcmp(voidptr(array + 32), c'Swift._MergeError', 18) == 0
	unsafe { McRelease(voidptr(api.release))(array) }
}

fn mc_dictionary(api McApi, dictionary u64) {
	assert dictionary != 0
	$if macos {
		if api.native {
			assert C.CFGetTypeID(voidptr(dictionary)) == C.CFDictionaryGetTypeID() && C.CFDictionaryGetCount(voidptr(dictionary)) == 0
			return
		}
	}
	assert objc_is_kind(dictionary, ios_runtime.names['NSDictionary']) && obj_header(dictionary).keys.len == 0
}

fn mc_drop_dictionary(api McApi, dictionary u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(dictionary))
			return
		}
	}
	objc_release(dictionary)
}

fn mc_suite(api McApi, probe u64, guard u64) {
	assert read64(api.table) & 0x0000ffffffffffff == api.descriptor
	bits := read32(api.descriptor)
	field := u64(i64(api.descriptor) + i64(i32(bits & ~u32(1))))
	assert (if bits & 1 != 0 { read64(field) } else { field }) == api.protocol
	assert mc_relative(api.descriptor + 4) == read64(api.metadata + 8) && mc_relative(api.descriptor + 8) == api.table && read32(api.descriptor + 12) == 0
	assert unsafe { McLookup(voidptr(api.lookup))(api.descriptor, api.metadata, guard) } == api.table
	// String results remain independently owned through copy/take/destruction;
	// the zero-sized receiver itself needs no storage at either guard boundary.
	for receiver in [u64(0), guard, guard + u64(C.getpagesize())]! {
		result := mc_call(api, probe, receiver, 1)
		mut source := SwiftStringWords{ first: result[0], second: result[1] }
		mut copy := SwiftStringWords{}
		witness := read64(api.string_metadata - 8) & 0x0000ffffffffffff
		copy_entry := read64(witness + 16) & 0x0000ffffffffffff
		destroy := unsafe { McDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
		assert unsafe { McCopy(voidptr(copy_entry))(u64(&copy), u64(&source), api.string_metadata) } == u64(&copy)
		destroy(u64(unsafe { &source }), api.string_metadata)
		mc_text(api, copy)
		mut taken := SwiftStringWords{}
		assert unsafe { McCopy(voidptr(read64(witness + 32) & 0x0000ffffffffffff))(u64(&taken), u64(&copy), api.string_metadata) } == u64(&taken)
		mc_text(api, taken)
		destroy(u64(unsafe { &taken }), api.string_metadata)
		assert mc_call(api, probe, receiver, 2)[0] == 0
		first := mc_call(api, probe, receiver, 3)[0]
		second := mc_call(api, probe, receiver, 3)[0]
		mc_dictionary(api, first)
		mc_dictionary(api, second)
		mc_drop_dictionary(api, first)
		mc_dictionary(api, second)
		mc_drop_dictionary(api, second)
		assert mc_call(api, probe, receiver, 4)[0] == 0
	}
	$if macos {
		if !api.native {
			// A real native Swift consumer resolves this concrete descriptor and
			// decodes the compatibility witness's frozen String representation.
			native := mc_api(true)
			assert unsafe { McLookup(voidptr(native.lookup))(api.descriptor, api.metadata, guard) } == api.table
			words := mc_call(api, probe, guard, 1)
			mc_text(native, SwiftStringWords{ first: words[0], second: words[1] })
		}
	}
}

fn mc_publish() u64 { return mc_symbol(false, '_$ss11_MergeErrorOs0B0sWP') }

fn mc_worker(api McApi, probe u64, guard u64) {
	for _ in 0 .. 32 {
		assert mc_publish() == api.table
		result := mc_call(api, probe, guard, 1)
		mc_text(api, SwiftStringWords{ first: result[0], second: result[1] })
		unsafe { McRelease(voidptr(api.release))(result[1]) }
		assert mc_call(api, probe, guard, 2)[0] == 0 && mc_call(api, probe, guard, 4)[0] == 0
		info := mc_call(api, probe, guard, 3)[0]
		mc_dictionary(api, info)
		mc_drop_dictionary(api, info)
	}
}

fn mc_reject() {
	for symbol in ['_$ss11_MergeErrorOs0B0sWP', '_$ss11_MergeErrorOs0B0sMc']! {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
	}
	if _ := swift_merge_error_table_checked(0) {
		assert false
	}
}

fn test_swift_merge_error_conformance() {
	page := usize(C.getpagesize())
	probe := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert probe != ~u64(0) && guard != ~u64(0)
	defer {
		assert C.munmap(voidptr(probe), page) == 0
		assert C.munmap(voidptr(guard), page * 2) == 0
	}
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0303f0, 0xaa0003f4,
		0xaa0103e0, 0xaa0203e1, u32(0xd2800000 | (0x5121 << 5) | 21), 0xd63f0200, 0xa9000660,
		0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(probe + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(probe), voidptr(probe + 64))
	assert C.mprotect(voidptr(probe), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		mc_suite(mc_api(true), probe, guard)
		println('NATIVE-MERGE-ERROR-CONFORMANCE: concrete Error descriptor/table, owned Swift._MergeError domain, code zero, owned empty dictionary, nil embedded NSError, protected zero-size Self and preserved x20/x21')
	}
	mc_reject()
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn mc_publish() }
		values := publishers.wait()
		for value in values {
			assert value == values[0]
		}
		unsafe {
			values.free()
			publishers.free()
		}
		api := mc_api(false)
		mc_suite(api, probe, guard)
		measured := swift_merge_error_table_checked(api.metadata) or { panic(err) }
		assert measured == api.table
		for invalid in [u64(0), guard, ~u64(0), api.metadata + 8]! {
			if _ := swift_witness_table_checked(api.descriptor, invalid, guard) {
				assert false
			}
		}
		for symbol in ['_$ss11_MergeErrorOs0B0sWP', '_$ss11_MergeErrorOs0B0sMc']! {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol[1..]) == none
			for library in ['/usr/lib/swift/libswiftFoundation.dylib', '/usr/lib/libSystem.B.dylib']! {
				assert runtime_symbol(library, symbol) == none
			}
		}
		mc_protection(ios_runtime.swift_merge_error_metadata_arena, 128, true)
		mc_protection(api.table, 56, false)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn mc_worker(api, probe, guard) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		ios_runtime.swift_concurrency_retired = true
		mc_reject()
		ios_runtime.swift_concurrency_retired = false
		arena := ios_runtime.swift_merge_error_metadata_arena
		objc_stop()
		mc_reject()
		assert ios_runtime.swift_merge_error_metadata_arena == 0 && ios_runtime.swift_error_arena == 0
		assert ios_runtime.swift_merge_error_conformance_descriptor == api.descriptor
		if _ := swift_witness_table_checked(api.descriptor, guard, guard) {
			assert false
		}
		for offset in [u64(0), u64(page)]! {
			$if macos {
				assert C.mprotect(voidptr(arena + offset), page, C.PROT_READ) == -1
			} $else {
				mut state := u8(0)
				assert C.mincore(voidptr(arena + offset), page, &state) == -1
			}
		}
	}
	println('IOS-MERGE-ERROR-CONFORMANCE: canonical concrete Error table, four working witnesses and owned results, native String/table consumers, protected Self, sealed shared metadata pages, rejected foreign metadata/stale descriptors, eight cold publishers/workers and two drained/unmapped lifetimes')
}

fn mc_protection(address u64, length u64, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + length <= start + size && info[0] == (C.PROT_READ | if executable {
			C.PROT_EXEC
		} else {
			0
		})
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
				assert address + length <= end && fields[1] == if executable {
					'r-xp'
				} else {
					'r--p'
				}
				found = true
				break
			}
		}
		assert found
	}
}
