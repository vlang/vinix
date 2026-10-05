// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

// Fixtures and NativeApp storage live outside tracking; polling itself only
// mutates scalar counters. This measures real child dispatch/reply ownership
// and the real compositor's Desktop.poll_apps, without app/frame allocations.
struct NativeOrdinaryPollHeapReceiver {
mut:
	calls int
	changed bool
}

fn (mut _ NativeOrdinaryPollHeapReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }
fn (mut _ NativeOrdinaryPollHeapReceiver) handle(_ string) ! {}
fn (mut app NativeOrdinaryPollHeapReceiver) poll() bool { app.calls++; return app.changed }

struct NativePacedPollHeapReceiver {
mut:
	calls int
	changed bool
}

fn (mut _ NativePacedPollHeapReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }
fn (mut _ NativePacedPollHeapReceiver) handle(_ string) ! {}
fn (mut app NativePacedPollHeapReceiver) poll() bool { app.calls++; return app.changed }
fn (app &NativePacedPollHeapReceiver) next_poll_ms() u64 { return u64(0x01020300 + app.calls) }

struct NativeNonPollingHeapReceiver {}
fn (mut _ NativeNonPollingHeapReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }
fn (mut _ NativeNonPollingHeapReceiver) handle(_ string) ! {}

fn test_native_child_nonpolling_reply_is_quiet_and_releases_owned_payload() {
	mut receiver := &NativeNonPollingHeapReceiver{}
	mut app := NativeApp(receiver)
	for count in [100, 200]! {
		C.vinix_heap_begin()
		for _ in 0 .. count {
			payload := native_app_poll_reply(mut app)
			assert payload.len == 1 && payload[0] == 0
			unsafe { payload.free() }
		}
		live := C.vinix_heap_end()
		assert live == 0, 'Nonpolling native reply retained ${live} bytes for ${count} replies'
	}
}

fn test_native_child_ordinary_poll_reply_dispatch_does_not_retain_heap() {
	mut receiver := &NativeOrdinaryPollHeapReceiver{}
	mut app := NativeApp(receiver)
	for count in [100, 200]! {
		start := receiver.calls
		C.vinix_heap_begin()
		for index in 0 .. count {
			receiver.changed = index % 2 == 0
			payload := native_app_poll_reply(mut app)
			assert payload.len == 1
			assert payload[0] == u8(if receiver.changed { 1 } else { 0 })
			unsafe { payload.free() }
		}
		live := C.vinix_heap_end()
		assert receiver.calls - start == count
		assert live == 0, 'Ordinary native poll retained ${live} bytes for ${count} replies'
	}
}

fn test_native_child_paced_poll_reply_dispatch_and_growth_do_not_retain_heap() {
	mut receiver := &NativePacedPollHeapReceiver{}
	mut app := NativeApp(receiver)
	for count in [100, 200]! {
		start := receiver.calls
		C.vinix_heap_begin()
		for index in 0 .. count {
			receiver.changed = index % 2 != 0
			payload := native_app_poll_reply(mut app)
			assert payload.len == 5
			assert payload[0] == u8(if receiver.changed { 1 } else { 0 })
			interval := u32(payload[1]) | u32(payload[2]) << 8 | u32(payload[3]) << 16 | u32(payload[4]) << 24
			assert interval == u32(0x01020300 + receiver.calls)
			unsafe { payload.free() }
		}
		live := C.vinix_heap_end()
		assert receiver.calls - start == count
		assert live == 0, 'Paced native poll retained ${live} bytes for ${count} replies'
	}
}

fn test_compositor_native_poll_idle_does_not_retain_interface_wrappers() {
	mut receiver := &NativeOrdinaryPollHeapReceiver{}
	mut closed := &NativeOrdinaryPollHeapReceiver{}
	mut nonpolling := &NativeNonPollingHeapReceiver{}
	mut desktop := Desktop{dirty: false}
	desktop.apps << receiver
	desktop.apps << closed
	desktop.apps << nonpolling
	desktop.windows << Window{id: 73, page: .app, app_index: 0, width: 320, height: 240}
	desktop.windows << Window{id: 74, page: .app, app_index: 2}
	desktop.windows << Window{id: 75, page: .app, app_index: -1}
	desktop.windows << Window{id: 76, page: .app, app_index: 50}
	for count in [100, 200]! {
		start := receiver.calls
		C.vinix_heap_begin()
		for _ in 0 .. count {
			desktop.poll_apps()
			assert !desktop.dirty
			assert !desktop.frame_damage.valid()
		}
		live := C.vinix_heap_end()
		assert receiver.calls - start == count
		assert closed.calls == 0
		assert live == 0, 'Idle compositor poll retained ${live} bytes for ${count} calls'
	}
}

fn test_compositor_native_poll_changed_marks_visible_windows_without_retained_heap() {
	mut receiver := &NativePacedPollHeapReceiver{changed: true}
	mut desktop := Desktop{dirty: false}
	desktop.canvas.width = 640
	desktop.canvas.height = 480
	desktop.apps << receiver
	desktop.windows << Window{id: 91, page: .app, app_index: 0, x: 10, y: 20, width: 320, height: 240}
	for count in [100, 200]! {
		start := receiver.calls
		C.vinix_heap_begin()
		for index in 0 .. count {
			desktop.dirty = index % 2 != 0
			desktop.frame_damage = FrameDamage{}
			desktop.poll_apps()
			assert desktop.dirty == (index % 2 != 0)
			assert desktop.frame_damage.valid()
			desktop.windows[0].minimized = true
			desktop.frame_damage = FrameDamage{}
			desktop.poll_apps()
			assert !desktop.frame_damage.valid()
			desktop.windows[0].minimized = false
		}
		live := C.vinix_heap_end()
		assert receiver.calls - start == count * 2
		assert live == 0, 'Changed compositor poll retained ${live} bytes for ${count * 2} calls'
	}
}
