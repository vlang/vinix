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
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type IdInvoke = fn (u64, u64, u64, u64, &u64)
type IdLookup = fn (u64, u64, u64) u64
type IdBytes = fn (u64, u64) u64
type IdDrop = fn (u64)
type IdKeep = fn (u64) u64
type IdCString = fn (&u8) SwiftStringWords
type IdSign = fn (u64, u64) u64

struct IdApi {
	native      bool
	code        u64
	table       u64
	conformance u64
	protocol    u64
	dispatch    u64
	integer     u64
	lookup      IdLookup @[required]
	bytes       IdBytes  @[required]
	drop        IdDrop   @[required]
	keep        IdKeep   @[required]
	cstring     u64
}

const id_exports = ['_$sSis23CustomStringConvertiblesWP', '_$sSis23CustomStringConvertiblesMc',
	'_$ss23CustomStringConvertibleMp', '_$ss23CustomStringConvertibleTL',
	'_$ss23CustomStringConvertibleP11descriptionSSvgTq',
	'_$ss23CustomStringConvertibleP11descriptionSSvgTj']

fn id_symbol(native bool, name string) u64 {
	if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert core != unsafe { nil }
		address := u64(C.dlsym(core, name[1..].str))
		assert address != 0, name
		return address
	}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
}

fn id_api(native bool, code u64) IdApi {
	return IdApi{
		native:      native
		code:        code
		table:       id_symbol(native, id_exports[0])
		conformance: id_symbol(native, id_exports[1])
		protocol:    id_symbol(native, id_exports[2])
		dispatch:    id_symbol(native, id_exports[5])
		integer:     id_symbol(native, '_$sSiN')
		lookup:      unsafe { IdLookup(voidptr(id_symbol(native, '_swift_getWitnessTable'))) }
		bytes:       unsafe { IdBytes(voidptr(id_symbol(native, '_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg'))) }
		drop:        unsafe { IdDrop(voidptr(id_symbol(native, '_swift_bridgeObjectRelease'))) }
		keep:        unsafe { IdKeep(voidptr(id_symbol(native, '_swift_bridgeObjectRetain'))) }
		cstring:     if native {
			id_symbol(native, '_$sSS7cStringSSSPys4Int8VG_tcfC')
		} else {
			u64(0)
		}
	}
}

fn id_relative(at u64) u64 { return u64(i64(at) + i64(i32(read32(at)))) }

fn id_declaration(api IdApi, guard u64) {
	p := api.protocol
	d := api.conformance
	assert read64(api.table) == d && read64(api.table + 8) != 0 && read32(d + 12) == 0
	assert id_relative(d) == p && id_relative(d + 4) == read64(api.integer + 8) && id_relative(d + 8) == api.table
	assert read32(p) == 0x30043 && read32(p + 12) == 0 && read32(p + 16) == 1 && read32(p + 20) == 0 && read32(p + 24) == 0x8be30013 && read32(p + 28) == 0
	assert unsafe { (&char(id_relative(p + 8))).vstring() } == 'CustomStringConvertible'
	parent := id_relative(p + 4)
	assert unsafe { (&char(id_relative(parent + 8))).vstring() } == 'Swift'
	assert id_symbol(api.native, id_exports[3]) == p + 16 && id_symbol(api.native, id_exports[4]) == p + 24
	for metadata in [u64(0), guard, ~u64(0)]! {
		for arguments in [u64(0), guard, ~u64(0)]! {
			assert api.lookup(d, metadata, arguments) == api.table
		}
	}
	if !api.native {
		id_protection(api.table, 32, false)
		id_protection(api.dispatch, 8, true)
		id_protection(read64(api.table + 8), 24, true)
	}
}

fn id_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303f4, 0xaa0403f3, u32(0xd2800000 | (0x5121 << 5) | 21), 0xd63f0200, 0xa9000660,
		0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 128, 0xdac10020)
	write32(code + 132, 0xd65f03c0)
	write32(code + 160, 0xaa1403e0)
	write32(code + 164, 0x58000070)
	write32(code + 168, 0xd61f0200)
	write32(code + 172, 0xd503201f)
	unsafe { *(&u64(code + 176)) = u64(voidptr(id_callback)) }
}

fn id_assert(api IdApi, words SwiftStringWords, expected string) {
	assert words.second != 0
	small := words.second & (u64(1) << 61) != 0
	assert small == (expected.len <= 15)
	if !small {
		assert read64(words.second + 8) >> 33 == 0
		api.keep(words.second)
		assert read64(words.second + 8) >> 33 == 1
		api.drop(words.second)
		assert read64(words.second + 8) >> 33 == 0
	}
	array := api.bytes(words.first, words.second)
	assert read64(array + 16) == u64(expected.len + 1)
	assert C.memcmp(voidptr(array + 32), expected.str, usize(expected.len)) == 0 && unsafe { *(&u8(array + 32 + u64(expected.len))) } == 0
	api.drop(array)
	api.drop(words.second)
}

fn id_case(api IdApi, value i64, at_end bool, dispatch bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 5) == 0 }
	for offset in [u64(page), u64(page * 3)]! {
		assert C.mprotect(voidptr(span + offset), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	source := span + u64(page) + if at_end { u64(page) - 8 } else { u64(0) }
	output := span + u64(page * 3) + if at_end { u64(page) - 48 } else { u64(0) }
	unsafe {
		*(&i64(source)) = value
		*(&u64(output)) = 0xaaaa
		*(&u64(output + 40)) = 0xbbbb
	}
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	entry := if dispatch { api.dispatch } else { read64(api.table + 8) & 0x0000ffffffffffff }
	metadata := if dispatch { api.integer } else { span }
	table := if dispatch { api.table } else { span }
	unsafe { IdInvoke(voidptr(api.code))(entry, metadata, table, source, &u64(output + 8)) }
	assert read64(output) == 0xaaaa && read64(output + 40) == 0xbbbb && read64(output + 24) == source && read64(output + 32) == 0x5121 && read64(source) == u64(value)
	expected := value.str()
	id_assert(api, SwiftStringWords{ first: read64(output + 8), second: read64(output + 16) }, expected)
	unsafe { expected.free() }
}

fn id_values() []i64 {
	mut values := []i64{cap: 400}
	for value in [i64(0), 1, -1, 9223372036854775807, i64(-9223372036854775807) - 1]! {
		values << value
	}
	mut power := i64(1)
	for _ in 0 .. 19 {
		for delta in [i64(-1), 0, 1]! {
			value := power + delta
			values << value
			values << -value
		}
		if power < 1000000000000000000 { power *= 10 }
	}
	mut bits := u64(0x91379bade1234679)
	for _ in 0 .. 128 {
		bits ^= bits << 13
		bits ^= bits >> 7
		bits ^= bits << 17
		values << i64(bits)
	}
	return values
}

fn id_matrix(api IdApi) {
	values := id_values()
	for value in values {
		for at_end in [false, true]! {
			for dispatch in [false, true]! { id_case(api, value, at_end, dispatch) }
		}
	}
	unsafe { values.free() }
}

struct IdContext {
	api IdApi
mut:
	calls int
}

fn id_callback(receiver u64) SwiftStringWords {
	mut context := unsafe { &IdContext(read64(receiver)) }
	assert read64(receiver + 8) == 0x12345678
	context.calls++
	expected := 'generic description getter returns owned text'
	if context.api.native {
		return unsafe { IdCString(voidptr(context.api.cstring))(expected.str) }
	}
	worker := spawn id_publish()
	assert worker.wait() == context.api.table
	mut words := swift_interpolation_init(i64(expected.len), 0)
	swift_string_append_bytes(u64(unsafe { &words }), u64(expected.str), u64(expected.len))
	return words
}

fn id_generic(api IdApi, at_end bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 5) == 0 }
	for offset in [u64(page), u64(page * 3)]! {
		assert C.mprotect(voidptr(span + offset), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	table := span + u64(page) + if at_end { u64(page) - 16 } else { u64(0) }
	receiver := span + u64(page * 3) + if at_end { u64(page) - 16 } else { u64(0) }
	mut context := IdContext{ api: api }
	mut method := api.code + 160
	$if macos {
		if api.native {
			method = unsafe { IdSign(voidptr(api.code + 128))(method, (table + 8) | (u64(0x8be3) << 48)) }
		}
	}
	unsafe {
		*(&u64(table)) = span
		*(&u64(table + 8)) = method
		*(&u64(receiver)) = u64(&context)
		*(&u64(receiver + 8)) = 0x12345678
	}
	for offset in [u64(page), u64(page * 3)]! {
		assert C.mprotect(voidptr(span + offset), page, C.PROT_READ) == 0
	}
	mut output := [u64(0xaaaa), 0, 0, 0, 0, 0xbbbb]!
	unsafe { IdInvoke(voidptr(api.code))(api.dispatch, span, table, receiver, &output[1]) }
	assert context.calls == 1 && output[0] == 0xaaaa && output[5] == 0xbbbb && output[3] == receiver && output[4] == 0x5121
	id_assert(api, SwiftStringWords{ first: output[1], second: output[2] }, 'generic description getter returns owned text')
}

fn id_string(api IdApi) {
	expected := 'String and Int share a canonical description protocol'
	mut words := SwiftStringWords{}
	if api.native {
		words = unsafe { IdCString(voidptr(api.cstring))(expected.str) }
	} else {
		words = swift_interpolation_init(i64(expected.len), 0)
		swift_string_append_bytes(u64(unsafe { &words }), u64(expected.str), u64(expected.len))
	}
	table := id_symbol(api.native, '_$sSSs23CustomStringConvertiblesWP')
	assert id_relative(read64(table)) == api.protocol
	metadata := id_symbol(api.native, '_$sSSN')
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	source := span + u64(page) - 16
	unsafe { *(&SwiftStringWords(source)) = words }
	assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0 && C.mprotect(voidptr(span + u64(page)), page, C.PROT_NONE) == 0
	mut output := [u64(0xaaaa), 0, 0, 0, 0, 0xbbbb]!
	unsafe { IdInvoke(voidptr(api.code))(api.dispatch, metadata, table, source, &output[1]) }
	assert output[0] == 0xaaaa && output[5] == 0xbbbb && output[3] == source && output[4] == 0x5121 && output[1] == words.first && output[2] == words.second && read64(words.second + 8) >> 33 == 1
	api.drop(words.second)
	id_assert(api, SwiftStringWords{ first: output[1], second: output[2] }, expected)
	assert C.munmap(voidptr(span), page * 2) == 0
}

fn id_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', id_exports[0]) or { panic(err) }
}

fn id_worker(api IdApi, index int) {
	for i in 0 .. 8 {
		id_case(api, if index & 1 == 0 {
			i64(9223372036854775807) - i
		} else {
			i64(-9223372036854775807) + i
		}, i & 1 == 0, index & 2 == 0)
	}
}

fn id_reject() {
	for symbol in id_exports {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
	}
}

fn test_swift_integer_description() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	id_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 184))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		api := id_api(true, code)
		id_declaration(api, guard)
		id_matrix(api)
		id_string(api)
		for boundary in [false, true]! { id_generic(api, boundary) }
		println('NATIVE-INTEGER-DESCRIPTION: exact static Int conformance and protocol records, borrowed eight-byte Self, decimal extremes/powers/random values, owned inline/large String results, generic caller witness dispatch and preserved x20/x21')
	}
	id_reject()
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn id_publish() }
		identities := publishers.wait()
		api := id_api(false, code)
		for table in identities {
			assert table == api.table
		}
		unsafe {
			identities.free()
			publishers.free()
		}
		id_declaration(api, guard)
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn id_worker(api, i) }
		workers.wait()
		unsafe { workers.free() }
		id_matrix(api)
		id_string(api)
		for boundary in [false, true]! { id_generic(api, boundary) }
		for symbol in id_exports {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol[1..]) == none
			for library in ['/usr/lib/swift/libswiftFoundation.dylib', '/usr/lib/libSystem.B.dylib']! {
				assert runtime_symbol(library, symbol) == none
			}
		}
		for symbol in ['_$sSi11descriptionSSvg', '_$sSus23CustomStringConvertiblesWP',
			'_$ss28CustomDebugStringConvertibleMp']! {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
		}
		ios_runtime.swift_concurrency_retired = true
		id_reject()
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_integer_description_arena
		objc_stop()
		assert ios_runtime.swift_integer_arena == 0 && ios_runtime.swift_integer_description_arena == 0 && ios_runtime.swift_integer_description_retired
		id_reject()
		for offset in [u64(0), u64(page)]! {
			$if macos {
				assert C.mprotect(voidptr(arena + offset), page, C.PROT_READ) == -1
			} $else {
				mut resident := u8(0)
				assert C.mincore(voidptr(arena + offset), page, unsafe { &resident }) == -1
			}
		}
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-INTEGER-DESCRIPTION: canonical static witnesses and generic description dispatch, exact signed decimals and owned String results, guarded readonly Self/table records, ignored concrete lookup arguments, eight cold publishers/workers, reentrant caller witnesses and two drained/unmapped lifetimes')
}

fn id_protection(address u64, length u64, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + length <= start + size
		assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
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
