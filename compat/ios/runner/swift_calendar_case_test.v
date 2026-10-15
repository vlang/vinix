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
type CalendarProbe = fn (u64, u64, u64, u64, u64, &u64)
type CalendarObjectType = fn (u64) u64
type CalendarSign = fn (u64, u64) u64

struct CalendarApi {
	native bool
	entries [5]u64
	metadata u64
	witness u64
	probe CalendarProbe
}

fn calendar_api(native bool, code u64) CalendarApi {
	mut entries := [5]u64{}
	for i, symbol in ['_$s10Foundation8CalendarV10identifierA2C10IdentifierOh_tcfC',
		'_$s10Foundation8CalendarV10identifierAC10IdentifierOvg', '_$s10Foundation8CalendarVMa', '_$s10Foundation8CalendarVMn',
		'_$s10Foundation8CalendarV10startOfDay3forAA4DateVAG_tF']! {
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/swift/libswiftFoundation.dylib']! {
			mut address := u64(0)
			$if macos { if native { handle := C.dlopen(library.str, 2); address = u64(C.dlsym(handle, symbol[1..].str)) } }
			if !native { address = runtime_symbol(library, symbol) or { panic(err) } }
			assert address != 0 && (entries[i] == 0 || entries[i] == address)
			entries[i] = address
		}
	}
	response := unsafe { CalendarCaseAccess(voidptr(entries[2]))(0) }
	assert response.state == 0 && read64(response.metadata) == 0x200
	witness := read64(response.metadata - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 16 && read64(witness + 72) == 16
	assert read32(witness + 80) == 0x02010007 && read32(witness + 84) == 0x7fffffff
	assert read64(response.metadata + 8) & 0x0000ffffffffffff == entries[3]
	identifier_entries := calendar_identifier_entries(native, false)
	assert calendar_identifier_relative(identifier_entries[1] + 4) == entries[3]
	assert calendar_identifier_relative(entries[3] + 12) == entries[2]
	assert read32(entries[3] + 20) == 1 && read32(entries[3] + 24) == 2
	return CalendarApi{native: native, entries: entries, metadata: response.metadata, witness: witness, probe: unsafe { CalendarProbe(voidptr(code + 160)) }}
}

fn (api CalendarApi) call(entry u64, first u64, second u64, self u64, output u64) {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(entry, first, second, self, output, unsafe { &capture[1] })
	assert capture[0] == 0xcafe && capture[3] == self && capture[4] == 0x5021 && capture[5] == 0xbeef
}

fn (api CalendarApi) destroy(value u64) {
	unsafe { CalendarCaseDestroy(voidptr(read64(api.witness + 8) & 0x0000ffffffffffff))(value, api.metadata) }
}

fn calendar_value_case(api CalendarApi, which u8, source_end bool, result_end bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 7, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	for offset in [u64(1), 3, 5]! {
		assert C.mprotect(voidptr(span + u64(page) * offset), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(span + u64(page) * offset), 0xa5, page)
	}
	source := span + u64(page) + if source_end { u64(page) - 1 } else { u64(0) }
	value := span + u64(page * 3) + if result_end { u64(page) - 16 } else { u64(0) }
	output := span + u64(page * 5) + if result_end { u64(page) - 1 } else { u64(0) }
	unsafe { *(&u8(source)) = which }
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	api.call(api.entries[0], source, span, span, value)
	assert unsafe { *(&u8(source)) } == which
	calendar_identifier_padding(span + u64(page), u64(page), source, 1)
	calendar_identifier_padding(span + u64(page * 3), u64(page), value, 16)
	owner := read64(value)
	assert owner != 0 && read64(value + 8) != 0
	mut generation := u64(0)
	if !api.native {
		C.ios_objc_initialize_lock()
		storage := ios_runtime.swift_heap[owner] or { panic('missing Calendar owner') }
		generation = storage.generation
		C.ios_objc_initialize_unlock()
		assert storage.size == 24 && storage.mask == 7 && !storage.deiniting && read64(owner + 8) == 3
		assert read64(owner + 16) == u64(which)
	}
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
	api.call(api.entries[1], span, span, value, output)
	assert unsafe { *(&u8(output)) } == which
	calendar_identifier_padding(span + u64(page * 5), u64(page), output, 1)
	mut copies := [4]u64{}
	first := u64(unsafe { &copies[0] }); second := u64(unsafe { &copies[2] })
	for i, slot in [u64(0), 16]! {
		copy_value := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + slot) & 0x0000ffffffffffff)) }
		assert copy_value(u64(unsafe { &copies[i * 2] }), value, api.metadata) == u64(unsafe { &copies[i * 2] })
	}
	if !api.native { assert read64(owner + 8) == 3 + (u64(2) << 33) }
	assign_copy := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + 24) & 0x0000ffffffffffff)) }
	assert assign_copy(first, second, api.metadata) == first
	mut moved := [2]u64{}
	moved_value := u64(unsafe { &moved[0] })
	take_value := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + 32) & 0x0000ffffffffffff)) }
	assert take_value(moved_value, first, api.metadata) == moved_value
	assign_take := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + 40) & 0x0000ffffffffffff)) }
	assert assign_take(second, moved_value, api.metadata) == second
	api.destroy(value)
	if !api.native { assert read64(owner + 8) == 3 }
	unsafe { *(&u8(output)) = 0xa5 }
	api.call(api.entries[1], span, span, second, output)
	assert unsafe { *(&u8(output)) } == which
	api.destroy(second)
	if !api.native {
		C.ios_objc_initialize_lock()
		if storage := ios_runtime.swift_heap[owner] { assert storage.generation != generation }
		C.ios_objc_initialize_unlock()
	}
	assert unsafe { *(&u8(output)) } == which && unsafe { *(&u8(source)) } == which
	calendar_identifier_padding(span + u64(page * 5), u64(page), output, 1)
	assert C.munmap(voidptr(span), page * 7) == 0
}

fn calendar_values_worker(api CalendarApi) {
	for _ in 0 .. 8 { calendar_value_case(api, 7, true, false); calendar_value_case(api, 26, false, true) }
}

fn calendar_spy_identifier(metadata u64, table u64, owner u64, output u64) {
	assert owner == read64(table + 32) && output == read64(table + 40) && metadata == read64(table + 48)
	unsafe { *(&u8(output)) = 7 }
}

fn calendar_dispatch_case(api CalendarApi, code u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
	table := span + u64(page) + 64; self := span + u64(page) + 256; output := span + u64(page * 4) - 1
	mut original := [2]u64{}
	mut owner := u64(0)
	mut metadata := u64(0)
	mut callback := code + 256
	$if macos { if api.native {
		which := u8(7)
		api.call(api.entries[0], u64(unsafe { &which }), span, span, u64(unsafe { &original[0] }))
		owner = original[0]
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		metadata = unsafe { CalendarObjectType(C.dlsym(core, c'swift_getObjectType'))(owner) }
		callback = unsafe { CalendarSign(voidptr(code + 288))(callback, (table + 24) | (u64(64425) << 48)) }
	} }
	if !api.native { owner = objc_allocate(ios_runtime.names['NSObject']); metadata = swift_object_type(owner) }
	unsafe {
		*(&u64(table + 24)) = callback; *(&u64(table + 32)) = owner; *(&u64(table + 40)) = output; *(&u64(table + 48)) = metadata
		*(&SwiftURLWords(self)) = SwiftURLWords{owner: owner, table: table}
	}
	C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	api.call(api.entries[1], span, span, self, output)
	assert unsafe { *(&u8(output)) } == 7
	calendar_identifier_padding(span + u64(page * 3), u64(page), output, 1)
	if api.native { api.destroy(u64(unsafe { &original[0] })) } else {
		assert obj_header(owner).refs == 1
		objc_release(owner)
	}
	assert C.munmap(voidptr(span), page * 5) == 0
}

fn calendar_day_clamped_bits(bits u64) u64 {
	value := unsafe { *(&f64(&bits)) }
	if !(value > -211845067200.0) { return 0xc248a97998e00000 }
	if value > 15927175497600.0 { return 0x42acf8ab468f0000 }
	return bits
}

fn calendar_spy_day(component u64, date u64, metadata u64, table u64, owner u64, output u64) {
	assert unsafe { *(&u8(component)) } == 3
	assert owner == read64(table + 176) && metadata == read64(table + 184)
	assert read64(date) == read64(table + 192)
	assert date != read64(table + 216) && output != read64(table + 224)
	// A nil interval has no initialized payload. The caller must inspect only
	// the discriminator. Noncanonical tags follow the measured native branch.
	tag := u8(read64(table + 208))
	if tag != 1 {
		unsafe { *(&u64(output)) = read64(table + 200); *(&u64(output + 8)) = 0x7ff8000000001234 }
	}
	unsafe { *(&u8(output + 16)) = tag }
}

fn calendar_day_case(api CalendarApi, code u64, bits u64, tag u8, start u64, at_end bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 7, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	for index in [1, 3, 5]! {
		assert C.mprotect(voidptr(span + u64(page * usize(index))), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(span + u64(page * usize(index))), 0xa5, page)
	}
	source := span + u64(page) + if at_end { u64(page) - 8 } else { u64(0) }
	table := span + u64(page * 3) + 64; self := table + 256
	output := span + u64(page * 5) + if at_end { u64(page) - 8 } else { u64(0) }
	mut original := [2]u64{}
	mut owner := u64(0); mut metadata := u64(0); mut callback := code + 320
	$if macos { if api.native {
		which := u8(7)
		api.call(api.entries[0], u64(unsafe { &which }), span, span, u64(unsafe { &original[0] }))
		owner = original[0]
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		metadata = unsafe { CalendarObjectType(C.dlsym(core, c'swift_getObjectType'))(owner) }
		callback = unsafe { CalendarSign(voidptr(code + 288))(callback, (table + 160) | (u64(33412) << 48)) }
	} }
	if !api.native { owner = objc_allocate(ios_runtime.names['NSObject']); metadata = swift_object_type(owner) }
	unsafe {
		*(&u64(source)) = bits
		*(&u64(table + 160)) = callback; *(&u64(table + 176)) = owner; *(&u64(table + 184)) = metadata
		*(&u64(table + 192)) = calendar_day_clamped_bits(bits); *(&u64(table + 200)) = start; *(&u64(table + 208)) = u64(tag)
		*(&u64(table + 216)) = source; *(&u64(table + 224)) = output
		*(&SwiftURLWords(self)) = SwiftURLWords{owner: owner, table: table}
	}
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
	api.call(api.entries[4], source, span, self, output)
	mut expected := start
	if tag == 1 {
		value := unsafe { *(&f64(&bits)) } + f64(-1)
		expected = unsafe { *(&u64(&value)) }
	}
	assert read64(output) == expected && read64(source) == bits
	calendar_identifier_padding(span + u64(page), u64(page), source, 8)
	calendar_identifier_padding(span + u64(page * 5), u64(page), output, 8)
	if api.native { api.destroy(u64(unsafe { &original[0] })) } else {
		assert obj_header(owner).refs == 1
		objc_release(owner)
	}
	assert C.munmap(voidptr(span), page * 7) == 0
}

fn calendar_days_worker(api CalendarApi, code u64) {
	for _ in 0 .. 8 {
		calendar_day_case(api, code, 0x7ff8000000001234, 0, 0x8000000000000000, true)
		calendar_day_case(api, code, 0x42c0000000000000, 1, 0, false)
	}
}

fn calendar_days_suite(api CalendarApi, code u64) {
	for bits in [u64(0), 0x8000000000000000, 0x3ff0000000000000, 0xbff0000000000000,
		0x3ff8000000000000, 0xbff8000000000000, 0x7ff0000000000000, 0xfff0000000000000,
		0x7ff8000000001234, 0xfff8000000001234, 0x7ff0000000001234, 0xfff0000000001234,
		0xc248a97998e00001, 0xc248a97998e00000, 0xc248a97998dfffff,
		0x42acf8ab468effff, 0x42acf8ab468f0000, 0x42acf8ab468f0001, 0x42c0000000000000]! {
		for tag in [u8(0), 1, 2, 255]! { for at_end in [false, true]! {
			calendar_day_case(api, code, bits, tag, 0x7ff8000000004321, at_end)
		} }
	}
	for start in [u64(0), 0x8000000000000000, 0x3ff8000000000000, 0x7ff0000000000000, 0xfff0000000000000]! {
		calendar_day_case(api, code, 0x3ff8000000000000, 0, start, true)
	}
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn calendar_days_worker(api, code) }
	workers.wait()
}

fn calendar_values_suite(api CalendarApi, code u64) {
	for which in u8(0) .. 27 { for source_end in [false, true]! { for result_end in [false, true]! { calendar_value_case(api, which, source_end, result_end) } } }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn calendar_values_worker(api) }
	workers.wait()
	calendar_dispatch_case(api, code)
	store := unsafe { CalendarIdentifierStore(voidptr(read64(api.witness + 56) & 0x0000ffffffffffff)) }
	get := unsafe { CalendarIdentifierGet(voidptr(read64(api.witness + 48) & 0x0000ffffffffffff)) }
	for cases in [u32(0), 1, 255, 0x7fffffff, 0x80000000, 0xffffffff]! {
		for tag in [u32(0), 1, 255, 0x7fffffff, 0x80000000, 0xffffffff]! {
			if tag > cases { continue }
			mut bytes := [40]u8{}; C.memset(unsafe { &bytes[0] }, 0xa5, 40)
			value := u64(unsafe { &bytes[5] })
			store(value, tag, cases, api.metadata)
			assert get(value, cases, api.metadata) == tag
			length := if cases > 0x7fffffff { 17 } else { 16 }
			for i in 0 .. 40 { if i < 5 || i >= 5 + length { assert bytes[i] == 0xa5 } }
		}
	}
}

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
		assert calendar_identifier_relative(descriptor + 16) == 0
		assert calendar_identifier_relative(parent + 12) == (runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_$s10Foundation8CalendarVMa') or { panic(err) })
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
	assert calendar_api(false, 0).entries[3] == calendar_identifier_relative(entries[1] + 4)
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
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0503f3,
		0xaa0403e8, 0xaa0303f4, 0xaa0103e0, 0xaa0203e1, 0xd28a0435, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + 160 + u64(i * 4), op) }
	for i, op in [u32(0xaa1403e2), 0xaa0803e3, 0x58000050, 0xd61f0200]! { write32(code + 256 + u64(i * 4), op) }
	unsafe { *(&u64(code + 272)) = u64(voidptr(calendar_spy_identifier)) }
	write32(code + 288, 0xdac10020); write32(code + 292, 0xd65f03c0)
	for i, op in [u32(0xaa1403e4), 0xaa0803e5, 0x58000050, 0xd61f0200]! { write32(code + 320 + u64(i * 4), op) }
	unsafe { *(&u64(code + 336)) = u64(voidptr(calendar_spy_day)) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 344))
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
		calendar_values_suite(calendar_api(true, code), code)
		calendar_days_suite(calendar_api(true, code), code)
		println('IOS-SWIFT-CALENDAR-CASE-NATIVE: startOfDay witness dispatch, native bounds/NaNs, optional interval fallback, guarded eight-byte Date results and concurrent borrows; Calendar construction, metadata, ownership, Identifier witnesses and ISO 8601 export measured')
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
		api := calendar_api(false, code)
		assert api.metadata == arena + u64(page) + 1896 && api.entries[3] == arena + u64(page) + 1600
		calendar_values_suite(api, code)
		calendar_days_suite(api, code)
		assert read64(arena + u64(page) + 2208) == u64(unsafe { voidptr(swift_calendar_interval_unavailable) })
		for invalid in [u8(27), 28, 127, 255]! { if _ := swift_calendar_input_checked(u64(unsafe { &invalid })) { assert false } }
		if _ := swift_calendar_identifier_checked(0) { assert false }
		for symbol in ['_$s10Foundation8CalendarV10IdentifierO9gregorianyA2EmFWC', '_$s10Foundation8CalendarV6localeAA6LocaleVSgvs']! {
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
		calendar_case_mapping(api.metadata, false, false)
		if _ := swift_foundation_symbol(calendar_case_symbol) {
			assert false
		}
		for symbol in ['_$s10Foundation8CalendarV10IdentifierOMa', '_$s10Foundation8CalendarV10IdentifierOMn']! {
			if _ := swift_foundation_symbol(symbol) { assert false }
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-SWIFT-CALENDAR-CASE: startOfDay witness dispatch, native bounds/NaNs, optional interval fallback, guarded Date results and concurrent borrows; Calendar construction, ownership, metadata, Identifier witnesses and ISO 8601 export, two drained/unmapped runtimes; private timezone-aware interval backend, mutation and Objective-C bridging remain unsupported')
}
