// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <mach/mach.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type StorefrontProbe = fn (u64, u64, u64, &u64)
type StorefrontLiteral = fn (&u8, i64, bool) SwiftStringWords
type StorefrontCString = fn (&u8) SwiftStringWords
type StorefrontRelease = fn (u64)
type StorefrontBytes = fn (u64, u64) u64
struct StorefrontApi {
	native bool
	entry u64
	probe StorefrontProbe
	literal StorefrontLiteral
	owned StorefrontCString
	release StorefrontRelease
	buffer_release StorefrontRelease
	bytes StorefrontBytes
}

fn storefront_owned(text &u8) SwiftStringWords {
	source := owned_string(unsafe { text.vstring() })
	words := swift_foundation_unbridge(source)
	objc_release(source)
	return words
}

fn storefront_result(api StorefrontApi, source u64, guard u64) SwiftStringWords {
	mut output := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(api.entry, source, guard, unsafe { &output[1] })
	assert output[0] == 0xcafe && output[5] == 0xbeef
	assert output[3] == source && output[4] == 0x5021
	assert read64(source) == output[1] && read64(source + 8) == output[2]
	return SwiftStringWords{first: output[1], second: output[2]}
}

fn storefront_text(api StorefrontApi, words SwiftStringWords, expected string) {
	buffer := api.bytes(words.first, words.second)
	assert read64(buffer + 16) == u64(expected.len + 1)
	assert C.memcmp(voidptr(buffer + 32), expected.str, usize(expected.len)) == 0
	api.buffer_release(buffer)
}

fn storefront_worker(api StorefrontApi, source u64, guard u64) {
	for _ in 0 .. 256 {
		words := storefront_result(api, source, guard)
		api.release(words.second)
	}
}

fn storefront_cases(api StorefrontApi, guard u64, page u64) {
	// Only the country field is readable. x0..x8 point at PROT_NONE, and Self
	// is read-only at both edges of a page, including an 8-byte-aligned address.
	for address in [guard + page, guard + page + 8, guard + page * 2 - 16]! {
		for text in ['', 'USA', 'GBR', 'é🎮', '123456789012345',
			'immortal String longer than fifteen bytes', 'literal with\x00embedded NUL']! {
			words := api.literal(text.str, text.len, text.is_ascii())
			assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
			C.memcpy(voidptr(address), unsafe { &words }, 16)
			assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ) == 0
			result := storefront_result(api, address, guard)
			storefront_text(api, result, text)
			api.release(result.second)
			api.release(words.second)
		}
	}
	text := 'Owned country field storage exercises native Swift ARC π 🎮'
	words := api.owned(text.str)
	assert words.second & u64(0xf000000000000000) == 0
	owner := words.second
	refs := read64(owner + 8)
	address := guard + page * 2 - 16
	assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	C.memcpy(voidptr(address), unsafe { &words }, 16)
	assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ) == 0
	first := storefront_result(api, address, guard)
	assert read64(owner + 8) == refs + swift_strong_step
	second := storefront_result(api, address, guard)
	assert read64(owner + 8) == refs + swift_strong_step * 2
	api.release(first.second)
	assert read64(owner + 8) == refs + swift_strong_step
	api.release(words.second) // A returned String must survive its Storefront.
	assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	C.memset(voidptr(address), 0, 16)
	storefront_text(api, second, text)
	api.release(second.second)

	shared := api.owned(text.str)
	C.memcpy(voidptr(address), unsafe { &shared }, 16)
	assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ) == 0
	shared_refs := read64(shared.second + 8)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn storefront_worker(api, address, guard) }
	workers.wait()
	unsafe { workers.free() }
	assert read64(shared.second + 8) == shared_refs
	api.release(shared.second)

	// A Cocoa-backed String retains its NSString, preserving discriminator bits.
	mut cocoa := u64(0)
	if api.native {
		$if macos { cocoa = u64(C.CFStringCreateWithBytes(unsafe { nil }, text.str, text.len, 0x08000100, false)) }
	} else { cocoa = owned_string(text) }
	assert cocoa != 0
	foreign := SwiftStringWords{first: u64(text.len), second: cocoa | u64(0x4000000000000000)}
	mut cocoa_refs := i64(0)
	if api.native { $if macos { cocoa_refs = C.CFGetRetainCount(voidptr(cocoa)) } }
	else { cocoa_refs = obj_header(cocoa).refs }
	assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	C.memcpy(voidptr(address), unsafe { &foreign }, 16)
	assert C.mprotect(voidptr(guard + page), usize(page), C.PROT_READ) == 0
	result := storefront_result(api, address, guard)
	if api.native { $if macos { assert C.CFGetRetainCount(voidptr(cocoa)) == cocoa_refs + 1; C.CFRelease(voidptr(cocoa)) } }
	else { assert obj_header(cocoa).refs == cocoa_refs + 1; objc_release(cocoa); assert string_text(cocoa) == text }
	api.release(result.second)
}

fn storefront_publish() u64 {
	return runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', '_$s8StoreKit10StorefrontV11countryCodeSSvg') or { panic(err) }
}

fn storefront_mapping(address u64, mapped bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped { assert status == 0 && start <= address && address + 24 <= start + size && info[0] == (C.PROT_READ | C.PROT_EXEC) }
		else { assert status != 0 || start > address }
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if start <= address && address < end { assert mapped && fields[1] == 'r-xp'; found = true }
		}
		assert found == mapped
	}
}

fn test_storefront_country_code() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	// C arguments: entry, borrowed Self, inaccessible unused args, guarded output.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103f4, 0xaa0303f3,
		0xaa0203e0, 0xaa0203e1, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5, 0xaa0203e6, 0xaa0203e7,
		0xaa0203e8, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 88))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { StorefrontProbe(voidptr(code)) }
	$if macos {
		store := C.dlopen(c'/System/Library/Frameworks/StoreKit.framework/StoreKit', 2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert store != unsafe { nil } && core != unsafe { nil }
		api := StorefrontApi{native: true,
			entry: u64(C.dlsym(store, c'$s8StoreKit10StorefrontV11countryCodeSSvg')), probe: probe,
			literal: unsafe { StorefrontLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) },
			owned: unsafe { StorefrontCString(C.dlsym(core, c'$sSS7cStringSSSPys4Int8VG_tcfC')) },
			release: unsafe { StorefrontRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) },
			buffer_release: unsafe { StorefrontRelease(C.dlsym(core, c'swift_release')) },
			bytes: unsafe { StorefrontBytes(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }}
		assert api.entry != 0 && voidptr(api.literal) != unsafe { nil } && voidptr(api.owned) != unsafe { nil } && voidptr(api.bytes) != unsafe { nil }
		storefront_cases(api, guard, u64(page))
		println('IOS-STOREFRONT-NATIVE: borrowed x20 Self at offset zero, owned x0/x1 String, read-only guarded fields, preserved x20/x21, small/immortal/native/Cocoa owners and concurrent ARC')
	}
	if _ := storefront_symbol('_$s8StoreKit10StorefrontV11countryCodeSSvg') { assert false }
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn storefront_publish() }
		entries := publishers.wait()
		entry := entries[0]
		for candidate in entries { assert candidate == entry }
		unsafe { publishers.free(); entries.free() }
		storefront_mapping(entry, true)
		storefront_cases(StorefrontApi{entry: entry, probe: probe, literal: swift_string_literal,
			owned: storefront_owned, release: swift_bridge_release, buffer_release: swift_release,
			bytes: swift_string_utf8_cstring}, guard, u64(page))
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation',
			'/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/swift/libswiftCore.dylib', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_$s8StoreKit10StorefrontV11countryCodeSSvg') { assert false }
		}
		for unsupported in ['_$s8StoreKit10StorefrontVMa', '_$s8StoreKit10StorefrontVMn',
			'_$s8StoreKit10StorefrontV2idSSvg', '$s8StoreKit10StorefrontV11countryCodeSSvg']! {
			if _ := storefront_symbol(unsupported) { assert false }
		}
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		assert ios_runtime.storefront_code == 0 && ios_runtime.storefront_retired
		storefront_mapping(entry, false)
		if _ := storefront_symbol('_$s8StoreKit10StorefrontV11countryCodeSSvg') { assert false }
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page * 3) == 0
	println('IOS-STOREFRONT: scoped Swift country getter, guarded field/register ABI, owned String survival, exact ARC for native/Cocoa owners, concurrent calls/publication and two sealed/unmapped runtimes')
}
