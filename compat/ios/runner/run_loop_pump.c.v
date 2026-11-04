// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import time

// State uses the Objective-C registry lock. The native condition has a separate
// mutex, always acquired after that lock. A waiter holds both until it releases
// the registry lock and atomically waits, preventing lost mutation/shutdown wakes.
fn run_loop_wait_initialize_locked() {
	if ios_runtime.run_loop_wait_mutex != unsafe { nil } { return }
	ios_runtime.run_loop_wait_mutex = C.calloc(1, C.ios_sizeof_mutex())
	ios_runtime.run_loop_wait_condition = C.calloc(1, C.ios_sizeof_cond())
	if ios_runtime.run_loop_wait_mutex == unsafe { nil } || ios_runtime.run_loop_wait_condition == unsafe { nil }
		|| C.ios_mutex_create(ios_runtime.run_loop_wait_mutex, 0) != 0
		|| C.pthread_cond_init(ios_runtime.run_loop_wait_condition, unsafe { nil }) != 0 {
		panic('iOS: cannot initialize run-loop wait')
	}
}

fn run_loop_wake_locked() {
	if ios_runtime.run_loop_wait_mutex == unsafe { nil } { return }
	C.pthread_mutex_lock(ios_runtime.run_loop_wait_mutex)
	C.pthread_cond_broadcast(ios_runtime.run_loop_wait_condition)
	C.pthread_mutex_unlock(ios_runtime.run_loop_wait_mutex)
}

fn run_loop_wait_stop() {
	// Foundation/dispatch workers and foreign Foundation users have terminated.
	if ios_runtime.run_loop_wait_mutex == unsafe { nil } { return }
	if C.pthread_cond_destroy(ios_runtime.run_loop_wait_condition) != 0
		|| C.pthread_mutex_destroy(ios_runtime.run_loop_wait_mutex) != 0 { panic('iOS: active run-loop wait at shutdown') }
	C.free(ios_runtime.run_loop_wait_condition); C.free(ios_runtime.run_loop_wait_mutex)
	ios_runtime.run_loop_wait_condition = unsafe { nil }; ios_runtime.run_loop_wait_mutex = unsafe { nil }
}

fn run_loop_run_mode(loop u64, mode u64, date u64) bool {
	if !objc_is_kind(mode, ios_runtime.names['NSString']) || !ns_date_is_date(date) {
		panic('iOS: run-loop pump requires a mode string and NSDate')
	}
	limit := cf_date_absolute(date)
	if !math.is_finite(limit) { panic('iOS: nonfinite run-loop deadline') }
	C.ios_objc_initialize_lock()
	owner := obj_header(loop).number
	C.ios_objc_initialize_unlock()
	if u64(owner) != u64(C.pthread_self()) { panic('iOS: run-loop pump requires its owning thread') }
	// Common modes are a registration set, not a runnable mode. Only default
	// mode is currently a member; unknown modes have no supported input sources.
	if string_text(mode) != 'kCFRunLoopDefaultMode' { return false }
	for {
		C.ios_objc_initialize_lock()
		if ios_runtime.display_links_stopping || !obj_header(loop).loaded { C.ios_objc_initialize_unlock(); return false }
		now := time.sys_mono_now()
		mut attached := false
		mut next := now + 100_000_000
		for link in ios_runtime.display_links {
			header := obj_header(link)
			if header.valid && header.loaded && header.fields[1] == loop && header.section & 3 != 0 {
				attached = true
				if !header.repeat && header.deadline < next { next = header.deadline }
			}
		}
		if !attached { C.ios_objc_initialize_unlock(); return false }
		if next <= now {
			C.ios_objc_initialize_unlock()
			if display_links_fire_for_loop(loop) { return true }
			continue
		}
		remaining := limit - cf_absolute_time()
		if remaining <= 0 { C.ios_objc_initialize_unlock(); return true }
		interval := u64(math.min(f64(next - now), math.min(remaining, 0.1) * 1e9))
		run_loop_wait_initialize_locked()
		mutex := ios_runtime.run_loop_wait_mutex; condition := ios_runtime.run_loop_wait_condition
		C.pthread_mutex_lock(mutex)
		C.ios_objc_initialize_unlock()
		dispatch_wait_interval(condition, mutex, interval)
		C.pthread_mutex_unlock(mutex)
	}
}
