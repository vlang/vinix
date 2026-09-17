// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn clock_test_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		found := clock_test_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_taskbar_clock_formats_24_and_12_hour_time() {
	mut desktop := Desktop{}
	// 1970-01-01 13:05:09 UTC.
	seconds := i64(47_109)
	time_24, date_24 := desktop.taskbar_clock_strings_at(seconds)
	assert time_24 == '13:05:09'
	assert date_24 == 'Thu 1 Jan'

	desktop.settings.clock_show_seconds = false
	time_no_seconds, _ := desktop.taskbar_clock_strings_at(seconds)
	assert time_no_seconds == '13:05'

	desktop.settings.clock_24_hour = false
	time_12, _ := desktop.taskbar_clock_strings_at(seconds)
	assert time_12 == '1:05 PM'

	desktop.settings.clock_show_seconds = true
	time_12_seconds, _ := desktop.taskbar_clock_strings_at(seconds)
	assert time_12_seconds == '1:05:09 PM'
	midnight, _ := desktop.taskbar_clock_strings_at(0)
	assert midnight == '12:00:00 AM'
	noon, _ := desktop.taskbar_clock_strings_at(43_200)
	assert noon == '12:00:00 PM'
}

fn test_date_time_settings_controls_update_desktop_preferences() {
	mut desktop := Desktop{}
	mut app := SettingsApp{
		desktop: &desktop
		category: .date_time
	}
	assert SettingsCategory.date_time.title() == 'Date & Time'
	assert settings_categories.index(SettingsCategory.date_time) >= 0

	mut root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	format_24 := clock_test_element(root, '${settings_action_clock_format}0') or {
		panic('missing 24-hour clock choice')
	}
	seconds_show := clock_test_element(root, '${settings_action_clock_seconds}0') or {
		panic('missing show-seconds choice')
	}
	assert format_24.box.bg == app_accent
	assert seconds_show.box.bg == app_accent

	app.handle('${settings_action_clock_format}1') or { panic(err) }
	app.handle('${settings_action_clock_seconds}1') or { panic(err) }
	assert !desktop.settings.clock_24_hour
	assert !desktop.settings.clock_show_seconds

	root = app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	format_12 := clock_test_element(root, '${settings_action_clock_format}1') or {
		panic('missing 12-hour clock choice')
	}
	seconds_hide := clock_test_element(root, '${settings_action_clock_seconds}1') or {
		panic('missing hide-seconds choice')
	}
	assert format_12.box.bg == app_accent
	assert seconds_hide.box.bg == app_accent
}

fn test_date_time_settings_actions_save_and_restore() {
	home := os.join_path(os.temp_dir(), 'vinix-clock-settings-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	defer { os.rmdir_all(home) or {} }
	mut preferences := desktop_load_preferences(home)
	previous_scale := preferences.configure_scale(1920, 1080)
	mut desktop := Desktop{
		settings: preferences.settings
	}
	mut app := SettingsApp{
		desktop: &desktop
		category: .date_time
	}
	app.handle('${settings_action_clock_format}1') or { panic(err) }
	app.handle('${settings_action_clock_seconds}1') or { panic(err) }
	assert preferences.save_changes(desktop.settings, previous_scale, home)
	restored := desktop_load_preferences(home)
	assert !restored.settings.clock_24_hour
	assert !restored.settings.clock_show_seconds
	assert restored.scale == 0
}

fn test_clock_preferences_cross_app_wire_state() {
	state := AppWireState{
		settings: Settings{
			clock_24_hour: false
			clock_show_seconds: false
		}
		requested_scale: desktop_scale_100
	}
	mut encoded := []u8{}
	wire_put_state(mut encoded, state)
	mut reader := WireReader{ data: encoded }
	decoded := wire_take_state(mut reader) or { panic(err) }
	assert reader.index == encoded.len
	assert !decoded.settings.clock_24_hour
	assert !decoded.settings.clock_show_seconds
	assert decoded.requested_scale == desktop_scale_100
}
