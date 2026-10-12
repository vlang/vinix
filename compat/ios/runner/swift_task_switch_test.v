// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type SwitchCreate = fn (u64, u64, u64, u64, u64) SwiftTaskPair
type SwitchJob = fn (u64, u64, u64)
type SwitchCurrent = fn () u64
type SwitchRetain = fn (u64) u64
type SwitchRelease = fn (u64)
type SwitchSign = fn (u64, u64) u64
struct SwitchApi {
	native bool
	create SwitchCreate
	run SwitchJob
	current SwitchCurrent
	retain SwitchRetain
	release SwitchRelease
	allocate SwitchRetain
	deallocate SwitchRelease
	entry u64
	integer u64
}
struct SwitchScene {
mut:
	api SwitchApi
	body u64
	owner u64
	initial u64
	resume u64
	result u64
	first u64
	second u64
	stack u64
	calls u64
	limit u64
	protected u64
	no_caller bool
}

fn switch_prepare(context u64, self u64, error_word u64, stack u64, result u64) SwiftTaskPair {
	mut scene := unsafe { &SwitchScene(self) }
	assert error_word == 0
	scene.owner = scene.api.current(); scene.initial = context; scene.stack = stack
	scene.result = result; scene.resume = read64(scene.owner + 56)
	assert scene.owner != 0 && read64(scene.owner + 64) == context
	if !scene.api.native {
		for executor in [SwiftTaskPair{ task: context, context: 0 }, SwiftTaskPair{ task: 0, context: context }]! {
			if _ := swift_task_switch_checked(context, scene.body, executor.task, executor.context) { assert false }
		}
		for address in [u64(0), 1, 9, ~u64(0)]! {
			if _ := swift_task_switch_checked(address, scene.body, 0, 0) { assert false }
			if _ := swift_task_switch_checked(context, address, 0, 0) { assert false }
		}
		mut state := unsafe { &SwiftTaskState(scene.owner + 80) }
		state.phase = 4
		if _ := swift_task_switch_checked(context, scene.body, 0, 0) { assert false }
		state.phase = 2
		assert C.pthread_setspecific(ios_runtime.swift_task_key, unsafe { voidptr(scene.protected) }) == 0
		if _ := swift_task_switch_checked(context, scene.body, 0, 0) { assert false }
		assert C.pthread_setspecific(ios_runtime.swift_task_key, unsafe { voidptr(scene.owner) }) == 0
		assert read64(scene.owner + 56) == scene.resume && read64(scene.owner + 64) == context
	}
	scene.first = scene.api.allocate(64); scene.second = scene.api.allocate(64)
	for frame in [scene.first, scene.second]! {
		unsafe { *(&u64(frame)) = context; *(&u64(frame + 8)) = read64(context + 8)
			*(&u64(frame + 16)) = self; *(&u64(frame + 24)) = 0x123456789abcdef0 }
	}
	return SwiftTaskPair{ task: if scene.limit == 1 { scene.protected } else { scene.first }, context: scene.body }
}
fn switch_resume(context u64, error_word u64, stack u64) SwiftTaskPair {
	mut scene := unsafe { &SwitchScene(read64(context + 16)) }
	assert scene.api.current() == scene.owner && error_word == 0
	assert context == if scene.calls & 1 == 0 { scene.first } else { scene.second }
	assert stack == scene.stack // Tail resumption cannot accumulate C stack frames.
	assert read64(context) == scene.initial && read64(context + 24) == 0x123456789abcdef0
	assert read64(scene.owner + 56) == scene.resume && read64(scene.owner + 64) == scene.initial
	assert C.ios_load_pointer(unsafe { &u64(scene.owner + 8) }) == if scene.no_caller { u64(3) } else { u64(0x200000003) }
	if !scene.api.native {
		assert unsafe { (&SwiftTaskState(scene.owner + 80)).phase } == 2
		assert ios_runtime.swift_task_alloc_top != scene.first - 16
	}
	scene.calls++
	if scene.calls == scene.limit {
		if scene.result != 0 { unsafe { *(&u64(scene.result)) = 0x76543210fedcba98 } }
		completion := read64(scene.initial + 8)
		scene.api.deallocate(scene.second); scene.api.deallocate(scene.first)
		return SwiftTaskPair{ task: scene.initial, context: completion }
	}
	return SwiftTaskPair{ task: if scene.calls & 1 == 0 { scene.first } else { scene.second }, context: scene.body }
}

fn switch_protected_resume(owner u64, context u64, stack u64) SwiftTaskPair {
	initial := read64(owner + 64)
	mut scene := unsafe { &SwitchScene(read64(initial - 16)) }
	assert scene.api.current() == owner && scene.owner == owner
	assert context == scene.protected && stack + 16 == scene.stack
	assert read64(owner + 56) == scene.resume && read64(owner + 64) == scene.initial
	scene.calls++
	if scene.result != 0 { unsafe { *(&u64(scene.result)) = 0x76543210fedcba98 } }
	completion := read64(initial + 8)
	scene.api.deallocate(scene.second); scene.api.deallocate(scene.first)
	return SwiftTaskPair{ task: initial, context: completion }
}

fn switch_emit(code u64, api SwitchApi) {
	write32(code, 0xdac10820); write32(code + 4, 0xd65f03c0) // Native descriptor PACDA.
	// Initial async body -> ordinary observer -> tail switch (x22, x0, x1/x2).
	for i, instruction in [u32(0xa9bf7bfd), 0xaa0003e4, 0xaa1603e0, 0xaa1403e1,
		0xaa1503e2, 0x910003e3, 0x58000190, 0xd63f0200, 0xa8c17bfd,
		0xaa0003f6, 0xaa0103e0, if api.native { u32(0xdac123e0) } else { u32(0xd503201f) },
		0xd2800001, 0xd2800002, 0x58000050, 0xd61f0200]! { write32(code + 64 + u64(i * 4), instruction) }
	unsafe { *(&u64(code + 128)) = api.entry; *(&u64(code + 136)) = u64(voidptr(switch_prepare)) }
	// Continuation -> observer -> another switch, or final initial completion.
	for i, instruction in [u32(0xa9bf7bfd), 0xaa1603e0, 0xaa1503e1, 0x910003e2,
		0x580002d0, 0xd63f0200, 0xa8c17bfd, 0xaa0003f6, 0xaa0103e0,
		0xf94002c8, 0xb40000c8, if api.native { u32(0xdac123e0) } else { u32(0xd503201f) },
		0xd2800001, 0xd2800002, 0x58000150, 0xd61f0200,
		0xd2800014, 0xd2800015, 0xaa0003f0,
		if api.native { u32(0xdac143f0) } else { u32(0xd503201f) }, 0xd61f0200]! { write32(code + 192 + u64(i * 4), instruction) }
	unsafe { *(&u64(code + 288)) = api.entry; *(&u64(code + 296)) = u64(voidptr(switch_resume)) }
	// Opaque protected context: obtain the scene from current task, never x22.
	for i, instruction in [u32(0xa9be7bf3), 0xf9000bf6, 0x58000250, 0xd63f0200,
		0xf9400be1, 0x910003e2, 0x58000210, 0xd63f0200, 0xa8c27bf3,
		0xaa0003f6, 0xaa0103f0, 0xd2800014, 0xd2800015,
		if api.native { u32(0xdac143f0) } else { u32(0xd503201f) }, 0xd61f0200]! { write32(code + 320 + u64(i * 4), instruction) }
	unsafe { *(&u64(code + 400)) = u64(voidptr(api.current)); *(&u64(code + 408)) = u64(voidptr(switch_protected_resume)) }
}

fn switch_api(native bool) SwitchApi {
	mut concurrency := unsafe { voidptr(nil) }; mut core := unsafe { voidptr(nil) }
	$if macos { if native {
		concurrency = C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib', C.RTLD_NOW)
		core = C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert concurrency != unsafe { nil } && core != unsafe { nil }
	} }
	mut entries := [9]u64{}
	for i, name in ['_swift_task_create', '_swift_job_run', '_swift_task_getCurrent', '_swift_retain', '_swift_release',
		'_swift_task_alloc', '_swift_task_dealloc', '_swift_task_switch', '_$sSiN']! {
		is_concurrency := i < 3 || i == 5 || i == 6 || i == 7
		if native { entries[i] = u64(C.dlsym(if is_concurrency { concurrency } else { core }, name[1..].str)) }
		else { entries[i] = runtime_symbol('/usr/lib/swift/' + if is_concurrency { 'libswift_Concurrency.dylib' } else { 'libswiftCore.dylib' }, name) or { panic(err) } }
		assert entries[i] != 0, name
	}
	return SwitchApi{ native: native, create: unsafe { SwitchCreate(voidptr(entries[0])) },
		run: unsafe { SwitchJob(voidptr(entries[1])) }, current: unsafe { SwitchCurrent(voidptr(entries[2])) },
		retain: unsafe { SwitchRetain(voidptr(entries[3])) }, release: unsafe { SwitchRelease(voidptr(entries[4])) },
		allocate: unsafe { SwitchRetain(voidptr(entries[5])) }, deallocate: unsafe { SwitchRelease(voidptr(entries[6])) },
		entry: entries[7], integer: entries[8] }
}

fn switch_scenario(api SwitchApi, code u64, descriptor u64, future bool, queued bool, limit u64, no_caller bool) {
	mut scene := unsafe { &SwitchScene(C.__builtin_alloca(sizeof(SwitchScene))) }
	unsafe { *scene = SwitchScene{ api: api, body: code + if limit == 1 { u64(320) } else { u64(192) },
		limit: limit, protected: descriptor + 8, no_caller: no_caller } }
	sign := unsafe { SwitchSign(voidptr(code)) }
	flags := u64(21) | 0x8000 | (if future { u64(0) } else { u64(0x4000) }) | if queued { u64(0x1000) } else { u64(0) }
	entry := if api.native { sign(descriptor, if future { u64(29199) } else { u64(3848) }) } else { descriptor }
	metadata := if future { api.integer } else { u64(0) }
	pair := api.create(flags, 0, metadata, entry, u64(scene))
	if !queued {
		api.retain(pair.task)
		if no_caller { api.release(pair.task) }
		api.run(pair.task, 0, 0)
	}
	if !api.native { swift_tasks_join() }
	if no_caller {
		assert !queued && scene.calls == limit && api.current() == 0
		return // Completion released the final reference; no task/result read.
	}
	for _ in 0 .. 100000 { if C.ios_load_pointer(unsafe { &u64(pair.task + 8) }) == 3 { break }; C.sched_yield() }
	assert C.ios_load_pointer(unsafe { &u64(pair.task + 8) }) == 3
	assert scene.owner == pair.task && scene.initial == pair.context && scene.calls == limit
	if future { assert read64(scene.result) == 0x76543210fedcba98 && read64(pair.task + 176) & 3 == 1 }
	api.release(pair.task)
	assert api.current() == 0
}
fn switch_worker(api SwitchApi, code u64, descriptor u64) {
	for i in 0 .. 12 { switch_scenario(api, code, descriptor, i & 1 == 0, true, 256, false) }
}
fn switch_suite(native bool) {
	api := switch_api(native)
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	data := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && data != u64(-1)
	switch_emit(code, api)
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 416) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	descriptor := data + u64(page) - 8
	delta := i64(code + 64) - i64(descriptor); assert delta >= -2147483648 && delta <= 2147483647
	write32(descriptor, u32(i32(delta))); write32(descriptor + 4, 64)
	assert C.mprotect(unsafe { voidptr(data) }, page, C.PROT_READ) == 0
	assert C.mprotect(unsafe { voidptr(data + u64(page)) }, page, C.PROT_NONE) == 0
	if !native { if _ := swift_task_switch_checked(data + u64(page), code + 192, 0, 0) { assert false } }
	for future in [false, true]! { for queued in [false, true]! {
		switch_scenario(api, code, descriptor, future, queued, 100000, false)
		switch_scenario(api, code, descriptor, future, queued, 1, false)
	} }
	switch_scenario(api, code, descriptor, false, false, 256, true)
	switch_scenario(api, code, descriptor, true, false, 256, true)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn switch_worker(api, code, descriptor) }
	workers.wait()
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	assert C.munmap(unsafe { voidptr(data) }, page * 2) == 0
}
fn test_swift_task_switch() {
	$if macos {
		switch_suite(true)
		println('IOS-SWIFT-TASK-SWITCH-NATIVE: immediate generic executor tail resumption, unchanged saved entry/context and execution references, alternating task-private frames and opaque protected context, 100000 switches with constant C stack, discarded and Int futures, completion frees final task, manual and queued jobs, eight concurrent workers')
	}
	$if ios_native_task_switch_measure ? { return }
	if _ := swift_task_switch_checked(8, 4, 0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start(); system_data_start() or { panic(err) }
		fallback := swift_task_allocate(64)
		unsafe { *(&u64(fallback)) = 0xfeedbeef }
		switch_suite(false); swift_tasks_join(); swift_tasks_drain_checked() or { panic(err) }
		assert ios_runtime.swift_task_alloc_top == fallback - 16 && read64(fallback) == 0xfeedbeef
		swift_task_deallocate(fallback)
		objc_stop(); system_data_stop()
		assert ios_runtime.swift_task_arena == 0 && !ios_runtime.swift_task_key_live && ios_runtime.swift_task_sync == 0
		if _ := swift_task_switch_checked(8, 4, 0, 0) { assert false }
	}
	println('IOS-SWIFT-TASK-SWITCH: real current-task generic tail continuations, alternate frames and opaque protected contexts, constant stack, unchanged saved resume fields and execution ownership, completion can free final task, typed completion, allocator isolation, rejected nonrunning/foreign/invalid continuations and custom executors, eight workers and two drained lifetimes')
}
