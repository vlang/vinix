// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The taskbar's notification area: status icons for the network, battery,
// display and Capture, each with a flyout, and an overflow panel for the icons
// the user has chosen to tuck away.
//
// Devices are sampled on a slow cadence from the compositor loop and only a
// change invalidates the frame. Every string the icons and flyouts show is
// formatted when a sample or the desktop's language changes and retained, so
// an idle rebuild allocates nothing.
module main

import ui2

#include "network_status.h"

fn C.vinix_interface_ipv4(name &char, address &u32) int

const tray_item_count = 4
const tray_icon_actions = ['tray.icon.network', 'tray.icon.battery', 'tray.icon.display',
	'tray.icon.capture']
const tray_overflow_icon_actions = ['tray.overflow.icon.network', 'tray.overflow.icon.battery',
	'tray.overflow.icon.display', 'tray.overflow.icon.capture']
// Persisted by name, one `name hidden|shown` line each.
const tray_item_names = ['network', 'battery', 'display', 'capture']
const tray_preferences_filename = '.vinix-tray'
const action_tray_overflow = 'tray.overflow'
const action_tray_flyout = 'tray.flyout'
const action_tray_network_settings = 'tray.action.network'
const action_tray_power_settings = 'tray.action.power'
const action_tray_display_settings = 'tray.action.display'
const action_tray_brightness_down = 'tray.action.brightness.down'
const action_tray_brightness_up = 'tray.action.brightness.up'
const action_tray_capture_open = 'tray.action.capture.open'
const action_tray_capture_screenshot = 'tray.action.capture.screenshot'
const tray_icon_width = 26
const tray_chevron_width = 18
const tray_sample_ms = i64(5000)
const tray_flyout_width = 264
const tray_ethernet_name = 'eth0'
const tray_battery_glyphs = ['builtin:battery_0', 'builtin:battery_10', 'builtin:battery_20',
	'builtin:battery_30', 'builtin:battery_40', 'builtin:battery_50', 'builtin:battery_60',
	'builtin:battery_70', 'builtin:battery_80', 'builtin:battery_90', 'builtin:battery_100']
const tray_battery_charging_glyphs = ['builtin:battery_charging_0', 'builtin:battery_charging_10',
	'builtin:battery_charging_20', 'builtin:battery_charging_30', 'builtin:battery_charging_40',
	'builtin:battery_charging_50', 'builtin:battery_charging_60', 'builtin:battery_charging_70',
	'builtin:battery_charging_80', 'builtin:battery_charging_90', 'builtin:battery_charging_100']
const tray_flyout_text = u32(0x243044)
const tray_flyout_muted = u32(0x6b778c)
const tray_flyout_button = u32(0xe7edf6)
const tray_flyout_button_hover = u32(0xd4e2f5)

enum TrayItem {
	network
	battery
	display
	capture
}

enum TrayFlyout {
	none_
	network
	battery
	display
	capture
	overflow
	// The input menu; keyboard_layout.v draws it.
	input
}

enum NetworkLink {
	unknown
	absent
	pending
	connected
}

struct TraySample {
	ethernet          NetworkLink
	address           u32
	wifi_present      bool
	wifi_radio        bool
	wifi_networks     int
	battery           int = battery_unavailable
	charging          bool
	backlight_present bool
	backlight_percent int
}

fn (a &TraySample) same(b &TraySample) bool {
	return a.ethernet == b.ethernet && a.address == b.address && a.wifi_present == b.wifi_present
		&& a.wifi_radio == b.wifi_radio && a.wifi_networks == b.wifi_networks
		&& a.battery == b.battery && a.charging == b.charging
		&& a.backlight_present == b.backlight_present
		&& a.backlight_percent == b.backlight_percent
}

struct TrayState {
mut:
	preferences_loaded bool
	// Windows 7 keeps its less important icons in the overflow until asked.
	hide_network bool
	hide_battery bool
	hide_display bool = true
	hide_capture bool = true
	sampled      bool
	sampled_ms   i64
	sample       TraySample
	flyout       TrayFlyout
	// The icon the open flyout points at, and where it was laid out.
	flyout_anchor string
	flyout_x      int
	flyout_y      int
	flyout_width  int
	flyout_height int
	// Formatted from the last sample; all owned, and worded in `language`.
	language       DesktopLanguage
	network_tip    string
	ethernet_line  string
	address_line   string
	wifi_line      string
	battery_tip    string
	battery_line   string
	display_tip    string
	display_line   string
}

fn tray_item_from_index(index int) TrayItem {
	return match index {
		1 { TrayItem.battery }
		2 { TrayItem.display }
		3 { TrayItem.capture }
		else { TrayItem.network }
	}
}

fn tray_flyout_for(item TrayItem) TrayFlyout {
	return match item {
		.network { TrayFlyout.network }
		.battery { TrayFlyout.battery }
		.display { TrayFlyout.display }
		.capture { TrayFlyout.capture }
	}
}

fn (t &TrayState) hidden(item TrayItem) bool {
	return match item {
		.network { t.hide_network }
		.battery { t.hide_battery }
		.display { t.hide_display }
		.capture { t.hide_capture }
	}
}

fn (mut t TrayState) set_hidden(item TrayItem, hidden bool) {
	match item {
		.network { t.hide_network = hidden }
		.battery { t.hide_battery = hidden }
		.display { t.hide_display = hidden }
		.capture { t.hide_capture = hidden }
	}
}

// present says whether an item has anything to report on this machine. A
// desktop computer has no battery, and says nothing about one.
fn (t &TrayState) present(item TrayItem) bool {
	return match item {
		.battery { t.sample.battery >= 0 }
		else { true }
	}
}

fn (t &TrayState) on_taskbar(item TrayItem) bool {
	return t.present(item) && !t.hidden(item)
}

fn (t &TrayState) overflow_count() int {
	mut count := 0
	for index in 0 .. tray_item_count {
		item := tray_item_from_index(index)
		if t.present(item) && t.hidden(item) {
			count++
		}
	}
	return count
}

// ── Preferences ────────────────────────────────────────────────────

fn (mut d Desktop) load_tray_preferences(home string) {
	d.tray.preferences_loaded = true
	path := home_file_path(home, tray_preferences_filename)
	buffer := read_small_file(path, 1024)
	unsafe { path.free() }
	mut start := 0
	for offset := 0; offset <= buffer.len; offset++ {
		if offset < buffer.len && buffer[offset] != `\n` {
			continue
		}
		if offset > start {
			line := unsafe { tos(&u8(buffer.data) + start, offset - start) }
			for index, name in tray_item_names {
				if line.len == name.len + 7 && line.starts_with(name) && line.ends_with(' hidden') {
					d.tray.set_hidden(tray_item_from_index(index), true)
				} else if line.len == name.len + 6 && line.starts_with(name)
					&& line.ends_with(' shown') {
					d.tray.set_hidden(tray_item_from_index(index), false)
				}
			}
		}
		start = offset + 1
	}
	if buffer.cap > 0 {
		unsafe { buffer.free() }
	}
}

fn (d &Desktop) save_tray_preferences(home string) bool {
	mut text := []u8{cap: 96}
	defer { unsafe { text.free() } }
	for index, name in tray_item_names {
		for ch in name {
			text << ch
		}
		state := if d.tray.hidden(tray_item_from_index(index)) { ' hidden\n' } else { ' shown\n' }
		for ch in state {
			text << ch
		}
	}
	path := home_file_path(home, tray_preferences_filename)
	defer { unsafe { path.free() } }
	return desktop_write_file(path, text.data, u64(text.len))
}

fn (mut d Desktop) set_tray_item_hidden_in(home string, item TrayItem, hidden bool) {
	if d.tray.hidden(item) == hidden {
		return
	}
	d.tray.set_hidden(item, hidden)
	if !d.save_tray_preferences(home) {
		eprintln('vinix-desktop: could not save notification area preferences')
	}
	d.close_tray_flyout()
	d.dirty = true
}

// ── Sampling ───────────────────────────────────────────────────────

fn sample_ethernet() (NetworkLink, u32) {
	mut address := u32(0)
	result := C.vinix_interface_ipv4(&char(tray_ethernet_name.str), &address)
	if result == 0 && address != 0 {
		return .connected, address
	}
	if result == 0 || result == C.EADDRNOTAVAIL {
		return .pending, u32(0)
	}
	return .absent, u32(0)
}

fn ipv4_text(address u32) string {
	return '${address & 0xff}.${(address >> 8) & 0xff}.${(address >> 16) & 0xff}.${address >> 24}'
}

fn (mut d Desktop) update_tray() {
	d.update_tray_at(monotonic_millis(), false)
}

fn (mut d Desktop) update_tray_at(now i64, force bool) {
	if !d.tray.preferences_loaded {
		d.load_tray_preferences(d.home)
	}
	// Text worded in another language is rewritten from the sample it
	// describes; the devices need not be read again for that.
	if d.tray.sampled && d.tray.language != desktop_language {
		d.format_tray_text()
	}
	if !force && d.tray.sampled && now >= d.tray.sampled_ms
		&& now - d.tray.sampled_ms < tray_sample_ms {
		return
	}
	d.tray.sampled_ms = now
	ethernet, address := sample_ethernet()
	mut wifi_present := false
	mut wifi_radio := false
	mut wifi_networks := 0
	if desktop_stat(wifi_path) != none {
		wifi_present = true
		mut state := WifiState{}
		if read_wifi(mut state) == .ok {
			wifi_radio = state.radio_on
			wifi_networks = state.count
		}
	}
	battery := battery_get(force)
	mut backlight := BacklightState{}
	mut backlight_present := false
	mut brightness := 0
	if read_backlight(mut backlight) == .ok && backlight.online {
		percent := backlight_percent(&backlight)
		if percent >= 0 {
			backlight_present = true
			brightness = percent
		}
	}
	d.apply_tray_sample(TraySample{
		ethernet:          ethernet
		address:           address
		wifi_present:      wifi_present
		wifi_radio:        wifi_radio
		wifi_networks:     wifi_networks
		battery:           battery
		charging:          desktop_battery_cache.history.trend == .charging
		backlight_present: backlight_present
		backlight_percent: brightness
	})
}

// set_owned_text stores a formatted string, or a literal, which V's free
// leaves alone, and releases the one it replaces. Text from tr() belongs to
// the translation table, so it is cloned before it is stored here.
fn set_owned_text(slot string, text string) string {
	if slot.len > 0 {
		unsafe { slot.free() }
	}
	return text
}

// apply_tray_sample reformats the retained strings only when what the icons
// report, or the language they report it in, has changed. It is separate from
// sampling so tests can supply one.
fn (mut d Desktop) apply_tray_sample(sample TraySample) {
	if d.tray.sampled && d.tray.sample.same(sample) && d.tray.language == desktop_language {
		return
	}
	d.tray.sampled = true
	d.tray.sample = sample
	d.format_tray_text()
}

// format_tray_text words the retained strings for the current sample in the
// desktop's language.
fn (mut d Desktop) format_tray_text() {
	sample := d.tray.sample
	d.tray.language = desktop_language
	address := if sample.ethernet == .connected { ipv4_text(sample.address) } else { '' }
	d.tray.ethernet_line = set_owned_text(d.tray.ethernet_line, match sample.ethernet {
		.connected { tr('tray.ethernet.connected').clone() }
		.pending { tr('tray.ethernet.acquiring').clone() }
		.absent { tr('tray.ethernet.no_adapter').clone() }
		.unknown { tr('tray.ethernet.checking').clone() }
	})
	d.tray.wifi_line = set_owned_text(d.tray.wifi_line, if !sample.wifi_present {
		tr('tray.wifi.no_adapter').clone()
	} else if !sample.wifi_radio {
		tr('tray.wifi.off').clone()
	} else {
		tr_count('tray.wifi.networks_nearby', sample.wifi_networks)
	})
	d.tray.address_line = set_owned_text(d.tray.address_line, if address.len > 0 {
		tr_fill('tray.network.ipv4_address', address)
	} else {
		''
	})
	d.tray.network_tip = set_owned_text(d.tray.network_tip, if sample.ethernet == .connected {
		tr_fill('tray.network.ethernet_address', address)
	} else if sample.ethernet == .pending {
		tr('tray.ethernet.acquiring').clone()
	} else if sample.wifi_present && sample.wifi_radio {
		tr('tray.wifi.not_connected').clone()
	} else {
		tr('tray.network.not_connected').clone()
	})
	if address.len > 0 {
		unsafe { address.free() }
	}
	percent := battery_percentage_text(sample.battery)
	d.tray.battery_tip = set_owned_text(d.tray.battery_tip, if sample.charging {
		tr_fill('tray.battery.tip_charging', percent)
	} else {
		tr_fill('tray.battery.tip_remaining', percent)
	})
	estimate := desktop_battery_cache.history.remaining_hours(sample.battery)
	d.tray.battery_line = set_owned_text(d.tray.battery_line, battery_remaining_text(estimate).clone())
	brightness := if sample.backlight_present { sample.backlight_percent.str() } else { '' }
	d.tray.display_tip = set_owned_text(d.tray.display_tip, if sample.backlight_present {
		tr_fill('tray.display.tip_brightness', brightness)
	} else {
		tr('tray.display.heading').clone()
	})
	d.tray.display_line = set_owned_text(d.tray.display_line, if sample.backlight_present {
		tr_fill('tray.display.brightness', brightness)
	} else {
		tr('tray.display.no_backlight').clone()
	})
	if brightness.len > 0 {
		unsafe { brightness.free() }
	}
	d.dirty = true
}

// ── Glyphs ─────────────────────────────────────────────────────────

fn (d &Desktop) tray_glyph(item TrayItem) string {
	match item {
		.network {
			return match d.tray.sample.ethernet {
				.connected {
					'builtin:network_wired'
				}
				.pending {
					'builtin:network_pending'
				}
				else {
					if d.tray.sample.wifi_present && d.tray.sample.wifi_radio {
						'builtin:network_wifi'
					} else {
						'builtin:network_offline'
					}
				}
			}
		}
		.battery {
			mut level := (d.tray.sample.battery + 5) / 10
			if level < 0 {
				level = 0
			}
			if level > 10 {
				level = 10
			}
			return if d.tray.sample.charging {
				tray_battery_charging_glyphs[level]
			} else {
				tray_battery_glyphs[level]
			}
		}
		.display {
			return 'builtin:brightness'
		}
		.capture {
			return if d.capture.report.phase == .recording {
				'builtin:record'
			} else {
				'builtin:camera'
			}
		}
	}
}

// ── Taskbar icons ──────────────────────────────────────────────────

fn (d &Desktop) tray_width() int {
	mut width := 0
	for index in 0 .. tray_item_count {
		if d.tray.on_taskbar(tray_item_from_index(index)) {
			width += tray_icon_width
		}
	}
	if d.tray.overflow_count() > 0 {
		width += tray_chevron_width + 2
	}
	return width
}

fn (d &Desktop) tray_icon_element(id string, glyph string, x int, y int, width int, height int,
	open bool) ui2.Element {
	theme := d.theme()
	hovered := d.hover == id
	return ui2.button_with_image(id, '', glyph, ui2.rect(f64(x), f64(y), f64(width), f64(height)),
		ui2.BoxStyle{
		bg:          if open { theme.taskbar_item_active } else { theme.taskbar_item_hover }
		radius:      4
		transparent: !hovered && !open
	}, ui2.TextStyle{
		color: theme.taskbar_text_active
	})
}

// The overflow panel is light, so its icons are drawn dark on it.
fn (d &Desktop) tray_overflow_icon_element(id string, glyph string, x int, y int) ui2.Element {
	return ui2.button_with_image(id, '', glyph, ui2.rect(f64(x), f64(y), f64(tray_icon_width + 6),
		32), ui2.BoxStyle{
		bg:          tray_flyout_button_hover
		radius:      4
		transparent: d.hover != id
	}, ui2.TextStyle{
		color: tray_flyout_text
	})
}

fn (d &Desktop) tray_elements(mut children []ui2.Element, x int, y int, height int) {
	mut at := x
	if d.tray.overflow_count() > 0 {
		children << d.tray_icon_element(action_tray_overflow, 'builtin:chevron_up', at, y,
			tray_chevron_width, height, d.tray.flyout == .overflow)
		at += tray_chevron_width + 2
	}
	for index in 0 .. tray_item_count {
		item := tray_item_from_index(index)
		if !d.tray.on_taskbar(item) {
			continue
		}
		children << d.tray_icon_element(tray_icon_actions[index], d.tray_glyph(item), at, y,
			tray_icon_width, height, d.tray.flyout == tray_flyout_for(item))
		at += tray_icon_width
	}
}

fn (d &Desktop) tooltip_text(action string) string {
	return match action {
		action_window_overview { tr('desktop.overview.title') }
		action_show_desktop { tr('tray.show_desktop') }
		action_tray_overflow { tr('tray.show_hidden_icons') }
		action_tray_input { keyboard_layout_text(d.settings.keyboard_layout) }
		'tray.icon.network', 'tray.overflow.icon.network' { d.tray.network_tip }
		'tray.icon.battery', 'tray.overflow.icon.battery' { d.tray.battery_tip }
		'tray.icon.display', 'tray.overflow.icon.display' { d.tray.display_tip }
		'tray.icon.capture', 'tray.overflow.icon.capture' {
			if d.capture.report.phase == .recording {
				tr('tray.capture.tip_recording')
			} else {
				tr('app.capture')
			}
		}
		else { '' }
	}
}

// ── Flyouts ────────────────────────────────────────────────────────

fn tray_item_for_action(action string) ?TrayItem {
	for index in 0 .. tray_item_count {
		if action == tray_icon_actions[index] || action == tray_overflow_icon_actions[index] {
			return tray_item_from_index(index)
		}
	}
	return none
}

fn (mut d Desktop) open_tray_flyout(flyout TrayFlyout, anchor string) {
	d.close_start_menu()
	d.close_taskbar_preview()
	d.hide_tooltip()
	d.tray.flyout = flyout
	d.tray.flyout_anchor = replace_owned(d.tray.flyout_anchor, anchor)
	if flyout != .overflow && flyout != .capture && flyout != .input {
		// Read the device again rather than show a five-second-old sample.
		d.update_tray_at(monotonic_millis(), true)
	}
	d.dirty = true
}

fn (mut d Desktop) close_tray_flyout() {
	if d.tray.flyout == .none_ {
		return
	}
	d.tray.flyout = .none_
	d.tray.flyout_width = 0
	d.tray.flyout_height = 0
	d.tray.flyout_anchor = replace_owned(d.tray.flyout_anchor, '')
	d.dirty = true
}

fn (mut d Desktop) handle_tray_action(action string) {
	if action == action_tray_flyout {
		return
	}
	if action == action_tray_overflow {
		if d.tray.flyout == .overflow {
			d.close_tray_flyout()
		} else {
			d.open_tray_flyout(.overflow, action_tray_overflow)
		}
		return
	}
	if action == action_tray_input {
		if d.tray.flyout == .input {
			d.close_tray_flyout()
		} else {
			d.open_tray_flyout(.input, action_tray_input)
		}
		return
	}
	if action.starts_with(tray_input_layout_prefix) {
		d.choose_input_source(action[tray_input_layout_prefix.len..].int())
		return
	}
	if item := tray_item_for_action(action) {
		flyout := tray_flyout_for(item)
		if d.tray.flyout == flyout {
			d.close_tray_flyout()
			return
		}
		// An icon inside the overflow panel opens its flyout from the chevron,
		// which is the part of the taskbar that is still there once it closes.
		anchor := if action.starts_with('tray.overflow.') { action_tray_overflow } else { action }
		d.open_tray_flyout(flyout, anchor)
		return
	}
	match action {
		action_tray_network_settings {
			d.close_tray_flyout()
			d.open_settings_category(.wifi)
		}
		action_tray_power_settings {
			d.close_tray_flyout()
			d.open_settings_category(.battery)
		}
		action_tray_display_settings {
			d.close_tray_flyout()
			d.open_settings_category(.display)
		}
		action_tray_keyboard_settings {
			d.close_tray_flyout()
			d.open_settings_category(.keyboard)
		}
		action_tray_brightness_down, action_tray_brightness_up {
			adjust_brightness(if action == action_tray_brightness_up {
				brightness_step
			} else {
				-brightness_step
			})
			d.update_tray_at(monotonic_millis(), true)
		}
		action_tray_capture_open {
			d.close_tray_flyout()
			d.open_capture_window()
		}
		action_tray_capture_screenshot {
			d.close_tray_flyout()
			if id := d.open_capture_window() {
				d.capture_from_window(id, capture_action_take_screenshot)
			}
		}
		else {}
	}
}

// open_settings_category brings up Settings on one of its panes, reusing a
// Settings window that is already open.
fn (mut d Desktop) open_settings_category(category SettingsCategory) {
	settings_index := shortcut_app_index_named('vinix-settings')
	mut window_id := d.taskbar_window_for_app(settings_index)
	if window_id != 0 {
		d.activate(window_id)
	} else {
		window_id = d.launch_index_window(settings_index)
	}
	mut slot := -1
	for index, candidate in settings_categories {
		if candidate == category {
			slot = index
		}
	}
	if window_id == 0 || slot < 0 {
		return
	}
	event := '${settings_action_category}${slot}'
	d.send_to_window(window_id, event)
	unsafe { event.free() }
}

fn (mut d Desktop) open_capture_window() ?int {
	capture_index := shortcut_app_index_named('vinix-capture')
	mut window_id := d.taskbar_window_for_app(capture_index)
	if window_id != 0 {
		d.activate(window_id)
	} else {
		window_id = d.launch_index_window(capture_index)
	}
	if window_id == 0 {
		return none
	}
	return window_id
}

// capture_from_window starts a Capture action the way its own button does:
// the compositor records the owner and hides it before the first frame.
fn (mut d Desktop) capture_from_window(window_id int, action string) {
	index := d.window_index(window_id) or { return }
	app_index := d.windows[index].app_index
	if app_index < 0 || app_index >= d.apps.len {
		return
	}
	d.apps[app_index].handle(action) or {
		eprintln('vinix-desktop: Capture: ${err}')
		return
	}
	d.capture.owner_window_id = window_id
	d.minimize(window_id)
	d.dirty = true
}

fn (d &Desktop) tray_flyout_button(id string, title string, x int, y int, width int) ui2.Element {
	return ui2.button(id, title, ui2.rect(f64(x), f64(y), f64(width), 28), ui2.BoxStyle{
		bg:     if d.hover == id { tray_flyout_button_hover } else { tray_flyout_button }
		radius: 5
	}, ui2.TextStyle{
		color: tray_flyout_text
		size:  12
		align: .center
	})
}

fn tray_flyout_heading(text string, x int, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(x), f64(y), f64(width), 20), ui2.TextStyle{
		color: tray_flyout_text
		size:  13
		bold:  true
	})
}

fn tray_flyout_line(text string, x int, y int, width int, muted bool) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(x), f64(y), f64(width), 18), ui2.TextStyle{
		color: if muted { tray_flyout_muted } else { tray_flyout_text }
		size:  12
	})
}

fn (mut d Desktop) tray_flyout_element() ?ui2.Element {
	if d.tray.flyout == .none_ {
		return none
	}
	pad := 14
	inner := tray_flyout_width - 2 * pad
	mut children := frame_elements(10)
	mut height := 0
	mut width := tray_flyout_width
	match d.tray.flyout {
		.network {
			children << tray_flyout_heading(tr('tray.network.heading'), pad, 12, inner)
			children << ui2.button_with_image('', '', d.tray_glyph(.network), ui2.rect(f64(pad), 40,
				28, 28), ui2.BoxStyle{
				transparent: true
			}, ui2.TextStyle{
				color: files_folder_icon
			})
			children << tray_flyout_line(d.tray.ethernet_line, pad + 38, 38, inner - 38, false)
			children << tray_flyout_line(if d.tray.address_line.len > 0 {
				d.tray.address_line
			} else {
				tr('tray.network.no_ipv4')
			}, pad + 38, 56, inner - 38, true)
			children << tray_flyout_line(d.tray.wifi_line, pad + 38, 80, inner - 38, false)
			children << d.tray_flyout_button(action_tray_network_settings, tr('tray.network.settings'),
				pad, 110, inner)
			height = 152
		}
		.battery {
			children << tray_flyout_heading(tr('tray.battery.heading'), pad, 12, inner)
			children << ui2.label('', battery_percentage_text(d.tray.sample.battery), ui2.rect(f64(pad),
				36, f64(inner), 34), ui2.TextStyle{
				color: tray_flyout_text
				size:  26
				bold:  true
			})
			children << tray_flyout_line(if d.tray.sample.charging {
				tr('tray.battery.charging')
			} else {
				d.tray.battery_line
			}, pad, 74, inner, true)
			children << d.tray_flyout_button(action_tray_power_settings, tr('tray.battery.settings'),
				pad, 102, inner)
			height = 144
		}
		.display {
			children << tray_flyout_heading(tr('tray.display.heading'), pad, 12, inner)
			children << tray_flyout_line(d.tray.display_line, pad, 40, inner, !d.tray.sample.backlight_present)
			mut y := 66
			if d.tray.sample.backlight_present {
				half := (inner - 8) / 2
				children << d.tray_flyout_button(action_tray_brightness_down, tr('tray.display.dimmer'),
					pad, y, half)
				children << d.tray_flyout_button(action_tray_brightness_up, tr('tray.display.brighter'),
					pad + half + 8, y, half)
				y += 36
			}
			children << d.tray_flyout_button(action_tray_display_settings, tr('tray.display.settings'),
				pad, y, inner)
			height = y + 42
		}
		.capture {
			children << tray_flyout_heading(tr('app.capture'), pad, 12, inner)
			children << tray_flyout_line(if d.capture.report.phase == .recording {
				tr('tray.capture.recording')
			} else {
				tr('tray.capture.note')
			}, pad, 40, inner, true)
			children << d.tray_flyout_button(action_tray_capture_screenshot, tr('tray.capture.screenshot'),
				pad, 66, inner)
			children << d.tray_flyout_button(action_tray_capture_open, tr('tray.capture.open'),
				pad, 102, inner)
			height = 144
		}
		.overflow {
			mut count := 0
			for index in 0 .. tray_item_count {
				item := tray_item_from_index(index)
				if !d.tray.present(item) || !d.tray.hidden(item) {
					continue
				}
				children << d.tray_overflow_icon_element(tray_overflow_icon_actions[index],
					d.tray_glyph(item), 8 + count * (tray_icon_width + 6), 8)
				count++
			}
			hint := tr('tray.overflow.hint')
			hint_style := ui2.TextStyle{
				color: tray_flyout_muted
				size:  11
			}
			// Wide enough for the hint under the icons, in whichever language.
			mut least := 132
			if d.fonts.len > 0 {
				hint_width := d.face_for(hint_style).text_width(hint) + 20
				if hint_width > least {
					least = hint_width
				}
			}
			width = 16 + count * (tray_icon_width + 6)
			if width < least {
				width = least
			}
			children << ui2.label('', hint, ui2.rect(10, 44, f64(width - 20), 16), hint_style)
			height = 68
		}
		.input {
			if !d.input_menu_shown() {
				// Settings turned the other input sources off under it.
				d.close_tray_flyout()
				return none
			}
			width = tray_input_menu_width
			height = d.input_menu_children(mut children)
		}
		.none_ {}
	}
	mut anchor_x := d.canvas.width - width
	if target := d.hit_target_named(d.tray.flyout_anchor) {
		anchor_x = target.x + target.width / 2
	}
	mut x := anchor_x - width / 2
	if x + width > d.canvas.width - 6 {
		x = d.canvas.width - 6 - width
	}
	if x < 6 {
		x = 6
	}
	y := d.canvas.height - taskbar_height - height - 6
	d.tray.flyout_x = x
	d.tray.flyout_y = y
	d.tray.flyout_width = width
	d.tray.flyout_height = height
	return ui2.clickable_view(action_tray_flyout, ui2.rect(f64(x), f64(y), f64(width),
		f64(height)), ui2.BoxStyle{
		bg:     app_surface
		radius: 8
	}, children)
}
