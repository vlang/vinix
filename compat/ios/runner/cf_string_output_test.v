// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type OutputCall = fn (u64, CFRange, u32, u8, bool, u64, i64, &i64) i64
type OutputCreate = fn (u64, u64, i64, u32, bool) u64
type OutputDrop = fn (u64)
type OutputLength = fn (u64) i64
struct OutputApi {
	native bool
	call OutputCall
	create OutputCreate
	drop OutputDrop
	length OutputLength
}
fn output_api(native bool) OutputApi {
	$if macos { if native {
		lib := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		return OutputApi{native: true,
			call: unsafe { OutputCall(C.dlsym(lib, c'CFStringGetBytes')) },
			create: unsafe { OutputCreate(C.dlsym(lib, c'CFStringCreateWithBytes')) },
			drop: unsafe { OutputDrop(C.dlsym(lib, c'CFRelease')) },
			length: unsafe { OutputLength(C.dlsym(lib, c'CFStringGetLength')) }}
	} }
	entry := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFStringGetBytes') or { panic(err) }
	create := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFStringCreateWithBytes') or { panic(err) }
	length := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFStringGetLength') or { panic(err) }
	return OutputApi{call: unsafe { OutputCall(voidptr(entry)) }, create: unsafe { OutputCreate(voidptr(create)) },
		length: unsafe { OutputLength(voidptr(length)) }, drop: objc_release}
}

fn input_case(api OutputApi, bytes []u8, units []u16, encoding u32, external bool) {
	// A mutable, deliberately unaligned source verifies that Create copies it.
	mut source := []u8{len: bytes.len + 2, init: 0xa5}
	for index, byte in bytes { source[index + 1] = byte }
	object := api.create(0, u64(unsafe { &source[1] }), bytes.len, encoding, external)
	for index in 0 .. source.len { source[index] = 0x5a }
	unsafe { source.free() }
	if bytes.len == 1 && (encoding != 0x100 || external) { assert object == 0; return }
	assert object != 0 && api.length(object) == units.len
	for start in 0 .. units.len + 1 {
	for length in 0 .. units.len - start + 1 {
	for capacity in [i64(0), 1, 3, 16] {
		output_case(api, object, units, CFRange{start, length}, 0x14000100, false, capacity, false)
	} } }
	api.drop(object)
}

fn input_matrix(api OutputApi) {
	for units in [ []u16{}, [u16(0x41), 0, 0x3c0, 0xd83c, 0xdfae, 0x5a],
		[u16(0xd83c)], [u16(0xdfae)], [u16(0x41), 0xd83c, 0x5a],
		[u16(0xd83c), 0xd83c, 0xdfae, 0xdfae], [u16(0xfffe), 0xfeff, 0x41] ] {
	for encoding in [u32(0x100), 0x14000100, 0x10000100] {
	for external in [false, true] {
	for bom in [false, true] {
		big_endian := encoding == 0x10000100 || (encoding == 0x100 && external)
		mut bytes := []u8{cap: units.len * 2 + 3}
		mut expected := []u16{cap: units.len + 1}
		if bom {
			bytes << if big_endian { u8(0xfe) } else { u8(0xff) }
			bytes << if big_endian { u8(0xff) } else { u8(0xfe) }
			if encoding != 0x100 || !external { expected << u16(0xfeff) }
		}
		for unit in units {
			bytes << if big_endian { u8(unit >> 8) } else { u8(unit) }
			bytes << if big_endian { u8(unit) } else { u8(unit >> 8) }
		}
		expected << units
		// An initial reverse mark on external native input selects LE order.
		if !bom && encoding == 0x100 && external && units.len > 0 && units[0] == 0xfffe {
			expected.clear()
			for unit in units[1..] { expected << (unit >> 8) | (unit << 8) }
		}
		input_case(api, bytes, expected, encoding, external)
		bytes << u8(0xa5) // Native CF ignores an odd trailing byte after complete units.
		input_case(api, bytes, expected, encoding, external)
		unsafe { bytes.free(); expected.free() }
	} } }
	unsafe { units.free() }
	}
	// External native UTF-16 consumes either byte-order mark.
	for bytes in [[u8(0xff), 0xfe, 0x41, 0], [u8(0xfe), 0xff, 0, 0x41]] {
		input_case(api, bytes, [u16(0x41)], 0x100, true)
		unsafe { bytes.free() }
	}
	// UTF-8 output must stop before an isolated surrogate, even with lossByte.
	for middle in [u8(0xd8), 0xdc] {
		bytes := [u8(0x41), 0, 0, middle, 0x5a, 0]
		object := api.create(0, u64(bytes.data), bytes.len, 0x14000100, false)
		for loss in [u8(0), 63] {
		for query in [false, true] {
			mut buffer := [16]u8{init: 0xa5}
			mut used := i64(-1)
			assert api.call(object, CFRange{0, 3}, 0x08000100, loss, false,
				if query { 0 } else { u64(unsafe { &buffer[1] }) }, 8, &used) == 1
			assert used == 1 && buffer[0] == 0xa5 && buffer[2] == 0xa5
			assert buffer[1] == if query { u8(0xa5) } else { u8(0x41) }
		} }
		api.drop(object)
		unsafe { bytes.free() }
	}
}

fn input_guard(api OutputApi) {
	page := usize(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != voidptr(-1)
	assert C.mprotect(voidptr(u64(mapping) + u64(page)), page, C.PROT_NONE) == 0
	for length in 0 .. 18 {
		pointer := u64(mapping) + u64(page) - u64(length)
		unsafe { C.memset(voidptr(pointer), 0x41, usize(length)) }
		for encoding in [u32(0x100), 0x14000100, 0x10000100] {
		for external in [false, true] {
			object := api.create(0, pointer, length, encoding, external)
			if length == 1 && (encoding != 0x100 || external) { assert object == 0; continue }
			assert object != 0 && api.length(object) == length / 2
			mut buffer := [32]u8{init: 0xa5}
			mut used := i64(-1)
			assert api.call(object, CFRange{0, length / 2}, 0x14000100, 0, false,
				u64(unsafe { &buffer[1] }), 30, &used) == length / 2
			assert used == (length / 2) * 2 && buffer[0] == 0xa5 && buffer[int(used) + 1] == 0xa5
			for index in 0 .. int(used) { assert buffer[index + 1] == 0x41 }
			api.drop(object)
		} }
	}
	for external in [false, true] {
		object := api.create(0, 0, 0, 0x100, external); assert object != 0; api.drop(object)
	}
	assert C.munmap(mapping, page * 2) == 0
}
fn output_case(api OutputApi, object u64, units []u16, range CFRange, encoding u32, external bool, capacity i64, query bool) {
	mut buffer := [32]u8{init: 0xa5}
	bom := encoding == 0x100 && external
	if api.native && bom && capacity < 2 && !query { return } // Native CF overruns these capacities.
	prefix := if bom && (query || capacity >= 2) { i64(2) } else { i64(0) }
	available := (capacity - prefix) / 2
	count := if query { range.length } else if capacity < prefix { i64(0) } else if range.length < available { range.length } else { available }
	mut expected := [32]u8{init: 0xa5}
	if !query {
		if prefix != 0 { expected[1] = 0xff; expected[2] = 0xfe }
		for index in 0 .. int(count) {
			value := units[int(range.location) + index]
			start := 1 + int(prefix) + index * 2
			expected[start] = if encoding == 0x10000100 { u8(value >> 8) } else { u8(value) }
			expected[start + 1] = if encoding == 0x10000100 { u8(value) } else { u8(value >> 8) }
		}
	}
	mut used := i64(-1)
	converted := api.call(object, range, encoding, 63, external, if query { 0 } else { u64(unsafe { &buffer[1] }) }, capacity, &used)
	assert converted == count
	assert used == prefix + count * 2
	assert buffer == expected // Deliberately unaligned, including untouched tail and both canaries.
}
fn output_matrix(api OutputApi) {
	for text in ['', 'AZ', 'A\x00π🎮Z'] {
		units := match text { '' { []u16{} } 'AZ' { [u16(0x41), 0x5a] } else { [u16(0x41), 0, 0x3c0, 0xd83c, 0xdfae, 0x5a] } }
		object := api.create(0, u64(text.str), text.len, 0x08000100, false)
		assert object != 0
		for encoding in [u32(0x100), 0x14000100, 0x10000100] {
		for external in [false, true] {
		for start in 0 .. units.len + 1 {
		for length in 0 .. units.len - start + 1 {
		for capacity in [i64(0), 1, 2, 3, 4, 5, 7, 16] {
		for query in [false, true] {
			output_case(api, object, units, CFRange{start, length}, encoding, external, capacity, query)
		} } } } } }
		api.drop(object)
		unsafe { units.free() }
	}
}
fn output_guard(api OutputApi) {
	page := usize(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != voidptr(-1)
	assert C.mprotect(voidptr(u64(mapping) + u64(page)), page, C.PROT_NONE) == 0
	text := 'A\x00π🎮Z'
	object := api.create(0, u64(text.str), text.len, 0x08000100, false)
	for capacity in 0 .. 14 {
		pointer := u64(mapping) + u64(page) - u64(capacity)
		for encoding in [u32(0x100), 0x14000100, 0x10000100, 0x08000100, 0x600] {
			mut used := i64(-1)
			converted := api.call(object, CFRange{0, 6}, encoding, 63, false, pointer, capacity, &used)
			if capacity == 0 && encoding == 0x08000100 {
				assert converted == 6 && used == 9 // Native UTF-8's non-null sizing convention.
			} else {
				assert used >= 0 && used <= capacity && converted >= 0 && converted <= 6
				if capacity == 0 { assert converted == 0 && used == 0 }
			}
			assert api.call(object, CFRange{0, 6}, encoding, 63, false, pointer, capacity, unsafe { nil }) == converted
		}
		if !api.native && capacity < 2 {
			mut used := i64(-1)
			assert api.call(object, CFRange{0, 6}, 0x100, 63, true, pointer, capacity, &used) == 0
			assert used == 0
		}
	}
	// The game's sizing call followed by an odd capacity; conversion leaves its terminator space untouched.
	mut size := i64(-1)
	assert api.call(object, CFRange{0, 6}, 0x14000100, 63, false, 0, 0, &size) == 6 && size == 12
	mut buffer := [16]u8{init: 0xa5}
	assert api.call(object, CFRange{0, 6}, 0x14000100, 63, false, u64(unsafe { &buffer[0] }), size | 1, unsafe { nil }) == 6
	assert buffer == [u8(0x41), 0, 0, 0, 0xc0, 3, 0x3c, 0xd8, 0xae, 0xdf, 0x5a, 0, 0xa5, 0xa5, 0xa5, 0xa5]!
	api.drop(object)
	assert C.munmap(mapping, page * 2) == 0
}
fn output_worker(api OutputApi, object u64) {
	units := [u16(0x41), 0, 0x3c0, 0xd83c, 0xdfae, 0x5a]
	for _ in 0 .. 100 { output_case(api, object, units, CFRange{0, 6}, 0x14000100, false, 13, false) }
	unsafe { units.free() }
}
fn output_threads(api OutputApi) {
	text := 'A\x00π🎮Z'; object := api.create(0, u64(text.str), text.len, 0x08000100, false)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn output_worker(api, object) }
	workers.wait(); api.drop(object)
	unsafe { workers.free() }
}
fn test_cf_string_output() {
	$if macos {
		api := output_api(true); input_matrix(api); input_guard(api); output_matrix(api); output_guard(api); output_threads(api)
		println('IOS-CF-STRING-INPUT-NATIVE: endian/BOM, odd input, surrogate preservation, owned copy, C ABI and guard pages PASS')
		println('IOS-CF-STRING-OUTPUT-NATIVE: UTF-16 ranges, endian/BOM, sizing, partial buffers, C ABI, guard pages and concurrent readers PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); api := output_api(false)
		input_matrix(api); input_guard(api); output_matrix(api); output_guard(api); output_threads(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-CF-STRING-INPUT: endian/BOM, odd input, surrogate preservation, owned copy, C ABI and guard pages PASS')
	println('IOS-CF-STRING-OUTPUT: UTF-16 ranges including surrogate halves, endian/BOM, null sizing, zero/odd capacities, unaligned canaries, guard pages, null used pointer, game call sequence, UTF-8/ASCII capacity regression, concurrent readers and two drained runtimes PASS')
}
