// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

struct NativeCloseHeapReceiver {
mut:
	allowed bool
	calls   int
}

fn (mut _ NativeCloseHeapReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }

fn (mut _ NativeCloseHeapReceiver) handle(_ string) ! {}

fn (mut a NativeCloseHeapReceiver) prepare_close() bool {
	a.calls++
	return a.allowed
}

struct NativeCloseDefaultHeapReceiver {}

fn (mut _ NativeCloseDefaultHeapReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }

fn (mut _ NativeCloseDefaultHeapReceiver) handle(_ string) ! {}

fn test_native_close_default_and_guarded_dispatch_retain_zero_bytes() {
	mut receiver := &NativeCloseHeapReceiver{}
	defer { unsafe { free(receiver) } }
	mut app := NativeApp(receiver)
	mut plain_receiver := &NativeCloseDefaultHeapReceiver{}
	defer { unsafe { free(plain_receiver) } }
	mut plain := NativeApp(plain_receiver)
	for repetitions in [100, 200]! {
		start := receiver.calls
		C.vinix_heap_begin()
		for index in 0 .. repetitions {
			receiver.allowed = index % 2 == 0
			assert native_app_prepare_close(mut app) == receiver.allowed
			assert native_app_prepare_close(mut plain)
		}
		live := C.vinix_heap_end()
		assert receiver.calls - start == repetitions
		assert live == 0
	}
}

fn test_native_close_wire_validation_and_legacy_remote_guard_retain_zero_bytes() {
	mut remote := RemoteApp{ standalone: true, request_fd: -1, response_fd: -1 }
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		for byte in [u8(0), 1, 2, 255]! {
			mut payload := []u8{cap: 1}
			payload << byte
			assert native_close_reply_allows(AppReply{ ok: true, payload: payload }) == (byte == 1)
			unsafe { payload.free() }
		}
		assert remote.prepare_close() && !remote.closed
	}
	assert C.vinix_heap_end() == 0
}

fn test_native_close_remote_round_trips_release_headers_replies_and_dispatch_receivers() {
	mut requests := [2]i32{}
	mut responses := [2]i32{}
	assert C.pipe(&requests[0]) == 0 && C.pipe(&responses[0]) == 0
	defer {
		for fd in [requests[0], requests[1], responses[0], responses[1]]! { desktop_close(fd) }
	}
	mut receiver := &RemoteApp{ request_fd: requests[1], response_fd: responses[0], peer_features: app_feature_close_guard }
	defer { unsafe { free(receiver) } }
	mut app := NativeApp(receiver)
	C.vinix_heap_begin()
	for index in 0 .. 200 {
		mut payload := []u8{cap: 1}
		payload << u8(index % 2)
		assert send_app_response(responses[1], true, AppWireState{}, payload)
		unsafe { payload.free() }
		assert native_app_prepare_close(mut app) == (index % 2 == 1)
		assert !receiver.closed
		command, _, _, _, text := receive_app_request(requests[0])!
		assert command == .prepare_close && text.len == 0
		unsafe { text.free() }
	}
	assert C.vinix_heap_end() == 0
}

fn test_native_close_related_tree_decode_reader_and_owned_elements_release_zero_bytes() {
	root := ui2.screen(0x102030, [
		ui2.clickable_view('panel', ui2.rect(0, 0, 320, 200), ui2.BoxStyle{ bg: 0xffffff }, [
			ui2.label('title', 'Native close 日本語 😀', ui2.rect(8, 8, 200, 20), ui2.TextStyle{ color: 0x111111, font_family: 'mono' }),
		]),
	])
	mut encoded := []u8{cap: 4096}
	unsafe { encoded.flags |= .noslices }
	encode_app_element(root, mut encoded)!
	free_tree(root)
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		tree := decode_app_tree(encoded)!
		assert tree.children[0].id == 'panel'
		assert tree.children[0].children[0].text == 'Native close 日本語 😀'
		free_tree(tree)
	}
	assert C.vinix_heap_end() == 0
	unsafe { encoded.free() }
}

fn test_native_close_repeated_compositor_declines_keep_session_and_window_without_retained_bytes() {
	mut receiver := &NativeCloseHeapReceiver{}
	defer { unsafe { free(receiver) } }
	mut desktop := Desktop{ running: true, focus: 91 }
	desktop.apps << receiver
	desktop.windows << Window{ id: 91, title: 'Guarded', page: .app, app_index: 0, width: 820, height: 600 }
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		desktop.close_window(91)
		assert desktop.windows.len == 1 && desktop.focus == 91
		desktop.end_session(.power_off)
		assert desktop.running && desktop.power == .keep_running
	}
	assert C.vinix_heap_end() == 0
	unsafe {
		desktop.apps.free()
		desktop.windows.free()
	}
}
