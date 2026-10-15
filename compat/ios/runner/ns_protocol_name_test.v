// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type PNLookup = fn (u64) u64
type PNName = fn (&char) u64
type PNDrop = fn (u64)
type PNPush = fn () u64
type PNBytes = fn (u64, &char, i64, u32) bool
type PNProbe = fn (u64, u64, u64, &u64)
struct PNApi { native bool values [8]u64 objc u64 core u64 probe u64 guard u64 }
fn pn_api(native bool, probe u64, guard u64) PNApi {
	mut obj := unsafe { voidptr(nil) }; mut core := unsafe { voidptr(nil) }; mut foundation := unsafe { voidptr(nil) }
	$if macos { if native {
		obj = C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		core = C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		foundation = C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
	} }
	mut values := [8]u64{}
	for i, name in ['_NSStringFromProtocol', '_objc_getProtocol', '_protocol_getName', '_NSProtocolFromString', '_objc_retain', '_objc_release', '_objc_autoreleasePoolPush', '_objc_autoreleasePoolPop']! {
		is_foundation := i in [0, 3]!
		values[i] = if native { u64(C.dlsym(if is_foundation { foundation } else { obj }, unsafe { &char(name.str + 1) })) } else { runtime_symbol(if is_foundation { '/System/Library/Frameworks/Foundation.framework/Foundation' } else { '/usr/lib/libobjc.A.dylib' }, name) or { panic(err) } }
		assert values[i] != 0
	}
	return PNApi{native, values, u64(obj), u64(core), probe, guard}
}
fn pn_call(api PNApi, slot int, value u64) u64 { return unsafe { PNLookup(voidptr(api.values[slot]))(value) } }
fn pn_drop(api PNApi, value u64) { unsafe { PNDrop(voidptr(api.values[5]))(value) } }
fn pn_pool(api PNApi) u64 { return unsafe { PNPush(voidptr(api.values[6]))() } }
fn pn_pop(api PNApi, pool u64) { unsafe { PNDrop(voidptr(api.values[7]))(pool) } }
fn pn_text(api PNApi, value u64, expected string) {
	assert value != 0
	if !api.native { assert string_text(value) == expected; return }
	mut buffer := [2048]u8{}
	assert unsafe { PNBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&buffer[0]), 2048, 0x08000100) }
	assert buffer[expected.len] == 0 && C.memcmp(unsafe { &buffer[0] }, expected.str, usize(expected.len)) == 0
}
fn pn_define(api PNApi, text string) u64 {
	if api.native {
		found := unsafe { PNName(C.dlsym(voidptr(api.objc), c'objc_getProtocol'))(text.str) }
		if found != 0 { return found }
		value := unsafe { PNName(C.dlsym(voidptr(api.objc), c'objc_allocateProtocol'))(text.str) }; assert value != 0
		unsafe { PNDrop(C.dlsym(voidptr(api.objc), c'objc_registerProtocol'))(value) }
		return value
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return objc_protocol_define(text) or { panic(err) }
}
fn pn_case(api PNApi, protocol u64, canonical u64, expected string, isolated bool) {
	baseline := if api.native || !isolated { i64(0) } else { ios_runtime.live }
	pool := pn_pool(api)
	first := pn_call(api, 0, protocol)
	mut capture := [u64(0xcafe), 0, 0, 0, 0xbeef]!
	unsafe { PNProbe(voidptr(api.probe))(api.values[0], protocol, api.guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[2] == api.guard && capture[3] == 0x1234 && capture[4] == 0xbeef
	second := capture[1]
	pn_text(api, first, expected); pn_text(api, second, expected)
	if protocol != 0 { assert pn_call(api, 3, first) == canonical && pn_call(api, 3, second) == canonical }
	assert unsafe { (&char(pn_call(api, 2, protocol))).vstring() } == expected
	if !api.native && isolated { assert first != second && obj_header(first).refs == 1 && obj_header(second).refs == 1 && ios_runtime.live == baseline + 2 }
	assert pn_call(api, 4, first) == first
	pn_pop(api, pool)
	pn_text(api, first, expected)
	if !api.native && isolated { assert obj_header(first).refs == 1 && second !in ios_runtime.objects }
	pn_drop(api, first)
	if !api.native && isolated { assert ios_runtime.live == baseline }
}
fn pn_worker(api PNApi, protocol u64, text string) {
	pool := pn_pool(api)
	for _ in 0 .. 32 { pn_case(api, protocol, protocol, text, false); pn_case(api, 0, 0, 'nil', false) }
	pn_pop(api, pool)
}
fn pn_shared(api PNApi) {
	pn_case(api, 0, 0, 'nil', true)
	for text in ['NSObject', 'VinixProtocolNameReference', 'Vinix.ProtocolName_π_🎮', 'Vinix.ProtocolName with space']! {
		protocol := pn_define(api, text)
		pn_case(api, protocol, protocol, text, true)
	}
	long_name := 'VinixProtocolName' + 'x'.repeat(1006)
	assert long_name.len == 1023
	long_protocol := pn_define(api, long_name)
	pn_case(api, long_protocol, long_protocol, long_name, true)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn pn_worker(api, long_protocol, long_name) }
	workers.wait(); unsafe { workers.free(); long_name.free() }
}
fn pn_image(api PNApi, base u64, size u64) {
	text := 'VinixImageProtocolName_π_🎮'
	name_at := base + size - u64(text.len) - 1
	C.memset(unsafe { voidptr(base) }, 0, usize(size))
	C.memcpy(unsafe { voidptr(name_at) }, text.str, usize(text.len + 1))
	unsafe { *(&u64(base)) = base + 128; *(&u64(base + 32)) = base + 128; *(&u64(base + 136)) = name_at }
	write32(base + 192, 96)
	metadata := ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA', address: 0x1000, filesize: size, size: size, prot: 3, sections: [macho.Section{name: '__objc_protolist', address: 0x1000, size: 8}, macho.Section{name: '__objc_protorefs', address: 0x1020, size: 8}]}]}, layout: macho.Layout{base: 0x1000, size: size}, base: base}
	metadata.protocols_register() or { panic(err) }
	canonical := read64(base + 32)
	assert canonical != 0 && canonical != base + 128
	// Erase the caller-owned source after registration: names and returned
	// NSString bytes must be independently owned. Alias lookup never reads it.
	C.memset(unsafe { voidptr(name_at) }, 0x58, usize(text.len))
	pn_case(api, base + 128, canonical, text, true)
	pn_case(api, canonical, canonical, text, true)
	pool := pn_pool(api)
	result := pn_call(api, 0, base + 128)
	info := ios_runtime.protocols[canonical] or { panic('missing protocol fixture') }
	assert u64(obj_header(result).text) != u64(info.name.str)
	pn_pop(api, pool)
	for value in [u64(1), ~u64(0), api.guard, ios_runtime.names['NSObject']]! { if _ := ns_string_from_protocol_checked(value) { assert false } }
	object := owned_string('NSObject')
	if _ := ns_string_from_protocol_checked(object) { assert false }
	objc_release(object)
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
}
fn test_ns_string_from_protocol() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	data := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != voidptr(-1) && data != voidptr(-1)
	defer { assert C.munmap(code, page * 2) == 0 && C.munmap(data, page * 2) == 0 }
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1, 0xaa0203e8, 0xaa0203f4, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5, 0xaa0203e6, 0xaa0203e7, 0xd2824695, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	C.__builtin___clear_cache(code, voidptr(u64(code) + 88))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(u64(code) + u64(page)), page, C.PROT_NONE) == 0 && C.mprotect(voidptr(u64(data) + u64(page)), page, C.PROT_NONE) == 0
	$if macos {
		pn_shared(pn_api(true, u64(code), u64(code) + u64(page)))
		println('IOS-PROTOCOL-NAME-NATIVE: nil literal, exact Unicode/space/1023-byte names, guarded C ABI, +0 strings retained across pools, round trips and eight concurrent readers')
	}
	if _ := ns_string_from_protocol_checked(0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		api := pn_api(false, u64(code), u64(code) + u64(page))
		pn_shared(api); pn_image(api, u64(data), u64(page))
		for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, '_NSStringFromProtocol') { assert false } }
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.protocols.len == 0
		if _ := ns_string_from_protocol_checked(0) { assert false }
	}
	println('IOS-PROTOCOL-NAME: nil literal and C name parity, copied canonical/image-alias names, guarded ABI, foreign-pointer/lifecycle rejection, pool ownership, concurrent readers and two drained registries')
}
