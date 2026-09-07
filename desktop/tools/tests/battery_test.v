// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module main

import ui2

// Runs alongside settings_test.v against the real Settings/Battery UI code.
// Battery is a category of the desktop's one Settings application now, so the
// page is chosen through the shared sidebar rather than by an id of its own.
__global (
	battery_fixture_value   int
	battery_fixture_forces  int
	battery_fixture_now_ms  u64
	battery_fixture_history BatteryHistory
)

const battery_category_action = '${settings_action_category}${settings_categories.index(SettingsCategory.battery)}'
const display_category_action = '${settings_action_category}${settings_categories.index(SettingsCategory.display)}'

fn battery_fixture_read(force bool) int {
	if force { battery_fixture_forces++ }
	battery_fixture_history.observe(battery_fixture_now_ms, battery_fixture_value)
	return battery_fixture_value
}

fn battery_fixture_history_read() BatteryHistory {
	return battery_fixture_history
}

fn battery_fixture_app() &SettingsApp {
	mut app := fixture_app()
	app.battery_read = battery_fixture_read
	app.battery_history = battery_fixture_history_read
	battery_fixture_value = 73
	battery_fixture_forces = 0
	battery_fixture_now_ms = 0
	battery_fixture_history = BatteryHistory{}
	return app
}

fn test_battery_category_refresh_and_display_preserved() {
	mut app := battery_fixture_app()
	initial := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	element_named(initial, battery_category_action) or { panic('missing Battery category') }
	assert SettingsCategory.battery.title() == 'Battery'
	app.handle(battery_category_action) or { panic(err) }
	assert battery_fixture_forces == 1
	root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	value := element_named(root, 'settings.battery.percent') or { panic('missing percentage') }
	assert value.text == '73%'
	if _ := element_named(root, 'settings.brightness.50') {
		assert false, 'Display controls must not be active on the Battery page'
	}
	app.handle('settings.brightness.50') or { panic(err) }
	assert fixture_writes == 0
	battery_fixture_value = 42
	app.handle('settings.refresh') or { panic(err) }
	assert battery_fixture_forces == 2
	updated := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	updated_value := element_named(updated, 'settings.battery.percent') or { panic('missing percentage') }
	assert updated_value.text == '42%'
	app.handle(display_category_action) or { panic(err) }
	display := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	control := element_named(display, 'settings.brightness.50') or { panic('missing brightness') }
	assert control.enabled && fixture_writes == 0
}

fn test_battery_zero_full_and_unavailable_states() {
	mut app := battery_fixture_app()
	app.handle(battery_category_action) or { panic(err) }
	for sample in [0, 100, battery_unavailable, battery_permission, battery_invalid, battery_io,
		101] {
		battery_fixture_value = sample
		root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
		value := element_named(root, 'settings.battery.percent') or { panic('missing percentage') }
		if sample >= 0 && sample <= 100 {
			assert value.text == battery_percentage_text(sample)
		} else {
			assert value.text == 'Unavailable'
		}
		if sample == 100 {
			fill := element_named(root, 'settings.battery.fill') or { panic('missing full bar') }
			assert fill.frame.width == 455
		} else {
			if _ := element_named(root, 'settings.battery.fill') {
				assert false, 'empty/invalid samples must not have a filled bar'
			}
		}
	}
	assert fixture_writes == 0
}

fn test_battery_taskbar_labels_and_narrow_settings() {
	assert battery_clock_label(73, '18:54:22') == '73%  |  18:54:22'
	assert battery_clock_label(0, '00:00:00') == '0%  |  00:00:00'
	assert battery_clock_label(100, '23:59:59') == '100%  |  23:59:59'
	assert battery_clock_label(battery_io, '--:--:--') == '--%  |  --:--:--'
	assert battery_percentage_text(101) == '--%'
	mut app := battery_fixture_app()
	app.handle(battery_category_action) or { panic(err) }
	root := app.build(ui2.rect(0, 0, 320, 200)) or { panic(err) }
	if _ := element_named(root, 'settings.battery.percent') {
		assert false, 'offscreen battery elements must not be built'
	}
	mut wide := battery_fixture_app()
	wide.handle(battery_category_action) or { panic(err) }
	short := wide.build(ui2.rect(0, 0, 620, 359)) or { panic(err) }
	if _ := element_named(short, 'settings.battery.graph') {
		assert false, 'offscreen battery graph must not be built'
	}
}

fn test_battery_history_graph_and_estimate_are_rendered() {
	assert battery_graph_x(0, 3_600_000, 455) == 435
	assert battery_graph_x(3_600_000, 3_600_000, 455) == 454
	assert battery_graph_x(3_600_001, 3_600_000, 455) == -1
	mut history := BatteryHistory{}
	history.observe(0, 80)
	history.observe(300_000, 80)
	history.observe(600_000, 79)
	history.observe(3_900_000, 70)
	root := ui2.screen(app_surface, battery_settings_elements(70, &history, 16, 455))
	estimate := element_named(root, 'settings.battery.estimate') or {
		panic('missing remaining-time estimate')
	}
	assert estimate.text == 'About 7 hours'
	graph := element_named(root, 'settings.battery.graph') or { panic('missing battery graph') }
	assert graph.frame.width == 455 && graph.frame.height == 76
	marker := element_named(root, 'settings.battery.graph.current') or {
		panic('missing current battery marker')
	}
	assert marker.frame.x == 450
}
