// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
import os
import strconv
#include <dlfcn.h>
$if macos {
	#include <mach/mach.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type SCSign = fn (u64, u64) u64
type SCSignResume = fn (u64) u64
type SCCreate = fn (u64, u64, u64, u64, u64) SwiftTaskPair
type SCJob = fn (u64, u64, u64)
type SCWord = fn (u64) u64
type SCDrop = fn (u64)
type SCCurrentTask = fn () u64
type SCTag = fn (u64, u32, u64) u32
type SCDestroy = fn (u64, u64)
type SCAccess = fn (u64) SwiftAssociatedMetadata
type SCRaw = fn (u64, u64, u64, u64)
struct SCApi {
	native bool
	entry u64
	descriptor u64
	create SCCreate
	run SCJob
	retain SCWord
	release SCDrop
	allocate SCWord
	deallocate SCDrop
	current SCCurrentTask
	tag SCTag
	metadata u64
	destroy SCDestroy
}
struct SCScene {
	api SCApi
	result u64
	resume u64
mut:
	owner u64
	parent u64
	child u64
	calls u64
	tag u32
}

fn sc_prepare(_unused u64, parent u64, context u64) SwiftTaskPair {
	mut scene := unsafe { &SCScene(context) }
	scene.parent = parent; scene.owner = scene.api.current()
	assert scene.owner != 0 && read64(scene.owner + 64) == parent
	child := scene.api.allocate(u64(read32(scene.api.descriptor + 4)))
	scene.child = child
	unsafe {
		*(&u64(parent + 16)) = context
		*(&u64(child)) = parent
		*(&u64(child + 8)) = scene.resume
	}
	return SwiftTaskPair{task: scene.result, context: child}
}

fn sc_resume(child u64) SwiftTaskPair {
	parent := read64(child)
	mut scene := unsafe { &SCScene(read64(parent + 16)) }
	assert scene.api.current() == scene.owner && child == scene.child && parent == scene.parent
	assert scene.calls == 0
	scene.tag = scene.api.tag(scene.result, 1, scene.api.metadata)
	assert scene.tag <= 1
	if !scene.api.native { assert scene.tag == 1 }
	scene.calls++
	completion := read64(parent + 8)
	scene.api.deallocate(child) // The tail caller must never touch this frame again.
	return SwiftTaskPair{task: parent, context: completion}
}

fn sc_api(native bool) SCApi {
	mut entries := [8]u64{}
	for i, symbol in ['_swift_task_create', '_swift_job_run', '_swift_retain', '_swift_release',
		'_swift_task_alloc', '_swift_task_dealloc', '_swift_task_getCurrent', '_$s8StoreKit10StorefrontV7currentACSgvgZTu']! {
		library := if i == 7 { '/System/Library/Frameworks/StoreKit.framework/StoreKit' }
			else if i == 2 || i == 3 { '/usr/lib/swift/libswiftCore.dylib' }
			else { '/usr/lib/swift/libswift_Concurrency.dylib' }
		if native { $if macos { entries[i] = u64(C.dlsym(C.dlopen(library.str, 2), symbol[1..].str)) } }
		else { entries[i] = runtime_symbol(library, symbol) or { panic(err) } }
		assert entries[i] != 0
	}
	mut metadata := u64(0)
	mut tag := SCTag(swift_string_enum_get)
	mut destroy := SCDestroy(swift_string_destroy)
	$if macos { if native {
		store := C.dlopen(c'/System/Library/Frameworks/StoreKit.framework/StoreKit', 2)
		response := unsafe { SCAccess(C.dlsym(store, c'$s8StoreKit10StorefrontVMa'))(0) }
		metadata = response.metadata
		witness := read64(metadata - 8) & u64(0x0000ffffffffffff)
		assert response.state == 0 && read64(witness + 64) == 48 && read32(witness + 84) == 0x7fffffff
		tag = unsafe { SCTag(voidptr(read64(witness + 48) & u64(0x0000ffffffffffff))) }
		destroy = unsafe { SCDestroy(voidptr(read64(witness + 8) & u64(0x0000ffffffffffff))) }
	} }
	if !native {
		metadata = unsafe { SCAccess(voidptr(runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', '_$s8StoreKit10StorefrontVMa') or { panic(err) }))(0) }.metadata
		witness := read64(metadata - 8)
		tag = unsafe { SCTag(voidptr(read64(witness + 48))) }
		destroy = unsafe { SCDestroy(voidptr(read64(witness + 8))) }
	}
	descriptor := entries[7]
	assert read32(descriptor + 4) == 64
	entry := u64(i64(descriptor) + i64(i32(read32(descriptor))))
	if !native { assert entry == runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', '_$s8StoreKit10StorefrontV7currentACSgvgZ') or { panic(err) } }
	return SCApi{native: native, entry: entry, descriptor: descriptor,
		create: unsafe { SCCreate(voidptr(entries[0])) }, run: unsafe { SCJob(voidptr(entries[1])) },
		retain: unsafe { SCWord(voidptr(entries[2])) }, release: unsafe { SCDrop(voidptr(entries[3])) },
		allocate: unsafe { SCWord(voidptr(entries[4])) }, deallocate: unsafe { SCDrop(voidptr(entries[5])) },
		current: unsafe { SCCurrentTask(voidptr(entries[6])) }, tag: tag, metadata: metadata, destroy: destroy}
}

fn sc_emit(code u64, api SCApi) {
	write32(code, 0xdac10820); write32(code + 4, 0xd65f03c0) // PACDA descriptor.
	write32(code + 16, 0xdac123e0); write32(code + 20, 0xd65f03c0) // PACIZA callback.
	// Root task -> child allocation -> static async getter, indirect result x0.
	for i, op in [u32(0xa9bf7bfd), 0xaa1603e1, 0xaa1403e2, 0x58000130,
		0xd63f0200, 0xa8c17bfd, 0xaa0103f6, 0x580000f0, 0xd61f0200]! { write32(code + 64 + u64(i * 4), op) }
	unsafe { *(&u64(code + 112)) = u64(voidptr(sc_prepare)); *(&u64(code + 120)) = api.entry }
	// Receive child x22; observer frees it, then restore parent and complete.
	for i, op in [u32(0xa9bf7bfd), 0xaa1603e0, 0x58000190, 0xd63f0200,
		0xa8c17bfd, 0xaa0003f6, 0xaa0103f0, 0xd2800014, 0xd2800015,
		if api.native { u32(0xdac143f0) } else { u32(0xd503201f) }, 0xd61f0200]! { write32(code + 128 + u64(i * 4), op) }
	unsafe { *(&u64(code + 184)) = u64(voidptr(sc_resume)) }
	// C raw call: protected unused x8 and parent; retain x20/x21/x22 sentinels.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0,
		0xaa0103e0, 0xaa0203f6, 0xaa0303e8, 0xd28a0414, 0xd28a0435,
		0xd63f0200, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + 256 + u64(i * 4), op) }
	// Raw resume observes the same child and returns via the raw caller's LR.
	for i, op in [u32(0xf9400ac9), 0xa9005534, 0xf9000936, 0xf9400d2a,
		0x9100054a, 0xf9000d2a, 0xd65f03c0]! { write32(code + 384 + u64(i * 4), op) }
}

fn sc_case(api SCApi, code u64, descriptor u64, queued bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	result := span + u64(page) * 2 - 48
	C.memset(voidptr(result - 8), 0xa5, 56)
	resume := if api.native { unsafe { SCSignResume(voidptr(code + 16))(code + 128) } } else { code + 128 }
	mut scene := SCScene{api: api, result: result, resume: resume}
	entry := if api.native { unsafe { SCSign(voidptr(code))(descriptor, 3848) } } else { descriptor }
	pair := api.create(0xc015 | if queued { u64(0x1000) } else { u64(0) }, 0, 0, entry, u64(unsafe { &scene }))
	if !queued { api.retain(pair.task); api.run(pair.task, 0, 0) }
	if !api.native { swift_tasks_join() }
	start := time.sys_mono_now()
	for C.ios_load_pointer(unsafe { &u64(pair.task + 8) }) != 3 {
		assert time.sys_mono_now() - start < i64(25 * time.second)
		time.sleep(time.millisecond)
	}
	assert scene.calls == 1 && scene.owner == pair.task && scene.parent == pair.context
	assert read64(result - 8) == 0xa5a5a5a5a5a5a5a5 && api.current() == 0
	if scene.tag == 0 { api.destroy(result, api.metadata) }
	api.release(pair.task)
	assert C.munmap(voidptr(span), page * 3) == 0
}

fn sc_worker(api SCApi, code u64, descriptor u64) { for _ in 0 .. 16 { sc_case(api, code, descriptor, true) } }

fn sc_raw(api SCApi, code u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1) && C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	for address in [span + u64(page), span + u64(page) + 8, span + u64(page) * 2 - 48]! {
		C.memset(voidptr(address), 0xa5, 48)
		mut observed := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
		mut context := [u64(span), code + 384, u64(unsafe { &observed[1] }), 0, 0, 0, 0, 0]!
		child := u64(unsafe { &context[0] })
		unsafe { SCRaw(voidptr(code + 256))(api.entry, address, child, span) }
		assert observed == [u64(0xcafe), 0x5020, 0x5021, child, 1, 0xbeef]!
		assert context[0] == span && context[1] == code + 384
		for i in 0 .. 48 { assert unsafe { *(&u8(address + u64(i))) } == if i >= 8 && i < 16 { u8(0) } else { u8(0xa5) } }
		assert api.tag(address, 1, api.metadata) == 1
	}
	assert C.munmap(voidptr(span), page * 3) == 0
}

fn sc_mapping(address u64, mapped bool, executable bool) {
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

fn sc_suite(native bool) {
	api := sc_api(native)
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	sc_emit(code, api)
	descriptor := code + u64(page)
	swift_protocol_relative(descriptor, code + 64); write32(descriptor + 4, 32)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 412))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(voidptr(descriptor), page, C.PROT_READ) == 0
	sc_case(api, code, descriptor, true)
	if !native {
		sc_raw(api, code)
		sc_mapping(api.entry, true, true); sc_mapping(api.descriptor, true, false)
		sc_case(api, code, descriptor, false)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn sc_worker(api, code, descriptor) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.swift_tasks == 0 && ios_runtime.swift_task_count == 0
	}
	assert C.munmap(voidptr(code), page * 2) == 0
}

fn sc_publish() u64 { return runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', '_$s8StoreKit10StorefrontV7currentACSgvgZTu') or { panic(err) } }

fn test_storefront_current() {
	$if macos { sc_suite(true); println('IOS-STOREFRONT-CURRENT-NATIVE: real async query, 64-byte descriptor, indirect guarded Optional<Storefront>, nested task frame and single child-context resume with joined completion') }
	if _ := storefront_symbol('_$s8StoreKit10StorefrontV7currentACSgvgZ') { assert false }
	for _ in 0 .. 2 {
		objc_start(); system_data_start() or { panic(err) }
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn sc_publish() }
		entries := publishers.wait(); descriptor := entries[0]
		for entry in entries { assert entry == descriptor }; unsafe { publishers.free(); entries.free() }
		fallback := swift_task_allocate(64)
		sc_suite(false)
		assert ios_runtime.swift_task_alloc_top == fallback - 16
		swift_task_deallocate(fallback)
		for name in ['_$s8StoreKit10StorefrontV7currentACSgvgZ', '_$s8StoreKit10StorefrontV7currentACSgvgZTu']! {
			for library in ['/usr/lib/swift/libswiftCore.dylib', '/usr/lib/libSystem.B.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
				if _ := runtime_symbol(library, name) { assert false }
			}
		}
		code := ios_runtime.storefront_code
		objc_stop(); system_data_stop()
		sc_mapping(code, false, true); sc_mapping(descriptor, false, false)
		assert ios_runtime.storefront_code == 0 && ios_runtime.swift_task_arena == 0
		if _ := storefront_symbol('_$s8StoreKit10StorefrontV7currentACSgvgZTu') { assert false }
	}
	println('IOS-STOREFRONT-CURRENT: accountless nil, exact guarded extra-inhabitant word, async x0/x22 ABI and single tail resume, freed child frames, real manual/queued tasks, eight workers/publishers, scoped sealed code/read-only descriptor and two drained/unmapped runtimes')
}
