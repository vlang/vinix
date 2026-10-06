// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone host integration test for the compositor/application process
// boundary. The parent execs this same binary in app mode, exactly as the
// installed per-app symlinks do on Vinix.
module main

import os
import ui2
import encoding.base64
import math

fn tree_has_id(element ui2.Element, id string) bool {
	if element.id == id {
		return true
	}
	for child in element.children {
		if tree_has_id(child, id) {
			return true
		}
	}
	return false
}

fn tree_has_native_button(element ui2.Element, id string, checked bool) bool {
	if element.id == id {
		return element.kind == .button && element.native_style && element.checked == checked
	}
	for child in element.children {
		if tree_has_native_button(child, id, checked) {
			return true
		}
	}
	return false
}

fn tree_contains_text(element ui2.Element, text string) bool {
	if element.text.contains(text) {
		return true
	}
	for child in element.children {
		if tree_contains_text(child, text) {
			return true
		}
	}
	return false
}

fn tree_text_dump(element ui2.Element) string {
	mut text := element.text + '\n'
	for child in element.children {
		text += tree_text_dump(child)
	}
	return text
}

fn close_remote(mut app NativeApp) {
	if mut app is RemoteApp {
		app.close()
	}
}

fn main() {
	if options := app_process_options(arguments()[1..]) {
		run_app_process(options)
		return
	}
	if arguments().contains('--prepare-precision-gui') {
		image := integration_resize_source()
		defer { unsafe { image.free() } }
		os.write_file('/tmp/utility-resize-input.png', unsafe { tos(&u8(image.data), image.len) }) or { panic(err) }
		return
	}
	// The same real app/clipboard workflows run inside Vinix without the
	// host-only zero-deadline pipe timing assertions below.
	if arguments().contains('--utility-copy-integration') {
		check_utility_copy_clients()
		return
	}
	if arguments().contains('--utility-document-integration') {
		if arguments().contains('--require-vinix') { assert os.exists('/dev/processes') }
		desktop_ignore_broken_pipe()
		mut desktop := Desktop{}
		check_utility_document_clients(mut desktop)
		return
	}
	if arguments().contains('--utility-recovery-integration') {
		if arguments().contains('--require-vinix') { assert os.exists('/dev/processes') }
		desktop_ignore_broken_pipe()
		mut desktop := Desktop{}
		check_utility_recovery_clients(mut desktop)
		return
	}
	if arguments().contains('--utility-controls-integration') {
		if arguments().contains('--require-vinix') { assert os.exists('/dev/processes') }
		desktop_ignore_broken_pipe()
		mut desktop := Desktop{}
		check_utility_controls_clients(mut desktop)
		return
	}
	if arguments().contains('--utility-precision-integration') {
		if arguments().contains('--require-vinix') { assert os.exists('/dev/processes') }
		desktop_ignore_broken_pipe()
		mut desktop := Desktop{}
		check_utility_precision_clients(mut desktop)
		return
	}
	if arguments().contains('--utility-refinement-integration') {
		if arguments().contains('--require-vinix') { integration_refinement_require(os.exists('/dev/processes'), 'Refinement fixture must run inside Vinix') }
		desktop_ignore_broken_pipe()
		mut desktop := Desktop{}
		check_utility_refinement_clients(mut desktop)
		return
	}
	if arguments().contains('--utility-organize-integration') {
		if arguments().contains('--require-vinix') { assert os.exists('/dev/processes') }
		desktop_ignore_broken_pipe()
		mut desktop := Desktop{}
		check_utility_organize_clients(mut desktop)
		return
	}
	if arguments().contains('--utility-input-integration') {
		if arguments().contains('--require-vinix') { assert os.exists('/dev/processes') }
		desktop_ignore_broken_pipe()
		mut desktop := Desktop{}
		check_utility_input_clients(mut desktop)
		return
	}
	// Standalone applications receive their pipe descriptors through the
	// environment, leaving argv empty for applications that open argv[1].
	if os.getenv('VINIX_RESPONSE_FD') != '' {
		assert arguments().len == 1
		assert os.getenv('VINIX_REQUEST_FD').int() >= 3
		os.fd_write(os.getenv('VINIX_RESPONSE_FD').int(), 'S')
		return
	}
	desktop_ignore_broken_pipe()
	standalone := desktop_spawn_app(arguments()[0], 'voffice-calc', 0, 'en', true, '') or {
		panic('could not start standalone app fixture')
	}
	mut standalone_marker := [1]u8{}
	mut standalone_replied := false
	for _ in 0 .. 100 {
		if desktop_read(standalone.from_child, &standalone_marker[0], 1) == 1 {
			standalone_replied = true
			break
		}
		desktop_sleep_ms(10)
	}
	assert standalone_replied && standalone_marker[0] == `S`
	desktop_close(standalone.to_child)
	desktop_close(standalone.from_child)
	assert desktop_wait_child(standalone.pid) == 0

	// A silent application process must not be able to hold the system session
	// before its first framebuffer present (or during a later Settings action).
	// Keep the test timeout tiny; production allows a slow Vinix child five seconds.
	mut silent_pipe := [2]i32{}
	assert C.pipe(&silent_pipe[0]) == 0
	mut response_timed_out := false
	receive_app_response_with_timeout(int(silent_pipe[0]), 10) or {
		assert err.msg() == 'application response timed out'
		response_timed_out = true
	}
	assert response_timed_out
	desktop_close(int(silent_pipe[0]))
	desktop_close(int(silent_pipe[1]))
	// The timeout must also cover a client that sends a valid response header
	// and only part of its advertised tree, while keeping the pipe open.
	mut partial_pipe := [2]i32{}
	assert C.pipe(&partial_pipe[0]) == 0
	assert desktop_set_nonblocking(int(partial_pipe[0]), true)
	mut partial_header := []u8{cap: app_response_header_size}
	wire_put_u32(mut partial_header, app_protocol_magic)
	wire_put_u8(mut partial_header, app_protocol_version)
	wire_put_u8(mut partial_header, 0)
	wire_put_u8(mut partial_header, 0)
	wire_put_u8(mut partial_header, 0)
	wire_put_state(mut partial_header, AppWireState{})
	wire_put_u32(mut partial_header, 4)
	assert partial_header.len == app_response_header_size
	assert desktop_write_all(int(partial_pipe[1]), partial_header.data, u64(partial_header.len))
	assert desktop_write_all(int(partial_pipe[1]), c'x', 1)
	mut partial_timed_out := false
	receive_app_response_with_timeout(int(partial_pipe[0]), 20) or {
		assert err.msg() == 'application response payload timed out or pipe closed'
		partial_timed_out = true
	}
	assert partial_timed_out
	unsafe { partial_header.free() }
	desktop_close(int(partial_pipe[0]))
	desktop_close(int(partial_pipe[1]))
	// A deadline recheck must still accept a reply already in the pipe, and
	// readiness from a closed writer must not count as a successful response.
	mut ready_pipe := [2]i32{}
	assert C.pipe(&ready_pipe[0]) == 0
	assert desktop_set_nonblocking(int(ready_pipe[0]), true)
	assert send_app_response(int(ready_pipe[1]), true, AppWireState{}, [u8(7)])
	ready_reply := receive_app_response_with_timeout(int(ready_pipe[0]), 0) or {
		panic(err)
	}
	assert ready_reply.ok && ready_reply.payload == [u8(7)]
	unsafe { ready_reply.payload.free() }
	desktop_close(int(ready_pipe[1]))
	mut closed_response_rejected := false
	receive_app_response_with_timeout(int(ready_pipe[0]), 10) or {
		assert err.msg() == 'application response header timed out or pipe closed'
		closed_response_rejected = true
	}
	assert closed_response_rejected
	desktop_close(int(ready_pipe[0]))
	// A cold persistent home can make Files' initial directory scan slower
	// than a normal interaction. Boot-started apps get that larger budget;
	// requests after startup still fail promptly through the timeout above.
	assert app_startup_response_timeout_ms > app_response_timeout_ms

	// Remote polling is paced before a pipe request is sent. Terminal keeps a
	// short fallback cadence because its PTY echo can arrive just after the
	// immediate poll forced by a keystroke. Activity Monitor can remain slow.
	assert available_apps[3].poll_interval_ms == 100
	assert available_apps[5].poll_interval_ms == 250
	assert available_apps[8].poll_interval_ms == 100
	assert available_apps[9].poll_interval_ms == 0
	assert remote_app_poll_due(50, false, 0, 1_000)
	assert !remote_app_poll_due(50, true, 1_000, 1_049)
	assert remote_app_poll_due(50, true, 1_000, 1_050)
	assert remote_app_poll_due(50, true, 1_000, 999)
	assert remote_app_poll_due(50, true, 1_000, ~u64(0))
	mut cadence_desktop := Desktop{}
	mut cadence_app := &RemoteApp{
		polling: true
		poll_interval_ms: 1000
		poll_sampled: true
	}
	cadence_desktop.apps << cadence_app
	cadence_desktop.windows << Window{app_index: 0}
	assert cadence_desktop.idle_wait_interval(1000, 16) == 1000
	cadence_app.poll_interval_ms = 100
	assert cadence_desktop.idle_wait_interval(1000, 16) == 100
	cadence_app.poll_sampled = false
	assert cadence_desktop.idle_wait_interval(1000, 16) == 16
	// After a poll the wait runs to when the next one is due, a little past it
	// rather than a little before, and an application's own estimate replaces
	// its cadence within bounds.
	cadence_app.poll_sampled = true
	cadence_app.last_poll_ms = desktop_monotonic_ms() - 40
	remaining := cadence_desktop.idle_wait_interval(1000, 16)
	assert remaining > 60 && remaining <= 60 + poll_wake_margin_ms
	cadence_app.poll_hint_ms = 400
	assert cadence_app.next_poll_interval() == 400
	cadence_app.poll_hint_ms = 5
	assert cadence_app.next_poll_interval() == 25
	cadence_app.poll_hint_ms = 60_000
	assert cadence_app.next_poll_interval() == remote_poll_hint_max_ms
	cadence_app.poll_interval_ms = 0
	assert cadence_app.next_poll_interval() == 0

	mut desktop := Desktop{}
	mut files := start_remote_app_at_with_timeout(arguments()[0], available_apps[0], mut desktop,
		app_response_timeout_ms) or {
		panic(err)
	}
	if mut files is RemoteApp {
		assert files.pid > 0
		// Large response frames must not depend on a blocking pipe hand-off:
		// Vinix's compositor and app otherwise can both sleep while transferring
		// one tree during session startup.
		assert C.fcntl(files.response_fd, C.F_GETFL) & C.O_NONBLOCK != 0
	}
	files_tree := files.build(ui2.rect(0, 0, 460, 326)) or { panic(err) }
	assert files_tree.kind == .screen
	assert tree_has_id(files_tree, files_action_up)
	files.handle(files_action_up) or { panic(err) }
	free_tree(files_tree)
	close_remote(mut files)

	// A native application may abort for reasons outside the protocol. Its
	// process must be the only casualty: the compositor side closes the broken
	// transport and remains able to launch and render another application.
	mut crashing_files := start_remote_app_at_with_timeout(arguments()[0], available_apps[0], mut desktop,
		app_response_timeout_ms) or {
		panic(err)
	}
	mut crashed_pid := -1
	if mut crashing_files is RemoteApp {
		crashed_pid = crashing_files.pid
	}
	assert crashed_pid > 0
	assert C.kill(crashed_pid, C.SIGKILL) == 0
	mut failure_was_isolated := false
	mut first_failure := ''
	crashing_files.build(ui2.rect(0, 0, 460, 326)) or {
		failure_was_isolated = true
		first_failure = err.msg().clone()
	}
	assert failure_was_isolated
	assert first_failure != ''
	mut failure_was_preserved := false
	crashing_files.build(ui2.rect(0, 0, 460, 326)) or {
		failure_was_preserved = err.msg() == first_failure
	}
	assert failure_was_preserved
	if mut crashing_files is RemoteApp {
		assert crashing_files.closed
		assert crashing_files.failure_reason == first_failure
	}

	mut settings := start_remote_app_at_with_timeout(arguments()[0], available_apps[4], mut desktop,
		app_response_timeout_ms) or {
		panic(err)
	}
	settings.handle('${settings_action_category}1') or { panic(err) }
	settings.handle('${settings_action_theme}1') or { panic(err) }
	assert desktop.settings.theme == .macos
	settings.handle('${settings_action_category}${settings_categories.index(SettingsCategory.display)}') or {
		panic(err)
	}
	settings.handle(settings_scale_200_action) or { panic(err) }
	assert desktop_requested_scale() == desktop_scale_200
	settings_tree := settings.build(ui2.rect(0, 0, 620, 386)) or { panic(err) }
	assert settings_tree.kind == .screen
	assert tree_has_id(settings_tree, settings_scale_100_action)
	assert tree_has_native_button(settings_tree, settings_scale_100_action, false)
	assert tree_has_native_button(settings_tree, settings_scale_200_action, true)
	free_tree(settings_tree)
	close_remote(mut settings)

	mut capture := start_remote_app_at_with_timeout(arguments()[0], available_apps[14], mut desktop,
		app_response_timeout_ms) or {
		panic(err)
	}
	capture_tree := capture.build(ui2.rect(0, 0, 560, 396)) or { panic(err) }
	assert tree_has_id(capture_tree, capture_action_take_screenshot)
	free_tree(capture_tree)
	capture.handle(capture_action_delay_5) or { panic(err) }
	capture.handle(capture_action_take_screenshot) or { panic(err) }
	assert desktop.capture.request.command == .screenshot
	assert desktop.capture.request.delay == 5
	assert desktop.capture.report.phase == .screenshot_countdown
	capture.handle(capture_action_stop) or { panic(err) }
	assert desktop.capture.report.phase == .cancelled
	close_remote(mut capture)

	// Maximising a window asks its application to lay itself out again at the
	// new size. The terminal rebuilds its grid there, and releasing the old
	// row cache twice used to abort the application process, leaving the
	// window able to report only that its application had stopped drawing.
	mut terminal := start_remote_app_at_with_timeout(arguments()[0], available_apps[3], mut desktop,
		app_response_timeout_ms) or {
		panic(err)
	}
	terminal_tree := terminal.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
	assert terminal_tree.kind == .screen
	free_tree(terminal_tree)
	maximized_tree := terminal.build(ui2.rect(0, 0, 1780, 1264)) or { panic(err) }
	assert maximized_tree.kind == .screen
	free_tree(maximized_tree)
	restored_tree := terminal.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
	assert restored_tree.kind == .screen
	free_tree(restored_tree)

	// Keyboard input crosses the app pipe and then the PTY. The first forced
	// poll can beat the slave's echo, so prove the Terminal's fallback cadence
	// makes ordinary typing visible promptly through the real remote process.
	if os.exists(terminal_shell) {
		if mut terminal is RemoteApp {
			terminal.key_input('vinix-remote-input')
			mut echoed := false
			for _ in 0 .. 20 {
				terminal.poll()
				input_tree := terminal.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
				echoed = tree_contains_text(input_tree, 'vinix-remote-input')
				free_tree(input_tree)
				if echoed {
					break
				}
				desktop_sleep_ms(10)
			}
			assert echoed
		}
	}
	close_remote(mut terminal)
	check_scientific_calculator_client(mut desktop)
	check_new_utility_clients(mut desktop)
	check_storage_utility_clients(mut desktop)
	check_productivity_utility_clients(mut desktop)
	check_current_utility_workflow_clients(mut desktop)
	check_utility_document_clients(mut desktop)
	check_utility_recovery_clients(mut desktop)
	check_utility_controls_clients(mut desktop)
	check_utility_precision_clients(mut desktop)
	check_utility_refinement_clients(mut desktop)
	check_utility_input_clients(mut desktop)
	check_utility_organize_clients(mut desktop)
	desktop_restore_requested_scale()
}

fn integration_assert_file(path string, expected string) {
	actual := os.read_file(path) or { panic(err) }
	defer { unsafe { actual.free() } }
	assert actual == expected, path
}

fn integration_assert_text(mut app NativeApp, size ui2.Rect, expected string) {
	tree := app.build(size) or { panic(err) }
	defer { free_tree(tree) }
	assert tree_contains_text(tree, expected), 'Missing ${expected}: ${tree_text_dump(tree)}'
}

// These workflows share a canonical temporary user home, so process-local
// profile resolution and filesystem changes cannot reach a real user profile.
fn check_current_utility_workflow_clients(mut desktop Desktop) {
	base := os.real_path(os.temp_dir())
	home := join_path(base, 'vinix-workflows-ipc-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_dictionary_workflow_client(home, mut desktop)
	check_calendar_interchange_client(home, mut desktop)
	check_editor_workflow_client(home, mut desktop)
	check_files_trash_client(home, mut desktop)
	check_programmer_calculator_client(mut desktop)
	check_editor_selection_client(home)
	check_settings_search_client(mut desktop)
	check_activity_view_client(home, mut desktop)
	check_terminal_copy_client(mut desktop)
	check_preview_orientation_client(home, mut desktop)
}

fn check_utility_copy_clients() {
	desktop_ignore_broken_pipe()
	base := os.real_path(os.temp_dir())
	home := join_path(base, 'vinix-copy-ipc-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	mut desktop := Desktop{home: home}
	defer {
		desktop_user_home = previous_home
		desktop.clipboard.close_request()
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_dictionary_workflow_client(home, mut desktop)
	check_scientific_calculator_client(mut desktop)
	check_programmer_calculator_client(mut desktop)
	check_terminal_copy_client(mut desktop)
	check_preview_orientation_client(home, mut desktop)
	if arguments().contains('--require-vinix') { assert os.exists('/dev/processes') }
	println('IPC utility copy workflows passed')
}

// A focused entry point runs the same real child processes on the host and
// in Vinix. Its temporary home and all output paths are owned by this wrapper.
fn check_utility_document_clients(mut desktop Desktop) {
	temporary := os.temp_dir()
	mut canonical := [4096]u8{}
	assert unsafe { C.realpath(&char(temporary.str), &char(&canonical[0])) } != unsafe { nil }
	unsafe { temporary.free() }
	mut length := 0
	for length < canonical.len && canonical[length] != 0 { length++ }
	assert length > 0 && length < canonical.len
	base := unsafe { tos(&canonical[0], length) }.clone()
	pid := os.getpid().str()
	name := 'vinix-documents-ipc-${pid}'
	home := system_information_join_path(base, name)
	unsafe { pid.free(); name.free() }
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_preview_crop_client(home, mut desktop)
	check_grapher_document_client(home, mut desktop)
	check_archive_selection_client(home, mut desktop)
	check_system_information_search_client(home, mut desktop)
	println('IPC utility document workflows passed')
}

fn check_utility_recovery_clients(mut desktop Desktop) {
	temporary := os.temp_dir()
	mut canonical := [4096]u8{}
	assert unsafe { C.realpath(&char(temporary.str), &char(&canonical[0])) } != unsafe { nil }
	unsafe { temporary.free() }
	mut length := 0
	for length < canonical.len && canonical[length] != 0 { length++ }
	assert length > 0 && length < canonical.len
	base := unsafe { tos(&canonical[0], length) }.clone()
	pid := os.getpid().str()
	name := 'vinix-recovery-ipc-${pid}'
	home := system_information_join_path(base, name)
	unsafe { pid.free(); name.free() }
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		desktop.clipboard.close_request()
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_preview_crop_recovery_client(home, mut desktop, true)
	check_hyperbolic_calculator_client(mut desktop)
	check_calendar_search_client(home, mut desktop)
	check_disk_usage_capacity_client(home, mut desktop)
	println('IPC utility recovery workflows passed')
}

fn integration_tree_enabled(element ui2.Element, id string) bool {
	if element.id == id || element.action_id == id { return element.enabled }
	for child in element.children {
		if integration_tree_enabled(child, id) { return true }
	}
	return false
}

fn check_utility_controls_clients(mut desktop Desktop) {
	temporary := os.temp_dir()
	base := os.real_path(temporary)
	pid := os.getpid().str()
	name := 'vinix-controls-ipc-${pid}'
	home := system_information_join_path(base, name)
	unsafe { temporary.free(); pid.free(); name.free() }
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		desktop.clipboard.close_request()
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_grapher_png_client(home, mut desktop)
	check_notes_history_client(mut desktop)
	check_clock_named_timer_client(mut desktop)
	check_color_meter_client()
	println('IPC utility controls workflows passed')
}

fn check_utility_precision_clients(mut desktop Desktop) {
	temporary := os.temp_dir()
	base := os.real_path(temporary)
	pid := os.getpid().str()
	name := 'vinix-precision-ipc-${pid}'
	home := system_information_join_path(base, name)
	unsafe { temporary.free(); pid.free(); name.free() }
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		desktop.clipboard.close_request()
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_clock_duration_client(mut desktop)
	check_preview_resize_client(home, mut desktop)
	check_calculator_precision_client(mut desktop)
	check_grapher_compact_client(home, mut desktop)
	println('IPC utility precision workflows passed')
}

// Critical golden checks remain executable independently of V assertions.
// The suite also rejects production builds, where ordinary assertions vanish.
fn integration_refinement_require(condition bool, message string) {
	if !condition { eprintln(message) C.exit(97) }
	assert condition, message
}

fn integration_refinement_file(path string, expected string) {
	actual := os.read_file(path) or { panic(err) }
	defer { unsafe { actual.free() } }
	integration_refinement_require(actual == expected, 'IPC refinement file bytes differ')
}

fn check_utility_refinement_clients(mut desktop Desktop) {
	$if prod { eprintln('Utility refinement integration requires enabled assertions') C.exit(96) }
	temporary := os.temp_dir()
	base := os.real_path(temporary)
	pid := os.getpid().str()
	name := 'vinix-refinement-ipc-${pid}'
	home := system_information_join_path(base, name)
	unsafe { temporary.free(); pid.free(); name.free() }
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		desktop.clipboard.close_request()
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_calculator_bits_client(mut desktop)
	check_reminders_direction_client(home, mut desktop)
	check_grapher_svg_client(home, mut desktop)
	check_notes_import_client(home, mut desktop)
	println('IPC utility refinement workflows passed')
}

fn check_calculator_bits_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-calculator') or { panic('Calculator is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	if mut app is RemoteApp { assert app.pid > 0 && app.keyboard; app.key_input('2+3') }
	app.handle('calculator.mode.programmer') or { panic(err) }
	app.handle('calculator.programmer.width.8') or { panic(err) }
	app.handle('calculator.programmer.base.hex') or { panic(err) }
	if mut app is RemoteApp { app.paste_input('0xA'); app.key_input('+') }
	app.handle('calculator.programmer.bits') or { panic(err) }
	bits := app.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
	bit := integration_element_named(bits, 'calculator.programmer.bit.3') or { panic('missing serialized bit 3') }
	integration_refinement_require(bit.text == '1' && bit.checked, 'Initial programmer bit 3 must be set')
	assert !tree_has_id(bits, 'calculator.programmer.bit.8')
	app.handle(if bit.action_id.len > 0 { bit.action_id } else { bit.id }) or { panic(err) }
	free_tree(bits)
	integration_assert_integer(mut app, ['2', '2', '2', '10']!)
	if mut app is RemoteApp { app.key_input('=') }
	integration_assert_integer(mut app, ['12', 'C', '14', '1100']!)
	app.handle('calculator.programmer.bit.0') or { panic(err) }
	if mut app is RemoteApp { app.key_input('=') }
	integration_assert_integer(mut app, ['15', 'F', '17', '1111']!)
	app.handle('calculator.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, 'F')
	integration_assert_text(mut app, ui2.rect(0, 0, 620, 576), tr('clipboard.copy.copied'))
	app.handle('calculator.programmer.width.64') or { panic(err) }
	for _ in 0 .. 7 { app.handle('calculator.programmer.bits.next') or { panic(err) } }
	high := app.build(ui2.rect(0, 0, 180, 300)) or { panic(err) }
	integration_refinement_require((integration_tree_text(high, 'calculator.programmer.bits.range') or { panic('missing high byte range') }) == '63 - 56', 'Compact bit page must show the high byte')
	assert tree_has_id(high, 'calculator.programmer.bit.63') && !tree_has_id(high, 'calculator.programmer.bit.0')
	for child in high.children { integration_assert_frame_inside(child, 180, 300) }
	free_tree(high)
	app.handle('calculator.programmer.bit.63') or { panic(err) }
	wide := app.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
	integration_refinement_require((integration_programmer_readout(wide, 0) or { panic('missing wide integer') }) == '9223372036854775823', 'Bit 63 must retain all lower bits exactly')
	free_tree(wide)
	app.handle('calculator.programmer.history.1') or { panic(err) }
	integration_assert_integer(mut app, ['12', 'C', '14', '1100']!)
	recalled := app.build(ui2.rect(0, 0, 180, 300)) or { panic(err) }
	integration_refinement_require((integration_tree_text(recalled, 'calculator.programmer.bits.range') or { panic('missing restored byte range') }) == '7 - 0', 'History must restore width and clamp the compact bit page')
	assert tree_has_id(recalled, 'calculator.programmer.bit.7') && !tree_has_id(recalled, 'calculator.programmer.bit.63')
	free_tree(recalled)
	app.handle('calculator.programmer.bit.63') or { panic(err) }
	integration_assert_integer(mut app, ['12', 'C', '14', '1100']!)
	app.handle('calculator.programmer.bits') or { panic(err) }
	app.handle('calculator.programmer.bits') or { panic(err) }
	app.handle('calculator.mode.basic') or { panic(err) }
	if mut app is RemoteApp { app.key_input('=') }
	integration_assert_calculator_display(mut app, '5')
	println('IPC Calculator Bits, pending/repeated operands, high bit, width/page/history, Copy and Basic state passed')
}

fn integration_refinement_reminders_rows(mut app NativeApp, expected [5]int) {
	tree := app.build(ui2.rect(0, 0, 800, 736)) or { panic(err) }
	defer { free_tree(tree) }
	mut row := 0
	for child in tree.children {
		if !child.id.starts_with('reminders.row.') { continue }
		index := calendar_integer(console_borrow(child.id, 14, child.id.len)) or { panic('invalid serialized task identity') }
		integration_refinement_require(row < expected.len && index == expected[row], 'Reminders visible row order differs from the golden order')
		assert child.frame.y == f64(200 + row * 40)
		row++
	}
	integration_refinement_require(row == expected.len, 'Reminders must show every expected task')
}

fn check_reminders_direction_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, '.vinix-reminders')
	export := system_information_join_path(home, 'directions.csv')
	defer { unsafe { path.free(); export.free() } }
	record := 'VINIX-REMINDERS 2\n0\t0\t\tZeta\n0\t3\t2028-02-29 09:00\talpha\n1\t3\t2028-02-29\tAlpha\n0\t1\t2028-02-29 09:00\talpha\n0\t2\t\tUndated\n'
	os.write_file(path, record) or { panic(err) }
	factory := app_factory_named('vinix-reminders') or { panic('Reminders is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	integration_refinement_reminders_rows(mut app, [0, 1, 2, 3, 4]!)
	app.handle('reminders.direction.toggle') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [4, 3, 2, 1, 0]!)
	app.handle('reminders.sort.priority') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [1, 2, 4, 3, 0]!)
	app.handle('reminders.direction.toggle') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [0, 3, 4, 1, 2]!)
	app.handle('reminders.row.3') or { panic(err) }
	app.handle('reminders.edit') or { panic(err) }
	storage_remote_field(mut app, 'reminders.title', 'Direction draft stays attached')
	app.handle('reminders.priority.high') or { panic(err) }
	app.handle('reminders.sort.due') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [2, 1, 3, 0, 4]!)
	app.handle('reminders.direction.toggle') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [1, 3, 2, 0, 4]!)
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 736), 'Direction draft stays attached')
	app.handle('reminders.sort.title') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [2, 4, 0, 1, 3]!)
	app.handle('reminders.direction.toggle') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [1, 3, 0, 4, 2]!)
	app.handle('reminders.cancel') or { panic(err) }
	app.handle('reminders.sort.due') or { panic(err) }
	integration_refinement_reminders_rows(mut app, [1, 3, 2, 0, 4]!)
	storage_remote_field(mut app, 'reminders.export_path', export)
	app.handle('reminders.export_csv') or { panic(err) }
	integration_refinement_file(export, '"Title","Due","Completed (0 or 1)","Priority"\n"alpha","2028-02-29 09:00",0,"High"\n"alpha","2028-02-29 09:00",0,"Low"\n"Alpha","2028-02-29",1,"High"\n"Zeta","",0,"None"\n"Undated","",0,"Medium"\n')
	integration_refinement_file(path, record)
	app.handle('reminders.export_csv') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 736), tr('reminders.export_exists'))
	integration_refinement_file(path, record)
	println('IPC Reminders four directions, stable ties, undated-last, retained draft, exact ordered CSV and unchanged record passed')
}

fn check_grapher_svg_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, 'vector-Ж.svg')
	document := system_information_join_path(home, 'vector.vgraph')
	escaped := system_information_join_path(home, 'vector-text.xml')
	defer { unsafe { path.free(); document.free(); escaped.free() } }
	factory := app_factory_named('vinix-grapher') or { panic('Grapher is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	for index, value in ['sqrt(x)', '-2', '2', '-1', '2']! { storage_remote_field(mut app, grapher_field_actions[index], value) }
	app.handle('grapher.plot') or { panic(err) }
	storage_remote_field(mut app, 'grapher.document_path', document)
	app.handle('grapher.document_save_as') or { panic(err) }
	storage_remote_field(mut app, 'grapher.svg_path', path)
	page := app.build(ui2.rect(0, 0, 320, 340)) or { panic(err) }
	assert tree_has_id(page, 'grapher.svg_path') && tree_has_id(page, 'grapher.export_svg')
	for child in page.children { integration_assert_frame_inside(child, 320, 340) }
	free_tree(page)
	app.handle('grapher.export_svg') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 320, 340), tr('grapher.svg_saved'))
	svg := os.read_file(path) or { panic(err) }
	defer { unsafe { svg.free() } }
	integration_refinement_require(svg.starts_with('<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="960" height="640" viewBox="0 0 960 640">\n') && svg.ends_with('</g></svg>\n'), 'Grapher must write a standalone SVG document')
	integration_refinement_require(svg.contains('<desc>y = sqrt(x)</desc>') && svg.contains('<path id="curve"') && svg.contains('clip-path="url(#plot)"'), 'Grapher SVG must contain the plotted expression and clipped vector curve')
	assert !svg.contains('nan') && !svg.contains('NaN') && !svg.contains('Infinity')
	app.handle('grapher.export_svg') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 320, 340), tr('grapher.svg_exists'))
	integration_refinement_file(path, svg)
	integration_refinement_file(document, 'VINIX-GRAPH 1\nexpression=sqrt(x)\nxmin=-2\nxmax=2\nymin=-1\nymax=2\n')
	// Math expression syntax has no XML metacharacters. Exercise the same
	// streaming text method separately with an immutable escaped UTF-8 golden.
	fd := C.open(&char(escaped.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	integration_refinement_require(fd >= 0, 'Cannot create SVG escaping fixture')
	mut stream := GrapherSvgStream{fd: fd}
	stream.append('<text>')
	stream.text('& < > " \' Ж 日本語')
	stream.append('</text>\n')
	stream.flush()
	written := stream.ok
	closed := desktop_close(fd) == 0
	integration_refinement_require(written && closed, 'Grapher text streaming failed')
	integration_refinement_file(escaped, '<text>&amp; &lt; &gt; &quot; &apos; Ж 日本語</text>\n')
	println('IPC Grapher SVG standalone vector, UTF-8 XML escaping, exclusive export and unchanged vgraph passed')
}

fn integration_refinement_notes_body(mut app NativeApp, expected string) {
	tree := app.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	defer { free_tree(tree) }
	body := integration_element_named(tree, 'notes.body') or { panic('missing Notes body') }
	mut bytes := []u8{cap: notes_body_limit}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut rows := 0
	for child in body.children {
		if child.kind != .label { continue }
		if rows > 0 { bytes << `\n` }
		editor_append(mut bytes, child.text)
		rows++
	}
	integration_refinement_require(editor_bytes_text(bytes) == expected, 'Notes body differs from the preserved UTF-8 draft')
}

fn check_notes_import_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, 'Imported café 日本語.TXT')
	invalid := system_information_join_path(home, 'invalid.txt')
	store := system_information_join_path(home, '.vinix-notes')
	defer { unsafe { path.free(); invalid.free(); store.free() } }
	os.write_file(path, '\xef\xbb\xbfImported café 日本語\r\nsecond\rthird\n') or { panic(err) }
	os.write_file(invalid, '\xff') or { panic(err) }
	factory := app_factory_named('vinix-notes') or { panic('Notes is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('notes.new') or { panic(err) }
	storage_remote_field(mut app, 'notes.title', 'Draft kept')
	storage_remote_field(mut app, 'notes.body', 'Original body')
	app.handle('notes.save') or { panic(err) }
	storage_remote_field(mut app, 'notes.body', 'Unsaved café 日本語\nsecond line')
	app.handle('notes.import') or { panic(err) }
	storage_remote_field(mut app, 'notes.import_path', path)
	app.handle('notes.import_confirm') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 820, 576), tr('notes.import_saved'))
	integration_refinement_notes_body(mut app, 'Imported café 日本語\nsecond\nthird\n')
	expected := 'VINIX-NOTES 1\n3\n1 10 35\nDraft keptUnsaved café 日本語\nsecond line\n2 24 38\nImported café 日本語Imported café 日本語\nsecond\nthird\n\n'
	integration_refinement_file(store, expected)
	imported := app.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_has_id(imported, 'notes.row.0') && tree_has_id(imported, 'notes.row.1') && !tree_has_id(imported, 'notes.row.2')
	assert !integration_tree_enabled(imported, 'notes.undo') && !integration_tree_enabled(imported, 'notes.redo')
	free_tree(imported)
	storage_remote_field(mut app, 'notes.body', 'Kept body and history')
	app.handle('notes.import') or { panic(err) }
	storage_remote_field(mut app, 'notes.import_path', path)
	app.handle('notes.import_cancel') or { panic(err) }
	// A stale confirm with a valid retained source must not add a third note.
	app.handle('notes.import_confirm') or { panic(err) }
	integration_refinement_notes_body(mut app, 'Kept body and history')
	integration_refinement_file(store, expected)
	app.handle('notes.import') or { panic(err) }
	storage_remote_field(mut app, 'notes.import_path', invalid)
	app.handle('notes.import_confirm') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 820, 576), tr('notes.invalid_text'))
	integration_refinement_file(store, expected)
	app.handle('notes.import_cancel') or { panic(err) }
	app.handle('notes.import_confirm') or { panic(err) }
	integration_refinement_notes_body(mut app, 'Kept body and history')
	app.handle('notes.undo') or { panic(err) }
	integration_refinement_notes_body(mut app, 'Imported café 日本語\nsecond\nthird\n')
	app.handle('notes.redo') or { panic(err) }
	integration_refinement_notes_body(mut app, 'Kept body and history')
	mut writer := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut writer) }
	writer.handle('notes.row.1') or { panic(err) }
	storage_remote_field(mut writer, 'notes.body', 'Other window')
	writer.handle('notes.save') or { panic(err) }
	changed := 'VINIX-NOTES 1\n3\n1 10 35\nDraft keptUnsaved café 日本語\nsecond line\n2 24 12\nImported café 日本語Other window\n'
	integration_refinement_file(store, changed)
	app.handle('notes.import') or { panic(err) }
	storage_remote_field(mut app, 'notes.import_path', path)
	app.handle('notes.import_confirm') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 820, 576), tr('notes.conflict'))
	integration_refinement_file(store, changed)
	app.handle('notes.import_cancel') or { panic(err) }
	app.handle('notes.import_confirm') or { panic(err) }
	integration_refinement_notes_body(mut app, 'Kept body and history')
	app.handle('notes.undo') or { panic(err) }
	integration_refinement_notes_body(mut app, 'Imported café 日本語\nsecond\nthird\n')
	app.handle('notes.redo') or { panic(err) }
	integration_refinement_notes_body(mut app, 'Kept body and history')
	integration_refinement_file(store, changed)
	println('IPC Notes UTF-8 BOM/CRLF import, atomic draft/new note, invalid/conflicting import, history and stale confirmation passed')
}

fn check_utility_input_clients(mut desktop Desktop) {
	temporary := os.temp_dir()
	base := os.real_path(temporary)
	pid := os.getpid().str()
	name := 'vinix-input-ipc-${pid}'
	home := system_information_join_path(base, name)
	unsafe { temporary.free(); pid.free(); name.free() }
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		desktop.clipboard.close_request()
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_calculator_random_client(mut desktop)
	check_reminders_priority_client(home, mut desktop)
	check_capture_cursor_client(mut desktop)
	check_terminal_word_line_client(mut desktop)
	println('IPC utility input workflows passed')
}

fn check_utility_organize_clients(mut desktop Desktop) {
	temporary := os.temp_dir()
	base := os.real_path(temporary)
	pid := os.getpid().str()
	name := 'vinix-organize-ipc-${pid}'
	home := system_information_join_path(base, name)
	unsafe { temporary.free(); pid.free(); name.free() }
	os.mkdir(home) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = home
	defer {
		desktop_user_home = previous_home
		desktop.clipboard.close_request()
		os.rmdir_all(home) or {}
		unsafe { base.free(); home.free() }
	}
	check_calculator_width_client(mut desktop)
	check_reminders_sort_client(home, mut desktop)
	check_console_severity_client(home, mut desktop)
	check_terminal_block_client(mut desktop)
	println('IPC utility organize workflows passed')
}

fn check_calculator_width_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-calculator') or { panic('Calculator is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	if mut app is RemoteApp { app.key_input('2+3\x10') }
	app.handle('calculator.programmer.width.8') or { panic(err) }
	if mut app is RemoteApp { app.paste_input('255'); app.key_input('+1=') }
	integration_assert_integer(mut app, ['0', '0', '0', '0']!)
	app.handle('calculator.programmer.not') or { panic(err) }
	integration_assert_integer(mut app, ['255', 'FF', '377', '11111111']!)
	app.handle('calculator.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, '255')
	if mut app is RemoteApp { app.paste_input('256') }
	integration_assert_text(mut app, ui2.rect(0, 0, 620, 576), tr('calculator.programmer.error.range'))
	integration_assert_integer(mut app, ['255', 'FF', '377', '11111111']!)
	app.handle('calculator.programmer.clear') or { panic(err) }
	app.handle('calculator.programmer.width.16') or { panic(err) }
	if mut app is RemoteApp { app.paste_input('65535'); app.key_input('+1=') }
	app.handle('calculator.programmer.not') or { panic(err) }
	app.handle('calculator.programmer.width.8') or { panic(err) }
	integration_assert_integer(mut app, ['255', 'FF', '377', '11111111']!)
	app.handle('calculator.programmer.history.0') or { panic(err) }
	integration_assert_integer(mut app, ['65535', 'FFFF', '177777', '1111111111111111']!)
	tree := app.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
	width := integration_element_named(tree, 'calculator.programmer.width.16') or { panic('missing width choice') }
	assert width.checked && width.text == tr('calculator.programmer.width.16')
	free_tree(tree)
	app.handle('calculator.programmer.width.8') or { panic(err) }
	app.handle('calculator.programmer.width.64') or { panic(err) }
	integration_assert_integer(mut app, ['255', 'FF', '377', '11111111']!)
	app.handle('calculator.mode.basic') or { panic(err) }
	if mut app is RemoteApp { app.key_input('=') }
	integration_assert_calculator_display(mut app, '5')
	println('IPC Calculator widths, modular results, narrowing, history restore, Copy and Basic state passed')
}

fn integration_assert_reminders_order(mut app NativeApp, expected [3]string) {
	// The Direction row leaves three task slots at height 656 (two at 616).
	tree := app.build(ui2.rect(0, 0, 800, 656)) or { panic(err) }
	defer { free_tree(tree) }
	mut row := 0
	for child in tree.children {
		if !child.id.starts_with('reminders.row.') { continue }
		assert row < expected.len && child.id == expected[row]
		row++
	}
	assert row == expected.len
}

fn check_reminders_sort_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, '.vinix-reminders')
	export := system_information_join_path(home, 'sorted.csv')
	defer { unsafe { path.free(); export.free() } }
	record := 'VINIX-REMINDERS 2\n0\t1\t2026-10-08\tZebra\n0\t3\t2026-10-07 09:00\tBeta\n0\t3\t2026-10-07\tAlpha\n'
	os.write_file(path, record) or { panic(err) }
	factory := app_factory_named('vinix-reminders') or { panic('Reminders is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	integration_assert_reminders_order(mut app, ['reminders.row.0', 'reminders.row.1', 'reminders.row.2']!)
	app.handle('reminders.row.0') or { panic(err) }
	app.handle('reminders.sort.priority') or { panic(err) }
	integration_assert_reminders_order(mut app, ['reminders.row.1', 'reminders.row.2', 'reminders.row.0']!)
	app.handle('reminders.edit') or { panic(err) }
	editor := app.build(ui2.rect(0, 0, 800, 616)) or { panic(err) }
	title_field := integration_element_named(editor, 'reminders.title') or { panic('missing title editor') }
	assert title_field.children.len == 1 && title_field.children[0].kind == .text_field
	assert title_field.children[0].text == 'Zebra'
	free_tree(editor)
	storage_remote_field(mut app, 'reminders.title', 'unsaved draft')
	app.handle('reminders.sort.due') or { panic(err) }
	integration_assert_reminders_order(mut app, ['reminders.row.2', 'reminders.row.1', 'reminders.row.0']!)
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 616), 'unsaved draft')
	app.handle('reminders.cancel') or { panic(err) }
	app.handle('reminders.sort.title') or { panic(err) }
	integration_assert_reminders_order(mut app, ['reminders.row.2', 'reminders.row.1', 'reminders.row.0']!)
	storage_remote_field(mut app, 'reminders.export_path', export)
	app.handle('reminders.export_csv') or { panic(err) }
	csv := os.read_file(export) or { panic(err) }
	defer { unsafe { csv.free() } }
	assert csv.ends_with('"Alpha","2026-10-07",0,"High"\n"Beta","2026-10-07 09:00",0,"High"\n"Zebra","2026-10-08",0,"Low"\n')
	integration_assert_file(path, record)
	app.handle('reminders.sort.title') or { panic(err) }
	if mut app is RemoteApp { app.key_input('\x1b[C') }
	integration_assert_reminders_order(mut app, ['reminders.row.0', 'reminders.row.1', 'reminders.row.2']!)
	close_remote(mut app)
	mut reopened := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut reopened) }
	integration_assert_reminders_order(mut reopened, ['reminders.row.0', 'reminders.row.1', 'reminders.row.2']!)
	integration_assert_file(path, record)
	println('IPC Reminders stable sort modes, row identity, draft preservation, ordered CSV and unchanged record passed')
}

fn check_console_severity_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, 'levels.log')
	export := system_information_join_path(home, 'errors.txt')
	defer { unsafe { path.free(); export.free() } }
	os.write_file(path, 'INFO keep\nERROR keep caf\xc3\xa9\nWARN retry\nplain ERROR keep\nDEBUG keep\n') or { panic(err) }
	factory := app_factory_named('vinix-console') or { panic('Console is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	storage_remote_field(mut app, 'console.path', path)
	app.handle('console.load') or { panic(err) }
	storage_remote_field(mut app, 'console.filter', 'keep')
	app.handle('console.severity.error') or { panic(err) }
	tree := app.build(ui2.rect(0, 0, 800, 536)) or { panic(err) }
	assert tree_contains_text(tree, 'ERROR keep caf\xc3\xa9') && !tree_contains_text(tree, 'INFO keep')
	assert !tree_contains_text(tree, 'plain ERROR keep') && !tree_contains_text(tree, 'DEBUG keep')
	free_tree(tree)
	storage_remote_field(mut app, 'console.export_path', export)
	app.handle('console.export') or { panic(err) }
	integration_assert_file(export, 'ERROR keep caf\xc3\xa9\n')
	app.handle('console.severity.unmarked') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 536), 'plain ERROR keep')
	app.handle('console.export') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 536), tr('console.export_exists'))
	integration_assert_file(export, 'ERROR keep caf\xc3\xa9\n')
	os.write_file(path, '[WARN] keep replacement\n') or { panic(err) }
	app.handle('console.refresh') or { panic(err) }
	app.handle('console.severity.warning') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 380, 400), '[WARN] keep replacement')
	tiny := app.build(ui2.rect(0, 0, 240, 180)) or { panic(err) }
	assert tree_has_id(tiny, 'console.resize')
	for child in tiny.children { integration_assert_frame_inside(child, 240, 180) }
	free_tree(tiny)
	println('IPC Console explicit levels, text intersection, exact UTF-8 export, protected output and refresh passed')
}

fn check_terminal_block_client(mut desktop Desktop) {
	assert os.exists(terminal_shell), 'Terminal block selection needs the installed shell'
	factory := app_factory_named('vinix-terminal') or { panic('Terminal is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	free_tree(app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) })
	integration_wait_terminal_prompt(mut app)
	if mut app is RemoteApp { app.key_input("\x15printf 'blockA caf\\303\\251\\n\\nblockC Z\\n'\r") }
	mut first_y := 0
	mut last_y := 0
	mut stable := 0
	mut found := false
	for _ in 0 .. 300 {
		if mut app is RemoteApp { app.poll() }
		tree := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
		mut next_first := 0
		mut next_last := 0
		for child in tree.children {
			if child.text == 'blockA caf\xc3\xa9' { next_first = int(child.frame.y) + 4 }
			if child.text == 'blockC Z' { next_last = int(child.frame.y) + 4 }
		}
		free_tree(tree)
		stable = if next_first > 0 && next_last == next_first + 2 * terminal_row_height
			&& next_first == first_y && next_last == last_y { stable + 1 } else { 0 }
		first_y = next_first
		last_y = next_last
		found = stable >= 3
		if found { break }
		desktop_sleep_ms(100)
	}
	if !found {
		tree := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
		eprintln('IPC Terminal block rows did not settle; rendered text follows:')
		for child in tree.children { if child.text.len > 0 { eprintln(child.text) } }
		free_tree(tree)
	}
	assert found
	app.handle(terminal_action_selection_mode) or { panic(err) }
	if mut app is RemoteApp {
		app.pointer_event(.down, .left, 0, terminal_padding + 7 * terminal_column_width, first_y, 560, 316)
		app.pointer_event(.move, .no_button, 0, terminal_padding + 11 * terminal_column_width, last_y, 560, 316)
		app.pointer_event(.up, .left, 0, terminal_padding + 11 * terminal_column_width, last_y, 560, 316)
	}
	app.handle(terminal_action_copy) or { panic(err) }
	integration_assert_clipboard(&desktop, 'caf\xc3\xa9\n    \nZ   ')
	app.handle(terminal_action_selection_mode) or { panic(err) }
	text := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
	mode := integration_element_named(text, terminal_action_selection_mode) or { panic('missing selection mode') }
	assert !mode.checked && mode.text == tr('terminal.selection.text')
	assert !integration_tree_enabled(text, terminal_action_copy)
	free_tree(text)
	if mut app is RemoteApp {
		for _ in 0 .. 2 {
			app.pointer_event(.down, .left, 0, terminal_padding + 8 * terminal_column_width, first_y, 560, 316)
			app.pointer_event(.up, .left, 0, terminal_padding + 8 * terminal_column_width, first_y, 560, 316)
		}
		app.key_input(terminal_key_cmd_copy)
	}
	integration_assert_clipboard(&desktop, 'caf\xc3\xa9')
	println('IPC Terminal block UTF-8/blank-row padding, clipboard acknowledgement and restored word selection passed')
}

fn check_calculator_random_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-calculator') or { panic('Calculator is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('calculator.mode.scientific') or { panic(err) }
	if mut app is RemoteApp { app.key_input('7') }
	app.handle('calculator.memory.add') or { panic(err) }
	if mut app is RemoteApp { app.key_input('c1+2=c2+1e-') }
	app.handle('calculator.scientific.random') or { panic(err) }
	tree := app.build(ui2.rect(0, 0, 620, 566)) or { panic(err) }
	value := (integration_tree_text(tree, 'display') or { panic('missing Calculator display') }).clone()
	defer { unsafe { value.free() } }
	assert tree_has_id(tree, 'calculator.scientific.random')
	assert tree_contains_text(tree, '1 + 2 = 3')
	unavailable := tree_contains_text(tree, tr('calculator.random.unavailable'))
	free_tree(tree)
	if unavailable {
		// A guest without entropy must preserve its unfinished operand and remain
		// usable. The host has /dev/urandom and must exercise the success path.
		assert os.exists('/dev/processes')
		assert value == '1e-'
		if mut app is RemoteApp { app.key_input('3=') }
		integration_assert_calculator_display(mut app, '2.001')
		app.handle('calculator.memory.recall') or { panic(err) }
		integration_assert_calculator_display(mut app, '7')
		println('IPC Calculator Rand unavailable: recoverable entropy status and preserved arithmetic verified')
		return
	}
	operand := calculator_numeric_value(value)
	assert math.is_finite(operand) && operand >= 0 && operand < 1
	app.handle('calculator.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, value)
	rand_history := app.build(ui2.rect(0, 0, 620, 566)) or { panic(err) }
	assert tree_contains_text(rand_history, tr('calculator.scientific.random') + ' = ' + value)
	free_tree(rand_history)
	if mut app is RemoteApp { app.key_input('==') }
	result_tree := app.build(ui2.rect(0, 0, 620, 566)) or { panic(err) }
	result := integration_tree_text(result_tree, 'display') or { panic('missing Calculator result') }
	assert math.abs(calculator_numeric_value(result) - (2 + 2 * operand)) < 1e-13
	assert tree_contains_text(result_tree, '1 + 2 = 3')
	free_tree(result_tree)
	app.handle('calculator.memory.recall') or { panic(err) }
	integration_assert_calculator_display(mut app, '7')
	app.handle('calculator.mode.basic') or { panic(err) }
	app.handle('calculator.scientific.random') or { panic(err) }
	integration_assert_calculator_display(mut app, '7')
	println('IPC Calculator Rand interval, pending arithmetic, repeat, history, Copy and memory passed')
}

fn check_reminders_priority_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, '.vinix-reminders')
	export := system_information_join_path(home, 'priority.csv')
	defer { unsafe { path.free(); export.free() } }
	legacy := 'VINIX-REMINDERS 1\n0\t\tLegacy task\n'
	os.write_file(path, legacy) or { panic(err) }
	factory := app_factory_named('vinix-reminders') or { panic('Reminders is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 616), 'Legacy task')
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 616), tr('reminders.priority.none'))
	integration_assert_file(path, legacy)
	app.handle('reminders.row.0') or { panic(err) }
	app.handle('reminders.edit') or { panic(err) }
	app.handle('reminders.priority.low') or { panic(err) }
	app.handle('reminders.cancel') or { panic(err) }
	integration_assert_file(path, legacy)
	app.handle('reminders.edit') or { panic(err) }
	app.handle('reminders.priority.high') or { panic(err) }
	chosen := app.build(ui2.rect(0, 0, 800, 616)) or { panic(err) }
	control := integration_element_named(chosen, 'reminders.priority.high') or { panic('missing High priority') }
	assert control.kind == .button && control.box.bg == app_accent
	assert control.text == tr('reminders.priority.high')
	free_tree(chosen)
	app.handle('reminders.save') or { panic(err) }
	integration_assert_file(path, 'VINIX-REMINDERS 2\n0\t3\t\tLegacy task\n')
	for index, priority in ['reminders.priority.low', 'reminders.priority.medium', 'reminders.priority.none']! {
		app.handle('reminders.new') or { panic(err) }
		storage_remote_field(mut app, 'reminders.title', ['Low task', 'Medium task', 'Default task']![index])
		app.handle(priority) or { panic(err) }
		app.handle('reminders.save') or { panic(err) }
	}
	integration_assert_file(path, 'VINIX-REMINDERS 2\n0\t3\t\tLegacy task\n0\t1\t\tLow task\n0\t2\t\tMedium task\n0\t0\t\tDefault task\n')
	app.handle('reminders.row.0') or { panic(err) }
	app.handle('reminders.toggle') or { panic(err) }
	app.handle('reminders.filter.completed') or { panic(err) }
	storage_remote_field(mut app, 'reminders.export_path', export)
	app.handle('reminders.export_csv') or { panic(err) }
	close_remote(mut app)
	csv := os.read_file(export) or { panic(err) }
	defer { unsafe { csv.free() } }
	assert csv.contains(tr('reminders.csv_priority'))
	assert csv.contains('"Legacy task","",1,"' + tr('reminders.priority.high') + '"\n')
	mut reopened := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut reopened) }
	for priority in ['reminders.priority.low', 'reminders.priority.medium', 'reminders.priority.none']! {
		integration_assert_text(mut reopened, ui2.rect(0, 0, 800, 696), tr(priority))
	}
	reopened.handle('reminders.filter.completed') or { panic(err) }
	integration_assert_text(mut reopened, ui2.rect(0, 0, 800, 616), tr('reminders.priority.high'))
	println('IPC Reminders v1 preservation, v2 priority migration, four levels, completion, CSV and reopen passed')
}

// Send a real old-compositor header to the same new Capture process. The
// unadvertised cursor flag remains zero while normal replies advertise the new app.
fn integration_capture_legacy_request(mut app NativeApp, mut desktop Desktop, command AppCommand, payload string) AppReply {
	if mut app is RemoteApp {
		state := app_current_state(&desktop)
		assert !state.capture_request.hide_cursor
		mut header := []u8{cap: app_request_header_size}
		wire_put_u32(mut header, app_protocol_magic)
		wire_put_u8(mut header, app_protocol_version)
		wire_put_u8(mut header, u8(command))
		wire_put_u8(mut header, app_features & ~app_feature_capture_cursor)
		wire_put_u8(mut header, 0)
		wire_put_i32(mut header, 560)
		wire_put_i32(mut header, 396)
		wire_put_state(mut header, state)
		wire_put_u32(mut header, u32(payload.len))
		assert header.len == app_request_header_size
		assert desktop_write_all(app.request_fd, header.data, u64(header.len))
		unsafe { header.free() }
		if payload.len > 0 { assert desktop_write_all(app.request_fd, payload.str, u64(payload.len)) }
		reply := receive_app_response(app.response_fd) or { panic(err) }
		assert reply.ok && reply.features & app_feature_capture_cursor != 0
		assert !reply.state.capture_request.hide_cursor
		apply_app_state(mut desktop, reply.state)
		app.tree_stale = true
		return reply
	}
	panic('Capture must be a real remote app')
}

fn check_capture_cursor_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-capture') or { panic('Capture is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	initial := app.build(ui2.rect(0, 0, 560, 396)) or { panic(err) }
	assert integration_tree_enabled(initial, capture_action_cursor)
	assert tree_contains_text(initial, tr('capture.cursor.shown'))
	free_tree(initial)
	app.handle(capture_action_cursor) or { panic(err) }
	app.handle(capture_action_delay_5) or { panic(err) }
	app.handle(capture_action_take_screenshot) or { panic(err) }
	assert desktop.capture.request.hide_cursor && desktop.capture.request.delay == 5
	assert desktop.capture.report.phase == .screenshot_countdown
	sequence := desktop.capture.request.sequence
	active := app.build(ui2.rect(0, 0, 560, 396)) or { panic(err) }
	assert !integration_tree_enabled(active, capture_action_cursor)
	assert tree_contains_text(active, tr('capture.cursor.hidden'))
	free_tree(active)
	app.handle(capture_action_cursor) or { panic(err) }
	assert desktop.capture.request.sequence == sequence && desktop.capture.request.hide_cursor
	app.handle(capture_action_stop) or { panic(err) }
	assert desktop.capture.report.phase == .cancelled
	app.handle(capture_action_video_tab) or { panic(err) }
	app.handle(capture_action_start_video) or { panic(err) }
	assert desktop.capture.report.phase == .video_countdown && desktop.capture.request.hide_cursor
	countdown_report := desktop.capture.report
	// Transport a recording report without opening a writer in this headless compositor.
	desktop.capture.report.phase = .recording
	recording := app.build(ui2.rect(0, 0, 560, 396)) or { panic(err) }
	assert !integration_tree_enabled(recording, capture_action_cursor)
	free_tree(recording)
	app.handle(capture_action_cursor) or { panic(err) }
	assert desktop.capture.request.hide_cursor
	desktop.capture.report = countdown_report
	app.handle(capture_action_stop) or { panic(err) }
	app.handle(capture_action_cursor) or { panic(err) }
	app.handle(capture_action_screenshot_tab) or { panic(err) }
	app.handle(capture_action_take_screenshot) or { panic(err) }
	assert !desktop.capture.request.hide_cursor
	app.handle(capture_action_stop) or { panic(err) }
	legacy_build := integration_capture_legacy_request(mut app, mut desktop, .build, '')
	mut reader := WireReader{data: legacy_build.payload}
	legacy_tree := decode_app_element(mut reader, 0) or { panic(err) }
	assert !tree_has_id(legacy_tree, capture_action_cursor)
	free_tree(legacy_tree)
	unsafe { legacy_build.payload.free() }
	for action in [capture_action_cursor, capture_action_take_screenshot, capture_action_stop]! {
		reply := integration_capture_legacy_request(mut app, mut desktop, .handle, action)
		if reply.payload.cap > 0 { unsafe { reply.payload.free() } }
	}
	assert !desktop.capture.request.hide_cursor && desktop.capture.report.phase == .cancelled
	println('IPC Capture cursor flag request/reply, frozen active choice and old-compositor fallback passed')
}

fn integration_wait_terminal_prompt(mut app NativeApp) {
	// The installed interactive shell loads its startup files before reading
	// keys. Its initial termios setup can flush input queued immediately after
	// fork, so wait for a settled prompt before entering the output command.
	mut ready := false
	mut prompt := ''
	mut prompt_y := 0
	mut prompt_stable := 0
	for _ in 0 .. 300 {
		if mut app is RemoteApp { app.poll() }
		tree := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
		mut matched := false
		for child in tree.children {
			if child.kind != .label || int(child.frame.y) < terminal_toolbar_height + terminal_padding
				|| int(child.frame.y) >= 316 - terminal_selection_status_height
				|| child.text.len <= 1 || !child.text.ends_with('_') { continue }
			next_y := int(child.frame.y)
			prompt_stable = if next_y == prompt_y && child.text == prompt { prompt_stable + 1 } else { 1 }
			if prompt.len > 0 { unsafe { prompt.free() } }
			prompt = child.text.clone()
			prompt_y = next_y
			matched = true
			ready = prompt_stable >= 3
			break
		}
		free_tree(tree)
		if !matched { prompt_stable = 0 }
		if ready { break }
		desktop_sleep_ms(100)
	}
	if prompt.len > 0 { unsafe { prompt.free() } }
	if !ready {
		tree := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
		eprintln('IPC Terminal shell prompt did not settle; rendered text follows:')
		for child in tree.children { if child.text.len > 0 { eprintln(child.text) } }
		free_tree(tree)
	}
	assert ready
}

fn check_terminal_word_line_client(mut desktop Desktop) {
	assert os.exists(terminal_shell), 'Terminal selection needs the installed shell'
	factory := app_factory_named('vinix-terminal') or { panic('Terminal is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	free_tree(app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) })
	word := 'café_42'
	if mut app is RemoteApp {
		assert app.clipboard_copy && app.pointer && app.keyboard
	}
	integration_wait_terminal_prompt(mut app)
	if mut app is RemoteApp {
		// ASCII octal escapes produce the same independent Unicode output even
		// when the shell line editor starts in the C locale. Ctrl-U clears any
		// draft command; carriage return is the ordinary Enter key.
		app.key_input("\x15printf 'ipcword_42 caf\\303\\251_42 tail\\n'\r")
	}
	mut found := false
	mut x := 0
	mut y := 0
	mut line := ''
	mut stable := 0
	for _ in 0 .. 300 {
		if mut app is RemoteApp { app.poll() }
		tree := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
		mut matched := false
		for child in tree.children {
			if child.text != 'ipcword_42 café_42 tail' { continue }
			at := child.text.index(word) or { continue }
			x = terminal_padding + integration_terminal_cells(child.text, at) * terminal_column_width + 3
			next_y := int(child.frame.y) + 4
			next_line := child.text + '\n'
			stable = if next_y == y && next_line == line { stable + 1 } else { 1 }
			if line.len > 0 { unsafe { line.free() } }
			line = next_line
			y = next_y
			assert y + terminal_row_height < 316 - terminal_selection_status_height
			matched = true
			found = stable >= 3
			break
		}
		free_tree(tree)
		if !matched { stable = 0 }
		if found { break }
		// Initial PTY echo can precede the shell editor's prompt/redraw. Output
		// clears selection, so wait for complete, settled text before clicking.
		desktop_sleep_ms(100)
	}
	defer { if line.len > 0 { unsafe { line.free() } } }
	if !found {
		tree := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
		eprintln('IPC Terminal Unicode output row did not settle; rendered text follows:')
		for child in tree.children { if child.text.len > 0 { eprintln(child.text) } }
		free_tree(tree)
	}
	assert found
	if mut app is RemoteApp {
		for _ in 0 .. 2 {
			app.pointer_event(.down, .left, 0, x, y, 560, 316)
			app.pointer_event(.up, .left, 0, x, y, 560, 316)
		}
	}
	app.handle(terminal_action_copy) or { panic(err) }
	integration_assert_clipboard(&desktop, word)
	if mut app is RemoteApp {
		// A different button resets the click sequence before three new clicks.
		app.pointer_event(.down, .right, 0, x, y, 560, 316)
		for _ in 0 .. 3 {
			app.pointer_event(.down, .left, 0, x, y, 560, 316)
			app.pointer_event(.up, .left, 0, x, y, 560, 316)
		}
	}
	app.handle(terminal_action_copy) or { panic(err) }
	integration_assert_clipboard(&desktop, line)
	assert desktop.clipboard.set_local_text('Cmd-C must replace this text')
	if mut app is RemoteApp { app.key_input(terminal_key_cmd_copy) }
	integration_assert_clipboard(&desktop, line)
	println('IPC Terminal double-click Unicode word, triple-click physical line and Cmd-C clipboard passed')
}

fn integration_element_named(element ui2.Element, id string) ?ui2.Element {
	if element.id == id || element.action_id == id { return element }
	for child in element.children {
		found := integration_element_named(child, id) or { continue }
		return found
	}
	return none
}

fn integration_assert_calculator_display(mut app NativeApp, expected string) {
	tree := app.build(ui2.rect(0, 0, 620, 566)) or { panic(err) }
	display := integration_element_named(tree, 'display') or { panic('missing Calculator display') }
	assert display.text == expected
	free_tree(tree)
}

fn integration_resize_source() []u8 {
	// Independent PNG: opaque red/half-alpha green, transparent blue/white.
	// Its bilinear center is premultiplied RGBA (204,153,102,160), not the
	// straight RGB average that would retain invisible blue in the result.
	return base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP4z8DwHwgbGMA0EAAAP9cIeY8TiooAAAAASUVORK5CYII=')
}

fn integration_assert_resize_pixel(path string) {
	bytes := os.read_bytes(path) or { panic(err) }
	defer { unsafe { bytes.free() } }
	mut dimensions := [3]int{}
	pixels := unsafe { C.stbi_load_from_memory(bytes.data, bytes.len, &dimensions[0], &dimensions[1], &dimensions[2], 4) }
	assert pixels != unsafe { nil }
	defer { C.stbi_image_free(pixels) }
	assert dimensions[0] == 1 && dimensions[1] == 1
	assert unsafe { pixels[0] == 204 && pixels[1] == 153 && pixels[2] == 102 && pixels[3] == 160 }
}

fn check_preview_resize_client(home string, mut desktop Desktop) {
	image := integration_resize_source()
	defer { unsafe { image.free() } }
	source := system_information_join_path(home, 'resize-source.png')
	output := system_information_join_path(home, 'resize-1x1.png')
	undo := system_information_join_path(home, 'resize-undo.png')
	redo := system_information_join_path(home, 'resize-redo.png')
	defer { unsafe { source.free(); output.free(); undo.free(); redo.free() } }
	os.write_file(source, unsafe { tos(&u8(image.data), image.len) }) or { panic(err) }
	factory := app_factory_named('vinix-preview') or { panic('Preview is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	storage_remote_field(mut app, preview_action_open_path, source)
	app.handle(preview_action_open) or { panic(err) }
	storage_remote_field(mut app, preview_action_resize_width, '1')
	app.handle(preview_action_resize) or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 566), tr('preview.status.resized'))
	storage_remote_field(mut app, preview_action_export_path, output)
	app.handle(preview_action_export_png) or { panic(err) }
	integration_assert_resize_pixel(output)
	// A no-op and failed resize must retain the sole Undo state.
	app.handle(preview_action_resize) or { panic(err) }
	storage_remote_field(mut app, preview_action_resize_width, '8192')
	app.handle(preview_action_resize) or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 566), tr('preview.status.resize_invalid'))
	state := app.build(ui2.rect(0, 0, 800, 566)) or { panic(err) }
	assert integration_tree_enabled(state, preview_action_undo_crop)
	free_tree(state)
	app.handle(preview_action_undo_crop) or { panic(err) }
	storage_remote_field(mut app, preview_action_export_path, undo)
	app.handle(preview_action_export_png) or { panic(err) }
	integration_assert_same_image_pixels(undo, source, 2, 2)
	app.handle(preview_action_redo_crop) or { panic(err) }
	storage_remote_field(mut app, preview_action_export_path, redo)
	app.handle(preview_action_export_png) or { panic(err) }
	integration_assert_resize_pixel(redo)
	app.handle(preview_action_export_png) or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 566), tr('preview.status.exists'))
	integration_assert_resize_pixel(redo)
	println('IPC Preview alpha-weighted resize, protected export and exact Undo/Redo passed')
}

fn check_calculator_precision_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-calculator') or { panic('Calculator is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('calculator.mode.scientific') or { panic(err) }
	if mut app is RemoteApp { app.key_input('2.5E-3*4=') }
	integration_assert_calculator_display(mut app, '0.01')
	app.handle('C') or { panic(err) }
	if mut app is RemoteApp { app.key_input('8') }
	app.handle('calculator.scientific.root') or { panic(err) }
	if mut app is RemoteApp { app.key_input('3=') }
	integration_assert_calculator_display(mut app, '2')
	app.handle('C') or { panic(err) }
	if mut app is RemoteApp { app.paste_input('-8') }
	app.handle('calculator.scientific.root') or { panic(err) }
	if mut app is RemoteApp { app.key_input('3=') }
	integration_assert_calculator_display(mut app, '-2')
	app.handle('C') or { panic(err) }
	if mut app is RemoteApp { app.key_input('8') }
	app.handle('calculator.scientific.root') or { panic(err) }
	if mut app is RemoteApp { app.key_input('0=') }
	integration_assert_calculator_display(mut app, tr('calculator.error'))
	integration_assert_text(mut app, ui2.rect(0, 0, 620, 566), tr('calculator.error.domain'))
	app.handle('C') or { panic(err) }
	if mut app is RemoteApp { app.key_input('1E=') }
	integration_assert_calculator_display(mut app, tr('calculator.error'))
	integration_assert_text(mut app, ui2.rect(0, 0, 620, 566), tr('calculator.error.exponent'))
	println('IPC Calculator EE arithmetic, odd negative root and domain guards passed')
}

fn integration_assert_frame_inside(element ui2.Element, width f64, height f64) {
	assert element.frame.x >= 0 && element.frame.y >= 0
	assert element.frame.width >= 0 && element.frame.height >= 0
	assert element.frame.x + element.frame.width <= width
	assert element.frame.y + element.frame.height <= height
	for child in element.children {
		integration_assert_frame_inside(child, element.frame.width, element.frame.height)
	}
}

fn check_grapher_compact_client(home string, mut desktop Desktop) {
	factory := app_factory_named('vinix-grapher') or { panic('Grapher is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	compact := app.build(ui2.rect(0, 0, 320, 340)) or { panic(err) }
	for child in compact.children { integration_assert_frame_inside(child, 320, 340) }
	assert integration_element_named(compact, 'grapher.page.graph') != none
	free_tree(compact)
	path := system_information_join_path(home, 'compact-graph.png')
	defer { unsafe { path.free() } }
	storage_remote_field(mut app, 'grapher.png_path', path)
	image_page := app.build(ui2.rect(0, 0, 320, 340)) or { panic(err) }
	assert integration_element_named(image_page, 'grapher.png_path') != none
	assert integration_element_named(image_page, 'grapher.export_png') != none
	assert integration_element_named(image_page, 'grapher.expression') == none
	for child in image_page.children { integration_assert_frame_inside(child, 320, 340) }
	free_tree(image_page)
	app.handle('grapher.export_png') or { panic(err) }
	assert os.exists(path)
	integration_assert_text(mut app, ui2.rect(0, 0, 320, 340), tr('grapher.png_saved'))
	if mut app is RemoteApp { app.key_input('\x0c') }
	graph_page := app.build(ui2.rect(0, 0, 320, 340)) or { panic(err) }
	assert integration_element_named(graph_page, 'grapher.expression') != none
	assert integration_element_named(graph_page, 'grapher.png_path') == none
	free_tree(graph_page)
	tiny := app.build(ui2.rect(0, 0, 180, 96)) or { panic(err) }
	for child in tiny.children { integration_assert_frame_inside(child, 180, 96) }
	assert integration_element_named(tiny, 'grapher.plot') != none
	free_tree(tiny)
	println('IPC Grapher compact pages, visible focus, PNG export and tiny geometry passed')
}

fn check_clock_duration_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-clock') or { panic('Clock is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('clock.tab.timer') or { panic(err) }
	app.handle('clock.timer.duration') or { panic(err) }
	storage_remote_field(mut app, 'clock.timer.duration.field', '24:00:01')
	app.handle('clock.timer.duration.apply') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 400, 370), tr('clock.timer.duration.invalid'))
	integration_assert_text(mut app, ui2.rect(0, 0, 400, 370), '00:05:00')
	storage_remote_field(mut app, 'clock.timer.duration.field', '00:00:07')
	if mut app is RemoteApp { app.key_input('\r') }
	integration_assert_text(mut app, ui2.rect(0, 0, 400, 370), '00:00:07')
	app.handle('clock.timer.duration') or { panic(err) }
	storage_remote_field(mut app, 'clock.timer.duration.field', '00:00:02\n')
	integration_assert_text(mut app, ui2.rect(0, 0, 400, 370), '00:00:07')
	if mut app is RemoteApp { app.key_input('\x1b') }
	app.handle('clock.timer.add') or { panic(err) }
	app.handle('clock.timer.preset.1') or { panic(err) }
	app.handle('clock.timer.toggle') or { panic(err) }
	app.handle('clock.timer.select.0') or { panic(err) }
	app.handle('clock.timer.duration') or { panic(err) }
	storage_remote_field(mut app, 'clock.timer.duration.field', '00:00:01')
	draft := app.build(ui2.rect(0, 0, 400, 370)) or { panic(err) }
	assert !integration_tree_enabled(draft, 'clock.timer.toggle')
	assert integration_tree_enabled(draft, 'clock.timer.duration.apply')
	free_tree(draft)
	app.handle('clock.timer.duration.apply') or { panic(err) }
	app.handle('clock.timer.toggle') or { panic(err) }
	running := app.build(ui2.rect(0, 0, 400, 370)) or { panic(err) }
	assert !integration_tree_enabled(running, 'clock.timer.duration')
	free_tree(running)
	app.handle('clock.timer.duration') or { panic(err) }
	app.handle('clock.timer.select.1') or { panic(err) }
	desktop_sleep_ms(1100)
	if mut app is RemoteApp { app.last_poll_ms = 0; app.poll() }
	integration_assert_text(mut app, ui2.rect(0, 0, 400, 370), tr('clock.timer.finished'))
	app.handle('clock.timer.select.1') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 400, 370), tr('clock.stop'))
	println('IPC Clock exact duration validation, cancellation and independent expiry passed')
}

fn check_grapher_png_client(home string, mut desktop Desktop) {
	factory := app_factory_named('vinix-grapher') or { panic('Grapher is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	path := system_information_join_path(home, 'graph-Ж.png')
	fresh := system_information_join_path(home, 'invalid-graph.png')
	defer { unsafe { path.free(); fresh.free() } }
	storage_remote_field(mut app, 'grapher.expression', 'sqrt(x)')
	for index, action in ['grapher.xmin', 'grapher.xmax', 'grapher.ymin', 'grapher.ymax']! {
		values := ['-1', '1', '-2', '2']!
		storage_remote_field(mut app, action, values[index])
	}
	storage_remote_field(mut app, 'grapher.png_path', path)
	app.handle('grapher.export_png') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 840, 636), tr('grapher.png_saved'))
	bytes := os.read_bytes(path) or { panic(err) }
	defer { unsafe { bytes.free() } }
	mut dimensions := [3]int{}
	pixels := unsafe { C.stbi_load_from_memory(bytes.data, bytes.len, &dimensions[0], &dimensions[1], &dimensions[2], 4) }
	assert pixels != unsafe { nil }
	defer { C.stbi_image_free(pixels) }
	assert dimensions[0] == 960 && dimensions[1] == 640
	mut curve_pixels := 0
	for y in 110 .. 550 {
		for x in 110 .. 932 {
			at := (y * 960 + x) * 4
			color := unsafe { u32(pixels[at]) << 16 | u32(pixels[at + 1]) << 8 | u32(pixels[at + 2]) }
			assert unsafe { pixels[at + 3] } == 255
			if x < 510 { assert color != 0x1671d9 }
			if color == 0x1671d9 { curve_pixels++ }
		}
	}
	assert curve_pixels > 100
	if mut app is RemoteApp { app.key_input('\r') }
	integration_assert_text(mut app, ui2.rect(0, 0, 840, 636), tr('grapher.png_exists'))
	preserved := os.read_bytes(path) or { panic(err) }
	assert preserved == bytes
	unsafe { preserved.free() }
	storage_remote_field(mut app, 'grapher.expression', 'sin(')
	storage_remote_field(mut app, 'grapher.png_path', fresh)
	app.handle('grapher.export_png') or { panic(err) }
	assert !os.exists(fresh)
	integration_assert_text(mut app, ui2.rect(0, 0, 840, 636), tr('grapher.expression_invalid'))
	println('IPC Grapher PNG pixels, gaps and destination protection passed')
}

fn check_notes_history_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-notes') or { panic('Notes is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('notes.new') or { panic(err) }
	storage_remote_field(mut app, 'notes.title', 'History 日本語')
	storage_remote_field(mut app, 'notes.body', 'First complete paste 日本語')
	app.handle('notes.save') or { panic(err) }
	storage_remote_field(mut app, 'notes.body', 'Second complete paste Ж')
	if mut app is RemoteApp { app.key_input('\x1a') }
	integration_assert_text(mut app, ui2.rect(0, 0, 820, 576), 'First complete paste 日本語')
	ready := app.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert integration_tree_enabled(ready, 'notes.redo')
	free_tree(ready)
	app.handle('notes.save') or { panic(err) }
	if mut app is RemoteApp { app.key_input('\x19') }
	integration_assert_text(mut app, ui2.rect(0, 0, 820, 576), 'Second complete paste Ж')
	app.handle('notes.undo') or { panic(err) }
	if mut app is RemoteApp { app.paste_input('different complete paste') }
	changed := app.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert !integration_tree_enabled(changed, 'notes.redo')
	free_tree(changed)
	app.handle('notes.undo') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 820, 576), 'First complete paste 日本語')
	app.handle('notes.new') or { panic(err) }
	new_note := app.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert !integration_tree_enabled(new_note, 'notes.undo')
	assert !integration_tree_enabled(new_note, 'notes.redo')
	free_tree(new_note)
	println('IPC Notes atomic Undo/Redo, saved history and note scope passed')
}

fn check_clock_named_timer_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-clock') or { panic('Clock is not registered') }
	assert factory.keyboard && factory.polling
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('clock.tab.timer') or { panic(err) }
	storage_remote_field(mut app, 'clock.timer.name', 'Tea 日本語')
	app.handle('clock.timer.preset.1') or { panic(err) }
	app.handle('clock.timer.toggle') or { panic(err) }
	app.handle('clock.timer.add') or { panic(err) }
	storage_remote_field(mut app, 'clock.timer.name', 'Work Ж')
	app.handle('clock.timer.toggle') or { panic(err) }
	app.handle('clock.timer.select.0') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 376), 'Tea 日本語')
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 376), tr('clock.stop'))
	app.handle('clock.timer.toggle') or { panic(err) }
	app.handle('clock.timer.less') or { panic(err) }
	app.handle('clock.timer.toggle') or { panic(err) }
	app.handle('clock.timer.select.1') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 376), 'Work Ж')
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 376), tr('clock.stop'))
	desktop_sleep_ms(1100)
	if mut app is RemoteApp { app.last_poll_ms = 0; app.poll() }
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 376), tr('clock.timer.finished'))
	app.handle('clock.timer.select.1') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 376), tr('clock.stop'))
	app.handle('clock.timer.toggle') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 376), tr('clock.start'))
	app.handle('clock.timer.add') or { panic(err) }
	app.handle('clock.timer.add') or { panic(err) }
	full := app.build(ui2.rect(0, 0, 560, 376)) or { panic(err) }
	assert !integration_tree_enabled(full, 'clock.timer.add')
	free_tree(full)
	app.handle('clock.timer.remove') or { panic(err) }
	removed := app.build(ui2.rect(0, 0, 560, 376)) or { panic(err) }
	assert integration_tree_enabled(removed, 'clock.timer.add')
	free_tree(removed)
	println('IPC Clock independent named timers, expiry and bounds passed')
}

fn check_preview_crop_client(home string, mut desktop Desktop) {
	check_preview_crop_recovery_client(home, mut desktop, false)
}

fn integration_assert_same_image_pixels(path string, expected_path string, width int, height int) {
	bytes := os.read_bytes(path) or { panic(err) }
	expected_bytes := os.read_bytes(expected_path) or { panic(err) }
	defer { unsafe { bytes.free(); expected_bytes.free() } }
	mut actual_dimensions := [3]int{}
	mut expected_dimensions := [3]int{}
	pixels := unsafe { C.stbi_load_from_memory(bytes.data, bytes.len, &actual_dimensions[0], &actual_dimensions[1], &actual_dimensions[2], 4) }
	expected := unsafe { C.stbi_load_from_memory(expected_bytes.data, expected_bytes.len, &expected_dimensions[0], &expected_dimensions[1], &expected_dimensions[2], 4) }
	assert pixels != unsafe { nil } && expected != unsafe { nil }
	defer { C.stbi_image_free(pixels); C.stbi_image_free(expected) }
	assert actual_dimensions[0] == width && actual_dimensions[1] == height
	assert expected_dimensions[0] == width && expected_dimensions[1] == height
	for index in 0 .. width * height * 4 { assert unsafe { pixels[index] } == unsafe { expected[index] } }
}

fn check_preview_crop_recovery_client(home string, mut desktop Desktop, recovery bool) {
	// An independent 4x3 RGBA PNG has different colors in every row and column.
	image := base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAYAAAC09K7GAAAAN0lEQVR4nA3IsQ0AIAgAQRtDoqDjMAWDMA8lw75eeWPKwmWTorQYY8bGQ8kwOs6PUryMrEPX5QG/NBPnu9fREQAAAABJRU5ErkJggg==')
	path := system_information_join_path(home, 'crop-日本語.png')
	export_path := system_information_join_path(home, 'cropped-Ж.png')
	original_path := system_information_join_path(home, 'crop-original.png')
	undo_path := system_information_join_path(home, 'crop-undone.png')
	redo_path := system_information_join_path(home, 'crop-redone.png')
	open_action := jump_open_prefix + path
	defer { unsafe {
		image.free(); path.free(); export_path.free(); original_path.free(); undo_path.free(); redo_path.free(); open_action.free()
	} }
	os.write_file_array(path, image) or { panic(err) }
	factory := app_factory_named('vinix-preview') or { panic('Preview is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle(open_action) or { panic(err) }
	free_tree(app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) })
	app.handle(preview_action_actual) or { panic(err) }
	app.handle(preview_action_select) or { panic(err) }
	layout := app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) }
	viewport := integration_element_named(layout, preview_action_image) or { panic('missing Preview viewport') }
	// The independent 4x3 image is centered at 100%. Resolve its origin from
	// the real viewport so toolbar rows do not invalidate pointer coverage.
	image_x := int(viewport.frame.x) + (int(viewport.frame.width) - 4) / 2
	image_y := int(viewport.frame.y) + (int(viewport.frame.height) - 3) / 2
	free_tree(layout)
	// Drag displayed pixels (1,1) through (2,2); exported pixels remain golden.
	if mut app is RemoteApp {
		assert app.pointer_input_enabled()
		app.pointer_event(.down, .left, 0, image_x + 1, image_y + 1, 800, 576)
		app.pointer_event(.move, .no_button, 0, image_x + 2, image_y + 2, 800, 576)
		app.pointer_event(.up, .left, 0, image_x + 2, image_y + 2, 800, 576)
	}
	selection := app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) }
	assert integration_tree_enabled(selection, preview_action_crop)
	free_tree(selection)
	app.handle(preview_action_crop) or { panic(err) }
	cropped := app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) }
	assert tree_contains_text(cropped, '2 × 2 px')
	assert tree_contains_text(cropped, 'Image cropped.')
	assert !integration_tree_enabled(cropped, preview_action_crop)
	free_tree(cropped)
	storage_remote_field(mut app, preview_action_export_path, export_path)
	app.handle(preview_action_export_png) or { panic(err) }
	integration_assert_image_size(export_path, 2, 2)
	bytes := os.read_bytes(export_path) or { panic(err) }
	defer { unsafe { bytes.free() } }
	mut dimensions := [3]int{}
	pixels := unsafe { C.stbi_load_from_memory(bytes.data, bytes.len, &dimensions[0], &dimensions[1], &dimensions[2], 4) }
	assert pixels != unsafe { nil }
	defer { C.stbi_image_free(pixels) }
	assert dimensions[0] == 2 && dimensions[1] == 2
	expected := [u8(55), 77, 12, 255, 105, 77, 13, 255, 55, 147, 13, 255, 105, 147, 14, 255]!
	for index, byte in expected { assert unsafe { pixels[index] } == byte }
	if recovery {
		ready := app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) }
		assert integration_tree_enabled(ready, preview_action_undo_crop)
		free_tree(ready)
		if mut app is RemoteApp { app.key_input('\x1a') }
		undone := app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) }
		assert tree_contains_text(undone, '4 × 3 px')
		assert tree_contains_text(undone, 'Crop undone. Redo restores it.')
		assert integration_tree_enabled(undone, preview_action_redo_crop)
		assert !integration_tree_enabled(undone, preview_action_undo_crop)
		free_tree(undone)
		storage_remote_field(mut app, preview_action_export_path, undo_path)
		app.handle(preview_action_export_png) or { panic(err) }
		integration_assert_same_image_pixels(undo_path, path, 4, 3)
		if mut app is RemoteApp { app.key_input('\x19') }
		redone := app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) }
		assert tree_contains_text(redone, '2 × 2 px')
		assert tree_contains_text(redone, 'Crop restored. Export PNG to save.')
		assert integration_tree_enabled(redone, preview_action_undo_crop)
		assert !integration_tree_enabled(redone, preview_action_redo_crop)
		free_tree(redone)
		storage_remote_field(mut app, preview_action_export_path, redo_path)
		app.handle(preview_action_export_png) or { panic(err) }
		integration_assert_same_image_pixels(redo_path, export_path, 2, 2)
	}
	storage_remote_field(mut app, preview_action_export_path, original_path)
	app.handle(preview_action_export_copy) or { panic(err) }
	original := os.read_bytes(original_path) or { panic(err) }
	defer { unsafe { original.free() } }
	assert original == image
	println(if recovery { 'IPC Preview crop, Undo/Redo, exact original/cropped PNG pixels and source bytes passed' }
		else { 'IPC Preview pointer selection, exact 2x2 crop, PNG and original bytes passed' })
}

fn integration_tree_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id || element.action_id == id { return element }
	for child in element.children {
		if found := integration_tree_element(child, id) { return found }
	}
	return none
}

fn check_hyperbolic_calculator_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-calculator') or { panic('Calculator is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('calculator.mode.scientific') or { panic(err) }
	actions := ['calculator.scientific.sinh', 'calculator.scientific.cosh',
		'calculator.scientific.tanh', 'calculator.scientific.asinh',
		'calculator.scientific.acosh', 'calculator.scientific.atanh']!
	inputs := ['1', '-1', '1', '-1', '2', '-.5']!
	expected := [1.1752011936438014, 1.5430806348152437, .7615941559557649,
		-.881373587019543, 1.3169578969248166, -.5493061443340548]!
	mut degrees := [6]f64{}
	for angular_mode, angle in ['calculator.angle.degrees', 'calculator.angle.radians']! {
		app.handle(angle) or { panic(err) }
		for index, action in actions {
			app.handle('C') or { panic(err) }
			if mut app is RemoteApp { app.paste_input(inputs[index]) }
			controls := app.build(ui2.rect(0, 0, 540, 430)) or { panic(err) }
			control := integration_tree_element(controls, action) or { panic('missing serialized hyperbolic control') }
			assert control.kind == .button && control.text == tr(action)
			assert control.frame.width >= 28 && control.frame.height >= 28
			integration_assert_frame_inside(control, 540, 430)
			app.handle(if control.action_id.len > 0 { control.action_id } else { control.id }) or { panic(err) }
			free_tree(controls)
			result := app.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
			text := integration_tree_text(result, 'display') or { panic('missing hyperbolic result') }
			assert math.abs(text.f64() - expected[index]) < 1e-14
			assert !tree_contains_text(result, '[DEG]') && !tree_contains_text(result, '[RAD]')
			if angular_mode == 0 { degrees[index] = text.f64() }
			else { assert text.f64() == degrees[index] }
			free_tree(result)
		}
	}
	for index, action in ['calculator.scientific.acosh', 'calculator.scientific.atanh',
		'calculator.scientific.atanh', 'calculator.scientific.sinh']! {
		app.handle('C') or { panic(err) }
		if mut app is RemoteApp { app.paste_input(['0', '1', '-1', '711']![index]) }
		app.handle(action) or { panic(err) }
		integration_calculator_display(mut app, tr('calculator.error'))
		integration_assert_text(mut app, ui2.rect(0, 0, 620, 576), tr(if index < 3 {
			'calculator.error.domain'
		} else { 'calculator.error.nonfinite' }))
		if mut app is RemoteApp { app.key_input('7') }
		integration_calculator_display(mut app, '7')
	}
	for action in ['calculator.scientific.sinh', 'calculator.scientific.cosh']! {
		app.handle('C') or { panic(err) }
		if mut app is RemoteApp { app.paste_input('710') }
		app.handle(action) or { panic(err) }
		result := app.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
		text := integration_tree_text(result, 'display') or { panic('missing large hyperbolic result') }
		assert math.is_finite(text.f64()) && math.abs(text.f64() / 1.1169973830808557e308 - 1) < 1e-14
		free_tree(result)
	}
	app.handle('C') or { panic(err) }
	if mut app is RemoteApp { app.key_input('2+0') }
	app.handle('calculator.scientific.cosh') or { panic(err) }
	if mut app is RemoteApp { app.key_input('==') }
	integration_calculator_display(mut app, '4')
	app.handle('calculator.mode.programmer') or { panic(err) }
	if mut app is RemoteApp { app.paste_input('0xFF'); app.key_input('+1=') }
	app.handle('calculator.mode.scientific') or { panic(err) }
	integration_calculator_display(mut app, '4')
	app.handle('C') or { panic(err) }
	app.handle('calculator.scientific.cosh') or { panic(err) }
	app.handle('calculator.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, '1')
	println('IPC Calculator six hyperbolic controls, angular independence, domains, finite boundary and state passed')
}

fn check_calendar_search_client(home string, mut desktop Desktop) {
	store := system_information_join_path(home, calendar_events_filename)
	defer { unsafe { store.free() } }
	// Store order deliberately differs from chronological results, including
	// all-day/timed events and equal-time records that must retain their order.
	record := 'VINIX-CALENDAR 1\n2031\t3\t4\t600\tIPC 日本語 meeting late\tCafé Ж north\n2030\t2\t3\t600\tIPC 日本語 meeting timed\tCafé Ж north\n2030\t2\t3\t-1\tIPC 日本語 meeting all-day\tCafé Ж north\n2029\t12\t31\t540\tIPC 日本語 meeting early\tCafé Ж north\n2030\t2\t3\t600\tIPC 日本語 meeting tied\tCafé Ж north\n2030\t2\t2\t-1\tUnmatched event\tElsewhere\n'
	os.write_file(store, record) or { panic(err) }
	factory := app_factory_named('vinix-calendar') or { panic('Calendar is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	query := '日本語 cafe ж'
	if mut app is RemoteApp { assert app.keyboard && app.polling; app.key_input('\x06'); app.paste_input(query) }
	results := app.build(ui2.rect(0, 0, 740, 520)) or { panic(err) }
	assert (integration_tree_text(results, 'calendar.search') or { panic('missing Calendar search') }) == query
	assert tree_contains_text(results, '5 matching events')
	for row, action in ['calendar.event.row.3', 'calendar.event.row.2',
		'calendar.event.row.1', 'calendar.event.row.4', 'calendar.event.row.0']! {
		control := integration_tree_element(results, action) or { panic('missing chronological result') }
		assert control.frame.y == f64(142 + row * 60)
	}
	assert !tree_has_id(results, 'calendar.event.row.5')
	assert tree_contains_text(results, '2029-12-31') && tree_contains_text(results, '2031-03-04')
	free_tree(results)
	app.handle('calendar.event.row.0') or { panic(err) }
	editor := app.build(ui2.rect(0, 0, 740, 520)) or { panic(err) }
	date := date_long_text(2031, 3, 4, calendar_weekday(2031, 3, 4))
	assert tree_contains_text(editor, date)
	unsafe { date.free() }
	assert tree_contains_text(editor, 'IPC 日本語 meeting late') && tree_contains_text(editor, '10:00')
	assert tree_contains_text(editor, 'Café Ж north') && tree_has_id(editor, 'calendar.event.save')
	free_tree(editor)
	storage_remote_field(mut app, 'calendar.event.title', 'IPC 日本語 meeting late edited')
	app.handle('calendar.event.save') or { panic(err) }
	persisted := os.read_file(store) or { panic(err) }
	defer { unsafe { persisted.free() } }
	mut model := calendar_parse_events(persisted) or { panic('damaged saved Calendar record') }
	assert model.count == 6 && model.items[0].year == 2031 && model.items[0].month == 3 && model.items[0].day == 4
	assert model.items[0].minutes == 600 && model.items[0].title == 'IPC 日本語 meeting late edited'
	model.free_items()
	saved := app.build(ui2.rect(0, 0, 740, 520)) or { panic(err) }
	assert (integration_tree_text(saved, 'calendar.search') or { panic('lost Calendar search after save') }) == query
	assert tree_contains_text(saved, 'IPC 日本語 meeting late edited')
	free_tree(saved)
	// One visible result makes actual paging observable over fragmented requests.
	free_tree(app.build(ui2.rect(0, 0, 400, 210)) or { panic(err) })
	if mut app is RemoteApp { app.key_input('\x1b'); app.key_input('['); app.key_input('6~') }
	next := app.build(ui2.rect(0, 0, 400, 210)) or { panic(err) }
	assert (integration_tree_text(next, 'calendar.search') or { panic('missing paged query') }) == query
	assert tree_has_id(next, 'calendar.event.row.2') && !tree_has_id(next, 'calendar.event.row.3')
	free_tree(next)
	if mut app is RemoteApp { app.key_input('\x1bO'); app.key_input('B') }
	ss3 := app.build(ui2.rect(0, 0, 400, 210)) or { panic(err) }
	assert (integration_tree_text(ss3, 'calendar.search') or { panic('missing SS3 query') }) == query
	assert tree_has_id(ss3, 'calendar.event.row.1') && !tree_has_id(ss3, 'calendar.event.row.2')
	free_tree(ss3)
	if mut app is RemoteApp { app.key_input('\x1b') }
	mut escaped := false
	for _ in 0 .. 100 {
		if mut app is RemoteApp { app.poll() }
		tree := app.build(ui2.rect(0, 0, 740, 520)) or { panic(err) }
		escaped = !tree_has_id(tree, 'calendar.search.back') && tree_has_id(tree, calendar_action_today)
		free_tree(tree)
		if escaped { break }
		desktop_sleep_ms(20)
	}
	assert escaped
	if mut app is RemoteApp { app.key_input('\x06'); app.paste_input('no-match-Ж😀-987654') }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), tr('calendar.search.empty'))
	app.handle('calendar.search.clear') or { panic(err) }
	month := app.build(ui2.rect(0, 0, 740, 520)) or { panic(err) }
	assert !tree_has_id(month, 'calendar.search.back') && tree_has_id(month, calendar_action_today)
	free_tree(month)
	println('IPC Calendar Unicode token search, chronological dates, saved editor navigation, fragmented paging and Escape passed')
}

fn integration_csv_counter(record string, kind string) ?u64 {
	mut start := 0
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		line := calendar_borrow(record, start, end)
		if line.len > kind.len && line.starts_with(kind) && line[kind.len] == `,` {
			mut separator := line.len - 1
			for separator > 0 && line[separator] != `,` { separator-- }
			value := calendar_borrow(line, separator + 1, line.len)
			if value.len == 0 { return none }
			for byte in value { if !byte.is_digit() { return none } }
			return value.u64()
		}
		start = end + 1
	}
	return none
}

fn check_disk_usage_capacity_client(home string, mut desktop Desktop) {
	root := system_information_join_path(home, 'capacity-Ж')
	file := system_information_join_path(root, 'five-bytes.txt')
	path := system_information_join_path(home, 'capacity.csv')
	missing := system_information_join_path(home, 'capacity-missing')
	defer { unsafe { root.free(); file.free(); path.free(); missing.free() } }
	os.mkdir(root) or { panic(err) }
	os.write_file(file, '12345') or { panic(err) }
	expected := disk_usage_read_capacity(root)
	assert expected.valid
	factory := app_factory_named('vinix-disk-usage') or { panic('Disk Usage is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	storage_remote_field(mut app, disk_usage_action_root, root)
	app.handle(disk_usage_action_scan_path) or { panic(err) }
	for _ in 0 .. 100 {
		if mut app is RemoteApp { app.poll() }
	}
	storage_remote_field(mut app, disk_usage_action_report_path, path)
	app.handle(disk_usage_action_export) or { panic(err) }
	saved_report := tr_fill('disk_usage.report.saved', path)
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 546), saved_report)
	unsafe { saved_report.free() }
	record := os.read_file(path) or { panic(err) }
	defer { unsafe { record.free() } }
	assert (integration_csv_counter(record, 'root') or { panic('missing logical root bytes') }) == 5
	assert (integration_csv_counter(record, 'file_count') or { panic('missing file count') }) == 1
	total := integration_csv_counter(record, 'filesystem_total') or { panic('missing filesystem total') }
	used := integration_csv_counter(record, 'filesystem_used') or { panic('missing filesystem used') }
	free := integration_csv_counter(record, 'filesystem_free') or { panic('missing filesystem free') }
	available := integration_csv_counter(record, 'filesystem_available') or { panic('missing filesystem available') }
	assert total == expected.total && total > 5 && used <= total && free == total - used && available <= free
	app.handle(disk_usage_action_capacity) or { panic(err) }
	for size in [ui2.rect(0, 0, 880, 546), ui2.rect(0, 0, 400, 250)]! {
		capacity := app.build(size) or { panic(err) }
		assert tree_has_id(capacity, disk_usage_action_inventory) && tree_has_id(capacity, disk_usage_action_capacity)
		for key in ['disk_usage.capacity.total', 'disk_usage.capacity.used',
			'disk_usage.capacity.free', 'disk_usage.capacity.available']! { assert tree_contains_text(capacity, tr(key)) }
		for value in [total, used, free, available]! {
			formatted := disk_usage_size_text(value)
			assert tree_contains_text(capacity, formatted)
			unsafe { formatted.free() }
		}
		free_tree(capacity)
	}
	app.handle(disk_usage_action_inventory) or { panic(err) }
	storage_remote_field(mut app, disk_usage_action_root, missing)
	app.handle(disk_usage_action_scan_path) or { panic(err) }
	app.handle(disk_usage_action_capacity) or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 400, 250), tr('disk_usage.capacity.unavailable'))
	println('IPC Disk Usage filesystem cards and raw CSV snapshot distinct from five inventory bytes, unavailable root passed')
}

fn integration_grapher_chart_signature(element ui2.Element) ?u64 {
	if element.id == 'grapher.chart' {
		assert element.children.len > 100
		mut signature := u64(1469598103934665603)
		for child in element.children {
			for coordinate in [child.frame.x, child.frame.y, child.frame.width, child.frame.height]! {
				signature = (signature ^ u64(i64(coordinate * 1024))) * u64(1099511628211)
			}
		}
		return signature
	}
	for child in element.children {
		if signature := integration_grapher_chart_signature(child) { return signature }
	}
	return none
}

fn check_grapher_document_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, 'graph-日本語.vgraph')
	defer { unsafe { path.free() } }
	factory := app_factory_named('vinix-grapher') or { panic('Grapher is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	fields := ['sin(x)+x/2', '-3', '3', '-4', '4']!
	for index, text in fields { storage_remote_field(mut app, grapher_field_actions[index], text) }
	app.handle('grapher.plot') or { panic(err) }
	storage_remote_field(mut app, 'grapher.document_path', path)
	before := app.build(ui2.rect(0, 0, 840, 636)) or { panic(err) }
	assert tree_has_id(before, 'grapher.document_save_as') && tree_has_id(before, 'grapher.document_open')
	signature := integration_grapher_chart_signature(before) or { panic('missing serialized chart') }
	free_tree(before)
	app.handle('grapher.document_save_as') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 840, 636), 'Graph document saved.')
	expected := 'VINIX-GRAPH 1\nexpression=sin(x)+x/2\nxmin=-3\nxmax=3\nymin=-4\nymax=4\n'
	integration_assert_file(path, expected)
	app.handle('grapher.document_save_as') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 840, 636), 'This path already exists.')
	integration_assert_file(path, expected)
	for index, text in ['x*x', '-2', '2', '-1', '5']! {
		storage_remote_field(mut app, grapher_field_actions[index], text)
	}
	app.handle('grapher.plot') or { panic(err) }
	changed := app.build(ui2.rect(0, 0, 840, 636)) or { panic(err) }
	changed_signature := integration_grapher_chart_signature(changed) or { panic('missing changed chart') }
	assert changed_signature != signature
	free_tree(changed)
	app.handle('grapher.document_open') or { panic(err) }
	opened := app.build(ui2.rect(0, 0, 840, 636)) or { panic(err) }
	for index, text in fields {
		assert (integration_tree_text(opened, grapher_field_actions[index]) or { panic('missing graph field') }) == text
	}
	assert (integration_tree_text(opened, 'grapher.document_path') or { panic('missing document path') }) == path
	assert tree_contains_text(opened, 'Graph document opened.')
	assert (integration_grapher_chart_signature(opened) or { panic('missing restored chart') }) == signature
	free_tree(opened)
	println('IPC Grapher exclusive Save As, Open, restored fields and serialized chart passed')
}

fn integration_archive_selection_fixture() []u8 {
	mut bytes := []u8{cap: 8192}
	unsafe { bytes.flags |= .noslices }
	names := ['documents', 'documents/日本語.txt', 'documents/nested', 'documents/nested/empty.txt',
		'documents-copy', 'documents-copy/other.txt']!
	for index, name in names {
		payload := if index == 1 { 'selected 😀\n' } else if index == 5 { 'omitted sibling' } else { '' }
		header := archive_tar_header(ArchiveEntry{name: name, size: u64(payload.len), directory: index in [0, 2, 4]!})
		for byte in header { bytes << byte }
		for byte in payload { bytes << byte }
		for _ in 0 .. (512 - payload.len % 512) % 512 { bytes << u8(0) }
	}
	for _ in 0 .. 1024 { bytes << u8(0) }
	return bytes
}

fn check_archive_selection_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, 'selected-日本語.tar')
	destination := system_information_join_path(home, 'extracted-Ж')
	member := system_information_join_path(destination, 'documents/日本語.txt')
	empty_member := system_information_join_path(destination, 'documents/nested/empty.txt')
	omitted := system_information_join_path(destination, 'documents-copy')
	bytes := integration_archive_selection_fixture()
	defer { unsafe {
		path.free(); destination.free(); member.free(); empty_member.free(); omitted.free(); bytes.free()
	} }
	os.write_file_array(path, bytes) or { panic(err) }
	factory := app_factory_named('vinix-archive') or { panic('Archive Utility is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	storage_remote_field(mut app, 'archive.path', path)
	app.handle('archive.browse') or { panic(err) }
	storage_remote_wait(mut app, ui2.rect(0, 0, 800, 656), 'Archive validated.')
	storage_remote_field(mut app, 'archive.destination', destination)
	app.handle('archive.extract_selected') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 800, 656), 'Select at least one entry')
	assert !os.exists(destination)
	app.handle('archive.row.0') or { panic(err) }
	selected := app.build(ui2.rect(0, 0, 800, 656)) or { panic(err) }
	assert (integration_tree_text(selected, 'archive.row.0') or { panic('missing folder toggle') }) == '[x]'
	assert (integration_tree_text(selected, 'archive.row.1') or { panic('missing member toggle') }) == '[x]'
	assert (integration_tree_text(selected, 'archive.row.4') or { panic('missing sibling toggle') }) == '[ ]'
	assert tree_contains_text(selected, 'documents/日本語.txt')
	free_tree(selected)
	app.handle('archive.extract_selected') or { panic(err) }
	storage_remote_wait(mut app, ui2.rect(0, 0, 800, 656), 'Archive extracted.')
	integration_assert_file(member, 'selected 😀\n')
	integration_assert_file(empty_member, '')
	assert !os.exists(omitted)
	println('IPC Archive visible directory selection, exact members and omitted sibling passed')
}

fn check_system_information_search_client(home string, mut desktop Desktop) {
	path := system_information_join_path(home, 'system-search-Ж.txt')
	defer { unsafe { path.free() } }
	factory := app_factory_named('vinix-system-information') or { panic('System Information is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	free_tree(app.build(ui2.rect(0, 0, 780, 516)) or { panic(err) })
	if mut app is RemoteApp { app.key_input('\x06'); app.paste_input('kernel') }
	matching := app.build(ui2.rect(0, 0, 780, 516)) or { panic(err) }
	assert (integration_tree_text(matching, 'system_information.search') or { panic('missing report search') }) == 'kernel'
	assert tree_contains_text(matching, 'Kernel') && !tree_has_id(matching, 'system_information.search.empty')
	free_tree(matching)
	query := 'vinix-no-such-report-Ж😀-987654'
	if mut app is RemoteApp { app.key_input('\x06'); app.paste_input(query) }
	empty := app.build(ui2.rect(0, 0, 780, 516)) or { panic(err) }
	assert (integration_tree_text(empty, 'system_information.search') or { panic('missing report search') }) == query
	assert tree_has_id(empty, 'system_information.search.empty')
	free_tree(empty)
	storage_remote_field(mut app, 'system_information.path', path)
	app.handle('system_information.export') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 780, 516), 'Report saved')
	report := os.read_file(path) or { panic(err) }
	defer { unsafe { report.free() } }
	for section in ['\nOverview\n', '\nHardware\n', '\nStorage\n', '\nInstalled packages\n']! {
		assert report.contains(section)
	}
	assert report.contains('Kernel') && !report.contains(query)
	if mut app is RemoteApp {
		app.key_input('\x06')
		app.paste_input(query)
		// Split CSI and SS3 navigation over several real request packets.
		app.key_input('\x1b')
		app.key_input('[')
		app.key_input('B')
		app.key_input('\x1bO')
		app.key_input('A')
	}
	navigated := app.build(ui2.rect(0, 0, 780, 516)) or { panic(err) }
	assert (integration_tree_text(navigated, 'system_information.search') or { panic('missing navigated search') }) == query
	assert tree_has_id(navigated, 'system_information.search.empty')
	free_tree(navigated)
	if mut app is RemoteApp {
		assert app.polling
		app.key_input('\x1b')
	}
	mut escaped := false
	for _ in 0 .. 100 {
		if mut app is RemoteApp { app.poll() }
		tree := app.build(ui2.rect(0, 0, 780, 516)) or { panic(err) }
		escaped = (integration_tree_text(tree, 'system_information.search') or { panic('missing Escape search') }) == ''
		free_tree(tree)
		if escaped { break }
		desktop_sleep_ms(20)
	}
	assert escaped
	if mut app is RemoteApp { app.key_input('\x06'); app.paste_input('kernel') }
	app.handle('system_information.search.clear') or { panic(err) }
	cleared := app.build(ui2.rect(0, 0, 780, 516)) or { panic(err) }
	assert (integration_tree_text(cleared, 'system_information.search') or { panic('missing cleared search') }) == ''
	assert !tree_has_id(cleared, 'system_information.search.empty')
	free_tree(cleared)
	println('IPC System Information Ctrl-F, fragmented navigation, Escape and full report export passed')
}

fn integration_terminal_cells(text string, end int) int {
	mut at := 0
	mut cells := 0
	for at < end {
		length := editor_utf8_length(text[at])
		at += if length > 0 && at + length <= end { length } else { 1 }
		cells++
	}
	return cells
}

fn integration_assert_image_size(path string, width int, height int) {
	bytes := os.read_bytes(path) or { panic(err) }
	defer { unsafe { bytes.free() } }
	mut dimensions := [3]int{}
	assert unsafe { C.stbi_info_from_memory(bytes.data, bytes.len, &dimensions[0], &dimensions[1], &dimensions[2]) } != 0
	assert dimensions[0] == width && dimensions[1] == height
}

fn check_preview_orientation_client(home string, mut desktop Desktop) {
	// Independent asymmetric 2x3 JPEG plus a little-endian IFD0 Orientation6.
	image := base64.decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAADAAIDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABoQAAIDAQEAAAAAAAAAAAAAAAQFAgMHBgH/xAAVAQEBAAAAAAAAAAAAAAAAAAAHCv/EABsRAAIDAQEBAAAAAAAAAAAAAAUGAwQHCAkC/9oADAMBAAIRAxEAPwBUcDgqTYViycPlOCuEVZNnK0W5rnnDPmlo4PHphaLGTx5zzF05PnVVGRjVwwOaMSPbDGBhRd1183LXvKXgts1nUGkpiJGqTZdEdWAjVWtk3hLXK18yykyNuAAnJ2nAlFTCQ2LMkYpaVgYZcBUPmAWDFDhlWrUhlx9FupNZRvQbutKCwZDdDJ/ZHTqsJuOHOPOuhttsYv7a7iaFlpf3/K2Z7eGOerUilNuDqyMDazE/u0aZDZUzduX7H//Z')
	segment := [u8(0xff), 0xe1, 0, 34, `E`, `x`, `i`, `f`, 0, 0,
		`I`, `I`, 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 1, 3, 0,
		1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0]!
	mut jpeg := []u8{len: image.len + segment.len}
	jpeg[0] = 0xff
	jpeg[1] = 0xd8
	for index, byte in segment { jpeg[2 + index] = byte }
	for index in 2 .. image.len { jpeg[index + segment.len] = image[index] }
	path := join_path(home, 'orientation.jpg')
	export_path := join_path(home, 'orientation.png')
	rotated_path := join_path(home, 'orientation-rotated.png')
	original_path := join_path(home, 'orientation-original.jpg')
	open_action := jump_open_prefix + path
	defer { unsafe {
		image.free(); jpeg.free(); path.free(); export_path.free()
		rotated_path.free(); original_path.free(); open_action.free()
	} }
	os.write_file_array(path, jpeg) or { panic(err) }
	factory := app_factory_named('vinix-preview') or { panic('Preview is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle(open_action) or { panic(err) }
	free_tree(app.build(ui2.rect(0, 0, 800, 576)) or { panic(err) })
	storage_remote_field(mut app, preview_action_export_path, export_path)
	app.handle(preview_action_export_png) or { panic(err) }
	integration_assert_image_size(export_path, 3, 2)
	app.handle(preview_action_rotate_right) or { panic(err) }
	storage_remote_field(mut app, preview_action_export_path, rotated_path)
	app.handle(preview_action_export_png) or { panic(err) }
	integration_assert_image_size(rotated_path, 2, 3)
	storage_remote_field(mut app, preview_action_export_path, original_path)
	app.handle(preview_action_export_copy) or { panic(err) }
	original := os.read_bytes(original_path) or { panic(err) }
	defer { unsafe { original.free() } }
	assert original == jpeg
	println('IPC Preview EXIF orientation, rotated PNG and exact Original Copy passed')
}

fn check_terminal_copy_client(mut desktop Desktop) {
	if !os.exists(terminal_shell) {
		println('IPC Terminal copy skipped: shell unavailable')
		return
	}
	factory := app_factory_named('vinix-terminal') or { panic('Terminal is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	free_tree(app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) })
	expected := 'vinix-copy-日本語'
	if mut app is RemoteApp {
		assert app.clipboard_copy && app.pointer && app.keyboard
		app.key_input(expected)
	}
	mut found := false
	mut x := 0
	mut y := 0
	for _ in 0 .. 50 {
		if mut app is RemoteApp { app.poll() }
		tree := app.build(ui2.rect(0, 0, 560, 316)) or { panic(err) }
		for child in tree.children {
			at := child.text.index(expected) or { continue }
			x = terminal_padding + integration_terminal_cells(child.text, at) * terminal_column_width
			y = int(child.frame.y) + 4
			found = true
			break
		}
		free_tree(tree)
		if found { break }
		desktop_sleep_ms(20)
	}
	assert found
	if mut app is RemoteApp {
		app.pointer_event(.down, .left, 0, x, y, 560, 316)
		app.pointer_event(.move, .no_button, 0,
			x + integration_terminal_cells(expected, expected.len) * terminal_column_width, y, 560, 316)
		app.pointer_event(.up, .left, 0,
			x + integration_terminal_cells(expected, expected.len) * terminal_column_width, y, 560, 316)
	}
	app.handle('term.selection.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, expected)
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 316), tr('clipboard.copy.copied'))
	assert desktop.clipboard.set_local_text('Cmd-C must replace this text')
	if mut app is RemoteApp { app.key_input('\x1b[99;9u') }
	integration_assert_clipboard(&desktop, expected)
	integration_assert_text(mut app, ui2.rect(0, 0, 560, 316), tr('clipboard.copy.copied'))
	if mut app is RemoteApp { app.key_input('\x03') }
	integration_assert_clipboard(&desktop, expected)
	println('IPC Terminal UTF-8 pointer selection, Copy, Cmd-C and Ctrl-C passed')
}

fn integration_programmer_readout(element ui2.Element, row int) ?string {
	if row >= 0 && row < 4 && element.id == ['calculator.programmer.readout.dec',
		'calculator.programmer.readout.hex', 'calculator.programmer.readout.oct',
		'calculator.programmer.readout.bin']![row] {
		return element.text
	}
	for child in element.children {
		if text := integration_programmer_readout(child, row) { return text }
	}
	return none
}

fn integration_assert_integer(mut app NativeApp, expected [4]string) {
	tree := app.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
	defer { free_tree(tree) }
	assert tree_has_id(tree, 'calculator.programmer.equals')
	for row, text in expected {
		actual := integration_programmer_readout(tree, row) or { panic('missing integer readout') }
		assert actual == text, 'Programmer readout ${row}: ${actual}, expected ${text}'
	}
}

// Exact operands and results cross the real app protocol without converting
// through floating point. Returning to Basic must retain its pending sum.
fn check_programmer_calculator_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-calculator') or { panic('Calculator is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	if mut app is RemoteApp {
		assert app.pid > 0 && app.keyboard && C.kill(app.pid, 0) == 0
		app.key_input('2+3\x10')
		app.paste_input('18446744073709551615')
	}
	integration_assert_integer(mut app, ['18446744073709551615', 'FFFFFFFFFFFFFFFF',
		'1777777777777777777777', '1111111111111111111111111111111111111111111111111111111111111111']!)
	for index, base in ['dec', 'hex', 'oct', 'bin']! {
		app.handle('calculator.programmer.base.' + base) or { panic(err) }
		app.handle('calculator.copy') or { panic(err) }
		integration_assert_clipboard(&desktop, ['18446744073709551615', 'FFFFFFFFFFFFFFFF',
			'1777777777777777777777', '1111111111111111111111111111111111111111111111111111111111111111']![index])
		integration_assert_text(mut app, ui2.rect(0, 0, 620, 576), tr('clipboard.copy.copied'))
	}
	app.handle('calculator.programmer.base.dec') or { panic(err) }
	if mut app is RemoteApp { app.key_input('+1=') }
	integration_assert_integer(mut app, ['0', '0', '0', '0']!)
	app.handle('calculator.programmer.not') or { panic(err) }
	app.handle('calculator.programmer.shr') or { panic(err) }
	if mut app is RemoteApp {
		app.paste_input('63')
		app.key_input('=')
	}
	integration_assert_integer(mut app, ['1', '1', '1', '1']!)
	app.handle('calculator.programmer.shl') or { panic(err) }
	if mut app is RemoteApp {
		app.paste_input('64')
		app.key_input('=')
	}
	integration_assert_text(mut app, ui2.rect(0, 0, 620, 576), tr('calculator.programmer.error.shift'))
	integration_assert_integer(mut app, ['64', '40', '100', '1000000']!)
	app.handle('calculator.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, '1111111111111111111111111111111111111111111111111111111111111111')
	integration_assert_text(mut app, ui2.rect(0, 0, 620, 576), tr('clipboard.copy.empty'))
	app.handle('calculator.programmer.clear') or { panic(err) }
	app.handle('calculator.programmer.base.hex') or { panic(err) }
	if mut app is RemoteApp {
		app.key_input('ff&')
		app.paste_input('0b1010')
		app.key_input('=')
	}
	integration_assert_integer(mut app, ['10', 'A', '12', '1010']!)
	if mut app is RemoteApp { app.paste_input('0x10000000000000000') }
	integration_assert_text(mut app, ui2.rect(0, 0, 620, 576), tr('calculator.programmer.error.range'))
	integration_assert_integer(mut app, ['10', 'A', '12', '1010']!)
	if mut app is RemoteApp { app.key_input('\x10=') }
	integration_calculator_display(mut app, '5')
	if mut app is RemoteApp { app.key_input('\x03') }
	integration_assert_clipboard(&desktop, '5')
	assert native_app_prepare_close(mut app)
	println('IPC Programmer Calculator exact integers and Basic state passed')
}

fn integration_assert_clipboard(desktop &Desktop, expected string) {
	assert desktop.clipboard.local_available && desktop.clipboard.local_length == expected.len,
		'Clipboard has ${desktop.clipboard.local_length} bytes; expected ${expected.len}'
	assert unsafe { tos(&desktop.clipboard.local_bytes[0], desktop.clipboard.local_length) } == expected
	assert desktop.clipboard.pid == -1 && desktop.clipboard.fd == -1
}

fn integration_editor_paste(mut desktop Desktop, mut app NativeApp) {
	app.handle(editor_action_document) or { panic(err) }
	rest := desktop.take_paste_keys('\x16')
	assert rest.len == 0
	unsafe { rest.free() }
}

// Copy/Cut waits for the compositor's acknowledgement. Saved document bytes
// verify selection replacement and Undo as well as visible highlight state.
fn check_editor_selection_client(home string) {
	path := join_path(home, 'selection-Ж.txt')
	mut desktop := Desktop{ home: home, focus: 9300 }
	defer {
		desktop.clipboard.close_request()
		desktop.free_start_menu_query()
		unsafe {
			path.free()
			desktop.apps.free()
			desktop.windows.free()
			desktop.native_asset_icons.free()
			desktop.clipboard.url.free()
			desktop.clipboard.pending.free()
			desktop.clipboard.data.free()
		}
	}
	factory := app_factory_named('vinix-editor') or { panic('Text Editor is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	desktop.apps << app
	desktop.windows << Window{ id: 9300, title: 'Text Editor', page: .app, app_index: 0 }
	app.handle(editor_action_document) or { panic(err) }
	document := 'aй😀\nsecond\nthird\nfourth\nfifth'
	if mut app is RemoteApp {
		assert app.clipboard_copy && app.pointer && app.peer_features & app_feature_text_copy != 0
		app.paste_input(document)
		app.key_input('\x01\x03')
	}
	integration_assert_clipboard(&desktop, document)
	selected := app.build(ui2.rect(0, 0, 700, 500)) or { panic(err) }
	assert tree_has_id(selected, 'editor.selection.highlight')
	free_tree(selected)
	if mut app is RemoteApp { app.key_input('\x18') }
	integration_assert_clipboard(&desktop, document)
	app.handle(editor_action_save_as) or { panic(err) }
	storage_remote_field(mut app, editor_action_save_as_path, path)
	app.handle(editor_action_save_as_create) or { panic(err) }
	integration_assert_file(path, '')
	app.handle(editor_action_document) or { panic(err) }
	if mut app is RemoteApp { app.key_input('\x1a') }
	app.handle(editor_action_save) or { panic(err) }
	integration_assert_file(path, document)
	app.handle(editor_action_document) or { panic(err) }
	if mut app is RemoteApp {
		app.key_input('\x01')
		app.paste_input('replaced')
	}
	integration_editor_paste(mut desktop, mut app)
	app.handle(editor_action_save) or { panic(err) }
	integration_assert_file(path, 'replacedaй😀\nsecond\nthird\nfourth\nfifth')
	if mut app is RemoteApp { app.key_input('\x1a\x1a') }
	app.handle(editor_action_save) or { panic(err) }
	integration_assert_file(path, document)
	// Build first to establish the child's viewport before pointer packets.
	viewport := app.build(ui2.rect(0, 0, 700, 500)) or { panic(err) }
	free_tree(viewport)
	if mut app is RemoteApp {
		app.pointer_event(.down, .left, 0, 18, 90, 700, 500)
		app.pointer_event(.up, .left, 0, 18, 90, 700, 500)
		app.key_input('!')
	}
	app.handle(editor_action_save) or { panic(err) }
	integration_assert_file(path, 'a!й😀\nsecond\nthird\nfourth\nfifth')
	if mut app is RemoteApp { app.key_input('\x1a') }
	if mut app is RemoteApp {
		app.pointer_event(.down, .left, 0, 18, 90, 700, 500)
		app.pointer_event(.move, .no_button, 0, 26, 108, 700, 500)
		app.pointer_event(.up, .left, 0, 26, 108, 700, 500)
		app.key_input('\x03')
	}
	integration_assert_clipboard(&desktop, 'й😀\nse')
	dragged := app.build(ui2.rect(0, 0, 700, 500)) or { panic(err) }
	assert tree_has_id(dragged, 'editor.selection.highlight')
	free_tree(dragged)
	if mut app is RemoteApp { app.paste_input('Z') }
	app.handle(editor_action_save) or { panic(err) }
	integration_assert_file(path, 'aZcond\nthird\nfourth\nfifth')
	// Copied control bytes are text when pasted into Start-menu search.
	app.handle(editor_action_document) or { panic(err) }
	if mut app is RemoteApp {
		app.key_input('\x01')
		app.paste_input('calc\n\x1b\x7f\t日本語')
		app.key_input('\x01\x03')
	}
	integration_assert_clipboard(&desktop, 'calc\n\x1b\x7f\t日本語')
	desktop.start_menu_open = true
	desktop.start_menu_page = 2
	window_count := desktop.windows.len
	rest := desktop.take_paste_keys('\x16')
	assert rest.len == 0
	unsafe { rest.free() }
	assert desktop.start_menu_open && desktop.start_menu_page == 0 && desktop.start_menu_searching
	assert desktop.start_menu_query_text() == 'calc 日本語'
	assert desktop.windows.len == window_count
	if mut app is RemoteApp {
		assert C.kill(app.pid, 0) == 0
	}
	desktop.start_menu_open = false
	// A live Clock has no clipboard-copy capability, even though its
	// protocol peer supports the shared extension.
	clock_factory := app_factory_named('vinix-clock') or { panic('Clock is not registered') }
	mut clock := start_remote_app_at_with_timeout(arguments()[0], clock_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut clock) }
	request := text_copy_request(71, 'unauthorized overwrite')
	defer { unsafe { request.free() } }
	if mut clock is RemoteApp {
		assert clock.pid > 0 && !clock.clipboard_copy
		assert !clock.handle_native_operation(editor_bytes_text(request))
	}
	integration_assert_clipboard(&desktop, 'calc\n\x1b\x7f\t日本語')
	free_tree(clock.build(ui2.rect(0, 0, 540, 420)) or { panic(err) })
	println('IPC Editor selection, clipboard acknowledgement, pointer and paste passed')
}

fn check_settings_search_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-settings') or { panic('Settings is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	if mut app is RemoteApp {
		assert app.pid > 0 && app.keyboard && app.polling
		app.key_input('\x06window buttons')
	}
	results := app.build(ui2.rect(0, 0, 760, 576)) or { panic(err) }
	assert tree_has_id(results, 'settings.search.result.0') && !tree_has_id(results, 'settings.search.result.1')
	free_tree(results)
	if mut app is RemoteApp {
		app.key_input('\x1b')
		app.key_input('[B\r')
	}
	appearance := app.build(ui2.rect(0, 0, 760, 576)) or { panic(err) }
	assert tree_has_id(appearance, 'settings.side.0') && !tree_has_id(appearance, 'settings.search.result.0')
	free_tree(appearance)
	if mut app is RemoteApp {
		app.key_input('\x06')
		app.paste_input('brightness')
	}
	display_results := app.build(ui2.rect(0, 0, 760, 576)) or { panic(err) }
	assert tree_has_id(display_results, 'settings.search.result.0')
	free_tree(display_results)
	app.handle('settings.search.result.0') or { panic(err) }
	display := app.build(ui2.rect(0, 0, 760, 576)) or { panic(err) }
	assert tree_has_id(display, settings_scale_100_action) && !tree_has_id(display, 'settings.search.result.0')
	free_tree(display)
	if mut app is RemoteApp {
		app.key_input('\x06')
		app.paste_input('keyboard french')
		app.key_input('\r')
	}
	keyboard := app.build(ui2.rect(0, 0, 760, 576)) or { panic(err) }
	assert tree_has_id(keyboard, 'settings.keyboard.enable.3')
	free_tree(keyboard)
	println('IPC Settings search and keyboard pane navigation passed')
}

fn integration_tree_background(element ui2.Element, id string) ?u32 {
	if element.id == id { return element.box.bg }
	for child in element.children {
		if color := integration_tree_background(child, id) { return color }
	}
	return none
}

fn check_activity_view_client(home string, mut desktop Desktop) {
	if !os.exists(activity_device) {
		println('IPC Activity saved view requires the real /dev/processes device; host check skipped')
		return
	}
	path := join_path(home, activity_preferences_filename)
	defer { unsafe { path.free() } }
	factory := app_factory_named('vinix-activity') or { panic('Activity Monitor is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	for action in ['activity.sort.name', 'activity.sort.name', 'activity.tree', 'activity.filter',
		'activity.column.toggle.ppid', 'activity.interval', 'activity.view.resources',
		'activity.resources.network']! {
		app.handle(action) or { panic(err) }
	}
	close_remote(mut app)
	record := os.read_file(path) or { panic(err) }
	defer { unsafe { record.free() } }
	prefs := activity_parse_view_preferences(record) or { panic('missing saved Activity view') }
	assert prefs.sort == .name && prefs.descending && prefs.hierarchy && prefs.filter == .applications
	assert prefs.columns & activity_column_bit(.ppid) != 0 && prefs.interval_ms == 2000
	assert prefs.view == .resources && prefs.resource_tab == .network
	mut reopened := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut reopened) }
	resources := reopened.build(ui2.rect(0, 0, 900, 600)) or { panic(err) }
	assert tree_has_id(resources, 'activity.resources')
	network_color := integration_tree_background(resources, 'activity.resources.network') or { panic('missing Network tab') }
	assert network_color == app_accent
	free_tree(resources)
	reopened.handle('activity.view.processes') or { panic(err) }
	processes := reopened.build(ui2.rect(0, 0, 900, 600)) or { panic(err) }
	assert tree_has_id(processes, 'activity.sort.ppid')
	tree_color := integration_tree_background(processes, 'activity.tree') or { panic('missing hierarchy control') }
	assert tree_color == files_sidebar_selected
	free_tree(processes)
	println('IPC Activity saved view and reopen passed')
}

// An independently packed tiny index keeps this IPC check offline and bounded.
fn integration_dictionary_fixture() []u8 {
	words := ['computer', 'computing', 'data structure']!
	definitions := ['IPC electronic machine 日本語.', 'IPC computing definition.', 'IPC organized collection.']!
	mut bytes := []u8{cap: 512}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, 'VNXDICT1')
	mut key_size := 0
	mut definition_size := 0
	for word in words { key_size += word.len }
	for definition in definitions { definition_size += definition.len }
	for value in [3, key_size, definition_size, 0]! { wire_put_u32(mut bytes, u32(value)) }
	mut key_at := 0
	mut definition_at := 0
	for index, word in words {
		for value in [key_at, word.len, definition_at, definitions[index].len]! { wire_put_u32(mut bytes, u32(value)) }
		key_at += word.len
		definition_at += definitions[index].len
	}
	for word in words { editor_append(mut bytes, word) }
	for definition in definitions { editor_append(mut bytes, definition) }
	return bytes
}

fn check_dictionary_workflow_client(home string, mut desktop Desktop) {
	path := join_path(home, 'fixture.vnd')
	export_path := join_path(home, 'definition-Ж.txt')
	bad_path := join_path(home, 'broken.vnd')
	bytes := integration_dictionary_fixture()
	defer { unsafe { path.free(); export_path.free(); bad_path.free(); bytes.free() } }
	os.write_file_array(path, bytes) or { panic(err) }
	os.write_file(bad_path, 'truncated index') or { panic(err) }
	factory := app_factory_named('vinix-dictionary') or { panic('Dictionary is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	storage_remote_field(mut app, 'dictionary.path', path)
	app.handle('dictionary.load') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), 'IPC electronic machine 日本語.')
	storage_remote_field(mut app, 'dictionary.query', '  COMPUTER  ')
	app.handle('dictionary.lookup') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), tr('dictionary.ready'))
	storage_remote_field(mut app, 'dictionary.query', 'comp')
	prefix := app.build(ui2.rect(0, 0, 880, 620)) or { panic(err) }
	assert tree_has_id(prefix, 'dictionary.result.0') && tree_has_id(prefix, 'dictionary.result.1')
	assert !tree_has_id(prefix, 'dictionary.result.2')
	free_tree(prefix)
	app.handle('dictionary.result.1') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), 'IPC computing definition.')
	storage_remote_field(mut app, 'dictionary.query', 'DATA_structure')
	app.handle('dictionary.lookup') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), 'IPC organized collection.')
	app.handle('dictionary.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, 'data structure\n\nIPC organized collection.')
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), tr('clipboard.copy.copied'))
	app.handle('dictionary.back') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), 'IPC computing definition.')
	if mut app is RemoteApp { app.key_input('\x03') }
	integration_assert_clipboard(&desktop, 'computing\n\nIPC computing definition.')
	app.handle('dictionary.forward') or { panic(err) }
	storage_remote_field(mut app, 'dictionary.export_path', export_path)
	app.handle('dictionary.export') or { panic(err) }
	integration_assert_file(export_path, 'data structure\n\nIPC organized collection.')
	app.handle('dictionary.export') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), tr('dictionary.export_exists'))
	integration_assert_file(export_path, 'data structure\n\nIPC organized collection.')
	storage_remote_field(mut app, 'dictionary.path', bad_path)
	app.handle('dictionary.load') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), tr('dictionary.unavailable'))
	integration_assert_text(mut app, ui2.rect(0, 0, 880, 620), 'IPC organized collection.')
	println('IPC Dictionary lookup and exclusive export passed')
}

fn integration_assert_calendar_export(path string) {
	record := os.read_file(path) or { panic(err) }
	defer { unsafe { record.free() } }
	mut model, status := calendar_ics_parse(record)
	defer { model.free_items() }
	assert status == '' && model.count == 2
	for index in 0 .. model.count {
		assert model.items[index].year == 2026 && model.items[index].month == 10 && model.items[index].day == 5
	}
	assert model.items[0].title == 'IPC all-day 日本語' && model.items[0].minutes == -1
	assert model.items[0].location == 'Room, A'
	assert model.items[1].title == 'IPC local meeting' && model.items[1].minutes == 870
}

fn check_calendar_interchange_client(home string, mut desktop Desktop) {
	input := join_path(home, 'calendar-Ж.ics')
	unsupported := join_path(home, 'unsupported.ics')
	export_path := join_path(home, 'calendar-export.ics')
	preserved_export := join_path(home, 'calendar-preserved.ics')
	reopened_export := join_path(home, 'calendar-reopened.ics')
	store := join_path(home, calendar_events_filename)
	defer { unsafe { input.free(); unsupported.free(); export_path.free(); preserved_export.free(); reopened_export.free(); store.free() } }
	ics := 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:Vinix IPC\r\nBEGIN:VEVENT\r\nUID:ipc-one\r\nDTSTAMP:20261005T120000Z\r\nDTSTART;VALUE=DATE:20261005\r\nSUMMARY:IPC all-day 日本語\r\nLOCATION:Room\\, A\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:ipc-two\r\nDTSTAMP:20261005T120000Z\r\nDTSTART:20261005T143000\r\nSUMMARY:IPC local meeting\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n'
	os.write_file(input, ics) or { panic(err) }
	bad_ics := ics.replace('SUMMARY:IPC local meeting', 'RRULE:FREQ=DAILY\r\nSUMMARY:IPC local meeting')
	defer { unsafe { bad_ics.free() } }
	os.write_file(unsupported, bad_ics) or { panic(err) }
	factory := app_factory_named('vinix-calendar') or { panic('Calendar is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle('calendar.ics.open') or { panic(err) }
	storage_remote_field(mut app, 'calendar.ics.import_path', input)
	app.handle('calendar.ics.import') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), tr('calendar.ics.imported'))
	stored := os.read_file(store) or { panic(err) }
	defer { unsafe { stored.free() } }
	assert stored.contains('IPC all-day 日本語') && stored.contains('IPC local meeting')
	storage_remote_field(mut app, 'calendar.ics.export_path', export_path)
	app.handle('calendar.ics.export') or { panic(err) }
	exported := os.read_file(export_path) or { panic(err) }
	defer { unsafe { exported.free() } }
	assert exported.contains('DTSTART;VALUE=DATE:20261005\r\n')
	assert exported.contains('DTSTART:20261005T143000\r\n')
	assert exported.contains('SUMMARY:IPC all-day 日本語\r\n') && exported.contains('LOCATION:Room\\, A\r\n')
	app.handle('calendar.ics.export') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), tr('calendar.ics.export_exists'))
	integration_assert_file(export_path, exported)
	storage_remote_field(mut app, 'calendar.ics.import_path', unsupported)
	app.handle('calendar.ics.import') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), tr('calendar.ics.unsupported'))
	integration_assert_file(store, stored)
	storage_remote_field(mut app, 'calendar.ics.export_path', preserved_export)
	app.handle('calendar.ics.export') or { panic(err) }
	integration_assert_calendar_export(preserved_export)
	close_remote(mut app)
	mut reopened := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut reopened) }
	reopened.handle('calendar.ics.open') or { panic(err) }
	storage_remote_field(mut reopened, 'calendar.ics.export_path', reopened_export)
	reopened.handle('calendar.ics.export') or { panic(err) }
	integration_assert_calendar_export(reopened_export)
	println('IPC Calendar interchange and reopen passed')
}

fn check_editor_workflow_client(home string, mut desktop Desktop) {
	existing := join_path(home, 'existing.txt')
	saved := join_path(home, 'draft-Ж.txt')
	missing := disk_utility_join_path(home, 'missing/target.txt')
	defer { unsafe { existing.free(); saved.free(); missing.free() } }
	os.write_file(existing, 'preserved existing file') or { panic(err) }
	factory := app_factory_named('vinix-editor') or { panic('Text Editor is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle(editor_action_document) or { panic(err) }
	mut pid := -1
	if mut app is RemoteApp {
		pid = app.pid
		assert app.peer_features & app_feature_close_guard != 0
		app.paste_input('IPC unsaved 日本語')
	}
	assert pid > 0
	mut session := Desktop{ running: true }
	session.apps << app
	session.windows << Window{ id: 9200, title: 'Text Editor', page: .app, app_index: 0 }
	defer { unsafe { session.apps.free(); session.windows.free() } }
	session.close_window(9200)
	assert session.windows.len == 1 && session.focus == 9200
	session.end_session(.keep_running)
	assert session.running && session.windows.len == 1 && C.kill(pid, 0) == 0
	integration_assert_text(mut app, ui2.rect(0, 0, 700, 500), 'IPC unsaved 日本語')
	app.handle(editor_action_guard_save) or { panic(err) }
	storage_remote_field(mut app, editor_action_save_as_path, existing)
	app.handle(editor_action_save_as_create) or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 700, 500), tr('editor.workflow.exists'))
	integration_assert_file(existing, 'preserved existing file')
	assert !native_app_prepare_close(mut app)
	storage_remote_field(mut app, editor_action_save_as_path, saved)
	app.handle(editor_action_save_as_create) or { panic(err) }
	integration_assert_file(saved, 'IPC unsaved 日本語')
	assert native_app_prepare_close(mut app)
	app.handle(editor_action_document) or { panic(err) }
	if mut app is RemoteApp { app.paste_input('\nRetained after failed Open') }
	storage_remote_field(mut app, editor_action_path, missing)
	app.handle(editor_action_open) or { panic(err) }
	app.handle(editor_action_discard) or { panic(err) }
	app.handle(editor_action_confirm_discard) or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 700, 500), 'Retained after failed Open')
	integration_assert_text(mut app, ui2.rect(0, 0, 700, 500), tr('editor.status.cannot_open'))
	assert !os.exists(missing)
	app.handle(editor_action_save) or { panic(err) }
	integration_assert_file(saved, 'IPC unsaved 日本語\nRetained after failed Open')
	assert !os.exists(missing)
	app.handle(editor_action_document) or { panic(err) }
	if mut app is RemoteApp { app.paste_input('\nExplicitly discarded draft') }
	assert !native_app_prepare_close(mut app)
	app.handle(editor_action_confirm_discard) or { panic(err) }
	assert !native_app_prepare_close(mut app)
	app.handle(editor_action_discard) or { panic(err) }
	confirmation := app.build(ui2.rect(0, 0, 700, 500)) or { panic(err) }
	assert tree_has_id(confirmation, editor_action_confirm_discard)
	free_tree(confirmation)
	app.handle(editor_action_confirm_discard) or { panic(err) }
	session.close_window(9200)
	assert session.windows.len == 0
	if mut app is RemoteApp { assert app.closed }
	integration_assert_file(saved, 'IPC unsaved 日本語\nRetained after failed Open')
	session.end_session(.keep_running)
	assert !session.running
	println('IPC Text Editor close, Save As, and failed Open passed')
}

fn check_files_trash_client(home string, mut desktop Desktop) {
	path := join_path(home, 'Trash café 日本語.txt')
	open_action := jump_open_prefix + path
	defer { unsafe { path.free(); open_action.free() } }
	os.write_file(path, 'IPC original trash contents') or { panic(err) }
	factory := app_factory_named('vinix-files') or { panic('Files is not registered') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut app) }
	app.handle(open_action) or { panic(err) }
	app.handle(file_context_delete) or { panic(err) }
	assert !os.exists(path)
	app.handle('files.trash.open') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), 'Trash café 日本語.txt')
	app.handle('files.trash.row.0') or { panic(err) }
	os.write_file(path, 'IPC replacement must survive') or { panic(err) }
	app.handle('files.trash.restore') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), tr('files.trash.conflict'))
	integration_assert_file(path, 'IPC replacement must survive')
	os.rm(path) or { panic(err) }
	app.handle('files.trash.restore') or { panic(err) }
	integration_assert_file(path, 'IPC original trash contents')
	app.handle('files.trash.back') or { panic(err) }
	app.handle(open_action) or { panic(err) }
	app.handle(file_context_delete) or { panic(err) }
	assert !os.exists(path)
	app.handle('files.trash.open') or { panic(err) }
	app.handle('files.trash.confirm') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), 'Trash café 日本語.txt')
	app.handle('files.trash.empty') or { panic(err) }
	armed := app.build(ui2.rect(0, 0, 740, 520)) or { panic(err) }
	assert tree_has_id(armed, 'files.trash.confirm') && tree_has_id(armed, 'files.trash.cancel')
	free_tree(armed)
	app.handle('files.trash.cancel') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), 'Trash café 日本語.txt')
	app.handle('files.trash.empty') or { panic(err) }
	app.handle('files.trash.confirm') or { panic(err) }
	integration_assert_text(mut app, ui2.rect(0, 0, 740, 520), tr('files.trash.empty_list'))
	assert !os.exists(path)
	close_remote(mut app)
	mut reopened := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut reopened) }
	reopened.handle('files.trash.open') or { panic(err) }
	integration_assert_text(mut reopened, ui2.rect(0, 0, 740, 520), tr('files.trash.empty_list'))
	println('IPC Files Trash restore and guarded empty passed')
}

// Open real documents, deliver edits and exports through the native protocol,
// then inspect the result outside each child process.
fn check_new_utility_clients(mut desktop Desktop) {
	root := os.join_path(os.temp_dir(), 'vinix-utility-ipc-${os.getpid()}')
	os.mkdir(root) or { panic(err) }
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	image_path := os.join_path(root, 'image.png')
	image_export := os.join_path(root, 'rotated.png')
	image := base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAD0lEQVR4nGP4z8DwHwgbABB5A359Y87XAAAAAElFTkSuQmCC')
	os.write_file_array(image_path, image) or { panic(err) }
	preview_factory := app_factory_named('vinix-preview') or { panic('Preview is not registered') }
	mut preview := start_remote_app_at_with_timeout(arguments()[0], preview_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	preview_open := jump_open_prefix + image_path
	preview.handle(preview_open) or { panic(err) }
	preview.handle(preview_action_rotate_right) or { panic(err) }
	preview.handle(preview_action_export_path) or { panic(err) }
	if mut preview is RemoteApp { preview.paste_input(image_export) }
	preview.handle(preview_action_export_png) or { panic(err) }
	preview_tree := preview.build(ui2.rect(0, 0, 800, 576)) or { panic(err) }
	assert tree_has_id(preview_tree, preview_action_image)
	assert tree_contains_text(preview_tree, 'PNG image exported.')
	free_tree(preview_tree)
	close_remote(mut preview)
	exported_image := os.read_bytes(image_export) or { panic(err) }
	mut image_width := 0
	mut image_height := 0
	mut image_channels := 0
	assert C.stbi_info_from_memory(exported_image.data, exported_image.len, &image_width,
		&image_height, &image_channels) == 1
	assert image_width == 1 && image_height == 2

	log_path := os.join_path(root, 'application.log')
	log_export := os.join_path(root, 'matching.txt')
	os.write_file(log_path, 'alpha boot\nbeta warning\nalpha ready\n') or { panic(err) }
	console_factory := app_factory_named('vinix-console') or { panic('Console is not registered') }
	mut console := start_remote_app_at_with_timeout(arguments()[0], console_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	console_open := jump_open_prefix + log_path
	console.handle(console_open) or { panic(err) }
	console.handle('console.filter') or { panic(err) }
	if mut console is RemoteApp { console.paste_input('alpha') }
	console.handle('console.export_path') or { panic(err) }
	if mut console is RemoteApp {
		console.key_input('\x01')
		console.paste_input(log_export)
	}
	console.handle('console.export') or { panic(err) }
	console_tree := console.build(ui2.rect(0, 0, 800, 536)) or { panic(err) }
	assert tree_contains_text(console_tree, 'alpha ready')
	assert !tree_contains_text(console_tree, 'beta warning')
	free_tree(console_tree)
	close_remote(mut console)
	log_text := os.read_file(log_export) or { panic(err) }
	assert log_text == 'alpha boot\nalpha ready\n'

	report_path := os.join_path(root, 'system.txt')
	info_factory := app_factory_named('vinix-system-information') or {
		panic('System Information is not registered')
	}
	mut info := start_remote_app_at_with_timeout(arguments()[0], info_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	info.handle('system_information.path') or { panic(err) }
	if mut info is RemoteApp { info.paste_input(report_path) }
	info.handle('system_information.export') or { panic(err) }
	info_tree := info.build(ui2.rect(0, 0, 780, 516)) or { panic(err) }
	assert tree_has_id(info_tree, 'system_information.refresh')
	assert tree_contains_text(info_tree, 'Report saved'), 'System Information export: ${tree_text_dump(info_tree)}'
	free_tree(info_tree)
	close_remote(mut info)
	report := os.read_file(report_path) or { panic(err) }
	assert report.contains('System Information') && report.contains('Installed packages')
	assert report.contains('Storage') && report.contains('Hardware')
	unsafe {
		image_path.free(); image_export.free(); image.free(); preview_open.free(); exported_image.free()
		log_path.free(); log_export.free(); console_open.free(); log_text.free(); report_path.free(); report.free()
	}
}

fn storage_remote_field(mut app NativeApp, action string, text string) {
	app.handle(action) or { panic(err) }
	if mut app is RemoteApp {
		app.key_input('\x01')
		app.paste_input(text)
	}
}

fn storage_remote_wait(mut app NativeApp, size ui2.Rect, text string) {
	for _ in 0 .. 500 {
		if mut app is RemoteApp { app.poll() }
		tree := app.build(size) or { panic(err) }
		ready := tree_contains_text(tree, text)
		free_tree(tree)
		if ready { return }
		desktop_sleep_ms(10)
	}
	tree := app.build(size) or { panic(err) }
	panic('Storage utility did not finish: ${tree_text_dump(tree)}')
}

// Exercise real child-process copies and exports, including paths shortened
// through native keyboard/paste IPC. Descriptor walks intentionally reject
// symlink parents, so use the host's canonical temporary directory.
fn check_storage_utility_clients(mut desktop Desktop) {
	base := os.real_path(os.temp_dir())
	root := join_path(base, 'vinix-storage-ipc-${os.getpid()}')
	os.mkdir(root) or { panic(err) }
	defer { os.rmdir_all(root) or {}; unsafe { base.free(); root.free() } }
	source := join_path(root, 'source')
	store := join_path(root, 'backups')
	restored := join_path(root, 'restored')
	archive_path := join_path(root, 'files.tar')
	extracted := join_path(root, 'extracted')
	note := join_path(source, 'note.txt')
	restored_note := join_path(restored, 'note.txt')
	extracted_source := join_path(extracted, 'source')
	extracted_note := join_path(extracted_source, 'note.txt')
	report_path := join_path(root, 'disk-Ж.txt')
	long_report := report_path + '.long'
	defer {
		unsafe {
			source.free(); store.free(); restored.free(); archive_path.free(); extracted.free()
			note.free(); restored_note.free(); extracted_source.free(); extracted_note.free()
			report_path.free(); long_report.free()
		}
	}
	os.mkdir(source) or { panic(err) }
	os.mkdir(store) or { panic(err) }
	os.write_file(note, 'Native storage workflow 日本語\n') or { panic(err) }
	archive_factory := app_factory_named('vinix-archive') or { panic('Archive Utility is not registered') }
	mut archive := start_remote_app_at_with_timeout(arguments()[0], archive_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	storage_remote_field(mut archive, 'archive.source', source)
	storage_remote_field(mut archive, 'archive.output', archive_path)
	if mut archive is RemoteApp {
		archive.poll_hint_ms = 2000
		archive.poll_sampled = true
		archive.last_poll_ms = desktop_monotonic_ms()
	}
	archive.handle('archive.create') or { panic(err) }
	if mut archive is RemoteApp { assert !archive.poll_sampled }
	storage_remote_wait(mut archive, ui2.rect(0, 0, 800, 656), 'TAR created.')
	storage_remote_field(mut archive, 'archive.path', archive_path)
	archive.handle('archive.browse') or { panic(err) }
	storage_remote_wait(mut archive, ui2.rect(0, 0, 800, 656), 'Archive validated.')
	storage_remote_field(mut archive, 'archive.destination', extracted)
	archive.handle('archive.extract') or { panic(err) }
	storage_remote_wait(mut archive, ui2.rect(0, 0, 800, 656), 'Archive extracted.')
	close_remote(mut archive)
	extracted_text := os.read_file(extracted_note) or { panic(err) }
	assert extracted_text == 'Native storage workflow 日本語\n'
	unsafe { extracted_text.free() }

	backup_factory := app_factory_named('vinix-backup') or { panic('Backup is not registered') }
	mut backup := start_remote_app_at_with_timeout(arguments()[0], backup_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	storage_remote_field(mut backup, 'backup.source', source)
	storage_remote_field(mut backup, 'backup.store', store)
	backup.handle('backup.start') or { panic(err) }
	storage_remote_wait(mut backup, ui2.rect(0, 0, 760, 536), 'Backup completed.')
	backup.handle('backup.refresh') or { panic(err) }
	// The completed snapshot is the only version in this fresh store.
	for _ in 0 .. 30 {
		if mut backup is RemoteApp { backup.poll() }
		desktop_sleep_ms(10)
	}
	backup.handle('backup.version.0') or { panic(err) }
	storage_remote_field(mut backup, 'backup.restore_path', restored)
	backup.handle('backup.restore') or { panic(err) }
	storage_remote_wait(mut backup, ui2.rect(0, 0, 760, 536), 'Restore completed.')
	close_remote(mut backup)
	restored_text := os.read_file(restored_note) or { panic(err) }
	assert restored_text == 'Native storage workflow 日本語\n'
	unsafe { restored_text.free() }

	disk_factory := app_factory_named('vinix-disk-utility') or { panic('Disk Utility is not registered') }
	mut disk := start_remote_app_at_with_timeout(arguments()[0], disk_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	storage_remote_field(mut disk, 'disk_utility.path', long_report)
	if mut disk is RemoteApp { disk.key_input('\x7f\x7f\x7f\x7f\x7f') }
	disk.handle('disk_utility.export') or { panic(err) }
	disk_tree := disk.build(ui2.rect(0, 0, 780, 560)) or { panic(err) }
	assert tree_contains_text(disk_tree, 'Report saved'), 'Disk Utility export: ${tree_text_dump(disk_tree)}'
	free_tree(disk_tree)
	close_remote(mut disk)
	assert !os.exists(long_report)
	report := os.read_file(report_path) or { panic(err) }
	assert report.contains('Disk Utility') && report.contains('Devices') && report.contains('Volumes')
	unsafe { report.free() }
}

// Native clients receive the compositor's active user folder and reopen their
// own durable records. No test data is written into the real desktop profile.
fn check_productivity_utility_clients(mut desktop Desktop) {
	base := os.real_path(os.temp_dir())
	root := join_path(base, 'vinix-productivity-ipc-${os.getpid()}')
	os.mkdir(root) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = root
	defer {
		desktop_user_home = previous_home
		os.rmdir_all(root) or {}
		unsafe { base.free(); root.free() }
	}
	note_export := join_path(root, 'note-Ж.txt')
	task_export := join_path(root, 'tasks-Ж.csv')
	graph_export := join_path(root, 'graph-Ж.csv')
	defer { unsafe { note_export.free(); task_export.free(); graph_export.free() } }

	notes_factory := app_factory_named('vinix-notes') or { panic('Notes is not registered') }
	mut notes := start_remote_app_at_with_timeout(arguments()[0], notes_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	notes.handle('notes.new') or { panic(err) }
	storage_remote_field(mut notes, 'notes.title', 'IPC note 😀')
	storage_remote_field(mut notes, 'notes.body', 'Native note 日本語\nSecond line')
	storage_remote_wait(mut notes, ui2.rect(0, 0, 820, 576), 'Saved')
	storage_remote_field(mut notes, 'notes.export_path', note_export)
	notes.handle('notes.export') or { panic(err) }
	note_tree := notes.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_contains_text(note_tree, 'Text exported.')
	free_tree(note_tree)
	close_remote(mut notes)
	note_text := os.read_file(note_export) or { panic(err) }
	assert note_text == 'IPC note 😀\n\nNative note 日本語\nSecond line'
	unsafe { note_text.free() }
	mut reopened_notes := start_remote_app_at_with_timeout(arguments()[0], notes_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	reloaded_notes := reopened_notes.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_contains_text(reloaded_notes, 'IPC note 😀')
	assert tree_contains_text(reloaded_notes, 'Native note 日本語')
	free_tree(reloaded_notes)
	check_notes_close_client(mut reopened_notes, notes_factory, mut desktop)
	check_color_meter_client()

	reminders_factory := app_factory_named('vinix-reminders') or { panic('Reminders is not registered') }
	mut reminders := start_remote_app_at_with_timeout(arguments()[0], reminders_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	reminders.handle('reminders.new') or { panic(err) }
	storage_remote_field(mut reminders, 'reminders.title', 'IPC task 日本語')
	storage_remote_field(mut reminders, 'reminders.due', '2000-02-29 12:30')
	reminders.handle('reminders.save') or { panic(err) }
	task_tree := reminders.build(ui2.rect(0, 0, 800, 616)) or { panic(err) }
	assert tree_contains_text(task_tree, 'Tasks saved.')
	free_tree(task_tree)
	reminders.handle('reminders.toggle') or { panic(err) }
	reminders.handle('reminders.filter.completed') or { panic(err) }
	storage_remote_field(mut reminders, 'reminders.export_path', task_export)
	reminders.handle('reminders.export_csv') or { panic(err) }
	export_tree := reminders.build(ui2.rect(0, 0, 800, 616)) or { panic(err) }
	assert tree_contains_text(export_tree, 'Export saved.')
	free_tree(export_tree)
	close_remote(mut reminders)
	task_text := os.read_file(task_export) or { panic(err) }
	assert task_text.contains('IPC task 日本語') && task_text.contains('2000-02-29 12:30')
	unsafe { task_text.free() }
	mut reopened_tasks := start_remote_app_at_with_timeout(arguments()[0], reminders_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	reopened_tasks.handle('reminders.filter.completed') or { panic(err) }
	reloaded_tasks := reopened_tasks.build(ui2.rect(0, 0, 800, 616)) or { panic(err) }
	assert tree_contains_text(reloaded_tasks, 'IPC task 日本語')
	free_tree(reloaded_tasks)
	close_remote(mut reopened_tasks)

	grapher_factory := app_factory_named('vinix-grapher') or { panic('Grapher is not registered') }
	mut grapher := start_remote_app_at_with_timeout(arguments()[0], grapher_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	storage_remote_field(mut grapher, 'grapher.expression', 'sqrt(x)')
	grapher.handle('grapher.plot') or { panic(err) }
	graph_tree := grapher.build(ui2.rect(0, 0, 840, 636)) or { panic(err) }
	assert tree_has_id(graph_tree, 'grapher.chart')
	assert tree_contains_text(graph_tree, 'Plotted with gaps')
	free_tree(graph_tree)
	storage_remote_field(mut grapher, 'grapher.path', graph_export)
	grapher.handle('grapher.export') or { panic(err) }
	graph_text := os.read_file(graph_export) or { panic(err) }
	assert graph_text.starts_with('x,y\n-10,\n')
	assert graph_text.contains('\n0,0\n')
	grapher.handle('grapher.export') or { panic(err) }
	existing_tree := grapher.build(ui2.rect(0, 0, 840, 636)) or { panic(err) }
	assert tree_contains_text(existing_tree, 'That destination already exists.')
	free_tree(existing_tree)
	unchanged_graph := os.read_file(graph_export) or { panic(err) }
	assert unchanged_graph == graph_text
	unsafe { graph_text.free(); unchanged_graph.free() }
	close_remote(mut grapher)
}

fn integration_tree_text(element ui2.Element, id string) ?string {
	if element.id == id { return element.text }
	for child in element.children {
		if text := integration_tree_text(child, id) { return text }
	}
	return none
}

fn integration_calculator_display(mut app NativeApp, expected string) {
	tree := app.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
	value := integration_tree_text(tree, 'display') or { panic('missing Calculator display') }
	assert value == expected, 'Calculator displayed ${value}, expected ${expected}'
	free_tree(tree)
}

// Scientific controls, typed operators, pasted numeric operands and resize all
// cross the same pipes as the installed multicall Calculator executable.
fn check_scientific_calculator_client(mut desktop Desktop) {
	factory := app_factory_named('vinix-calculator') or { panic('Calculator is not registered') }
	mut calculator := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut calculator) }
	basic := calculator.build(ui2.rect(0, 0, 340, 516)) or { panic(err) }
	assert tree_has_id(basic, 'calculator.mode.scientific')
	assert !tree_has_id(basic, 'calculator.scientific.sqrt')
	free_tree(basic)
	calculator.handle('calculator.mode.scientific') or { panic(err) }
	if mut calculator is RemoteApp {
		assert calculator.pid > 0 && calculator.keyboard
		calculator.paste_input('9')
	}
	calculator.handle('calculator.scientific.sqrt') or { panic(err) }
	integration_calculator_display(mut calculator, '3')
	calculator.handle('calculator.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, '3')
	integration_assert_text(mut calculator, ui2.rect(0, 0, 620, 576), tr('clipboard.copy.copied'))
	calculator.handle('calculator.scientific.cube') or { panic(err) }
	integration_calculator_display(mut calculator, '27')
	calculator.handle('calculator.scientific.cbrt') or { panic(err) }
	integration_calculator_display(mut calculator, '3')
	calculator.handle('C') or { panic(err) }
	if mut calculator is RemoteApp { calculator.paste_input('8') }
	calculator.handle('calculator.scientific.log2') or { panic(err) }
	integration_calculator_display(mut calculator, '3')
	calculator.handle('C') or { panic(err) }
	if mut calculator is RemoteApp {
		calculator.key_input('2+')
		calculator.paste_input('9')
	}
	calculator.handle('calculator.scientific.sqrt') or { panic(err) }
	calculator.handle('=') or { panic(err) }
	integration_calculator_display(mut calculator, '5')
	calculator.handle('C') or { panic(err) }
	calculator.handle('calculator.angle.degrees') or { panic(err) }
	if mut calculator is RemoteApp { calculator.paste_input('30') }
	calculator.handle('calculator.scientific.sin') or { panic(err) }
	integration_calculator_display(mut calculator, '0.5')
	calculator.handle('C') or { panic(err) }
	calculator.handle('calculator.angle.radians') or { panic(err) }
	if mut calculator is RemoteApp { calculator.paste_input('1.5707963267948966') }
	calculator.handle('calculator.scientific.cos') or { panic(err) }
	radians := calculator.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
	cosine := integration_tree_text(radians, 'display') or { panic('missing radians result') }
	assert math.abs(cosine.f64()) < 1e-12
	assert tree_has_id(radians, 'calculator.angle.radians')
	free_tree(radians)
	calculator.handle('C') or { panic(err) }
	if mut calculator is RemoteApp { calculator.paste_input('1e3') }
	calculator.handle('calculator.scientific.reciprocal') or { panic(err) }
	integration_calculator_display(mut calculator, '0.001')
	calculator.handle('C') or { panic(err) }
	if mut calculator is RemoteApp { calculator.paste_input('-1') }
	calculator.handle('calculator.scientific.sqrt') or { panic(err) }
	domain := calculator.build(ui2.rect(0, 0, 620, 576)) or { panic(err) }
	domain_display := integration_tree_text(domain, 'display') or { panic('missing error display') }
	assert domain_display == tr('calculator.error')
	assert tree_contains_text(domain, tr('calculator.error.domain'))
	free_tree(domain)
	calculator.handle('calculator.copy') or { panic(err) }
	integration_assert_clipboard(&desktop, '3')
	integration_assert_text(mut calculator, ui2.rect(0, 0, 620, 576), tr('clipboard.copy.empty'))
	calculator.handle('C') or { panic(err) }
	if mut calculator is RemoteApp { calculator.paste_input('25') }
	calculator.handle('calculator.scientific.sqrt') or { panic(err) }
	integration_calculator_display(mut calculator, '5')
	narrow := calculator.build(ui2.rect(0, 0, 340, 516)) or { panic(err) }
	assert tree_contains_text(narrow, tr('calculator.scientific.resize'))
	assert !tree_has_id(narrow, 'calculator.scientific.sqrt')
	free_tree(narrow)
	calculator.handle('calculator.mode.basic') or { panic(err) }
	restored := calculator.build(ui2.rect(0, 0, 340, 516)) or { panic(err) }
	assert tree_has_id(restored, '5') && tree_has_id(restored, 'display')
	assert !tree_has_id(restored, 'calculator.scientific.sqrt')
	free_tree(restored)
	assert native_app_prepare_close(mut calculator)
	println('IPC scientific Calculator passed')
}

// An invalid draft must survive a real prepare-close request. Repair saves it;
// the separate two-step discard only abandons the subsequent unsaved edit.
fn check_notes_close_client(mut notes NativeApp, factory AppFactory, mut desktop Desktop) {
	notes.handle('notes.title') or { panic(err) }
	mut pid := -1
	if mut notes is RemoteApp {
		pid = notes.pid
		assert notes.peer_features & app_feature_close_guard != 0
		notes.key_input('\x01\x7f')
	}
	assert pid > 0
	assert !native_app_prepare_close(mut notes)
	if mut notes is RemoteApp {
		assert !notes.closed && notes.pid == pid
		assert C.fcntl(notes.request_fd, C.F_GETFD) >= 0
		assert C.fcntl(notes.response_fd, C.F_GETFD) >= 0
	}
	assert C.kill(pid, 0) == 0
	refused := notes.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_has_id(refused, 'notes.keep_editing') && tree_has_id(refused, 'notes.discard')
	assert !tree_has_id(refused, 'notes.confirm_discard')
	assert tree_contains_text(refused, 'Native note 日本語')
	free_tree(refused)
	notes.handle('notes.keep_editing') or { panic(err) }
	storage_remote_field(mut notes, 'notes.title', 'IPC repaired note 😀')
	assert native_app_prepare_close(mut notes)
	close_remote(mut notes)

	mut discard := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut discard) }
	repaired := discard.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_contains_text(repaired, 'IPC repaired note 😀')
	assert tree_contains_text(repaired, 'Native note 日本語')
	free_tree(repaired)
	storage_remote_field(mut discard, 'notes.title', '')
	if mut discard is RemoteApp { discard.key_input('\x7f') }
	storage_remote_field(mut discard, 'notes.body', 'Discarded IPC text 日本語')
	assert !native_app_prepare_close(mut discard)
	// Confirm without the explicit first step cannot authorize closing.
	discard.handle('notes.confirm_discard') or { panic(err) }
	assert !native_app_prepare_close(mut discard)
	discard.handle('notes.discard') or { panic(err) }
	confirmation := discard.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_has_id(confirmation, 'notes.confirm_discard')
	assert tree_contains_text(confirmation, 'Discarded IPC text 日本語')
	free_tree(confirmation)
	discard.handle('notes.confirm_discard') or { panic(err) }
	assert native_app_prepare_close(mut discard)
	close_remote(mut discard)
	mut durable := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut durable) }
	unchanged := durable.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_contains_text(unchanged, 'IPC repaired note 😀')
	assert tree_contains_text(unchanged, 'Native note 日本語')
	assert !tree_contains_text(unchanged, 'Discarded IPC text 日本語')
	free_tree(unchanged)
	println('IPC Notes close guard passed')
}

fn integration_session_paste(mut desktop Desktop, mut recipient NativeApp, chord string) {
	recipient.handle('notes.body') or { panic(err) }
	if mut recipient is RemoteApp { recipient.key_input('\x01') }
	rest := desktop.take_paste_keys(chord)
	assert rest.len == 0
	unsafe { rest.free() }
	assert desktop.clipboard.pid == -1 && desktop.clipboard.fd == -1
}

// Only the compositor owns these pixels. Samples, pointer updates and copy
// requests traverse a live child, and its copied text pastes into another one.
fn check_color_meter_client() {
	factory := app_factory_named('vinix-color-meter') or { panic('Color Meter is not registered') }
	assert factory.desktop_services && factory.polling && factory.poll_interval_ms == 100
	mut desktop := Desktop{
		home: desktop_user_home
		canvas: new_scaled_canvas(16, 12, 32, 24, 2)
		pointer_x: 4
		pointer_y: 3
	}
	pixels := desktop.canvas.pixels
	defer {
		desktop.clipboard.close_request()
		unsafe {
			free(pixels)
			desktop.cursor_backing.pixels.free()
			desktop.apps.free(); desktop.windows.free(); desktop.native_asset_icons.free()
			desktop.clipboard.url.free(); desktop.clipboard.pending.free(); desktop.clipboard.data.free()
		}
	}
	for index in 0 .. 32 * 24 { unsafe { pixels[index] = 0x112233 } }
	unsafe { pixels[5 * 32 + 4] = 0x123456 }
	mut meter := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut meter) }
	storage_remote_field(mut meter, 'color_meter.x', '4')
	storage_remote_field(mut meter, 'color_meter.y', '5')
	meter.handle('color_meter.sample') or { panic(err) }
	if mut meter is RemoteApp {
		assert meter.pid > 0 && meter.peer_features & app_feature_desktop_services != 0
		assert meter.color_sample.status == .sampled && meter.color_sample.rgb == 0x123456
		assert meter.color_sample.width == 32 && meter.color_sample.height == 24
		assert meter.color_sample.x == 4 && meter.color_sample.y == 5 && meter.color_sample.count == 1
	}
	sample := meter.build(ui2.rect(0, 0, 620, 516)) or { panic(err) }
	assert tree_has_id(sample, 'color_meter.magnifier') && tree_has_id(sample, 'color_meter.copy_hex')
	assert tree_contains_text(sample, '#123456') && tree_contains_text(sample, 'rgb(18, 52, 86)')
	free_tree(sample)
	meter.handle('color_meter.aperture.3') or { panic(err) }
	if mut meter is RemoteApp { assert meter.color_sample.count == 9 && meter.color_sample.rgb == 0x112437 }
	meter.handle('color_meter.aperture.1') or { panic(err) }

	notes_factory := app_factory_named('vinix-notes') or { panic('Notes is not registered') }
	mut recipient := start_remote_app_at_with_timeout(arguments()[0], notes_factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { close_remote(mut recipient) }
	recipient.handle('notes.new') or { panic(err) }
	storage_remote_field(mut recipient, 'notes.title', 'IPC clipboard note')
	desktop.apps << recipient
	desktop.windows << Window{ id: 9100, title: 'Notes', page: .app, app_index: 0 }
	desktop.focus = 9100
	meter.handle('color_meter.copy_hex') or { panic(err) }
	assert desktop.clipboard.local_available
	assert unsafe { tos(&desktop.clipboard.local_bytes[0], desktop.clipboard.local_length) } == '#123456'
	integration_session_paste(mut desktop, mut recipient, key_cmd_v)
	hex_pasted := recipient.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_contains_text(hex_pasted, '#123456')
	free_tree(hex_pasted)
	meter.handle('color_meter.copy_rgb') or { panic(err) }
	assert unsafe { tos(&desktop.clipboard.local_bytes[0], desktop.clipboard.local_length) } == 'rgb(18, 52, 86)'
	integration_session_paste(mut desktop, mut recipient, '\x16')
	rgb_pasted := recipient.build(ui2.rect(0, 0, 820, 576)) or { panic(err) }
	assert tree_contains_text(rgb_pasted, 'rgb(18, 52, 86)') && !tree_contains_text(rgb_pasted, '#123456')
	free_tree(rgb_pasted)
	assert native_app_prepare_close(mut recipient)
	close_remote(mut recipient)

	// The cursor's painted white pixel is excluded through its saved backing;
	// logical pointer coordinates select the centre of the physical HiDPI cell.
	unsafe { pixels[7 * 32 + 9] = 0xffffff }
	desktop.cursor_backing = CursorBacking{
		box: DamageRect{ x: 4, y: 3, w: 1, h: 1, valid: true }
		pixels: [u32(0xabcdef), 0xabcdef, 0xabcdef, 0xabcdef]
	}
	meter.handle('color_meter.live') or { panic(err) }
	if mut meter is RemoteApp {
		assert meter.color_sample.x == 9 && meter.color_sample.y == 7 && meter.color_sample.rgb == 0xabcdef
		assert !meter.poll()
		assert meter.poll_sampled && meter.next_poll_interval() == 100
		sequence := meter.color_sample.sequence
		desktop.cursor_backing.pixels[3] = 0xfedcba
		meter.last_poll_ms = desktop_monotonic_ms()
		assert !meter.poll()
		assert meter.color_sample.sequence == sequence && meter.color_sample.rgb == 0xabcdef
		meter.last_poll_ms = desktop_monotonic_ms() - 100
		assert meter.poll()
		assert meter.color_sample.rgb == 0xfedcba && meter.color_sample.sequence > sequence
	}
	live := meter.build(ui2.rect(0, 0, 620, 516)) or { panic(err) }
	assert tree_contains_text(live, '#FEDCBA')
	assert tree_contains_text(live, tr('color_meter.live_status'))
	free_tree(live)
	meter.handle('color_meter.freeze') or { panic(err) }
	desktop.cursor_backing.pixels[3] = 0x090807
	if mut meter is RemoteApp {
		sequence := meter.color_sample.sequence
		assert !meter.poll()
		assert meter.color_sample.sequence == sequence && meter.color_sample.rgb == 0xfedcba
		assert meter.next_poll_interval() == 1000
	}
	frozen := meter.build(ui2.rect(0, 0, 620, 516)) or { panic(err) }
	assert tree_contains_text(frozen, '#FEDCBA') && tree_contains_text(frozen, tr('color_meter.frozen'))
	free_tree(frozen)
	// Physical X remains9 while the other axis follows a2x pointer. Both
	// locks then hold9,9; releasing X resumes only that axis's live position.
	meter.handle('color_meter.lock_x') or { panic(err) }
	desktop.pointer_x = 11
	desktop.pointer_y = 4
	unsafe { pixels[9 * 32 + 9] = 0x2468ac; pixels[9 * 32 + 27] = 0x987654 }
	meter.handle('color_meter.live') or { panic(err) }
	if mut meter is RemoteApp {
		assert meter.color_sample.x == 9 && meter.color_sample.y == 9 && meter.color_sample.rgb == 0x2468ac
	}
	meter.handle('color_meter.lock_y') or { panic(err) }
	desktop.pointer_x = 13
	desktop.pointer_y = 6
	if mut meter is RemoteApp {
		meter.last_poll_ms = 0
		meter.poll()
		assert meter.color_sample.x == 9 && meter.color_sample.y == 9 && meter.color_sample.rgb == 0x2468ac
	}
	meter.handle('color_meter.lock_x') or { panic(err) }
	if mut meter is RemoteApp {
		assert meter.color_sample.x == 27 && meter.color_sample.y == 9 && meter.color_sample.rgb == 0x987654
	}
	meter.handle('color_meter.freeze') or { panic(err) }
	meter.handle('color_meter.lock_y') or { panic(err) }

	desktop.canvas.pixels = unsafe { nil }
	meter.handle('color_meter.sample') or { panic(err) }
	if mut meter is RemoteApp {
		assert meter.color_sample.status == .unavailable && meter.color_sample.count == 0
		assert !meter.closed
	}
	unavailable := meter.build(ui2.rect(0, 0, 620, 516)) or { panic(err) }
	assert tree_contains_text(unavailable, tr('color_meter.unavailable'))
	assert !tree_contains_text(unavailable, '#FEDCBA')
	assert !tree_contains_text(unavailable, '#987654')
	free_tree(unavailable)
	meter.handle('color_meter.copy_hex') or { panic(err) }
	assert unsafe { tos(&desktop.clipboard.local_bytes[0], desktop.clipboard.local_length) } == 'rgb(18, 52, 86)'
	desktop.canvas.pixels = pixels
	println('IPC Color Meter sampling, clipboard and polling passed')
}
