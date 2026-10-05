// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import io.util
import ui2

const activity_startup_filename = '.vinix-startup-apps'
const activity_startup_limit = 16384
const activity_startup_timings_filename = '.vinix-startup-timings'

struct ActivityStartup {
mut:
	enabled      [32]bool
	actions      [32]string
	timing_ms    [32]u64
	timing_known [32]bool
	timing_text  [32]string
	home         string
	language     DesktopLanguage
	loaded       bool
	failed       bool
	scroll       int
}

fn activity_startup_defaults(development bool) ActivityStartup {
	mut model := ActivityStartup{}
	for index, app in available_apps {
		if index >= model.enabled.len { break }
		model.enabled[index] = app.title == 'Files' || (development && app.title == 'Terminal')
	}
	return model
}

// Store stable executable names; catalog reorderings cannot change the apps
// a saved configuration enables. Unknown/duplicate lines are harmless.
fn activity_startup_parse(record string) ActivityStartup {
	mut model := ActivityStartup{}
	mut start := 0
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		for index, app in available_apps {
			if index >= model.enabled.len { break }
			if end - start != app.process_name.len { continue }
			mut matches := true
			for offset, byte in app.process_name {
				if record[start + offset] != byte {
					matches = false
					break
				}
			}
			if matches { model.enabled[index] = true }
		}
		start = end + 1
	}
	return model
}

fn activity_startup_load(home string, development bool) ActivityStartup {
	mut model := activity_startup_defaults(development)
	path := '${home}/${activity_startup_filename}'
	defer { unsafe { path.free() } }
	info := os.lstat(path) or { return model }
	if info.get_filetype() != .regular || info.size > activity_startup_limit { return model }
	record := os.read_file(path) or { return model }
	defer { unsafe { record.free() } }
	model = activity_startup_parse(record)
	return model
}

// A separate record keeps the last successful startup handshake duration for
// each stable executable name. It measures launch latency, not CPU impact.
fn activity_startup_timings_parse(mut model ActivityStartup, record string) {
	mut start := 0
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		mut separator := start
		for separator < end && record[separator] != `\t` { separator++ }
		if separator >= end {
			start = end + 1
			continue
		}
		mut value := u64(0)
		mut valid := separator + 1 < end
		for at := separator + 1; at < end; at++ {
			byte := record[at]
			if byte < `0` || byte > `9` || value > (u64(-1) - u64(byte - `0`)) / 10 {
				valid = false
				break
			}
			value = value * 10 + u64(byte - `0`)
		}
		if valid {
			for index, app in available_apps {
				if index >= model.timing_ms.len { break }
				if app.process_name.len != separator - start { continue }
				mut matches := true
				for offset, byte in app.process_name {
					if record[start + offset] != byte {
						matches = false
						break
					}
				}
				if matches {
					model.timing_ms[index] = value
					model.timing_known[index] = true
				}
			}
		}
		start = end + 1
	}
}

fn (model &ActivityStartup) encode_timings() string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	for index, app in available_apps {
		if index >= model.timing_ms.len { break }
		if !model.timing_known[index] { continue }
		for byte in app.process_name { bytes << byte }
		bytes << `\t`
		milliseconds := model.timing_ms[index].str()
		for byte in milliseconds { bytes << byte }
		unsafe { milliseconds.free() }
		bytes << `\n`
	}
	data := if bytes.len > 0 { unsafe { tos(bytes.data, bytes.len).clone() } } else { '' }
	unsafe { bytes.free() }
	return data
}

fn activity_startup_timings_load(mut model ActivityStartup, home string) {
	path := '${home}/${activity_startup_timings_filename}'
	defer { unsafe { path.free() } }
	info := os.lstat(path) or { return }
	if info.get_filetype() != .regular || info.size > activity_startup_limit { return }
	record := os.read_file(path) or { return }
	defer { unsafe { record.free() } }
	activity_startup_timings_parse(mut model, record)
}

fn (mut model ActivityStartup) refresh_timing_text() {
	model.language = desktop_language
	for index, _ in available_apps {
		if index >= model.timing_text.len { break }
		if model.timing_known[index] {
			milliseconds := model.timing_ms[index].str()
			model.timing_text[index] = replace_activity_text(model.timing_text[index], tr_fill('activity.startup.launch_ms', milliseconds))
			unsafe { milliseconds.free() }
		} else {
			model.timing_text[index] = replace_activity_text(model.timing_text[index], tr('activity.startup.not_measured').clone())
		}
	}
}

fn (mut model ActivityStartup) load_in(home string, development bool) {
	if model.loaded { return }
	model = activity_startup_load(home, development)
	model.home = home.clone()
	activity_startup_timings_load(mut model, home)
	model.loaded = true
	for index, _ in available_apps {
		if index >= model.actions.len { break }
		index_text := index.str()
		model.actions[index] = 'activity.startup.toggle.${index_text}'
		unsafe { index_text.free() }
	}
	model.refresh_timing_text()
}

fn (model &ActivityStartup) encode() string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	for index, app in available_apps {
		if index >= model.enabled.len { break }
		if model.enabled[index] {
			for byte in app.process_name { bytes << byte }
			bytes << `\n`
		}
	}
	data := bytes.bytestr()
	unsafe { bytes.free() }
	return data
}

// Also used for diagnostic reports: publish through a synced temporary file
// so a interrupted write cannot replace the previous complete record.
fn activity_write_record(home string, filename string, data string) bool {
	if home == '' || !os.is_dir(home) { return false }
	mut file, temporary := util.temp_file(path: home, pattern: '.vinix-activity.*') or { return false }
	mut published := false
	defer {
		file.close()
		if !published { os.rm(temporary) or {} }
		unsafe { temporary.free() }
	}
	if !desktop_write_all(file.fd, data.str, u64(data.len)) || !desktop_preferences_fsync(file.fd) {
		return false
	}
	path := '${home}/${filename}'
	defer { unsafe { path.free() } }
	os.rename_dir(temporary, path) or { return false }
	published = true
	return desktop_preferences_sync_directory(home, file.fd)
}

fn (mut model ActivityStartup) load() {
	model.load_in(if desktop_user_home != '' { desktop_user_home } else { desktop_home }, desktop_is_development_session())
}

fn (mut model ActivityStartup) handle(action string) bool {
	model.load()
	if action == 'activity.startup.up' {
		if model.scroll > 0 { model.scroll-- }
		return true
	}
	if action == 'activity.startup.down' {
		if model.scroll < available_apps.len - 1 { model.scroll++ }
		return true
	}
	if !action.starts_with('activity.startup.toggle.') { return false }
	mut index := 0
	if action.len <= 'activity.startup.toggle.'.len { return true }
	for offset in 'activity.startup.toggle.'.len .. action.len {
		byte := action[offset]
		if byte < `0` || byte > `9` || index > 32 { return true }
		index = index * 10 + int(byte - `0`)
	}
	if index < 0 || index >= available_apps.len || index >= model.enabled.len { return true }
	model.enabled[index] = !model.enabled[index]
	data := model.encode()
	model.failed = !activity_write_record(model.home, activity_startup_filename, data)
	unsafe { data.free() }
	return true
}

fn (mut model ActivityStartup) build(width int, height int) ui2.Element {
	model.load()
	if model.language != desktop_language { model.refresh_timing_text() }
	mut children := frame_elements(available_apps.len * 3 + 8)
	compact := width < 480
	row_height := if compact { 48 } else { 32 }
	header_height := if height >= 150 { 54 } else if height >= 110 { 32 } else { 4 }
	footer_height := if height >= 150 { 48 } else { 30 }
	if header_height > 4 {
		children << ui2.label('', tr('activity.startup.description'), ui2.rect(12, 8, f64(width - 24), f64(header_height - 12)), ui2.TextStyle{ color: body_text, size: 12 })
	}
	fit := (height - header_height - footer_height) / row_height
	visible := if fit > 0 { fit } else { 1 }
	maximum := if available_apps.len > visible { available_apps.len - visible } else { 0 }
	if model.scroll > maximum { model.scroll = maximum }
	for index := model.scroll; index < available_apps.len && index < model.scroll + visible; index++ {
		app := available_apps[index]
		y := header_height + (index - model.scroll) * row_height
		title := app_title_text(app.title)
		children << ui2.Element{
			...ui2.label('', title, ui2.rect(16, f64(y), f64(if compact { width - 128 } else { width - 290 }), 24), ui2.TextStyle{ color: body_text, size: 13 })
			tooltip: title
		}
		children << ui2.Element{
			...ui2.label('', model.timing_text[index], if compact {
				ui2.rect(16, f64(y + 27), f64(width - 32), 18)
			} else { ui2.rect(f64(width - 264), f64(y), 134, 28) }, ui2.TextStyle{ color: body_muted, size: 11, align: if compact { ui2.Align.left } else { ui2.Align.right } })
			tooltip: model.timing_text[index]
		}
		children << activity_toolbar_button(model.actions[index], if model.enabled[index] {
			tr('activity.startup.enabled')
		} else {
			tr('activity.startup.disabled')
		}, if compact { width - 96 } else { width - 118 }, y, if compact { 84 } else { 100 }, model.enabled[index])
	}
	footer_y := height - footer_height
	children << ui2.Element{
		...activity_toolbar_button('activity.startup.up', '<', width - 64, footer_y, 24, false)
		tooltip: tr('activity.scroll_up')
		accessibility_label: tr('activity.scroll_up')
	}
	children << ui2.Element{
		...activity_toolbar_button('activity.startup.down', '>', width - 34, footer_y, 24, false)
		tooltip: tr('activity.scroll_down')
		accessibility_label: tr('activity.scroll_down')
	}
	note := if model.failed {
		tr('activity.startup.save_failed')
	} else {
		tr('activity.startup.launch_note')
	}
	children << ui2.Element{
		...ui2.label('', note, ui2.rect(12, f64(footer_y), f64(width - 86), f64(footer_height - 4)), ui2.TextStyle{ color: body_text, size: 11 })
		tooltip: note
	}
	return ui2.view('activity.startup.body', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ bg: app_surface }, children)
}

fn (mut model ActivityStartup) free() {
	for mut action in model.actions {
		unsafe { action.free() }
		action = ''
	}
	for mut text in model.timing_text {
		unsafe { text.free() }
		text = ''
	}
	unsafe { model.home.free() }
	model.home = ''
}

fn (mut desktop Desktop) launch_startup_measured(mut model ActivityStartup, index int) bool {
	if index < 0 || index >= available_apps.len || index >= model.timing_ms.len { return false }
	before := desktop.apps.len
	start := monotonic_millis()
	desktop.launch_titled_at_startup(available_apps[index].title)
	elapsed := monotonic_millis() - start
	// A native application is appended only after its first successful tree
	// response. Missing packages, failed handshakes and queued external apps
	// do not produce measurements.
	if desktop.apps.len <= before || elapsed < 0 { return false }
	model.timing_ms[index] = u64(elapsed)
	model.timing_known[index] = true
	return true
}

fn (mut desktop Desktop) launch_configured_startup(install_terminal bool) {
	home := if desktop_user_home != '' { desktop_user_home } else { desktop_home }
	mut model := activity_startup_load(home, desktop_is_development_session())
	activity_startup_timings_load(mut model, home)
	mut terminal_launched := false
	mut measured := false
	for index, app in available_apps {
		if index >= model.enabled.len { break }
		if model.enabled[index] {
			if desktop.launch_startup_measured(mut model, index) { measured = true }
			if app.title == 'Terminal' { terminal_launched = true }
		}
	}
	if install_terminal && !terminal_launched {
		for index, app in available_apps {
			if app.title == 'Terminal' && desktop.launch_startup_measured(mut model, index) {
				measured = true
				break
			}
		}
	}
	if measured {
		data := model.encode_timings()
		if !activity_write_record(home, activity_startup_timings_filename, data) {
			eprintln('vinix-desktop: could not save startup launch timings')
		}
		unsafe { data.free() }
	}
}
