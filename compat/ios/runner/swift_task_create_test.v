// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithCString(voidptr, &char, u32) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFRelease(voidptr)

type TaskCreateCall = fn (u64, u64, u64, u64, u64) SwiftTaskPair
type TaskJobCall = fn (u64, u64, u64)
type TaskHeapAllocate = fn (u64, u64, u64) u64
type TaskHeapDeallocate = fn (u64, u64, u64)
type TaskLiteralCall = fn (&u8, i64, bool) SwiftStringWords
type TaskCreateCurrent = fn () u64
type TaskCreateRetain = fn (u64) u64
type TaskCreateRelease = fn (u64)

struct TaskCreateApi {
	native bool
	create TaskCreateCall
	run TaskJobCall
	current TaskCreateCurrent
	retain TaskCreateRetain
	release TaskCreateRelease
	allocate TaskCreateRetain
	deallocate TaskCreateRelease
	heap_allocate TaskHeapAllocate
	heap_deallocate TaskHeapDeallocate
	literal TaskLiteralCall
	integer u64
	string u64
	void_type u64
}
struct TaskScenario {
mut:
	tag u64
	api TaskCreateApi
	kind int
	dropped u64
	calls u64
	owner u64
	context u64
	result u64
	leftover bool
	error_value u64
}
type TaskDataSign = fn (u64, u64) u64

fn task_scenario_observe(result u64, context u64, self u64, error_word u64) u64 {
	mut scene := unsafe { &TaskScenario(if read64(self) == 0x1234 { self } else { read64(self + 16) }) }
	assert scene.tag == 0x1234 && error_word == 0
	owner := scene.api.current()
	assert owner != 0 && read64(read64(owner)) == 0x502
	assert read64(owner + 64) == context && read64(context) == 0 && read64(context + 8) != 0
	scene.owner = owner; scene.context = context
	a := scene.api.allocate(17); b := scene.api.allocate(33)
	assert a != 0 && b != 0 && a != b && a & 15 == 0 && b & 15 == 0
	unsafe { *(&u64(a)) = 0x9876; *(&u64(b)) = 0x5678 }
	assert read64(a) == 0x9876 && read64(b) == 0x5678
	if !scene.leftover { scene.api.deallocate(b); scene.api.deallocate(a) }
	if !scene.api.native {
		assert ios_runtime.swift_task_alloc_top != a - 16 && ios_runtime.swift_task_alloc_top != b - 16
		if _ := swift_task_deallocate_checked(ios_runtime.swift_task_alloc_top + 16) { assert false }
	}
	if scene.kind != 0 {
		assert result == read64(context - 32) && result != 0
		scene.result = result
		if scene.error_value == 0 {
			if scene.kind == 1 { unsafe { *(&u64(result)) = 0x123456789abcdef0 } }
			if scene.kind == 2 {
				text := 'task future owns this long native String result'
				value := scene.api.literal(text.str, i64(text.len), true)
				unsafe { *(&SwiftStringWords(result)) = value }
			}
		}
	}
	C.ios_store_pointer(unsafe { &scene.calls }, 1)
	return scene.error_value
}

fn task_scenario_drop(owner u64) {
	mut scene := unsafe { &TaskScenario(read64(owner + 16)) }
	// Native completes the closure's release before clearing current-task TLS.
	assert scene.api.current() == scene.owner && C.ios_load_pointer(unsafe { &scene.calls }) == 1
	if !scene.api.native {
		worker := spawn task_create_resolve_worker()
		assert worker.wait() != 0 // A destructor may join another resolver.
	}
	C.ios_store_pointer(unsafe { &scene.dropped }, 1)
	scene.api.heap_deallocate(owner, 32, 15)
}

fn task_scenario_emit(code u64) {
	write32(code, 0xdac10820); write32(code + 4, 0xd65f03c0) // Native descriptor signing only.
	for native in [false, true]! {
		base := code + if native { u64(256) } else { u64(512) }
		for i, instruction in [u32(0xa9bf7bfd), 0xaa1603e1, 0xaa1403e2, 0xaa1503e3,
			0x58000190, 0xd63f0200, 0xa8c17bfd, 0xaa0003f4, 0xd2800015,
			0xf94006d0, if native { u32(0xdac143f0) } else { u32(0xd503201f) }, 0xd61f0200]! { write32(base + u64(i * 4), instruction) }
		unsafe { *(&u64(base + 64)) = u64(voidptr(task_scenario_observe)) }
		// A consumed opaque closure need not be a readable heap object.
		for i, instruction in [u32(0xd2800014), 0xd2800015, 0xf94006d0,
			if native { u32(0xdac143f0) } else { u32(0xd503201f) }, 0xd61f0200]! { write32(base + 96 + u64(i * 4), instruction) }
	}
	write32(code + 768, 0xaa1403e0); write32(code + 772, 0x58000070); write32(code + 776, 0xd61f0200)
	unsafe { *(&u64(code + 784)) = u64(voidptr(task_scenario_drop)) }
}

fn task_create_api(native bool) TaskCreateApi {
	mut concurrency := unsafe { voidptr(nil) }
	mut core := unsafe { voidptr(nil) }
	$if macos {
		if native {
			concurrency = C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib', C.RTLD_NOW)
			core = C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			assert concurrency != unsafe { nil } && core != unsafe { nil }
		}
	}
	mut entries := [13]u64{}
	for i, name in ['_swift_task_create', '_swift_job_run', '_swift_task_getCurrent', '_swift_retain', '_swift_release',
		'_swift_task_alloc', '_swift_task_dealloc', '_swift_allocObject', '_swift_deallocObject',
		'_$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC', '_$sSiN', '_$sSSN', '_$sytN']! {
		is_concurrency := i < 3 || i == 5 || i == 6
		if native { entries[i] = u64(C.dlsym(if is_concurrency { concurrency } else { core }, name[1..].str)) }
		else { entries[i] = runtime_symbol('/usr/lib/swift/' + if is_concurrency { 'libswift_Concurrency.dylib' } else { 'libswiftCore.dylib' }, name) or { panic(err) } }
		assert entries[i] != 0, name
	}
	return TaskCreateApi{ native: native, create: unsafe { TaskCreateCall(voidptr(entries[0])) },
		run: unsafe { TaskJobCall(voidptr(entries[1])) }, current: unsafe { TaskCreateCurrent(voidptr(entries[2])) },
		retain: unsafe { TaskCreateRetain(voidptr(entries[3])) }, release: unsafe { TaskCreateRelease(voidptr(entries[4])) },
		allocate: unsafe { TaskCreateRetain(voidptr(entries[5])) }, deallocate: unsafe { TaskCreateRelease(voidptr(entries[6])) },
		heap_allocate: unsafe { TaskHeapAllocate(voidptr(entries[7])) }, heap_deallocate: unsafe { TaskHeapDeallocate(voidptr(entries[8])) },
		literal: unsafe { TaskLiteralCall(voidptr(entries[9])) }, integer: entries[10], string: entries[11], void_type: entries[12] + 8 }
}

fn task_create_resolve_worker() u64 {
	mut result := u64(0)
	for _ in 0 .. 64 { result = runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_swift_task_create') or { panic(err) } }
	return result
}

fn task_scenario(api TaskCreateApi, code u64, kind int, queued bool, consumed bool, named bool, leftover bool) {
	page := usize(C.getpagesize())
	data := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert data != u64(-1)
	assert C.mprotect(unsafe { voidptr(data + u64(page)) }, page, C.PROT_NONE) == 0
	descriptor := data + u64(page) - 8
	body := code + if api.native { u64(256) } else { u64(512) }
	delta := i64(body) - i64(descriptor)
	assert delta >= -2147483648 && delta <= 2147483647
	write32(descriptor, u32(i32(delta))); write32(descriptor + 4, 32)
	heap_metadata := data + 32
	unsafe { *(&u64(heap_metadata - 16)) = code + 768; *(&u64(heap_metadata)) = 0x400 }
	name := 'named task fixture'
	unsafe { *(&u64(data + 64)) = 7; *(&u64(data + 72)) = 0; *(&u64(data + 80)) = u64(name.str) }
	assert C.mprotect(unsafe { voidptr(data) }, page, C.PROT_READ) == 0
	mut scene := unsafe { &TaskScenario(C.__builtin_alloca(sizeof(TaskScenario))) }
	unsafe { *scene = TaskScenario{ tag: 0x1234, api: api, kind: kind, leftover: leftover } }
	if kind == 4 {
		$if macos { if api.native {
			domain := C.CFStringCreateWithCString(unsafe { nil }, c'VinixTaskErrorFixture', 0x08000100)
			scene.error_value = u64(C.CFErrorCreate(unsafe { nil }, domain, -7, unsafe { nil }))
			C.CFRelease(domain)
		} }
		if !api.native {
			scene.error_value = objc_allocate(cf_error_type_id())
			mut header := obj_header(scene.error_value)
			header.number = -7; header.fields[0] = owned_string('VinixTaskErrorFixture')
		}
		assert scene.error_value != 0
	}
	closure := if consumed { u64(scene) } else { api.heap_allocate(heap_metadata, 32, 15) }
	if !consumed { unsafe { *(&u64(closure + 16)) = u64(scene) } }
	flags := u64(21) | (if kind == 0 { u64(0x4000) } else { u64(0) })
		| (if consumed { u64(0x8000) } else { u64(0) }) | if queued { u64(0x1000) } else { u64(0) }
	sign := unsafe { TaskDataSign(voidptr(code)) }
	entry := if api.native { sign(descriptor, if kind == 0 { u64(3848) } else { u64(29199) }) } else { descriptor }
	metadata := match kind { 1, 4 { api.integer } 2 { api.string } 3 { api.void_type } else { u64(0) } }
	options := if named { data + 64 } else { u64(0) }
	pair := api.create(flags, options, metadata, entry, closure)
	assert pair.task != 0 && pair.context != 0 && pair.task & 15 == 0 && pair.context & 15 == 0
	assert read64(read64(pair.task)) == 0x502 && read64(pair.task + 64) == pair.context && api.current() == 0
	if named {
		assert read32(pair.task + 32) & (u32(1) << 30) != 0
		assert ctext(read64(pair.task + 176)) == name && read64(pair.task + 184) == u64(name.len)
	}
	if !queued { api.retain(pair.task); api.run(pair.task, 0, 0) }
	if !api.native { swift_tasks_join() }
	for _ in 0 .. 100000 {
		if C.ios_load_pointer(unsafe { &u64(pair.task + 8) }) == 3 { break }
		C.sched_yield()
	}
	assert C.ios_load_pointer(unsafe { &u64(pair.task + 8) }) == 3
	assert C.ios_load_pointer(unsafe { &scene.calls }) == 1 && scene.owner == pair.task && scene.context == pair.context
	assert C.ios_load_pointer(unsafe { &scene.dropped }) == if consumed { u64(0) } else { u64(1) }
	if kind == 1 { assert read64(scene.result) == 0x123456789abcdef0 }
	if kind != 0 { assert read64(pair.task + 176 + if named { u64(16) } else { u64(0) }) & 3 == if kind == 4 { u64(2) } else { u64(1) } }
	api.release(pair.task)
	assert api.current() == 0
	assert C.munmap(unsafe { voidptr(data) }, page * 2) == 0
}

fn task_create_worker(api TaskCreateApi, code u64) {
	for i in 0 .. 24 { task_scenario(api, code, i % 4, true, true, false, false) }
}

fn task_create_protected(api TaskCreateApi, code u64) {
	page := usize(C.getpagesize())
	data := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert data != u64(-1)
	assert C.mprotect(unsafe { voidptr(data + u64(page)) }, page, C.PROT_NONE) == 0
	descriptor := data + u64(page) - 8
	body := code + (if api.native { u64(256) } else { u64(512) }) + 96
	delta := i64(body) - i64(descriptor)
	assert delta >= -2147483648 && delta <= 2147483647
	write32(descriptor, u32(i32(delta))); write32(descriptor + 4, 16)
	if !api.native {
		for flags in [u64(256), 512, 8192, 65536, u64(1) << 63]! {
			if _ := swift_task_create_checked(flags, 0, 0, descriptor, 0) { assert false }
		}
		for address in [u64(0), 1, 9, ~u64(0)]! {
			if _ := swift_task_create_checked(0x4000, 0, 0, address, 0) { assert false }
		}
		for size in [u32(0), 15, 17, 31]! {
			write32(descriptor + 4, size)
			if _ := swift_task_create_checked(0x4000, 0, 0, descriptor, 0) { assert false }
		}
		write32(descriptor + 4, 16)
		unsafe { *(&u64(data)) = 7; *(&u64(data + 8)) = data; *(&u64(data + 16)) = 0 }
		if _ := swift_task_create_checked(0x4000, data, 0, descriptor, 0) { assert false }
		unsafe { *(&u64(data)) = 1; *(&u64(data + 8)) = 0 }
		if _ := swift_task_create_checked(0x4000, data, 0, descriptor, 0) { assert false }
		unsafe { *(&u64(data)) = 0; *(&u64(data + 16)) = 42; *(&u64(data + 24)) = 0 }
		if _ := swift_task_create_checked(0x4000, data, 0, descriptor, 0) { assert false }
		if _ := swift_task_create_checked(0x4000, 0, 0, descriptor, data + u64(page)) { assert false }
		if _ := swift_task_run_checked(data + u64(page), 0, 0) { assert false }
		if _ := swift_task_complete_checked(data + u64(page), 0) { assert false }
		assert ios_runtime.swift_task_arena == 0 && ios_runtime.swift_task_count == 0 && !ios_runtime.swift_task_key_live
	}
	assert C.mprotect(unsafe { voidptr(data) }, page, C.PROT_READ) == 0
	sign := unsafe { TaskDataSign(voidptr(code)) }
	entry := if api.native { sign(descriptor, 3848) } else { descriptor }
	// The consumed context is an unreadable opaque value, not a heap owner.
	pair := api.create(0xc000, 0, 0, entry, data + u64(page))
	if !api.native {
		if _ := swift_tasks_drain_checked() { assert false }
		if _ := swift_task_refs(pair.task, -1) { assert false }
		if _ := swift_task_run_checked(pair.task, 1, 0) { assert false }
		assert read64(pair.task + 8) == 3 && unsafe { (&SwiftTaskState(pair.task + 80)).phase } == 0
	}
	api.retain(pair.task); api.run(pair.task, 0, 0)
	assert read64(pair.task + 8) == 3 && api.current() == 0
	if !api.native { if _ := swift_task_run_checked(pair.task, 0, 0) { assert false } }
	api.release(pair.task)
	if !api.native { if _ := swift_task_refs(pair.task, -1) { assert false }; swift_tasks_drain_checked() or { panic(err) } }
	assert C.munmap(unsafe { voidptr(data) }, page * 2) == 0
}

fn test_swift_task_create() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	task_scenario_emit(code)
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 792) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		api := task_create_api(true)
		task_create_protected(api, code)
		for kind in 0 .. 4 { for consumed in [false, true]! { task_scenario(api, code, kind, false, consumed, false, false) } }
		for kind in 0 .. 5 { task_scenario(api, code, kind, true, true, false, false) }
		println('IOS-SWIFT-TASK-CREATE-NATIVE: real discarded/Int/String/Void future tasks, two-word return, guarded signed descriptor, explicit job run and real enqueue, current task and private nested allocations, opaque consumed versus transferred heap closure, closure release before TLS clear, initialized result lifetime and task destruction')
	}
	if _ := swift_task_create_symbol('_swift_task_create') { assert false }
	for _ in 0 .. 2 {
		objc_start()
		system_data_start() or { panic(err) }
		api := task_create_api(false)
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn task_create_resolve_worker() }
		for entry in resolvers.wait() { assert entry == u64(voidptr(swift_task_create)) }
		assert ios_runtime.swift_task_arena == 0 && api.current() == 0
		task_create_protected(api, code)
		fallback := api.allocate(64)
		unsafe { *(&u64(fallback)) = 0xfeedbeef }
		for kind in 0 .. 4 { for consumed in [false, true]! { task_scenario(api, code, kind, false, consumed, false, false) } }
		for kind in 0 .. 5 { task_scenario(api, code, kind, true, false, true, false) }
		task_scenario(api, code, 1, false, true, false, true)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn task_create_worker(api, code) }
		workers.wait(); swift_tasks_join()
		swift_tasks_drain_checked() or { panic(err) }
		assert ios_runtime.swift_task_alloc_top == fallback - 16 && ios_runtime.swift_task_alloc_count == 1 && read64(fallback) == 0xfeedbeef
		api.deallocate(fallback)
		assert ios_runtime.swift_task_alloc_top == 0 && ios_runtime.swift_task_alloc_count == 0
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_strings.len == 0
		objc_stop()
		system_data_stop()
		assert ios_runtime.swift_task_arena == 0 && !ios_runtime.swift_task_key_live && ios_runtime.swift_task_sync == 0
		if _ := swift_task_create_symbol('_swift_task_create') { assert false }
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-TASK-CREATE: real creation/run/enqueue/completion, task-private allocators and fallback isolation, typed result destruction, consumed opaque and transferred closure ownership with unlocked reentrant destructor, named options, eight resolvers/workers and two drained lifetimes; custom executors, structured tasks and async suspension remain unsupported')
}
