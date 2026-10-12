// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFDate.h>
}

#include <dlfcn.h>

fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int
fn C.CFDateCreate(voidptr, f64) voidptr
fn C.CFRelease(voidptr)

type ConditionSend = fn (u64, u64, u64) u64
type ConditionPush = fn () u64
type ConditionPop = fn (u64)

struct ConditionApi {
	native          bool
	send            u64
	push            u64
	pop             u64
	condition_class u64
	string_class    u64
	root_class      u64
}

struct ConditionState {
mut:
	ready i64
	woken i64
	value i64
}

fn (api ConditionApi) message(object u64, name &char, argument u64) u64 {
	mut selector := u64(name)
	$if macos {
		if api.native { selector = u64(C.sel_registerName(name)) }
	}
	return unsafe { ConditionSend(voidptr(api.send))(object, selector, argument) }
}

fn (api ConditionApi) pool() u64 {
	$if macos {
		if api.native { return unsafe { ConditionPush(voidptr(api.push))() } }
	}
	return objc_pool_push()
}

fn (api ConditionApi) drain(pool u64) {
	$if macos {
		if api.native {
			unsafe { ConditionPop(voidptr(api.pop))(pool) }
			return
		}
	}
	objc_pool_pop(pool)
}

fn (api ConditionApi) date(interval f64) u64 {
	absolute := f64(dispatch_wall_now_ns()) / 1e9 - 978307200 + interval
	$if macos {
		if api.native { return u64(C.CFDateCreate(unsafe { nil }, absolute)) }
	}
	return cf_date_create(0, absolute)
}

fn (api ConditionApi) release_date(date u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(date))
			return
		}
	}
	objc_release(date)
}

fn condition_wait_count(slot &i64, expected i64) {
	deadline := time.sys_mono_now() + 10 * time.second
	for C.ios_ref_change(slot, 0) != expected {
		assert time.sys_mono_now() < deadline, 'condition handshake timed out'
		time.sleep(time.millisecond)
	}
}

fn condition_waiter(api ConditionApi, object u64, state &ConditionState, date u64) {
	api.message(object, c'lock', 0)
	C.ios_ref_change(unsafe { &state.ready }, 1)
	for C.ios_ref_change(unsafe { &state.value }, 0) == 0 {
		if date == 0 {
			api.message(object, c'wait', 0)
		} else {
			assert api.message(object, c'waitUntilDate:', date) == 1
		}
	}
	C.ios_ref_change(unsafe { &state.woken }, 1)
	api.message(object, c'unlock', 0)
}

fn condition_lock_probe(api ConditionApi, object u64, state &ConditionState) {
	C.ios_ref_change(unsafe { &state.ready }, 1)
	api.message(object, c'lock', 0)
	C.ios_ref_change(unsafe { &state.woken }, 1)
	api.message(object, c'unlock', 0)
}

fn condition_cases(api ConditionApi) {
	pool := api.pool()
	for _ in 0 .. 100 {
		object := api.message(api.condition_class, c'new', 0)
		assert object != 0 && api.message(object, c'name', 0) == 0
		assert read64(object + 8) == 0x4d55545a && read64(object + 72) == 0x434f4e44
		name := api.message(api.string_class, c'stringWithUTF8String:', u64(c'condition-nameabcdefghijklmnopqrstuvwxyz'))
		api.message(object, c'setName:', name)
		stored := api.message(object, c'name', 0)
		assert stored != 0 && read64(object + 120) == stored && ctext(api.message(stored, c'UTF8String', 0)) == 'condition-nameabcdefghijklmnopqrstuvwxyz'
		api.message(object, c'setName:', 0)
		assert api.message(object, c'name', 0) == 0
		api.message(object, c'signal', 0)
		api.message(object, c'broadcast', 0)
		api.message(object, c'lock', 0)
		api.message(object, c'unlock', 0)
		api.message(object, c'release', 0)
	}
	object := api.message(api.condition_class, c'new', 0)
	for _ in 0 .. 20 {
		state := unsafe { &ConditionState(C.calloc(1, sizeof(ConditionState))) }
		waiter := spawn condition_waiter(api, object, state, 0)
		condition_wait_count(unsafe { &state.ready }, 1)
		// The waiting message releases its mutex and the global runtime lock.
		other := api.message(api.root_class, c'new', 0)
		api.message(other, c'release', 0)
		api.message(object, c'lock', 0)
		C.ios_ref_change(unsafe { &state.value }, 1)
		api.message(object, c'signal', 0)
		api.message(object, c'unlock', 0)
		waiter.wait()
		assert state.woken == 1
		C.free(state)
	}
	state := unsafe { &ConditionState(C.calloc(1, sizeof(ConditionState))) }
	mut workers := []thread{cap: 8}
	workers.flags |= .noslices
	for _ in 0 .. 8 { workers << spawn condition_waiter(api, object, state, 0) }
	condition_wait_count(unsafe { &state.ready }, 8)
	api.message(object, c'lock', 0)
	C.ios_ref_change(unsafe { &state.value }, 1)
	api.message(object, c'broadcast', 0)
	api.message(object, c'unlock', 0)
	workers.wait()
	assert state.woken == 8
	unsafe { workers.free() }
	C.free(state)
	date := api.date(5)
	timed := unsafe { &ConditionState(C.calloc(1, sizeof(ConditionState))) }
	worker := spawn condition_waiter(api, object, timed, date)
	condition_wait_count(unsafe { &timed.ready }, 1)
	api.message(object, c'lock', 0)
	C.ios_ref_change(unsafe { &timed.value }, 1)
	api.message(object, c'signal', 0)
	api.message(object, c'unlock', 0)
	worker.wait()
	assert timed.woken == 1
	C.free(timed)
	api.release_date(date)
	api.message(object, c'lock', 0)
	for interval in [f64(-10), 0.01]! {
		deadline := api.date(interval)
		before := time.sys_mono_now()
		assert api.message(object, c'waitUntilDate:', deadline) == 0
		elapsed := time.sys_mono_now() - before
		assert elapsed < 2 * time.second
		if interval > 0 {
			assert elapsed >= 2 * time.millisecond
		}
		api.release_date(deadline)
	}
	assert api.message(object, c'waitUntilDate:', 0) == 0
	reacquire := unsafe { &ConditionState(C.calloc(1, sizeof(ConditionState))) }
	contender := spawn condition_lock_probe(api, object, reacquire)
	condition_wait_count(unsafe { &reacquire.ready }, 1)
	time.sleep(5 * time.millisecond)
	assert C.ios_ref_change(unsafe { &reacquire.woken }, 0) == 0
	api.message(object, c'unlock', 0)
	contender.wait()
	assert reacquire.woken == 1
	C.free(reacquire)
	api.message(object, c'release', 0)
	api.drain(pool)
}

fn test_condition_native_reference() {
	$if macos {
		library := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert library != unsafe { nil }
		api := ConditionApi{ native: true, send: u64(C.dlsym(library, c'objc_msgSend')), push: u64(C.dlsym(library, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(library, c'objc_autoreleasePoolPop')), condition_class: u64(C.objc_getClass(c'NSCondition')), string_class: u64(C.objc_getClass(c'NSString')), root_class: u64(C.objc_getClass(c'NSObject')) }
		assert C.class_getInstanceSize(voidptr(api.condition_class)) == 128
		condition_cases(api)
		assert C.dlclose(library) == 0
		println('IOS-CONDITION-NATIVE: 128-byte record, initialized signatures, copied names, mutex handoff, eight-waiter broadcast, signaled deadlines, expired/nil dates and reacquisition passed')
	}
}

fn test_condition_runtime_ownership_and_storage() {
	for _ in 0 .. 2 {
		objc_start()
		system_data_start()!
		cls := ios_runtime.names['NSCondition']
		assert sizeof(AbiNSCondition) == 128 && objc_class_size(cls) == 128
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSCondition') or { panic(err) } == cls
		for i, name in [c'm', c'c', c'n']! {
			assert objc_ivar_offset(objc_find_ivar(cls, name)) == [i64(8), 72, 120]![i]
		}
		method := objc_instance_method(cls, u64(c'waitUntilDate:'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'B24@0:8@16'
		api := ConditionApi{ send: u64(unsafe { voidptr(C.ios_objc_builtin) }), condition_class: cls, string_class: ios_runtime.names['NSString'], root_class: ios_runtime.names['NSObject'] }
		condition_cases(api)
		assert ios_runtime.live == 0 && system_data.mutexes.len == 0 && system_data.conditions.len == 0
		object := objc_allocate(cls)
		assert read64(object + 8) == 0 && read64(object + 72) == 0
		assert api.message(object, c'init', 0) == object
		assert system_data.mutexes.len == 1 && system_data.conditions.len == 1
		name := owned_string('owned-across-isa-change')
		api.message(object, c'setName:', name)
		objc_release(name)
		objc_set_class(object, api.root_class)
		objc_release(object)
		assert ios_runtime.live == 0 && system_data.mutexes.len == 0 && system_data.conditions.len == 0
		storage := u64(C.calloc(1, 128))
		assert storage != 0
		assert objc_construct_instance(cls, storage) == storage && read64(storage + 8) == 0
		api.message(storage, c'init', 0)
		assert objc_destruct_instance(storage) == storage && read64(storage + 8) == 0 && read64(storage + 72) == 0
		C.free(unsafe { voidptr(storage) })
		assert ios_runtime.live == 0 && system_data.mutexes.len == 0 && system_data.conditions.len == 0
		objc_stop()
		system_data_stop()
	}
	println('IOS-CONDITION: actual trampoline, native metadata, pthread registries, repeated quiescent release, class changes and caller-owned construct/destruct storage passed')
}

fn test_condition_invalid_inputs_are_explicit() {
	objc_start()
	system_data_start()!
	api := ConditionApi{ send: u64(unsafe { voidptr(C.ios_objc_builtin) }), condition_class: ios_runtime.names['NSCondition'] }
	uninitialized := objc_allocate(api.condition_class)
	object := objc_new(api.condition_class)
	wrong := objc_allocate(ios_runtime.names['NSNumber'])
	date := cf_date_create(0, 1e100)
	for operation in 0 .. 4 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0])
			assert C.dup2(descriptors[1], 2) == 2
			C.close(descriptors[1])
			match operation {
				0 { api.message(uninitialized, c'lock', 0) }
				1 { api.message(object, c'setName:', wrong) }
				2 { api.message(object, c'waitUntilDate:', wrong) }
				else { api.message(object, c'waitUntilDate:', date) }
			}
			C._exit(0)
		}
		C.close(descriptors[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(descriptors[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		expected := ['NSCondition is not initialized', 'NSCondition name must be a string',
			'unsupported CFDate object', 'NSCondition deadline is outside the finite clock profile']![operation]
		assert output.contains(expected) && !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(uninitialized)
	objc_release(object)
	objc_release(wrong)
	objc_release(date)
	assert ios_runtime.live == 0 && system_data.mutexes.len == 0 && system_data.conditions.len == 0
	objc_stop()
	system_data_stop()
	println('IOS-CONDITION-REJECT: uninitialized synchronization, non-string names, foreign dates and oversized deadlines fail explicitly without changing parent ownership')
}
