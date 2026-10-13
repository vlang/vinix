// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFError.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32
type SequenceProbeCall = fn (u64, u64, u64, u64, u64, u64, u64, &u64)
type SequenceProbeSign = fn (u64, u64) u64
type SequenceProbeRetain = fn (u64) u64
type SequenceProbeRelease = fn (u64)
type SequenceProbeObjCMetadata = fn (u64) u64
struct SequenceProbeApi {
	native bool
	entry u64
	first_entry u64
	code u64
	int_type u64
	string_type u64
	objc_type u64
	objc_result_type u64
	@[required]
	retain SequenceProbeRetain
	@[required]
	release SequenceProbeRelease
}
struct SequenceScenario {
	api SequenceProbeApi
	count int
	input_string bool
	output_string bool
	objc_values bool
	selection int
	throw_at int
	owner u64
	error_owner u64
	reenter bool
	first bool
mut:
	sequence_metadata u64
	iterator_metadata u64
	sequence_table u64
	iterator_table u64
	source u64
	copies int
	sequence_destroys int
	iterator_destroys int
	next_calls int
	transforms int
	kept int
	first_output u64
}
fn sequence_keep(api SequenceProbeApi, owner u64) {
	$if macos { if api.native { C.CFRetain(unsafe { voidptr(owner) }); return } }
	objc_retain(owner)
}
fn sequence_drop(api SequenceProbeApi, owner u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(owner) }); return } }
	objc_release(owner)
}
fn sequence_refs(api SequenceProbeApi, owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}
fn sequence_copy(destination u64, source u64, metadata u64) u64 {
	mut s := unsafe { &SequenceScenario(read64(metadata + 8)) }
	assert metadata == s.sequence_metadata && source == s.source && read64(source) == u64(s)
	s.copies++; unsafe { *(&u64(destination)) = read64(source) }; return destination
}
fn sequence_destroy(_value u64, metadata u64) {
	mut s := unsafe { &SequenceScenario(read64(metadata + 8)) }; s.sequence_destroys++
}
fn sequence_iterator_destroy(value u64, metadata u64) {
	mut s := unsafe { &SequenceScenario(read64(metadata + 8)) }
	assert read64(value) == u64(s) && metadata == s.iterator_metadata
	assert read64(value + 8) == u64(if s.first { s.transforms } else if s.throw_at >= 0 { s.throw_at + 1 } else { s.count })
	if s.first {
		assert sequence_refs(s.api, s.owner) == 1 + if s.kept != 0 && s.input_string { i64(1) } else { i64(0) }
		assert read64(s.first_output) == 0x7171717171717171 && read64(s.first_output + 8) == 0x8181818181818181
	}
	s.iterator_destroys++
}
fn sequence_pod_copy(destination u64, source u64, metadata u64) u64 {
	size := read64(read64(metadata - 8) + 64)
	C.memcpy(unsafe { voidptr(destination) }, unsafe { voidptr(source) }, usize(size)); return destination
}
fn sequence_pod_tag(_value u64, _cases u32, _metadata u64) u32 { return 0 }
fn sequence_make_iterator(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &SequenceScenario(read64(metadata + 8)) }
	assert metadata == s.sequence_metadata && table == s.sequence_table && receiver != s.source
	assert read64(receiver) == u64(s) && s.copies == 1
	unsafe { *(&u64(output)) = u64(s); *(&u64(output + 8)) = 0 }
}
fn sequence_next(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &SequenceScenario(read64(metadata + 8)) }
	assert metadata == s.iterator_metadata && table == s.iterator_table && read64(receiver) == u64(s)
	index := int(read64(receiver + 8)); assert index == s.transforms
	s.next_calls++
	if index == s.count {
		if s.objc_values { unsafe { *(&u64(output)) = 0 } }
		else if s.input_string { unsafe { *(&u64(output + 8)) = 0 } }
		else { unsafe { *(&u64(output)) = 0; *(&u8(output + 8)) = 1 } }
		return
	}
	if s.objc_values {
		sequence_keep(s.api, s.owner); unsafe { *(&u64(output)) = s.owner }
	} else if s.input_string {
		sequence_keep(s.api, s.owner)
		unsafe { *(&SwiftStringWords(output)) = SwiftStringWords{ first: 21, second: s.owner | u64(0x5000000000000000) } }
	} else { unsafe { *(&u64(output)) = u64(index); *(&u8(output + 8)) = 0 } }
	unsafe { *(&u64(receiver + 8)) = u64(index + 1) }
}
fn sequence_lookup_worker(entry u64) {
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF') or { panic(err) } == entry
}
fn sequence_first_lookup_worker(entry u64) {
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSTsE5first5where7ElementQzSgSbADKXE_tKF') or { panic(err) } == entry
}
fn sequence_predicate(input u64, context u64) SwiftSequenceResult {
	mut s := unsafe { &SequenceScenario(context) }; index := s.transforms
	assert s.first && s.copies == 1 && s.next_calls == index + 1
	if s.objc_values { assert read64(input) == s.owner }
	else if s.input_string { assert read64(input) == 21 && read64(input + 8) == s.owner | u64(0x5000000000000000) }
	else { assert read64(input) == u64(index) }
	assert sequence_refs(s.api, s.owner) == 1 + if s.input_string { i64(1) } else { i64(0) }
	if s.reenter && !s.api.native { worker := spawn sequence_first_lookup_worker(s.api.first_entry); worker.wait() }
	s.transforms++
	if index == s.throw_at { sequence_keep(s.api, s.error_owner); return SwiftSequenceResult{ error: s.error_owner } }
	if index == s.selection { s.kept++; return SwiftSequenceResult{ array: 1 } }
	return SwiftSequenceResult{}
}
fn sequence_transform(input u64, context u64, output u64) u64 {
	mut s := unsafe { &SequenceScenario(context) }; index := s.transforms
	assert s.copies == 1 && s.next_calls == index + 1
	if s.objc_values { assert read64(input) == s.owner }
	else if s.input_string {
		assert read64(input) == 21 && read64(input + 8) == s.owner | u64(0x5000000000000000)
	} else { assert read64(input) == u64(index), 'count=${s.count} selection=${s.selection} throw=${s.throw_at} input_string=${s.input_string} output_string=${s.output_string} transforms=${s.transforms} next=${s.next_calls} input=${input.hex()} output=${output.hex()} value=${read64(input)}' }
	assert sequence_refs(s.api, s.owner) == 1 + if s.input_string { i64(1) } else { i64(0) } + if s.output_string { i64(s.kept) } else { i64(0) }
	if s.reenter && !s.api.native { worker := spawn sequence_lookup_worker(s.api.entry); worker.wait() }
	s.transforms++
	if index == s.throw_at { sequence_keep(s.api, s.error_owner); return s.error_owner }
	keep := s.selection == 0 || (s.selection == 1 && index % 2 == 0)
	if keep {
		if s.objc_values {
			sequence_keep(s.api, s.owner); unsafe { *(&u64(output)) = s.owner }
		} else if s.output_string {
			sequence_keep(s.api, s.owner)
			unsafe { *(&SwiftStringWords(output)) = SwiftStringWords{ first: 21, second: s.owner | u64(0x5000000000000000) } }
		} else { unsafe { *(&u64(output)) = u64(index * 7 + 3); *(&u8(output + 8)) = 0 } }
		s.kept++
	} else {
		if s.objc_values { unsafe { *(&u64(output)) = 0 } }
		else if s.output_string { unsafe { *(&u64(output + 8)) = 0 } }
		else { unsafe { *(&u64(output)) = 0; *(&u8(output + 8)) = 1 } }
	}
	return 0
}
fn sequence_probe_emit(code u64) {
	// C invoke -> Swift generic method; capture result, error and preserved self.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0703f3,
		0xaa0603f4, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0503e4,
		0xaa1f03f5, 0xd63f0200, 0xf9000260, 0xf9000675, 0xf9000a74,
		0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	// Swift witness -> C fixture, preserving x20 through the C tail call.
	for offset, body in {u64(128): u64(unsafe { voidptr(sequence_make_iterator) }), u64(160): u64(unsafe { voidptr(sequence_next) })} {
		write32(code + offset, 0xaa0803e2); write32(code + offset + 4, 0xaa1403e3)
		write32(code + offset + 8, 0x58000090); write32(code + offset + 12, 0xd61f0200)
		unsafe { *(&u64(code + offset + 24)) = body }
	}
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa1403e1, 0xaa0803e2, 0x58000110,
		0xd63f0200, 0xaa0003f5, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + 192 + u64(i * 4), op) }
	unsafe { *(&u64(code + 240)) = u64(voidptr(sequence_transform)) }
	write32(code + 256, 0xdac10020); write32(code + 260, 0xd65f03c0)
	write32(code + 272, 0xdac10820); write32(code + 276, 0xd65f03c0)
	// Same C arguments as compactMap; argument four is the Optional output.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0703f3,
		0xaa0603f4, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0503e3, 0xaa0403e8,
		0xaa1f03f5, 0xd63f0200, 0xf9000260, 0xf9000675, 0xf9000a74,
		0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + 384 + u64(i * 4), op) }
	// Swift predicate -> C fixture; Bool x0 and original owned error x21.
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa1403e1, 0x58000130,
		0xd63f0200, 0xaa0103f5, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + 480 + u64(i * 4), op) }
	unsafe { *(&u64(code + 528)) = u64(voidptr(sequence_predicate)) }
}
fn sequence_probe_api(native bool, code u64) SequenceProbeApi {
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		metadata := unsafe { SequenceProbeObjCMetadata(C.dlsym(core, c'swift_getObjCClassMetadata')) }
		return SequenceProbeApi{native: true, code: code,
			entry: u64(C.dlsym(core, c'$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF')),
			first_entry: u64(C.dlsym(core, c'$sSTsE5first5where7ElementQzSgSbADKXE_tKF')),
			int_type: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')),
			objc_type: metadata(u64(C.objc_getClass(c'NSObject'))), objc_result_type: metadata(u64(C.objc_getClass(c'NSString'))),
			retain: unsafe { SequenceProbeRetain(C.dlsym(core, c'swift_bridgeObjectRetain')) },
			release: unsafe { SequenceProbeRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }}
	} }
	return SequenceProbeApi{ code: code, entry: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF') or { panic(err) },
		first_entry: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSTsE5first5where7ElementQzSgSbADKXE_tKF') or { panic(err) },
		int_type: swift_integer_metadata(), string_type: swift_string_metadata(),
		objc_type: swift_objc_metadata(ios_runtime.names['NSObject']), objc_result_type: swift_objc_metadata(ios_runtime.names['NSString']), retain: swift_bridge_retain, release: swift_bridge_release }
}
fn sequence_scenario(api SequenceProbeApi, count int, input_string bool, output_string bool, selection int, throw_at int, limited bool, objc_values bool) {
	sequence_scenario_checked(api, count, input_string, output_string, selection, throw_at, limited, objc_values, false)
}
fn sequence_scenario_checked(api SequenceProbeApi, count int, input_string bool, output_string bool, selection int, throw_at int, limited bool, objc_values bool, first bool) {
	mut owner := u64(0); mut error_owner := u64(0)
	$if macos { if api.native {
		owner = u64(C.CFStringCreateWithBytes(unsafe { nil }, c'compactMap owner text', 21, 0x08000100, false))
		domain := C.CFStringCreateWithBytes(unsafe { nil }, c'compactMap', 10, 0x08000100, false)
		error_owner = u64(C.CFErrorCreate(unsafe { nil }, domain, -9, unsafe { nil })); C.CFRelease(domain)
	} }
	if !api.native { owner = owned_string('compactMap owner text'); error_owner = objc_allocate(cf_error_type_id()) }
	mut s := SequenceScenario{ api: api, count: count, input_string: input_string, output_string: output_string,
		first: first,
		objc_values: objc_values,
		selection: selection, throw_at: throw_at, owner: owner, error_owner: error_owner,
		reenter: count == 9 && input_string && if first { selection == 3 } else { output_string && selection == 1 } }
	mut seq_vwt := [12]u64{}; mut iter_vwt := [12]u64{}
	mut seq_meta := [u64(0), 0x200, u64(unsafe { &s })]!
	mut iter_meta := [u64(0), 0x200, u64(unsafe { &s })]!
	seq_meta[0] = u64(unsafe { &seq_vwt[0] }); iter_meta[0] = u64(unsafe { &iter_vwt[0] })
	s.sequence_metadata = u64(unsafe { &seq_meta[1] }); s.iterator_metadata = u64(unsafe { &iter_meta[1] })
	for i in 0 .. 8 { seq_vwt[i] = u64(unsafe { voidptr(sequence_pod_copy) }); iter_vwt[i] = seq_vwt[i] }
	seq_vwt[1] = u64(unsafe { voidptr(sequence_destroy) }); seq_vwt[2] = u64(unsafe { voidptr(sequence_copy) })
	iter_vwt[1] = u64(unsafe { voidptr(sequence_iterator_destroy) }); seq_vwt[6] = u64(unsafe { voidptr(sequence_pod_tag) }); iter_vwt[6] = seq_vwt[6]
	seq_vwt[8] = 8; seq_vwt[9] = 8; seq_vwt[10] = 7
	iter_vwt[8] = 16; iter_vwt[9] = 16; iter_vwt[10] = 7
	element := if objc_values { api.objc_type } else if input_string { api.string_type } else { api.int_type }
	mut result := if objc_values { api.objc_result_type } else if output_string { api.string_type } else { api.int_type }
	mut limit_vwt := [12]u64{}; mut limit_meta := [u64(0), 0x200, 0]!
	if limited {
		assert !api.native && count == 1 && input_string && output_string
		for i in 0 .. 12 { limit_vwt[i] = read64(read64(result - 8) + u64(i * 8)) }
		limit_vwt[9] = u64(1) << 32; limit_meta[0] = u64(unsafe { &limit_vwt[0] })
		limit_meta[2] = read64(result + 8); result = u64(unsafe { &limit_meta[1] })
	}
	mut iter_table := [u64(0), element, api.code + 160]!
	mut seq_table := [u64(0), u64(unsafe { &iter_table[0] }), element, s.iterator_metadata, api.code + 128]!
	s.sequence_table = u64(unsafe { &seq_table[0] }); s.iterator_table = u64(unsafe { &iter_table[0] })
	mut source := [u64(unsafe { &s }), 0x123456789abcdef0]!
	s.source = u64(unsafe { &source[0] })
	mut closure := api.code + if first { u64(480) } else { u64(192) }
	$if macos { if api.native {
		sign_code := unsafe { SequenceProbeSign(voidptr(api.code + 256)) }; sign_data := unsafe { SequenceProbeSign(voidptr(api.code + 272)) }
		seq_meta[0] = sign_data(seq_meta[0], u64(unsafe { &seq_meta[0] }) | (u64(11839) << 48))
		iter_meta[0] = sign_data(iter_meta[0], u64(unsafe { &iter_meta[0] }) | (u64(11839) << 48))
		seq_vwt[2] = sign_code(seq_vwt[2], u64(unsafe { &seq_vwt[2] }) | (u64(58298) << 48))
		iter_vwt[1] = sign_code(iter_vwt[1], u64(unsafe { &iter_vwt[1] }) | (u64(1272) << 48))
		seq_table[1] = sign_data(seq_table[1], (s.sequence_table + 8) | (u64(0xb734) << 48))
		seq_table[2] = sign_data(seq_table[2], (s.sequence_table + 16) | (u64(0xb6c5) << 48))
		seq_table[3] = sign_data(seq_table[3], (s.sequence_table + 24) | (u64(0xcbc) << 48))
		seq_table[4] = sign_code(seq_table[4], (s.sequence_table + 32) | (u64(27944) << 48))
		iter_table[2] = sign_code(iter_table[2], (s.iterator_table + 16) | (u64(65124) << 48))
		closure = sign_code(closure, if first { u64(8404) } else { u64(55683) })
	} }
	mut observed := [u64(0xaaaa), 0, 0, 0, 0xbbbb]!
	if first {
		mut optional := [u64(0xaaaa), 0x7171717171717171, 0x8181818181818181, 0x9191919191919191, 0xbbbb]!
		s.first_output = u64(unsafe { &optional[1] })
		invoke := unsafe { SequenceProbeCall(voidptr(api.code + 384)) }
		invoke(api.first_entry, closure, u64(unsafe { &s }), s.sequence_metadata,
			u64(unsafe { &optional[1] }), s.sequence_table, s.source, unsafe { &observed[1] })
		assert observed[0] == 0xaaaa && observed[4] == 0xbbbb && observed[3] == s.source
		assert optional[0] == 0xaaaa && optional[4] == 0xbbbb && optional[3] == 0x9191919191919191
		assert source[0] == u64(unsafe { &s }) && source[1] == 0x123456789abcdef0
		assert s.copies == 1 && s.sequence_destroys == 0 && s.iterator_destroys == 1
		thrown := throw_at >= 0 && (selection < 0 || throw_at <= selection)
		matched := !thrown && selection >= 0
		expected := if thrown { throw_at + 1 } else if matched { selection + 1 } else { count }
		assert s.transforms == expected && s.next_calls == expected + if !thrown && !matched { 1 } else { 0 }
		assert s.kept == if matched { 1 } else { 0 }
		if thrown {
			assert observed[2] == error_owner && sequence_refs(api, error_owner) == 2
			assert optional[1] == 0x7171717171717171 && optional[2] == 0x8181818181818181
			sequence_drop(api, error_owner)
		} else {
			assert observed[2] == 0
			if matched {
				if objc_values { assert optional[1] == owner }
				else if input_string { assert optional[1] == 21 && optional[2] == owner | u64(0x5000000000000000) }
				else { assert optional[1] == u64(selection) && u8(optional[2]) == 0 }
			} else {
				if objc_values { assert optional[1] == 0 }
				else if input_string { assert optional[1] == 0x7171717171717171 && optional[2] == 0 }
				else { assert optional[1] == 0 && u8(optional[2]) == 1 }
			}
		}
		assert sequence_refs(api, owner) == 1 + if matched && input_string { i64(1) } else { i64(0) }
		if matched && input_string { sequence_drop(api, owner) }
		assert sequence_refs(api, owner) == 1 && sequence_refs(api, error_owner) == 1
		sequence_drop(api, owner); sequence_drop(api, error_owner); return
	}
	if limited {
		if _ := swift_compact_map_checked(closure, u64(unsafe { &s }), s.sequence_metadata, result, s.sequence_table, s.source) { assert false }
		assert s.copies == 1 && s.sequence_destroys == 0 && s.iterator_destroys == 1
		assert s.next_calls == 1 && s.transforms == 1 && s.kept == 1
		assert sequence_refs(api, owner) == 1 && sequence_refs(api, error_owner) == 1
		sequence_drop(api, owner); sequence_drop(api, error_owner)
		assert ios_runtime.swift_arrays.len == 0; return
	}
	invoke := unsafe { SequenceProbeCall(voidptr(api.code)) }
	invoke(api.entry, closure, u64(unsafe { &s }), s.sequence_metadata, result, s.sequence_table, s.source, unsafe { &observed[1] })
	assert observed[0] == 0xaaaa && observed[4] == 0xbbbb && observed[3] == s.source
	assert source[0] == u64(unsafe { &s }) && source[1] == 0x123456789abcdef0
	assert s.copies == 1 && s.sequence_destroys == 0 && s.iterator_destroys == 1
	if throw_at >= 0 {
		assert observed[2] == error_owner && s.transforms == throw_at + 1 && s.next_calls == s.transforms
		assert sequence_refs(api, owner) == 1 && sequence_refs(api, error_owner) == 2
		sequence_drop(api, error_owner)
	} else {
		assert observed[2] == 0 && s.transforms == count && s.next_calls == count + 1
		array := observed[1]; assert array != 0 && read64(array + 16) == u64(s.kept)
		assert read64(array + 24) & 1 == if s.kept == 0 || objc_values { u64(1) } else { u64(0) }
		mut found := 0
		for index in 0 .. count { if selection == 0 || (selection == 1 && index % 2 == 0) {
			at := array + 32 + u64(found * if objc_values { 8 } else if output_string { 16 } else { 8 })
			if objc_values { assert read64(at) == owner }
			else if output_string { assert read64(at) == 21 && read64(at + 8) == owner | u64(0x5000000000000000) }
			else { assert read64(at) == u64(index * 7 + 3) }; found++
		} }
		assert found == s.kept && sequence_refs(api, owner) == 1 + if output_string { i64(found) } else { i64(0) }
		assert api.retain(array) == array; api.release(array); api.release(array)
		assert sequence_refs(api, owner) == 1
	}
	assert sequence_refs(api, error_owner) == 1
	sequence_drop(api, owner); sequence_drop(api, error_owner)
}
fn sequence_values(api SequenceProbeApi) {
	mut cases := 0
	for input_string in [false, true]! { for output_string in [false, true]! {
		for count in [0, 1, 9, 33]! { for selection in 0 .. 3 { for throw_at in [-1, 0, 3, 31]! {
			if throw_at >= count { continue }
			sequence_scenario(api, count, input_string, output_string, selection, throw_at, false, false); cases++
		} } }
	} }
	for count in [0, 1, 9, 33]! { for selection in 0 .. 3 { for throw_at in [-1, 0, 3, 31]! {
		if throw_at >= count { continue }
		sequence_scenario(api, count, true, true, selection, throw_at, false, true); cases++
	} } }
	assert cases == 150
}
fn sequence_reader(api SequenceProbeApi) { sequence_scenario(api, 33, true, true, 1, -1, false, true) }
fn sequence_first_values(api SequenceProbeApi) {
	mut cases := 0
	for kind in 0 .. 3 { for count in [0, 1, 9, 33]! { for selection in [-1, 0, 3, 31]! { for throw_at in [-1, 0, 3, 31]! {
		if selection >= count || throw_at >= count { continue }
		sequence_scenario_checked(api, count, kind != 0, false, selection, throw_at, false, kind == 2, true); cases++
	} } } }
	assert cases == 90
}
fn sequence_first_reader(api SequenceProbeApi) { sequence_scenario_checked(api, 33, true, false, 31, -1, false, true, true) }
fn sequence_first_reject(code u64) {
	page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert guard != unsafe { voidptr(-1) }
	for args in [[u64(0), 0]!, [u64(1), 1]!, [u64(0), u64(guard)]!]! {
		if _ := swift_sequence_first_checked(code + 480, 0, args[0], args[1], u64(guard), u64(guard)) { assert false }
	}
	integer := swift_integer_metadata(); mut vwt := [12]u64{}
	for i in 0 .. 12 { vwt[i] = read64(read64(integer - 8) + u64(i * 8)) }
	mut metadata := [u64(unsafe { &vwt[0] }), 0x200, 0]!
	element := u64(unsafe { &metadata[1] })
	mut iterator := [u64(0), element, code + 160]!
	mut sequence := [u64(0), u64(unsafe { &iterator[0] }), element, integer, code + 128]!
	for address in [u64(0), 1]! {
		vwt[7] = address
		if _ := swift_sequence_first_checked(code + 480, 0, integer, u64(unsafe { &sequence[0] }), u64(guard), u64(guard)) { assert false }
	}
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_sequence_first_checked(code + 480, 0, integer, u64(guard), u64(guard), u64(guard)) { assert false }
	ios_runtime.swift_concurrency_retired = false
	if _ := swift_sequence_first_checked(0, 0, 0, 0, 0, 0) { assert false }
	assert C.munmap(guard, page) == 0
}
fn sequence_reject(code u64) {
	page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert guard != unsafe { voidptr(-1) }
	before := ios_runtime.swift_sequence_arena
	for args in [[u64(0), 0, 0]!, [u64(1), 1, 1]!, [u64(0), 0, u64(guard)]!]! {
		if _ := swift_sequence_layout_checked(args[0], args[1], args[2]) { assert false }
	}
	integer := swift_integer_metadata()
	mut vwt := [12]u64{}; for i in 0 .. 12 { vwt[i] = read64(read64(integer - 8) + u64(i * 8)) }
	mut metadata := [u64(unsafe { &vwt[0] }), 0x200, 0]!
	type_ptr := u64(unsafe { &metadata[1] })
	mut iterator := [u64(0), integer, code + 160]!
	mut sequence := [u64(0), u64(unsafe { &iterator[0] }), integer, integer, code + 128]!
	table := u64(unsafe { &sequence[0] })
	for slot in 1 .. 5 {
		old := sequence[slot]; sequence[slot] = 0
		if _ := swift_sequence_layout_checked(integer, integer, table) { assert false }; sequence[slot] = old | 1
		if _ := swift_sequence_layout_checked(integer, integer, table) { assert false }; sequence[slot] = old
	}
	iterator[1] = swift_string_metadata(); if _ := swift_sequence_layout_checked(integer, integer, table) { assert false }; iterator[1] = integer
	iterator[2] = 0; if _ := swift_sequence_layout_checked(integer, integer, table) { assert false }; iterator[2] = code + 160
	for pair in [[u64(8), 65537]!, [u64(9), 0]!, [u64(10), 0x400007]!, [u64(10), 2]!, [u64(1), 0]!, [u64(2), 0]!, [u64(4), 0]!, [u64(6), 0]!]! {
		old := vwt[int(pair[0])]; vwt[int(pair[0])] = pair[1]
		if _ := swift_compact_map_checked(code + 192, 0, type_ptr, integer, table, u64(guard)) { assert false }
		vwt[int(pair[0])] = old
	}
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_sequence_layout_checked(integer, integer, table) { assert false }
	ios_runtime.swift_concurrency_retired = false
	assert ios_runtime.swift_sequence_arena == before && ios_runtime.swift_arrays.len == 0
	assert C.munmap(guard, page) == 0
}
fn test_swift_compact_map() {
	page := usize(C.getpagesize()); base := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	sequence_probe_emit(base); C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 536) })
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		sequence_values(sequence_probe_api(true, base))
		sequence_first_values(sequence_probe_api(true, base))
		println('IOS-SEQUENCE-FIRST-NATIVE: 90 first(where:) cases; consuming copy and Iterator teardown before output construction, indirect Int/String/ObjC Optional results, predicate Bool/context and x21 throws, early termination, exact input/result/error ownership and untouched output on throws')
		println('IOS-SEQUENCE-NATIVE: 150 protocol-dispatched compactMap cases; consuming sequence copy, indirect iterator/Optional returns, borrowed transform input, context preservation, ordered kept Int/String/ObjC results and reference capacity flags, x21 throws and exact input/result/error ownership')
		if os.getenv('VINIX_IOS_COMPACT_MAP_NATIVE_ONLY') == '1' { assert C.munmap(unsafe { voidptr(base) }, page) == 0; return }
	}
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live; api := sequence_probe_api(false, base)
		sequence_values(api)
		sequence_first_values(api)
		mut readers := []thread{}; for _ in 0 .. 4 { readers << spawn sequence_reader(api) }; readers.wait(); unsafe { readers.free() }
		mut first_readers := []thread{}; for _ in 0 .. 4 { first_readers << spawn sequence_first_reader(api) }; first_readers.wait(); unsafe { first_readers.free() }
		sequence_first_reject(base)
		sequence_scenario(api, 1, true, true, 0, -1, true, false); sequence_reject(base)
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF') == none }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$sSTsE5first5where7ElementQzSgSbADKXE_tKF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSTsE5first5where7ElementQzSgSbADKXE_tKF') == none
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF') == none
		if _ := swift_compact_map_checked(0, 0, 0, 0, 0, 0) { assert false }
		assert ios_runtime.live == baseline && ios_runtime.swift_arrays.len == 0
		arena := ios_runtime.swift_sequence_arena; objc_stop(); assert ios_runtime.swift_sequence_arena == 0
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1 }
		$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(arena) }, page, unsafe { &residency }) == -1 }
	}
	assert C.munmap(unsafe { voidptr(base) }, page) == 0
	println('IOS-SEQUENCE-FIRST: borrowed Sequence copy, owned Iterator and matched element transfer; empty/missing/early matches, original owned throws and untouched indirect output, registered value witnesses, four readers, reentrant lookup, guarded/tagged/missing-store/retired rejection and two drained lifetimes')
	println('IOS-SEQUENCE: protocol-dispatched compactMap, nil filtering and ordered typed result tails; balanced consuming copy/iterator/input/result cleanup on exhaustion, throws and result-limit failure, no locks across reentrant workers, four readers, guarded/tagged/mismatched/incomplete/retired rejection, sealed adapters and two drained lifetimes')
}
