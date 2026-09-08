// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

import os
import ui2

fn utility_tree_has_text(element ui2.Element, text string) bool {
	if element.text == text {
		return true
	}
	for child in element.children {
		if utility_tree_has_text(child, text) {
			return true
		}
	}
	return false
}

fn utility_element_named(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		found := utility_element_named(child, id) or { continue }
		return found
	}
	return none
}

fn test_text_editor_inserts_and_navigates() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.key_input('hello\nworld')
	assert editor_bytes_text(editor.text) == 'hello\nworld'
	assert editor.cursor == editor.text.len

	// Up preserves the column, insertion happens at the cursor, then Home and
	// Delete edit in place rather than reducing the editor to an append box.
	editor.key_input('\x1b[A!')
	assert editor_bytes_text(editor.text) == 'hello!\nworld'
	assert editor.cursor == 6
	editor.key_input('\x1b[H\x1b[C\x1b[3~')
	assert editor_bytes_text(editor.text) == 'hllo!\nworld'
	assert editor.modified

	editor.key_input('\x0e')
	assert editor.text.len == 0
	assert editor_bytes_text(editor.path) == editor_default_path
	assert !editor.modified
}

fn test_text_editor_saves_and_opens_a_real_file() {
	path := os.join_path(os.temp_dir(), 'vinix-desktop-editor-test.txt')
	mut writer := TextEditorApp{}
	writer.set_path(path)
	writer.key_input('Vinix utilities\nwork.')
	writer.save_document()
	assert !writer.modified
	assert editor_bytes_text(writer.status).starts_with('Saved ')

	mut reader := TextEditorApp{}
	reader.set_path(path)
	reader.open_document()
	assert editor_bytes_text(reader.text) == 'Vinix utilities\nwork.'
	assert reader.cursor == reader.text.len
	assert !reader.modified
	os.rm(path) or {}
}

fn test_calendar_arithmetic_and_navigation() {
	assert calendar_is_leap_year(2000)
	assert !calendar_is_leap_year(1900)
	assert calendar_days_in_month(2024, 2) == 29
	assert calendar_days_in_month(2025, 2) == 28
	assert calendar_weekday(1970, 1, 1) == 4
	assert calendar_weekday(2026, 9, 7) == 1

	mut calendar := CalendarApp{
		year: 2024
		month: 1
		selected_day: 31
	}
	calendar.refresh_labels()
	calendar.change_month(1)
	assert calendar.year == 2024
	assert calendar.month == 2
	assert calendar.selected_day == 29
	calendar.change_month(-2)
	assert calendar.year == 2023
	assert calendar.month == 12
}

fn test_clock_stopwatch_format_and_elapsed_time() {
	assert clock_stopwatch_text(0) == '00:00:00.0'
	assert clock_stopwatch_text(3_726_599) == '01:02:06.5'
	clock := ClockApp{
		running: true
		started_ms: 1_000
		accumulated_ms: 250
	}
	assert clock.elapsed(2_500) == 1_750
}

fn test_terminal_sends_every_keystroke_through_the_pty_master() {
	mut input_pipe := [2]int{}
	assert C.pipe(&input_pipe[0]) == 0
	mut terminal := TerminalApp{
		terminal: input_pipe[1]
	}

	// There is no private prompt state or local line buffering: type-ahead and
	// control characters belong to the tty line discipline. Backspace is
	// normalized to the default VERASE byte.
	terminal.key_input('ab\b\n\x03')
	mut sent := []u8{len: 8}
	count := C.read(input_pipe[0], sent.data, sent.len)
	assert count == 5
	assert sent[..count] == [u8(`a`), `b`, 0x7f, `\n`, 0x03]
	assert terminal.lines.len == 0

	C.close(input_pipe[0])
	C.close(input_pipe[1])
}

fn test_terminal_renders_pty_echo_and_carriage_return_updates() {
	mut terminal := TerminalApp{}
	terminal.ingest_output('progress 10%\rprogress 20%\r\n\$ '.bytes())
	assert terminal.lines == ['progress 20%']
	assert terminal.partial.bytestr() == '\$ '
	assert terminal.partial_text == '\$ _'

	// Canonical erase echo is backspace-space-backspace. Interpret it as cursor
	// movement and overwrite, just as a terminal display does.
	terminal.ingest_output('abc\b \bD'.bytes())
	assert terminal.partial.bytestr() == '\$ abD'

	// BusyBox's line editor emits clear-to-end even under TERM=dumb, and an
	// escape sequence may straddle two non-blocking reads.
	terminal.ingest_output('\x1b['.bytes())
	terminal.ingest_output('J'.bytes())
	assert terminal.partial.bytestr() == '\$ abD'
}

fn test_utility_launchers_fit_macbook_and_fallback_layouts() {
	assert available_apps.len == 12
	assert available_apps[0].process_name == 'vinix-files'
	assert available_apps[1].title == 'Firefox'
	assert available_apps[1].exclusive_command == '/usr/bin/run-firefox'
	assert available_apps[1].process_name == ''
	assert available_apps[3].process_name == 'vinix-terminal'
	assert available_apps[3].keyboard && available_apps[3].polling
	assert available_apps[5].title == 'Activity Monitor'
	assert available_apps[5].process_name == 'vinix-activity'
	assert available_apps[9].process_name == 'vinix-cocoa-calculator'
	assert available_apps[10].title == 'Minecraft'
	assert available_apps[10].exclusive_command == '/usr/bin/minecraft'
	assert available_apps[11].title == 'Wine Calculator'
	assert available_apps[11].process_name == 'vinix-wine-calculator'
	assert available_apps[11].keyboard && available_apps[11].polling
	assert available_apps[11].pointer
	assert app_launcher_actions.len == available_apps.len
	assert app_shortcut_actions.len == available_apps.len
	assert taskbar_launcher_width(1280, 114, available_apps.len) == 63
	assert taskbar_launcher_width(1152, 114, available_apps.len) == 53
	assert taskbar_launcher_width(1024, 114, available_apps.len) == 42
	assert shortcut_rows_for_height(720) == 8
	assert shortcut_rows_for_height(600) == 6
}

fn test_show_desktop_button_minimizes_every_window() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 1280
			height: 720
		}
	}
	first := desktop.spawn('One', .welcome, 10, 10, 300, 200)
	desktop.spawn('Two', .system, 20, 20, 300, 200)
	desktop.minimize(first)
	desktop.dirty = false

	root := desktop.build_tree()
	button := utility_element_named(root, action_show_desktop) or {
		panic('missing Show desktop button')
	}
	assert int(button.frame.x) == 1280 - show_desktop_button_width
	assert int(button.frame.y) == 720 - taskbar_height
	assert int(button.frame.width) == show_desktop_button_width
	assert int(button.frame.height) == taskbar_height
	free_tree(root)

	desktop.targets << HitTarget{
		action_id: action_show_desktop
		x: 1280 - show_desktop_button_width
		y: 720 - taskbar_height
		width: show_desktop_button_width
		height: taskbar_height
	}
	desktop.on_pointer_down(1279, 719)
	assert desktop.visible_window_count() == 0
	assert desktop.focus == 0
	assert desktop.dirty
}

fn test_firefox_requests_an_exclusive_display_handoff() {
	mut desktop := Desktop{}
	desktop.launch(available_apps[1])
	assert desktop.pending_external == '/usr/bin/run-firefox'
	assert desktop.pending_external_title == 'Firefox'
	assert desktop.pending_external_icon == 'builtin:browser'
	assert desktop.apps.len == 0
	assert desktop.windows.len == 0
}

fn test_external_display_handoff_redraws_and_reports_failures() {
	mut desktop := Desktop{
		canvas: new_canvas(800, 600)
	}
	desktop.wallpaper_valid = true
	desktop.external_finished(.success)
	assert desktop.dirty
	assert !desktop.wallpaper_valid
	assert desktop.windows.len == 0

	desktop.external_finished(.unavailable)
	assert desktop.windows.len == 1
	assert desktop.windows[0].title == 'External application'
	assert desktop.windows[0].page == .external_error
	assert desktop.external_error.contains('not installed')
	assert desktop.external_error_title == 'External application could not start'

	// The same handoff reports Minecraft rather than reusing Firefox-specific
	// text and preserves the voxel icon on its error window.
	desktop.launch(available_apps[10])
	desktop.external_finished(.failed)
	assert desktop.windows[1].title == 'Minecraft'
	assert desktop.windows[1].icon == 'builtin:block'
	assert desktop.external_error_title == 'Minecraft could not start'
	assert desktop.external_error_hint.contains('build-minecraft-aarch64.sh')
	unsafe { free(voidptr(desktop.canvas.pixels)) }
}

fn test_activity_monitor_uses_only_real_process_rows() {
	mut app := ActivityApp{}
	tree := app.build(ui2.rect(0, 0, 520, 360))!
	assert utility_tree_has_text(tree, 'MB')
	free_tree(tree)
	app.monitor.free_rows()
}

fn test_native_process_names_are_presented_as_app_names() {
	mut sample := ActivitySample{}
	name := '/usr/bin/vinix-activity[42]'
	for index := 0; index < name.len; index++ {
		sample.name[index] = name[index]
	}
	display := activity_name_of(&sample)
	assert display == 'Activity Monitor'
	unsafe { display.free() }
}

fn test_application_tree_protocol_round_trip() {
	child := ui2.button_with_image('save', 'Save', 'builtin:editor', ui2.rect(7, 9, 80, 24), ui2.BoxStyle{
		bg: 0x123456
		radius: 6
	}, ui2.TextStyle{
		color: 0xfefefe
		background_color: 0x010203
		size: 13
		font_family: 'mono'
		bold: true
		shadow: true
		align: .center
	})
	root := ui2.screen(0xabcdef, [child])
	mut encoded := []u8{}
	encode_app_element(root, mut encoded)!
	decoded := decode_app_tree(encoded)!
	assert decoded.box.bg == 0xabcdef
	assert decoded.children.len == 1
	button := decoded.children[0]
	assert button.kind == .button
	assert button.id == 'save'
	assert button.text == 'Save'
	assert button.image_path == 'builtin:editor'
	assert button.frame.x == 7 && button.frame.y == 9
	assert button.box.bg == 0x123456 && button.box.radius == 6
	assert button.text_style.font_family == 'mono'
	assert button.text_style.bold && button.text_style.shadow
	assert button.text_style.align == .center
	free_tree(root)
	free_tree(decoded)
	unsafe { encoded.free() }
}
