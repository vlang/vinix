// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A file browser, built into the desktop.
//
// Unlike the calculator it is not a ui2 example but Vinix's own, and it reads
// a real filesystem: the listing comes from the kernel's getdents64 through
// musl's readdir, and each entry is stat'd for its size. It satisfies the same
// HostedApp interface a ui2 application does, so the window manager hosts it
// with the machinery that was already there and knows nothing about files.
module main

import ui2

// Longer than any name the kernel's Dirent can hold, so a listing never
// truncates one.
const max_name_len = 256

// A directory with more entries than this is listed no further. Vinix has no
// directory that large, and the cap keeps one pathological read from stalling
// the compositor for a whole frame.
const max_entries = 4096

struct FileEntry {
	name   string
	is_dir bool
	size   u64
}

// FileBrowser is the model: where it is, what is there, and how far down the
// list has been scrolled.
struct FileBrowser {
mut:
	path    string = '/'
	entries []FileEntry
	scroll  int
	error   string
	// Row the pointer is over, or -1. Kept here rather than in the desktop's
	// hover state because rows are the application's, not the chrome's.
	hover_row int = -1
}

// join builds a child path without the doubled slash that string concatenation
// would give at the root.
fn join_path(dir string, name string) string {
	if dir.ends_with('/') {
		return dir + name
	}
	return '${dir}/${name}'
}

fn parent_path(path string) string {
	trimmed := path.trim_right('/')
	index := trimmed.last_index('/') or { return '/' }
	if index == 0 {
		return '/'
	}
	return trimmed[..index]
}

// read replaces the listing with the contents of `path`. A directory it cannot
// open leaves the browser where it was and says so, rather than emptying the
// window and looking like the directory is empty.
fn (mut b FileBrowser) read(path string) {
	dir := desktop_opendir(path)
	if dir == unsafe { nil } {
		b.error = 'cannot open ${path}'
		return
	}

	mut entries := []FileEntry{}
	mut buffer := [max_name_len]u8{}
	mut names := unsafe { (&buffer[0]).vbytes(buffer.len) }
	for entries.len < max_entries {
		if !desktop_readdir(dir, mut names) {
			break
		}
		name := unsafe { cstring_to_vstring(&char(&buffer[0])) }
		// `.` says nothing, and `..` is the Up button's job.
		if name == '.' || name == '..' {
			continue
		}
		mut size := u64(0)
		mut is_dir := false
		full := join_path(path, name)
		if info := desktop_stat(full) {
			size = info.size
			is_dir = info.is_dir
		}
		// Unreadable entries remain visible, with unknown type and size.
		entries << FileEntry{
			name: name
			is_dir: is_dir
			size: size
		}
	}
	desktop_closedir(dir)

	// Directories first, then by name — the order a listing is read in is
	// whatever the filesystem happens to store, which is no order at all.
	entries.sort_with_compare(fn (a &FileEntry, b &FileEntry) int {
		if a.is_dir != b.is_dir {
			return if a.is_dir { -1 } else { 1 }
		}
		return compare_strings(a.name, b.name)
	})

	b.path = path
	b.entries = entries
	b.scroll = 0
	b.error = ''
	b.hover_row = -1
}

fn (mut b FileBrowser) enter(index int) {
	if index < 0 || index >= b.entries.len {
		return
	}
	entry := b.entries[index]
	if !entry.is_dir {
		return
	}
	b.read(join_path(b.path, entry.name))
}

fn (mut b FileBrowser) go_up() {
	if b.path == '/' {
		return
	}
	b.read(parent_path(b.path))
}

// human_size keeps a listing's last column narrow. Sizes are shown to three
// significant figures at most, which is as much as anyone reads at a glance.
fn human_size(size u64) string {
	if size < 1024 {
		return '${size} B'
	}
	units := ['KB', 'MB', 'GB', 'TB']
	mut value := f64(size) / 1024.0
	mut unit := 0
	for value >= 1024.0 && unit + 1 < units.len {
		value /= 1024.0
		unit++
	}
	if value < 10.0 {
		return '${value:.1f} ${units[unit]}'
	}
	return '${int(value)} ${units[unit]}'
}

// ── The hosted application ────────────────────────────────────────

const files_action_up = 'files.up'
const files_action_row = 'files.row.'
const files_action_scroll_up = 'files.scroll.up'
const files_action_scroll_down = 'files.scroll.down'

const files_row_height = 24
const files_header_height = 38
const files_padding = 10

struct FileBrowserApp {
mut:
	browser FileBrowser
	// Rows the window last had space for, so scrolling can clamp against the
	// window as it actually is rather than as it was when it opened.
	visible_rows int = 1
}

fn open_files(mut _ Desktop) !HostedApp {
	mut app := &FileBrowserApp{}
	app.browser.read('/')
	if app.browser.error != '' {
		return error(app.browser.error)
	}
	return app
}

fn (mut a FileBrowserApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	inner := width - 2 * files_padding

	list_top := files_header_height
	list_height := height - list_top - files_padding
	a.visible_rows = if list_height > files_row_height {
		list_height / files_row_height
	} else {
		1
	}
	a.clamp_scroll()

	mut children := []ui2.Element{}

	// Header: where we are, and the way back out.
	up_width := 40
	children << ui2.button(files_action_up, 'Up', ui2.rect(f64(files_padding), 8, f64(up_width), 22), ui2.BoxStyle{
		bg: if a.browser.path == '/' { files_up_disabled } else { files_up }
		radius: 5
	}, ui2.TextStyle{
		color: if a.browser.path == '/' { body_muted } else { app_on_accent }
		size: 12
		align: .center
	})
	children << ui2.label('', a.browser.path, ui2.rect(f64(files_padding + up_width + 10), 8, f64(inner - up_width - 10), 22), ui2.TextStyle{
		color: body_heading
		size: 13
		bold: true
	})
	children << ui2.view('', ui2.rect(0, f64(list_top - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	if a.browser.error != '' {
		children << ui2.label('', a.browser.error, ui2.rect(f64(files_padding), f64(list_top + 8), f64(inner), 20), ui2.TextStyle{
			color: files_error
			size: 13
		})
		return ui2.screen(app_surface, children)
	}

	if a.browser.entries.len == 0 {
		children << ui2.label('', 'This directory is empty.', ui2.rect(f64(files_padding), f64(list_top + 8), f64(inner), 20), ui2.TextStyle{
			color: body_muted
			size: 13
		})
		return ui2.screen(app_surface, children)
	}

	// Rows.
	mut row := 0
	for index := a.browser.scroll; index < a.browser.entries.len && row < a.visible_rows; index++ {
		entry := a.browser.entries[index]
		y := list_top + row * files_row_height
		hovered := a.browser.hover_row == index
		children << ui2.clickable_view('${files_action_row}${index}', ui2.rect(0, f64(y), f64(width), f64(files_row_height)), ui2.BoxStyle{
			bg: files_row_hover
			transparent: !hovered
		}, [
			ui2.button_with_image('', '', if entry.is_dir {
				'builtin:folder'
			} else {
				'builtin:file'
			}, ui2.rect(f64(files_padding), 4, 16, 16), ui2.BoxStyle{
				transparent: true
			}, ui2.TextStyle{
				color: if entry.is_dir { files_folder_icon } else { files_file_icon }
			}),
			ui2.label('', entry.name, ui2.rect(f64(files_padding + 24), 0, f64(inner - 24 - 72), f64(files_row_height)), ui2.TextStyle{
				color: if entry.is_dir { body_heading } else { body_text }
				size: 13
			}),
			ui2.label('', if entry.is_dir { '' } else { human_size(entry.size) }, ui2.rect(f64(width - files_padding - 70), 0, 70, f64(files_row_height)), ui2.TextStyle{
				color: body_muted
				size: 11
				align: .right
			}),
		])
		row++
	}

	// Scroll buttons, only when there is somewhere to scroll to. A wheel would
	// be nicer, but a button works with the one thing every pointer has.
	if a.browser.entries.len > a.visible_rows {
		button_size := 18
		right := width - files_padding - button_size
		children << ui2.button(files_action_scroll_up, '-', ui2.rect(f64(right - button_size - 4), 8, f64(button_size), 22), ui2.BoxStyle{
			bg: files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size: 12
			align: .center
		})
		children << ui2.button(files_action_scroll_down, '+', ui2.rect(f64(right), 8, f64(button_size), 22), ui2.BoxStyle{
			bg: files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size: 12
			align: .center
		})
	}

	return ui2.screen(app_surface, children)
}

fn (mut a FileBrowserApp) clamp_scroll() {
	max_scroll := a.browser.entries.len - a.visible_rows
	if a.browser.scroll > max_scroll {
		a.browser.scroll = max_scroll
	}
	if a.browser.scroll < 0 {
		a.browser.scroll = 0
	}
}

fn (mut a FileBrowserApp) handle(event_id string) ! {
	match event_id {
		files_action_up {
			a.browser.go_up()
			return
		}
		files_action_scroll_up {
			a.browser.scroll -= a.visible_rows
			a.clamp_scroll()
			return
		}
		files_action_scroll_down {
			a.browser.scroll += a.visible_rows
			a.clamp_scroll()
			return
		}
		else {}
	}
	if event_id.starts_with(files_action_row) {
		a.browser.enter(event_id[files_action_row.len..].int())
	}
}
