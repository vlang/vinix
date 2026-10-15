// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

$if macos {
	#include <mach/mach.h>
	#include <objc/runtime.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr

const json_date_case_symbol = '_$s10Foundation11JSONEncoderC20DateEncodingStrategyO9formattedyAESo15NSDateFormatterCcAEmFWC'

type JSONDateLoad = fn (u64, u64, u64, &u64)
type JSONDateAccess = fn (u64) SwiftAssociatedMetadata
type JSONDateNew = fn (u64, u64) u64
type JSONDateInject = fn (u64, u32, u64)
type JSONDateTag = fn (u64, u64) u32
type JSONDateCopy = fn (u64, u64, u64) u64
type JSONDateDestroy = fn (u64, u64)

fn json_date_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 4 <= start + size
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
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
				assert mapped && address + 4 <= end && fields[1] == if executable {
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

fn json_date_load_case(entry u64, probe JSONDateLoad, protected u64) {
	mut output := [u32(0xcafe), 0xdeadbeef, 0xbeef]!
	mut observations := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	destination := u64(unsafe { &output[1] })
	probe(entry, destination, protected, unsafe { &observations[1] })
	assert output == [u32(0xcafe), 0, 0xbeef]!
	assert observations == [u64(0xcafe), entry, destination, protected, 0x5021, 0xbeef]!
}

fn json_date_worker(entry u64, probe JSONDateLoad, protected u64) {
	for _ in 0 .. 128 { json_date_load_case(entry, probe, protected) }
}

fn json_date_spans(entry u64, probe JSONDateLoad) {
	page := usize(C.getpagesize())
	source := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	destination := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert source != u64(-1) && destination != u64(-1)
	assert C.mprotect(voidptr(destination + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	for source_end in [false, true]! {
		assert C.mprotect(voidptr(source + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
		input := source + u64(page) + if source_end { u64(page) - 4 } else { u64(0) }
		write32(input, read32(entry))
		assert C.mprotect(voidptr(source + u64(page)), page, C.PROT_READ) == 0
		json_date_load_case(input, probe, source)
		for output_end in [false, true]! {
			output := destination + u64(page) + if output_end { u64(page) - 4 } else { u64(0) }
			write32(output, 0xdeadbeef)
			mut observations := [4]u64{}
			probe(input, output, source, unsafe { &observations[0] })
			assert read32(output) == 0 && observations == [input, output, source, u64(0x5021)]!
		}
	}
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn json_date_worker(entry, probe, source) }
	workers.wait()
	assert C.munmap(voidptr(source), page * 3) == 0 && C.munmap(voidptr(destination), page * 3) == 0
}

fn json_date_native_payload(value u32) {
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert foundation != unsafe { nil } && objc != unsafe { nil }
		access := unsafe { JSONDateAccess(C.dlsym(foundation, c'$s10Foundation11JSONEncoderC20DateEncodingStrategyOMa')) }
		response := access(0)
		assert response.state == 0
		metadata := response.metadata
		witness := read64(metadata - 8) & 0x0000ffffffffffff
		assert read64(witness + 64) == 17 && read64(witness + 72) == 24
		inject := unsafe { JSONDateInject(voidptr(read64(witness + 104) & 0x0000ffffffffffff)) }
		tag := unsafe { JSONDateTag(voidptr(read64(witness + 88) & 0x0000ffffffffffff)) }
		copy_value := unsafe { JSONDateCopy(voidptr(read64(witness + 16) & 0x0000ffffffffffff)) }
		destroy := unsafe { JSONDateDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
		create := unsafe { JSONDateNew(C.dlsym(objc, c'objc_msgSend')) }
		cls := u64(C.objc_getClass(c'NSDateFormatter'))
		assert cls != 0
		formatter := create(cls, u64(C.sel_registerName(c'new')))
		assert formatter != 0
		mut storage := [16]u64{}
		source := u64(unsafe { &storage[0] })
		destination := source + 64
		unsafe { *(&u64(source)) = formatter }
		inject(source, value, metadata)
		assert tag(source, metadata) == value
		assert copy_value(destination, source, metadata) == destination && tag(destination, metadata) == value
		assert read64(source) == formatter && read64(destination) == formatter
		destroy(source, metadata)
		assert tag(destination, metadata) == value
		destroy(destination, metadata)
	}
}

fn json_date_publish(framework bool) u64 {
	library := if framework {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	} else {
		'/usr/lib/swift/libswiftFoundation.dylib'
	}
	return runtime_symbol(library, json_date_case_symbol) or { panic(err) }
}

fn test_swift_json_encoder_date_case() {
	$if !arm64 {
		return
	}
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	// Real ARM64 u32 data consumer: no call through the export, no ARC and
	// no read beyond its four-byte extent. Capture the borrowed addresses.
	for i, op in [u32(0xa9bf57f4), 0xb9400004, 0xb9000024, 0xa9000460, 0xaa0203f4, 0xd28a0435,
		0xa9015474, 0xa8c157f4, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 36))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { JSONDateLoad(voidptr(code)) }
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		overlay := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', 2)
		assert foundation != unsafe { nil } && overlay != unsafe { nil }
		entry := u64(C.dlsym(foundation, c'$s10Foundation11JSONEncoderC20DateEncodingStrategyO9formattedyAESo15NSDateFormatterCcAEmFWC'))
		assert entry != 0 && entry == u64(C.dlsym(overlay, c'$s10Foundation11JSONEncoderC20DateEncodingStrategyO9formattedyAESo15NSDateFormatterCcAEmFWC'))
		assert entry & 3 == 0 && read32(entry) == 0
		json_date_spans(entry, probe)
		json_date_native_payload(read32(entry))
		println('IOS-JSON-DATE-CASE-NATIVE: canonical four-byte zero discriminator through both Foundation aliases, real ARM64 data loads, exact guarded read/write spans and canaries, native formatted payload injection/copy/destruction, eight concurrent readers')
	}
	if _ := swift_foundation_symbol(json_date_case_symbol) {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		mut publishers := []thread u64{}
		for i in 0 .. 8 { publishers << spawn json_date_publish(i % 2 == 0) }
		entries := publishers.wait()
		entry := entries[0]
		for candidate in entries {
			assert candidate == entry
		}
		arena := ios_runtime.swift_foundation_arena
		assert entry == arena + u64(page) + 96 && entry & 3 == 0 && read32(entry) == 0
		json_date_mapping(entry, true, false)
		json_date_mapping(arena, true, true)
		json_date_spans(entry, probe)
		json_date_native_payload(read32(entry))
		for symbol in ['_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMa',
			'_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMn',
			'_$s10Foundation11JSONEncoderCACycfc']! {
			if _ := swift_foundation_symbol(symbol) {
				assert false
			}
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', json_date_case_symbol) {
			assert false
		}
		if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', json_date_case_symbol) {
			assert false
		}
		assert ios_runtime.live == baseline && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		json_date_mapping(entry, false, false)
		json_date_mapping(arena, false, false)
		if _ := swift_foundation_symbol(json_date_case_symbol) {
			assert false
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-JSON-DATE-CASE: exact read-only u32 enum data export, native payload-case meaning, guarded four-byte consumers, concurrent alias publication/readers and two unmapped retirements; strategy metadata, formatter/encoder methods and default backend remain unsupported')
}
