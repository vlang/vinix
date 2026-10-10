// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Keys are opaque identities, including classes, blocks and tagged pointers.
// A monitor does not retain or read the object used as its key.
struct ObjMonitor {
mut:
	mutex voidptr
	entries u64 // Held recursive entries plus callers waiting to acquire.
}

fn objc_sync_enter(object u64) i32 {
	if object == 0 { return 0 }
	C.ios_objc_initialize_lock()
	mut monitor := ios_runtime.monitors[object] or {
		mut created := unsafe { &ObjMonitor(C.calloc(1, sizeof(ObjMonitor))) }
		if created == unsafe { nil } { panic('iOS: cannot allocate object monitor') }
		created.mutex = C.calloc(1, C.ios_sizeof_mutex())
		if created.mutex == unsafe { nil } || C.ios_mutex_create(created.mutex, 2) != 0 {
			C.free(created.mutex); C.free(created)
			panic('iOS: cannot initialize object monitor')
		}
		ios_runtime.monitors[object] = created
		created
	}
	// Pin before leaving the registry, including every recursive acquisition.
	// Waiting must not hold the registry lock: the owner needs it to exit.
	monitor.entries++
	C.ios_objc_initialize_unlock()
	if C.pthread_mutex_lock(monitor.mutex) != 0 { panic('iOS: cannot acquire object monitor') }
	return 0
}

fn objc_sync_exit(object u64) i32 {
	if object == 0 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut monitor := ios_runtime.monitors[object] or { return -1 }
	// Unlock never waits or invokes app callbacks. Keep the registry guarded
	// through native unlock so a foreign exit cannot race monitor retirement.
	if C.pthread_mutex_unlock(monitor.mutex) != 0 { return -1 }
	monitor.entries--
	if monitor.entries == 0 {
		// Existing waiters already own pins; new callers cannot find this entry
		// until the registry unlocks. The last successful exit can free it now.
		ios_runtime.monitors.delete(object)
		if C.pthread_mutex_destroy(monitor.mutex) != 0 { panic('iOS: active object monitor at retirement') }
		C.free(monitor.mutex); C.free(monitor)
	}
	return 0
}

fn objc_monitors_stop() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.monitors.len != 0 { panic('iOS: active object monitor at shutdown') }
	unsafe { ios_runtime.monitors.free() }
}
