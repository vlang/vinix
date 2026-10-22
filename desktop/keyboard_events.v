// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.windowfb

fn (d &Desktop) focused_kitty_window() bool {
	index := d.focused_app_index() or { return false }
	app := d.apps[index]
	if app is FramebufferApp { return app.features & windowfb.kitty_keyboard != 0 }
	return false
}

fn (mut d Desktop) send_physical_framebuffer_key(id int, key int, modifiers int, value int, text string) bool {
	index := d.window_index(id) or { return false }
	slot := d.windows[index].app_index
	if slot < 0 { return false }
	mut app := d.apps[slot]
	if mut app is FramebufferApp {
		if app.features & windowfb.kitty_keyboard == 0 { return false }
		encoded := kitty_key(key, modifiers, value, d.settings.keyboard_layout, text)
		if encoded.length == 0 { return false }
		app.emit(.keys, 0, 0, 0, unsafe { tos(&encoded.bytes[0], encoded.length) })
		return true
	}
	return false
}

fn (mut d Desktop) physical_typing(raw string, key int, modifiers int, fd int) string {
	index := d.focused_app_index() or { return d.type_with_layout(raw, fd) }
	app := d.apps[index]
	if app is FramebufferApp {
		if key > 0 && app.features & windowfb.kitty_keyboard != 0 && modifiers & 12 == 0 {
			info := physical_identity(key, d.settings.keyboard_layout)
			mut point := keypad_text(key, modifiers)
			mut meta := modifiers & 2 != 0
			if info.base != 0 {
				shift := modifiers & 1 != 0
				caps := modifiers & 64 != 0 && keymap_cased(rune(info.code), rune(info.shifted))
				point = if shift != caps { info.shifted } else { info.code }
				if meta {
					if table := keymap_for(d.settings.keyboard_layout) {
						slot := physical_layout_keys.index(key)
						if slot >= 0 && table.option[slot] != 0 {
							point = int(table.option[slot])
							meta = false
						}
					}
				}
			} else if key == 57 {
				point = 32
			}
			if point > 0 {
				mut out := []u8{cap: 16}
				out.flags |= .noslices
				if meta { out << u8(27) }
				d.keyboard.type_rune(mut out, rune(point))
				text := out.bytestr()
				unsafe { out.free() }
				return text
			}
		}
	}
	return d.type_with_layout(raw, fd)
}

fn (mut d Desktop) pump_physical_key(mut keyboard Keyboard, key int, value int) {
	if key <= 0 || key >= keyboard.held.len { return }
	keyboard.held[key] = value != 0
	if key == 255 { return } // Apple Fn remaps navigation; Kitty has no Fn bit.
	if value == 1 {
		keyboard.aliases[key] = if keyboard.held[255] {
			match key {
				14 { 111 }
				106 { 107 }
				105 { 102 }
				108 { 109 }
				103 { 104 }
				else { key }
			}
		} else {
			key
		}
	}
	effective := if keyboard.aliases[key] > 0 { keyboard.aliases[key] } else { key }
	if value == 1 && key == 58 { keyboard.caps = !keyboard.caps }
	if value == 1 && key == 69 { keyboard.num = !keyboard.num }
	mods := keyboard.modifiers()
	if value != 0 && d.idle_key_input() {
		keyboard.owners[key] = 0
		return
	}
	legacy := legacy_physical_key(effective, mods, value)
	if value == 0 {
		if legacy.length > 0 {
			d.pump_key_text(keyboard.fd, unsafe { tos(&legacy.bytes[0], legacy.length).clone() }, -1, 0, value)
		}
		if keyboard.owners[key] != 0 {
			d.send_physical_framebuffer_key(keyboard.owners[key], effective, mods, value, '')
		}
		keyboard.owners[key] = 0
		keyboard.aliases[key] = 0
		return
	}
	if value == 2 && keyboard.owners[key] != 0 && keyboard.owners[key] != d.focus { return }
	if legacy.length == 0 {
		if !d.start_menu_open && d.send_physical_framebuffer_key(d.focus, effective, mods, value, '') {
			keyboard.owners[key] = d.focus
		}
		return
	}
	owner := d.pump_key_text(keyboard.fd, unsafe { tos(&legacy.bytes[0], legacy.length).clone() }, effective, mods, value)
	if value == 1 || (owner != 0 && keyboard.owners[key] == 0) { keyboard.owners[key] = owner }
}

fn (mut d Desktop) pump_keyboard(mut keyboard Keyboard) {
	raw := keyboard.poll()
	if !keyboard.key_events {
		if raw.len > 0 && d.idle_key_input() {
			unsafe { raw.free() }
			return
		}
		d.pump_key_text(keyboard.fd, raw, -1, 0, 1)
		return
	}
	defer { if raw.len > 0 { unsafe { raw.free() } } }
	if raw.len == 0 && keyboard.packet_used > 0 && monotonic_millis() - keyboard.packet_ms >= keyboard_sequence_gap_ms {
		// UART/serial legacy input can still arrive beside physical records.
		text := unsafe { tos(&keyboard.packet[0], keyboard.packet_used).clone() }
		keyboard.packet_used = 0
		d.pump_key_text(keyboard.fd, text, -1, 0, 1)
	}
	for byte in raw {
		count := keyboard.feed(byte)
		if count == 0 { continue }
		if keyboard.packet_physical(count) {
			key, value := physical_packet(unsafe { &keyboard.packet[0] }, count)
			if value >= 0 { d.pump_physical_key(mut keyboard, key, value) }
		} else {
			text := unsafe { tos(&keyboard.packet[0], count).clone() }
			d.pump_key_text(keyboard.fd, text, -1, 0, 1)
		}
	}
}

// feed adds one byte of console input to the packet being assembled. It
// returns the length of the packet that byte completes, or 0. The completed
// packet stays in kbd.packet until the next byte is fed.
fn (mut kbd Keyboard) feed(byte u8) int {
	kbd.packet[kbd.packet_used] = byte
	kbd.packet_used++
	kbd.packet_ms = monotonic_millis()
	count := kbd.packet_used
	complete := if kbd.packet_physical(count) {
		byte == `k` || byte == `h`
	} else {
		kbd.packet[0] != 27 || (count == 2 && byte != `[` && byte != `O`) || (count > 2 && byte >= 0x40 && byte <= 0x7e)
	}
	if !complete && count < kbd.packet.len { return 0 }
	kbd.packet_used = 0
	return count
}

fn (kbd &Keyboard) packet_physical(count int) bool {
	return count >= 3 && kbd.packet[0] == 27 && kbd.packet[1] == `[` && kbd.packet[2] == `?`
}

// poll_text returns what the waiting keys type, for the setup screens that
// read the keyboard before the desktop's own key handling runs. With physical
// key events on, the console sends key records instead of text; type them as
// the console would have, in the US layout, and leave out key releases.
fn (mut kbd Keyboard) poll_text() string {
	return kbd.poll_setup_text(false)
}

// Setup screens must retire both the raw physical records and their text
// translation. The returned text is owned by its caller, which wipes it too.
fn (mut kbd Keyboard) poll_secret_text() string {
	return kbd.poll_setup_text(true)
}

fn wipe_login_input(text string) {
	if text.len == 0 { return }
	$if linux { unsafe { C.explicit_bzero(text.str, usize(text.len)) } }
	$else { unsafe { C.memset_s(text.str, usize(text.len), 0, usize(text.len)) } }
}

fn (mut kbd Keyboard) poll_setup_text(secret bool) string {
	raw := kbd.poll_owned(secret)
	if !kbd.key_events { return raw }
	defer {
		if secret {
			wipe_login_input(raw)
			for i in kbd.packet_used .. kbd.packet.len { kbd.packet[i] = 0 }
		}
		if raw.len > 0 { unsafe { raw.free() } }
	}
	// Each physical record emits fewer bytes than its input. Reserving the
	// complete poll plus the pending packet avoids reallocating plaintext.
	mut out := []u8{cap: if secret { raw.len + kbd.packet.len } else { 64 }}
	out.flags |= .noslices
	if raw.len == 0 && kbd.packet_used > 0 && monotonic_millis() - kbd.packet_ms >= keyboard_sequence_gap_ms {
		// A lone Escape, or serial input beside the physical records.
		for i in 0 .. kbd.packet_used { out << kbd.packet[i] }
		kbd.packet_used = 0
	}
	for byte in raw {
		count := kbd.feed(byte)
		if count == 0 { continue }
		if !kbd.packet_physical(count) {
			for i in 0 .. count { out << kbd.packet[i] }
			continue
		}
		key, value := physical_packet(unsafe { &kbd.packet[0] }, count)
		if value < 0 || key <= 0 || key >= kbd.held.len { continue }
		kbd.held[key] = value != 0
		if value == 1 && key == 58 { kbd.caps = !kbd.caps }
		if value == 1 && key == 69 { kbd.num = !kbd.num }
		if value == 0 || key == 255 { continue }
		legacy := legacy_physical_key(key, kbd.modifiers(), value)
		for i in 0 .. legacy.length { out << legacy.bytes[i] }
	}
	if out.len == 0 {
		unsafe { out.free() }
		return ''
	}
	text := out.bytestr()
	if secret {
		wipe_login_input(unsafe { tos(out.data, out.len) })
		// Keep an incomplete escape packet for the next poll, but erase every
		// completed record. No password text survives in the packet buffer.
		for i in kbd.packet_used .. kbd.packet.len { kbd.packet[i] = 0 }
	}
	unsafe { out.free() }
	return text
}

fn (mut d Desktop) pump_key_text(fd int, raw string, key int, modifiers int, value int) int {
	// The console types the US layout. Everything below reads what the chosen
	// input source types instead; shortcuts arrive as they were.
	keys := d.physical_typing(raw, key, modifiers, fd)
	if raw.len > 0 && keys.str != raw.str {
		unsafe { raw.free() }
	}
	defer { if keys.len > 0 { unsafe { keys.free() } } }
	if key == 57 && modifiers & 4 != 0 && keys.len == 0 { return 0 }
	if keys.len == 0 && raw.len > 0 && key > 0 && d.send_physical_framebuffer_key(d.focus, key, modifiers, value, '') {
		return d.focus
	}
	// Shortcut parsers must also see disambiguated chords. In particular,
	// Alt-[ must not be held as a partial CSI, nor Ctrl-I treated as Tab.
	mut shortcut_keys := keys
	if key > 0 && modifiers & 14 != 0 && d.focused_kitty_window() && !d.start_menu_open {
		info := physical_identity(key, .us)
		mut encoded := KeyEncoding{}
		if info.final == `u` && info.number > 0 {
			encoded.byte(27)
			encoded.byte(`[`)
			encoded.decimal(info.number)
			encoded.byte(`;`)
			encoded.decimal((modifiers & 63) + 1)
			encoded.byte(`u`)
		} else {
			encoded = legacy_physical_key(key, modifiers, value)
		}
		if encoded.length > 0 {
			shortcut_keys = unsafe { tos(&encoded.bytes[0], encoded.length).clone() }
		}
	}
	defer {
		if shortcut_keys.len > 0 && shortcut_keys.str != keys.str {
			unsafe { shortcut_keys.free() }
		}
	}
	if keys.len > 0 { d.mark_session_gesture() }
	if d.shell_dialog_keys(shortcut_keys) || d.capture_session_shortcut(shortcut_keys) || d.session_workspace_keys(shortcut_keys) {
		return 0
	}

	// Window controls own typing; global switching can replace a control.
	// Empty reads also settle an incomplete terminal escape sequence.
	controls := d.take_window_overlay_keys(shortcut_keys)
	defer {
		if controls.len > 0 && controls.str != shortcut_keys.str {
			unsafe { controls.free() }
		}
	}
	if controls.len == 0 {
		return 0
	}

	// Keep the original panel brightness binding for the legacy input path.
	mut rest := if key > 0 && d.focused_kitty_window() && !d.start_menu_open {
		// Toolkit-independent applications need the ordinary F1/F2 keys too.
		controls
	} else {
		d.take_brightness_keys(controls)
	}
	if rest.len == 0 {
		return 0
	}
	rest = d.take_files_settings_shortcut(rest)
	if rest.len == 0 {
		return 0
	}

	// Window-management chords are taken before a focused app gets text. Cmd-W
	// must close a terminal or editor window rather than inserting an escape
	// sequence into it.
	rest = d.take_window_shortcuts(rest)
	if rest.len == 0 {
		return 0
	}

	if !d.focused_kitty_window() || d.start_menu_open { rest = d.take_paste_keys(rest) }
	if rest.len == 0 {
		return 0
	}

	// An open Start menu owns typing before the focused application does:
	// printable keys search, Backspace edits, Return launches and Escape closes.
	if d.start_menu_open {
		d.start_menu_key_input(rest)
		return 0
	}

	// An application that takes typed input gets it while it is focused, and
	// the desktop's own shortcuts stand down: a terminal cannot have `q` close
	// the desktop out from under whoever is typing.
	if d.focused_app_takes_keys() {
		mut settings_app_index := -1
		for window in d.windows {
			if window.id == d.focus && window.title == files_settings_window_title {
				settings_app_index = window.app_index
				break
			}
		}
		if key > 0 && d.send_physical_framebuffer_key(d.focus, key, modifiers, value, keys) {
			return d.focus
		}
		d.send_keys_to_focused(rest)
		if settings_app_index >= 0 {
			d.refresh_files_settings_clients(settings_app_index)
		}
		return 0
	}

	// Control chords rather than bare letters. These fire whenever no
	// application has the keyboard, which on a machine with no working pointer
	// is most of the time -- and a plain `q` meaning "close the desktop" then
	// means typing a word with a q in it drops the user back to the console.
	// Esc is out for the same reason: it is a key people press.
	for i := 0; i < rest.len; i++ {
		match rest[i] {
			key_ctrl_p {
				d.toggle_start_menu()
			}
			key_ctrl_q {
				d.running = false
			}
			key_ctrl_n {
				d.spawn_scattered()
			}
			key_ctrl_k {
				// The first native application, for a keyboard-only session.
				if available_apps.len > 0 {
					d.launch(available_apps[0])
				}
			}
			else {}
		}
	}
	return 0
}

// take_brightness_keys acts on every F1/F2 in the input and returns what is
// left. The common case is a string containing neither, which is returned as
// it came rather than rebuilt -- there is no garbage collector here, and this
// runs on every frame that has input.
fn (mut d Desktop) take_brightness_keys(keys string) string {
	if keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len}
	mut i := 0
	for i < keys.len {
		if i + key_f1.len <= keys.len {
			three := unsafe { tos(keys.str + i, key_f1.len) }
			if three == key_f1 {
				adjust_brightness(-brightness_step)
				i += key_f1.len
				continue
			}
			if three == key_f2 {
				adjust_brightness(brightness_step)
				i += key_f2.len
				continue
			}
		}
		kept << keys[i]
		i++
	}
	if kept.len == keys.len {
		unsafe { kept.free() }
		return keys
	}
	text := kept.bytestr()
	unsafe { kept.free() }
	return text
}

// The desktop's own shortcuts, as a raw terminal delivers them. The keyboard
// is read in raw mode, so a control chord arrives as one byte and nothing else
// can be mistaken for it.
const key_ctrl_k = u8(0x0b)
const key_ctrl_n = u8(0x0e)
const key_ctrl_p = u8(0x10)
const key_ctrl_q = u8(0x11)
// F1 and F2, as the Apple SPI keyboard encodes them. They are the brightness
// keys printed on the machine's own keycaps, so they drive the panel here.
const key_f1 = '\x1bOP'
const key_f2 = '\x1bOQ'
