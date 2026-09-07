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

fn test_utility_launchers_fit_macbook_and_fallback_layouts() {
	assert available_apps.len == 8
	assert available_apps[4].title == 'Activity Monitor'
	assert app_launcher_actions.len == available_apps.len
	assert app_shortcut_actions.len == available_apps.len
	assert taskbar_launcher_width(1280, 114, available_apps.len) == launcher_width
	assert taskbar_launcher_width(1152, 114, available_apps.len) == 82
	assert taskbar_launcher_width(1024, 114, available_apps.len) == 66
	assert shortcut_rows_for_height(720) == 8
	assert shortcut_rows_for_height(600) == 6
}

fn test_activity_monitor_includes_live_hosted_apps() {
	mut desktop := Desktop{}
	desktop.spawn('Welcome', .welcome, 0, 0, 100, 100)
	calculator_id := desktop.spawn('Calculator', .app, 0, 0, 100, 100)
	desktop.spawn('Text Editor', .app, 0, 0, 100, 100)

	mut monitor := ActivityMonitor{}
	assert monitor.sync_open_apps(desktop)
	assert !monitor.sync_open_apps(desktop)
	assert monitor.app_count == 2
	assert monitor.rows.any(it.is_app && it.name == 'Calculator')
	assert monitor.rows.any(it.is_app && it.name == 'Text Editor')
	assert !monitor.rows.any(it.is_app && it.name == 'Welcome')

	desktop.close_window(calculator_id)
	assert monitor.sync_open_apps(desktop)
	assert monitor.app_count == 1
	assert !monitor.rows.any(it.is_app && it.name == 'Calculator')
	assert monitor.rows.any(it.is_app && it.name == 'Text Editor')
}

fn test_activity_monitor_uses_only_the_window_title_as_its_heading() {
	mut desktop := Desktop{}
	desktop.spawn('Calculator', .app, 0, 0, 100, 100)
	mut app := ActivityApp{
		desktop: &desktop
	}
	tree := app.build(ui2.rect(0, 0, 520, 360))!
	assert utility_tree_has_text(tree, 'Calculator')
	assert !utility_tree_has_text(tree, 'Activity Monitor')
	assert !utility_tree_has_text(tree, 'PROCESS / OPEN APP')
	assert utility_tree_has_text(tree, 'MB')
	free_tree(tree)
	app.monitor.free_rows()
}
