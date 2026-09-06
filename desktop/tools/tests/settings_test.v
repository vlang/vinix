// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import ui2

// Only the real Settings implementation and theme are staged for these tests.
// This is the same interface as app.v, without the unrelated calculator model.
interface HostedApp {
mut:
	build(size ui2.Rect) !ui2.Element
	handle(event_id string) !
}

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
	mut app := &SettingsApp{ read_state: fixture_read, write_percent: fixture_write }
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
	category := element_named(root, 'settings.display') or { panic('missing Display category') }
	assert category.text == 'Display'
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
