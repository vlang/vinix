// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
import sync.stdatomic

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFDate.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.CFDateCreate(voidptr, f64) voidptr
fn C.CFAbsoluteTimeGetCurrent() f64
fn C.CFRelease(voidptr)

type RecursiveLockSend = fn (u64, u64, u64) u64
struct RecursiveLockApi { native bool send u64 cls u64 strings u64 mutable_strings u64 root u64 }
struct RecursiveLockFixtureState { mut: ready i64 acquired i64 finish i64 result i64 }
fn (api RecursiveLockApi) message(object u64, name &char, argument u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { RecursiveLockSend(voidptr(api.send))(object, selector, argument) }
}
fn (api RecursiveLockApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	return objc_pool_push()
}
fn (api RecursiveLockApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn (api RecursiveLockApi) date(interval f64) u64 {
	$if macos { if api.native { return u64(C.CFDateCreate(unsafe { nil }, C.CFAbsoluteTimeGetCurrent() + interval)) } }
	return cf_date_create(0, f64(dispatch_wall_now_ns()) / 1e9 - 978307200 + interval)
}
fn (api RecursiveLockApi) release_date(date u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(date) }); return } }
	objc_release(date)
}
fn recursive_lock_wait(slot &i64, expected i64) {
	deadline := time.sys_mono_now() + 10 * time.second
	for stdatomic.load_i64(slot) != expected { assert time.sys_mono_now() < deadline, 'recursive lock handshake timed out'; time.sleep(time.millisecond) }
}
fn recursive_lock_contender(api RecursiveLockApi, object u64, state &RecursiveLockFixtureState, mode int, date u64) {
	stdatomic.store_i64(unsafe { &state.ready }, 1)
	result := if mode == 0 { api.message(object, c'tryLock', 0) }
		else if mode == 1 { api.message(object, c'lockBeforeDate:', date) }
		else { api.message(object, c'lock', 0); u64(1) }
	stdatomic.store_i64(unsafe { &state.result }, i64(result))
	if result == 1 {
		stdatomic.store_i64(unsafe { &state.acquired }, 1)
		if mode == 2 { recursive_lock_wait(unsafe { &state.finish }, 1) }
		api.message(object, c'unlock', 0)
	}
}
fn recursive_lock_shared(api RecursiveLockApi) {
	pool := api.pool()
	for construction in [c'alloc', c'new']! {
		object := api.message(api.cls, construction, 0)
		assert object != 0 && api.message(object, c'class', 0) == api.cls && api.message(object, c'name', 0) == 0
		if construction == c'alloc' {
			for offset in 8 .. 104 { assert unsafe { *(&u8(voidptr(object + u64(offset)))) } == 0 }
			assert api.message(object, c'init', 0) == object
		}
		assert read64(object + 8) == 0x4d555458 && read64(object + 72) == 0 && read64(object + 80) == 0
		api.message(object, c'release', 0)
	}
	for _ in 0 .. 32 {
		object := api.message(api.cls, c'new', 0)
		name := api.message(api.message(api.mutable_strings, c'alloc', 0), c'initWithUTF8String:', u64(c'recursive copied name with Unicode 😀'))
		api.message(object, c'setName:', name)
		stored := api.message(object, c'name', 0)
		assert stored != name && read64(object + 96) == stored
		assert ctext(api.message(stored, c'UTF8String', 0)) == 'recursive copied name with Unicode 😀'
		changed := api.message(api.strings, c'stringWithUTF8String:', u64(c'changed mutable name'))
		api.message(name, c'setString:', changed); api.message(name, c'release', 0)
		assert ctext(api.message(api.message(object, c'name', 0), c'UTF8String', 0)) == 'recursive copied name with Unicode 😀'
		api.message(object, c'setName:', stored)
		assert api.message(object, c'name', 0) == stored
		api.message(object, c'setName:', 0); assert api.message(object, c'name', 0) == 0
		api.message(object, c'release', 0)
	}
	object := api.message(api.cls, c'new', 0)
	for _ in 0 .. 16 {
		api.message(object, c'lock', 0)
		for depth in 2 .. 7 { assert api.message(object, c'tryLock', 0) == 1; assert read64(object + 80) == u64(depth) }
		assert read64(object + 72) != 0
		state := unsafe { &RecursiveLockFixtureState(C.calloc(1, sizeof(RecursiveLockFixtureState))) }
		worker := spawn recursive_lock_contender(api, object, state, 0, 0); worker.wait()
		assert state.result == 0 && state.acquired == 0
		C.free(state)
		for _ in 0 .. 6 { api.message(object, c'unlock', 0) }
		assert read64(object + 72) == 0 && read64(object + 80) == 0
	}
	for interval in [f64(-1), 0, 0.02]! {
		date := api.date(interval)
		assert api.message(object, c'lockBeforeDate:', date) == 1
		assert api.message(object, c'lockBeforeDate:', date) == 1 && read64(object + 80) == 2
		api.message(object, c'unlock', 0); api.message(object, c'unlock', 0); api.release_date(date)
	}
	assert api.message(object, c'lockBeforeDate:', 0) == 1; api.message(object, c'unlock', 0)
	for interval in [f64(-1), 0, 0.05]! {
		api.message(object, c'lock', 0); date := api.date(interval)
		state := unsafe { &RecursiveLockFixtureState(C.calloc(1, sizeof(RecursiveLockFixtureState))) }
		before := time.sys_mono_now(); worker := spawn recursive_lock_contender(api, object, state, 1, date); worker.wait()
		elapsed := time.sys_mono_now() - before
		assert state.result == 0 && state.acquired == 0 && elapsed < 3 * time.second
		if interval > 0 { assert elapsed >= 2 * time.millisecond }
		api.message(object, c'unlock', 0); api.release_date(date); C.free(state)
	}
	api.message(object, c'lock', 0)
	missing := unsafe { &RecursiveLockFixtureState(C.calloc(1, sizeof(RecursiveLockFixtureState))) }
	nil_worker := spawn recursive_lock_contender(api, object, missing, 1, 0); nil_worker.wait()
	assert missing.result == 0; api.message(object, c'unlock', 0); C.free(missing)
	for mode in [1, 2]! {
		api.message(object, c'lock', 0); api.message(object, c'lock', 0)
		date := if mode == 1 { api.date(5) } else { u64(0) }
		state := unsafe { &RecursiveLockFixtureState(C.calloc(1, sizeof(RecursiveLockFixtureState))) }
		worker := spawn recursive_lock_contender(api, object, state, mode, date)
		recursive_lock_wait(unsafe { &state.ready }, 1); time.sleep(5 * time.millisecond)
		assert stdatomic.load_i64(unsafe { &state.acquired }) == 0
		// Other object operations must progress while this message waits.
		other := api.message(api.root, c'new', 0); api.message(other, c'release', 0)
		api.message(object, c'unlock', 0); time.sleep(5 * time.millisecond)
		assert stdatomic.load_i64(unsafe { &state.acquired }) == 0
		api.message(object, c'unlock', 0); recursive_lock_wait(unsafe { &state.acquired }, 1)
		stdatomic.store_i64(unsafe { &state.finish }, 1); worker.wait()
		if date != 0 { api.release_date(date) }; C.free(state)
	}
	// A timed contender expiring must not strand another blocked caller.
	api.message(object, c'lock', 0)
	short_date := api.date(0.04)
	short := unsafe { &RecursiveLockFixtureState(C.calloc(1, sizeof(RecursiveLockFixtureState))) }
	blocked := unsafe { &RecursiveLockFixtureState(C.calloc(1, sizeof(RecursiveLockFixtureState))) }
	timed_worker := spawn recursive_lock_contender(api, object, short, 1, short_date)
	blocked_worker := spawn recursive_lock_contender(api, object, blocked, 2, 0)
	recursive_lock_wait(unsafe { &short.ready }, 1); recursive_lock_wait(unsafe { &blocked.ready }, 1)
	timed_worker.wait(); assert short.result == 0 && stdatomic.load_i64(unsafe { &blocked.acquired }) == 0
	api.message(object, c'unlock', 0); recursive_lock_wait(unsafe { &blocked.acquired }, 1)
	stdatomic.store_i64(unsafe { &blocked.finish }, 1); blocked_worker.wait()
	api.release_date(short_date); C.free(short); C.free(blocked)
	api.message(object, c'release', 0); api.drain(pool)
}

fn recursive_lock_encodings(api RecursiveLockApi) {
	for name, expected in {'init': '@16@0:8', 'name': '@16@0:8', 'setName:': 'v24@0:8@16', 'lock': 'v16@0:8', 'unlock': 'v16@0:8', 'tryLock': 'B16@0:8', 'lockBeforeDate:': 'B24@0:8@16'} {
		mut actual := ''
		$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(api.cls) }, C.sel_registerName(name.str)); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
		if !api.native { method := objc_instance_method(api.cls, u64(name.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == expected, name + ': ' + actual + ' != ' + expected
	}
}
fn test_recursive_lock_native() {
	$if macos {
		api := RecursiveLockApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSRecursiveLock')), strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass('NSMutableString'.str)), root: u64(C.objc_getClass(c'NSObject'))}
		assert C.class_getInstanceSize(unsafe { voidptr(api.cls) }) == 104 && C.class_getSuperclass(unsafe { voidptr(api.cls) }) == C.objc_getClass(c'NSObject')
		recursive_lock_encodings(api); recursive_lock_shared(api)
		println('IOS-RECURSIVE-LOCK-NATIVE:104-byte allocation/init, typed methods, copied mutable names, recursion and foreign tryLock, nested handoff, timed success, past/nil expiration and independent object progress')
	}
}

// Runtime-only ownership and invalid-input fixtures.
__global recursive_lock_callback_api = RecursiveLockApi{}
__global recursive_lock_callback_receiver = u64(0)
__global recursive_lock_callback_name_weak = u64(0)
__global recursive_lock_constructor_fail = false
fn recursive_lock_runtime_api() RecursiveLockApi {
	return RecursiveLockApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cls: ios_runtime.names['NSRecursiveLock'], strings: ios_runtime.names['NSString'], mutable_strings: ios_runtime.names['NSMutableString'], root: ios_runtime.names['NSObject']}
}
fn recursive_lock_copy_worker() {
	api := recursive_lock_callback_api
	pool := api.pool()
	assert api.message(recursive_lock_callback_receiver, c'tryLock', 0) == 1
	api.message(recursive_lock_callback_receiver, c'unlock', 0)
	api.message(recursive_lock_callback_receiver, c'release', 0)
	api.drain(pool)
}
fn recursive_lock_property_copy(object u64, selector &char) u64 {
	worker := spawn recursive_lock_copy_worker(); worker.wait()
	copied := owned_string(string_text(object))
	objc_store_weak(unsafe { &recursive_lock_callback_name_weak }, copied)
	return copied
}
fn recursive_lock_bad_copy(object u64, selector &char) u64 { return objc_new(ios_runtime.names['NSObject']) }
fn recursive_lock_nil_copy(object u64, selector &char) u64 { return 0 }
fn recursive_lock_constructor(object u64, selector &char) u64 {
	if !recursive_lock_constructor_fail { return object }
	api := recursive_lock_callback_api
	api.message(object, c'init', 0)
	name := owned_string('failed recursive lock constructor owner')
	api.message(object, c'setName:', name); objc_release(name)
	objc_store_weak(unsafe { &recursive_lock_callback_name_weak }, read64(object + 96))
	return 0
}
fn recursive_lock_runtime_callbacks(api RecursiveLockApi) {
	recursive_lock_callback_api = api
	pool := api.pool()
	custom := objc_allocate_class(api.strings, c'VinixRecursiveLockCopyString', 0)
	assert objc_add_method(custom, u64(c'copy'), u64(unsafe { voidptr(recursive_lock_property_copy) }), c'@16@0:8'); objc_register_class(custom)
	property := owned_string('recursive lock copied property callback')
	assert objc_set_class(property, custom) == api.strings
	recursive_lock_callback_receiver = api.message(api.cls, c'new', 0)
	mut receiver_weak := u64(0); objc_store_weak(unsafe { &receiver_weak }, recursive_lock_callback_receiver)
	// Copy runs outside both locks and keeps the setter's receiver alive while
	// a joined worker drops its final caller-owned reference.
	api.message(recursive_lock_callback_receiver, c'setName:', property)
	assert receiver_weak == 0 && recursive_lock_callback_name_weak == 0
	objc_destroy_weak(unsafe { &receiver_weak }); objc_destroy_weak(unsafe { &recursive_lock_callback_name_weak })
	objc_release(property); recursive_lock_callback_receiver = 0
	assert objc_add_method(api.cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(recursive_lock_constructor) }), c'@16@0:8')
	recursive_lock_constructor_fail = true
	assert api.message(api.cls, c'new', 0) == 0 && recursive_lock_callback_name_weak == 0
	objc_destroy_weak(unsafe { &recursive_lock_callback_name_weak })
	mut storage := [13]u64{}
	assert objc_construct_instance(api.cls, u64(unsafe { &storage[0] })) == 0 && recursive_lock_callback_name_weak == 0
	objc_destroy_weak(unsafe { &recursive_lock_callback_name_weak })
	assert storage[0] == api.cls
	for i in 1 .. storage.len { assert storage[i] == 0 }
	recursive_lock_constructor_fail = false
	api.drain(pool)
}
fn test_recursive_lock_runtime() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := recursive_lock_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSRecursiveLock')! == api.cls
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSRecursiveLock')! == read64(api.cls)
		assert sizeof(AbiNSRecursiveLock) == 104 && objc_class_size(api.cls) == 104 && objc_class_parent(api.cls) == api.root
		assert ios_runtime.classes[api.cls].ivars.len == 1
		ivar := objc_find_ivar(api.cls, c'_priv')
		assert ivar != 0 && objc_ivar_offset(ivar) == 8
		assert ctext(u64(objc_ivar_types(ivar))) == '{?="m"{_opaque_pthread_mutex_t="__sig"q"__opaque"[56c]}"t"^{_opaque_pthread_t}"cnt"Q"cd"^{?}"n"@"NSString"}'
		recursive_lock_encodings(api); recursive_lock_shared(api)
		assert ios_runtime.live == 0 && system_data.mutexes.len == 0
		pool := api.pool(); preinit := api.message(api.cls, c'alloc', 0)
		name := owned_string('name before recursive lock initialization')
		api.message(preinit, c'setName:', name); objc_release(name)
		mut preinit_weak := u64(0); objc_store_weak(unsafe { &preinit_weak }, read64(preinit + 96))
		assert preinit_weak != 0 && api.message(preinit, c'init', 0) == preinit && preinit_weak == 0
		assert api.message(preinit, c'name', 0) == 0
		api.message(preinit, c'release', 0); objc_destroy_weak(unsafe { &preinit_weak }); api.drain(pool)
		recursive_lock_runtime_callbacks(api)
		assert ios_runtime.live == 0 && system_data.mutexes.len == 0
		mut guarded := [15]u64{}; guarded[0] = 0x1122334455667788; guarded[14] = 0x8877665544332211
		object := objc_construct_instance(api.cls, u64(unsafe { &guarded[1] }))
		assert object != 0 && read64(object + 8) == 0 && api.message(object, c'init', 0) == object
		owned := owned_string('caller-owned recursive lock storage')
		api.message(object, c'setName:', owned); objc_release(owned)
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, read64(object + 96))
		assert weak != 0 && objc_destruct_instance(object) == object && weak == 0
		objc_destroy_weak(unsafe { &weak })
		assert read64(object) == api.cls
		for offset in 8 .. 104 { assert unsafe { *(&u8(voidptr(object + u64(offset)))) } == 0 }
		assert guarded[0] == 0x1122334455667788 && guarded[14] == 0x8877665544332211
		for _ in 0 .. 64 {
			inner := api.pool(); replaced := api.message(api.cls, c'new', 0)
			value := owned_string('recursive lock isa replacement')
			api.message(replaced, c'setName:', value); objc_release(value)
			assert objc_set_class(replaced, api.root) == api.cls
			api.message(replaced, c'release', 0); api.drain(inner)
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && system_data.mutexes.len == 0
		last := objc_autorelease(api.message(api.cls, c'new', 0)); final_name := owned_string('recursive lock shutdown owner')
		api.message(last, c'setName:', final_name); objc_release(final_name)
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && system_data.mutexes.len == 0
		system_data_stop()
	}
	println('IOS-RECURSIVE-LOCK: typed metadata, copied-name callbacks and receiver pins, failed constructors, preinit name retirement, guarded caller storage,64 isa replacements and two drained runtimes')
}
fn recursive_lock_foreign_unlock(api RecursiveLockApi, object u64) { api.message(object, c'unlock', 0) }
fn test_recursive_lock_rejections() {
	objc_start(); system_data_start()!; api := recursive_lock_runtime_api()
	for mode in ['uninit-lock', 'uninit-try', 'uninit-unlock', 'uninit-timed', 'reinit', 'name-type', 'bad-copy', 'nil-copy', 'date-type', 'huge-date', 'nan-date', 'unlock', 'foreign-unlock', 'release-held', 'destruct-held', 'destruct-waiter', 'subclass', 'caller-subclass', 'spoof', 'copy', 'mutable-copy', 'coding', 'description']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := api.message(api.cls, c'new', 0)
			match mode {
				'uninit-lock', 'uninit-try', 'uninit-unlock', 'uninit-timed' {
					raw := api.message(api.cls, c'alloc', 0)
					selector := match mode { 'uninit-lock' { c'lock' } 'uninit-try' { c'tryLock' } 'uninit-unlock' { c'unlock' } else { c'lockBeforeDate:' } }
					api.message(raw, selector, 0)
				}
				'reinit' { api.message(object, c'init', 0) }
				'name-type' { api.message(object, c'setName:', objc_new(api.root)) }
				'bad-copy', 'nil-copy' {
					custom := objc_allocate_class(api.strings, c'VinixRecursiveLockBadCopyString', 0)
					implementation := if mode == 'bad-copy' { u64(unsafe { voidptr(recursive_lock_bad_copy) }) } else { u64(unsafe { voidptr(recursive_lock_nil_copy) }) }
					assert objc_add_method(custom, u64(c'copy'), implementation, c'@16@0:8'); objc_register_class(custom)
					api.message(object, c'setName:', objc_new(custom))
				}
				'date-type' { api.message(object, c'lockBeforeDate:', owned_string('not a date')) }
				'huge-date' { api.message(object, c'lockBeforeDate:', cf_date_create(0, 1e100)) }
				'nan-date' { bits := u64(0x7ff8000000000000); api.message(object, c'lockBeforeDate:', cf_date_create(0, unsafe { *(&f64(voidptr(&bits))) })) }
				'unlock' { api.message(object, c'unlock', 0) }
				'foreign-unlock' { api.message(object, c'lock', 0); worker := spawn recursive_lock_foreign_unlock(api, object); worker.wait() }
				'release-held', 'destruct-held' { api.message(object, c'lock', 0); if mode == 'release-held' { api.message(object, c'release', 0) } else { objc_destruct_instance(object) } }
				'destruct-waiter' {
					api.message(object, c'lock', 0)
					state := unsafe { &RecursiveLockFixtureState(C.calloc(1, sizeof(RecursiveLockFixtureState))) }
					worker := spawn recursive_lock_contender(api, object, state, 2, 0)
					recursive_lock_wait(unsafe { &state.ready }, 1)
					deadline := time.sys_mono_now() + 10 * time.second
					for {
						C.ios_objc_initialize_lock(); calls := obj_header(object).recursive_lock_calls; C.ios_objc_initialize_unlock()
						if calls != 0 { break }; assert time.sys_mono_now() < deadline; time.sleep(time.millisecond)
					}
					objc_destruct_instance(object); worker.wait()
				}
				'subclass', 'caller-subclass' {
					sub := objc_allocate_class(api.cls, c'VinixUnsupportedRecursiveLockSubclass', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { mut storage := [13]u64{}; objc_construct_instance(sub, u64(unsafe { &storage[0] })) }
				}
				'spoof' {
					sub := objc_allocate_class(api.root, c'VinixRecursiveLockSpoof', 0)
					assert objc_add_ivar(sub, c'bytes', 96, 3, c'[96C]'); objc_register_class(sub)
					spoof := objc_new(sub); objc_set_class(spoof, api.cls); api.message(spoof, c'tryLock', 0)
				}
				'copy' { api.message(object, c'copy', 0) }
				'mutable-copy' { api.message(object, c'mutableCopy', 0) }
				'coding' { api.message(object, c'initWithCoder:', 0) }
				else { api.message(object, c'description', 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'uninit-lock', 'uninit-try', 'uninit-unlock', 'uninit-timed' { 'is not initialized' }
			'reinit' { 'reinitialization' }
			'name-type' { 'name must be NSString' }
			'bad-copy', 'nil-copy' { 'name copy must return NSString' }
			'date-type' { 'unsupported CFDate' }
			'huge-date', 'nan-date' { 'finite clock profile' }
			'unlock', 'foreign-unlock' { 'owning thread' }
			'release-held', 'destruct-held', 'destruct-waiter' { 'destroying an active' }
			'subclass', 'caller-subclass' { 'custom NSRecursiveLock subclass' }
			'spoof' { 'live base lock storage' }
			else { 'copying, coding' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	assert ios_runtime.live == 0 && system_data.mutexes.len == 0; objc_stop(); system_data_stop()
	println('IOS-RECURSIVE-LOCK-REJECT:23 uninitialized, reinit, property-copy, date, owner, active destruction, subclass, spoof, copy and coding cases fail explicitly')
}
