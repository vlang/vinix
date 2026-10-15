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

const calendar_case_symbol = '_$s10Foundation8CalendarV10IdentifierO7iso8601yA2EmFWC'

type CalendarCaseLoad = fn (u64, u64, u64, &u64)
type CalendarCaseAccess = fn (u64) SwiftAssociatedMetadata
type CalendarCaseInject = fn (u64, u32, u64)
type CalendarCaseTag = fn (u64, u64) u32
type CalendarCaseCopy = fn (u64, u64, u64) u64
type CalendarCaseDestroy = fn (u64, u64)
type CalendarIdentifierProbe = fn (u64, u64, u64, &u64)
type CalendarIdentifierGet = fn (u64, u32, u64) u32
type CalendarIdentifierStore = fn (u64, u32, u32, u64)
type CalendarIdentifierLookup = fn (u64, u64, u64, u64, u64) u64

fn calendar_identifier_relative(address u64) u64 {
	delta := i32(read32(address))
	return if delta == 0 { u64(0) } else { u64(i64(address) + i64(delta)) }
}

fn calendar_identifier_entries(native bool, overlay bool) [2]u64 {
	library := if overlay { '/usr/lib/swift/libswiftFoundation.dylib' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
	mut entries := [2]u64{}
	for i, symbol in ['_$s10Foundation8CalendarV10IdentifierOMa', '_$s10Foundation8CalendarV10IdentifierOMn']! {
		if native {
			handle := C.dlopen(library.str, 2)
			assert handle != unsafe { nil }
			entries[i] = u64(C.dlsym(handle, symbol[1..].str))
		} else {
			entries[i] = runtime_symbol(library, symbol) or { panic(err) }
		}
		assert entries[i] != 0
	}
	return entries
}

fn calendar_identifier_padding(start u64, page u64, value u64, width u64) {
	for offset in u64(0) .. page {
		address := start + offset
		if address < value || address >= value + width { assert unsafe { *(&u8(address)) } == 0xa5 }
	}
}

fn calendar_identifier_values(metadata u64) {
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	destroy := unsafe { CalendarCaseDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	project := unsafe { CalendarCaseDestroy(voidptr(read64(witness + 96) & 0x0000ffffffffffff)) }
	inject := unsafe { CalendarCaseInject(voidptr(read64(witness + 104) & 0x0000ffffffffffff)) }
	tag := unsafe { CalendarCaseTag(voidptr(read64(witness + 88) & 0x0000ffffffffffff)) }
	get_tag := unsafe { CalendarIdentifierGet(voidptr(read64(witness + 48) & 0x0000ffffffffffff)) }
	store_tag := unsafe { CalendarIdentifierStore(voidptr(read64(witness + 56) & 0x0000ffffffffffff)) }
	// These witnesses must not read even value/metadata when there is no work.
	destroy(span, span)
	project(span, span)
	assert get_tag(span, 0, span) == 0
	store_tag(span, 0, 0, span)
	for source_end in [false, true]! {
		for destination_end in [false, true]! {
			source := span + u64(page) + if source_end { u64(page) - 1 } else { u64(0) }
			destination := span + u64(page * 3) + if destination_end { u64(page) - 1 } else { u64(0) }
			assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
			for which in u32(0) .. 27 {
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
				unsafe { *(&u8(source)) = u8(which) }
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
				assert tag(source, span) == which
				destroy(source, span)
				project(source, span)
				for slot in [u64(0), 16, 24, 32, 40]! {
					transfer := unsafe { CalendarCaseCopy(voidptr(read64(witness + slot) & 0x0000ffffffffffff)) }
					C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
					assert transfer(destination, source, span) == destination
					assert transfer(destination, destination, span) == destination
					assert unsafe { *(&u8(source)) } == u8(which)
					assert unsafe { *(&u8(destination)) } == u8(which)
					calendar_identifier_padding(span + u64(page * 3), u64(page), destination, 1)
				}
			}
			for which in [u32(0), 1, 7, 26, 27, 255, 256, 0xffffffff]! {
				C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
				inject(destination, which, span)
				assert tag(destination, span) == u32(u8(which))
				calendar_identifier_padding(span + u64(page * 3), u64(page), destination, 1)
			}
		}
	}
	// Native byte-width boundaries are conservative. The extreme UInt32 counts
	// wrap their count+26 calculation and may truncate a stored empty-case tag.
	for pair in [[u32(0), 0]!, [u32(1), 0]!, [u32(27), 0]!, [u32(228), 0]!,
		[u32(229), 0]!, [u32(230), 1]!, [u32(231), 1]!, [u32(256), 1]!,
		[u32(65253), 1]!, [u32(65254), 2]!, [u32(65509), 2]!, [u32(65510), 2]!,
		[u32(16776933), 2]!, [u32(16776934), 4]!, [u32(16777189), 4]!,
		[u32(16777190), 4]!, [u32(0x7fffffff), 4]!, [u32(0xffffffe5), 4]!,
		[u32(0xffffffe6), 1]!, [u32(0xffffffff), 1]!]! {
		cases := pair[0]
		width := u64(pair[1])
		for which in [u32(0), 1, 27, 228, 229, 230, 231, 255, 256, 485, 486,
			65253, 65254, 65509, 65510, 16776933, 16776934, 16777189, 16777190,
			0x7fffffff, 0xffffffe5, 0xffffffe6, 0xffffffff]! {
			if which > cases { continue }
			for at_end in [false, true]! {
				value := span + u64(page * 3) + if at_end { u64(page) - 1 - width } else { u64(0) }
				C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
				unsafe { *(&u8(value)) = 7 }
				store_tag(value, which, cases, span)
				payload := if which == 0 { u8(7) } else if which <= 229 { u8(which + 26) } else { u8(which - 230) }
				assert unsafe { *(&u8(value)) } == payload
				bits := if which <= 229 { u32(0) } else { ((which - 230) >> 8) + 1 }
				mut stored := u32(0)
				for i in u64(0) .. width {
					byte := unsafe { *(&u8(value + 1 + i)) }
					assert byte == u8(bits >> (i * 8))
					stored |= u32(byte) << (i * 8)
				}
				expected := if cases == 0 { u32(0) } else if stored != 0 {
					((stored - 1) << 8) + u32(payload) + 230
				} else if payload < 27 { u32(0) } else { u32(payload) - 26 }
				assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
				assert get_tag(value, cases, span) == expected
				calendar_identifier_padding(span + u64(page * 3), u64(page), value, 1 + width)
				assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
			}
		}
	}
	assert C.munmap(voidptr(span), page * 5) == 0
}

fn calendar_identifier_worker(metadata u64) {
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	inject := unsafe { CalendarCaseInject(voidptr(read64(witness + 104) & 0x0000ffffffffffff)) }
	tag := unsafe { CalendarCaseTag(voidptr(read64(witness + 88) & 0x0000ffffffffffff)) }
	for i in u32(0) .. 128 {
		mut storage := [u8(0xca), 0xfe, 0xbe]!
		value := u64(unsafe { &storage[1] })
		inject(value, i % 27, metadata)
		assert tag(value, metadata) == i % 27 && storage[0] == 0xca && storage[2] == 0xbe
	}
}

fn calendar_identifier_suite(native bool, code u64) u64 {
	entries := calendar_identifier_entries(native, false)
	assert calendar_identifier_entries(native, true) == entries
	response := unsafe { CalendarCaseAccess(voidptr(entries[0]))(0) }
	assert response.state == 0
	metadata := response.metadata
	descriptor := entries[1]
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	assert read64(metadata) == 0x201 && (read64(metadata + 8) & 0x0000ffffffffffff) == descriptor
	assert read64(witness + 64) == 1 && read64(witness + 72) == 1
	assert read32(witness + 80) == 0x02200000 && read32(witness + 84) == 229
	assert read32(descriptor) == 0x52 && read32(descriptor + 20) == 0 && read32(descriptor + 24) == 27
	assert unsafe { (&char(calendar_identifier_relative(descriptor + 8))).vstring() } == 'Identifier'
	parent := calendar_identifier_relative(descriptor + 4)
	assert read32(parent) & 31 == 17
	assert unsafe { (&char(calendar_identifier_relative(parent + 8))).vstring() } == 'Calendar'
	module_descriptor := calendar_identifier_relative(parent + 4)
	assert unsafe { (&char(calendar_identifier_relative(module_descriptor + 8))).vstring() } == 'Foundation'
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	probe := unsafe { CalendarIdentifierProbe(voidptr(code + 64)) }
	for accessor in [entries[0], calendar_identifier_relative(descriptor + 12)]! {
		for request in [u64(0), 0x3f, 0xff, 0x100, 0x1ff, ~u64(0)]! {
			mut output := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
			probe(request, accessor, span, unsafe { &output[1] })
			assert output == [u64(0xcafe), metadata, 0, span, 0x5021, 0xbeef]!
		}
	}
	assert C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
	name := span + u64(page) - 5
	unsafe { *(&u8(name)) = 2; *(&u64(span + 16)) = descriptor }
	delta := i32(i64(span + 16) - i64(name + 1))
	C.memcpy(voidptr(name + 1), unsafe { &delta }, 4)
	assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
	mut lookup := unsafe { CalendarIdentifierLookup(voidptr(swift_mangled_state_lookup)) }
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		lookup = unsafe { CalendarIdentifierLookup(C.dlsym(core, c'swift_getTypeByMangledNameInContextInMetadataState')) }
	} }
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x1ff]! { assert lookup(request, name, 5, 0, 0) == metadata }
	assert C.munmap(voidptr(span), page * 2) == 0
	calendar_identifier_values(metadata)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn calendar_identifier_worker(metadata) }
	workers.wait()
	if !native {
		assert calendar_identifier_relative(descriptor + 16) == 0 && calendar_identifier_relative(parent + 12) == 0
		calendar_case_mapping(entries[0], true, true)
		calendar_case_mapping(metadata, true, false)
		calendar_case_mapping(descriptor, true, false)
	}
	return metadata
}

fn calendar_case_mapping(address u64, mapped bool, executable bool) {
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

fn calendar_case_load_case(entry u64, probe CalendarCaseLoad, protected u64) {
	mut output := [u32(0xcafe), 0xdeadbeef, 0xbeef]!
	mut observations := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	destination := u64(unsafe { &output[1] })
	probe(entry, destination, protected, unsafe { &observations[1] })
	assert output == [u32(0xcafe), 7, 0xbeef]!
	assert observations == [u64(0xcafe), entry, destination, protected, 0x5021, 0xbeef]!
}

fn calendar_case_worker(entry u64, probe CalendarCaseLoad, protected u64) {
	for _ in 0 .. 128 { calendar_case_load_case(entry, probe, protected) }
}

fn calendar_case_spans(entry u64, probe CalendarCaseLoad) {
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
		calendar_case_load_case(input, probe, source)
		for output_end in [false, true]! {
			output := destination + u64(page) + if output_end { u64(page) - 4 } else { u64(0) }
			write32(output, 0xdeadbeef)
			mut observations := [4]u64{}
			probe(input, output, source, unsafe { &observations[0] })
			assert read32(output) == 7 && observations == [input, output, source, u64(0x5021)]!
		}
	}
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn calendar_case_worker(entry, probe, source) }
	workers.wait()
	assert C.munmap(voidptr(source), page * 3) == 0 && C.munmap(voidptr(destination), page * 3) == 0
}

fn calendar_case_native_payload(value u32) {
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		assert foundation != unsafe { nil } && value == 7
		access := unsafe { CalendarCaseAccess(C.dlsym(foundation, c'$s10Foundation8CalendarV10IdentifierOMa')) }
		response := access(0)
		assert response.state == 0
		metadata := response.metadata
		witness := read64(metadata - 8) & 0x0000ffffffffffff
		assert read64(witness + 64) == 1 && read64(witness + 72) == 1
		inject := unsafe { CalendarCaseInject(voidptr(read64(witness + 104) & 0x0000ffffffffffff)) }
		tag := unsafe { CalendarCaseTag(voidptr(read64(witness + 88) & 0x0000ffffffffffff)) }
		copy_value := unsafe { CalendarCaseCopy(voidptr(read64(witness + 16) & 0x0000ffffffffffff)) }
		destroy := unsafe { CalendarCaseDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
		mut source := [u8(0xca), 0xfe, 0xbe]!
		mut destination := [u8(0xca), 0xfe, 0xbe]!
		a := u64(unsafe { &source[1] })
		b := u64(unsafe { &destination[1] })
		inject(a, value, metadata)
		assert tag(a, metadata) == value
		assert copy_value(b, a, metadata) == b && tag(b, metadata) == value
		destroy(a, metadata)
		assert tag(b, metadata) == value
		destroy(b, metadata)
		assert source == [u8(0xca), 7, 0xbe]! && destination == source
	}
}

fn calendar_case_publish(framework bool) u64 {
	library := if framework {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	} else {
		'/usr/lib/swift/libswiftFoundation.dylib'
	}
	entries := calendar_identifier_entries(false, !framework)
	for _ in 0 .. 32 { assert calendar_identifier_entries(false, framework) == entries }
	return runtime_symbol(library, calendar_case_symbol) or { panic(err) }
}

fn test_swift_calendar_case() {
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
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0103f0,
		0xaa0203f4, 0xaa0203e8, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 64 + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 124))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { CalendarCaseLoad(voidptr(code)) }
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		overlay := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', 2)
		assert foundation != unsafe { nil } && overlay != unsafe { nil }
		entry := u64(C.dlsym(foundation, c'$s10Foundation8CalendarV10IdentifierO7iso8601yA2EmFWC'))
		assert entry != 0 && entry == u64(C.dlsym(overlay, c'$s10Foundation8CalendarV10IdentifierO7iso8601yA2EmFWC'))
		assert entry & 3 == 0 && read32(entry) == 7
		calendar_case_spans(entry, probe)
		calendar_case_native_payload(read32(entry))
		calendar_identifier_suite(true, code)
		println('IOS-SWIFT-CALENDAR-CASE-NATIVE: complete nested Identifier metadata, all one-byte value/enum witnesses, 27 cases, guarded copies and optional-tag width/wraparound matrix, bounded symbolic lookup, concurrent values and ISO 8601 case data measured')
	}
	if _ := swift_foundation_symbol(calendar_case_symbol) {
		assert false
	}
	for symbol in ['_$s10Foundation8CalendarV10IdentifierOMa', '_$s10Foundation8CalendarV10IdentifierOMn']! {
		if _ := swift_foundation_symbol(symbol) { assert false }
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		mut publishers := []thread u64{}
		for i in 0 .. 8 { publishers << spawn calendar_case_publish(i % 2 == 0) }
		entries := publishers.wait()
		entry := entries[0]
		for candidate in entries {
			assert candidate == entry
		}
		arena := ios_runtime.swift_foundation_arena
		assert entry == arena + u64(page) + 800 && entry & 3 == 0 && read32(entry) == 7
		calendar_case_mapping(entry, true, false)
		calendar_case_mapping(arena, true, true)
		calendar_case_spans(entry, probe)
		calendar_case_native_payload(read32(entry))
		metadata := calendar_identifier_suite(false, code)
		assert metadata == arena + u64(page) + 1520
		for symbol in ['_$s10Foundation8CalendarVMa', '_$s10Foundation8CalendarVMn', '_$s10Foundation8CalendarV10IdentifierO9gregorianyA2EmFWC', '_$s10Foundation8CalendarV10identifierA2C10IdentifierOh_tcfC']! {
			if _ := swift_foundation_symbol(symbol) {
				assert false
			}
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', calendar_case_symbol) {
			assert false
		}
		if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', calendar_case_symbol) {
			assert false
		}
		for symbol in ['_$s10Foundation8CalendarV10IdentifierOMa', '_$s10Foundation8CalendarV10IdentifierOMn']! {
			for library in ['/usr/lib/swift/libswiftCore.dylib', '/System/Library/Frameworks/UIKit.framework/UIKit']! {
				if _ := runtime_symbol(library, symbol) { assert false }
			}
		}
		assert ios_runtime.live == baseline && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		calendar_case_mapping(entry, false, false)
		calendar_case_mapping(arena, false, false)
		calendar_case_mapping(metadata, false, false)
		if _ := swift_foundation_symbol(calendar_case_symbol) {
			assert false
		}
		for symbol in ['_$s10Foundation8CalendarV10IdentifierOMa', '_$s10Foundation8CalendarV10IdentifierOMn']! {
			if _ := swift_foundation_symbol(symbol) { assert false }
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-SWIFT-CALENDAR-CASE: complete Calendar.Identifier metadata, nested nominal identity, one-byte POD witnesses, guarded 27-case and optional-tag width/wraparound matrix, symbolic lookup, concurrent publication/values, ISO 8601 case export and two drained/unmapped runtimes; Calendar construction and other case exports remain unsupported')
}
