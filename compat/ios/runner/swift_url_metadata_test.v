// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type URLMetaProbe = fn (u64, u64, u64, u64, u64, &u64)
type URLMetaAccess = fn (u64) SwiftAssociatedMetadata
type URLMetaCopy = fn (u64, u64, u64) u64
type URLMetaDestroy = fn (u64, u64)
type URLMetaGet = fn (u64, u32, u64) u32
type URLMetaStore = fn (u64, u32, u32, u64)
type URLMetaAllocate = fn (u64, u64, u64) u64
type URLMetaDeallocate = fn (u64, u64, u64)
type URLMetaRetain = fn (u64) u64
type URLMetaRelease = fn (u64)
type URLMetaSend = fn (u64, u64) u64
type URLMetaSign = fn (u64, u64) u64
type URLMetaLookup = fn (u64, u64, u64, u64) u64

struct URLMetaApi {
	native     bool
	access     u64
	metadata   u64
	descriptor u64
	probe      URLMetaProbe
	allocate   URLMetaAllocate
	deallocate URLMetaDeallocate
	retain     URLMetaRetain
	release    URLMetaRelease
	lookup     URLMetaLookup
}

struct URLMetaOwner {
	api      URLMetaApi
	metadata u64
mut:
	owner        u64
	destination  u64
	source       u64
	source_owner u64
	source_heap  bool
	source_refs  u64
	copy_assign  bool
	reenter      bool
	calls        int
}

fn url_meta_entries(native bool, overlay bool) [2]u64 {
	library := if overlay {
		'/usr/lib/swift/libswiftFoundation.dylib'
	} else {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	}
	mut entries := [2]u64{}
	for i, name in ['_$s10Foundation3URLVMa', '_$s10Foundation3URLVMn']! {
		if native {
			handle := C.dlopen(library.str, 2)
			entries[i] = u64(C.dlsym(handle, name[1..].str))
		} else {
			entries[i] = runtime_symbol(library, name) or { panic(err) }
		}
		assert entries[i] != 0
	}
	return entries
}

fn url_meta_publish(overlay bool) [2]u64 {
	entries := url_meta_entries(false, overlay)
	for _ in 0 .. 128 {
		assert url_meta_entries(false, overlay) == entries
	}
	return entries
}

fn url_meta_api(native bool, code u64) URLMetaApi {
	entries := url_meta_entries(native, false)
	assert url_meta_entries(native, true) == entries
	mut functions := [5]u64{}
	for i, name in ['_swift_allocObject', '_swift_deallocClassInstance', '_swift_unknownObjectRetain',
		'_swift_unknownObjectRelease', '_swift_getTypeByMangledNameInContext']! {
		if native {
			handle := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			functions[i] = u64(C.dlsym(handle, name[1..].str))
		} else {
			functions[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
		}
		assert functions[i] != 0
	}
	response := unsafe { URLMetaAccess(voidptr(entries[0]))(0) }
	assert response.state == 0
	return URLMetaApi{
		native:     native
		access:     entries[0]
		metadata:   response.metadata
		descriptor: entries[1]
		probe:      unsafe { URLMetaProbe(voidptr(code)) }
		allocate:   unsafe { URLMetaAllocate(voidptr(functions[0])) }
		deallocate: unsafe { URLMetaDeallocate(voidptr(functions[1])) }
		retain:     unsafe { URLMetaRetain(voidptr(functions[2])) }
		release:    unsafe { URLMetaRelease(voidptr(functions[3])) }
		lookup:     unsafe { URLMetaLookup(voidptr(functions[4])) }
	}
}

fn (api URLMetaApi) call(entry u64, a u64, b u64, c u64, d u64) [2]u64 {
	mut result := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(entry, a, b, c, d, unsafe { &result[1] })
	assert result[0] == 0xcafe && result[3] == 0x5020 && result[4] == 0x5021 && result[5] == 0xbeef
	return [result[1], result[2]]!
}

fn (api URLMetaApi) witness(slot int) u64 {
	return read64((read64(api.metadata - 8) & 0x0000ffffffffffff) + u64(slot * 8)) & 0x0000ffffffffffff
}

fn url_meta_send(owner u64, name &char) u64 {
	return unsafe { URLMetaSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(owner, u64(C.sel_registerName(name))) }
}

fn (api URLMetaApi) refs(owner u64, heap bool) u64 {
	if heap { return 1 + (read64(owner + 8) >> 33) }
	$if macos {
		if api.native { return url_meta_send(owner, c'retainCount') }
	}
	return u64(obj_header(owner).refs)
}

fn url_meta_reentry(api URLMetaApi) {
	if !api.native {
		assert url_meta_entries(false, true) == [api.access, api.descriptor]!
	}
	assert unsafe { URLMetaAccess(voidptr(api.access))(0) } == SwiftAssociatedMetadata{ metadata: api.metadata }
}

fn url_meta_owner_destroy(owner u64) {
	mut state := unsafe { &URLMetaOwner(read64(owner + 16)) }
	assert state.owner == owner && state.calls == 0 && read64(owner + 8) == 0x100000003
	state.calls++
	if state.destination != 0 {
		// Copy publishes the owner before release, acquires it after release,
		// then publishes the table. Take leaves both old words until release.
		assert read64(state.destination) == if state.copy_assign {
			state.source_owner
		} else {
			owner
		}
		assert read64(state.destination + 8) == 0xfeedface
		assert read64(state.source) == state.source_owner && read64(state.source + 8) == 0x12345678
		assert state.api.refs(state.source_owner, state.source_heap) == state.source_refs
	}
	if state.reenter {
		worker := spawn url_meta_reentry(state.api)
		worker.wait()
	}
	state.api.deallocate(owner, 32, 15)
}

fn url_meta_owner(api URLMetaApi, heap bool, metadata u64, mut state URLMetaOwner) u64 {
	if heap {
		owner := api.allocate(metadata, 32, 15)
		state.owner = owner
		unsafe { *(&u64(owner + 16)) = u64(&state) }
		return owner
	}
	$if macos {
		if api.native { return url_meta_send(u64(C.objc_getClass(c'NSObject')), c'new') }
	}
	return objc_allocate(ios_runtime.names['NSObject'])
}

fn url_meta_code(code u64) {
	// Ordinary C calls, with guarded return words and live x20/x21 sentinels.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0503f3, 0xaa0103e0,
		0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! { write32(code + 128 + u64(i * 4), op) }
	unsafe { *(&u64(code + 144)) = u64(voidptr(url_meta_owner_destroy)) }
	write32(code + 160, 0xdac10020)
	write32(code + 164, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 168))
}

fn url_meta_ownership(api URLMetaApi, owner_metadata u64, heap bool, reenter bool) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_NONE) == 0 && C.mprotect(voidptr(region + u64(page * 3)), page, C.PROT_NONE) == 0
	source := region + u64(page) - 16
	destination := region + u64(page * 3) - 24
	mut state := URLMetaOwner{ api: api, metadata: owner_metadata }
	owner := url_meta_owner(api, heap, owner_metadata, mut state)
	unsafe {
		*(&u64(source)) = owner
		*(&u64(source + 8)) = 0x12345678
		*(&u64(destination + 16)) = 0xbeef
	}
	assert C.mprotect(voidptr(region), page, C.PROT_READ) == 0
	for slot in [0, 2]! {
		result := api.call(api.witness(slot), destination, source, api.metadata, 0)
		assert result[0] == destination && read64(destination) == owner && read64(destination + 8) == 0x12345678
		assert api.refs(owner, heap) == 2
		api.call(api.witness(1), destination, api.metadata, 0, 0)
		assert api.refs(owner, heap) == 1 && read64(destination) == owner && read64(destination + 8) == 0x12345678
	}
	assert api.call(api.witness(6), source, 1, api.metadata, 0)[0] == 0
	for slot in [3, 5]! {
		if slot == 5 {
			assert api.retain(owner) == owner
		}
		mut old_state := URLMetaOwner{
			api:          api
			metadata:     owner_metadata
			destination:  destination
			source:       source
			source_owner: owner
			source_heap:  heap
			source_refs:  if slot == 5 { u64(2) } else { u64(1) }
			copy_assign:  slot == 3
			reenter:      reenter
		}
		previous := url_meta_owner(api, true, owner_metadata, mut old_state)
		unsafe {
			*(&u64(destination)) = previous
			*(&u64(destination + 8)) = 0xfeedface
		}
		assert api.call(api.witness(slot), destination, source, api.metadata, 0)[0] == destination
		assert old_state.calls == 1 && read64(destination) == owner && read64(destination + 8) == 0x12345678
		assert api.refs(owner, heap) == 2
		api.call(api.witness(1), destination, api.metadata, 0, 0)
		assert api.refs(owner, heap) == 1
	}
	api.retain(owner)
	assert api.call(api.witness(4), destination, source, api.metadata, 0)[0] == destination
	assert api.refs(owner, heap) == 2 && read64(source) == owner && read64(source + 8) == 0x12345678
	api.call(api.witness(1), destination, api.metadata, 0, 0)
	assert api.refs(owner, heap) == 1 && read64(destination + 16) == 0xbeef
	api.call(api.witness(1), source, api.metadata, 0, 0)
	if heap {
		assert state.calls == 1
	}
	assert C.munmap(voidptr(region), page * 4) == 0
}

fn url_meta_enums(api URLMetaApi) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(voidptr(region), page, C.PROT_NONE) == 0 && C.mprotect(voidptr(region + u64(page * 2)), page, C.PROT_NONE) == 0
	guard := region + u64(page * 2)
	assert api.call(api.witness(6), guard, 0, guard, 0)[0] == 0
	api.call(api.witness(7), guard, 0, 0, guard)
	for count in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
		for tag in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
			if tag > count { continue }
			length := if count > 0x7fffffff { 17 } else { 16 }
			for at_start in [false, true]! {
				value := if at_start { region + u64(page) } else { guard - u64(length) }
				C.memset(voidptr(value), 0xa5, usize(length))
				api.call(api.witness(7), value, tag, count, api.metadata)
				assert api.call(api.witness(6), value, count, api.metadata, 0)[0] == tag
				mut expected := [17]u8{}
				for i in 0 .. length { expected[i] = 0xa5 }
				if count > 0x7fffffff { expected[16] = if tag > 0x7fffffff { 1 } else { 0 } }
				if tag != 0 {
					owner := if tag <= 0x7fffffff { u64(tag - 1) } else { u64(tag - 0x80000000) }
					for i in 0 .. 8 { expected[i] = u8(owner >> u32(i * 8)) }
					if tag > 0x7fffffff {
						for i in 8 .. 16 { expected[i] = 0 }
					}
				}
				for i in 0 .. length {
					assert unsafe { *(&u8(value + u64(i))) } == expected[i]
				}
				// Also compare an unaligned span with canaries on both sides.
				mut bytes := [32]u8{}
				for i in 0 .. 32 { bytes[i] = 0xa5 }
				unaligned := u64(unsafe { &bytes[5] })
				api.call(api.witness(7), unaligned, tag, count, api.metadata)
				assert api.call(api.witness(6), unaligned, count, api.metadata, 0)[0] == tag
				for i in 0 .. 32 {
					assert bytes[i] == if i >= 5 && i < 5 + length {
						expected[i - 5]
					} else {
						u8(0xa5)
					}
				}
			}
		}
	}
	assert C.munmap(voidptr(region), page * 3) == 0
}

fn url_meta_worker(api URLMetaApi, owner_metadata u64) {
	for _ in 0 .. 4 {
		url_meta_reentry(api)
		for heap in [false, true]! { url_meta_ownership(api, owner_metadata, heap, false) }
	}
}

fn url_meta_suite(api URLMetaApi, code u64) {
	for request in [u64(0), 0xff, 0x100, 0x1ff, u64(-1)]! {
		assert api.call(api.access, request, 0, 0, 0) == [api.metadata, u64(0)]!
	}
	assert read64(api.metadata) == 0x200 && read64(api.metadata + 8) & 0x0000ffffffffffff == api.descriptor
	assert read32(api.metadata + 16) == 0 && read32(api.descriptor) & 0xffff == 0x51
	assert read32(api.descriptor + 20) == 1 && read32(api.descriptor + 24) == 2
	assert ctext(u64(i64(api.descriptor + 8) + i64(i32(read32(api.descriptor + 8))))) == 'URL'
	module_descriptor := u64(i64(api.descriptor + 4) + i64(i32(read32(api.descriptor + 4))))
	assert ctext(u64(i64(module_descriptor + 8) + i64(i32(read32(module_descriptor + 8))))) == 'Foundation'
	witness := read64(api.metadata - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 16 && read64(witness + 72) == 16 && read32(witness + 80) == 0x02010007 && read32(witness + 84) == 0x7fffffff
	// Indirect symbolic nominal reference keeps the relative field in range.
	mut name := [3]u64{}
	base := u64(unsafe { &name[0] })
	unsafe {
		*(&u8(base)) = 2
		*(&u64(base + 16)) = api.descriptor
	}
	for i in 0 .. 4 {
		unsafe { *(&u8(base + 1 + u64(i))) = u8(u32(15) >> u32(i * 8)) }
	}
	assert api.lookup(base, 5, 0, 0) == api.metadata
	page := usize(C.getpagesize())
	words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert words != u64(-1)
	metadata := words + 24
	mut destroyer := code + 128
	$if macos {
		if api.native {
			destroyer = unsafe { URLMetaSign(voidptr(code + 160))(destroyer, (metadata - 16) | (u64(0xbbbf) << 48)) }
		}
	}
	unsafe {
		*(&u64(metadata - 16)) = destroyer
		*(&u64(metadata + 32)) = 2
		*(&u64(metadata + 40)) = 2
		*(&u64(metadata + 48)) = 0xf00000020
		*(&u64(metadata + 64)) = words + 128
	}
	assert C.mprotect(voidptr(words), page, C.PROT_READ) == 0
	for heap in [false, true]! { url_meta_ownership(api, metadata, heap, true) }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn url_meta_worker(api, metadata) }
	workers.wait()
	url_meta_enums(api)
	assert C.munmap(voidptr(words), page) == 0
}

fn url_meta_mapping(address u64, mapped bool, executable bool) {
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

fn test_swift_url_metadata() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	url_meta_code(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		url_meta_suite(url_meta_api(true, code), code)
		println('IOS-URL-METADATA-NATIVE: complete accessor/nominal identity, inline sixteen-byte layout, eight witnesses, Swift/ObjC ownership, copy/take assignment reentry ordering, unchanged moved bytes, guarded/unaligned enum encoding and concurrent values measured')
	}
	for symbol in ['_$s10Foundation3URLVMa', '_$s10Foundation3URLVMn']! {
		if _ := swift_foundation_symbol(symbol) {
			assert false
		}
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread [2]u64{}
		for i in 0 .. 8 { publishers << spawn url_meta_publish(i % 2 == 0) }
		entries := publishers.wait()
		for pair in entries {
			assert pair == entries[0]
		}
		api := url_meta_api(false, code)
		arena := ios_runtime.swift_foundation_arena
		assert api.access == arena + 928 && api.descriptor == arena + u64(page) + 176
		assert read32(api.descriptor) == 0x51 && read32(api.descriptor + 16) == 0
		url_meta_mapping(api.access, true, true)
		url_meta_mapping(api.metadata, true, false)
		url_meta_suite(api, code)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		for library in ['/usr/lib/swift/libswiftCore.dylib',
			'/System/Library/Frameworks/UIKit.framework/UIKit']! {
			for symbol in ['_$s10Foundation3URLVMa', '_$s10Foundation3URLVMn']! {
				if _ := runtime_symbol(library, symbol) {
					assert false
				}
			}
		}
		if _ := swift_foundation_symbol('_$s10Foundation3URLV36_unconditionallyBridgeFromObjectiveCyACSo5NSURLCSgFZ') {
			assert false
		}
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		url_meta_mapping(api.access, false, false)
		url_meta_mapping(api.metadata, false, false)
		for symbol in ['_$s10Foundation3URLVMa', '_$s10Foundation3URLVMn']! {
			if _ := swift_foundation_symbol(symbol) {
				assert false
			}
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-URL-METADATA: canonical Foundation URL accessor/private nominal descriptor, native eight-witness layout and ownership, reentrant assignment ordering, guarded enum spans, concurrent publication/values and two unmapped lifetimes; constructors, concrete URL backend and field reflection remain unsupported')
}
