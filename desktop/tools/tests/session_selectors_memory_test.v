// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore

#include "@VMODROOT/tools/tests/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_selector_lookup_and_refusal_retain_no_allocations() {
	caller := sessioncore.SessionCaller{ pid: 100, uid: 1000, session_uid: 1000, compositor_pid: 200 }
	foreign := sessioncore.SessionCaller{ pid: 200, uid: 0, session_uid: 1000, compositor_pid: 200 }
	policy := sessioncore.Policy{ clipboard_apps: false }
	// A positive control prevents a missing heap-tracking flag from producing
	// a false pass. Retire it before measuring the actual request paths.
	C.vinix_heap_begin()
	mut probe := []u8{len: 31}
	probe[0] = 42
	assert probe[0] == 42
	assert C.vinix_heap_end() >= 31
	unsafe { probe.free() }
	C.vinix_heap_begin()
	for _ in 0 .. 1000 {
		assert sessioncore.authorize_session('ping', 1, caller, &policy)! == .ping
		// Exercise global, arity, domain, privacy and unknown-name failures.
		if _ := sessioncore.authorize_session('ping', 1, foreign, &policy) {
			assert false
		}
		if _ := sessioncore.authorize_session('ping', 2, caller, &policy) {
			assert false
		}
		if _ := sessioncore.authorize_session('settings.set', 2, caller, &policy) {
			assert false
		}
		if _ := sessioncore.authorize_session('clipboard.read', 2, caller, &policy) {
			assert false
		}
		if _ := sessioncore.authorize_session('sbp/selectors/register', 2, caller, &policy) {
			assert false
		}
	}
	kept := C.vinix_heap_end()
	assert kept == 0, 'selector requests retained ${kept} bytes'
}
