// SPDX-License-Identifier: GPL-2.0-or-later
// An exclusive, unprivileged client of the root session manager. Account lookup,
// password checking and session selection remain entirely with the manager.
module main

import authproto
import loginchannel
import ui2

const action_greeter_name = 'greeter.name'
const action_greeter_password = 'greeter.password'
const action_greeter_login = 'greeter.login'

struct GreeterState {
mut:
	name []u8
	password []u8
	name_display []u8
	mask []u8
	password_focus bool
	busy bool
	accepted bool
	failed bool
	deadline i64
	retry_at i64
	message string
}

fn new_greeter_state() GreeterState {
	mut state := GreeterState{
		name: []u8{cap: loginchannel.max_name}
		password: []u8{cap: loginchannel.max_password}
		name_display: []u8{cap: loginchannel.max_name + 1}
		mask: []u8{cap: loginchannel.max_password + 1}
	}
	unsafe {
		state.name.flags |= .noslices
		state.password.flags |= .noslices
		state.name_display.flags |= .noslices
		state.mask.flags |= .noslices
	}
	state.display()
	return state
}

fn (mut state GreeterState) close() {
	wipe_login_input(unsafe { tos(state.password.data, state.password.len) })
	registration_zero_and_free(mut state.name)
	registration_zero_and_free(mut state.password)
	registration_zero_and_free(mut state.name_display)
	registration_zero_and_free(mut state.mask)
}

fn (mut state GreeterState) clear_password() {
	// Wipe the whole live secret before reducing its length. Backspace also
	// erases its removed byte; no discarded characters remain in the buffer.
	wipe_login_input(unsafe { tos(state.password.data, state.password.len) })
	state.password.clear()
	state.display()
}

fn (mut state GreeterState) display() {
	state.name_display.clear()
	state.name_display << state.name
	state.mask.clear()
	for _ in 0 .. state.password.len { state.mask << `*` }
	if !state.busy && !state.accepted && !state.failed {
		if state.password_focus { state.mask << `|` } else { state.name_display << `|` }
	}
}

fn (mut state GreeterState) submit(now i64) {
	if state.busy || state.accepted || state.failed || now < state.retry_at { return }
	if state.name.len == 0 || state.password.len == 0 {
		state.message = 'Enter your login name and password.'
		return
	}
	// login() wipes the borrowed password on success and every refusal. Never
	// convert this buffer to a V string, log it or put it in an argv/environment.
	loginchannel.login(state.name, state.password) or {
		unsafe { err.free() }
		state.clear_password()
		state.message = 'Sign-in is unavailable. Please try again.'
		state.failed = true
		return
	}
	state.clear_password()
	state.busy = true
	state.deadline = now + 180_000
	state.message = 'Signing in…'
	state.display()
}

fn (mut state GreeterState) answer(answer authproto.Frame, now i64) {
	state.busy = false
	state.clear_password()
	match answer.code {
		authproto.status_ok {
			if answer.fields.len != 0 {
				state.failed = true
				state.message = 'Sign-in is unavailable. Please try again.'
			} else {
				state.accepted = true
				state.message = 'Starting your session…'
			}
		}
		authproto.status_wait {
			mut seconds := 0
			if answer.fields.len == 1 && answer.fields[0].len > 0 && answer.fields[0].len <= 4 {
				for ch in answer.fields[0] {
					if ch < `0` || ch > `9` { seconds = 0; break }
					seconds = seconds * 10 + int(ch - `0`)
				}
			}
			if seconds < 1 || seconds > 3600 {
				state.failed = true
				state.message = 'Sign-in is unavailable. Please try again.'
			} else {
				state.retry_at = now + i64(seconds) * 1000
				state.message = 'Too many attempts. Please wait before trying again.'
			}
		}
		authproto.status_denied {
			state.message = 'Login incorrect. Please try again.'
		}
		else {
			// Service diagnostics are never rendered as markup or disclosed to
			// another account at the login screen.
			state.message = 'Sign-in is unavailable. Please try again.'
		}
	}
	state.password_focus = true
	state.display()
}

fn (mut state GreeterState) tick(now i64) bool {
	if state.retry_at != 0 && now >= state.retry_at {
		state.retry_at = 0
		state.message = ''
		return true
	}
	if !state.busy { return false }
	if loginchannel.ready() {
		mut answer := loginchannel.reply() or {
			unsafe { err.free() }
			state.busy = false
			state.failed = true
			state.message = 'Sign-in is unavailable. Please try again.'
			state.display()
			return true
		}
		defer { answer.close() }
		state.answer(answer, now)
		return true
	}
	if now >= state.deadline {
		state.busy = false
		state.failed = true
		state.message = 'Sign-in timed out. Please try again.'
		state.display()
		return true
	}
	return false
}

fn (mut state GreeterState) key_input(keys string, now i64) {
	if state.busy || state.accepted || state.failed || now < state.retry_at { return }
	for ch in keys {
		match ch {
			0x1b { state.clear_password(); return }
			9 { state.password_focus = !state.password_focus }
			8, 127 {
				if state.password_focus && state.password.len > 0 {
					state.password[state.password.len - 1] = 0
					state.password.delete_last()
				} else if !state.password_focus && state.name.len > 0 { state.name.delete_last() }
			}
			`\n`, `\r` {
				if state.password_focus { state.submit(now); return }
				state.password_focus = true
			}
			else {
				if ch >= 0x20 && ch < 0x7f {
					if state.password_focus && state.password.len < loginchannel.max_password { state.password << ch }
					else if !state.password_focus && state.name.len < loginchannel.max_name { state.name << ch }
				}
			}
		}
		state.message = ''
		state.display()
	}
}

fn (mut state GreeterState) action(action string, now i64) {
	if state.busy || state.accepted || state.failed || now < state.retry_at { return }
	match action {
		action_greeter_name { state.password_focus = false; state.display() }
		action_greeter_password { state.password_focus = true; state.display() }
		action_greeter_login { state.submit(now) }
		else {}
	}
}

fn (state &GreeterState) element(d &Desktop) ui2.Element {
	width := if d.canvas.width < 464 { d.canvas.width - 24 } else { 440 }
	height := if d.canvas.height < 344 { d.canvas.height - 24 } else { 320 }
	compact := height < 280
	padding := if compact { 16 } else { 28 }
	field_width := width - 2 * padding
	top := if compact { 42 } else { 70 }
	pitch := if compact { 44 } else { 68 }
	mut children := frame_elements(8)
	children << ui2.label('greeter.title', 'Sign in to Vinix', ui2.rect(f64(padding), 12, f64(field_width), 28), ui2.TextStyle{color: body_heading, size: if compact { 18 } else { 24 }, bold: true})
	children << registration_field_element(action_greeter_name, state.name_display, 'Login name', !state.password_focus && !state.busy, d.hover == action_greeter_name, padding, top, field_width)
	children << registration_field_element(action_greeter_password, state.mask, 'Password', state.password_focus && !state.busy, d.hover == action_greeter_password, padding, top + pitch, field_width)
	children << ui2.label('greeter.message', state.message, ui2.rect(f64(padding), f64(height - 76), f64(field_width), 26), ui2.TextStyle{color: registration_error, size: if compact { 9 } else { 11 }})
	children << ui2.button(action_greeter_login, if state.busy { 'Signing in…' } else { 'Sign in' }, ui2.rect(f64(padding), f64(height - 48), f64(field_width), 34), ui2.BoxStyle{bg: if state.busy || state.retry_at != 0 { body_muted } else { app_accent }, radius: 6}, ui2.TextStyle{color: app_on_accent, size: 13, bold: true, align: .center})
	mut screen := frame_elements(1)
	screen << ui2.view('greeter.window', ui2.rect(f64((d.canvas.width - width) / 2), f64((d.canvas.height - height) / 2), f64(width), f64(height)), ui2.BoxStyle{bg: registration_card, radius: 10}, children)
	return ui2.screen(registration_backdrop, screen)
}

fn (mut d Desktop) run_greeter(mut fb Framebuffer, mut pointer PointerDevice, mut keyboard Keyboard, frame_interval i64) {
	mut state := new_greeter_state()
	defer { state.close() }
	mut dirty := true
	for {
		if !dirty { desktop_wait_for_input(pointer.fd, keyboard.fd, 100) }
		now := monotonic_millis()
		if state.tick(now) { dirty = true }
		if desktop_pending_power_action() != .keep_running { return }
		if packet := pointer.poll() {
			d.pointer_present = true
			if packet.max_x > 0 && packet.max_y > 0 {
				d.pointer_x = int(i64(packet.x) * i64(d.canvas.width - 1) / i64(packet.max_x))
				d.pointer_y = int(i64(packet.y) * i64(d.canvas.height - 1) / i64(packet.max_y))
			} else {
				d.pointer_x = terminal_clamp(d.pointer_x + packet.x, 0, d.canvas.width - 1)
				d.pointer_y = terminal_clamp(d.pointer_y + packet.y, 0, d.canvas.height - 1)
			}
			d.buttons = packet.buttons
			d.set_hover(d.hit_action(d.pointer_x, d.pointer_y))
			if packet.pressed & button_left != 0 { state.action(d.hover, now) }
			dirty = true
		}
		keys := keyboard.poll_secret_text()
		if keys.len > 0 {
			state.key_input(keys, now)
			// Keyboard polling owns this buffer; erase the input copy as soon
			// as the exclusive screen has consumed it.
			wipe_login_input(keys)
			unsafe { keys.free() }
			dirty = true
		}
		if !dirty { continue }
		started := monotonic_millis()
		begin_frame_elements()
		tree := state.element(d)
		d.render(tree)
		fb.present(&d.canvas, desktop_current_scale())
		free_tree(tree)
		dirty = false
		if state.failed { desktop_sleep_ms(1500); return }
		sleep_to_next_frame(started, frame_interval)
	}
}
