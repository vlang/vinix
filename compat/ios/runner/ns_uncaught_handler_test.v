// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type HandlerSet = fn (u64)
type HandlerGet = fn () u64
type HandlerProbe = fn (u64, u64, u64, &u64)
struct HandlerApi { set u64 get u64 }
fn (api HandlerApi) store(value u64) { unsafe { HandlerSet(voidptr(api.set))(value) } }
fn (api HandlerApi) load() u64 { return unsafe { HandlerGet(voidptr(api.get))() } }
fn handler_first(_ u64) { panic('exception registration invoked the first callback') }
fn handler_second(_ u64) { panic('exception registration invoked the second callback') }
struct HandlerHandshake {
mut:
	api HandlerApi
	ready i64
	proceed i64
	a u64
	b u64
}
fn handler_wait(slot &i64, value i64) {
	deadline := time.sys_mono_now() + 10 * time.second
	for C.ios_ref_change(slot, 0) != value { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
}
fn handler_worker(state &HandlerHandshake) {
	assert state.api.load() == state.a
	C.ios_ref_change(unsafe { &state.ready }, 1)
	handler_wait(unsafe { &state.proceed }, 1)
	state.api.store(state.b)
	C.ios_ref_change(unsafe { &state.ready }, 1)
	handler_wait(unsafe { &state.proceed }, 2)
	assert state.api.load() == state.a
	state.api.store(0)
	C.ios_ref_change(unsafe { &state.ready }, 1)
	handler_wait(unsafe { &state.proceed }, 3)
	assert state.api.load() == state.b
}
fn handler_fresh(api HandlerApi, value u64) { assert api.load() == value }
fn handler_stress(api HandlerApi, a u64, b u64) {
	for i in 0 .. 128 {
		api.store(if i % 2 == 0 { a } else { b })
		assert api.load() in [a, b]!
	}
}
fn handler_cases(api HandlerApi, code u64, guard u64) {
	saved := api.load()
	defer { api.store(saved) }
	a := u64(unsafe { voidptr(handler_first) }); b := u64(unsafe { voidptr(handler_second) })
	for value in [u64(0), a, b, a, guard, u64(0)]! {
		// The stored pointer is borrowed and opaque, even for inaccessible memory.
		api.store(value); assert api.load() == value
		mut capture := [u64(0xcafe), 0, 0, 0, 0xbeef]!
		unsafe { HandlerProbe(voidptr(code))(api.get, guard, guard, &capture[1]) }
		assert capture[0] == 0xcafe && capture[1] == value && capture[2] == guard && capture[3] == 0x1234 && capture[4] == 0xbeef
		unsafe { HandlerProbe(voidptr(code))(api.set, value, guard, &capture[1]) }
		assert api.load() == value && capture[0] == 0xcafe && capture[2] == guard && capture[3] == 0x1234 && capture[4] == 0xbeef
	}
	for _ in 0 .. 16 {
		api.store(a)
		state := unsafe { &HandlerHandshake(C.calloc(1, sizeof(HandlerHandshake))) }
		unsafe { *state = HandlerHandshake{api: api, a: a, b: b} }
		worker := spawn handler_worker(state)
		handler_wait(unsafe { &state.ready }, 1)
		C.ios_ref_change(unsafe { &state.proceed }, 1)
		handler_wait(unsafe { &state.ready }, 2)
		assert api.load() == b
		api.store(a); C.ios_ref_change(unsafe { &state.proceed }, 1)
		handler_wait(unsafe { &state.ready }, 3)
		assert api.load() == 0
		api.store(b); C.ios_ref_change(unsafe { &state.proceed }, 1)
		worker.wait(); C.free(state)
		assert api.load() == b
		fresh := spawn handler_fresh(api, b); fresh.wait()
	}
	api.store(a)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn handler_stress(api, a, b) }
	workers.wait(); unsafe { workers.free() }
}
fn test_uncaught_handler_registration() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != voidptr(-1)
	defer { assert C.munmap(code, page * 2) == 0 }
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1, 0xaa0203e8, 0xaa0203f4, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5, 0xaa0203e6, 0xaa0203e7, 0xd2824695, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	C.__builtin___clear_cache(code, voidptr(u64(code) + 88))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(u64(code) + u64(page)), page, C.PROT_NONE) == 0
	guard := u64(code) + u64(page)
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		api := HandlerApi{u64(C.dlsym(foundation, c'NSSetUncaughtExceptionHandler')), u64(C.dlsym(foundation, c'NSGetUncaughtExceptionHandler'))}
		assert api.set != 0 && api.get != 0
		handler_cases(api, u64(code), guard)
		println('IOS-UNCAUGHT-HANDLER-NATIVE: nullable borrowed C callbacks, guarded setter/getter ABI, process-wide cross-thread replacement/clear, worker exit persistence and concurrent updates; no callback invoked')
	}
	assert ns_get_uncaught_handler() == 0 && !ns_set_uncaught_handler_checked(guard)
	for _ in 0 .. 2 {
		objc_start()
		api := HandlerApi{runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_NSSetUncaughtExceptionHandler') or { panic(err) }, runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_NSGetUncaughtExceptionHandler') or { panic(err) }}
		assert api.load() == 0
		for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { for symbol in ['_NSSetUncaughtExceptionHandler', '_NSGetUncaughtExceptionHandler']! { if _ := runtime_symbol(library, symbol) { assert false } } }
		handler_cases(api, u64(code), guard)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		api.store(guard)
		objc_stop()
		assert ios_runtime.uncaught_exception_handler == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert ns_get_uncaught_handler() == 0 && !ns_set_uncaught_handler_checked(guard)
	}
	println('IOS-UNCAUGHT-HANDLER: Foundation-only exports, borrowed pointer registration, synchronized global visibility, no callback/object ownership, 1024 contended updates, lifecycle rejection and two cleared runtimes')
}
