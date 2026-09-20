// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Standalone host integration test for the compositor/application process
// boundary. The parent execs this same binary in app mode, exactly as the
// installed per-app symlinks do on Vinix.
module main

import os
import ui2

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
	desktop_ignore_broken_pipe()

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
	// A cold persistent home can make Files' initial directory scan slower
	// than a normal interaction. Boot-started apps get that larger budget;
	// requests after startup still fail promptly through the timeout above.
	assert app_startup_response_timeout_ms > app_response_timeout_ms

	// Remote polling is paced before a pipe request is sent. Terminal keeps a
	// short fallback cadence because its PTY echo can arrive just after the
	// immediate poll forced by a keystroke. Activity Monitor can remain slow.
	assert available_apps[3].poll_interval_ms == 100
	assert available_apps[5].poll_interval_ms == 1000
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

	mut desktop := Desktop{}
	mut files := start_remote_app_at(arguments()[0], available_apps[0], mut desktop) or {
		panic(err)
	}
	if mut files is RemoteApp {
		assert files.pid > 0
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
	mut crashing_files := start_remote_app_at(arguments()[0], available_apps[0], mut desktop) or {
		panic(err)
	}
	mut crashed_pid := -1
	if mut crashing_files is RemoteApp {
		crashed_pid = crashing_files.pid
	}
	assert crashed_pid > 0
	assert C.kill(crashed_pid, C.SIGKILL) == 0
	mut failure_was_isolated := false
	crashing_files.build(ui2.rect(0, 0, 460, 326)) or {
		failure_was_isolated = true
	}
	assert failure_was_isolated
	if mut crashing_files is RemoteApp {
		assert crashing_files.closed
	}

	mut settings := start_remote_app_at(arguments()[0], available_apps[4], mut desktop) or {
		panic(err)
	}
	settings.handle('${settings_action_category}1') or { panic(err) }
	settings.handle('${settings_action_theme}1') or { panic(err) }
	assert desktop.settings.theme == .macos
	settings.handle('${settings_action_category}4') or { panic(err) }
	settings.handle(settings_scale_200_action) or { panic(err) }
	assert desktop_requested_scale() == desktop_scale_200
	settings_tree := settings.build(ui2.rect(0, 0, 620, 386)) or { panic(err) }
	assert settings_tree.kind == .screen
	assert tree_has_id(settings_tree, settings_scale_100_action)
	assert tree_has_native_button(settings_tree, settings_scale_100_action, false)
	assert tree_has_native_button(settings_tree, settings_scale_200_action, true)
	free_tree(settings_tree)
	close_remote(mut settings)

	mut capture := start_remote_app_at(arguments()[0], available_apps[14], mut desktop) or {
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
	mut terminal := start_remote_app_at(arguments()[0], available_apps[3], mut desktop) or {
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
	desktop_restore_requested_scale()
}
