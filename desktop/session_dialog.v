// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import desktop.sessionipc
import ui2
import os
import time

struct ShellDialog {
mut:
	pid         int
	key         sessioncore.Text
	kind        int
	title       sessioncore.Text
	directory   sessioncore.Text
	filename    sessioncore.Text
	filter      sessioncore.Text
	entries     [128]sessioncore.Text
	directories [128]bool
	count       int
	page        int
	selected    int = -1
	edit        bool
	window      int
	status      sessioncore.Text
	actions     [128]string
}

fn session_dialog_open(key string, kind int, title string, directory string, filename string, filter string) bool {
	return sessionipc.dialog_open(key, kind, title, directory, filename, filter)
}

fn session_dialog_take(key string) ?string { return sessionipc.dialog_take(key) }

fn session_dialog_cli(kind int, directory string, filter string) {
	if !session_dialog_open('portal', kind, 'Choose a file or folder', directory, '', filter) {
		eprintln('File dialog unavailable')
		exit(1)
	}
	for _ in 0 .. 3000 {
		if path := session_dialog_take('portal') {
			if path.len > 0 {
				println(path)
				unsafe { path.free() }
				return
			}
			exit(1)
		}
		time.sleep(100 * time.millisecond)
	}
	exit(1)
}

fn (mut d Desktop) open_shell_dialog(m SessionMessage) {
	if m.count != 7 { return }
	if d.hub.dialog.pid > 0 { d.finish_shell_dialog('') }
	mut dialog := ShellDialog{ pid: m.pid, key: m.fields[1], kind: int(sessioncore.number(m.fields[2].str(), 0, 2) or { return }), title: m.fields[3], directory: m.fields[4], filename: m.fields[5], filter: m.fields[6] }
	for i in 0 .. dialog.actions.len { dialog.actions[i] = 'dialog.row.${i}' }
	dialog.window = d.spawn('Choose a file or folder', .dialog, 140, 90, 650, 450)
	d.hub.dialog = dialog
	d.read_shell_dialog()
}

fn (mut d Desktop) read_shell_dialog() {
	d.hub.dialog.count = 0
	d.hub.dialog.selected = -1
	d.hub.dialog.page = 0
	path := d.hub.dialog.directory.str()
	names := os.ls(path) or {
		d.hub.dialog.status.set('Cannot read this directory.') or {}
		return
	}
	defer {
		for name in names {
			unsafe { name.free() }
		}
		unsafe { (&array(&names)).free() }
	}
	for name in names {
		if d.hub.dialog.count == 128 {
			d.hub.dialog.status.set('First 128 entries shown. Choose a narrower folder.') or {}
			break
		}
		full := os.join_path(path, name)
		is_directory := os.is_dir(full)
		unsafe { full.free() }
		if !is_directory && d.hub.dialog.filter.len > 0 && sessioncore.mime_for_path(name) != d.hub.dialog.filter.str() {
			continue
		}
		if !is_directory && d.hub.dialog.kind == 1 { continue }
		i := d.hub.dialog.count
		d.hub.dialog.entries[i].set(name) or { continue }
		d.hub.dialog.directories[i] = is_directory
		d.hub.dialog.count++
	}
	d.dirty = true
}

fn (mut d Desktop) finish_shell_dialog(path string) {
	pid := d.hub.dialog.pid.str()
	args := [pid, d.hub.dialog.key.str(), path]
	_ = session_call_ok('dialog.result', args)
	unsafe {
		pid.free()
		(&array(&args)).free()
	}
	id := d.hub.dialog.window
	for action in d.hub.dialog.actions { if action.len > 0 { unsafe { action.free() } } }
	d.hub.dialog = ShellDialog{}
	if id > 0 { d.close_window(id) }
}

fn (mut d Desktop) handle_shell_dialog(action string) bool {
	if !action.starts_with('dialog.') { return false }
	if d.hub.dialog.pid <= 0 { return true }
	match action {
		'dialog.cancel' { d.finish_shell_dialog('') }
		'dialog.up' {
			parent := os.dir(d.hub.dialog.directory.str())
			d.hub.dialog.directory.set(parent) or {}
			unsafe { parent.free() }
			d.read_shell_dialog()
		}
		'dialog.previous' {
			if d.hub.dialog.page > 0 { d.hub.dialog.page-- }
			d.dirty = true
		}
		'dialog.next' {
			if (d.hub.dialog.page + 1) * 9 < d.hub.dialog.count { d.hub.dialog.page++ }
			d.dirty = true
		}
		'dialog.name' { d.hub.dialog.edit = true }
		'dialog.accept' {
			mut path := ''
			if d.hub.dialog.kind == 1 {
				path = d.hub.dialog.directory.str().clone()
			} else if d.hub.dialog.kind == 2 {
				name := d.hub.dialog.filename.str()
				if name.len == 0 || name in ['.', '..'] || name.contains('/') { return true }
				path = os.join_path(d.hub.dialog.directory.str(), name)
				if os.is_dir(path) {
					unsafe { path.free() }
					return true
				}
				if os.exists(path) && d.hub.dialog.status.str() != 'Click Choose again to replace this file.' {
					d.hub.dialog.status.set('Click Choose again to replace this file.') or {}
					unsafe { path.free() }
					d.dirty = true
					return true
				}
			} else if d.hub.dialog.selected >= 0 {
				path = os.join_path(d.hub.dialog.directory.str(), d.hub.dialog.entries[d.hub.dialog.selected].str())
			}
			if path.len > 0 {
				d.finish_shell_dialog(path)
				unsafe { path.free() }
			}
		}
		else {
			if action.starts_with('dialog.row.') {
				i := int(sessioncore.number(action['dialog.row.'.len..], 0, d.hub.dialog.count - 1) or { return true })
				if d.hub.dialog.directories[i] {
					path := os.join_path(d.hub.dialog.directory.str(), d.hub.dialog.entries[i].str())
					d.hub.dialog.directory.set(path) or {}
					unsafe { path.free() }
					d.read_shell_dialog()
				} else {
					d.hub.dialog.selected = i
					d.hub.dialog.filename = d.hub.dialog.entries[i]
					d.dirty = true
				}
			}
		}
	}
	return true
}

fn (d &Desktop) shell_dialog_contents(width int, height int) []ui2.Element {
	mut out := frame_elements(18)
	out << body_line(d.hub.dialog.directory.str(), 16, 12, width - 130)
	out << settings_choice('dialog.up', 'Up', width - 96, 8, 80, false)
	for slot in 0 .. 9 {
		i := d.hub.dialog.page * 9 + slot
		if i >= d.hub.dialog.count { break }
		out << settings_choice(d.hub.dialog.actions[i], d.hub.dialog.entries[i].str(), 16, 48 + slot * 30, width - 32, d.hub.dialog.selected == i)
	}
	if d.hub.dialog.kind == 2 {
		out << ui2.clickable_view('dialog.name', ui2.rect(16, f64(height - 104), f64(width - 32), 28), ui2.BoxStyle{ bg: body_panel }, [ui2.text_field('', 'Filename', d.hub.dialog.filename.str(), ui2.rect(8, 0, f64(width - 48), 28), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text }, 0)])
	}
	out << muted_line(d.hub.dialog.status.str(), 16, height - 72, width - 32)
	out << settings_choice('dialog.previous', 'Previous', 16, height - 40, 90, false)
	out << settings_choice('dialog.next', 'Next', 114, height - 40, 80, false)
	out << settings_choice('dialog.cancel', 'Cancel', width - 220, height - 40, 90, false)
	out << settings_choice('dialog.accept', 'Choose', width - 122, height - 40, 106, true)
	return out
}

fn (mut d Desktop) shell_dialog_keys(input string) bool {
	if d.hub.dialog.pid <= 0 { return false }
	if input == '\x1b' {
		d.finish_shell_dialog('')
		return true
	}
	if input == '\r' || input == '\n' {
		d.handle_shell_dialog('dialog.accept')
		return true
	}
	if d.hub.dialog.edit {
		for byte in input {
			if byte == 8 || byte == 127 {
				if d.hub.dialog.filename.len > 0 {
					d.hub.dialog.filename.len--
					d.hub.dialog.filename.bytes[d.hub.dialog.filename.len] = 0
				}
			} else if byte >= 32 && byte < 127 && d.hub.dialog.filename.len < 255 {
				d.hub.dialog.filename.bytes[d.hub.dialog.filename.len] = byte
				d.hub.dialog.filename.len++
				d.hub.dialog.filename.bytes[d.hub.dialog.filename.len] = 0
			}
		}
		d.hub.dialog.status = sessioncore.Text{}
		d.dirty = true
	}
	return true
}
