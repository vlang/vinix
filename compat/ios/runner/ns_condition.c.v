// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

struct AbiNSCondition {
mut:
	isa       u64
	mutex     [8]u64
	condition [6]u64
	name      u64
}

fn ns_condition_initialize(object u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := obj_header(object)
	if !header.condition_owned || header.native_size < sizeof(AbiNSCondition) {
		panic('iOS: invalid NSCondition storage')
	}
	if header.condition_initialized { return }
	if system_data == unsafe { nil } { panic('iOS: NSCondition requires initialized system data') }
	if darwin_mutex_init(object + 8, 0) != 0 {
		panic('iOS: NSCondition mutex initialization failed')
	}
	if darwin_cond_init(object + 72, 0) != 0 {
		darwin_mutex_destroy(object + 8)
		panic('iOS: NSCondition variable initialization failed')
	}
	// Keep the measured initialized signatures in the opaque Darwin records.
	// Real native storage is owned by the existing pthread registries.
	unsafe {
		*(&u64(object + 8)) = 0x4d55545a
		*(&u64(object + 72)) = 0x434f4e44
	}
	header.condition_initialized = true
}

fn ns_condition_dispose(object u64, mut header ObjHeader) {
	// Ownership survives object_setClass, including a change to NSObject.
	if !header.condition_owned { return }
	if header.condition_initialized {
		if system_data == unsafe { nil } { panic('iOS: NSCondition outlived system data') }
		if darwin_cond_destroy(object + 72) != 0 {
			panic('iOS: destroying an active NSCondition variable')
		}
		if darwin_mutex_destroy(object + 8) != 0 {
			panic('iOS: destroying an active NSCondition mutex')
		}
		header.condition_initialized = false
	}
	mut record := unsafe { &AbiNSCondition(object) }
	objc_release(record.name)
	record.name = 0
	header.condition_owned = false
}

fn ns_condition_wait_date(object u64, date u64) bool {
	// The runner's CFDate objects carry the same 2001 reference epoch as
	// Foundation's toll-free bridged NSDate. A nil date expires immediately.
	absolute := if date == 0 { f64(-978307200) } else { cf_date_absolute(date) }
	seconds := absolute + 978307200
	if !math.is_finite(seconds) || seconds >= 9223372036854775808.0 {
		panic('iOS: NSCondition deadline is outside the finite clock profile')
	}
	whole := math.floor(math.max(seconds, 0))
	mut deadline := DispatchTimespec{ seconds: i64(whole), nanoseconds: i64((math.max(seconds, 0) - whole) * 1e9) }
	result := darwin_cond_timedwait(object + 72, object + 8, unsafe { &deadline })
	if result != 0 && result != 60 { panic('iOS: NSCondition timed wait failed') }
	return result == 0
}

fn ns_condition_builtin_types(name string, meta bool, selector string) ?string {
	if meta || name != 'NSCondition' { return none }
	return match selector {
		'init', 'name' { '@16@0:8' }
		'lock', 'unlock', 'wait', 'signal', 'broadcast' { 'v16@0:8' }
		'setName:' { 'v24@0:8@16' }
		'waitUntilDate:' { 'B24@0:8@16' }
		else { return none }
	}
}

fn ns_condition_selector(object u64, selector string) bool {
	return object !in ios_runtime.classes && objc_is_kind(object, ios_runtime.names['NSCondition'])
		&& ns_condition_builtin_types('NSCondition', false, selector) != none
}

fn ns_condition_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes || !objc_is_kind(object, ios_runtime.names['NSCondition']) {
		return false
	}
	mut record := unsafe { &AbiNSCondition(object) }
	match selector {
		'init' {
			ns_condition_initialize(object)
			frame.x[0] = object
		}
		'name' { frame.x[0] = record.name }
		'setName:' {
			value := frame.x[2]
			if value != 0 && !objc_is_kind(value, ios_runtime.names['NSString']) {
				panic('iOS: NSCondition name must be a string')
			}
			name := if value == 0 { u64(0) } else { owned_string(string_text(value)) }
			objc_store_strong(unsafe { &record.name }, name)
			objc_release(name)
		}
		'lock', 'unlock', 'wait', 'signal', 'broadcast', 'waitUntilDate:' {
			if !obj_header(object).condition_initialized {
				panic('iOS: NSCondition is not initialized')
			}
			if selector == 'waitUntilDate:' {
				frame.x[0] = u64(ns_condition_wait_date(object, frame.x[2]))
				return true
			}
			result := match selector {
				'lock' { darwin_mutex_lock(object + 8) }
				'unlock' { darwin_mutex_unlock(object + 8) }
				'wait' { darwin_cond_wait(object + 72, object + 8) }
				'signal' { darwin_cond_signal(object + 72) }
				else { darwin_cond_broadcast(object + 72) }
			}
			if result != 0 { panic('iOS: NSCondition synchronization failed') }
		}
		else { return false }
	}
	return true
}
