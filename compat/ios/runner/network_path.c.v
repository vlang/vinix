// SPDX-License-Identifier: GPL-2.0-or-later
module main

type NWUpdate = fn (u64, u64)
type NWEnumerate = fn (u64, u64) bool
@[heap]
struct NWPathState { snapshot NWSnapshot links [64]u64 }
@[heap]
struct NWInterfaceState { link NWLink }
@[heap]
struct NWMonitorState {
mut:
	queue u64
	handler u64
	path u64
	generation u64
	started bool
	cancelled bool
	pending bool
}
@[heap]
struct NWRuntime {
mut:
	monitors [64]u64 // One reference per active monitor, independent of queued work.
	worker usize
	started bool
	stopping bool
}
@[heap]
struct NWWork { monitor u64 generation u64 }
__global nw_runtime = unsafe { &NWRuntime(nil) }

// Only these private classes use external_data for Network state. No common
// ObjHeader fields or guest-visible native ivars are added for this profile.
fn nw_header(object u64, name string) ?&ObjHeader {
	if ios_runtime == unsafe { nil } || object == 0 { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { return none }
	if header.cls != ios_runtime.names[name] || header.external_data == 0 { return none }
	return header
}
fn nw_path_state(path u64) ?&NWPathState {
	header := nw_header(path, 'VinixNWPath') or { return none }
	return unsafe { &NWPathState(header.external_data) }
}
fn nw_monitor_state(monitor u64) ?&NWMonitorState {
	header := nw_header(monitor, 'VinixNWPathMonitor') or { return none }
	return unsafe { &NWMonitorState(header.external_data) }
}
fn nw_path_from_snapshot(snapshot &NWSnapshot) u64 {
	mut links := [64]u64{}
	for i in 0 .. snapshot.count {
		link := objc_allocate(ios_runtime.names['VinixNWInterface'])
		obj_header(link).external_data = u64(&NWInterfaceState{snapshot.links[i]})
		links[i] = link
	}
	path := objc_allocate(ios_runtime.names['VinixNWPath'])
	obj_header(path).external_data = u64(&NWPathState{*snapshot, links})
	return path
}
fn nw_interface_name(link u64) &char {
	header := nw_header(link, 'VinixNWInterface') or { return unsafe { nil } }
	state := unsafe { &NWInterfaceState(header.external_data) }
	return unsafe { &char(&state.link.name[0]) }
}
fn nw_interface_index(link u64) u32 {
	header := nw_header(link, 'VinixNWInterface') or { return 0 }
	return unsafe { &NWInterfaceState(header.external_data) }.link.index
}
fn nw_interface_kind(link u64) u32 {
	header := nw_header(link, 'VinixNWInterface') or { return 0 }
	return unsafe { &NWInterfaceState(header.external_data) }.link.kind
}
fn nw_path_status(path u64) u32 { state := nw_path_state(path) or { return 0 }; return state.snapshot.status }
fn nw_path_dns(path u64) bool { state := nw_path_state(path) or { return false }; return state.snapshot.dns }
fn nw_path_ipv4(path u64) bool { state := nw_path_state(path) or { return false }; return state.snapshot.ipv4 }
fn nw_path_ipv6(path u64) bool { state := nw_path_state(path) or { return false }; return state.snapshot.ipv6 }
fn nw_path_uses(path u64, kind u32) bool {
	state := nw_path_state(path) or { return false }
	if kind > 4 { return false }
	for i in 0 .. state.snapshot.count { if state.snapshot.links[i].kind == kind { return true } }
	return false
}
fn nw_path_expensive(path u64) bool { return nw_path_uses(path, 2) }
fn nw_path_constrained(path u64) bool { _ = path; return false } // Vinix has no Low Data Mode policy.
fn nw_path_enumerate(path u64, block u64) {
	if block == 0 { return }
	state := nw_path_state(path) or { return }
	objc_retain(path)
	defer { objc_release(path) }
	for i in 0 .. state.snapshot.count {
		if !unsafe { NWEnumerate(voidptr(read64(block + 16)))(block, state.links[i]) } { break }
	}
}
fn nw_monitor_create() u64 {
	if ios_runtime == unsafe { nil } { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired || ios_runtime.network_retired { return 0 }
	if nw_runtime == unsafe { nil } { nw_runtime = &NWRuntime{} }
	if nw_runtime.stopping { return 0 }
	monitor := objc_allocate(ios_runtime.names['VinixNWPathMonitor'])
	obj_header(monitor).external_data = u64(&NWMonitorState{})
	return monitor
}
fn nw_monitor_queue(monitor u64, queue u64) {
	C.ios_objc_initialize_lock()
	mut state := nw_monitor_state(monitor) or { C.ios_objc_initialize_unlock(); return }
	if state.cancelled { C.ios_objc_initialize_unlock(); return }
	if state.started { C.ios_objc_initialize_unlock(); panic('iOS: Network monitor queue must be set before start') }
	if !dispatch_objc_is_queue(queue) { C.ios_objc_initialize_unlock(); panic('iOS: Network monitor requires a dispatch queue') }
	darwin_dispatch_retain(queue); previous := state.queue; state.queue = queue
	C.ios_objc_initialize_unlock()
	if previous != 0 { darwin_dispatch_release(previous) }
}
fn nw_monitor_handler(monitor u64, block u64) {
	// Copy/release helpers can reenter Network or Objective-C APIs.
	objc_retain(monitor)
	defer { objc_release(monitor) }
	copied := block_copy(block)
	C.ios_objc_initialize_lock()
	mut state := nw_monitor_state(monitor) or { C.ios_objc_initialize_unlock(); block_release(copied); return }
	if state.cancelled { C.ios_objc_initialize_unlock(); block_release(copied); return }
	previous := state.handler; state.handler = copied
	C.ios_objc_initialize_unlock()
	block_release(previous)
}
fn nw_monitor_start(monitor u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := nw_monitor_state(monitor) or { return }
	if state.started || state.cancelled || nw_runtime == unsafe { nil } || nw_runtime.stopping { return }
	if state.queue == 0 { panic('iOS: Network monitor requires a queue before start') }
	mut slot := -1
	for i, value in nw_runtime.monitors { if value == 0 { slot = i; break } }
	if slot < 0 { panic('iOS: Network monitor limit exceeded') }
	state.started = true; state.generation++
	nw_runtime.monitors[slot] = objc_retain(monitor)
	if !nw_runtime.started {
		if darwin_pthread_create(unsafe { voidptr(&nw_runtime.worker) }, unsafe { nil }, unsafe { voidptr(nw_worker) }, unsafe { nil }) != 0 { panic('iOS: cannot start Network monitor worker') }
		nw_runtime.started = true
	}
}
fn nw_monitor_cancel(monitor u64) {
	C.ios_objc_initialize_lock()
	mut state := nw_monitor_state(monitor) or { C.ios_objc_initialize_unlock(); return }
	if state.cancelled { C.ios_objc_initialize_unlock(); return }
	state.cancelled = true; state.generation++; state.pending = false
	mut owned := u64(0)
	if nw_runtime != unsafe { nil } {
		for i, value in nw_runtime.monitors { if value == monitor { nw_runtime.monitors[i] = 0; owned = monitor; break } }
	}
	queue := state.queue; handler := state.handler; path := state.path
	state.queue = 0; state.handler = 0; state.path = 0
	C.ios_objc_initialize_unlock()
	block_release(handler); objc_release(path)
	if queue != 0 { darwin_dispatch_release(queue) }
	objc_release(owned)
}
fn nw_work_drop(context voidptr) {
	work := unsafe { &NWWork(context) }
	objc_release(work.monitor)
	unsafe { free(work) }
}
fn nw_deliver(context voidptr) {
	work := unsafe { &NWWork(context) }
	C.ios_objc_initialize_lock()
	mut state := nw_monitor_state(work.monitor) or { C.ios_objc_initialize_unlock(); return }
	if state.cancelled || state.generation != work.generation { C.ios_objc_initialize_unlock(); return }
	state.pending = false
	block := block_retain(state.handler); path := objc_retain(state.path)
	C.ios_objc_initialize_unlock()
	if block != 0 && path != 0 { unsafe { NWUpdate(voidptr(read64(block + 16)))(block, path) } }
	block_release(block); objc_release(path)
}
fn nw_observe(monitor u64, snapshot &NWSnapshot) {
	C.ios_objc_initialize_lock()
	mut state := nw_monitor_state(monitor) or { C.ios_objc_initialize_unlock(); return }
	if state.cancelled || !state.started || nw_runtime.stopping { C.ios_objc_initialize_unlock(); return }
	if previous := nw_path_state(state.path) {
		if nw_snapshot_equal(unsafe { &previous.snapshot }, snapshot) { C.ios_objc_initialize_unlock(); return }
	}
	previous := state.path; state.path = nw_path_from_snapshot(snapshot)
	if !state.pending && state.handler != 0 {
		state.pending = true
		work := &NWWork{objc_retain(monitor), state.generation}
		dispatch_submit_owned(state.queue, unsafe { voidptr(work) }, nw_deliver, nw_work_drop)
	}
	C.ios_objc_initialize_unlock()
	objc_release(previous)
}
fn nw_worker(_argument voidptr) voidptr {
	for {
		C.ios_objc_initialize_lock()
		stopping := nw_runtime.stopping
		mut active := false
		for monitor in nw_runtime.monitors { if monitor != 0 { active = true; break } }
		C.ios_objc_initialize_unlock()
		if stopping { return unsafe { nil } }
		if !active { C.usleep(100000); continue }
		if snapshot := nw_snapshot() {
			for i in 0 .. 64 {
				C.ios_objc_initialize_lock()
				if nw_runtime.stopping { C.ios_objc_initialize_unlock(); return unsafe { nil } }
				monitor := objc_retain(nw_runtime.monitors[i]); C.ios_objc_initialize_unlock()
				if monitor != 0 { nw_observe(monitor, unsafe { &snapshot }); objc_release(monitor) }
			}
		}
		C.usleep(100000)
	}
	return unsafe { nil }
}
fn nw_dispose(mut header ObjHeader) {
	if header.external_data == 0 { return }
	if header.cls == ios_runtime.names['VinixNWPathMonitor'] {
		state := unsafe { &NWMonitorState(header.external_data) }
		if state.started && !state.cancelled { panic('iOS: active Network monitor lost its owner') }
		block_release(state.handler); objc_release(state.path)
		if state.queue != 0 { darwin_dispatch_release(state.queue) }
		unsafe { free(state) }
	} else if header.cls == ios_runtime.names['VinixNWPath'] {
		state := unsafe { &NWPathState(header.external_data) }
		for i in 0 .. state.snapshot.count { objc_release(state.links[i]) }
		unsafe { free(state) }
	} else if header.cls == ios_runtime.names['VinixNWInterface'] {
		unsafe { free(&NWInterfaceState(header.external_data)) }
	} else { return }
	header.external_data = 0
}
fn nw_stop() {
	C.ios_objc_initialize_lock()
	if ios_runtime != unsafe { nil } { ios_runtime.network_retired = true }
	if nw_runtime == unsafe { nil } { C.ios_objc_initialize_unlock(); return }
	nw_runtime.stopping = true
	C.ios_objc_initialize_unlock()
	if nw_runtime.started && C.pthread_join(unsafe { voidptr(nw_runtime.worker) }, unsafe { nil }) != 0 { panic('iOS: cannot join Network monitor worker') }
	nw_runtime.started = false
	for i in 0 .. 64 {
		C.ios_objc_initialize_lock(); monitor := objc_retain(nw_runtime.monitors[i]); C.ios_objc_initialize_unlock()
		if monitor != 0 { nw_monitor_cancel(monitor); objc_release(monitor) }
	}
}
fn nw_free() {
	if nw_runtime == unsafe { nil } { return }
	unsafe { free(nw_runtime) }; nw_runtime = unsafe { nil }
}
fn nw_symbol(symbol string) ?u64 {
	return match symbol {
		'_nw_interface_get_name' { u64(unsafe { voidptr(nw_interface_name) }) }
		'_nw_interface_get_index' { u64(unsafe { voidptr(nw_interface_index) }) }
		'_nw_interface_get_type' { u64(unsafe { voidptr(nw_interface_kind) }) }
		'_nw_path_enumerate_interfaces' { u64(unsafe { voidptr(nw_path_enumerate) }) }
		'_nw_path_get_status' { u64(unsafe { voidptr(nw_path_status) }) }
		'_nw_path_has_dns' { u64(unsafe { voidptr(nw_path_dns) }) }
		'_nw_path_has_ipv4' { u64(unsafe { voidptr(nw_path_ipv4) }) }
		'_nw_path_has_ipv6' { u64(unsafe { voidptr(nw_path_ipv6) }) }
		'_nw_path_is_constrained' { u64(unsafe { voidptr(nw_path_constrained) }) }
		'_nw_path_is_expensive' { u64(unsafe { voidptr(nw_path_expensive) }) }
		'_nw_path_uses_interface_type' { u64(unsafe { voidptr(nw_path_uses) }) }
		'_nw_path_monitor_create' { u64(unsafe { voidptr(nw_monitor_create) }) }
		'_nw_path_monitor_set_queue' { u64(unsafe { voidptr(nw_monitor_queue) }) }
		'_nw_path_monitor_set_update_handler' { u64(unsafe { voidptr(nw_monitor_handler) }) }
		'_nw_path_monitor_start' { u64(unsafe { voidptr(nw_monitor_start) }) }
		'_nw_path_monitor_cancel' { u64(unsafe { voidptr(nw_monitor_cancel) }) }
		'_nw_retain' { u64(unsafe { voidptr(objc_retain) }) }
		'_nw_release' { u64(unsafe { voidptr(objc_release) }) }
		else { none }
	}
}
