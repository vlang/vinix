// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Recently used documents, folders and programs, and the Start menu's pins.
//
// Documents and folders are recorded by the application processes that open
// them (Files and Text Editor), because only they know what they opened. The
// compositor reads the shared file when it builds a Jump List or the Start
// menu's Recent Items pane. Programs are recorded by the compositor, which is
// what launches them. Every list is stored by process name so reordering the
// application catalog cannot turn an entry into a different program.
module main

const recent_items_filename = '.vinix-recent-items'
const recent_programs_filename = '.vinix-recent-programs'
const start_pins_filename = '.vinix-start-pins'
const recent_items_file_limit = 32768
const app_name_list_file_limit = 4096
// A Jump List shows this many of one application's items; the file keeps a
// bounded history across all of them.
const recent_items_per_app = 8
const recent_items_limit = 64
const recent_programs_limit = 12
const recent_item_max_path = 1024

struct RecentItem {
	app  string
	path string
}

fn home_file_path(home string, name string) string {
	return '${home}/${name}'
}

// read_small_file returns an owned buffer, or an empty one for a missing,
// empty or oversized file. None of these lists is worth failing a frame over.
fn read_small_file(path string, limit int) []u8 {
	info := desktop_stat(path) or { return []u8{} }
	if info.size == 0 || info.size > u64(limit) {
		return []u8{}
	}
	mut buffer := []u8{len: int(info.size)}
	got := desktop_read_file(path, buffer.data, info.size)
	if got <= 0 {
		unsafe { buffer.free() }
		return []u8{}
	}
	if got < i64(buffer.len) {
		buffer.trim(int(got))
	}
	return buffer
}

// load_app_name_list reads one process name per line and returns catalog
// indices in file order. Unknown and repeated names are dropped.
fn load_app_name_list(path string, limit int) []int {
	buffer := read_small_file(path, app_name_list_file_limit)
	mut apps := []int{cap: if limit < available_apps.len { limit } else { available_apps.len }}
	mut start := 0
	for offset := 0; offset <= buffer.len; offset++ {
		if offset < buffer.len && buffer[offset] != `\n` {
			continue
		}
		mut end := offset
		if end > start && buffer[end - 1] == `\r` {
			end--
		}
		if end > start && apps.len < limit {
			name := unsafe { tos(&u8(buffer.data) + start, end - start) }
			index := shortcut_app_index_named(name)
			if index >= 0 && !shortcut_order_contains(apps, index) {
				apps << index
			}
		}
		start = offset + 1
	}
	if buffer.cap > 0 {
		unsafe { buffer.free() }
	}
	return apps
}

fn save_app_name_list(path string, apps []int) bool {
	mut bytes := []u8{cap: apps.len * 24}
	defer { unsafe { bytes.free() } }
	for index in apps {
		if index < 0 || index >= available_apps.len {
			return false
		}
		for ch in available_apps[index].process_name {
			bytes << ch
		}
		bytes << `\n`
	}
	data := if bytes.len > 0 { voidptr(bytes.data) } else { voidptr(unsafe { nil }) }
	return desktop_write_file(path, data, u64(bytes.len))
}

// ── Documents and folders ──────────────────────────────────────────

fn free_recent_items(items []RecentItem) {
	for item in items {
		unsafe {
			item.app.free()
			item.path.free()
		}
	}
	if items.cap > 0 {
		unsafe { items.free() }
	}
}

// load_recent_items parses `process-name TAB path` lines, most recent first.
fn load_recent_items(home string) []RecentItem {
	path := home_file_path(home, recent_items_filename)
	buffer := read_small_file(path, recent_items_file_limit)
	unsafe { path.free() }
	mut items := []RecentItem{cap: recent_items_limit}
	mut start := 0
	for offset := 0; offset <= buffer.len; offset++ {
		if offset < buffer.len && buffer[offset] != `\n` {
			continue
		}
		mut end := offset
		if end > start && buffer[end - 1] == `\r` {
			end--
		}
		mut tab := -1
		for at in start .. end {
			if buffer[at] == `\t` {
				tab = at
				break
			}
		}
		if tab > start && end > tab + 1 && end - tab - 1 <= recent_item_max_path
			&& items.len < recent_items_limit {
			items << RecentItem{
				app:  unsafe { tos(&u8(buffer.data) + start, tab - start) }.clone()
				path: unsafe { tos(&u8(buffer.data) + tab + 1, end - tab - 1) }.clone()
			}
		}
		start = offset + 1
	}
	if buffer.cap > 0 {
		unsafe { buffer.free() }
	}
	return items
}

fn save_recent_items(home string, items []RecentItem) bool {
	mut bytes := []u8{cap: 1024}
	defer { unsafe { bytes.free() } }
	for item in items {
		for ch in item.app {
			bytes << ch
		}
		bytes << `\t`
		for ch in item.path {
			bytes << ch
		}
		bytes << `\n`
	}
	path := home_file_path(home, recent_items_filename)
	defer { unsafe { path.free() } }
	data := if bytes.len > 0 { voidptr(bytes.data) } else { voidptr(unsafe { nil }) }
	return desktop_write_file(path, data, u64(bytes.len))
}

fn recent_item_path_valid(path string) bool {
	if path.len == 0 || path.len > recent_item_max_path || path[0] != `/` {
		return false
	}
	for ch in path {
		if ch == `\n` || ch == `\r` || ch == `\t` {
			return false
		}
	}
	return true
}

// record_recent_item_in moves `path` to the front of `app`'s history, keeps
// at most recent_items_per_app entries per application and saves the list.
fn record_recent_item_in(home string, app string, path string) bool {
	if app.len == 0 || !recent_item_path_valid(path) {
		return false
	}
	old := load_recent_items(home)
	mut next := []RecentItem{cap: old.len + 1}
	next << RecentItem{
		app:  app
		path: path
	}
	mut kept_for_app := 1
	for item in old {
		if next.len >= recent_items_limit {
			break
		}
		if item.app == app {
			if item.path == path || kept_for_app >= recent_items_per_app {
				continue
			}
			kept_for_app++
		}
		next << item
	}
	saved := save_recent_items(home, next)
	// The first entry borrows the caller's strings; the rest belong to `old`.
	unsafe { next.free() }
	free_recent_items(old)
	return saved
}

fn record_recent_item(app string, path string) {
	record_recent_item_in(desktop_home, app, path)
}

// recent_items_for returns up to `limit` of one application's items, or of
// every application's when `app` is empty. Missing paths are skipped so a
// deleted document does not linger in a Jump List.
fn recent_items_for(home string, app string, limit int) []RecentItem {
	all := load_recent_items(home)
	mut out := []RecentItem{cap: limit}
	for item in all {
		if out.len >= limit || (app.len > 0 && item.app != app) {
			unsafe {
				item.app.free()
				item.path.free()
			}
			continue
		}
		if desktop_stat(item.path) == none {
			unsafe {
				item.app.free()
				item.path.free()
			}
			continue
		}
		out << item
	}
	unsafe { all.free() }
	return out
}

// ── Programs ───────────────────────────────────────────────────────

fn load_recent_programs(home string) []int {
	path := home_file_path(home, recent_programs_filename)
	defer { unsafe { path.free() } }
	return load_app_name_list(path, recent_programs_limit)
}

fn load_start_pins(home string) []int {
	path := home_file_path(home, start_pins_filename)
	defer { unsafe { path.free() } }
	return load_app_name_list(path, available_apps.len)
}

// record_recent_program_in puts a launched program at the front of the Start
// menu's recent list. The list is saved on every launch, like Windows keeps
// its UserAssist counts, so a crash does not lose the history.
fn (mut d Desktop) record_recent_program_in(home string, index int) {
	if index < 0 || index >= available_apps.len {
		return
	}
	if d.recent_programs.len > 0 && d.recent_programs[0] == index {
		return
	}
	for slot, app in d.recent_programs {
		if app == index {
			d.recent_programs.delete(slot)
			break
		}
	}
	d.recent_programs.insert(0, index)
	if d.recent_programs.len > recent_programs_limit {
		d.recent_programs.trim(recent_programs_limit)
	}
	path := home_file_path(home, recent_programs_filename)
	if !save_app_name_list(path, d.recent_programs) {
		eprintln('vinix-desktop: could not save recent programs')
	}
	unsafe { path.free() }
	d.dirty = true
}

fn (mut d Desktop) forget_recent_program_in(home string, index int) bool {
	for slot, app in d.recent_programs {
		if app != index {
			continue
		}
		d.recent_programs.delete(slot)
		path := home_file_path(home, recent_programs_filename)
		saved := save_app_name_list(path, d.recent_programs)
		unsafe { path.free() }
		d.dirty = true
		return saved
	}
	return false
}

fn (d &Desktop) start_is_pinned(index int) bool {
	return shortcut_order_contains(d.start_pins, index)
}

fn (mut d Desktop) pin_start_app_in(home string, index int) bool {
	if index < 0 || index >= available_apps.len || d.start_is_pinned(index) {
		return false
	}
	d.start_pins << index
	path := home_file_path(home, start_pins_filename)
	defer { unsafe { path.free() } }
	if !save_app_name_list(path, d.start_pins) {
		d.start_pins.delete(d.start_pins.len - 1)
		return false
	}
	d.dirty = true
	return true
}

fn (mut d Desktop) unpin_start_app_in(home string, index int) bool {
	for slot, pinned in d.start_pins {
		if pinned != index {
			continue
		}
		d.start_pins.delete(slot)
		path := home_file_path(home, start_pins_filename)
		defer { unsafe { path.free() } }
		if !save_app_name_list(path, d.start_pins) {
			d.start_pins.insert(slot, index)
			return false
		}
		d.dirty = true
		return true
	}
	return false
}

// recent_item_title is the last path component, or `/` for the root. Unlike
// file_path_name it always returns an owned string, which a Jump List frees
// when it closes.
fn recent_item_title(path string) string {
	if path == '/' {
		return '/'
	}
	mut end := path.len
	for end > 1 && path[end - 1] == `/` {
		end--
	}
	mut start := end
	for start > 0 && path[start - 1] != `/` {
		start--
	}
	return path[start..end]
}
