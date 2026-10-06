// SPDX-License-Identifier: GPL-2.0-or-later
// An inline, transactional HH:MM:SS draft for the selected timer.
module main

fn clock_parse_duration(text string) ?u64 {
	if text.len != 8 || text[2] != `:` || text[5] != `:` { return none }
	for index in [0, 1, 3, 4, 6, 7]! {
		if text[index] < `0` || text[index] > `9` { return none }
	}
	hours := int(text[0] - `0`) * 10 + int(text[1] - `0`)
	minutes := int(text[3] - `0`) * 10 + int(text[4] - `0`)
	seconds := int(text[6] - `0`) * 10 + int(text[7] - `0`)
	if minutes > 59 || seconds > 59 { return none }
	total := hours * 3600 + minutes * 60 + seconds
	if total < 1 || total > 86_400 { return none }
	return u64(total) * 1000
}

fn (a &ClockApp) duration_text() string {
	return unsafe { tos(&a.duration_draft[0], a.duration_length) }
}

fn (mut a ClockApp) cancel_duration_edit() {
	a.duration_editing = false
	a.duration_selected = false
	a.duration_error = false
	a.duration_length = 0
}

fn (mut a ClockApp) edit_timer_duration() {
	a.initialize_timers()
	if a.tab != 1 || a.timers[a.selected_timer].running { return }
	a.name_focus = false
	a.name_pending_len = 0
	seconds := a.timers[a.selected_timer].duration_ms / 1000
	hours := seconds / 3600
	minutes := seconds / 60 % 60
	remainder := seconds % 60
	a.duration_draft[0] = u8(hours / 10) + `0`
	a.duration_draft[1] = u8(hours % 10) + `0`
	a.duration_draft[2] = `:`
	a.duration_draft[3] = u8(minutes / 10) + `0`
	a.duration_draft[4] = u8(minutes % 10) + `0`
	a.duration_draft[5] = `:`
	a.duration_draft[6] = u8(remainder / 10) + `0`
	a.duration_draft[7] = u8(remainder % 10) + `0`
	a.duration_length = 8
	a.duration_selected = true
	a.duration_editing = true
	a.duration_error = false
}

fn (mut a ClockApp) apply_timer_duration() bool {
	if !a.duration_editing || a.tab != 1 { return false }
	if a.timers[a.selected_timer].running {
		a.duration_error = true
		return false
	}
	milliseconds := clock_parse_duration(a.duration_text()) or {
		a.duration_error = true
		return false
	}
	a.set_timer_duration(milliseconds)
	a.cancel_duration_edit()
	return true
}

fn (mut a ClockApp) paste_duration(text string) {
	if !a.duration_editing || a.tab != 1 || text.len == 0 { return }
	start := if a.duration_selected { 0 } else { a.duration_length }
	if start + text.len > a.duration_draft.len {
		a.duration_error = true
		return
	}
	// Reject the whole paste before replacing selected text. Partial drafts
	// can be typed, but only a valid eight-byte duration can change a timer.
	for ch in text {
		if ch != `:` && (ch < `0` || ch > `9`) {
			a.duration_error = true
			return
		}
	}
	for offset in 0 .. text.len { a.duration_draft[start + offset] = text[offset] }
	a.duration_length = start + text.len
	a.duration_selected = false
	a.duration_error = false
}

fn (mut a ClockApp) duration_key_input(input string) {
	if input.len > 1 && input[0] == 27 { return }
	for ch in input {
		if !a.duration_editing { return }
		match ch {
			27, 9 { a.cancel_duration_edit() }
			13, 10 { if a.apply_timer_duration() { a.refresh() } }
			1 { a.duration_selected = true }
			8, 127 {
				if a.duration_selected {
					a.duration_length = 0
				} else if a.duration_length > 0 {
					a.duration_length--
				}
				a.duration_selected = false
				a.duration_error = false
			}
			else {
				if ch == `:` || (ch >= `0` && ch <= `9`) {
					a.paste_duration(unsafe { tos(&ch, 1) })
				}
			}
		}
	}
}
