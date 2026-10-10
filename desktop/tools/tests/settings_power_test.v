// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Settings > Power against a kernel these tests stand in for: what its power
// files say, and whether it takes a lid action or a profile when asked.
@[has_globals]
module main

import os
import ui2

__global (
	power_pane_controls       PowerControls
	power_pane_reads          int
	power_pane_lid_writes     []LidAction
	power_pane_profile_writes []PowerProfile
	power_pane_lid_result     PowerResult
	power_pane_profile_result PowerResult
)

const power_pane_action = '${settings_action_category}${settings_categories.index(SettingsCategory.power)}'

fn power_pane_read(mut out PowerControls) {
	power_pane_reads++
	out = power_pane_controls
}

// The kernel takes the word and says it back, unless it is to refuse.
fn power_pane_set_lid(action LidAction) PowerResult {
	power_pane_lid_writes << action
	if power_pane_lid_result == .ok {
		power_pane_controls.lid_action = action
	}
	return power_pane_lid_result
}

fn power_pane_set_profile(profile PowerProfile) PowerResult {
	power_pane_profile_writes << profile
	if power_pane_profile_result == .ok {
		power_pane_controls.profile = profile
	}
	return power_pane_profile_result
}

// A laptop with a frequency driver: it sleeps, has a lid, takes a profile.
fn power_pane_laptop() PowerControls {
	return PowerControls{
		sleep:            true
		lid:              true
		lid_action:       .suspend
		profile_known:    true
		profile:          .automatic
		profile_settable: true
	}
}

// A virtual machine: it sleeps, has no lid, and its profile file is
// read-only.
fn power_pane_vm() PowerControls {
	return PowerControls{
		sleep:         true
		profile_known: true
		profile:       .automatic
	}
}

fn power_pane_reset(controls PowerControls) {
	power_pane_controls = controls
	power_pane_reads = 0
	power_pane_lid_writes = []LidAction{}
	power_pane_profile_writes = []PowerProfile{}
	power_pane_lid_result = .ok
	power_pane_profile_result = .ok
}

fn power_pane_open(mut app SettingsApp) {
	app.power_read = power_pane_read
	app.power_set_lid = power_pane_set_lid
	app.power_set_profile = power_pane_set_profile
	app.handle(power_pane_action) or { panic(err) }
}

fn power_pane_find(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		if found := power_pane_find(child, id) {
			return found
		}
	}
	return none
}

fn power_pane_build(mut app SettingsApp) ui2.Element {
	return app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
}

fn power_pane_get(mut app SettingsApp, id string) ui2.Element {
	root := power_pane_build(mut app)
	return power_pane_find(root, id) or { panic('missing ${id}') }
}

fn power_pane_has(mut app SettingsApp, id string) bool {
	root := power_pane_build(mut app)
	if _ := power_pane_find(root, id) {
		return true
	}
	return false
}

// Which of a row's choices is the one in force. Exactly one is.
fn power_pane_checked(mut app SettingsApp, actions []string) int {
	root := power_pane_build(mut app)
	mut checked := -1
	for index, action in actions {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		if choice.checked {
			assert checked < 0, 'two choices checked in one row'
			checked = index
		}
	}
	return checked
}

fn test_power_is_a_category_between_battery_and_keyboard() {
	assert SettingsCategory.power.title() == 'Power'
	battery := settings_categories.index(SettingsCategory.battery)
	assert settings_categories.index(SettingsCategory.power) == battery + 1
	assert settings_categories.index(SettingsCategory.keyboard) == battery + 2
	assert settings_category_actions.len == settings_categories.len
	// Eleven categories still end inside the window Settings opens at.
	mut app := &SettingsApp{}
	root := power_pane_build(mut app)
	for index, action in settings_category_actions {
		row := power_pane_find(root, action) or { panic('missing category ${index}') }
		assert row.frame.y + row.frame.height <= 376, 'category ${index} ends at ${row.frame.y +
			row.frame.height}'
		if index > 0 {
			above := power_pane_find(root, settings_category_actions[index - 1]) or { panic('row') }
			assert row.frame.y >= above.frame.y + above.frame.height
		}
	}
}

fn test_power_pane_sets_the_timeouts_and_keeps_the_display_before_sleep() {
	power_pane_reset(power_pane_laptop())
	mut desktop := Desktop{}
	mut app := &SettingsApp{
		desktop: &desktop
	}
	power_pane_open(mut app)
	display := settings_power_display_actions[..]
	sleep := settings_power_sleep_actions[..]
	root := power_pane_build(mut app)
	mut labels := []string{}
	for action in display {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		assert choice.enabled
		labels << choice.text
	}
	assert labels == ['Never', '1 min', '2 min', '5 min', '10 min', '15 min', '30 min', '60 min']
	// As a new profile has them: never for both, until somebody chooses.
	assert desktop.settings.display_off_minutes == 0 && desktop.settings.sleep_minutes == 0
	assert power_pane_checked(mut app, display) == 0
	assert power_pane_checked(mut app, sleep) == 0
	assert power_pane_get(mut app, 'settings.power.idle_note').text == 'Counted from the last key press or pointer movement.'

	app.handle('settings.power.display.2')!
	assert desktop.settings.display_off_minutes == 2 && desktop.settings.sleep_minutes == 0
	assert power_pane_checked(mut app, display) == 2
	app.handle('settings.power.sleep.3')!
	assert desktop.settings.display_off_minutes == 2 && desktop.settings.sleep_minutes == 5
	// The display kept on longer than the machine pushes sleep back.
	app.handle('settings.power.display.6')!
	assert desktop.settings.display_off_minutes == 30 && desktop.settings.sleep_minutes == 30
	assert power_pane_checked(mut app, sleep) == 6
	// Sleeping sooner than the display turns off brings the display forward.
	app.handle('settings.power.sleep.1')!
	assert desktop.settings.display_off_minutes == 1 && desktop.settings.sleep_minutes == 1
	assert power_pane_checked(mut app, display) == 1
	// Never is free of the other.
	app.handle('settings.power.display.0')!
	assert desktop.settings.display_off_minutes == 0 && desktop.settings.sleep_minutes == 1
	app.handle('settings.power.sleep.0')!
	app.handle('settings.power.display.7')!
	assert desktop.settings.display_off_minutes == 60 && desktop.settings.sleep_minutes == 0
	for index in 0 .. idle_timeout_choices.len {
		app.handle(settings_power_display_actions[index])!
		assert desktop.settings.display_off_minutes == idle_timeout_choices[index]
		app.handle(settings_power_sleep_actions[index])!
		assert desktop.settings.sleep_minutes == idle_timeout_choices[index]
		assert idle_timeouts_valid(desktop.settings.display_off_minutes, desktop.settings.sleep_minutes)
	}
	// Nothing that is not one of the choices changes anything.
	before := desktop.settings
	for stale in ['settings.power.display.8', 'settings.power.display.-1', 'settings.power.display.',
		'settings.power.sleep.9', 'settings.power.sleep', 'settings.power.lid.2', 'settings.power.profile.4',
		'settings.brightness.50', 'settings.refresh'] {
		app.handle(stale)!
	}
	assert desktop.settings == before
	// The timeouts are the desktop's own: the kernel is told nothing.
	assert power_pane_lid_writes.len == 0 && power_pane_profile_writes.len == 0
}

fn test_power_pane_sleep_timeout_needs_a_kernel_that_sleeps() {
	mut awake := power_pane_laptop()
	awake.sleep = false
	power_pane_reset(awake)
	mut desktop := Desktop{}
	desktop.settings.sleep_minutes = 30
	mut app := &SettingsApp{
		desktop: &desktop
	}
	power_pane_open(mut app)
	root := power_pane_build(mut app)
	for action in settings_power_sleep_actions {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		assert !choice.enabled
	}
	for action in settings_power_display_actions {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		assert choice.enabled
	}
	// What was saved on a machine that could is still shown, and says why it
	// does nothing here.
	assert power_pane_checked(mut app, settings_power_sleep_actions[..]) == 6
	assert power_pane_get(mut app, 'settings.power.idle_note').text == 'This computer cannot sleep, so this is not used.'
	app.handle('settings.power.sleep.2')!
	assert desktop.settings.sleep_minutes == 30
	app.handle('settings.power.display.2')!
	assert desktop.settings.display_off_minutes == 2

	// The kernel is asked again at the click, not trusted from the last frame.
	power_pane_controls.sleep = true
	app.handle('settings.power.sleep.2')!
	assert desktop.settings.sleep_minutes == 2
}

fn test_power_pane_hides_the_lid_when_there_is_none() {
	power_pane_reset(power_pane_vm())
	mut desktop := Desktop{}
	mut app := &SettingsApp{
		desktop: &desktop
	}
	power_pane_open(mut app)
	assert !power_pane_has(mut app, 'settings.power.lid.0')
	assert !power_pane_has(mut app, 'settings.power.lid.1')
	// A button left over from a machine that had one writes nothing.
	app.handle('settings.power.lid.1')!
	assert power_pane_lid_writes.len == 0 && desktop.settings.lid_action == .suspend

	power_pane_reset(power_pane_laptop())
	power_pane_open(mut app)
	assert power_pane_get(mut app, 'settings.power.lid.0').text == 'Sleep'
	assert power_pane_get(mut app, 'settings.power.lid.1').text == 'Do nothing'
	assert power_pane_checked(mut app, settings_power_lid_actions[..]) == 0
	app.handle('settings.power.lid.1')!
	assert power_pane_lid_writes == [LidAction.ignore]
	// What the kernel says back is what is shown and what is kept.
	assert power_pane_checked(mut app, settings_power_lid_actions[..]) == 1
	assert desktop.settings.lid_action == .ignore
	assert !power_pane_has(mut app, 'settings.power.error')
	app.handle('settings.power.lid.0')!
	assert power_pane_lid_writes == [LidAction.ignore, .suspend]
	assert desktop.settings.lid_action == .suspend

	// A kernel that refuses: nothing is kept, the choice in force is still
	// the one shown, and the pane says the change was refused.
	power_pane_lid_result = .permission
	app.handle('settings.power.lid.1')!
	assert power_pane_lid_writes.len == 3 && desktop.settings.lid_action == .suspend
	assert power_pane_checked(mut app, settings_power_lid_actions[..]) == 0
	assert power_pane_get(mut app, 'settings.power.error').text == 'The kernel refused the change.'
	// Opening the page again clears the complaint.
	app.handle(power_pane_action)!
	assert !power_pane_has(mut app, 'settings.power.error')
	// The lid goes away between two frames, as when its state stops reading.
	power_pane_lid_result = .ok
	power_pane_controls.lid = false
	app.handle('settings.power.lid.1')!
	assert power_pane_lid_writes.len == 3
}

fn test_power_pane_disables_the_profile_the_kernel_refuses() {
	// Every virtual machine: the profile file is read-only. The control is
	// drawn, so what is in force can be seen, takes no click, and says why.
	power_pane_reset(power_pane_vm())
	mut desktop := Desktop{}
	mut app := &SettingsApp{
		desktop: &desktop
	}
	power_pane_open(mut app)
	profiles := settings_power_profile_actions[..]
	mut root := power_pane_build(mut app)
	for action in profiles {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		assert !choice.enabled
	}
	assert power_pane_checked(mut app, profiles) == 0
	assert power_pane_get(mut app, 'settings.power.profile_note').text == 'This machine has no CPU frequency control, so the profile cannot be changed.'
	for action in profiles {
		app.handle(action)!
	}
	assert power_pane_profile_writes.len == 0 && desktop.settings.power_profile == .automatic

	// A machine whose kernel takes one.
	power_pane_reset(power_pane_laptop())
	power_pane_open(mut app)
	root = power_pane_build(mut app)
	mut labels := []string{}
	for action in profiles {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		assert choice.enabled
		labels << choice.text
	}
	assert labels == ['Automatic', 'Performance', 'Balanced', 'Power saver']
	assert power_pane_get(mut app, 'settings.power.profile_note').text == 'Automatic: balanced on the charger, power saver on battery.'
	for index, profile in power_profiles {
		app.handle(settings_power_profile_actions[index])!
		assert power_pane_profile_writes.last() == profile
		assert desktop.settings.power_profile == profile
		assert power_pane_checked(mut app, profiles) == index
	}
	assert power_pane_profile_writes.len == power_profiles.len

	// The mode said yes and the kernel refused all the same: the choice is
	// not kept, and the control goes off with the same explanation rather
	// than inviting another try.
	power_pane_profile_result = .permission
	app.handle('settings.power.profile.1')!
	assert power_pane_profile_writes.len == power_profiles.len + 1
	assert desktop.settings.power_profile == .power_saver
	root = power_pane_build(mut app)
	for action in profiles {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		assert !choice.enabled
	}
	assert power_pane_get(mut app, 'settings.power.profile_note').text == 'This machine has no CPU frequency control, so the profile cannot be changed.'
	assert !power_pane_has(mut app, 'settings.power.error')
	app.handle('settings.power.profile.2')!
	assert power_pane_profile_writes.len == power_profiles.len + 1
	// Any other failure is reported and the control stays.
	app.handle(power_pane_action)!
	power_pane_profile_result = .io
	app.handle('settings.power.profile.2')!
	assert power_pane_get(mut app, 'settings.power.error').text == 'The kernel refused the change.'
	assert power_pane_get(mut app, 'settings.power.profile.2').enabled
	assert desktop.settings.power_profile == .power_saver

	// A kernel with no profile files has no control to show.
	mut older := power_pane_laptop()
	older.profile_known = false
	power_pane_reset(older)
	power_pane_open(mut app)
	assert !power_pane_has(mut app, 'settings.power.profile.0')
	assert !power_pane_has(mut app, 'settings.power.profile_note')
	app.handle('settings.power.profile.1')!
	assert power_pane_profile_writes.len == 0
}

fn test_power_pane_reads_the_kernel_and_never_writes_by_itself() {
	power_pane_reset(power_pane_laptop())
	mut desktop := Desktop{}
	mut app := &SettingsApp{
		desktop: &desktop
	}
	power_pane_open(mut app)
	// Choosing the page reads once; repaints within the second read nothing.
	assert power_pane_reads == 1
	for _ in 0 .. 50 {
		power_pane_build(mut app)
	}
	assert power_pane_reads == 1
	// A change made from a shell shows when the page next reads.
	power_pane_controls.lid_action = .ignore
	power_pane_controls.profile = .performance
	app.power_last_poll_ms = 0
	assert power_pane_checked(mut app, settings_power_lid_actions[..]) == 1
	assert power_pane_reads == 2
	assert power_pane_checked(mut app, settings_power_profile_actions[..]) == 1
	// Showing what the kernel says is not choosing it: nothing was written,
	// and the saved settings are not changed by looking.
	assert power_pane_lid_writes.len == 0 && power_pane_profile_writes.len == 0
	assert desktop.settings.lid_action == .suspend && desktop.settings.power_profile == .automatic
	// Another page reads nothing.
	app.handle('${settings_action_category}0')!
	reads := power_pane_reads
	app.power_last_poll_ms = 0
	power_pane_build(mut app)
	assert power_pane_reads == reads

	// With no desktop behind the window the kernel's side still shows, the
	// timeouts take no click, and nothing fails.
	power_pane_reset(power_pane_laptop())
	mut alone := &SettingsApp{}
	power_pane_open(mut alone)
	root := power_pane_build(mut alone)
	for action in settings_power_display_actions {
		choice := power_pane_find(root, action) or { panic('missing ${action}') }
		assert !choice.enabled
	}
	assert power_pane_find(root, 'settings.power.lid.0') != none
	alone.handle('settings.power.display.2')!
	alone.handle('settings.power.sleep.2')!
	alone.handle('settings.power.lid.1')!
	assert power_pane_lid_writes == [LidAction.ignore]
	// Too narrow for its controls, it builds none of them.
	narrow := alone.build(ui2.rect(0, 0, 320, 200)) or { panic(err) }
	assert power_pane_find(narrow, 'settings.power.display.0') == none
}

fn power_pane_assert_fits(desktop &Desktop, el ui2.Element, context string) {
	if el.text.len > 0 && (el.kind == .label || el.kind == .button) {
		width := desktop.face_for(el.text_style).text_width(el.text)
		assert width <= int(el.frame.width), '${context}: «${el.text}» is ${width}px in ${int(el.frame.width)}px'
	}
	for child in el.children {
		power_pane_assert_fits(desktop, child, context)
	}
}

fn test_power_pane_fits_the_window_in_every_language() {
	mut fonts := Desktop{
		canvas: new_canvas(8, 8)
		fonts:  load_fonts()
	}
	defer {
		set_desktop_language(.en)
		unsafe { free(fonts.canvas.pixels) }
	}
	mut desktop := Desktop{}
	mut app := &SettingsApp{
		desktop: &desktop
	}
	for language in desktop_languages {
		set_desktop_language(language)
		for case in 0 .. 4 {
			mut controls := if case == 1 { power_pane_vm() } else { power_pane_laptop() }
			if case == 2 {
				controls.sleep = false
			}
			power_pane_reset(controls)
			power_pane_open(mut app)
			if case == 3 {
				power_pane_lid_result = .io
				app.handle('settings.power.lid.1')!
			}
			root := power_pane_build(mut app)
			power_pane_assert_fits(&fonts, root, '${language} case ${case}')
			// Every control is inside the pane, and no two in a row overlap.
			for actions in [settings_power_display_actions[..], settings_power_sleep_actions[..],
				settings_power_lid_actions[..], settings_power_profile_actions[..]] {
				mut right := 0.0
				for action in actions {
					choice := power_pane_find(root, action) or { continue }
					assert choice.frame.x >= right, '${language} ${action}'
					assert choice.frame.x + choice.frame.width <= 620 - settings_sidebar_width - 1 - settings_padding
					assert choice.frame.y + choice.frame.height <= 376
					right = choice.frame.x + choice.frame.width
				}
			}
			for id in ['settings.power.idle_note', 'settings.power.profile_note', 'settings.power.error'] {
				line := power_pane_find(root, id) or { continue }
				assert line.frame.y + line.frame.height <= 376, '${language} ${id}'
			}
		}
	}
	// The minutes are made once per language and handed out again.
	set_desktop_language(.ru)
	assert power_timeout_text(4) == '10 мин'
	assert power_timeout_text(4).str == power_timeout_text(4).str
	assert power_timeout_text(0) == 'Никогда'
	set_desktop_language(.ja)
	assert power_timeout_text(7) == '60分'
	set_desktop_language(.en)
	assert power_timeout_text(1) == '1 min' && power_timeout_text(99) == 'Never'
}

fn test_power_settings_cross_the_process_boundary_and_are_saved() {
	state := AppWireState{
		settings: Settings{
			display_off_minutes: 5
			sleep_minutes:       30
			lid_action:          .ignore
			power_profile:       .balanced
		}
	}
	mut encoded := []u8{}
	wire_put_state(mut encoded, state)
	mut reader := &WireReader{
		data: encoded
	}
	decoded := wire_take_state(mut reader) or { panic(err) }
	assert decoded.settings == state.settings
	// A header is the state and twenty bytes around it, on both sides.
	assert app_request_header_size == encoded.len + 20
	assert app_response_header_size == encoded.len + 12

	// What Settings could not have produced is refused whole.
	for bad in [
		Settings{
			display_off_minutes: 30
			sleep_minutes:       5
		},
		Settings{
			display_off_minutes: 3
		},
		Settings{
			sleep_minutes: -1
		},
		Settings{
			sleep_minutes: 600
		},
	] {
		mut out := []u8{}
		wire_put_state(mut out, AppWireState{ settings: bad })
		mut bad_reader := &WireReader{
			data: out
		}
		if _ := wire_take_state(mut bad_reader) {
			assert false, 'accepted ${bad.display_off_minutes} and ${bad.sleep_minutes}'
		}
	}
	// A lid action or a profile past the last one.
	for offset in [56, 60] {
		for value in [u8(4), 255] {
			mut out := []u8{}
			wire_put_state(mut out, state)
			out[offset] = value
			mut bad_reader := &WireReader{
				data: out
			}
			if _ := wire_take_state(mut bad_reader) {
				assert false, 'accepted ${value} at ${offset}'
			}
		}
	}

	// The compositor takes them from Settings' reply and saves them with
	// everything else.
	home := os.join_path(os.temp_dir(), 'vinix-settings-power-${os.getpid()}')
	os.rmdir_all(home) or {}
	os.mkdir(home)!
	defer { os.rmdir_all(home) or {} }
	mut preferences := desktop_load_preferences(home)
	mut desktop := Desktop{
		settings: preferences.settings
	}
	power_pane_reset(power_pane_laptop())
	mut proxy := Desktop{
		settings: desktop.settings
	}
	mut app := &SettingsApp{
		desktop: &proxy
	}
	power_pane_open(mut app)
	app.handle('settings.power.display.2')!
	app.handle('settings.power.sleep.5')!
	app.handle('settings.power.lid.1')!
	app.handle('settings.power.profile.3')!
	apply_app_state(mut desktop, app_current_state(&proxy))
	assert desktop.settings.display_off_minutes == 2 && desktop.settings.sleep_minutes == 15
	assert desktop.settings.lid_action == .ignore && desktop.settings.power_profile == .power_saver
	assert preferences.save_changes(desktop.settings, desktop_current_scale(), home)
	restored := desktop_load_preferences(home)
	assert restored.settings == desktop.settings
	record := os.read_file(desktop_preferences_path(home))!
	assert record.ends_with('display_off_after=2\nsleep_after=15\nlid_action=ignore\npower_profile=power_saver\n')
}
