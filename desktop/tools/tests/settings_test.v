// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import ui2

// The whole desktop is staged for these tests, so HostedApp and the rest come
// from the application itself rather than being restated here.
//
// Display and Battery are two categories of the desktop's one Settings
// application now. They report a device rather than changing the desktop, so
// they build and handle with no desktop behind them, which is what lets these
// tests drive them without standing a window manager up.

__global (
	fixture_state        BacklightState
	fixture_result       BacklightResult
	fixture_write_result BacklightResult
	fixture_writes       int
	fixture_percent      int
)

fn fixture_read(mut out BacklightState) BacklightResult {
	if fixture_result == .ok {
		out = fixture_state
	}
	return fixture_result
}

fn fixture_write(percent int) BacklightResult {
	fixture_writes++
	fixture_percent = percent
	if fixture_write_result == .ok {
		fixture_state.requested_nits = backlight_percent_to_nits(&fixture_state, percent) or { panic('percent') }
		fixture_state.pending = true
	}
	return fixture_write_result
}

fn fixture_app() &SettingsApp {
	fixture_state = BacklightState{
		requested_nits: 100
		actual_nits: 99
		min_nits: 2
		max_nits: 400
		online: true
		writable: true
	}
	fixture_result = .ok
	fixture_write_result = .ok
	fixture_writes = 0
	fixture_percent = -1
	desktop_scale_factor = desktop_scale_100
	desktop_applied_scale = desktop_scale_100
	mut app := &SettingsApp{
		category: .display
		read_state: fixture_read
		write_percent: fixture_write
	}
	app.refresh()
	return app
}

fn element_named(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		found := element_named(child, id) or { continue }
		return found
	}
	return none
}

fn test_settings_display_controls_and_explicit_writes() {
	mut app := fixture_app()
	root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	display_index := settings_categories.index(SettingsCategory.display)
	assert display_index >= 0
	element_named(root, '${settings_action_category}${display_index}') or {
		panic('missing Display category')
	}
	assert SettingsCategory.display.title() == 'Display'
	assert fixture_writes == 0
	app.handle('settings.refresh') or { panic(err) }
	assert fixture_writes == 0
	app.handle('settings.brightness.75') or { panic(err) }
	assert fixture_writes == 1 && fixture_percent == 75
	assert app.state.requested_nits == 301 && app.state.actual_nits == 99
	assert app.state.pending
	assert app.status_text().contains('pending')
	app.handle('settings.brightness.invalid') or { panic(err) }
	assert fixture_writes == 1
}

fn test_settings_scale_choices_and_stale_hits() {
	mut app := fixture_app()
	mut root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	scale_100 := element_named(root, settings_scale_100_action) or { panic('missing 100% scale') }
	mut scale_200 := element_named(root, settings_scale_200_action) or { panic('missing 200% scale') }
	assert scale_100.text == '100%'
	assert scale_200.text == '200%'
	assert scale_100.box.bg == app_accent
	assert scale_200.box.bg == files_up

	app.handle(settings_scale_200_action) or { panic(err) }
	assert desktop_scale_factor == desktop_scale_200
	root = app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	scale_200 = element_named(root, settings_scale_200_action) or { panic('missing selected 200% scale') }
	assert scale_200.box.bg == app_accent

	battery_index := settings_categories.index(SettingsCategory.battery)
	assert battery_index >= 0
	app.handle('${settings_action_category}${battery_index}') or { panic(err) }
	app.handle(settings_scale_100_action) or { panic(err) }
	assert desktop_scale_factor == desktop_scale_200
}

fn test_desktop_scale_defaults_and_extents() {
	assert desktop_default_scale(2304, 1440) == desktop_scale_200
	assert desktop_default_scale(2560, 1600) == desktop_scale_200
	assert desktop_default_scale(3024, 1964) == desktop_scale_200
	assert desktop_default_scale(1920, 1080) == desktop_scale_100
	assert desktop_default_scale(1024, 768) == desktop_scale_100
	assert desktop_scaled_extent(2560, desktop_scale_200) == 1280
	assert desktop_scaled_extent(2559, desktop_scale_200) == 1280
	assert desktop_scaled_extent(1920, desktop_scale_100) == 1920
}

fn test_settings_missing_offline_readonly_and_stale_hits() {
	for failure in 0 .. 3 {
		mut app := fixture_app()
		match failure {
			0 {
				fixture_result = BacklightResult.unavailable
			}
			1 {
				fixture_state.online = false
			}
			else {
				fixture_state.writable = false
			}
		}
		// Simulate an enabled target from the frame before device loss.
		app.handle('settings.brightness.50') or { panic(err) }
		assert fixture_writes == 0
		root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
		button := element_named(root, 'settings.brightness.50') or { panic('missing control') }
		assert !button.enabled
		refresh := element_named(root, 'settings.refresh') or { panic('missing Refresh') }
		assert refresh.enabled
	}
}

fn test_settings_unknown_readback_and_write_errors() {
	mut app := fixture_app()
	fixture_state.requested_nits = -1
	fixture_state.actual_nits = -1
	app.refresh()
	root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	increase := element_named(root, 'settings.increase') or { panic('missing increase') }
	assert !increase.enabled
	assert app.level_text == 'Unknown'
	app.handle('settings.increase') or { panic(err) }
	assert fixture_writes == 0
	fixture_write_result = .io
	app.handle('settings.brightness.50') or { panic(err) }
	assert fixture_writes == 1
	assert app.state.requested_nits == -1 && app.state.actual_nits == -1
	assert app.status_text().contains('failed')
	app.handle('settings.refresh') or { panic(err) }
	assert app.write_result == .ok && fixture_writes == 1
}

fn test_settings_steps_clamp_and_narrow_layout() {
	mut app := fixture_app()
	fixture_state.requested_nits = 400
	app.handle('settings.increase') or { panic(err) }
	assert fixture_percent == 100
	fixture_state.requested_nits = 2
	app.handle('settings.decrease') or { panic(err) }
	assert fixture_percent == 0
	root := app.build(ui2.rect(0, 0, 320, 200)) or { panic(err) }
	if _ := element_named(root, 'settings.brightness.50') {
		assert false, 'offscreen controls must not become hit targets'
	}
}
