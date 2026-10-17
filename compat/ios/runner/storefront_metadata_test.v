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
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type SMProbe = fn (u64, u64, u64, u64, u64, &u64)
type SMAccess = fn (u64) SwiftAssociatedMetadata
type SMAllocate = fn (u64, u64, u64) u64
type SMBox = fn (u64) SwiftArrayAllocation
type SMDeallocate = fn (u64, u64, u64)
type SMRelease = fn (u64)
type SMSign = fn (u64, u64) u64
type SMLookup = fn (u64, u64, u64, u64) u64
type SMConstruct = fn (u64, u64, u64, u64)
type SMString = fn (&u8) SwiftStringWords
struct SMApi {
	native bool
	access u64
	metadata u64
	descriptor u64
	probe SMProbe
	allocate SMAllocate
	deallocate SMDeallocate
	release SMRelease
	lookup SMLookup
}
struct SMOwner {
	api SMApi
	observer u64
	index int
mut:
	calls int
}
struct SMScene {
	api SMApi
	source u64
	destination u64
	copying bool
mut:
	old [6]u64
	calls int
}
fn sm_entries(native bool) [2]u64 {
	mut entries := [2]u64{}
	for i, symbol in ['_$s8StoreKit10StorefrontVMa', '_$s8StoreKit10StorefrontVMn']! {
		if native { entries[i] = u64(C.dlsym(C.dlopen(c'/System/Library/Frameworks/StoreKit.framework/StoreKit', 2), symbol[1..].str)) }
		else { entries[i] = runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', symbol) or { panic(err) } }
		assert entries[i] != 0
	}
	return entries
}
fn sm_publish() [2]u64 {
	entries := sm_entries(false)
	for _ in 0 .. 64 { assert sm_entries(false) == entries }
	return entries
}
fn sm_api(native bool, code u64) SMApi {
	entries := sm_entries(native)
	mut functions := [4]u64{}
	for i, symbol in ['_swift_allocObject', '_swift_deallocClassInstance', '_swift_release', '_swift_getTypeByMangledNameInContext']! {
		if native { functions[i] = u64(C.dlsym(C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2), symbol[1..].str)) }
		else { functions[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) } }
		assert functions[i] != 0
	}
	response := unsafe { SMAccess(voidptr(entries[0]))(0) }
	assert response.state == 0
	return SMApi{native: native, access: entries[0], metadata: response.metadata, descriptor: entries[1],
		probe: unsafe { SMProbe(voidptr(code)) }, allocate: unsafe { SMAllocate(voidptr(functions[0])) },
		deallocate: unsafe { SMDeallocate(voidptr(functions[1])) }, release: unsafe { SMRelease(voidptr(functions[2])) },
		lookup: unsafe { SMLookup(voidptr(functions[3])) }}
}
fn (api SMApi) call(entry u64, a u64, b u64, c u64, d u64) u64 {
	mut result := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(entry, a, b, c, d, unsafe { &result[1] })
	assert result[0] == 0xcafe && result[3] == 0x5020 && result[4] == 0x5021 && result[5] == 0xbeef
	return result[1]
}
fn (api SMApi) witness(slot int) u64 {
	return read64((read64(api.metadata - 8) & 0x0000ffffffffffff) + u64(slot * 8)) & 0x0000ffffffffffff
}
fn (api SMApi) value(slot int, a u64, b u64) u64 { return api.call(api.witness(slot), a, b, api.metadata, 0) }
fn (api SMApi) refs(owner u64, cocoa bool) u64 {
	if !cocoa { return 1 + (read64(owner + 8) >> 33) }
	$if macos { if api.native { return u64(C.CFGetRetainCount(voidptr(owner))) } }
	return u64(obj_header(owner).refs)
}
fn sm_reenter(api SMApi) {
	assert unsafe { SMAccess(voidptr(api.access))(0) } == SwiftAssociatedMetadata{metadata: api.metadata}
	if !api.native { assert sm_entries(false) == [api.access, api.descriptor]! }
}
fn sm_owner_destroy(owner u64) {
	mut state := unsafe { &SMOwner(read64(owner + 16)) }
	assert state.calls == 0
	state.calls++
	if state.observer != 0 {
		mut scene := unsafe { &SMScene(state.observer) }
		assert scene.calls == state.index
		scene.calls++
		for i in 0 .. 6 {
			published := scene.copying && (i < (state.index + 1) * 2) && i != 5
			assert read64(scene.destination + u64(i * 8)) == if published { read64(scene.source + u64(i * 8)) } else { scene.old[i] }
		}
		for i, offset in [u64(8), 24, 32]! {
			assert scene.api.refs(read64(scene.source + offset), false) == if !scene.copying || (i <= state.index && i < 2) { u64(2) } else { u64(1) }
		}
		worker := spawn sm_reenter(scene.api)
		worker.wait()
	}
	state.api.deallocate(owner, 32, 15)
}
fn sm_owner(api SMApi, metadata u64, state u64, cocoa bool) u64 {
	if cocoa {
		$if macos { if api.native { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
		return owned_string('Storefront Cocoa owner')
	}
	owner := api.allocate(metadata, 32, 15)
	unsafe { *(&u64(owner + 16)) = state }
	return owner
}
fn sm_ownership(api SMApi, owner_metadata u64, cocoa bool) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_NONE) == 0 && C.mprotect(voidptr(region + u64(page * 3)), page, C.PROT_NONE) == 0
	source := region + u64(page) - 48
	destination := region + u64(page * 3) - 56
	mut states := [3]SMOwner{}
	for i, offset in [u64(8), 24, 32]! {
		states[i] = SMOwner{api: api}
		owner := sm_owner(api, owner_metadata, u64(unsafe { &states[i] }), cocoa)
		unsafe { *(&u64(source + offset)) = owner | if cocoa && i < 2 { u64(0x4000000000000000) } else { u64(0) } }
	}
	unsafe { *(&u64(source)) = 0xc01; *(&u64(source + 16)) = 0x1d; *(&u64(source + 40)) = 0x12345678; *(&u64(destination + 48)) = 0xbeef }
	assert C.mprotect(voidptr(region), page, C.PROT_READ) == 0
	for slot in [2, 4, 3, 5]! {
		mut previous := [3]SMOwner{}
		mut scene := SMScene{api: api, source: source, destination: destination, copying: slot == 3}
		if slot == 3 || slot == 5 {
			unsafe { *(&u64(destination)) = 0xd01; *(&u64(destination + 16)) = 0xd1d; *(&u64(destination + 40)) = 0xfeedface }
			for i, offset in [u64(8), 24, 32]! {
				previous[i] = SMOwner{api: api, index: i, observer: if cocoa {u64(0)} else {u64(unsafe { &scene })}}
				unsafe { *(&u64(destination + offset)) = sm_owner(api, owner_metadata, u64(&previous[i]), false) }
			}
			for i in 0 .. 6 { scene.old[i] = read64(destination + u64(i * 8)) }
		}
		// Takes consume an extra ownership claim, preserving the read-only source.
		if slot == 4 || slot == 5 { api.value(2, destination + 0 - 64, source) }
		assert api.value(slot, destination, source) == destination
		assert C.memcmp(voidptr(destination), voidptr(source), 48) == 0 && read64(destination + 48) == 0xbeef
		for offset in [u64(8), 24, 32]! { assert api.refs(read64(source + offset) & 0x0fffffffffffffff, cocoa) == 2 }
		if slot == 3 || slot == 5 { for state in previous { assert state.calls == 1 }; if !cocoa { assert scene.calls == 3 } }
		api.call(api.witness(1), destination, api.metadata, 0, 0)
		for offset in [u64(8), 24, 32]! { assert api.refs(read64(source + offset) & 0x0fffffffffffffff, cocoa) == 1 }
	}
	assert api.call(api.witness(6), source, 1, api.metadata, 0) == 0
	api.call(api.witness(1), source, api.metadata, 0, 0)
	if !cocoa { for state in states { assert state.calls == 1 } }
	assert C.munmap(voidptr(region), page * 4) == 0
}

fn sm_enums(api SMApi) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(voidptr(region), page, C.PROT_NONE) == 0 && C.mprotect(voidptr(region + u64(page * 2)), page, C.PROT_NONE) == 0
	guard := region + u64(page * 2)
	// Apple's generic resilient wrapper still reads the payload for zero
	// empty cases. Only the runner's no-access fast path accepts this guard.
	if !api.native {
		assert api.call(api.witness(6), guard, 0, api.metadata, 0) == 0
		api.call(api.witness(7), guard, 0, 0, api.metadata)
	}
	for count in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
		for tag in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
			if tag > count { continue }
			length := if count > 0x7fffffff { 49 } else { 48 }
			for at_start in [false, true]! {
				value := if at_start { region + u64(page) } else { guard - u64(length) }
				C.memset(voidptr(value), 0xa5, usize(length))
				api.call(api.witness(7), value, tag, count, api.metadata)
				assert api.call(api.witness(6), value, count, api.metadata, 0) == tag
				mut expected := [49]u8{}
				for i in 0 .. length { expected[i] = 0xa5 }
				if count > 0x7fffffff { expected[48] = if tag > 0x7fffffff { 1 } else { 0 } }
				if tag > 0x7fffffff {
					for i in 0 .. 48 { expected[i] = if i < 4 { u8((tag - u32(0x80000000)) >> u32(i * 8)) } else { u8(0) } }
				} else if tag != 0 { for i in 0 .. 8 { expected[i + 8] = u8(u64(tag - 1) >> u32(i * 8)) } }
				for i in 0 .. length { assert unsafe { *(&u8(value + u64(i))) } == expected[i] }
				mut bytes := [64]u8{}
				for i in 0 .. 64 { bytes[i] = 0xa5 }
				unaligned := u64(unsafe { &bytes[5] })
				api.call(api.witness(7), unaligned, tag, count, api.metadata)
				assert api.call(api.witness(6), unaligned, count, api.metadata, 0) == tag
				for i in 0 .. 64 { assert bytes[i] == if i >= 5 && i < 5 + length { expected[i - 5] } else { u8(0xa5) } }
			}
		}
	}
	assert C.munmap(voidptr(region), page * 3) == 0
}

fn sm_box(api SMApi, owner_metadata u64) {
	mut box := SwiftArrayAllocation{}
	$if macos { if api.native { box = unsafe { SMBox(C.dlsym(C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2), c'swift_allocBox'))(api.metadata) } } }
	if !api.native { owner := storefront_box_allocate(); box = SwiftArrayAllocation{owner: owner, bytes: owner + 16} }
	assert box.bytes == box.owner + 16 && read64(box.owner + 8) == 3
	mut states := [3]SMOwner{}
	C.memset(voidptr(box.bytes), 0, 48)
	for i, offset in [u64(8), 24, 32]! {
		states[i] = SMOwner{api: api}
		unsafe { *(&u64(box.bytes + offset)) = sm_owner(api, owner_metadata, u64(&states[i]), false) }
	}
	mut src := [box.owner, u64(0xa5), 0xa5]!
	mut dst := [u64(0xb5), 0xb5, 0xb5]!
	assert api.value(0, u64(unsafe { &dst[0] }), u64(unsafe { &src[0] })) == box.bytes
	assert dst == [box.owner, u64(0xb5), 0xb5]! && read64(box.owner + 8) == 0x200000003
	api.release(dst[0])
	assert read64(box.owner + 8) == 3
	if !api.native {
		mut any_src := [box.owner, u64(0xa5), 0xa5, api.metadata]!
		mut any_dst := [u64(0xb5), 0xb5, 0xb5, 0xb5]!
		swift_any_copy_checked(u64(unsafe { &any_dst[0] }), u64(unsafe { &any_src[0] })) or { panic(err) }
		assert any_dst == [box.owner, u64(0xb5), 0xb5, api.metadata]!
		swift_any_destroy_checked(u64(unsafe { &any_dst[0] })) or { panic(err) }
		mut forged := [u64(8), 0, 0]!
		if _ := storefront_buffer_copy_checked(u64(unsafe { &dst[0] }), u64(unsafe { &forged[0] }), api.metadata) { assert false }
		assert dst == [box.owner, u64(0xb5), 0xb5]!
	}
	api.release(box.owner)
	for state in states { assert state.calls == 1 }
}

fn sm_code(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0503f3, 0xaa0103e0,
		0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	write32(code + 128, 0xaa1403e0); write32(code + 132, 0x58000070); write32(code + 136, 0xd61f0200)
	unsafe { *(&u64(code + 144)) = u64(voidptr(sm_owner_destroy)) }
	write32(code + 160, 0xdac10020); write32(code + 164, 0xd65f03c0)
	for i, op in [u32(0xaa0003f0), 0xaa0103e0, 0xaa0203e1, 0xaa0303e8, 0xd61f0200]! { write32(code + 192 + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 212))
}
fn sm_constructed(api SMApi, code u64) {
	// Exercise an actual native/runner String and Locale, as well as the
	// instrumented heap/Cocoa owners used to observe each field's ARC above.
	mut country := SwiftStringWords{}
	mut entry := u64(0)
	if api.native {
		country = unsafe { SMString(C.dlsym(C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2), c'$sSS7cStringSSSPys4Int8VG_tcfC'))(c'Owned Storefront country storage') }
		entry = u64(C.dlsym(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2), c'$s10Foundation6LocaleV10identifierACSS_tcfC'))
	} else {
		text := 'Owned Storefront country storage'
		builder := u64(C.__builtin_alloca(16))
		unsafe { *(&SwiftStringWords(builder)) = swift_interpolation_init(128, 0) }
		swift_string_append_bytes(builder, u64(text.str), u64(text.len))
		country = unsafe { *(&SwiftStringWords(builder)) }
		entry = swift_foundation_symbol('_$s10Foundation6LocaleV10identifierACSS_tcfC') or { panic('missing Locale initializer') }
	}
	identifier := swift_string_literal(c'en_GB', 5, true)
	id := swift_string_literal(c'123456', 6, true)
	mut source := [country.first, country.second, id.first, id.second, u64(0), 0]!
	mut destination := [6]u64{}
	construct := unsafe { SMConstruct(voidptr(code + 192)) }
	construct(entry, identifier.first, identifier.second, u64(unsafe { &source[4] }))
	assert source[4] != 0 && source[5] != 0
	src := u64(unsafe { &source[0] }); dst := u64(unsafe { &destination[0] })
	assert api.value(2, dst, src) == dst && destination == source
	assert api.call(api.witness(6), src, 1, api.metadata, 0) == 0
	api.call(api.witness(1), src, api.metadata, 0, 0)
	assert api.call(api.witness(6), dst, 1, api.metadata, 0) == 0
	api.call(api.witness(1), dst, api.metadata, 0, 0)
}
fn sm_worker(api SMApi, metadata u64) { for _ in 0 .. 4 { sm_reenter(api); sm_ownership(api, metadata, false); sm_box(api, metadata) } }
fn sm_suite(api SMApi, code u64) {
	for request in [u64(0), 0xff, 0x100, 0x1ff, u64(-1)]! {
		mut response := [4]u64{}
		api.probe(api.access, request, 0, 0, 0, unsafe { &response[0] })
		assert response == [api.metadata, u64(0), 0x5020, 0x5021]!
	}
	assert read64(api.metadata) == 0x200 && read64(api.metadata + 8) & 0x0000ffffffffffff == api.descriptor
	for i, offset in [u32(0), 16, 32]! { assert read32(api.metadata + 16 + u64(i * 4)) == offset }
	assert read32(api.descriptor) & 0xffff == 0x51 && read32(api.descriptor + 20) == 3 && read32(api.descriptor + 24) == 2
	assert ctext(u64(i64(api.descriptor + 8) + i64(i32(read32(api.descriptor + 8))))) == 'Storefront'
	parent := u64(i64(api.descriptor + 4) + i64(i32(read32(api.descriptor + 4))))
	assert ctext(u64(i64(parent + 8) + i64(i32(read32(parent + 8))))) == 'StoreKit'
	witness := read64(api.metadata - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 48 && read64(witness + 72) == 48 && read32(witness + 80) == 0x30007 && read32(witness + 84) == 0x7fffffff
	mut name := [3]u64{}
	base := u64(unsafe { &name[0] })
	unsafe { *(&u8(base)) = 2; *(&u64(base + 16)) = api.descriptor }
	for i in 0 .. 4 { unsafe { *(&u8(base + 1 + u64(i))) = u8(u32(15) >> u32(i * 8)) } }
	assert api.lookup(base, 5, 0, 0) == api.metadata
	page := usize(C.getpagesize())
	words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert words != u64(-1)
	metadata := words + 24
	mut destroyer := code + 128
	$if macos { if api.native { destroyer = unsafe { SMSign(voidptr(code + 160))(destroyer, (metadata - 16) | (u64(0xbbbf) << 48)) } } }
	unsafe { *(&u64(metadata - 16)) = destroyer; *(&u64(metadata + 32)) = 2; *(&u64(metadata + 40)) = 2; *(&u64(metadata + 48)) = 0xf00000020; *(&u64(metadata + 64)) = words + 128 }
	assert C.mprotect(voidptr(words), page, C.PROT_READ) == 0
	for cocoa in [false, true]! { sm_ownership(api, metadata, cocoa) }
	sm_box(api, metadata)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn sm_worker(api, metadata) }
	workers.wait()
	sm_enums(api)
	sm_constructed(api, code)
	assert C.munmap(voidptr(words), page) == 0
}

fn sm_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 8 <= start + size && info[0] == (C.PROT_READ | if executable {
				C.PROT_EXEC
			} else {
				0
			})
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
				assert mapped && fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
				break
			}
		}
		assert found == mapped
	}
}

fn test_storefront_metadata() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	sm_code(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos { sm_suite(sm_api(true, code), code); println('IOS-STOREFRONT-METADATA-NATIVE: measured complete accessor, nominal identity, 48-byte layout, eight witnesses, reentrant field ownership, shared value buffers and guarded enum boundaries') }
	for symbol in ['_$s8StoreKit10StorefrontVMa', '_$s8StoreKit10StorefrontVMn']! { if _ := storefront_symbol(symbol) { assert false } }
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread [2]u64{}
		for _ in 0 .. 8 { workers << spawn sm_publish() }
		entries := workers.wait()
		for pair in entries { assert pair == entries[0] }
		api := sm_api(false, code)
		assert api.access == ios_runtime.storefront_code + 64 && api.metadata == ios_runtime.storefront_code + u64(page) + 32
		sm_mapping(api.access, true, true)
		sm_mapping(api.metadata, true, false)
		sm_suite(api, code)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		for library in ['/usr/lib/swift/libswiftCore.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit']! {
			for symbol in ['_$s8StoreKit10StorefrontVMa', '_$s8StoreKit10StorefrontVMn']! { if _ := runtime_symbol(library, symbol) { assert false } }
		}
		objc_stop()
		assert ios_runtime.storefront_code == 0 && ios_runtime.storefront_retired
		sm_mapping(api.access, false, false)
		sm_mapping(api.metadata, false, false)
		for symbol in ['_$s8StoreKit10StorefrontVMa', '_$s8StoreKit10StorefrontVMn']! { if _ := storefront_symbol(symbol) { assert false } }
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-STOREFRONT-METADATA: canonical StoreKit metadata/nominal descriptor, native 48-byte witnesses, Swift/Cocoa ARC, reentrant copy/take ordering, shared boxes/Any, guarded enum writes, concurrent publication and drained runtime lifetimes')
}
