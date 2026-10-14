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
type CocoaCodeProbe = fn (u64, u64, u64, &u64)
type CocoaCodeAccess = fn (u64) SwiftAssociatedMetadata

fn cocoa_code_mapping(address u64, length u64, mapped bool, executable bool) {
	$if macos {
		mut start := address; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0); task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + length <= start + size
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
		} else { assert status != 0 || start > address }
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields(); if fields.len < 2 { continue }; range := fields[0].split('-'); if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }; end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert mapped && address + length <= end && fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true; break
			}
		}; assert found == mapped
	}
}
fn cocoa_code_cases(entry u64, probe CocoaCodeProbe, guard u64, page u64, raw_reader u64) {
	for seed in [u64(0), 0x1122334455667788, ~u64(0)]! {
		mut output := [u64(0xcafe), seed, 0xbeef]!
		mut context := [u64(0xcafe), 0, 0, 0xbeef]!
		probe(entry, u64(unsafe { &output[1] }), guard, unsafe { &context[1] })
		assert output == [u64(0xcafe), 516, 0xbeef]!
		assert context == [u64(0xcafe), guard, 0x5021, 0xbeef]!
		$if macos { if raw_reader != 0 {
			mut readback := [u64(0xcafe), 0, 0, 0, 0xbeef]!
			reader := unsafe { CocoaCodeProbe(voidptr(u64(voidptr(probe)) + 128)) }
			reader(raw_reader, u64(unsafe { &output[1] }), guard, unsafe { &readback[1] })
			assert readback == [u64(0xcafe), 516, u64(unsafe { &output[1] }), 0x5021, 0xbeef]!
		} }
	}
	// The sole writable result word touches either edge of a guarded page.
	for destination in [guard + page, guard + page * 2 - 8]! {
		unsafe { *(&u64(destination)) = ~u64(0) }; mut context := [2]u64{}
		probe(entry, destination, guard, unsafe { &context[0] })
		assert read64(destination) == 516 && context == [guard, u64(0x5021)]!
	}
}
fn cocoa_code_worker(entry u64, probe CocoaCodeProbe, guard u64) {
	for _ in 0 .. 256 {
		mut output := [u64(0xcafe), ~u64(0), 0xbeef]!; mut context := [2]u64{}
		probe(entry, u64(unsafe { &output[1] }), guard, unsafe { &context[0] })
		assert output == [u64(0xcafe), 516, 0xbeef]! && context == [guard, u64(0x5021)]!
	}
}
fn cocoa_code_publish(framework bool) u64 {
	library := if framework { '/System/Library/Frameworks/Foundation.framework/Foundation' } else { '/usr/lib/swift/libswiftFoundation.dylib' }
	mut entry := u64(0)
	for _ in 0 .. 256 { entry = runtime_symbol(library, '_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ') or { panic(err) } }
	return entry
}
fn test_swift_cocoa_error_code() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	assert C.mprotect(unsafe { voidptr(guard + u64(page)) }, page, C.PROT_READ | C.PROT_WRITE) == 0
	// Ordinary entry/output/protected-unused/context -> Swift x8 result.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103e8, 0xaa0203f4,
		0xaa1403e0, 0xaa1403e1, 0xaa1403e2, 0xaa1403e3, 0xaa1403e4, 0xaa1403e5, 0xaa1403e6, 0xaa1403e7,
		0xd28a0435, 0xd63f0200, 0xa9005674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	// Native Code.rawValue consumes borrowed Self x20 and returns Int in x0.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103f4, 0xaa0203e0, 0xaa0203e8,
		0xd28a0435, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + 128 + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 192) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { CocoaCodeProbe(voidptr(code)) }; mut raw_reader := u64(0)
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', C.RTLD_NOW)
		overlay := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		assert foundation != unsafe { nil } && overlay != unsafe { nil }
		entry := u64(C.dlsym(foundation, c'$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ'))
		assert entry != 0 && entry == u64(C.dlsym(overlay, c'$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ'))
		raw_reader = u64(C.dlsym(foundation, c'$s10Foundation10CocoaErrorV4CodeV8rawValueSivg')); assert raw_reader != 0
		access := C.dlsym(foundation, c'$s10Foundation10CocoaErrorV4CodeVMa'); assert access != unsafe { nil }
		metadata := unsafe { CocoaCodeAccess(access)(0) }.metadata; witness := read64(metadata - 8)
		assert read64(witness + 64) == 8 && read64(witness + 72) == 8
		cocoa_code_cases(entry, probe, guard, u64(page), raw_reader)
		mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn cocoa_code_worker(entry, probe, guard) }; workers.wait()
		println('IOS-COCOA-CODE-NATIVE: indirect Code rawValue516, eight-byte native layout and rawValue consumer, protected unused arguments/Self, preserved x20/x21, result canaries/page boundaries, concurrent calls and both Foundation install names')
	}
	if _ := swift_foundation_symbol('_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ') { assert false }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		mut publishers := []thread u64{}; for i in 0 .. 8 { publishers << spawn cocoa_code_publish(i % 2 == 0) }
		entries := publishers.wait(); entry := entries[0]; for candidate in entries { assert candidate == entry }
		arena := ios_runtime.swift_foundation_arena; assert entry == arena + 128
		cocoa_code_mapping(entry, 12, true, true); cocoa_code_mapping(arena + u64(page), 96, true, false)
		cocoa_code_cases(entry, probe, guard, u64(page), raw_reader)
		mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn cocoa_code_worker(entry, probe, guard) }; workers.wait()
		for unsupported in ['_$s10Foundation10CocoaErrorV4CodeVMa', '_$s10Foundation10CocoaErrorV4CodeV8rawValueSivg',
			'_$s10Foundation10CocoaErrorV19fileWriteOutOfSpaceAC4CodeVvgZ']! { if _ := swift_foundation_symbol(unsupported) { assert false } }
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ') { assert false }
		if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ') { assert false }
		assert ios_runtime.live == baseline && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop(); assert ios_runtime.swift_foundation_arena == 0
		cocoa_code_mapping(arena, u64(page) * 2, false, false)
		if _ := swift_foundation_symbol('_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ') { assert false }
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0 && C.munmap(unsafe { voidptr(guard) }, page * 3) == 0
	println('IOS-COCOA-CODE: exact Foundation getter, native-compatible x8 word516 without input reads/ARC, sealed cached arena and concurrent publication, scoped export/lifetime guards, two unmapped teardowns')
}
