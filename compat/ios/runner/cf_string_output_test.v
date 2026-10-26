// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type OutputCall = fn (u64, CFRange, u32, u8, bool, u64, i64, &i64) i64
type OutputCreate = fn (u64, u64, i64, u32, bool) u64
type OutputDrop = fn (u64)
struct OutputApi {
	native bool
	call OutputCall
	create OutputCreate
	drop OutputDrop
}
fn output_api(native bool) OutputApi {
	$if macos { if native {
		lib := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		return OutputApi{native: true,
			call: unsafe { OutputCall(C.dlsym(lib, c'CFStringGetBytes')) },
			create: unsafe { OutputCreate(C.dlsym(lib, c'CFStringCreateWithBytes')) },
			drop: unsafe { OutputDrop(C.dlsym(lib, c'CFRelease')) }}
	} }
	entry := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFStringGetBytes') or { panic(err) }
	return OutputApi{call: unsafe { OutputCall(voidptr(entry)) }, create: cf_string_bytes, drop: objc_release}
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
		api := output_api(true); output_matrix(api); output_guard(api); output_threads(api)
		println('IOS-CF-STRING-OUTPUT-NATIVE: UTF-16 ranges, endian/BOM, sizing, partial buffers, C ABI, guard pages and concurrent readers PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); api := output_api(false)
		output_matrix(api); output_guard(api); output_threads(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-CF-STRING-OUTPUT: UTF-16 ranges including surrogate halves, endian/BOM, null sizing, zero/odd capacities, unaligned canaries, guard pages, null used pointer, game call sequence, UTF-8/ASCII capacity regression, concurrent readers and two drained runtimes PASS')
}
