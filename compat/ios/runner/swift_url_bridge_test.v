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
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type URLBridgeAllocate = fn (u64, u64, u64) u64
type URLBridgeDeallocate = fn (u64, u64, u64)
type URLBridgeRelease = fn (u64)
type URLBridgeProbe = fn (u64, u64, &u64)
type URLBridgeSign = fn (u64, u64) u64
type URLBridgeType = fn (u64) u64

struct URLBridgeApi {
	native      bool
	entry       u64
	allocate    URLBridgeAllocate
	deallocate  URLBridgeDeallocate
	release     URLBridgeRelease
	object_type URLBridgeType
}

struct URLBridgeScenario {
	api   URLBridgeApi
	owner u64
	url   u64
	table u64
mut:
	calls     int
	destroyed int
	observed  [4]u64
}

fn (api URLBridgeApi) keep(url u64) u64 {
	$if macos {
		if api.native { return u64(C.CFRetain(voidptr(url))) }
	}
	return objc_retain(url)
}

fn (api URLBridgeApi) drop(url u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(url))
			return
		}
	}
	objc_release(url)
}

fn (api URLBridgeApi) refs(url u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(url)) }
	}
	return obj_header(url).refs
}

fn url_bridge_destroy(owner u64) {
	mut scenario := unsafe { &URLBridgeScenario(read64(owner + 16)) }
	assert scenario.owner == owner && scenario.destroyed == 0
	assert read64(owner + 8) == 0x100000003
	scenario.destroyed++
	scenario.api.deallocate(owner, 32, 15)
}

fn url_bridge_witness(owner u64) u64 {
	mut scenario := unsafe { &URLBridgeScenario(read64(owner + 16)) }
	assert scenario.owner == owner && scenario.destroyed == 0
	assert read64(owner + 8) == 3 // Implementation is borrowed, with no extra retain.
	assert scenario.observed[0] == scenario.api.object_type(owner) && scenario.observed[1] == scenario.table
	assert scenario.observed[2] == scenario.table + 432 && scenario.observed[3] == owner
	scenario.calls++
	return scenario.api.keep(scenario.url)
}

fn url_bridge_code(code u64) {
	// C(entry, indirect Self, result) -> Swift borrowed Self in x20.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103f4, 0xaa0203f3]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 24, 0xd2800000 | (u32(0x7777) << 5) | 21)
	write32(code + 28, 0xd2800000 | (u32(0x8888) << 5) | 22)
	for i, op in [u32(0x91008268), 0xd63f0200, 0xa9005260, 0xa9015a75, 0xa9425bf5, 0xa94153f3,
		0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 32 + u64(i * 4), op)
	}
	// Capture exactly the registers used by the native URL witness, then
	// ordinary C borrows the implementation and returns owned NSURL.
	for i, op in [u32(0xf9400e89), 0xa9000520, 0xa9015128, 0xaa1403e0, 0x58000090, 0xd61f0200]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 160)) = u64(voidptr(url_bridge_witness)) }
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! { write32(code + 192 + u64(i * 4), op) }
	unsafe { *(&u64(code + 208)) = u64(voidptr(url_bridge_destroy)) }
	write32(code + 224, 0xdac10020)
	write32(code + 228, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 232))
}

fn url_bridge_case(api URLBridgeApi, code u64, metadata u64, self_end bool, slot_end bool) {
	page := usize(C.getpagesize())
	self_pages := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	table_pages := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert self_pages != u64(-1) && table_pages != u64(-1)
	assert C.mprotect(voidptr(self_pages + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	assert C.mprotect(voidptr(table_pages + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	self := self_pages + u64(page) + if self_end { u64(page) - 16 } else { u64(0) }
	slot := table_pages + u64(page) + if slot_end { u64(page) - 8 } else { u64(0) }
	table := slot - 432
	text := 'https://example.test/fortnite?bridge=owned#result'
	mut url := u64(0)
	$if macos {
		if api.native {
			url = u64(C.CFURLCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, unsafe { nil }))
		}
	}
	if !api.native {
		url = objc_allocate(ios_runtime.names['NSURL'])
		input := owned_string(text)
		assert http_url_initialize(url, input)
		objc_release(input)
	}
	assert url != 0
	owner := api.allocate(metadata, 32, 15)
	mut scenario := &URLBridgeScenario{ api: api, owner: owner, url: url, table: table }
	unsafe {
		*(&u64(owner + 16)) = u64(scenario)
		*(&u64(owner + 24)) = u64(&scenario.observed[0])
	}
	mut method := code + 128
	$if macos {
		if api.native {
			method = unsafe { URLBridgeSign(voidptr(code + 224))(method, slot | (u64(0x4c26) << 48)) }
		}
	}
	unsafe {
		*(&u64(self)) = owner
		*(&u64(self + 8)) = table
		*(&u64(slot)) = method
	}
	assert C.mprotect(voidptr(self_pages + u64(page)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(table_pages + u64(page)), page, C.PROT_READ) == 0
	probe := unsafe { URLBridgeProbe(voidptr(code)) }
	refs := api.refs(url)
	for iteration in 0 .. 32 {
		mut result := [6]u64{}
		result[4] = 0xcafe
		result[5] = 0xbeef
		probe(api.entry, self, unsafe { &result[0] })
		assert result[0] == url && result[1] == self && result[2] == 0x7777 && result[3] == 0x8888
		assert result[4] == 0xcafe && result[5] == 0xbeef
		assert scenario.calls == iteration + 1 && scenario.destroyed == 0
		assert read64(owner + 8) == 3 && api.refs(url) == refs + 1
		api.drop(result[0])
		assert api.refs(url) == refs
	}
	assert read64(self) == owner && read64(self + 8) == table && read64(slot) == method
	api.release(owner)
	assert scenario.destroyed == 1
	api.drop(url)
	unsafe { free(scenario) }
	assert C.munmap(voidptr(self_pages), page * 3) == 0 && C.munmap(voidptr(table_pages), page * 3) == 0
}

fn url_bridge_suite(api URLBridgeApi, code u64) {
	page := usize(C.getpagesize())
	words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert words != u64(-1)
	metadata := words + 24
	mut destroyer := code + 192
	$if macos {
		if api.native {
			destroyer = unsafe { URLBridgeSign(voidptr(code + 224))(destroyer, (metadata - 16) | (u64(0xbbbf) << 48)) }
		}
	}
	unsafe {
		*(&u64(metadata)) = 0
		*(&u64(metadata + 32)) = 2
		*(&u64(metadata + 40)) = 2
		*(&u64(metadata + 48)) = 0xf00000020
		*(&u64(metadata + 64)) = words + 128
		*(&u64(metadata - 16)) = destroyer
	}
	assert C.mprotect(voidptr(words), page, C.PROT_READ) == 0
	for self_end in [false, true]! {
		for slot_end in [false, true]! {
			url_bridge_case(api, code, metadata, self_end, slot_end)
			mut workers := []thread{}
			for _ in 0 .. 8 {
				workers << spawn url_bridge_case(api, code, metadata, self_end, slot_end)
			}
			workers.wait()
		}
	}
	assert C.munmap(voidptr(words), page) == 0
}

fn url_bridge_mapping(address u64, mapped bool, executable bool) {
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

fn url_bridge_publish(overlay bool) u64 {
	library := if overlay {
		'/usr/lib/swift/libswiftFoundation.dylib'
	} else {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	}
	mut entry := u64(0)
	for _ in 0 .. 128 {
		entry = runtime_symbol(library, '_$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF') or { panic(err) }
	}
	return entry
}

fn url_bridge_api(native bool, entry u64) URLBridgeApi {
	mut entries := [4]u64{}
	for i, name in ['_swift_allocObject', '_swift_deallocClassInstance', '_swift_release',
		'_swift_getObjectType']! {
		if native {
			handle := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			entries[i] = u64(C.dlsym(handle, name[1..].str))
		} else {
			entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
		}
		assert entries[i] != 0
	}
	return URLBridgeApi{
		native:      native
		entry:       entry
		allocate:    unsafe { URLBridgeAllocate(voidptr(entries[0])) }
		deallocate:  unsafe { URLBridgeDeallocate(voidptr(entries[1])) }
		release:     unsafe { URLBridgeRelease(voidptr(entries[2])) }
		object_type: unsafe { URLBridgeType(voidptr(entries[3])) }
	}
}

fn test_swift_url_bridge() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	url_bridge_code(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		handle := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		entry := u64(C.dlsym(handle, c'$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF'))
		assert entry != 0
		overlay := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', 2)
		assert u64(C.dlsym(overlay, c'$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF')) == entry
		url_bridge_suite(url_bridge_api(true, entry), code)
		println('IOS-URL-BRIDGE-NATIVE: indirect borrowed pair, formal type lookup and borrowed witness at432, x0 metadata/x1 table/x8 slot/x20 Self, owned NSURL result, exact ARC, guarded spans and eight callers measured')
	}
	if _ := swift_foundation_symbol('_$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF') {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for i in 0 .. 8 { publishers << spawn url_bridge_publish(i % 2 == 0) }
		entries := publishers.wait()
		entry := entries[0]
		for address in entries {
			assert address == entry
		}
		arena := ios_runtime.swift_foundation_arena
		assert entry == arena + 320
		url_bridge_mapping(entry, true, true)
		url_bridge_mapping(arena + u64(page), true, false)
		url_bridge_suite(url_bridge_api(false, entry), code)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		for library in ['/usr/lib/swift/libswiftCore.dylib',
			'/System/Library/Frameworks/UIKit.framework/UIKit']! {
			if _ := runtime_symbol(library, '_$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF') {
				assert false
			}
		}
		if _ := swift_foundation_symbol('_$s10Foundation3URLVMa') {
			assert false
		}
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0 && ios_runtime.swift_arc_code == 0
		url_bridge_mapping(entry, false, false)
		url_bridge_mapping(arena + u64(page), false, false)
		if _ := swift_foundation_symbol('_$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF') {
			assert false
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-URL-BRIDGE: native formal type lookup and borrowed witness dispatch without implementation ARC, owned NSURL results, preserved context and no indirect-result writes, sealed concurrent publication and two unmapped retirements; URL construction remains unsupported')
}
