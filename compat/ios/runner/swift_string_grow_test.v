// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type GrowLiteral = fn (&u8, i64, bool) SwiftStringWords
type GrowDrop = fn (u64)
type GrowRetain = fn (u64) u64
type GrowProbe = fn (u64, i64, u64, &u64)

struct GrowApi {
	native  bool
	entry   u64
	probe   u64
	literal GrowLiteral @[required]
	drop    GrowDrop    @[required]
	retain  GrowRetain  @[required]
}

fn grow_probe(code u64) {
	// C arguments: entry, capacity, inout, capture. Swift self is x20.
	// Guard both Swift preserved registers and the caller's saved context.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203f4,
		0xaa0303f3, 0xd2824695, 0xd63f0200, 0xa9005674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn grow_call(api GrowApi, mut words SwiftStringWords, capacity i64) {
	mut capture := [u64(0xcafe), 0, 0, 0xbeef]!
	address := u64(unsafe { &words })
	unsafe { GrowProbe(voidptr(api.probe))(api.entry, capacity, address, &capture[1]) }
	assert capture == [u64(0xcafe), address, 0x1234, 0xbeef]!
}

fn grow_literal(api GrowApi, text string) SwiftStringWords {
	mut ascii := true
	for byte in text { if byte >= 128 { ascii = false } }
	return api.literal(text.str, i64(text.len), ascii)
}

fn grow_expect(words SwiftStringWords, text string) {
	assert words.second != 0 && words.second >> 60 == 0
	assert words.first & swift_count_mask == u64(text.len)
	assert C.memcmp(voidptr(words.second + 32), text.str, usize(text.len)) == 0
	assert unsafe { *(&u8(words.second + 32 + u64(text.len))) } == 0
	mut ascii := true
	for byte in text { if byte >= 128 { ascii = false } }
	assert (words.first & (u64(1) << 63) != 0) == ascii
}

fn grow_capacity(words SwiftStringWords) u64 {
	return (read64(words.second + 16) & 0x0000ffffffffffff) - 1
}

fn grow_cases(api GrowApi) {
	for text in ['', 'Fortnite', '123456789012345', '1234567890123456',
		'Fortnite capacity preserves all literal bytes', 'a\x00b', 'π/🎮/é']! {
		for capacity in [i64(-16), 0, 1, 15, 16, 24, 30, 50, 128]! {
			mut value := grow_literal(api, text)
			grow_call(api, mut value, capacity)
			grow_expect(value, text)
			assert grow_capacity(value) >= u64(text.len)
			assert capacity <= 0 || grow_capacity(value) >= u64(capacity)
			api.drop(value.second)
		}
	}
	// Unique storage is replaced with geometric growth even for a smaller
	// hint. Retained native aliases instead copy only max(hint, UTF-8 count).
	mut value := grow_literal(api, 'copy on write / π 🎮')
	grow_call(api, mut value, 128)
	old := value.second
	capacity := grow_capacity(value)
	grow_call(api, mut value, 1)
	grow_expect(value, 'copy on write / π 🎮')
	assert value.second != old && grow_capacity(value) >= capacity + (capacity >> 1) + (capacity >> 3)
	mut alias := value
	api.retain(alias.second)
	shared_owner := alias.second
	grow_call(api, mut value, 1)
	assert value.second != shared_owner
	grow_expect(value, 'copy on write / π 🎮')
	grow_expect(alias, 'copy on write / π 🎮')
	if !api.native {
		assert grow_capacity(value) == u64('copy on write / π 🎮'.len)
		assert swift_buffer_refs(alias.second, 0) or { panic(err) } == 1
	}
	api.drop(alias.second)
	grow_expect(value, 'copy on write / π 🎮')
	api.drop(value.second)
	for count in [0, 14, 15, 16, 17, 31, 32, 4096, 65536]! {
		text := 'a'.repeat(count)
		mut large := grow_literal(api, text)
		grow_call(api, mut large, i64(count + 1))
		unsafe { text.free() }
		assert large.first & swift_count_mask == u64(count)
		for i in 0 .. count {
			assert unsafe { *(&u8(large.second + 32 + u64(i))) } == `a`
		}
		api.drop(large.second)
	}
}

fn grow_worker(api GrowApi, source SwiftStringWords) {
	mut value := source
	for hint in [i64(30), 50, 16, 24]! {
		grow_call(api, mut value, hint)
		grow_expect(value, 'shared concurrent Fortnite source')
	}
	api.drop(value.second)
}

fn grow_invalid(api GrowApi, guard u64) {
	mut original := grow_literal(api, 'unchanged')
	for address in [u64(0), u64(1)]! {
		if _ := swift_string_grow_checked(30, address) {
			assert false
		}
	}
	if _ := swift_string_grow_checked(i64(swift_count_mask) + 1, u64(unsafe { &original })) {
		assert false
	}
	assert original.first == grow_literal(api, 'unchanged').first
	for malformed in [SwiftStringWords{0, u64(0x2000000000000000)},
		SwiftStringWords{u64(0x1000000000000000), guard},
		SwiftStringWords{0, guard | u64(0x5000000000000000)},
		SwiftStringWords{0, guard | u64(0x4000000000000000)},
		SwiftStringWords{0xff, u64(0xa100000000000000)}]! {
		mut value := malformed
		before := ios_runtime.swift_strings.len
		if _ := swift_string_grow_checked(30, u64(unsafe { &value })) {
			assert false
		}
		assert value == malformed && ios_runtime.swift_strings.len == before
	}
	mut value := grow_literal(api, 'registered owner')
	grow_call(api, mut value, 30)
	saved := value
	value.first = (value.first & ~swift_count_mask) | 31
	if _ := swift_string_grow_checked(50, u64(unsafe { &value })) {
		assert false
	}
	value = saved
	unsafe { *(&u64(value.second + 16)) = 1 }
	if _ := swift_string_grow_checked(50, u64(unsafe { &value })) {
		assert false
	}
	unsafe { *(&u64(value.second + 16)) = 31 }
	api.drop(value.second)
}

fn grow_private(api GrowApi, guard u64) {
	for text in ['foreign Fortnite storage', 'π/🎮/é', 'a\x00b']! {
		object := owned_string(text)
		mut units := u64(0)
		for byte in text {
			if byte & 0xc0 != 0x80 { units += if byte >= 0xf0 { u64(2) } else { u64(1) } }
		}
		mut foreign := SwiftStringWords{units, object | u64(0x5000000000000000)}
		grow_call(api, mut foreign, 50)
		grow_expect(foreign, text)
		api.drop(foreign.second)
	}
	// A readable literal ends exactly at an inaccessible page. Its source
	// need not be NUL terminated, and may be retired as soon as grow returns.
	page := usize(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != voidptr(-1)
	text := 'bounded-Fortnite!'
	start := u64(mapping) + u64(page) - u64(text.len)
	C.memcpy(voidptr(start), text.str, usize(text.len))
	assert C.mprotect(mapping, page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(u64(mapping) + u64(page)), page, C.PROT_NONE) == 0
	mut value := api.literal(unsafe { &u8(start) }, i64(text.len), true)
	grow_call(api, mut value, 30)
	assert C.munmap(mapping, page * 2) == 0
	grow_expect(value, text)
	input := grow_literal(api, '/append')
	swift_interpolation_literal(input.first, input.second, u64(unsafe { &value }))
	grow_expect(value, 'bounded-Fortnite!/append')
	api.drop(value.second)
	grow_invalid(api, guard)
}

fn grow_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss11_StringGutsV4growyySiF') or { panic(err) }
}

fn test_swift_string_grow() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != voidptr(-1)
	defer { assert C.munmap(code, page * 2) == 0 }
	probe := u64(code)
	guard := probe + u64(page)
	grow_probe(probe)
	C.__builtin___clear_cache(code, voidptr(probe + 64))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		api := GrowApi{
			native:  true
			entry:   u64(C.dlsym(lib, c'$ss11_StringGutsV4growyySiF'))
			probe:   probe
			literal: unsafe { GrowLiteral(C.dlsym(lib, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }
			drop:    unsafe { GrowDrop(C.dlsym(lib, c'swift_bridgeObjectRelease')) }
			retain:  unsafe { GrowRetain(C.dlsym(lib, c'swift_bridgeObjectRetain')) }
		}
		assert api.entry != 0
		grow_cases(api)
		println('NATIVE-STRING-GROW: installed runtime preserves UTF-8/NUL, total capacity, negative/small hints, unique geometric growth, retained alias copies and x20/x21')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn grow_resolve() }
		entry := publishers[0].wait()
		for i in 1 .. publishers.len {
			assert publishers[i].wait() == entry
		}
		api := GrowApi{ entry: entry, probe: probe, literal: swift_string_literal, drop: swift_bridge_release, retain: swift_bridge_retain }
		grow_cases(api)
		grow_private(api, guard)
		mut shared_value := grow_literal(api, 'shared concurrent Fortnite source')
		grow_call(api, mut shared_value, 100)
		mut workers := []thread{}
		for _ in 0 .. 8 {
			api.retain(shared_value.second)
			workers << spawn grow_worker(api, shared_value)
		}
		for worker in workers { worker.wait() }
		grow_expect(shared_value, 'shared concurrent Fortnite source')
		assert swift_buffer_refs(shared_value.second, 0) or { panic(err) } == 1
		api.drop(shared_value.second)
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0
		arena := ios_runtime.swift_interpolation_arena
		objc_stop()
		assert ios_runtime.swift_interpolation_arena == 0
		assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
	}
	println('IOS-STRING-GROW: checked x20 inout capacity, unique geometric growth and COW, UTF-8/NUL and foreign storage, guarded literals/owners, eight cold publishers/workers and two drained/unmapped lifetimes')
}
