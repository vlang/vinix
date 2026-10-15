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
type CalendarLocaleCString = fn (&u8) SwiftStringWords
type CalendarLocaleUTF8 = fn (u64, u64) u64
type CalendarLocaleDrop = fn (u64)
type CalendarZoneSend = fn (u64, u64, u64) u64
type CalendarZoneReal = fn (u64, u64, u64) f64
type CalendarZoneSelector = fn (&char) u64
type CalendarZoneClass = fn (&char) u64
type CalendarZoneKeep = fn (u64) u64
type CalendarZonePool = fn () u64
type CalendarZoneDate = fn (u64, f64) u64

struct CalendarLocaleApi {
	native bool
	constructor u64
	identifier u64
	metadata u64
	witness u64
	cstring CalendarLocaleCString
	utf8 CalendarLocaleUTF8
	drop CalendarLocaleDrop
}

fn calendar_locale_cstring(bytes &u8) SwiftStringWords {
	text := unsafe { (&char(bytes)).vstring() }
	scratch := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(scratch)) = swift_interpolation_init(128, 0) }
	swift_string_append_bytes(scratch, u64(bytes), u64(text.len))
	return unsafe { *(&SwiftStringWords(scratch)) }
}

fn calendar_locale_api(native bool) CalendarLocaleApi {
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	mut entries := [3]u64{}
	for i, symbol in ['_$s10Foundation6LocaleV10identifierACSS_tcfC', '_$s10Foundation6LocaleV10identifierSSvg', '_$s10Foundation6LocaleVMa']! {
		$if macos { if native { entries[i] = u64(C.dlsym(C.dlopen(library.str, 2), symbol[1..].str)) } }
		if !native { entries[i] = runtime_symbol(library, symbol) or { panic(err) } }
		assert entries[i] != 0
	}
	response := unsafe { CalendarCaseAccess(voidptr(entries[2]))(0) }
	mut cstring := CalendarLocaleCString(calendar_locale_cstring)
	mut utf8 := CalendarLocaleUTF8(swift_string_utf8_cstring)
	mut drop := CalendarLocaleDrop(swift_bridge_release)
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		cstring = unsafe { CalendarLocaleCString(C.dlsym(core, c'$sSS7cStringSSSPys4Int8VG_tcfC')) }
		utf8 = unsafe { CalendarLocaleUTF8(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }
		drop = unsafe { CalendarLocaleDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) }
	} }
	return CalendarLocaleApi{native: native, constructor: entries[0], identifier: entries[1], metadata: response.metadata,
		witness: read64(response.metadata - 8) & 0x0000ffffffffffff, cstring: cstring, utf8: utf8, drop: drop}
}

fn (locale CalendarLocaleApi) make(api CalendarApi, label string, output u64, guard u64) {
	text := locale.cstring(unsafe { &u8(label.str) })
	api.call(locale.constructor, text.first, text.second, guard, output)
}

fn (locale CalendarLocaleApi) destroy(value u64) {
	unsafe { CalendarCaseDestroy(voidptr(read64(locale.witness + 8) & 0x0000ffffffffffff))(value, locale.metadata) }
}

fn (locale CalendarLocaleApi) check(api CalendarApi, value u64, expected string, guard u64) {
	assert read64(value) != 0
	mut capture := [4]u64{}
	api.probe(locale.identifier, guard, guard, value, guard, unsafe { &capture[0] })
	assert capture[2] == value && capture[3] == 0x5021
	array := locale.utf8(capture[0], capture[1])
	assert read64(array + 16) == u64(expected.len + 1)
	assert C.memcmp(voidptr(array + 32), expected.str, usize(expected.len)) == 0
	assert unsafe { *(&u8(array + 32 + u64(expected.len))) } == 0
	locale.drop(array); locale.drop(capture[1])
}

struct CalendarApi {
	native bool
	entries [9]u64
	metadata u64
	witness u64
	probe CalendarProbe
}

fn calendar_api(native bool, code u64) CalendarApi {
	mut entries := [9]u64{}
	for i, symbol in ['_$s10Foundation8CalendarV10identifierA2C10IdentifierOh_tcfC',
		'_$s10Foundation8CalendarV10identifierAC10IdentifierOvg', '_$s10Foundation8CalendarVMa', '_$s10Foundation8CalendarVMn',
		'_$s10Foundation8CalendarV10startOfDay3forAA4DateVAG_tF',
		'_$s10Foundation8CalendarV6localeAA6LocaleVSgvs', '_$s10Foundation8CalendarV6localeAA6LocaleVSgvg',
		'_$s10Foundation8CalendarV8timeZoneAA04TimeD0Vvs', '_$s10Foundation8CalendarV8timeZoneAA04TimeD0Vvg']! {
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
		assert storage.size == 56 && storage.mask == 7 && !storage.deiniting && read64(owner + 8) == 3
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

fn calendar_locale_case(api CalendarApi, locale CalendarLocaleApi, which u8, at_end bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 7, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	for index in [1, 3, 5]! {
		assert C.mprotect(voidptr(span + u64(page * usize(index))), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(span + u64(page * usize(index))), 0xa5, page)
	}
	value := span + u64(page) + if at_end { u64(page) - 16 } else { u64(0) }
	input := span + u64(page * 3) + if at_end { u64(page) - 16 } else { u64(0) }
	output := span + u64(page * 5) + if at_end { u64(page) - 16 } else { u64(0) }
	api.call(api.entries[0], u64(unsafe { &which }), span, span, value)
	mut original := [2]u64{}; backup := u64(unsafe { &original[0] })
	copy_value := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + 16) & 0x0000ffffffffffff)) }
	assert copy_value(backup, value, api.metadata) == backup
	initial := if which == 7 { 'en_001' } else { '' }
	api.call(api.entries[6], span, span, value, output)
	mut kept := unsafe { *(&SwiftURLWords(output)) }; held := u64(unsafe { &kept })
	locale.check(api, held, initial, span)
	mut expected := initial
	for index, label in ['<nil>', 'en_US_POSIX', 'en_US_POSIX', 'fr_FR', '<nil>', '', 'sr-Latn_RS_POSIX', 'iw_IL', 'he_IL', '<nil>']! {
		assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
		mut alias := [2]u64{}; alias_value := u64(unsafe { &alias[0] })
		if label == '<nil>' {
			unsafe { *(&u64(input)) = 0; *(&u64(input + 8)) = span }
		} else {
			locale.make(api, label, input, span)
			keep := unsafe { CalendarCaseCopy(voidptr(read64(locale.witness + 16) & 0x0000ffffffffffff)) }
			assert keep(alias_value, input, locale.metadata) == alias_value
			expected = if label == 'iw_IL' { 'he_IL' } else { label }
		}
		before := unsafe { *(&SwiftURLWords(input)) }
		assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
		owner := read64(value)
		api.call(api.entries[5], input, span, value, span)
		assert unsafe { *(&SwiftURLWords(input)) } == before
		calendar_identifier_padding(span + u64(page * 3), u64(page), input, 16)
		calendar_identifier_padding(span + u64(page), u64(page), value, 16)
		if !api.native && (label == '<nil>' || index == 2 || index == 8) { assert read64(value) == owner }
		if label != '<nil>' { locale.check(api, alias_value, expected, span); locale.destroy(alias_value) }
		assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
		C.memset(voidptr(span + u64(page * 5)), 0xa5, page)
		api.call(api.entries[6], span, span, value, output)
		locale.check(api, output, expected, span)
		calendar_identifier_padding(span + u64(page * 5), u64(page), output, 16)
		locale.destroy(output)
		assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	api.destroy(value)
	api.call(api.entries[6], span, span, backup, output)
	api.destroy(backup)
	locale.check(api, output, initial, span); locale.destroy(output)
	locale.check(api, held, initial, span); locale.destroy(held)
	assert C.munmap(voidptr(span), page * 7) == 0
}

fn calendar_locale_worker(api CalendarApi, locale CalendarLocaleApi, seed u64) {
	mut value := [2]u64{}; self := u64(unsafe { &value[0] })
	copy_value := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + 16) & 0x0000ffffffffffff)) }
	assert copy_value(self, seed, api.metadata) == self
	for _ in 0 .. 8 { for label in ['en_US_POSIX', 'fr_FR']! {
		mut supplied := [2]u64{}; input := u64(unsafe { &supplied[0] })
		locale.make(api, label, input, 0)
		api.call(api.entries[5], input, 0, self, 0)
		mut got := [2]u64{}; output := u64(unsafe { &got[0] })
		api.call(api.entries[6], 0, 0, self, output)
		locale.check(api, output, label, 0); locale.destroy(output)
	} }
	api.destroy(self)
}

fn calendar_locales_suite(api CalendarApi) {
	locale := calendar_locale_api(api.native)
	for which in u8(0) .. 27 { for at_end in [false, true]! { calendar_locale_case(api, locale, which, at_end) } }
	mut value := [2]u64{}; self := u64(unsafe { &value[0] }); which := u8(7)
	api.call(api.entries[0], u64(unsafe { &which }), 0, 0, self)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn calendar_locale_worker(api, locale, self) }
	workers.wait()
	mut got := [2]u64{}; output := u64(unsafe { &got[0] })
	api.call(api.entries[6], 0, 0, self, output)
	api.destroy(self)
	locale.check(api, output, 'en_001', 0); locale.destroy(output)
}

struct CalendarZoneApi {
	constructor u64
	value CalendarLocaleApi
}

fn calendar_zone_api(api CalendarApi) CalendarZoneApi {
	mut entries := [4]u64{}
	for i, symbol in ['_$s10Foundation8TimeZoneV14secondsFromGMTACSgSi_tcfC', '_$s10Foundation8TimeZoneV10identifierSSvg',
		'_$s10Foundation8TimeZoneVMa', '_$s10Foundation8TimeZoneVMn']! {
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/swift/libswiftFoundation.dylib']! {
			mut address := u64(0)
			$if macos { if api.native { address = u64(C.dlsym(C.dlopen(library.str, 2), symbol[1..].str)) } }
			if !api.native { address = runtime_symbol(library, symbol) or { panic(err) } }
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
	assert read32(entries[3] + 20) == 1 && read32(entries[3] + 24) == 2
	assert unsafe { (&char(calendar_identifier_relative(entries[3] + 8))).vstring() } == 'TimeZone'
	common := calendar_locale_api(api.native)
	return CalendarZoneApi{constructor: entries[0], value: CalendarLocaleApi{native: api.native, constructor: entries[0],
		identifier: entries[1], metadata: response.metadata, witness: witness, cstring: common.cstring, utf8: common.utf8, drop: common.drop}}
}

fn calendar_zone_label(seconds i64) string {
	return match seconds {
		-61260 { 'GMT-1701' }
		61260 { 'GMT+1701' }
		-64800, -64799 { 'GMT-1800' }
		-3600 { 'GMT-0100' }
		-61, -60, -59, -31, -30 { 'GMT-0001' }
		-29, -1, 0, 1, 29 { 'GMT' }
		30, 31, 59, 60, 61 { 'GMT+0001' }
		19800 { 'GMT+0530' }
		64799, 64800 { 'GMT+1800' }
		else { panic('missing zone expectation') }
	}
}

fn calendar_zone_days(api CalendarApi, self u64, seconds i64, span u64, at_end bool) {
	page := usize(C.getpagesize())
	input := span + u64(page) + if at_end { u64(page) - 8 } else { u64(0) }
	output := span + u64(page * 5) + if at_end { u64(page) - 8 } else { u64(0) }
	for bits in [u64(0), 0x8000000000000000, 0x3ff8000000000000, 0xbff8000000000000,
		0x40f5180000000000, 0x40f517ffffffffff, 0x8000000000000001, 0x3e112e0be826d695, 0xbe112e0be826d695,
		0xc248a97998e00001, 0xc248a97998e00000, 0xc248a97998dfffff,
		0x42acf8ab468effff, 0x42acf8ab468f0000, 0x42acf8ab468f0001,
		0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234, 0xfff8000000001234, 0x7ff0000000001234]! {
		assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(span + u64(page)), 0xa5, page)
		unsafe { *(&u64(input)) = bits }
		assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
		assert C.mprotect(voidptr(span + u64(page * 5)), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(span + u64(page * 5)), 0xa5, page)
		api.call(api.entries[4], input, span, self, output)
		clamped := calendar_day_clamped_bits(bits)
		value := unsafe { *(&f64(&clamped)) }
		expected := C.floor((C.floor(value) + f64(seconds)) / 86400.0) * 86400.0 - f64(seconds)
		assert read64(output) == unsafe { *(&u64(&expected)) } && read64(input) == bits
		calendar_identifier_padding(span + u64(page), u64(page), input, 8)
		calendar_identifier_padding(span + u64(page * 5), u64(page), output, 8)
	}
}

fn calendar_zone_case(api CalendarApi, zone CalendarZoneApi, seconds i64, which u8, at_end bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 7, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	for index in [1, 3, 5]! {
		assert C.mprotect(voidptr(span + u64(page * usize(index))), page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memset(voidptr(span + u64(page * usize(index))), 0xa5, page)
	}
	source := span + u64(page) + if at_end { u64(page) - 16 } else { u64(0) }
	self := span + u64(page * 3) + if at_end { u64(page) - 16 } else { u64(0) }
	input := span + u64(page * 5) + if at_end { u64(page) - 16 } else { u64(0) }
	api.call(zone.constructor, u64(seconds), span, span, source)
	calendar_identifier_padding(span + u64(page), u64(page), source, 16)
	tag := unsafe { CalendarIdentifierGet(voidptr(read64(zone.value.witness + 48) & 0x0000ffffffffffff)) }
	if seconds < -64800 || seconds > 64800 {
		assert read64(source) == 0 && read64(source + 8) == 0 && tag(source, 1, zone.value.metadata) == 1
		assert C.munmap(voidptr(span), page * 7) == 0
		return
	}
	assert tag(source, 1, zone.value.metadata) == 0
	zone.value.check(api, source, calendar_zone_label(seconds), span)
	copy_zone := unsafe { CalendarCaseCopy(voidptr(read64(zone.value.witness + 16) & 0x0000ffffffffffff)) }
	mut alias := [2]u64{}; alias_value := u64(unsafe { &alias[0] })
	assert copy_zone(alias_value, source, zone.value.metadata) == alias_value
	assert copy_zone(input, source, zone.value.metadata) == input
	api.call(api.entries[0], u64(unsafe { &which }), span, span, self)
	locale := calendar_locale_api(api.native)
	mut supplied_locale := [2]u64{}; lp := u64(unsafe { &supplied_locale[0] })
	locale.make(api, 'en_US_POSIX', lp, span); api.call(api.entries[5], lp, span, self, span)
	before := unsafe { *(&SwiftURLWords(input)) }
	assert C.mprotect(voidptr(span + u64(page * 5)), page, C.PROT_READ) == 0
	api.call(api.entries[7], input, span, self, span)
	assert unsafe { *(&SwiftURLWords(input)) } == before
	calendar_identifier_padding(span + u64(page * 5), u64(page), input, 16)
	zone.value.destroy(source)
	mut saved := [2]u64{}; backup := u64(unsafe { &saved[0] })
	copy_calendar := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + 16) & 0x0000ffffffffffff)) }
	assert copy_calendar(backup, self, api.metadata) == backup
	locale.make(api, 'fr_FR', lp, span); api.call(api.entries[5], lp, span, self, span)
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(span + u64(page * 5)), page, C.PROT_READ | C.PROT_WRITE) == 0
	C.memset(voidptr(span + u64(page * 5)), 0xa5, page)
	api.call(api.entries[8], span, span, self, input)
	zone.value.check(api, input, calendar_zone_label(seconds), span)
	calendar_identifier_padding(span + u64(page * 5), u64(page), input, 16)
	mut kept := unsafe { *(&SwiftURLWords(input)) }; held := u64(unsafe { &kept })
	calendar_zone_days(api, self, seconds, span, at_end)
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
	other := if calendar_zone_label(seconds) == 'GMT+0530' { i64(0) } else { i64(19800) }
	api.call(zone.constructor, u64(other), span, span, input)
	assert C.mprotect(voidptr(span + u64(page * 5)), page, C.PROT_READ) == 0
	api.call(api.entries[7], input, span, self, span)
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
	calendar_zone_days(api, self, other, span, at_end)
	mut got := [2]u64{}; result := u64(unsafe { &got[0] })
	api.call(api.entries[6], span, span, self, result); locale.check(api, result, 'fr_FR', span); locale.destroy(result)
	api.call(api.entries[6], span, span, backup, result); locale.check(api, result, 'en_US_POSIX', span); locale.destroy(result)
	api.call(api.entries[8], span, span, backup, result); zone.value.check(api, result, calendar_zone_label(seconds), span); zone.value.destroy(result)
	api.destroy(self); api.destroy(backup)
	zone.value.check(api, held, calendar_zone_label(seconds), span); zone.value.destroy(held)
	zone.value.check(api, alias_value, calendar_zone_label(seconds), span); zone.value.destroy(alias_value)
	assert C.munmap(voidptr(span), page * 7) == 0
}

fn calendar_zone_worker(api CalendarApi, zone CalendarZoneApi, seed u64) {
	mut value := [2]u64{}; self := u64(unsafe { &value[0] })
	copy_calendar := unsafe { CalendarCaseCopy(voidptr(read64(api.witness + 16) & 0x0000ffffffffffff)) }
	assert copy_calendar(self, seed, api.metadata) == self
	mut current := i64(0)
	for _ in 0 .. 4 { for seconds in [i64(0), 1, 19800, 30, 61, -3600, -29]! {
		if calendar_zone_label(current) != calendar_zone_label(seconds) { current = seconds }
		mut supplied := [2]u64{}; input := u64(unsafe { &supplied[0] })
		api.call(zone.constructor, u64(seconds), 0, 0, input)
		api.call(api.entries[7], input, 0, self, 0)
		mut got := [2]u64{}; output := u64(unsafe { &got[0] })
		api.call(api.entries[8], 0, 0, self, output)
		zone.value.check(api, output, calendar_zone_label(current), 0); zone.value.destroy(output)
		date := f64(0); mut day := f64(1)
		api.call(api.entries[4], u64(unsafe { &date }), 0, self, u64(unsafe { &day }))
		assert day == C.floor(f64(current) / 86400.0) * 86400.0 - f64(current)
	} }
	api.destroy(self)
}

fn calendar_zones_suite(api CalendarApi) {
	zone := calendar_zone_api(api)
	for seconds in [i64(-64801), -64800, -64799, -61, -60, -59, -31, -30, -29, -1, 0, 1, 29, 30, 31, 59, 60, 61, 19800, 64799, 64800, 64801]! {
		for which in [u8(0), 7]! { for at_end in [false, true]! { calendar_zone_case(api, zone, seconds, which, at_end) } }
	}
	mut value := [2]u64{}; self := u64(unsafe { &value[0] }); which := u8(7)
	api.call(api.entries[0], u64(unsafe { &which }), 0, 0, self)
	mut supplied := [2]u64{}; input := u64(unsafe { &supplied[0] })
	api.call(zone.constructor, 0, 0, 0, input); api.call(api.entries[7], input, 0, self, 0)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn calendar_zone_worker(api, zone, self) }
	workers.wait()
	mut got := [2]u64{}; output := u64(unsafe { &got[0] })
	api.call(api.entries[8], 0, 0, self, output); api.destroy(self)
	zone.value.check(api, output, 'GMT', 0); zone.value.destroy(output)
}

struct CalendarZoneBridgeApi {
	zone CalendarZoneApi
	entry u64
	cls u64
	send CalendarZoneSend
	real CalendarZoneReal
	selector CalendarZoneSelector
	keep CalendarZoneKeep
	drop CalendarLocaleDrop
	push CalendarZonePool
	pop CalendarLocaleDrop
	date CalendarZoneDate
}

fn calendar_zone_bridge_api(api CalendarApi) CalendarZoneBridgeApi {
	symbol := '_$s10Foundation8TimeZoneV19_bridgeToObjectiveCSo06NSTimeC0CyF'
	zone := calendar_zone_api(api)
	mut entry := u64(0)
	for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/swift/libswiftFoundation.dylib']! {
		mut address := u64(0)
		$if macos { if api.native { address = u64(C.dlsym(C.dlopen(library.str, 2), symbol[1..].str)) } }
		if !api.native { address = runtime_symbol(library, symbol) or { panic(err) } }
		assert address != 0 && (entry == 0 || entry == address); entry = address
	}
	$if macos { if api.native {
		obj := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		cf := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		return CalendarZoneBridgeApi{zone: zone, entry: entry,
			cls: unsafe { CalendarZoneClass(C.dlsym(obj, c'objc_getClass'))(c'NSTimeZone') },
			send: unsafe { CalendarZoneSend(C.dlsym(obj, c'objc_msgSend')) }, real: unsafe { CalendarZoneReal(C.dlsym(obj, c'objc_msgSend')) },
			selector: unsafe { CalendarZoneSelector(C.dlsym(obj, c'sel_registerName')) }, keep: unsafe { CalendarZoneKeep(C.dlsym(obj, c'objc_retain')) },
			drop: unsafe { CalendarLocaleDrop(C.dlsym(obj, c'objc_release')) }, push: unsafe { CalendarZonePool(C.dlsym(obj, c'objc_autoreleasePoolPush')) },
			pop: unsafe { CalendarLocaleDrop(C.dlsym(obj, c'objc_autoreleasePoolPop')) }, date: unsafe { CalendarZoneDate(C.dlsym(cf, c'CFDateCreate')) }}
	} }
	cls := ios_runtime.names['NSTimeZone']
	for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation']! {
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSTimeZone') or { panic(err) } == cls
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSTimeZone') or { panic(err) } == read64(cls)
	}
	assert ios_runtime.classes[cls].size == 8
	return CalendarZoneBridgeApi{zone: zone, entry: entry, cls: cls,
		send: unsafe { CalendarZoneSend(voidptr(C.ios_objc_msgsend)) }, real: unsafe { CalendarZoneReal(voidptr(C.ios_objc_msgsend)) },
		selector: objc_selector, keep: objc_retain, drop: objc_release, push: objc_pool_push, pop: objc_pool_pop, date: cf_date_create}
}

fn (bridge CalendarZoneBridgeApi) call(api CalendarApi, self u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(bridge.entry, guard, guard, self, guard, unsafe { &capture[1] })
	assert capture[0] == 0xcafe && capture[3] == self && capture[4] == 0x5021 && capture[5] == 0xbeef
	return capture[1]
}

fn (bridge CalendarZoneBridgeApi) text(object u64) string {
	return unsafe { (&char(bridge.send(object, bridge.selector(c'UTF8String'), 0))).vstring() }
}

fn (bridge CalendarZoneBridgeApi) check(object u64, seconds i64, date u64) {
	assert bridge.send(object, bridge.selector(c'isKindOfClass:'), bridge.cls) == 1
	assert bridge.text(bridge.send(object, bridge.selector(c'name'), 0)) == calendar_zone_label(seconds)
	abbreviation := match seconds {
		-64800, -64799 { 'GMT-18' }
		-61260 { 'GMT-17:01' }
		-61, -60, -59, -31, -30 { 'GMT-0:01' }
		-29, -1, 0, 1, 29 { 'GMT' }
		30, 31, 59, 60, 61 { 'GMT+0:01' }
		19800 { 'GMT+5:30' }
		61260 { 'GMT+17:01' }
		64799, 64800 { 'GMT+18' }
		else { panic('missing abbreviation expectation') }
	}
	for name in [c'abbreviation', c'abbreviationForDate:']! { assert bridge.text(bridge.send(object, bridge.selector(name), date)) == abbreviation }
	for name in [c'secondsFromGMT', c'secondsFromGMTForDate:']! { assert i64(bridge.send(object, bridge.selector(name), date)) == seconds }
	for name in [c'isDaylightSavingTime', c'isDaylightSavingTimeForDate:', c'nextDaylightSavingTimeTransition', c'nextDaylightSavingTimeTransitionAfterDate:']! {
		assert bridge.send(object, bridge.selector(name), date) == 0
	}
	for name in [c'daylightSavingTimeOffset', c'daylightSavingTimeOffsetForDate:']! { assert bridge.real(object, bridge.selector(name), date) == 0 }
	assert bridge.send(object, bridge.selector(c'classForCoder'), 0) == bridge.cls
}

fn calendar_zone_bridge_case(api CalendarApi, bridge CalendarZoneBridgeApi, seconds i64, at_end bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1) && C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	C.memset(voidptr(span + u64(page)), 0xa5, page)
	self := span + u64(page) + if at_end { u64(page) - 16 } else { u64(0) }
	pool := bridge.push()
	api.call(bridge.zone.constructor, u64(seconds), span, span, self)
	before := unsafe { *(&SwiftURLWords(self)) }
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	first := bridge.call(api, self, span); second := bridge.call(api, self, span)
	assert first != 0 && second != 0 && first != second && unsafe { *(&SwiftURLWords(self)) } == before
	calendar_identifier_padding(span + u64(page), u64(page), self, 16)
	copied := bridge.send(first, bridge.selector(c'copyWithZone:'), 0)
	assert copied == first
	name := bridge.keep(bridge.send(first, bridge.selector(c'name'), 0))
	bridge.zone.value.destroy(self)
	bridge.pop(pool) // Owned bridge results and the explicitly retained name survive.
	pool2 := bridge.push()
	past := bridge.date(0, -63114076800.0); future := bridge.date(0, 63113904000.0)
	bridge.check(first, seconds, past); bridge.check(second, seconds, future)
	assert bridge.send(first, bridge.selector(c'isEqualToTimeZone:'), second) == 1
	assert bridge.send(first, bridge.selector(c'hash'), 0) == bridge.send(second, bridge.selector(c'hash'), 0)
	bridge.drop(first); bridge.check(copied, seconds, past); bridge.drop(copied)
	bridge.check(second, seconds, future); bridge.drop(second)
	assert bridge.text(name) == calendar_zone_label(seconds)
	bridge.drop(name); bridge.drop(past); bridge.drop(future); bridge.pop(pool2)
	assert C.munmap(voidptr(span), page * 3) == 0
}

fn calendar_zone_bridge_worker(api CalendarApi, bridge CalendarZoneBridgeApi, self u64) {
	for _ in 0 .. 32 {
		pool := bridge.push(); date := bridge.date(0, 0)
		object := bridge.call(api, self, 0); bridge.check(object, 19800, date)
		bridge.drop(object); bridge.drop(date); bridge.pop(pool)
	}
}

fn calendar_zone_bridge_spy(metadata u64, table u64, owner u64, slot u64) u64 {
	assert slot == table + 128 && owner == read64(table + 144) && metadata == read64(table + 152)
	return read64(table + 160)
}

fn calendar_zone_bridge_dispatch(api CalendarApi, bridge CalendarZoneBridgeApi, code u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1) && C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	table := span + u64(page) + 64; self := table + 256
	mut original := [2]u64{}; value := u64(unsafe { &original[0] })
	api.call(bridge.zone.constructor, 19800, span, span, value)
	owner := original[0]
	mut metadata := u64(0); mut callback := code + 352
	$if macos { if api.native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		metadata = unsafe { CalendarObjectType(C.dlsym(core, c'swift_getObjectType'))(owner) }
		callback = unsafe { CalendarSign(voidptr(code + 288))(callback, (table + 128) | (u64(37611) << 48)) }
	} }
	if !api.native { metadata = swift_object_type(owner) }
	unsafe {
		*(&u64(table + 128)) = callback; *(&u64(table + 144)) = owner; *(&u64(table + 152)) = metadata
		*(&u64(table + 160)) = 0xcafebabefeed1234; *(&SwiftURLWords(self)) = SwiftURLWords{owner: owner, table: table}
	}
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	assert bridge.call(api, self, span) == 0xcafebabefeed1234
	bridge.zone.value.destroy(value)
	assert C.munmap(voidptr(span), page * 3) == 0
}

fn calendar_zone_bridges_suite(api CalendarApi, code u64) {
	bridge := calendar_zone_bridge_api(api)
	calendar_zone_bridge_dispatch(api, bridge, code)
	for seconds in [i64(-64800), -64799, -61260, -61, -60, -59, -31, -30, -29, -1, 0, 1, 29, 30, 31, 59, 60, 61, 19800, 61260, 64799, 64800]! {
		for at_end in [false, true]! { calendar_zone_bridge_case(api, bridge, seconds, at_end) }
	}
	pool := bridge.push()
	for pair in [[i64(-1), 0]!, [i64(0), 1]!, [i64(29), 0]!, [i64(30), 59]!, [i64(59), 60]!, [i64(60), 61]!,
		[i64(64799), 64800]!, [i64(-61), -60]!, [i64(-29), 29]!, [i64(-30), 30]!, [i64(29), 30]!, [i64(19800), 64800]!]! {
		a := bridge.send(bridge.cls, bridge.selector(c'timeZoneForSecondsFromGMT:'), u64(pair[0]))
		b := bridge.send(bridge.cls, bridge.selector(c'timeZoneForSecondsFromGMT:'), u64(pair[1]))
		equal := calendar_zone_label(pair[0]) == calendar_zone_label(pair[1])
		for selector in [c'isEqual:', c'isEqualToTimeZone:']! { assert bridge.send(a, bridge.selector(selector), b) == u64(equal) }
		if equal { assert bridge.send(a, bridge.selector(c'hash'), 0) == bridge.send(b, bridge.selector(c'hash'), 0) }
		if !api.native {
			assert cf_equal_depth(a, b, 0) == equal
			if equal { assert cf_hash(a) == cf_hash(b) }
			copy_value := objc_copy_value(a, false); assert copy_value == a; objc_release(copy_value)
		}
	}
	for seconds in [i64(-64801), 64801]! { assert bridge.send(bridge.cls, bridge.selector(c'timeZoneForSecondsFromGMT:'), u64(seconds)) == 0 }
	if !api.native {
		for seconds in [i64(-9223372036854775807) - 1, 9223372036854775807]! { assert ns_timezone_fixed(seconds) == 0 }
		for pair in [['name', '@16@0:8']!, ['secondsFromGMTForDate:', 'q24@0:8@16']!, ['isEqualToTimeZone:', 'B24@0:8@16']!,
			['daylightSavingTimeOffsetForDate:', 'd24@0:8@16']!, ['copyWithZone:', '@24@0:8^{_NSZone=}16']!, ['classForCoder', '#16@0:8']!]! {
			method := objc_instance_method(bridge.cls, bridge.selector(unsafe { &char(pair[0].str) }))
			assert method != 0 && unsafe { objc_method_types(method).vstring() } == pair[1]
		}
	}
	bridge.pop(pool)
	mut value := [2]u64{}; self := u64(unsafe { &value[0] })
	api.call(bridge.zone.constructor, 19800, 0, 0, self)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn calendar_zone_bridge_worker(api, bridge, self) }
	workers.wait(); bridge.zone.value.destroy(self)
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
	for i, op in [u32(0xaa1403e2), 0xaa0803e3, 0x58000050, 0xd61f0200]! { write32(code + 352 + u64(i * 4), op) }
	unsafe { *(&u64(code + 368)) = u64(voidptr(calendar_zone_bridge_spy)) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 376))
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
		calendar_locales_suite(calendar_api(true, code))
		calendar_zones_suite(calendar_api(true, code))
		calendar_zone_bridges_suite(calendar_api(true, code), code)
		println('IOS-SWIFT-CALENDAR-CASE-NATIVE: owned TimeZone Objective-C bridge, generic callback dispatch, exact seconds and rounded name/equality, abbreviation, DST queries, copies and independent getter/result lifetimes; guarded values, concurrent bridges, Calendar settings/day boundaries and native Identifier witnesses measured')
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
		calendar_locales_suite(api)
		calendar_zones_suite(api)
		calendar_zone_bridges_suite(api, code)
		assert read64(arena + u64(page) + 2208) == arena + 3456
		for invalid in [u8(27), 28, 127, 255]! { if _ := swift_calendar_input_checked(u64(unsafe { &invalid })) { assert false } }
		if _ := swift_calendar_identifier_checked(0) { assert false }
		for symbol in ['_$s10Foundation8CalendarV10IdentifierO9gregorianyA2EmFWC', '_$s10Foundation8TimeZoneV36_unconditionallyBridgeFromObjectiveCyACSo06NSTimeC0CSgFZ']! {
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
	println('IOS-SWIFT-CALENDAR-CASE: owned TimeZone Objective-C bridge, generic callback dispatch, exact seconds/rounded names/equality, fixed abbreviations/DST queries, copies/hash/metadata, guarded and independent value/result lifetimes, concurrent bridges, Calendar settings/day intervals and native Identifier witnesses, two drained/unmapped runtimes; default/named zones, other calendar calculations, Calendar Objective-C bridge and reverse TimeZone bridge remain unsupported')
}
