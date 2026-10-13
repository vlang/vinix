// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The Settings application: categories down the left, the chosen category's
// settings on the right.
//
// It is a native application like any other, but unlike the file browser it
// changes compositor state. Its process writes a synchronized Desktop proxy;
// app_process.v returns those preferences with the action response, and the
// compositor uses them on the next frame. A choice therefore still appears
// immediately and everywhere without sharing an address space.
module main

import ui2
import desktop.sessioncore

enum SettingsCategory {
	appearance
	date_time
	language
	theme
	wallpaper
	wifi
	display
	battery
	power
	keyboard
	about
	sound
	bluetooth
	printers
	users
	network
	privacy
	storage
	updates
	accessibility
	clock
	session
	shortcuts
	gestures
}

const settings_categories = [SettingsCategory.appearance, .date_time, .language, .theme, .wallpaper,
	.wifi, .display, .battery, .power, .keyboard, .about, .sound, .bluetooth, .printers,
	.users, .network, .privacy, .storage, .updates, .accessibility, .clock, .session, .shortcuts, .gestures]

fn (c SettingsCategory) title() string {
	return match c {
		.appearance { tr('settings.category.appearance') }
		.date_time { tr('settings.category.date_time') }
		.language { tr('settings.category.language') }
		.theme { tr('settings.category.theme') }
		.wallpaper { tr('settings.category.wallpaper') }
		.wifi { tr('settings.category.wifi') }
		.display { tr('settings.category.display') }
		.battery { tr('settings.category.battery') }
		.power { tr('settings.category.power') }
		.keyboard { tr('settings.category.keyboard') }
		.about { tr('settings.category.about') }
		.sound { 'Sound' }
		.bluetooth { 'Bluetooth' }
		.printers { 'Printers' }
		.users { 'Users' }
		.network { 'Network' }
		.privacy { 'Privacy' }
		.storage { 'Storage' }
		.updates { 'Updates' }
		.accessibility { 'Accessibility' }
		.clock { 'Clock & timezone' }
		.session { 'Session' }
		.shortcuts { 'Shortcuts' }
		.gestures { 'Gestures & corners' }
	}
}

const settings_action_category = 'settings.category.'
const settings_action_side = 'settings.side.'
const settings_action_taskbar = 'settings.taskbar.'
const settings_action_clock_format = 'settings.clock.format.'
const settings_action_clock_seconds = 'settings.clock.seconds.'
const settings_action_clock_date = 'settings.clock.date.'
const settings_action_clock_weekday = 'settings.clock.weekday.'
const settings_action_language = 'settings.language.'
const settings_action_theme = 'settings.theme.'
// One swatch per entry of glass_colors.
const settings_action_glass = 'settings.glass.'
const settings_glass_actions = ['settings.glass.0', 'settings.glass.1', 'settings.glass.2',
	'settings.glass.3', 'settings.glass.4', 'settings.glass.5', 'settings.glass.6', 'settings.glass.7',
	'settings.glass.8', 'settings.glass.9', 'settings.glass.10', 'settings.glass.11', 'settings.glass.12',
	'settings.glass.13', 'settings.glass.14', 'settings.glass.15']!
// Windows 7 lays its sixteen colours out in two rows.
const settings_glass_columns = 8
const settings_action_color = 'settings.color.'
const settings_action_image = 'settings.image.'
const settings_language_actions = ['settings.language.0', 'settings.language.1', 'settings.language.2',
	'settings.language.3', 'settings.language.4', 'settings.language.5']!

const settings_sidebar_width = 132
const settings_padding = 16
const settings_row_gap = 8
// From one category to the next in the sidebar. Eleven of them end just
// inside the window Settings opens at.
const settings_category_pitch = 29

struct SettingsApp {
mut:
	// The synchronized desktop-state proxy this is changing. A native app
	// usually knows nothing about compositor state; this one is the exception,
	// and is the reason
	// NativeApp's build takes only a size — everything else it needs, it holds.
	desktop  &Desktop = unsafe { nil }
	category SettingsCategory = .appearance
	about SettingsAbout
	images   []WallpaperImage
	// Display, Battery and Wi-Fi read devices rather than the desktop's own
	// preferences, so they carry the last readback and the labels made from
	// it. The reads are injectable so host tests can drive them.
	battery_read       fn (bool) int = read_battery
	battery_history    fn () BatteryHistory = battery_history_snapshot
	battery_reading    fn () BatteryReading = battery_reading_snapshot
	// The history the Battery pane last drew. See battery_pane.
	battery_shown      BatteryHistory
	state              BacklightState
	read_result        BacklightResult = .unavailable
	write_result       BacklightResult
	last_poll_ms       u64
	initialized        bool
	read_state         fn (mut BacklightState) BacklightResult = read_backlight
	write_percent      fn (int) BacklightResult = set_backlight_percent
	wifi_state         WifiState
	wifi_read_result   WifiResult = .unavailable
	wifi_action_result WifiResult
	wifi_last_poll_ms  u64
	wifi_initialized   bool
	wifi_read          fn (mut WifiState) WifiResult = read_wifi
	wifi_radio         fn (bool) WifiResult = set_wifi_radio
	wifi_scan          fn () WifiResult = scan_wifi
	wifi_names         [32]string
	wifi_details       [32]string
	wifi_offset        int
	// Power shows what the kernel's power files say beside the desktop's own
	// timeouts. `power_result` is how the last write to the kernel went.
	power              PowerControls
	power_result       PowerResult
	// The kernel refused a profile although the file's mode had let it be
	// tried. The control stays off until the page is opened again.
	power_profile_refused bool
	power_last_poll_ms u64
	power_initialized  bool
	power_read         fn (mut PowerControls) = read_power_controls
	power_set_lid      fn (LidAction) PowerResult = set_lid_action
	power_set_profile  fn (PowerProfile) PowerResult = set_power_profile
	// Owned, cached labels. Replaced only when a readback changes, never per
	// frame: the framebuffer renderer frees child arrays, not strings.
	level_text     string
	requested_text string
	actual_text    string
	range_text     string
	// The languages the labels above and wifi_names/wifi_details were made
	// in. When desktop_language differs they are remade before being shown.
	labels_language      DesktopLanguage
	wifi_labels_language DesktopLanguage
	// Only the bounded query owns storage; result indices and input fragments
	// are inline. Frame labels borrow the query and translation table.
	search []u8
	search_results [settings_search_capacity]int
	search_count int
	search_selected int
	search_page int
	search_rows int = 6
	search_language DesktopLanguage
	search_focused bool
	search_select_all bool
	search_pending [4]u8
	search_pending_len int
	search_escape [16]u8
	search_escape_len int
	search_escape_ms u64
	category_page int
	service_status sessioncore.SettingsStatus
	service_poll_ms i64
	service_value sessioncore.Text
	service_edit bool
	service_actions [8]string
}

fn (mut d Desktop) open_settings() !NativeApp {
	return &SettingsApp{
		desktop: d
		images: list_wallpapers()
	}
}

fn (mut a SettingsApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	if int(a.category) >= int(SettingsCategory.sound) && !a.searching() { a.refresh_session_settings(false) }
	if a.search_language != desktop_language { a.refilter_search() }

	mut children := frame_elements(3)

	// The sidebar, and a hairline between it and the pane.
	children << ui2.view('', ui2.rect(0, 0, f64(settings_sidebar_width), f64(height)), ui2.BoxStyle{
		bg: settings_sidebar_bg
	}, a.category_rows())
	children << ui2.view('', ui2.rect(f64(settings_sidebar_width), 0, 1, f64(height)), ui2.BoxStyle{
		bg: body_rule
	}, [])

	pane_x := settings_sidebar_width + 1
	pane_width := width - pane_x
	// Display polls the panel no more often than the desktop redraws for its
	// clock, and picks up a change another Settings window made.
	if !a.searching() && a.category == .display {
		now := desktop_monotonic_ms()
		if !a.initialized || (now != ~u64(0) && (now < a.last_poll_ms
			|| now - a.last_poll_ms >= 1000)) {
			a.refresh()
		}
	}
	if !a.searching() && a.category == .wifi {
		now := desktop_monotonic_ms()
		if !a.wifi_initialized || (now != ~u64(0) && (now < a.wifi_last_poll_ms
			|| now - a.wifi_last_poll_ms >= 1000)) {
			a.refresh_wifi()
		}
	}
	// Power rereads the kernel's files on the same cadence, so a lid action
	// or profile changed from a shell shows here too.
	if !a.searching() && a.category == .power {
		now := desktop_monotonic_ms()
		if !a.power_initialized || (now != ~u64(0) && (now < a.power_last_poll_ms
			|| now - a.power_last_poll_ms >= 1000)) {
			a.refresh_power()
		}
	}
	if !a.searching() && a.category == .about && !a.about.initialized { a.about.refresh() }
	content := if a.searching() { a.search_pane(pane_width, height) } else { a.pane(pane_width, height) }

	children << ui2.view('', ui2.rect(f64(pane_x), 0, f64(pane_width), f64(height)), ui2.BoxStyle{
		bg: app_surface
	}, content)

	// The screen's own background never shows; the two panes cover it. It is
	// the application surface so that a window resized oddly still looks whole.
	return ui2.screen(app_surface, children)
}

// Display and Battery report a device and change nothing here, so they draw
// without a desktop behind them, and Power shows the kernel's side of itself
// the same way. The remaining panes are desktop preferences and have nothing
// to show without one.
fn (a &SettingsApp) pane(width int, height int) []ui2.Element {
	if int(a.category) >= int(SettingsCategory.sound) { return a.session_settings_pane(width,height) }
	match a.category {
		.about { return a.about.pane(width) }
		.wifi {
			return a.wifi_pane(width, height)
		}
		.display {
			return a.display_pane(width)
		}
		.battery {
			return a.battery_pane(width, height)
		}
		.power {
			return a.power_pane(width)
		}
		else {}
	}
	if a.desktop == unsafe { nil } {
		return []ui2.Element{}
	}
	return match a.category {
		.appearance { a.appearance_pane(width) }
		.date_time { a.date_time_pane(width) }
		.language { a.language_pane(width) }
		.theme { a.theme_pane(width) }
		.wallpaper { a.wallpaper_pane(width) }
		.keyboard { a.keyboard_pane(width) }
		else { []ui2.Element{} }
	}
}

fn (a &SettingsApp) category_rows() []ui2.Element {
	mut rows := frame_elements(settings_categories.len + 1)
	rows << a.search_field()
	for index, category in settings_categories {
		if index / 11 != a.category_page { continue }
		selected := category == a.category
		y := 56 + (index % 11) * settings_category_pitch
		mut label := frame_elements(1)
		label << ui2.label('', category.title(), ui2.rect(18, 0, f64(settings_sidebar_width - 24), 28), ui2.TextStyle{
			color: if selected { body_heading } else { body_text }
			size: 13
			bold: selected
		})
		rows << ui2.clickable_view(settings_category_actions[index], ui2.rect(0, f64(y), f64(settings_sidebar_width), 28), ui2.BoxStyle{
			bg: settings_category_selected
			transparent: !selected
		}, label)
	}
	rows << settings_choice('settings.categories.previous','<',8,378,52,false)
	rows << settings_choice('settings.categories.next','>',70,378,52,false)
	return rows
}

// heading_row and option_row give every pane the same shape: a heading, a
// sentence saying what the choice means, then the choices themselves.
fn settings_heading(text string, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(settings_padding), f64(y), f64(width - 2 * settings_padding), 20), ui2.TextStyle{
		color: body_heading
		size: 13
		bold: true
	})
}

fn settings_note(text string, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(settings_padding), f64(y), f64(width - 2 * settings_padding), 16), ui2.TextStyle{
		color: body_muted
		size: 11
	})
}

// A choice carries radio state but asks for a native button bezel. The Vinix
// renderer therefore keeps the existing flat control in the default theme and
// uses a compact Catalina push-button face in the macOS theme.
fn settings_choice(id string, label string, x int, y int, width int, selected bool) ui2.Element {
	return ui2.Element{
		kind:                .button
		id:                  id
		text:                label
		frame:               ui2.rect(f64(x), f64(y), f64(width), 28)
		box:                 ui2.BoxStyle{
			bg:     if selected { app_accent } else { settings_choice_bg }
			radius: 6
		}
		text_style:          ui2.TextStyle{
			color: if selected { app_on_accent } else { body_text }
			size:  12
			align: .center
		}
		native_style:        true
		checked:             selected
		accessibility_role:  'radio'
		accessibility_label: label
		accessibility_value: if selected { tr('settings.choice.selected') } else { tr('settings.choice.not_selected') }
	}
}

fn (a &SettingsApp) appearance_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	half := (inner - settings_row_gap) / 2

	mut out := frame_elements(12)
	mut y := settings_padding

	out << settings_heading(tr('settings.appearance.buttons'), y, width)
	y += 22
	out << settings_note(tr('settings.appearance.buttons_note'), y, width)
	y += 22
	out << settings_choice('settings.side.0', tr('settings.appearance.right'), settings_padding, y, half, settings.button_side == .right)
	out << settings_choice('settings.side.1', tr('settings.appearance.left'), settings_padding + half + settings_row_gap, y, half, settings.button_side == .left)
	y += 28 + 22

	out << settings_heading(tr('settings.appearance.taskbar'), y, width)
	y += 22
	out << settings_note(tr('settings.appearance.taskbar_note'), y, width)
	y += 22
	out << settings_choice('settings.taskbar.0', tr('settings.appearance.standard'), settings_padding, y, half, settings.taskbar_mode == .standard)
	out << settings_choice('settings.taskbar.1', tr('settings.appearance.combined'), settings_padding + half + settings_row_gap, y, half, settings.taskbar_mode == .combined)
	y += 28 + 6
	out << settings_note(if settings.taskbar_mode == .combined {
		tr('settings.appearance.combined_note')
	} else {
		tr('settings.appearance.standard_note')
	}, y, width)

	return out
}

fn (a &SettingsApp) date_time_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	half := (inner - settings_row_gap) / 2

	mut out := frame_elements(16)
	mut y := settings_padding

	out << settings_heading(tr('settings.date_time.format'), y, width)
	y += 22
	out << settings_note(tr('settings.date_time.format_note'), y, width)
	y += 22
	out << settings_choice('settings.clock.format.0', tr('settings.date_time.24_hour'), settings_padding, y, half, settings.clock_24_hour)
	out << settings_choice('settings.clock.format.1', tr('settings.date_time.12_hour'), settings_padding + half + settings_row_gap, y, half, !settings.clock_24_hour)
	y += 28 + 22

	out << settings_heading(tr('settings.date_time.seconds'), y, width)
	y += 22
	out << settings_note(tr('settings.date_time.seconds_note'), y, width)
	y += 22
	out << settings_choice('settings.clock.seconds.0', tr('settings.date_time.show'), settings_padding, y, half, settings.clock_show_seconds)
	out << settings_choice('settings.clock.seconds.1', tr('settings.date_time.hide'), settings_padding + half + settings_row_gap, y, half, !settings.clock_show_seconds)
	y += 28 + 22

	out << settings_heading(tr('settings.date_time.date_line'), y, width)
	y += 22
	out << settings_note(tr('settings.date_time.date_line_note'), y, width)
	y += 22
	out << settings_choice('settings.clock.date.0', tr('settings.date_time.show_date'), settings_padding, y, half, settings.clock_show_date)
	out << settings_choice('settings.clock.date.1', tr('settings.date_time.hide_date'), settings_padding + half + settings_row_gap, y, half, !settings.clock_show_date)
	y += 28 + settings_row_gap
	out << settings_choice('settings.clock.weekday.0', tr('settings.date_time.show_weekday'), settings_padding, y, half, settings.clock_show_weekday)
	out << settings_choice('settings.clock.weekday.1', tr('settings.date_time.hide_weekday'), settings_padding + half + settings_row_gap, y, half, !settings.clock_show_weekday)

	return out
}

// settings_glass_offered says whether the compositor showing this window has
// the Windows 7 theme.
fn settings_glass_offered() bool {
	return app_compositor_features & app_feature_glass != 0
}

// settings_luna_offered says the same of the Windows XP theme.
fn settings_luna_offered() bool {
	return app_compositor_extended & app_extended_luna != 0
}

fn (a &SettingsApp) theme_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	// Settings published to a running desktop on its own offers only the
	// themes that desktop can draw.
	glass_offered := settings_glass_offered()
	luna_offered := settings_luna_offered()
	columns := 2 + if glass_offered { 1 } else { 0 } + if luna_offered { 1 } else { 0 }
	choice := (inner - (columns - 1) * settings_row_gap) / columns

	mut out := frame_elements(9 + glass_colors.len)
	mut y := settings_padding

	out << settings_heading(tr('settings.theme.heading'), y, width)
	y += 22
	out << settings_note(tr('settings.theme.note'), y, width)
	y += 22
	out << settings_choice('settings.theme.0', tr('settings.theme.default'), settings_padding, y, choice, settings.theme == .default_)
	out << settings_choice('settings.theme.1', tr('settings.theme.macos'), settings_padding + choice + settings_row_gap, y, choice, settings.theme == .macos)
	mut slot := 2
	if glass_offered {
		out << settings_choice('settings.theme.2', tr('settings.theme.windows7'), settings_padding + slot * (choice + settings_row_gap), y, choice, settings.theme == .windows7)
		slot++
	}
	if luna_offered {
		out << settings_choice('settings.theme.3', tr('settings.theme.windowsxp'), settings_padding + slot * (choice + settings_row_gap), y, choice, settings.theme == .windows_xp)
	}
	y += 28 + 10

	// Each description is two lines, broken where the translation breaks it.
	match settings.theme {
		.default_ {
			out << settings_note(tr('settings.theme.default_note_1'), y, width)
			y += 16
			out << settings_note(tr('settings.theme.default_note_2'), y, width)
		}
		.macos {
			out << settings_note(tr('settings.theme.macos_note_1'), y, width)
			y += 16
			out << settings_note(tr('settings.theme.macos_note_2'), y, width)
		}
		.windows7 {
			out << settings_note(tr('settings.theme.windows7_note_1'), y, width)
			y += 16
			out << settings_note(tr('settings.theme.windows7_note_2'), y, width)
		}
		.windows_xp {
			out << settings_note(tr('settings.theme.windowsxp_note_1'), y, width)
			y += 16
			out << settings_note(tr('settings.theme.windowsxp_note_2'), y, width)
		}
	}
	if settings.theme != .windows7 {
		return out
	}
	y += 16 + 22

	// The colour of the glass: Windows 7's own sixteen, in its two rows.
	out << settings_heading(tr('settings.theme.glass_color'), y, width)
	y += 22
	out << settings_note(tr('settings.theme.glass_color_note'), y, width)
	y += 24
	swatch := (inner - (settings_glass_columns - 1) * settings_row_gap) / settings_glass_columns
	for index, color in glass_colors {
		column := index % settings_glass_columns
		row := index / settings_glass_columns
		selected := settings.glass_color == index
		out << ui2.clickable_view(settings_glass_actions[index], ui2.rect(f64(settings_padding +
			column * (swatch + settings_row_gap)), f64(y + row * (swatch + settings_row_gap)), f64(swatch),
			f64(swatch)), ui2.BoxStyle{
			bg:     if selected { app_accent } else { settings_choice_bg }
			radius: 6
		}, frame_child(
		// The swatch proper, inset so the selected ring shows around it.
		ui2.view('', ui2.rect(3, 3, f64(swatch - 6), f64(swatch - 6)), ui2.BoxStyle{
			bg:     color.color
			radius: 4
		}, [])))
	}

	return out
}

// Each language is offered in its own name, three to a row.
fn (a &SettingsApp) language_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	columns := 3
	choice_width := (inner - (columns - 1) * settings_row_gap) / columns

	mut out := frame_elements(desktop_languages.len + 3)
	mut y := settings_padding

	out << settings_heading(tr('settings.language.heading'), y, width)
	y += 22
	out << settings_note(tr('settings.language.note'), y, width)
	y += 22
	for index, language in desktop_languages {
		column := index % columns
		row := index / columns
		out << settings_choice(settings_language_actions[index], language.native_name(),
			settings_padding + column * (choice_width + settings_row_gap), y + row * (28 +
			settings_row_gap), choice_width, settings.language == language)
	}
	rows := (desktop_languages.len + columns - 1) / columns
	y += rows * (28 + settings_row_gap) + 6
	out << settings_note(tr('settings.language.apps_note'), y, width)

	return out
}

fn (a &SettingsApp) wallpaper_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding

	mut out := frame_elements(wallpaper_colors.len + a.images.len + 4)
	mut y := settings_padding

	out << settings_heading(tr('settings.wallpaper.colour'), y, width)
	y += 24

	// Colour swatches, four to a row.
	columns := 4
	swatch := (inner - (columns - 1) * settings_row_gap) / columns
	for index, color in wallpaper_colors {
		column := index % columns
		row := index / columns
		selected := settings.wallpaper_image < 0 && settings.wallpaper_color == index
		out << ui2.clickable_view('${settings_action_color}${index}', ui2.rect(f64(settings_padding + column * (swatch + settings_row_gap)), f64(y + row * (swatch + settings_row_gap)), f64(swatch), f64(swatch)), ui2.BoxStyle{
			bg: if selected { app_accent } else { settings_choice_bg }
			radius: 6
		}, frame_child(
		// The swatch proper, inset so the selected ring shows around it.
		ui2.view('', ui2.rect(3, 3, f64(swatch - 6), f64(swatch - 6)), ui2.BoxStyle{
			bg: color.top
			radius: 4
		}, [])))
	}
	rows := (wallpaper_colors.len + columns - 1) / columns
	y += rows * (swatch + settings_row_gap) + 6

	out << settings_heading(tr('settings.wallpaper.photo'), y, width)
	y += 24

	if a.images.len == 0 {
		out << settings_note(tr('settings.wallpaper.no_photos_1'), y, width)
		y += 16
		out << settings_note(tr('settings.wallpaper.no_photos_2'), y, width)
		return out
	}

	// Thumbnails, five to a row. They are drawn as plain tiles rather than as
	// the pictures themselves: scaling ten wallpapers every frame to fill
	// squares this size would cost more than the desktop it is describing.
	photo_columns := 5
	tile_width := (inner - (photo_columns - 1) * settings_row_gap) / photo_columns
	tile_height := tile_width * 3 / 4
	for index, _ in a.images {
		column := index % photo_columns
		row := index / photo_columns
		selected := settings.wallpaper_image == index
		out << ui2.clickable_view('${settings_action_image}${index}', ui2.rect(f64(settings_padding + column * (tile_width + settings_row_gap)), f64(y + row * (tile_height + settings_row_gap)), f64(tile_width), f64(tile_height)), ui2.BoxStyle{
			bg: if selected { app_accent } else { settings_choice_bg }
			radius: 6
		}, frame_child(ui2.label('', '${index + 1}', ui2.rect(0, 0, f64(tile_width), f64(tile_height)), ui2.TextStyle{
			color: if selected { app_on_accent } else { body_text }
			size: 12
			align: .center
		})))
	}

	return out
}

fn (mut a SettingsApp) handle(event_id string) ! {
	if event_id == 'settings.categories.previous' { if a.category_page>0 { a.category_page-- }; return }
	if event_id == 'settings.categories.next' { if a.category_page < (settings_categories.len-1)/11 { a.category_page++ }; return }
	if a.handle_session_settings(event_id) { return }
	if a.handle_search(event_id) { return }
	if event_id.starts_with(settings_action_category) {
		for index, action in settings_category_actions {
			if event_id == action { a.choose_category(settings_categories[index]); break }
		}
		return
	}
	// A stale control from the pane hidden by results cannot change a setting.
	if a.searching() { return }
	a.search_focused = false
	a.search_select_all = false
	if event_id == 'settings.about.refresh' { a.about.refresh(); return }
	if a.category == .wifi {
		a.handle_wifi(event_id)
		return
	}
	if a.category == .display || a.category == .battery {
		a.handle_device(event_id)
		return
	}
	if a.category == .power {
		a.handle_power(event_id)
		return
	}
	// Everything below writes a preference, which needs a desktop to write to.
	if a.desktop == unsafe { nil } {
		return
	}
	if a.handle_keyboard(event_id) {
		return
	}
	if event_id.starts_with(settings_action_side) {
		a.desktop.settings.button_side = if event_id.ends_with('1') {
			ButtonSide.left
		} else {
			ButtonSide.right
		}
		return
	}
	if event_id.starts_with(settings_action_taskbar) {
		a.desktop.settings.taskbar_mode = if event_id.ends_with('1') {
			TaskbarMode.combined
		} else {
			TaskbarMode.standard
		}
		return
	}
	if event_id.starts_with(settings_action_clock_format) {
		a.desktop.settings.clock_24_hour = !event_id.ends_with('1')
		return
	}
	if event_id.starts_with(settings_action_clock_seconds) {
		a.desktop.settings.clock_show_seconds = !event_id.ends_with('1')
		return
	}
	if event_id.starts_with(settings_action_clock_date) {
		a.desktop.settings.clock_show_date = !event_id.ends_with('1')
		return
	}
	if event_id.starts_with(settings_action_clock_weekday) {
		a.desktop.settings.clock_show_weekday = !event_id.ends_with('1')
		return
	}
	if event_id.starts_with(settings_action_language) {
		for index, action in settings_language_actions {
			if event_id == action {
				a.desktop.settings.language = desktop_languages[index]
				// This window answers in the new language on its next frame.
				set_desktop_language(a.desktop.settings.language)
				break
			}
		}
		return
	}
	if event_id.starts_with(settings_action_glass) {
		for index, action in settings_glass_actions {
			if event_id == action && index < glass_colors.len && settings_glass_offered() {
				a.desktop.settings.glass_color = index
				break
			}
		}
		return
	}
	if event_id.starts_with(settings_action_theme) {
		if event_id.ends_with('3') {
			if !settings_luna_offered() {
				return
			}
			a.desktop.settings.theme = .windows_xp
			// Windows XP's caption buttons are at the right too.
			a.desktop.settings.button_side = .right
		} else if event_id.ends_with('2') {
			if !settings_glass_offered() {
				return
			}
			a.desktop.settings.theme = .windows7
			// Windows 7's caption buttons are at the right, and a theme chosen
			// afresh starts with its own geometry, as Catalina's does below.
			a.desktop.settings.button_side = .right
		} else if event_id.ends_with('1') {
			a.desktop.settings.theme = .macos
			// A freshly selected Catalina theme starts with Catalina geometry.
			// Appearance remains independent, so the user can deliberately move
			// the controls afterwards.
			a.desktop.settings.button_side = .left
		} else {
			a.desktop.settings.theme = .default_
		}
		return
	}
	if event_id.starts_with(settings_action_color) {
		index := event_id[settings_action_color.len..].int()
		if index >= 0 && index < wallpaper_colors.len {
			a.desktop.settings.wallpaper_color = index
			a.desktop.settings.wallpaper_image = -1
			a.desktop.invalidate_wallpaper()
		}
		return
	}
	if event_id.starts_with(settings_action_image) {
		index := event_id[settings_action_image.len..].int()
		if index >= 0 && index < a.images.len {
			a.desktop.settings.wallpaper_image = index
			a.desktop.invalidate_wallpaper()
		}
		return
	}
}
