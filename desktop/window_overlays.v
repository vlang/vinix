// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct WindowOverlayInput {
mut:
	pending     [32]u8
	pending_len int
	pending_owned bool
}

// Window controls own pointer input and cursor visibility while they cover
// applications. Keep all compositor paths on the same modal policy.
fn (d &Desktop) window_overlay_active() bool {
	return d.overview.active || d.window_layout.active || d.snap_assist.active
		|| d.window_actions.active
}

fn (mut d Desktop) close_window_overlays() {
	d.close_window_actions()
	d.close_window_snap_assist()
	d.close_window_overview()
	d.close_window_layout()
}

// Completed navigation packets and normal text belong to the active control.
// Its output is consumed even if Enter/Escape dismissed it partway through.
fn (mut d Desktop) consume_window_overlay_keys(keys string) {
	result := if d.window_actions.active {
		d.take_window_actions_keys(keys)
	} else if d.snap_assist.active {
		d.take_window_snap_assist_keys(keys)
	} else if d.overview.active {
		d.take_window_overview_keys(keys)
	} else if d.window_layout.active {
		d.take_window_layout_keys(keys)
	} else {
		keys
	}
	if result.len > 0 && result.str != keys.str {
		unsafe { result.free() }
	}
}

fn window_overlay_switch_sequence(sequence string) bool {
	for key in switcher_keys {
		if key.step != switch_commit && sequence == key.bytes {
			return true
		}
	}
	return sequence == key_alt_tab || sequence == key_alt_shift_tab
}

// A single bounded prefix owner follows the terminal protocol. Cascading the
// inactive controls' parsers would repeatedly recapture an expired Escape.
fn window_overlay_sequence_complete(sequence string) bool {
	if sequence.len < 2 {
		return false
	}
	if sequence[1] == `O` {
		return sequence.len >= 3
	}
	if sequence[1] != `[` {
		return true
	}
	if sequence.len < 3 {
		return false
	}
	last := sequence[sequence.len - 1]
	return (last >= 0x40 && last <= 0x7e) || last < 0x20 || last > 0x7e
}

// Handle the global control chords once, before delivering the remaining
// stream to a switcher or application. Unrelated packets retain every byte.
fn (mut d Desktop) take_window_overlay_keys(keys string) string {
	if keys.len == 0 {
		length := d.overlay_input.pending_len
		owned := d.overlay_input.pending_owned
		d.overlay_input.pending_len = 0
		d.overlay_input.pending_owned = false
		if length == 0 {
			if d.window_overlay_active() {
				d.consume_window_overlay_keys('')
			}
			return keys
		}
		sequence := unsafe { tos(&d.overlay_input.pending[0], length) }
		if d.window_overlay_active() {
			if length == 1 {
				d.close_window_overlays()
			} else {
				d.consume_window_overlay_keys(sequence)
				d.consume_window_overlay_keys('')
			}
			return ''
		}
		if d.switcher.quick_launch {
			d.switcher_close()
			return ''
		}
		if owned { return '' }
		return sequence.clone()
	}
	if !d.window_overlay_active() && !d.switcher.quick_launch && d.overlay_input.pending_len == 0
		&& keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len + d.overlay_input.pending_len}
	mut owned_input := d.window_overlay_active()
	mut changed := false
	mut i := 0
	for i < keys.len {
		ch := keys[i]
		if d.overlay_input.pending_len == 0 && ch != 0x1b {
			start := i
			for i < keys.len && keys[i] != 0x1b { i++ }
			if !owned_input && d.switcher.quick_launch {
				d.quick_launch_take_keys(unsafe { tos(keys.str + start, i - start) })
				changed = true
			} else if !owned_input && !d.overlay_input.pending_owned {
				for at in start .. i { kept << keys[at] }
			} else {
				d.consume_window_overlay_keys(unsafe { tos(keys.str + start, i - start) })
				changed = true
			}
			continue
		}
		// A new Escape terminates a malformed CSI/SS3 prefix. Keep the
		// prefix intact and start the new packet rather than losing its ESC.
		if ch == 0x1b && d.overlay_input.pending_len >= 2 {
			length := d.overlay_input.pending_len
			sequence := unsafe { tos(&d.overlay_input.pending[0], length) }
			if !owned_input && !d.overlay_input.pending_owned {
				for byte in sequence { kept << byte }
			} else {
				d.consume_window_overlay_keys(sequence)
				d.consume_window_overlay_keys('')
				changed = true
			}
			d.overlay_input.pending_len = 0
			d.overlay_input.pending_owned = false
		}
		if d.overlay_input.pending_len == 0 {
			d.overlay_input.pending_owned = owned_input || d.switcher.quick_launch
		}
		d.overlay_input.pending[d.overlay_input.pending_len] = ch
		d.overlay_input.pending_len++
		i++
		sequence := unsafe { tos(&d.overlay_input.pending[0], d.overlay_input.pending_len) }
		complete := window_overlay_sequence_complete(sequence)
		if !complete && d.overlay_input.pending_len < d.overlay_input.pending.len {
			continue
		}
		packet_owned := owned_input || d.overlay_input.pending_owned
		d.overlay_input.pending_len = 0
		d.overlay_input.pending_owned = false
		if complete && (sequence == key_window_actions || sequence == key_window_actions_legacy) {
			d.open_window_actions(d.focus)
			owned_input = owned_input || d.window_actions.active
			changed = true
		} else if complete && sequence == key_window_overview {
			d.window_overview_sequence(sequence)
			owned_input = true
			changed = true
		} else if complete && sequence == key_super_z {
			d.open_window_layout(d.focus)
			owned_input = owned_input || d.window_layout.active
			changed = true
		} else if complete && (window_overlay_switch_sequence(sequence)
			|| sequence == key_alt_f4 || sequence == key_cmd_w) {
			d.close_window_overlays()
			if sequence == key_alt_f4 || sequence == key_cmd_w {
				d.take_window_shortcuts(sequence)
			} else if d.switcher.quick_launch {
				d.quick_launch_take_sequence(sequence, 0)
			} else {
				d.take_switcher_sequence(sequence, 0)
			}
			changed = true
		} else if complete && (sequence == key_alt_released || sequence == quick_launch_cmd_release) {
			// Releasing a chord rearms Quick Launch but leaves menus open.
			d.take_switcher_sequence(sequence, 0)
			changed = true
		} else if complete && !d.window_overlay_active() && window_shortcut_sequence(sequence) {
			d.take_window_shortcuts(sequence)
			owned_input = owned_input || d.window_overlay_active()
			changed = true
		} else if !owned_input && d.switcher.quick_launch {
			if complete {
				d.quick_launch_take_keys(sequence)
			} else {
				d.switcher_close()
			}
			changed = true
		} else if complete && !packet_owned && d.switcher.active
			&& d.take_switcher_sequence(sequence, 0) > seq_none {
			changed = true
		} else if !packet_owned {
			for byte in sequence { kept << byte }
		} else {
			d.consume_window_overlay_keys(sequence)
			if !complete { d.consume_window_overlay_keys('') }
			changed = true
		}
	}
	if kept.len == 0 {
		unsafe { kept.free() }
		return ''
	}
	if !changed && d.overlay_input.pending_len == 0 && kept.len == keys.len {
		unsafe { kept.free() }
		return keys
	}
	result := kept.bytestr()
	unsafe { kept.free() }
	return result
}
