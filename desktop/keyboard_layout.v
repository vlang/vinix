// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Keyboard layouts: what a key types once the desktop's chosen input source
// has had its say.
//
// The console keyboard drivers speak the US layout: a key arrives as the byte
// it has on a US keyboard, the ISO key between left Shift and Z as `§`, Option
// (Alt) as an escape in front of the key, and Ctrl and Cmd chords already
// turned into control bytes and CSI-u sequences. Each of those names a key by
// its position, so the compositor can re-type printable keys in another layout
// the way an X server's keymap does, while Ctrl-C, Cmd-W and every other
// shortcut stay on the keys they are printed on whatever the layout.
//
// The tables below are the standard PC layouts (xkb `ru`, `es`, `fr`, `de`,
// `pt`), including their dead accent keys. Option types a layout's AltGr
// characters -- the ones printed on the keycaps, such as the German `@` on Q
// -- and an Option chord a layout has nothing for still reaches applications
// as the US key with Meta. Ctrl-Space moves to the next enabled input source.
module main

import ui2

// How long the input-source panel stays up after Ctrl-Space.
const keyboard_hud_ms = i64(1200)
// A sequence the console delivered whole can still be split by a short read.
// Its remainder is already waiting then; a key pressed after Escape is not.
const keyboard_sequence_gap_ms = i64(50)
// Linux's KDGETLED, and the bit in its answer that is Caps Lock.
const keyboard_kdgetled = u64(0x4b31)
const keyboard_led_caps = u8(0x04)

// ── Tables ─────────────────────────────────────────────────────────

// Dead keys are written as the combining mark they put on the next letter.
const dead_grave = rune(0x0300)
const dead_acute = rune(0x0301)
const dead_circumflex = rune(0x0302)
const dead_tilde = rune(0x0303)
const dead_diaeresis = rune(0x0308)

// Every key the US layout types something on, unshifted and shifted, in the
// order the layout tables list them: the number row, then the three letter
// rows, then the ISO key.
const keymap_us_lower = '`1234567890-=qwertyuiop[]\\asdfghjkl;\'zxcvbnm,./§'.runes()
const keymap_us_upper = '~!@#\$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:"ZXCVBNM<>?±'.runes()
const keymap_key_count = 48
const keymap_iso_key = 47
// The US [ key: Option on it and the start of every CSI are both ESC [.
const keymap_bracket_key = 23
// For each US byte, its key times two plus one if it is the shifted level.
const keymap_us_slots = keymap_build_us_slots()

// Keymap is what one layout types on those keys. `option` is the AltGr level,
// zero where the layout prints nothing there.
struct Keymap {
	lower  []rune
	upper  []rune
	option []rune
}

// Option levels are written as pairs: the key as the US layout names it
// unshifted, then what Option types on it.
fn new_keymap(lower string, upper string, option string) Keymap {
	mut levels := []rune{len: keymap_key_count}
	pairs := option.runes()
	for i := 0; i + 1 < pairs.len; i += 2 {
		index := keymap_us_lower.index(pairs[i])
		if index >= 0 {
			levels[index] = pairs[i + 1]
		}
	}
	return Keymap{
		lower:  lower.runes()
		upper:  upper.runes()
		option: levels
	}
}

fn keymap_build_us_slots() []int {
	mut slots := []int{len: 128, init: -1}
	for index, key in keymap_us_lower {
		if key < 128 {
			slots[int(key)] = index * 2
		}
	}
	for index, key in keymap_us_upper {
		if key < 128 {
			slots[int(key)] = index * 2 + 1
		}
	}
	return slots
}

// ЙЦУКЕН, with № and the punctuation on the number row where xkb `ru` has it.
const keymap_russian = new_keymap('ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю./',
	'Ё!"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,|', '')

const keymap_spanish = new_keymap('º1234567890\'¡qwertyuiop\u0300+çasdfghjklñ\u0301zxcvbnm,.-<',
	'ª!"·\$%&/()=?¿QWERTYUIOP\u0302*ÇASDFGHJKLÑ\u0308ZXCVBNM;:_>',
	'`\\1|2@3#4~6¬e€[[]]\\}\'{')

// AZERTY. Digits are the shifted level of the number row, as on the keycaps.
const keymap_french = new_keymap('²&é"\'(-è_çà)=azertyuiop\u0302\$*qsdfghjklmùwxcvbn,;:!<',
	'³1234567890°+AZERTYUIOP\u0308£µQSDFGHJKLM%WXCVBN?./§>',
	'2~3#4{5[6|7`8\\9^0@-]=}e€]¤')

// QWERTZ.
const keymap_german = new_keymap('\u03021234567890ß\u0301qwertzuiopü+#asdfghjklöäyxcvbnm,.-<',
	'°!"§\$%&/()=?\u0300QWERTZUIOPÜ*\'ASDFGHJKLÖÄYXCVBNM;:_>',
	'2²3³7{8[9]0}-\\q@e€]~mµ§|')

// Portugal's layout; the accents are on the two keys right of P and L.
const keymap_portuguese = new_keymap('\\1234567890\'«qwertyuiop+\u0301\u0303asdfghjklçºzxcvbnm,.-<',
	'|!"#\$%&/()=?»QWERTYUIOP*\u0300\u0302ASDFGHJKLÇªZXCVBNM;:_>',
	'2@3£4§7{8[9]0}e€[\u0308§\\')

fn keymap_for(layout KeyboardLayout) ?Keymap {
	return match layout {
		.us { none }
		.russian { keymap_russian }
		.spanish { keymap_spanish }
		.french { keymap_french }
		.german { keymap_german }
		.portuguese { keymap_portuguese }
	}
}

// What each dead key does to the letters it can sit on.
struct DeadKey {
	mark    rune
	spacing rune
	bases   []rune
	letters []rune
}

const dead_keys = [
	DeadKey{dead_grave, `\``, 'aeiouAEIOU'.runes(), 'àèìòùÀÈÌÒÙ'.runes()},
	DeadKey{dead_acute, `´`, 'aeiouyAEIOUY'.runes(), 'áéíóúýÁÉÍÓÚÝ'.runes()},
	DeadKey{dead_circumflex, `^`, 'aeiouAEIOU'.runes(), 'âêîôûÂÊÎÔÛ'.runes()},
	DeadKey{dead_tilde, `~`, 'anoANO'.runes(), 'ãñõÃÑÕ'.runes()},
	DeadKey{dead_diaeresis, `¨`, 'aeiouyAEIOUY'.runes(), 'äëïöüÿÄËÏÖÜŸ'.runes()},
]

fn dead_key_for(mark rune) ?DeadKey {
	for key in dead_keys {
		if key.mark == mark {
			return key
		}
	}
	return none
}

// keymap_upper is the capital of a letter the layouts type, or the rune
// itself when it has none.
fn keymap_upper(r rune) rune {
	if (r >= `a` && r <= `z`) || (r >= 0xe0 && r <= 0xfe && r != 0xf7)
		|| (r >= 0x430 && r <= 0x44f) {
		return r - 0x20
	}
	return match r {
		0xff { rune(0x178) }
		0x153 { rune(0x152) }
		0x451 { rune(0x401) }
		else { r }
	}
}

// keymap_cased reports whether a key's two levels are a letter and its
// capital, which is what Caps Lock applies to.
fn keymap_cased(lower rune, upper rune) bool {
	return lower != upper && keymap_upper(lower) == upper
}

fn keymap_us_letter(index int) bool {
	key := keymap_us_lower[index]
	return key >= `a` && key <= `z`
}

// keymap_slot names the key at `at`: its slot, or -1 when the bytes there are
// not a US key, and how many bytes it took.
fn keymap_slot(keys string, at int) (int, int) {
	b := keys[at]
	if b < 128 {
		return keymap_us_slots[int(b)], 1
	}
	// The ISO key: § unshifted, ± shifted.
	if b == 0xc2 && at + 1 < keys.len {
		if keys[at + 1] == 0xa7 {
			return keymap_iso_key * 2, 2
		}
		if keys[at + 1] == 0xb1 {
			return keymap_iso_key * 2 + 1, 2
		}
	}
	return -1, 1
}

// keyboard_csi_start reports whether `b` can follow ESC [ in what the keyboard
// drivers send: a parameter digit, or the final byte of an arrow, Home, End or
// Shift-Tab.
fn keyboard_csi_start(b u8) bool {
	return (b >= `0` && b <= `9`) || b in [u8(`A`), `B`, `C`, `D`, `F`, `H`, `Z`]
}

fn keymap_bracket_option(table ?Keymap) rune {
	keymap := table or { return 0 }
	return keymap.option[keymap_bracket_key]
}

// ── Typing ─────────────────────────────────────────────────────────

enum KeyboardEscape {
	ground
	// The last read ended on an escape, which has been passed on already.
	escape
	// The last read ended on ESC [ in a layout that types something with
	// Option-[, and it has been held back to see whether a CSI follows.
	bracket
	csi
	ss3
}

// KeyboardInput is the typing state that outlives one read: a dead key
// waiting for its letter, and an escape sequence a read ended inside of.
struct KeyboardInput {
mut:
	dead      rune
	escape    KeyboardEscape
	escape_ms i64
	// When the input-source panel comes down, or zero while it is not up.
	hud_until i64
	// Caps Lock is the console's, so it is asked for only on a key where it
	// matters and the US bytes cannot say: one that is a letter in only one
	// of the two layouts.
	read_caps fn (int) bool = desktop_keyboard_caps_lock
}

fn desktop_keyboard_caps_lock(fd int) bool {
	mut leds := u8(0)
	if desktop_ioctl(fd, keyboard_kdgetled, &leds) != 0 {
		return false
	}
	return leds & keyboard_led_caps != 0
}

fn keyboard_put_rune(mut out []u8, r rune) {
	if r < 0x80 {
		out << u8(r)
		return
	}
	if r < 0x800 {
		out << u8(0xc0 | (r >> 6))
		out << u8(0x80 | (r & 0x3f))
		return
	}
	out << u8(0xe0 | (r >> 12))
	out << u8(0x80 | ((r >> 6) & 0x3f))
	out << u8(0x80 | (r & 0x3f))
}

// type_rune puts one character a key typed, composing it with a pending dead
// key. A dead key followed by Space or by itself types the accent alone, and
// one followed by a letter it has no form for types the accent and then the
// letter, so nothing typed is lost.
fn (mut k KeyboardInput) type_rune(mut out []u8, r rune) {
	if pending := dead_key_for(k.dead) {
		k.dead = 0
		if r == pending.mark || r == ` ` {
			keyboard_put_rune(mut out, pending.spacing)
			return
		}
		if _ := dead_key_for(r) {
			keyboard_put_rune(mut out, pending.spacing)
			k.dead = r
			return
		}
		index := pending.bases.index(r)
		if index >= 0 {
			keyboard_put_rune(mut out, pending.letters[index])
			return
		}
		keyboard_put_rune(mut out, pending.spacing)
		keyboard_put_rune(mut out, r)
		return
	}
	if _ := dead_key_for(r) {
		k.dead = r
		return
	}
	keyboard_put_rune(mut out, r)
}

// translate re-types a console read in the current input source, and moves to
// the next enabled one on Ctrl-Space (a NUL) when more than one is enabled.
// It answers whether the input source changed. Escape sequences, control bytes
// and anything that is not a US key pass through untouched; an unchanged read
// is returned as it came.
fn (mut k KeyboardInput) translate(keys string, mut settings Settings, fd int, now i64) (string, bool) {
	if k.escape != .ground && k.escape != .bracket
		&& (keys.len == 0 || now - k.escape_ms > keyboard_sequence_gap_ms) {
		k.escape = .ground
	}
	switching := keyboard_layout_count(settings.keyboard_layouts) > 1
	if k.escape != .bracket && (keys.len == 0 || (settings.keyboard_layout == .us
		&& k.dead == 0 && (!switching || keys.index_u8(0) < 0))) {
		// Still follow sequences, so a layout chosen in the middle of one does
		// not re-type the rest of it.
		for b in keys {
			k.follow_escape(b, now)
		}
		return keys, false
	}
	mut out := []u8{cap: keys.len + 8}
	mut table := keymap_for(settings.keyboard_layout)
	mut switched := false
	mut caps_known := false
	mut caps := false
	if k.escape == .bracket {
		k.escape = .ground
		bracket := keymap_bracket_option(table)
		if bracket == 0 || (keys.len > 0 && now - k.escape_ms <= keyboard_sequence_gap_ms
			&& keyboard_csi_start(keys[0])) {
			// A sequence the read split after all.
			out << 0x1b
			out << `[`
			k.escape = .csi
		} else {
			k.type_rune(mut out, bracket)
		}
	}
	mut i := 0
	for i < keys.len {
		b := keys[i]
		if k.escape != .ground {
			if k.escape == .escape && b != `[` && b != `O` {
				// An Option chord whose escape went out with the last read
				// stays the US key, as Meta.
				k.escape = .ground
				if b >= 0x20 && b < 0x7f {
					out << b
					i++
					continue
				}
			} else {
				k.follow_escape(b, now)
				out << b
				i++
				continue
			}
		}
		if b == 0x1b {
			k.dead = 0
			k.follow_escape(b, now)
			out << b
			i++
			if i >= keys.len {
				continue
			}
			next := keys[i]
			bracket := keymap_bracket_option(table)
			if next == `[` && bracket != 0 {
				if i + 1 >= keys.len {
					// Wait a frame for the rest of a sequence the read split.
					out.delete_last()
					k.escape = .bracket
					k.escape_ms = now
					i++
					continue
				}
				if !keyboard_csi_start(keys[i + 1]) {
					out.delete_last()
					k.escape = .ground
					k.type_rune(mut out, bracket)
					i++
					continue
				}
			}
			if next == `[` || next == `O` || next < 0x20 || next == 0x7f {
				// A sequence, or Meta on a control key; the loop follows it.
				continue
			}
			k.escape = .ground
			slot, width := keymap_slot(keys, i)
			if chord_map := table {
				if slot >= 0 {
					index := slot >> 1
					mut shifted := slot & 1 == 1
					if keymap_us_letter(index) {
						// The driver applied Caps Lock to the US letter.
						if !caps_known {
							caps = k.read_caps(fd)
							caps_known = true
						}
						shifted = shifted != caps
					}
					if !shifted && chord_map.option[index] != 0 {
						// Option types the layout's AltGr character instead.
						out.delete_last()
						k.type_rune(mut out, chord_map.option[index])
						i += width
						continue
					}
				}
			}
			// Meta: the key as the US layout names it, so Alt shortcuts stay
			// where they are printed.
			for j in 0 .. width {
				out << keys[i + j]
			}
			i += width
			continue
		}
		if b == 0 && switching {
			settings.keyboard_layout = keyboard_next_layout(settings.keyboard_layouts,
				settings.keyboard_layout)
			table = keymap_for(settings.keyboard_layout)
			switched = true
			k.dead = 0
			i++
			continue
		}
		if b < 0x20 || b == 0x7f {
			// Return, Tab, Backspace and control chords cancel a dead key.
			k.dead = 0
			out << b
			i++
			continue
		}
		slot, width := keymap_slot(keys, i)
		keymap := table or {
			out << b
			i++
			continue
		}
		if slot < 0 {
			if b == ` ` {
				// Space after an accent types the accent alone.
				k.type_rune(mut out, ` `)
			} else {
				out << b
			}
			i++
			continue
		}
		index := slot >> 1
		lower := keymap.lower[index]
		upper := keymap.upper[index]
		mut shifted := slot & 1 == 1
		if keymap_us_letter(index) != keymap_cased(lower, upper) {
			// Caps Lock capitalises letters, and the driver only knew which
			// keys are letters on a US keyboard.
			if !caps_known {
				caps = k.read_caps(fd)
				caps_known = true
			}
			if caps {
				shifted = !shifted
			}
		}
		k.type_rune(mut out, if shifted { upper } else { lower })
		i += width
	}
	text := out.bytestr()
	unsafe { out.free() }
	return text, switched
}

// follow_escape tracks the keyboard's escape sequences: a CSI runs to its
// final byte, SS3 takes one more.
fn (mut k KeyboardInput) follow_escape(b u8, now i64) {
	match k.escape {
		.ground {
			if b == 0x1b {
				k.escape = .escape
				k.escape_ms = now
			}
		}
		.escape {
			k.escape = match b {
				`[` { KeyboardEscape.csi }
				`O` { KeyboardEscape.ss3 }
				0x1b { KeyboardEscape.escape }
				else { KeyboardEscape.ground }
			}
			k.escape_ms = now
		}
		.csi {
			if b >= 0x40 && b <= 0x7e {
				k.escape = .ground
			}
		}
		.ss3 {
			k.escape = .ground
		}
		// translate settles a held-back ESC [ before it follows anything.
		.bracket {}
	}
}

// ── The desktop ────────────────────────────────────────────────────

// type_with_layout is the first thing typing meets, so the Start menu, Quick
// Launch and applications all receive what the input source types.
fn (mut d Desktop) type_with_layout(keys string, fd int) string {
	now := monotonic_millis()
	if d.keyboard.hud_until != 0 && now >= d.keyboard.hud_until {
		d.keyboard.hud_until = 0
		d.dirty = true
	}
	if d.focused_app_wants_us_keys() {
		d.keyboard.dead = 0
		d.keyboard.escape = .ground
		return keys
	}
	text, switched := d.keyboard.translate(keys, mut d.settings, fd, now)
	if switched {
		d.keyboard.hud_until = now + keyboard_hud_ms
		d.dirty = true
	}
	if d.keyboard.escape == .bracket {
		// Come straight back for the next read, which settles it.
		d.dirty = true
	}
	return text
}

// focused_app_wants_us_keys is true for a game or a virtual machine on top,
// which read keys by where they are rather than by what they type.
fn (d &Desktop) focused_app_wants_us_keys() bool {
	index := d.focused_app_index() or { return false }
	app := d.apps[index]
	if app is RemoteApp {
		return app.us_keys
	}
	return false
}

// keyboard_hud_wait shortens an idle wait so the panel comes down on time.
fn (d &Desktop) keyboard_hud_wait(interval i64) i64 {
	if d.keyboard.hud_until == 0 {
		return interval
	}
	left := d.keyboard.hud_until - monotonic_millis()
	if left <= 0 {
		return 0
	}
	return if left < interval { left } else { interval }
}

const keyboard_hud_width = 220
const keyboard_hud_height = 64
const keyboard_hud_badge = 40

// keyboard_hud_element is the brief panel Ctrl-Space raises, naming the input
// source typing has just moved to.
fn (d &Desktop) keyboard_hud_element() ?ui2.Element {
	if d.keyboard.hud_until == 0 {
		return none
	}
	layout := d.settings.keyboard_layout
	inset := (keyboard_hud_height - keyboard_hud_badge) / 2
	badge := f64(keyboard_hud_badge)
	mut children := frame_elements(2)
	children << ui2.view('', ui2.rect(f64(inset), f64(inset), badge, badge), ui2.BoxStyle{
		bg:     d.theme().accent
		radius: 8
	}, frame_child(ui2.label('', layout.badge(), ui2.rect(0, 0, badge, badge), ui2.TextStyle{
		color: switcher_text
		size:  15
		bold:  true
		align: .center
		lines: 1
	})))
	text_x := inset * 2 + keyboard_hud_badge
	children << ui2.label('', layout.title(), ui2.rect(f64(text_x), 0, f64(keyboard_hud_width - text_x - inset), f64(keyboard_hud_height)), ui2.TextStyle{
		color: switcher_text
		size:  15
		bold:  true
		lines: 1
	})
	return ui2.view('', ui2.rect(f64((d.canvas.width - keyboard_hud_width) / 2), f64((d.canvas.height - keyboard_hud_height) / 2), f64(keyboard_hud_width), f64(keyboard_hud_height)), ui2.BoxStyle{
		bg:     switcher_bg
		radius: switcher_radius
	}, children)
}

// ── The input menu ─────────────────────────────────────────────────

// The taskbar names the current input source just left of the clock whenever
// there is more than one to choose from, as Windows' language bar and the Mac
// input menu do. Clicking it lists the enabled ones.
const action_tray_input = 'tray.input'
const tray_input_layout_prefix = 'tray.input.layout.'
// One per entry of keyboard_layouts, so a rebuild formats nothing.
const tray_input_layout_actions = ['tray.input.layout.0', 'tray.input.layout.1',
	'tray.input.layout.2', 'tray.input.layout.3', 'tray.input.layout.4', 'tray.input.layout.5']
const action_tray_keyboard_settings = 'tray.action.keyboard'
const tray_input_width = 34
const tray_input_badge_width = 26
const tray_input_badge_height = 18
const tray_input_menu_width = 232
const tray_input_row_height = 28

fn (d &Desktop) input_menu_shown() bool {
	return keyboard_layout_count(d.settings.keyboard_layouts) > 1
}

// clock_text_width is how much of its box the clock's right-aligned text
// covers. Its digits are all one width, so this holds still as the seconds
// tick and changes only with the date or the clock's format.
fn (d &Desktop) clock_text_width() int {
	if d.fonts.len == 0 {
		return taskbar_clock_width
	}
	time := d.face_for(ui2.TextStyle{
		size: taskbar_clock_time_size
		bold: true
	}).text_width(d.taskbar_clock_time)
	date := d.face_for(ui2.TextStyle{
		size: taskbar_clock_date_size
	}).text_width(d.taskbar_clock_date)
	widest := if time > date { time } else { date }
	return if widest < taskbar_clock_width { widest } else { taskbar_clock_width }
}

// input_menu_span is the room the button needs beyond what the clock's box
// leaves free left of its text. A 24-hour clock leaves enough, so the taskbar
// usually gives up nothing for it.
fn (d &Desktop) input_menu_span() int {
	if !d.input_menu_shown() {
		return 0
	}
	need := tray_input_width + taskbar_item_gap - (taskbar_clock_width - d.clock_text_width())
	return if need > 0 { need } else { 0 }
}

fn input_badge(text string, x int, y int, bg u32, color u32) ui2.Element {
	return ui2.view('', ui2.rect(f64(x), f64(y), f64(tray_input_badge_width), f64(tray_input_badge_height)),
		ui2.BoxStyle{
		bg:     bg
		radius: 4
	}, frame_child(ui2.label('', text, ui2.rect(0, 0, f64(tray_input_badge_width), f64(tray_input_badge_height)),
		ui2.TextStyle{
		color: color
		size:  11
		bold:  true
		align: .center
		lines: 1
	})))
}

// input_menu_button is the badge on the taskbar, cut out of a solid tag the
// way the Mac draws it, so it reads as a label and not as another status icon.
fn (d &Desktop) input_menu_button(x int, y int, height int) ui2.Element {
	theme := d.theme()
	open := d.tray.flyout == .input
	return ui2.clickable_view(action_tray_input, ui2.rect(f64(x), f64(y), f64(tray_input_width),
		f64(height)), ui2.BoxStyle{
		bg:          if open { theme.taskbar_item_active } else { theme.taskbar_item_hover }
		radius:      4
		transparent: d.hover != action_tray_input && !open
	}, frame_child(input_badge(d.settings.keyboard_layout.badge(), (tray_input_width - tray_input_badge_width) / 2,
		(height - tray_input_badge_height) / 2, theme.taskbar_text_active, theme.taskbar_bg)))
}

fn (d &Desktop) input_menu_row(id string, x int, y int, width int, children []ui2.Element) ui2.Element {
	return ui2.clickable_view(id, ui2.rect(f64(x), f64(y), f64(width), f64(tray_input_row_height)),
		ui2.BoxStyle{
		bg:          tray_flyout_button_hover
		radius:      5
		transparent: d.hover != id
	}, children)
}

// input_menu_children lays out the menu: the enabled input sources with a
// tick on the current one, then Keyboard settings. It answers the height.
fn (d &Desktop) input_menu_children(mut children []ui2.Element) int {
	pad := 6
	row_width := tray_input_menu_width - 2 * pad
	badge_x := 30
	text_x := badge_x + tray_input_badge_width + 10
	mut y := pad
	for index, layout in keyboard_layouts {
		if d.settings.keyboard_layouts & layout.bit() == 0 {
			continue
		}
		mut row := frame_elements(3)
		if layout == d.settings.keyboard_layout {
			check := ui2.image('', 'builtin:check', ui2.rect(8, 6, 16, 16))
			row << ui2.Element{
				...check
				text_style: ui2.TextStyle{
					color: tray_flyout_text
				}
			}
		}
		row << input_badge(layout.badge(), badge_x, (tray_input_row_height - tray_input_badge_height) / 2,
			tray_flyout_text, 0xffffff)
		row << ui2.label('', layout.title(), ui2.rect(f64(text_x), 0, f64(row_width - text_x - 8),
			f64(tray_input_row_height)), ui2.TextStyle{
			color: tray_flyout_text
			size:  13
			lines: 1
		})
		children << d.input_menu_row(tray_input_layout_actions[index], pad, y, row_width, row)
		y += tray_input_row_height
	}
	y += 5
	children << ui2.view('', ui2.rect(f64(pad + 8), f64(y), f64(row_width - 16), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	y += 6
	children << d.input_menu_row(action_tray_keyboard_settings, pad, y, row_width, frame_child(ui2.label('',
		'Keyboard settings', ui2.rect(f64(badge_x), 0, f64(row_width - badge_x - 8), f64(tray_input_row_height)),
		ui2.TextStyle{
		color: tray_flyout_text
		size:  13
		lines: 1
	})))
	y += tray_input_row_height
	children << ui2.label('', 'Ctrl-Space: next input source', ui2.rect(f64(pad + badge_x),
		f64(y + 2), f64(row_width - badge_x - 8), 18), ui2.TextStyle{
		color: tray_flyout_muted
		size:  11
		lines: 1
	})
	return y + 2 + 18 + pad
}

// choose_input_source is a pick from the menu. Like Ctrl-Space it drops an
// accent typed in the old source, and the preference file follows on its own.
fn (mut d Desktop) choose_input_source(index int) {
	d.close_tray_flyout()
	if index < 0 || index >= keyboard_layouts.len {
		return
	}
	layout := keyboard_layouts[index]
	if d.settings.keyboard_layouts & layout.bit() == 0 || d.settings.keyboard_layout == layout {
		return
	}
	d.settings.keyboard_layout = layout
	d.keyboard.dead = 0
	d.dirty = true
}
