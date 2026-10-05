// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import os

struct NativeCloseTestReceiver {
mut:
	allowed bool
	calls   int
}

fn (mut _ NativeCloseTestReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }

fn (mut _ NativeCloseTestReceiver) handle(_ string) ! {}

fn (mut a NativeCloseTestReceiver) prepare_close() bool {
	a.calls++
	return a.allowed
}

struct NativeCloseDefaultTestReceiver {}

fn (mut _ NativeCloseDefaultTestReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }

fn (mut _ NativeCloseDefaultTestReceiver) handle(_ string) ! {}

fn test_native_close_optional_dispatch_allows_default_and_preserves_guard_denial() {
	mut plain_receiver := &NativeCloseDefaultTestReceiver{}
	defer { unsafe { free(plain_receiver) } }
	mut plain := NativeApp(plain_receiver)
	assert native_app_prepare_close(mut plain)
	mut receiver := &NativeCloseTestReceiver{}
	defer { unsafe { free(receiver) } }
	mut guarded := NativeApp(receiver)
	assert !native_app_prepare_close(mut guarded)
	assert receiver.calls == 1
	receiver.allowed = true
	assert native_app_prepare_close(mut guarded)
	assert receiver.calls == 2
}

fn test_native_close_reply_requires_exact_successful_one_byte_boolean() {
	for bytes in [[]u8{}, [u8(0)], [u8(2)], [u8(1), 0], [u8(0), 1], [u8(255)]]! {
		assert !native_close_reply_allows(AppReply{ ok: true, payload: bytes })
		unsafe { bytes.free() }
	}
	mut bytes := []u8{cap: 1}
	bytes << u8(1)
	assert !native_close_reply_allows(AppReply{ ok: false, payload: bytes })
	assert native_close_reply_allows(AppReply{ ok: true, payload: bytes })
	unsafe { bytes.free() }
}

fn test_native_close_dead_and_legacy_remote_clients_do_not_need_new_handshake() {
	mut closed := RemoteApp{ closed: true, request_fd: -1, response_fd: -1 }
	assert closed.prepare_close()
	mut legacy := RemoteApp{ standalone: true, request_fd: -1, response_fd: -1 }
	assert legacy.prepare_close() && !legacy.closed
	mut old_native := RemoteApp{ request_fd: -1, response_fd: -1 }
	assert old_native.prepare_close() && !old_native.closed
	mut supported := RemoteApp{ request_fd: -1, response_fd: -1, peer_features: app_feature_close_guard }
	assert !supported.prepare_close() && !supported.closed
}

fn test_native_close_remote_denial_and_malformed_replies_keep_live_transport() {
	for wire_value in [0, 1, 2, 3, 4, 5]! {
		mut requests := [2]i32{}
		mut responses := [2]i32{}
		assert C.pipe(&requests[0]) == 0 && C.pipe(&responses[0]) == 0
		defer {
			for fd in [requests[0], requests[1], responses[0], responses[1]]! { desktop_close(fd) }
		}
		mut payload := []u8{cap: 2}
		if wire_value != 3 { payload << u8(if wire_value == 5 { 1 } else { wire_value }) }
		if wire_value == 4 { payload << u8(1) }
		assert send_app_response(responses[1], wire_value != 5, AppWireState{}, payload)
		unsafe { payload.free() }
		mut remote := RemoteApp{ request_fd: requests[1], response_fd: responses[0], peer_features: app_feature_close_guard, tree_stale: false, poll_sampled: true }
		assert remote.prepare_close() == (wire_value == 1)
		assert !remote.closed && remote.tree_stale && !remote.poll_sampled
		assert C.fcntl(remote.request_fd, C.F_GETFD) >= 0 && C.fcntl(remote.response_fd, C.F_GETFD) >= 0
		command, width, height, _, text := receive_app_request(requests[0])!
		assert command == .prepare_close && width == 0 && height == 0 && text.len == 0
		unsafe { text.free() }
	}
}

fn test_native_close_compositor_restores_refused_notes_and_keeps_session_running() {
	base := os.real_path(os.temp_dir())
	pid := os.getpid().str()
	home := '${base}/vinix-close-compositor-${pid}'
	unsafe {
		base.free()
		pid.free()
	}
	os.rmdir_all(home) or {}
	os.mkdir(home)!
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut notes := new_notes_app(home)
	notes.new_note()
	assert notes.save()
	notes.focus_field(1)
	notes.key_input('\x01\x7f')
	mut desktop := Desktop{ running: true, current_workspace: 0, focus: 82 }
	desktop.apps << unsafe { &notes }
	desktop.windows << Window{ id: 81, title: 'Notes', page: .app, app_index: 0, workspace: 1, minimized: true, width: 820, height: 600 }
	desktop.windows << Window{ id: 82, title: 'System', app_index: -1 }
	desktop.close_window(81)
	assert desktop.windows.len == 2 && desktop.focus == 81
	index := desktop.window_index(81) or { panic('Notes window disappeared after close denial') }
	assert !desktop.windows[index].minimized && desktop.current_workspace == 1
	assert notes.dirty && notes.close_requested
	desktop.windows[index].minimized = true
	desktop.current_workspace = 0
	desktop.focus = 82
	desktop.end_session(.power_off)
	assert desktop.running && desktop.power == .keep_running && desktop.focus == 81
	restored := desktop.window_index(81) or { panic('Notes window disappeared after session denial') }
	assert !desktop.windows[restored].minimized && desktop.current_workspace == 1
	notes.handle('notes.keep_editing')!
	notes.focus_field(1)
	notes.paste_input('Saved before closing')
	desktop.close_window(81)
	assert desktop.windows.len == 1 && !notes.dirty
	notes.close_app()
	unsafe {
		desktop.apps.free()
		desktop.windows.free()
	}
}
