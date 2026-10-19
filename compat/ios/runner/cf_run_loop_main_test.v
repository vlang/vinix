// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	#define dispatch_sync vinix_native_header_dispatch_sync
	#include <CoreFoundation/CFRunLoop.h>
	#undef dispatch_sync
	#include <objc/runtime.h>
	#include <dlfcn.h>
	fn C.CFRunLoopGetMain() voidptr
	fn C.CFRunLoopGetCurrent() voidptr
	fn C.CFRetain(voidptr) voidptr
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.dlsym(voidptr, &char) voidptr
}

type RunLoopMainCall = fn () u64
type RunLoopMainKeep = fn (u64) u64
type RunLoopMainDrop = fn (u64)
type RunLoopMainSend = fn (u64, u64, u64, u64) u64
type RunLoopMainNativeSend = fn (u64, u64) u64
type RunLoopMainProbe = fn (u64, u64, &u64)

struct RunLoopMainGate {
mut:
	ready i64
	go u64
}

fn run_loop_main_message(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { RunLoopMainSend(voidptr(C.ios_objc_builtin))(object, objc_selector(selector), a, b) }
}

fn run_loop_main_native_message(object u64, selector &char) u64 {
	$if macos {
		return unsafe { RunLoopMainNativeSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(object, u64(C.sel_registerName(selector))) }
	}
	return 0
}

fn run_loop_main_native() u64 {
	$if macos { return u64(C.CFRunLoopGetMain()) }
	return 0
}

fn run_loop_main_probe_emit(code u64) {
	// Call with protected x0–x8 pointers and preserve x20/x21 canaries.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0003e2, 0xaa0003e3, 0xaa0003e4, 0xaa0003e5, 0xaa0003e6,
		0xaa0003e7, 0xaa0003e8, 0xaa0003f4, 0xd2824695, 0xd63f0200, 0xa9000660,
		0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn run_loop_main_raw(entry u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { RunLoopMainProbe(voidptr(code))(entry, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn run_loop_main_worker(entry u64, gate &RunLoopMainGate, native bool) u64 {
	C.ios_ref_change(unsafe { &gate.ready }, 1)
	for C.ios_load_pointer(unsafe { &gate.go }) == 0 { time.sleep(time.microsecond) }
	get := unsafe { RunLoopMainCall(voidptr(entry)) }
	mut first := u64(0)
	for _ in 0 .. 100 {
		if native {
			$if macos {
				pool := C.objc_autoreleasePoolPush()
				value := get()
				if first == 0 { first = value }
				assert first != 0 && value == first && u64(C.CFRunLoopGetCurrent()) != first
				wrapper := run_loop_main_native_message(u64(C.objc_getClass(c'NSRunLoop')), c'mainRunLoop')
				assert run_loop_main_native_message(wrapper, c'getCFRunLoop') == first
				assert C.CFRetain(voidptr(first)) == voidptr(first)
				C.CFRelease(voidptr(first))
				C.objc_autoreleasePoolPop(pool)
			}
		} else {
			pool := objc_pool_push()
			value := get()
			if first == 0 { first = value }
			assert first != 0 && value == first && u64(C.pthread_self()) != ios_runtime.main_thread
			assert run_loop_main_message(ios_runtime.names['NSRunLoop'], c'mainRunLoop', 0, 0) == first
			assert run_loop_main_message(first, c'getCFRunLoop', 0, 0) == first
			assert objc_pool().objects.len == 0
			objc_pool_pop(pool)
		}
	}
	return first
}

fn run_loop_main_threads(entry u64, native bool) u64 {
	mut gate := RunLoopMainGate{}
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn run_loop_main_worker(entry, unsafe { &gate }, native) }
	for C.ios_load_pointer(unsafe { &u64(&gate.ready) }) != 8 { time.sleep(time.microsecond) }
	C.ios_store_pointer(unsafe { &gate.go }, 1)
	values := workers.wait()
	first := values[0]
	for value in values { assert value == first }
	unsafe { workers.free(); values.free() }
	return first
}

fn run_loop_main_tick(target u64, selector &char, link u64) {
	assert u64(C.pthread_self()) == ios_runtime.main_thread
	assert obj_header(link).fields[1] == cf_run_loop_get_main()
	mut header := obj_header(target)
	header.number++
}

fn run_loop_main_display_link(loop u64) {
	objc_record_method(ios_runtime.names['NSObject'], c'vinixRunLoopMainTick:', u64(unsafe { voidptr(run_loop_main_tick) }), c'v@:@', false)
	pool := objc_pool_push()
	target := objc_new(ios_runtime.names['NSObject'])
	link := run_loop_main_message(ios_runtime.names['CADisplayLink'], c'displayLinkWithTarget:selector:', target, objc_selector(c'vinixRunLoopMainTick:'))
	mode := owned_string('kCFRunLoopDefaultMode')
	run_loop_main_message(link, c'addToRunLoop:forMode:', loop, mode)
	assert obj_header(loop).refs == 2 && ios_runtime.display_links.len == 1
	assert display_links_fire() && obj_header(target).number == 1
	run_loop_main_message(link, c'removeFromRunLoop:forMode:', loop, mode)
	assert !display_links_fire() && obj_header(target).number == 1 && obj_header(loop).refs == 1
	run_loop_main_message(link, c'addToRunLoop:forMode:', loop, mode)
	run_loop_main_message(link, c'invalidate', 0, 0)
	assert !display_links_fire() && ios_runtime.display_links.len == 0 && obj_header(loop).refs == 1
	objc_release(mode); objc_release(target); objc_pool_pop(pool)
}

fn test_cf_run_loop_main() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page * 2) == 0 }
	run_loop_main_probe_emit(u64(code))
	C.__builtin___clear_cache(code, voidptr(u64(code) + 88))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		first := run_loop_main_threads(u64(unsafe { voidptr(run_loop_main_native) }), true)
		assert first == run_loop_main_raw(u64(unsafe { voidptr(run_loop_main_native) }), u64(code), guard)
		pool := C.objc_autoreleasePoolPush()
		assert u64(C.CFRunLoopGetCurrent()) == first
		wrapper := run_loop_main_native_message(u64(C.objc_getClass(c'NSRunLoop')), c'currentRunLoop')
		assert run_loop_main_native_message(wrapper, c'getCFRunLoop') == first
		C.objc_autoreleasePoolPop(pool)
		assert run_loop_main_native() == first
		println('NATIVE-CF-RUN-LOOP-MAIN: stable borrowed main loop across eight workers, main/current distinction, NSRunLoop getCFRunLoop, balanced retain/release, pool independence and protected no-argument ABI')
	}
	for iteration in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFRunLoopGetMain') or { panic(err) }
		get := unsafe { RunLoopMainCall(voidptr(entry)) }
		keep := unsafe { RunLoopMainKeep(voidptr(runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFRetain') or { panic(err) })) }
		drop := unsafe { RunLoopMainDrop(voidptr(runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFRelease') or { panic(err) })) }
		assert ios_runtime.run_loop == 0 && ios_runtime.live == 0
		first := if iteration == 0 { run_loop_main_threads(entry, false) } else { run_loop_main_message(ios_runtime.names['NSRunLoop'], c'currentRunLoop', 0, 0) }
		assert first == get() && first == run_loop_main_raw(entry, u64(code), guard)
		assert first == ios_runtime.run_loop && obj_header(first).refs == 1 && ios_runtime.live == 1
		assert first == run_loop_main_message(ios_runtime.names['NSRunLoop'], c'mainRunLoop', 0, 0)
		assert first == run_loop_main_message(ios_runtime.names['NSRunLoop'], c'currentRunLoop', 0, 0)
		assert first == run_loop_main_message(first, c'getCFRunLoop', 0, 0)
		pool := objc_pool_push()
		for _ in 0 .. 1000 { assert get() == first }
		assert obj_header(first).refs == 1 && objc_pool().objects.len == 0
		assert keep(first) == first && obj_header(first).refs == 2
		objc_pool_pop(pool)
		assert get() == first && obj_header(first).refs == 2
		drop(first)
		run_loop_main_display_link(first)
		assert ios_runtime.live == 1 && obj_header(first).refs == 1
		assert run_loop_main_threads(entry, false) == first
		assert ios_runtime.live == 1 && obj_header(first).refs == 1
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFRunLoopGetMain') { assert false }
		}
		mut weak := u64(0)
		objc_store_weak(unsafe { &weak }, first)
		objc_stop()
		assert weak == 0 && ios_runtime.swift_concurrency_retired && ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-CF-RUN-LOOP-MAIN: scoped no-argument borrowed ABI, protected x0–x8, preserved x20/x21, synchronized worker-first publication, shared Foundation handle, main-thread display-link schedule/fire/remove/invalidate, balanced caller references, no per-call objects/autoreleases and two released runtime caches')
}
