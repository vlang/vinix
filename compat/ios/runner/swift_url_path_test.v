// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFURL.h>
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFURLCreateWithBytes(voidptr, &u8, i64, u32, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type URLPathAllocate = fn (u64, u64, u64) u64
type URLPathDeallocate = fn (u64, u64, u64)
type URLPathRetain = fn (u64) u64
type URLPathRelease = fn (u64)
type URLPathType = fn (u64) u64
type URLPathProbe = fn (u64, u64, u64, &u64)
type URLPathSign = fn (u64, u64) u64

struct URLPathApi {
	native      bool
	append      u64
	delete      u64
	allocate    URLPathAllocate
	deallocate  URLPathDeallocate
	retain      URLPathRetain
	release     URLPathRelease
	object_type URLPathType
}

struct URLPathScenario {
	api          URLPathApi
	owner        u64
	result       u64
	objc         bool
	table        u64
	result_table u64
	destination  u64
	deleting     bool
	fallback     bool
mut:
	first     u64
	second    u64
	flag      u64
	calls     int
	destroyed int
}

__global url_path_contexts = map[u64]&URLPathScenario{}

fn url_path_context(owner u64) &URLPathScenario {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return url_path_contexts[owner] or { panic('unknown URL path fixture owner') }
}

fn (api URLPathApi) refs(owner u64, objc bool) u64 {
	if !objc { return 1 + (read64(owner + 8) >> 33) }
	$if macos {
		if api.native { return u64(C.CFGetRetainCount(voidptr(owner))) }
	}
	return u64(obj_header(owner).refs)
}

fn url_path_destroy(owner u64) {
	mut scenario := url_path_context(owner)
	assert !scenario.objc && read64(owner + 8) == 0x100000003
	assert scenario.destroyed == 0
	scenario.destroyed++
	// Remove the lookup before freeing: another worker may immediately reuse
	// this address for a different owner after deallocation returns.
	C.ios_objc_initialize_lock()
	url_path_contexts.delete(owner)
	C.ios_objc_initialize_unlock()
	scenario.api.deallocate(owner, 32, 15)
}

fn url_path_witness(owner u64, metadata u64, table u64, output u64, first u64, second u64, flag u64) {
	mut scenario := url_path_context(owner)
	assert scenario.api.refs(owner, scenario.objc) == 1 && scenario.destroyed == 0
	assert metadata == scenario.api.object_type(owner) && table == scenario.table
	assert first == scenario.first && second == scenario.second && flag == scenario.flag
	assert output != scenario.destination && output & 15 == 0
	scenario.calls++
	if scenario.fallback {
		unsafe {
			*(&u64(output)) = 0
			*(&u64(output + 8)) = 0xbadcafe
		}
	} else {
		assert scenario.api.retain(scenario.result) == scenario.result
		unsafe {
			*(&u64(output)) = scenario.result
			*(&u64(output + 8)) = scenario.result_table
		}
	}
}

fn url_path_code(code u64) {
	// C(entry, Self, result, arguments) -> Swift x20 Self/x8 result. Keep the
	// caller's context separately from the guarded sixteen-byte result span.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103f4, 0xaa0203e8,
		0xaa0303f3, 0xa9400660, 0xf9400a62]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 36, 0xd2800000 | (u32(0x7777) << 5) | 21)
	write32(code + 40, 0xd2800000 | (u32(0x8888) << 5) | 22)
	for i, op in [u32(0xd63f0200), 0xa901d674, 0xf9001676, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd,
		0xd65f03c0]! {
		write32(code + 44 + u64(i * 4), op)
	}
	// Appending's witness: String words x0/x1, Bool x2, type x3, table x4.
	for i, op in [u32(0xaa0003e9), 0xaa0103ea, 0xaa0203eb, 0xaa1403e0, 0xaa0303e1, 0xaa0403e2,
		0xaa0803e3, 0xaa0903e4, 0xaa0a03e5, 0xaa0b03e6, 0x580000d0, 0xd61f0200]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 192)) = u64(voidptr(url_path_witness)) }
	// Deleting's witness: type x0, table x1; no String/Bool arguments.
	for i, op in [u32(0xaa0103e2), 0xaa0003e1, 0xaa1403e0, 0xaa0803e3, 0xd2800004, 0xd2800005,
		0xd2800006, 0x58000130, 0xd61f0200]! {
		write32(code + 224 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 288)) = u64(voidptr(url_path_witness)) }
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! { write32(code + 320 + u64(i * 4), op) }
	unsafe { *(&u64(code + 336)) = u64(voidptr(url_path_destroy)) }
	write32(code + 352, 0xdac10020)
	write32(code + 356, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 360))
}

fn url_path_owner(api URLPathApi, metadata u64, objc bool, other bool) u64 {
	if !objc { return api.allocate(metadata, 32, 15) }
	text := if other {
		'https://example.test/other-implementation'
	} else {
		'https://example.test/original-implementation'
	}
	$if macos {
		if api.native {
			return u64(C.CFURLCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, unsafe { nil }))
		}
	}
	owner := objc_allocate(ios_runtime.names['NSURL'])
	input := owned_string(text)
	assert http_url_initialize(owner, input)
	objc_release(input)
	return owner
}

fn url_path_case(api URLPathApi, code u64, metadata u64, deleting bool, fallback bool, objc bool, self_end bool, slot_end bool, output_end bool) {
	page := usize(C.getpagesize())
	mut pages := [3]u64{}
	for i in 0 .. 3 {
		pages[i] = u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert pages[i] != u64(-1)
		assert C.mprotect(voidptr(pages[i] + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	self := pages[0] + u64(page) + if self_end { u64(page) - 16 } else { u64(0) }
	slot := pages[1] + u64(page) + if slot_end { u64(page) - 8 } else { u64(0) }
	output := pages[2] + u64(page) + if output_end { u64(page) - 16 } else { u64(0) }
	table := slot - if deleting { u64(368) } else { u64(336) }
	result_table := pages[1] + u64(page) + 1024
	owner := url_path_owner(api, metadata, objc, false)
	result := url_path_owner(api, metadata, objc, true)
	assert owner != 0 && result != 0 && owner != result
	mut scenario := &URLPathScenario{
		api:          api
		owner:        owner
		result:       result
		objc:         objc
		table:        table
		result_table: result_table
		destination:  output
		deleting:     deleting
		fallback:     fallback
	}
	mut child := &URLPathScenario{ api: api, owner: result, objc: objc }
	C.ios_objc_initialize_lock()
	url_path_contexts[owner] = scenario
	url_path_contexts[result] = child
	C.ios_objc_initialize_unlock()
	mut method := code + if deleting { u64(224) } else { u64(128) }
	$if macos {
		if api.native {
			method = unsafe { URLPathSign(voidptr(code + 352))(method, slot | ((if deleting {
				u64(0x6dd6)
			} else {
				u64(0xa074)
			}) << 48)) }
		}
	}
	unsafe {
		*(&u64(self)) = owner
		*(&u64(self + 8)) = table
		*(&u64(slot)) = method
	}
	assert C.mprotect(voidptr(pages[0] + u64(page)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(pages[1] + u64(page)), page, C.PROT_READ) == 0
	probe := unsafe { URLPathProbe(voidptr(code)) }
	for iteration in 0 .. 8 {
		mut arguments := [u64(0x726964), 0xe300000000000000, u64(iteration & 1), 0, 0, 0, 0xcafe,
			0xbeef]!
		if iteration & 2 != 0 {
			arguments[0] = 0
			arguments[1] = 0xe000000000000000
		}
		scenario.first = if deleting { 0 } else { arguments[0] }
		scenario.second = if deleting { 0 } else { arguments[1] }
		scenario.flag = if deleting { 0 } else { arguments[2] }
		probe(if deleting { api.delete } else { api.append }, self, output, unsafe { &arguments[0] })
		assert arguments[3] == self && arguments[4] == 0x7777 && arguments[5] == 0x8888
		assert arguments[6] == 0xcafe && arguments[7] == 0xbeef
		assert read64(output) == if fallback { owner } else { result }
		assert read64(output + 8) == if fallback { table } else { result_table }
		assert api.refs(owner, objc) == if fallback { u64(2) } else { u64(1) }
		assert api.refs(result, objc) == if fallback { u64(1) } else { u64(2) }
		api.release(read64(output))
		assert api.refs(owner, objc) == 1 && api.refs(result, objc) == 1
		assert scenario.calls == iteration + 1 && scenario.destroyed == 0 && child.destroyed == 0
	}
	assert read64(self) == owner && read64(self + 8) == table && read64(slot) == method
	if objc {
		// Drop the lookup while the final owned reference prevents reuse.
		C.ios_objc_initialize_lock()
		url_path_contexts.delete(owner)
		url_path_contexts.delete(result)
		C.ios_objc_initialize_unlock()
	}
	api.release(owner)
	api.release(result)
	if !objc {
		assert scenario.destroyed == 1 && child.destroyed == 1
	}
	unsafe {
		free(scenario)
		free(child)
	}
	for address in pages {
		assert C.munmap(voidptr(address), page * 3) == 0
	}
}

fn url_path_suite(api URLPathApi, code u64) {
	page := usize(C.getpagesize())
	words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert words != u64(-1)
	metadata := words + 24
	mut destroyer := code + 320
	$if macos {
		if api.native {
			destroyer = unsafe { URLPathSign(voidptr(code + 352))(destroyer, (metadata - 16) | (u64(0xbbbf) << 48)) }
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
	for deleting in [false, true]! {
		for fallback in [false, true]! {
			for objc in [false, true]! {
				for self_end in [false, true]! {
					for slot_end in [false, true]! {
						for output_end in [false, true]! {
							url_path_case(api, code, metadata, deleting, fallback, objc, self_end, slot_end, output_end)
							if self_end && output_end {
								mut workers := []thread{}
								for _ in 0 .. 8 {
									workers << spawn url_path_case(api, code, metadata, deleting, fallback, objc, self_end, slot_end, output_end)
								}
								workers.wait()
							}
						}
					}
				}
			}
		}
	}
	assert url_path_contexts.len == 0
	assert C.munmap(voidptr(words), page) == 0
}

fn url_path_mapping(address u64, mapped bool, executable bool) {
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

fn url_path_entries(native bool, overlay bool) [2]u64 {
	library := if overlay {
		'/usr/lib/swift/libswiftFoundation.dylib'
	} else {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	}
	mut entries := [2]u64{}
	for i, symbol in [
		'_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF',
		'_$s10Foundation3URLV25deletingLastPathComponentACyF',
	]! {
		if native {
			handle := C.dlopen(library.str, 2)
			entries[i] = u64(C.dlsym(handle, symbol[1..].str))
		} else {
			entries[i] = runtime_symbol(library, symbol) or { panic(err) }
		}
		assert entries[i] != 0
	}
	return entries
}

fn url_path_publish(overlay bool) [2]u64 {
	entries := url_path_entries(false, overlay)
	for _ in 0 .. 128 {
		assert url_path_entries(false, overlay) == entries
	}
	return entries
}

fn url_path_api(native bool, entries [2]u64) URLPathApi {
	mut functions := [5]u64{}
	for i, symbol in ['_swift_allocObject', '_swift_deallocClassInstance', '_swift_unknownObjectRetain',
		'_swift_unknownObjectRelease', '_swift_getObjectType']! {
		if native {
			handle := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			functions[i] = u64(C.dlsym(handle, symbol[1..].str))
		} else {
			functions[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
		}
		assert functions[i] != 0
	}
	return URLPathApi{
		native:      native
		append:      entries[0]
		delete:      entries[1]
		allocate:    unsafe { URLPathAllocate(voidptr(functions[0])) }
		deallocate:  unsafe { URLPathDeallocate(voidptr(functions[1])) }
		retain:      unsafe { URLPathRetain(voidptr(functions[2])) }
		release:     unsafe { URLPathRelease(voidptr(functions[3])) }
		object_type: unsafe { URLPathType(voidptr(functions[4])) }
	}
}

fn test_swift_url_path() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	url_path_code(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		entries := url_path_entries(true, false)
		assert url_path_entries(true, true) == entries
		url_path_suite(url_path_api(true, entries), code)
		println('IOS-URL-PATH-NATIVE: append/delete slots336/368, borrowed String/Bool/implementation, formal type metadata, owned witness result and retained original fallback, Swift/ObjC ARC, guarded sixteen-byte Self/result and exact slot, preserved context and eight callers measured')
	}
	for symbol in [
		'_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF',
		'_$s10Foundation3URLV25deletingLastPathComponentACyF',
	]! {
		if _ := swift_foundation_symbol(symbol) {
			assert false
		}
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread [2]u64{}
		for i in 0 .. 8 { publishers << spawn url_path_publish(i % 2 == 0) }
		all := publishers.wait()
		entries := all[0]
		for pair in all {
			assert pair == entries
		}
		arena := ios_runtime.swift_foundation_arena
		assert entries == [arena + 416, arena + 672]!
		url_path_mapping(entries[0], true, true)
		url_path_mapping(arena + u64(page), true, false)
		url_path_suite(url_path_api(false, entries), code)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		for library in ['/usr/lib/swift/libswiftCore.dylib',
			'/System/Library/Frameworks/UIKit.framework/UIKit']! {
			for symbol in [
				'_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF',
				'_$s10Foundation3URLV25deletingLastPathComponentACyF',
			]! {
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
		url_path_mapping(entries[0], false, false)
		url_path_mapping(arena + u64(page), false, false)
		for symbol in [
			'_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF',
			'_$s10Foundation3URLV25deletingLastPathComponentACyF',
		]! {
			if _ := swift_foundation_symbol(symbol) {
				assert false
			}
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-URL-PATH: native borrowed append/delete witness dispatch, owned replacement and identity fallback with exact Swift/ObjC ownership, guarded ABI spans, concurrent calls/publication and two unmapped lifetimes; concrete URL construction and path backend remain unsupported')
}
