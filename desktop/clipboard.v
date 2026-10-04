// SPDX-License-Identifier: GPL-2.0-or-later
// Host clipboard requests are bounded, asynchronous and made only on paste.
module main

import os

const host_clipboard_url_path = '/etc/vinix/host-clipboard-url'
const clipboard_max_bytes = 64 * 1024
const key_cmd_v = '\x1b[118;9u'
const key_ctrl_shift_v = '\x1b[118;6u'
const key_shift_insert = '\x1b[2;2~'

interface PastingApp {
mut:
	paste_input(text string)
}

struct HostClipboard {
mut:
	configured bool
	url        string
	pid        int = -1
	fd         int = -1
	target     int = -1
	menu       bool
	finished   bool
	success    bool
	data       []u8
	pending    string
}

fn (mut c HostClipboard) configure() {
	if c.configured {
		return
	}
	c.configured = true
	value := os.read_file(host_clipboard_url_path) or { return }
	defer { unsafe { value.free() } }
	c.url = value.trim_space()
}

// Preserve printable UTF-8, tabs and line breaks; terminal control sequences
// and shortcut bytes are never interpreted as commands from clipboard text.
fn clipboard_text(input string) string {
	mut text := []u8{cap: input.len}
	for i, ch in input {
		if ch == `\r` {
			if i + 1 == input.len || input[i + 1] != `\n` {
				text << u8(`\n`)
			}
		} else if ch == `\n` || ch == `\t` || (ch >= 32 && ch != 127) {
			text << ch
		}
	}
	result := text.bytestr()
	unsafe { text.free() }
	return result
}

fn (mut d Desktop) take_paste_keys(keys string) string {
	d.clipboard.configure()
	if d.clipboard.url.len == 0 {
		return keys
	}
	if d.clipboard.pending.len == 0 && keys.index_u8(0x16) < 0 && keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut input := keys
	joined := d.clipboard.pending.len > 0
	if joined {
		input = d.clipboard.pending + keys
		unsafe { d.clipboard.pending.free() }
		d.clipboard.pending = ''
	}
	mut kept := []u8{cap: input.len}
	mut at := 0
	for at < input.len {
		mut length := if input[at] == 0x16 { 1 } else { 0 }
		mut partial := false
		if length == 0 && input[at] == 0x1b {
			for chord in [key_cmd_v, key_ctrl_shift_v, key_shift_insert]! {
				matched := match_at(input, at, chord)
				if matched > 0 {
					length = chord.len
					break
				}
				if matched == seq_partial {
					partial = true
				}
			}
		}
		if partial && length == 0 {
			d.clipboard.pending = input[at..].clone()
			break
		}
		if length > 0 {
			// Deliver preceding typing before asking for the clipboard, and do
			// not route pasted text back through layout or desktop shortcuts.
			if kept.len > 0 {
				if d.start_menu_open {
					d.start_menu_key_input(unsafe { tos(kept.data, kept.len) })
				} else {
					d.send_keys_to_focused(unsafe { tos(kept.data, kept.len) })
				}
				kept.clear()
			}
			d.request_host_paste()
			at += length
		} else {
			kept << input[at]
			at++
		}
	}
	if kept.len == input.len && !joined {
		unsafe { kept.free() }
		return keys
	}
	result := kept.bytestr()
	unsafe {
		kept.free()
		if joined { input.free() }
	}
	return result
}

fn (mut d Desktop) request_host_paste() {
	if d.clipboard.pid > 0 || (!d.start_menu_open && !d.focused_app_takes_keys()) {
		return
	}
	child := desktop_spawn_clipboard(d.clipboard.url) or { return }
	d.clipboard.pid = child.pid
	d.clipboard.fd = child.output
	d.clipboard.target = d.focus
	d.clipboard.menu = d.start_menu_open
	d.clipboard.finished = false
	d.clipboard.success = false
	d.clipboard.data.clear()
}

fn (mut d Desktop) poll_host_paste() {
	if d.clipboard.pid <= 0 {
		return
	}
	mut buffer := [4096]u8{}
	mut eof := false
	for _ in 0 .. 17 {
		n := desktop_read(d.clipboard.fd, &buffer[0], 4096)
		if n <= 0 {
			eof = n == 0
			break
		}
		if d.clipboard.data.len + int(n) > clipboard_max_bytes {
			d.clipboard.close_request()
			return
		}
		for i in 0 .. int(n) {
			d.clipboard.data << buffer[i]
		}
	}
	if !d.clipboard.finished {
		mut status := 0
		if C.waitpid(d.clipboard.pid, &status, C.WNOHANG) == d.clipboard.pid {
			d.clipboard.finished = true
			d.clipboard.success = status == 0
		}
	}
	if !eof || !d.clipboard.finished {
		return
	}
	if d.clipboard.success && d.focus == d.clipboard.target
		&& d.start_menu_open == d.clipboard.menu {
		text := clipboard_text(unsafe { tos(d.clipboard.data.data, d.clipboard.data.len) })
		if d.start_menu_open {
			d.start_menu_key_input(text)
		} else {
			d.send_paste_to_focused(text)
		}
		unsafe { text.free() }
	}
	d.clipboard.close_request()
}

fn (mut c HostClipboard) close_request() {
	if c.fd >= 0 {
		desktop_close(c.fd)
		c.fd = -1
	}
	if c.pid > 0 && !c.finished {
		_ = desktop_terminate_child(c.pid)
	}
	c.pid = -1
	c.data.clear()
}

fn (mut d Desktop) send_paste_to_focused(text string) {
	index := d.focused_app_index() or { return }
	mut app := d.apps[index]
	if mut app is PastingApp {
		app.paste_input(text)
		d.dirty = true
	} else if mut app is KeyboardApp {
		app.key_input(text)
		d.dirty = true
	}
}
