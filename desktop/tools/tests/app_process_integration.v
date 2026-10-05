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
	check_new_utility_clients(mut desktop)
	check_storage_utility_clients(mut desktop)
	desktop_restore_requested_scale()
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
