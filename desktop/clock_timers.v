// SPDX-License-Identifier: GPL-2.0-or-later
// Four independent monotonic timers. Names live inline and never allocate.
module main

import ui2

const clock_timer_limit = 4
const clock_timer_name_limit = 48
const clock_timer_actions = ['clock.timer.select.0', 'clock.timer.select.1',
	'clock.timer.select.2', 'clock.timer.select.3']!

struct ClockTimer {
mut:
	duration_ms  u64 = 300_000
	remaining_ms u64 = 300_000
	started_ms   u64
	running      bool
	done         bool
	name         [clock_timer_name_limit]u8
	name_len     int
}

fn (mut a ClockApp) initialize_timers() {
	if a.timer_count > 0 { return }
	a.timers[0] = ClockTimer{}
	a.timer_count = 1
	a.selected_timer = 0
}

fn (timer &ClockTimer) remaining(now u64) u64 {
	if !timer.running || now == ~u64(0) || now < timer.started_ms { return timer.remaining_ms }
	elapsed := now - timer.started_ms
	return if elapsed >= timer.remaining_ms { u64(0) } else { timer.remaining_ms - elapsed }
}

fn (a &ClockApp) timer_remaining(now u64) u64 {
	if a.timer_count == 0 { return 300_000 }
	return a.timers[a.selected_timer].remaining(now)
}

fn (a &ClockApp) any_timer_running() bool {
	for index in 0 .. a.timer_count {
		if a.timers[index].running { return true }
	}
	return false
}

fn (mut a ClockApp) update_timer(now u64) {
	a.initialize_timers()
	mut first_finished := -1
	for index in 0 .. a.timer_count {
		if a.timers[index].running && a.timers[index].remaining(now) == 0 {
			a.timers[index].running = false
			a.timers[index].remaining_ms = 0
			a.timers[index].done = true
			if first_finished < 0 { first_finished = index }
		}
	}
	// Never redirect typing into another timer when a countdown finishes.
	if first_finished >= 0 && !a.name_focus && !a.duration_editing {
		a.selected_timer = first_finished
		a.tab = 1
	}
}

fn (mut a ClockApp) toggle_timer_at(now u64) {
	a.initialize_timers()
	if now == ~u64(0) { return }
	// Updating another expired timer may select it; this action still applies
	// to the timer the user clicked before that update.
	selected := a.selected_timer
	a.update_timer(now)
	a.selected_timer = selected
	if a.timers[selected].running {
		a.timers[selected].remaining_ms = a.timers[selected].remaining(now)
		a.timers[selected].running = false
	} else {
		if a.timers[selected].remaining_ms == 0 {
			a.timers[selected].remaining_ms = a.timers[selected].duration_ms
		}
		a.timers[selected].started_ms = now
		a.timers[selected].running = true
		a.timers[selected].done = false
	}
}

fn (mut a ClockApp) reset_timer() {
	a.initialize_timers()
	index := a.selected_timer
	a.timers[index].remaining_ms = a.timers[index].duration_ms
	a.timers[index].running = false
	a.timers[index].done = false
}

fn (mut a ClockApp) set_timer_duration(milliseconds u64) {
	a.initialize_timers()
	if a.timers[a.selected_timer].running || milliseconds < 1000 || milliseconds > 86_400_000 { return }
	a.timers[a.selected_timer].duration_ms = milliseconds
	a.reset_timer()
}

fn (mut a ClockApp) adjust_timer(delta i64) {
	a.initialize_timers()
	if a.timers[a.selected_timer].running { return }
	mut duration := i64(a.timers[a.selected_timer].duration_ms) + delta
	if duration < 1000 { duration = 1000 }
	if duration > 86_400_000 { duration = 86_400_000 }
	a.set_timer_duration(u64(duration))
}

fn (mut a ClockApp) add_timer() bool {
	a.initialize_timers()
	if a.timer_count == clock_timer_limit { return false }
	a.cancel_duration_edit()
	a.selected_timer = a.timer_count
	a.timers[a.timer_count] = ClockTimer{}
	a.timer_count++
	return true
}

fn (mut a ClockApp) remove_timer() bool {
	a.initialize_timers()
	if a.timer_count <= 1 || a.timers[a.selected_timer].running { return false }
	for index in a.selected_timer + 1 .. a.timer_count {
		a.timers[index - 1] = a.timers[index]
	}
	a.timer_count--
	a.timers[a.timer_count] = ClockTimer{}
	if a.selected_timer >= a.timer_count { a.selected_timer = a.timer_count - 1 }
	a.cancel_duration_edit()
	a.name_focus = false
	a.name_pending_len = 0
	return true
}

fn (a &ClockApp) timer_name(index int) string {
	return unsafe { tos(&a.timers[index].name[0], a.timers[index].name_len) }
}

fn (mut a ClockApp) paste_input(text string) {
	if a.duration_editing { a.paste_duration(text); return }
	if !a.name_focus || a.tab != 1 { return }
	a.name_pending_len = 0
	// Validate the complete paste before replacing a selected name. This
	// preserves both the name and selection when invalid input is rejected.
	if !notes_valid_text(text, clock_timer_name_limit, false) || text.len == 0 { return }
	index := a.selected_timer
	start := if a.name_selected { 0 } else { a.timers[index].name_len }
	if start + text.len > clock_timer_name_limit { return }
	for offset in 0 .. text.len { a.timers[index].name[start + offset] = text[offset] }
	a.timers[index].name_len = start + text.len
	a.name_selected = false
}

fn (mut a ClockApp) key_input(input string) {
	if a.duration_editing { a.duration_key_input(input); return }
	if !a.name_focus || a.tab != 1 { return }
	if input.len > 1 && input[0] == 27 { a.name_pending_len = 0; return }
	for ch in input {
		if ch == 27 || ch == 13 || ch == 10 || ch == 9 {
			a.name_focus = false
			a.name_pending_len = 0
			return
		}
		if ch == 1 { a.name_selected = true; a.name_pending_len = 0; continue }
		if ch == 8 || ch == 127 {
			a.name_pending_len = 0
			index := a.selected_timer
			mut length := if a.name_selected { 0 } else { a.timers[index].name_len }
			if length > 0 {
				length--
				for length > 0 && a.timers[index].name[length] & 0xc0 == 0x80 { length-- }
			}
			a.timers[index].name_len = length
			a.name_selected = false
			continue
		}
		if a.name_pending_len > 0 {
			if editor_utf8_follows(a.name_pending[0], a.name_pending_len, ch) {
				a.name_pending[a.name_pending_len] = ch
				a.name_pending_len++
				if a.name_pending_len == editor_utf8_length(a.name_pending[0]) {
					text := unsafe { tos(&a.name_pending[0], a.name_pending_len) }
					a.paste_input(text)
				}
				continue
			}
			a.name_pending_len = 0
		}
		length := editor_utf8_length(ch)
		if length == 1 {
			a.paste_input(unsafe { tos(&ch, 1) })
		} else if length > 1 {
			a.name_pending[0] = ch
			a.name_pending_len = 1
		}
	}
}

fn (a &ClockApp) timer_button_text(index int, columns int) string {
	mut fallback := ''
	mut text := a.timer_name(index)
	if text.len == 0 {
		number := (index + 1).str()
		fallback = tr_fill('clock.timer.number', number)
		unsafe { number.free() }
		text = fallback
	}
	mut buffer := [128]u8{}
	buffer[0] = u8(index + 1) + `0`
	buffer[1] = if a.timers[index].done { `!` } else if a.timers[index].running { `*` } else { ` ` }
	buffer[2] = ` `
	mut at := 0
	mut characters := 0
	for at < text.len && characters < columns {
		length := editor_utf8_length(text[at])
		for offset in 0 .. length { buffer[3 + at + offset] = text[at + offset] }
		at += length
		characters++
	}
	mut total := at + 3
	if at < text.len {
		buffer[total] = 0xe2; buffer[total + 1] = 0x80; buffer[total + 2] = 0xa6
		total += 3
	}
	result := unsafe { tos(&buffer[0], total) }.clone()
	if fallback.len > 0 { unsafe { fallback.free() } }
	return result
}

fn (mut a ClockApp) append_timer(mut children []ui2.Element, width int) {
	pad := 24
	inner := width - 2 * pad
	button_width := (inner - 24) / clock_timer_limit
	for index in 0 .. a.timer_count {
		children << ui2.Element{
			...clock_control(clock_timer_actions[index], a.timer_button_text(index, (button_width - 40) / 16),
				pad + index * (button_width + 8), 148, button_width, a.selected_timer == index)
			id: frame_owned_text_id
			action_id: clock_timer_actions[index]
		}
	}
	mut name_children := frame_elements(1)
	name_children << ui2.text_field('', tr('clock.timer.name'), a.timer_name(a.selected_timer),
		ui2.rect(8, 0, f64(inner - 224), 30), ui2.BoxStyle{transparent: true},
		ui2.TextStyle{color: body_text, size: 12}, 0)
	children << ui2.clickable_view('clock.timer.name', ui2.rect(f64(pad), 184, f64(inner - 208), 30),
		ui2.BoxStyle{bg: body_panel, radius: 5, border_color: if a.name_focus { app_accent } else { body_rule },
			border_top: 1, border_bottom: 1, border_left: 1, border_right: 1}, name_children)
	children << ui2.Element{
		...clock_control('clock.timer.add', tr('clock.timer.add'), width - 220, 184, 92, false)
		enabled: a.timer_count < clock_timer_limit
	}
	children << ui2.Element{
		...clock_control('clock.timer.remove', tr('clock.timer.remove'), width - 120, 184, 96, false)
		enabled: a.timer_count > 1 && !a.timers[a.selected_timer].running
	}
	children << ui2.label('', a.timer_text, ui2.rect(f64(pad), 218, f64(inner - 112), 42),
		ui2.TextStyle{color: clock_stopwatch, font_family: 'mono', size: 28, bold: true, align: .center})
	children << ui2.Element{
		...clock_control('clock.timer.duration', tr('clock.timer.duration'), width - 120, 224, 96, a.duration_editing)
		enabled: !a.timers[a.selected_timer].running
	}
	center := width / 2
	if a.duration_editing {
		mut draft_children := frame_elements(1)
		draft_children << ui2.Element{
			...ui2.text_field('', tr('clock.timer.duration.field'), a.duration_text(),
				ui2.rect(8, 0, f64(inner - 208), 30), ui2.BoxStyle{transparent: true},
				ui2.TextStyle{color: body_text, font_family: 'mono', size: 14}, 0)
			focused: true
			text_selection: ui2.TextSelection{
				anchor: if a.duration_selected { 0 } else { a.duration_length }
				caret: a.duration_length
			}
		}
		children << ui2.clickable_view('clock.timer.duration.field', ui2.rect(f64(pad), 264, f64(inner - 192), 30),
			ui2.BoxStyle{bg: body_panel, radius: 5, border_color: app_accent,
				border_top: 1, border_bottom: 1, border_left: 1, border_right: 1}, draft_children)
		children << clock_control('clock.timer.duration.apply', tr('clock.timer.duration.apply'), width - 208, 264, 88, true)
		children << clock_control('clock.timer.duration.cancel', tr('clock.timer.duration.cancel'), width - 112, 264, 88, false)
	} else {
		children << clock_control('clock.timer.less', '-1', center - 148, 264, 44, false)
		children << clock_control('clock.timer.preset.1', tr('clock.timer.preset.1'), center - 96, 264, 58, false)
		children << clock_control('clock.timer.preset.5', tr('clock.timer.preset.5'), center - 30, 264, 58, false)
		children << clock_control('clock.timer.preset.15', tr('clock.timer.preset.15'), center + 36, 264, 66, false)
		children << clock_control('clock.timer.more', '+1', center + 110, 264, 44, false)
	}
	children << ui2.Element{
		...clock_control('clock.timer.toggle', if a.timers[a.selected_timer].running { tr('clock.stop') } else { tr('clock.start') }, center - 118, 300, 112, true)
		enabled: !a.duration_editing
	}
	children << clock_control('clock.timer.reset', tr('clock.reset'), center + 6, 300, 112, false)
	children << ui2.label('', tr(if a.duration_editing {
		if a.duration_error { 'clock.timer.duration.invalid' } else { 'clock.timer.duration.help' }
	} else if a.timers[a.selected_timer].done { 'clock.timer.finished' } else { 'clock.timer.legend' }),
		ui2.rect(f64(pad), 334, f64(inner), 18),
		ui2.TextStyle{color: if a.duration_error || a.timers[a.selected_timer].done { clock_stop } else { body_muted }, size: 11, align: .center})
	children << ui2.label('', tr('clock.timer.scope'), ui2.rect(f64(pad), 354, f64(inner), 16),
		ui2.TextStyle{color: body_muted, size: 10, align: .center})
}
