// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
import os
import strconv
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <mach/mach.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithCString(voidptr, &char, u32) voidptr
fn C.CFStringGetCString(voidptr, &u8, i64, u32) bool
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFErrorGetDomain(voidptr) voidptr
fn C.CFErrorGetCode(voidptr) i64
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type RFAccess = fn (u64) SwiftAssociatedMetadata
type RFCopy = fn (u64, u64, u64) u64
type RFDrop = fn (u64)
type RFKeep = fn (u64) u64
type RFGet = fn (u64, u32, u64) u32
type RFPut = fn (u64, u32, u32, u64)
type RFTag = fn (u64, u64) u32
type RFNoop = fn (u64, u64)
type RFInject = fn (u64, u32, u64)
type RFLookup = fn (u64, u64, u64, u64) u64
type RFCreate = fn (u64, u64, u64, u64, u64) SwiftTaskPair
type RFJob = fn (u64, u64, u64)
type RFCurrent = fn () u64
type RFSign = fn (u64, u64) u64
type RFSignResume = fn (u64) u64
type RFRaw = fn (u64, u64, u64, u64)
struct RFApi {
	native bool
	entry u64
	descriptor u64
	access u64
	metadata u64
	create RFCreate
	run RFJob
	retain RFKeep
	release RFDrop
	allocate RFKeep
	deallocate RFDrop
	current RFCurrent
	error_keep RFKeep
	error_drop RFDrop
}
struct RFScene {
	api RFApi
	result u64
	resume u64
	propagate bool
mut:
	owner u64
	parent u64
	child u64
	future u64
	calls u64
	error_value u64
}
fn rf_native_error() u64 {
	$if macos {
		domain := C.CFStringCreateWithCString(unsafe { nil }, c'SKErrorDomain', 0x08000100)
		owner := C.CFErrorCreate(unsafe { nil }, domain, 19, unsafe { nil })
		C.CFRelease(domain)
		assert owner != unsafe { nil }
		return u64(owner)
	}
	panic('native error fixture requires macOS')
}
fn rf_error(api RFApi, owner u64) {
	assert owner != 0
	$if macos { if api.native {
		assert C.CFErrorGetCode(voidptr(owner)) == 19
		mut bytes := [32]u8{}
		assert C.CFStringGetCString(C.CFErrorGetDomain(voidptr(owner)), unsafe { &bytes[0] }, 32, 0x08000100)
		assert unsafe { (&char(&bytes[0])).vstring() } == 'SKErrorDomain'
		return
	} }
	assert cf_error_code(owner) == 19 && string_text(cf_error_domain(owner)) == 'SKErrorDomain'
	info := obj_header(owner).fields[1]
	assert info != 0 && obj_header(info).keys.len == 1 && obj_header(info).items.len == 1
	assert string_text(obj_header(info).keys[0]) == 'NSLocalizedDescription'
	assert string_text(obj_header(info).items[0]) == 'Refund requests are unavailable on this platform.'
	assert swift_error_bridge_checked(owner) or { panic(err) } == owner
}
fn rf_refs(api RFApi, owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(voidptr(owner)) } }
	return obj_header(owner).refs
}
fn rf_prepare(future u64, parent u64, context u64) SwiftTaskPair {
	mut scene := unsafe { &RFScene(context) }
	scene.parent = parent; scene.owner = scene.api.current(); scene.future = future
	assert scene.owner != 0 && read64(scene.owner + 64) == parent && future != 0
	unsafe { *(&u8(future)) = 0xa5 }
	child := scene.api.allocate(u64(read32(scene.api.descriptor + 4)))
	scene.child = child
	unsafe { *(&u64(parent + 16)) = context; *(&u64(child)) = parent; *(&u64(child + 8)) = scene.resume }
	return SwiftTaskPair{task: scene.result, context: child}
}
fn rf_resume(child u64, error_value u64) SwiftTaskPair {
	parent := read64(child)
	mut scene := unsafe { &RFScene(read64(parent + 16)) }
	assert scene.api.current() == scene.owner && scene.child == child && scene.parent == parent && scene.calls == 0
	rf_error(scene.api, error_value)
	assert rf_refs(scene.api, error_value) == 1
	scene.error_value = scene.api.error_keep(error_value)
	scene.calls++
	unsafe { *(&u64(parent + 24)) = if scene.propagate { error_value } else { u64(0) } }
	if !scene.propagate {
		// A synthetic catching caller supplies its own valid result. The refund
		// entry itself never writes a status or reports a completed request.
		unsafe { *(&u8(scene.future)) = 1 }
		scene.api.error_drop(error_value)
	}
	completion := read64(parent + 8)
	scene.api.deallocate(child) // Tail resumption may free the child immediately.
	return SwiftTaskPair{task: parent, context: completion}
}
fn rf_api(native bool, code u64, data u64) RFApi {
	mut entries := [9]u64{}
	for i, symbol in ['_swift_task_create', '_swift_job_run', '_swift_retain', '_swift_release',
		'_swift_task_alloc', '_swift_task_dealloc', '_swift_task_getCurrent', '_swift_errorRetain', '_swift_errorRelease']! {
		library := if i in [2, 3, 7, 8]! { '/usr/lib/swift/libswiftCore.dylib' } else { '/usr/lib/swift/libswift_Concurrency.dylib' }
		if native { entries[i] = u64(C.dlsym(C.dlopen(library.str, 2), symbol[1..].str)) }
		else { entries[i] = runtime_symbol(library, symbol) or { panic(err) } }
		assert entries[i] != 0
	}
	mut access := u64(0)
	mut entry := u64(0)
	mut descriptor := u64(0)
	if native {
		access = u64(C.dlsym(C.dlopen(c'/System/Library/Frameworks/StoreKit.framework/StoreKit', 2), refund_status_symbol[1..].str))
		entry = code + 512; descriptor = data + 16 // Synthetic thrower; no refund API invocation.
	} else {
		library := '/System/Library/Frameworks/StoreKit.framework/StoreKit'
		access = runtime_symbol(library, refund_status_symbol) or { panic(err) }
		entry = runtime_symbol(library, refund_entry_symbol) or { panic(err) }
		descriptor = runtime_symbol(library, refund_descriptor_symbol) or { panic(err) }
	}
	response := unsafe { RFAccess(voidptr(access))(0) }
	assert response.state == 0 && read32(descriptor + 4) == 112
	assert u64(i64(descriptor) + i64(i32(read32(descriptor)))) == entry
	return RFApi{native: native, access: access, entry: entry, descriptor: descriptor, metadata: response.metadata,
		create: unsafe { RFCreate(voidptr(entries[0])) }, run: unsafe { RFJob(voidptr(entries[1])) },
		retain: unsafe { RFKeep(voidptr(entries[2])) }, release: unsafe { RFDrop(voidptr(entries[3])) },
		allocate: unsafe { RFKeep(voidptr(entries[4])) }, deallocate: unsafe { RFDrop(voidptr(entries[5])) },
		current: unsafe { RFCurrent(voidptr(entries[6])) }, error_keep: unsafe { RFKeep(voidptr(entries[7])) }, error_drop: unsafe { RFDrop(voidptr(entries[8])) }}
}
fn rf_emit(code u64, api RFApi) {
	write32(code, 0xdac10820); write32(code + 4, 0xd65f03c0)
	write32(code + 16, 0xdac123e0); write32(code + 20, 0xd65f03c0)
	for i, op in [u32(0xa9bf7bfd), 0xaa1603e1, 0xaa1403e2, 0x58000130,
		0xd63f0200, 0xa8c17bfd, 0xaa0103f6, 0x580000f0, 0xd61f0200]! { write32(code + 64 + u64(i * 4), op) }
	unsafe { *(&u64(code + 112)) = u64(voidptr(rf_prepare)); *(&u64(code + 120)) = api.entry }
	// Propagate the child's x21 through C, free that child, then pass the root
	// task's separate error completion argument in x20 (native task ABI).
	for i, op in [u32(0xa9bf7bfd), 0xaa1603e0, 0xaa1503e1, 0x580001b0, 0xd63f0200,
		0xa8c17bfd, 0xf9400c14, 0xaa0003f6, 0xaa0103f0, 0xd2800015,
		if api.native { u32(0xdac143f0) } else { u32(0xd503201f) }, 0xd61f0200]! { write32(code + 128 + u64(i * 4), op) }
	unsafe { *(&u64(code + 192)) = u64(voidptr(rf_resume)) }
	// Raw caller preserves C registers and makes unused x1/x2/x8 inaccessible.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0,
		0xaa0103e0, 0xaa0203f6, 0xaa0303e8, 0xaa0303e1, 0xaa0303e2,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + 256 + u64(i * 4), op) }
	for i, op in [u32(0xf9400ac9), 0xa9005534, 0xf9000936, 0xf9400d2a,
		0x9100054a, 0xf9000d2a, 0xd65f03c0]! { write32(code + 384 + u64(i * 4), op) }
	for i, op in [u32(0xa9bf7bfd), 0x580000f0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xf94006d0, 0xd61f0200]! { write32(code + 512 + u64(i * 4), op) }
	unsafe { *(&u64(code + 544)) = u64(voidptr(rf_native_error)) }
}
fn rf_case(api RFApi, code u64, descriptor u64, queued bool, propagate bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	result := span + u64(page) * 2 - 1
	C.memset(voidptr(result - 8), 0xa5, 9)
	mut resume := code + 128
	$if macos { if api.native { resume = unsafe { RFSignResume(voidptr(code + 16))(resume) } } }
	mut scene := RFScene{api: api, result: result, resume: resume, propagate: propagate}
	pair := api.create(if queued {u64(0x9015)} else {u64(0x8015)}, 0, api.metadata, descriptor, u64(unsafe { &scene }))
	assert pair.task != 0
	if !queued { api.retain(pair.task); api.run(pair.task, 0, 0) }
	if !api.native { swift_tasks_join() }
	start := time.sys_mono_now()
	for C.ios_load_pointer(unsafe { &u64(pair.task + 8) }) != 3 { assert time.sys_mono_now() - start < i64(20 * time.second); C.usleep(1000) }
	assert read64(pair.task + 176) & 3 == if propagate {u64(2)} else {u64(1)}
	assert scene.calls == 1 && scene.error_value != 0
	for i in 0 .. 9 { assert unsafe { *(&u8(result - 8 + u64(i))) } == 0xa5 }
	assert unsafe { *(&u8(scene.future)) } == if propagate {u8(0xa5)} else {u8(1)}
	assert rf_refs(api, scene.error_value) == if propagate {i64(2)} else {i64(1)}
	if propagate { assert read64(pair.task + 192) == scene.error_value }
	api.release(pair.task)
	assert rf_refs(api, scene.error_value) == 1
	rf_error(api, scene.error_value)
	api.error_drop(scene.error_value)
	assert C.munmap(voidptr(span), page * 3) == 0
}
fn rf_raw(api RFApi, code u64) {
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	mut words := [14]u64{}
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	context := u64(unsafe { &words[0] })
	words[0] = guard; words[1] = code + 384; words[2] = u64(unsafe { &capture[1] })
	call := unsafe { RFRaw(voidptr(code + 256)) }
	for _ in 0 .. 64 {
		capture[4] = 0; call(api.entry, guard, context, guard)
		assert capture[0] == 0xcafe && capture[1] == 0x5020 && capture[3] == context && capture[4] == 1 && capture[5] == 0xbeef && words[0] == guard
		rf_error(api, capture[2]); assert rf_refs(api, capture[2]) == 1; api.error_drop(capture[2])
	}
	assert C.munmap(voidptr(guard), page) == 0
}

fn rf_metadata(api RFApi) {
	for request in [u64(0), 0xff, 0x100, 0x1ff, u64(-1)]! {
		assert unsafe { RFAccess(voidptr(api.access))(request) } == SwiftAssociatedMetadata{metadata: api.metadata}
	}
	metadata := api.metadata
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	descriptor := read64(metadata + 8) & 0x0000ffffffffffff
	assert read64(metadata) == 0x201 && read64(witness + 64) == 1 && read64(witness + 72) == 1
	assert read32(witness + 80) == 0x02200000 && read32(witness + 84) == 254
	assert read32(descriptor) & 0xffff == 0x52 && read32(descriptor + 20) == 0 && read32(descriptor + 24) == 2
	assert ctext(u64(i64(descriptor + 8) + i64(i32(read32(descriptor + 8))))) == 'RefundRequestStatus'
	parent := u64(i64(descriptor + 4) + i64(i32(read32(descriptor + 4))))
	assert read32(parent) & 0xffff == 0x51 && ctext(u64(i64(parent + 8) + i64(i32(read32(parent + 8))))) == 'Transaction'
	module_descriptor := u64(i64(parent + 4) + i64(i32(read32(parent + 4))))
	assert ctext(u64(i64(module_descriptor + 8) + i64(i32(read32(module_descriptor + 8))))) == 'StoreKit'
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_NONE) == 0 && C.mprotect(voidptr(region + u64(page * 3)), page, C.PROT_NONE) == 0
	source := region + u64(page) - 1; destination := region + u64(page * 3) - 1
	destroy := unsafe { RFNoop(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	project := unsafe { RFNoop(voidptr(read64(witness + 96) & 0x0000ffffffffffff)) }
	get_tag := unsafe { RFTag(voidptr(read64(witness + 88) & 0x0000ffffffffffff)) }
	inject := unsafe { RFInject(voidptr(read64(witness + 104) & 0x0000ffffffffffff)) }
	destroy(region + u64(page), metadata); project(region + u64(page), metadata)
	for byte in 0 .. 256 {
		unsafe { *(&u8(source)) = u8(byte); *(&u8(destination - 1)) = 0x5a }
		assert C.mprotect(voidptr(region), page, C.PROT_READ) == 0
		for slot in [0, 2, 3, 4, 5]! {
			copy_value := unsafe { RFCopy(voidptr(read64(witness + u64(slot * 8)) & 0x0000ffffffffffff)) }
			assert copy_value(destination, source, metadata) == destination
			assert unsafe { *(&u8(destination)) } == u8(byte) && unsafe { *(&u8(destination - 1)) } == 0x5a
		}
		assert get_tag(source, metadata) == u32(byte)
		inject(destination, u32(byte), metadata)
		assert unsafe { *(&u8(destination)) } == u8(byte)
		assert C.mprotect(voidptr(region), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	get := unsafe { RFGet(voidptr(read64(witness + 48) & 0x0000ffffffffffff)) }
	put := unsafe { RFPut(voidptr(read64(witness + 56) & 0x0000ffffffffffff)) }
	for pair in [[u32(0), 0]!, [u32(1), 0]!, [u32(254), 0]!, [u32(255), 1]!, [u32(65278), 1]!,
		[u32(65279), 2]!, [u32(16776958), 2]!, [u32(16776959), 4]!, [u32(0xffffffff), 1]!]! {
		count := pair[0]; width := pair[1]
		for tag in [u32(0), 1, 254, 255, 256, 65278, 65279, 16776958, 16776959, 0xffffffff]! {
			if tag > count { continue }
			mut expected := [5]u8{}
			expected[0] = if tag == 0 {u8(1)} else if tag <= 254 {u8(tag + 1)} else {u8(tag - 255)}
			upper := if tag <= 254 {u32(0)} else {((tag - 255) >> 8) + 1}
			for i in u32(0) .. width { expected[i + 1] = u8(upper >> (i * 8)) }
			// Model the native tag-byte truncation, including UInt32 overflow.
			mut stored := u32(0)
			for i in u32(0) .. width { stored |= u32(expected[i + 1]) << (i * 8) }
			roundtrip := if count == 0 {u32(0)} else if stored != 0 {((stored - 1) << 8) + u32(expected[0]) + 255}
				else if expected[0] < 2 {u32(0)} else {u32(expected[0]) - 1}
			for edge in [false, true]! {
				value := if edge {destination + 1 - u64(width + 1)} else {region + u64(page * 2)}
				C.memset(voidptr(value), 0xa5, usize(width + 1)); unsafe { *(&u8(value)) = 1 }
				put(value, tag, count, metadata)
				assert get(value, count, metadata) == roundtrip
				for i in u32(0) .. width + 1 { assert unsafe { *(&u8(value + i)) } == expected[i] }
				mut bytes := [16]u8{}
				for i in 0 .. 16 { bytes[i] = 0xa5 }; bytes[5] = 1
				unaligned := u64(unsafe { &bytes[5] }); put(unaligned, tag, count, metadata)
				assert get(unaligned, count, metadata) == roundtrip
				for i in 0 .. 16 { assert bytes[i] == if i >= 5 && i < 6 + int(width) {expected[i - 5]} else {u8(0xa5)} }
			}
		}
	}
	if !api.native {
		assert get(region + u64(page), 0, metadata) == 0
		put(region + u64(page), 0, 0, metadata)
		mut name := [3]u64{}
		base := u64(unsafe { &name[0] })
		unsafe { *(&u8(base)) = 2; *(&u64(base + 16)) = descriptor }
		for i in 0 .. 4 { unsafe { *(&u8(base + 1 + u64(i))) = u8(u32(15) >> u32(i * 8)) } }
		lookup := unsafe { RFLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getTypeByMangledNameInContext') or { panic(err) })) }
		assert lookup(base, 5, 0, 0) == metadata
	}
	assert C.munmap(voidptr(region), page * 4) == 0
}
fn rf_worker(api RFApi, code u64, descriptor u64) {
	for _ in 0 .. 4 { for propagate in [false, true]! { rf_case(api, code, descriptor, false, propagate) } }
}
fn rf_publish() u64 {
	mut entry := u64(0)
	for _ in 0 .. 128 { next := runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', refund_entry_symbol) or { panic(err) }; assert entry == 0 || entry == next; entry = next }
	return entry
}
fn rf_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped { assert status == 0 && start <= address && info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 }) }
		else { assert status != 0 || start > address }
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields(); if fields.len < 2 { continue }; range := fields[0].split('-'); if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }; end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if start <= address && address < end { assert mapped && fields[1] == if executable { 'r-xp' } else { 'r--p' }; found = true }
		}
		assert found == mapped
	}
}

fn rf_suite(native bool) {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	data := code + u64(page)
	swift_protocol_relative(data, code + 64); write32(data + 4, 64)
	swift_protocol_relative(data + 16, code + 512); write32(data + 20, 112)
	api := rf_api(native, code, data)
	rf_emit(code, api)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 552))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(data), page, C.PROT_READ) == 0
	mut descriptor := data
	$if macos { if native { descriptor = unsafe { RFSign(voidptr(code))(descriptor, 29199) } } }
	rf_metadata(api)
	rf_raw(api, code)
	for queued in [false, true]! { for propagate in [false, true]! { rf_case(api, code, descriptor, queued, propagate) } }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn rf_worker(api, code, descriptor) }
	workers.wait()
	assert C.munmap(voidptr(code), page * 2) == 0
}
fn test_refund() {
	$if macos { rf_suite(true); println('IOS-REFUND-NATIVE: measured two-case POD enum/VWT and generic native Swift async throwing/catching with synthetic CFError; refund service entries not invoked') }
	for symbol in [refund_entry_symbol, refund_descriptor_symbol, refund_status_symbol]! { if _ := refund_symbol(symbol) { assert false } }
	for _ in 0 .. 2 {
		objc_start(); system_data_start() or { panic(err) }
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn rf_publish() }
		entries := workers.wait()
		for entry in entries { assert entry == entries[0] }
		base := ios_runtime.storefront_code
		rf_mapping(base, true, true); rf_mapping(base + u64(C.getpagesize()), true, false)
		rf_suite(false)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/swift/libswiftCore.dylib']! {
			for symbol in [refund_entry_symbol, refund_descriptor_symbol, refund_status_symbol]! { if _ := runtime_symbol(library, symbol) { assert false } }
		}
		objc_stop(); system_data_stop()
		assert ios_runtime.storefront_code == 0 && ios_runtime.storefront_retired
		rf_mapping(base, false, true); rf_mapping(base + u64(C.getpagesize()), false, false)
		for symbol in [refund_entry_symbol, refund_descriptor_symbol, refund_status_symbol]! { if _ := refund_symbol(symbol) { assert false } }
	}
	println('IOS-REFUND: unavailable-platform Error, untouched indirect status/borrowed arguments, throwing x21 and tail child x22, caught/propagated native task ABI, balanced error futures, exact enum witnesses, guarded byte limits, eight workers/publishers and drained lifetimes')
}
