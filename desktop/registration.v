// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// First-launch user registration. This runs before ordinary desktop windows are
// created, so there is no taskbar, shortcut, or closable window to get around.
module main

import ui2

const registration_max_name = 48
const registration_max_password = 128

const action_registration_name = 'registration.name'
const action_registration_password = 'registration.password'
const action_registration_confirm = 'registration.confirm'
const action_registration_create = 'registration.create'

const registration_backdrop = u32(0x172235)
const registration_card = u32(0xfbfcfe)
const registration_field_bg = u32(0xffffff)
const registration_error = u32(0xc0392b)

enum RegistrationField {
	name
	password
	confirm
}

struct RegistrationState {
mut:
	field         RegistrationField
	name          []u8
	name_display  []u8
	password      []u8
	password_mask []u8
	confirm       []u8
	confirm_mask  []u8
	error         string
	complete      bool
}

fn new_registration_state() RegistrationState {
	mut state := RegistrationState{
		name:          []u8{cap: registration_max_name}
		name_display:  []u8{cap: registration_max_name + 1}
		password:      []u8{cap: registration_max_password}
		password_mask: []u8{cap: registration_max_password + 1}
		confirm:       []u8{cap: registration_max_password}
		confirm_mask:  []u8{cap: registration_max_password + 1}
	}
	// The caret lives in the ui2 text field's displayed text. It is not a
	// separate view painted over the field, so text and caret share the
	// textbox's own clipping, padding and rendering.
	state.name_display << `|`
	unsafe {
		state.name.flags |= .noslices
		state.name_display.flags |= .noslices
		state.password.flags |= .noslices
		state.password_mask.flags |= .noslices
		state.confirm.flags |= .noslices
		state.confirm_mask.flags |= .noslices
	}
	return state
}

fn registration_text(value []u8) string {
	if value.len == 0 {
		return ''
	}
	return unsafe { tos(value.data, value.len) }
}

fn (mut r RegistrationState) close() {
	registration_zero_and_free(mut r.name)
	registration_zero_and_free(mut r.name_display)
	registration_zero_and_free(mut r.password)
	registration_zero_and_free(mut r.password_mask)
	registration_zero_and_free(mut r.confirm)
	registration_zero_and_free(mut r.confirm_mask)
	r.error = ''
}

fn registration_bytes_equal(left []u8, right []u8) bool {
	if left.len != right.len {
		return false
	}
	for i in 0 .. left.len {
		if left[i] != right[i] {
			return false
		}
	}
	return true
}

fn (mut r RegistrationState) remove_caret() {
	match r.field {
		.name {
			if r.name_display.len > 0 {
				r.name_display.delete_last()
			}
		}
		.password {
			if r.password_mask.len > 0 {
				r.password_mask.delete_last()
			}
		}
		.confirm {
			if r.confirm_mask.len > 0 {
				r.confirm_mask.delete_last()
			}
		}
	}
}

fn (mut r RegistrationState) add_caret() {
	match r.field {
		.name { r.name_display << `|` }
		.password { r.password_mask << `|` }
		.confirm { r.confirm_mask << `|` }
	}
}

fn (mut r RegistrationState) focus(field RegistrationField) {
	r.remove_caret()
	r.field = field
	r.add_caret()
	r.error = ''
}

fn (mut r RegistrationState) submit(home string) {
	name := registration_text(r.name).trim_space()
	defer { unsafe { name.free() } }
	if !registration_valid_name(name) {
		r.focus(.name)
		r.error = 'Enter a name.'
		return
	}
	if r.password.len == 0 {
		r.focus(.password)
		r.error = 'Enter a password.'
		return
	}
	if !registration_bytes_equal(r.password, r.confirm) {
		r.focus(.confirm)
		r.error = 'Passwords do not match.'
		return
	}
	if !desktop_save_user(home, name, r.password) {
		r.error = 'Could not save the user. Try again.'
		return
	}
	r.error = ''
	r.complete = true
}

fn (mut r RegistrationState) handle_action(action string, home string) {
	match action {
		action_registration_name {
			r.focus(.name)
		}
		action_registration_password {
			r.focus(.password)
		}
		action_registration_confirm {
			r.focus(.confirm)
		}
		action_registration_create {
			r.submit(home)
		}
		else {}
	}
}

fn (mut r RegistrationState) backspace() {
	r.remove_caret()
	match r.field {
		.name {
			if r.name.len > 0 {
				r.name.delete_last()
				r.name_display.delete_last()
			}
		}
		.password {
			if r.password.len > 0 {
				r.password.delete_last()
				r.password_mask.delete_last()
			}
		}
		.confirm {
			if r.confirm.len > 0 {
				r.confirm.delete_last()
				r.confirm_mask.delete_last()
			}
		}
	}
	r.add_caret()
	r.error = ''
}

fn (mut r RegistrationState) append(ch u8) {
	r.remove_caret()
	match r.field {
		.name {
			if r.name.len < registration_max_name {
				r.name << ch
				r.name_display << ch
			}
		}
		.password {
			if r.password.len < registration_max_password {
				r.password << ch
				r.password_mask << `*`
			}
		}
		.confirm {
			if r.confirm.len < registration_max_password {
				r.confirm << ch
				r.confirm_mask << `*`
			}
		}
	}
	r.add_caret()
	r.error = ''
}

fn (mut r RegistrationState) advance() {
	next := match r.field {
		.name { RegistrationField.password }
		.password { RegistrationField.confirm }
		.confirm { RegistrationField.name }
	}
	r.focus(next)
}

// Setup owns every byte from the keyboard. Escape and control chords are
// intentionally ignored instead of reaching the desktop's normal shortcuts.
fn (mut r RegistrationState) key_input(keys string, home string) {
	for i := 0; i < keys.len; i++ {
		ch := keys[i]
		match ch {
			0x1b {
				// Also discard the rest of an escape sequence so arrow keys do not
				// turn their trailing printable bytes into account data.
				return
			}
			9 {
				r.advance()
			}
			8, 127 {
				r.backspace()
			}
			`\n`, `\r` {
				if r.field == .confirm {
					r.submit(home)
					if r.complete {
						return
					}
				} else {
					r.advance()
				}
			}
			else {
				if ch >= 0x20 && ch < 0x7f {
					r.append(ch)
				}
			}
		}
	}
}

// registration_field_element is a real ui2 text field. `clickable` only lets
// the framebuffer compositor collect it as a hit target; the field itself owns
// all pixels, including the active caret carried in `display`.
fn registration_field_element(action string, display []u8, placeholder string, active bool,
	hovered bool, x int, y int, width int) ui2.Element {
	mut text := placeholder
	mut color := body_muted
	if display.len > 0 {
		text = registration_text(display)
		color = body_text
	}
	border := if active { 2 } else { 1 }
	field := ui2.text_field(action, placeholder, text, ui2.rect(f64(x), f64(y), f64(width), 38),
		ui2.BoxStyle{
			bg:            registration_field_bg
			radius:        6
			border_color:  if active || hovered { app_accent } else { body_rule }
			border_left:   border
			border_top:    border
			border_right:  border
			border_bottom: border
		}, ui2.TextStyle{
			color: color
			size:  13
			align: .left
		}, ui2.keyboard_default)
	return ui2.Element{
		...field
		clickable: true
	}
}

fn (r &RegistrationState) element(d &Desktop) ui2.Element {
	mut card_width := 440
	if card_width > d.canvas.width - 24 {
		card_width = d.canvas.width - 24
	}
	if card_width < 1 {
		card_width = 1
	}
	mut card_height := 420
	if card_height > d.canvas.height - 24 {
		card_height = d.canvas.height - 24
	}
	if card_height < 1 {
		card_height = 1
	}
	card_x := (d.canvas.width - card_width) / 2
	card_y := (d.canvas.height - card_height) / 2
	field_x := 32
	field_width := card_width - 64

	mut card_children := frame_elements(12)
	card_children << ui2.label('registration.title', 'Create your user', ui2.rect(32, 28,
		f64(field_width), 34), ui2.TextStyle{
		color: body_heading
		size:  24
		bold:  true
	})
	card_children << ui2.label('registration.subtitle', 'Finish setup to use Vinix.', ui2.rect(32,
		67, f64(field_width), 24), ui2.TextStyle{
		color: body_muted
		size:  12
	})

	card_children << ui2.label('', 'Name', ui2.rect(32, 104, f64(field_width), 18), ui2.TextStyle{
		color: body_text
		size:  11
		bold:  true
	})
	card_children << registration_field_element(action_registration_name, r.name_display,
		'Enter your name', r.field == .name, d.hover == action_registration_name, field_x, 124,
		field_width)

	card_children << ui2.label('', 'Password', ui2.rect(32, 176, f64(field_width), 18), ui2.TextStyle{
		color: body_text
		size:  11
		bold:  true
	})
	card_children << registration_field_element(action_registration_password, r.password_mask,
		'Enter a password', r.field == .password, d.hover == action_registration_password, field_x,
		196, field_width)

	card_children << ui2.label('', 'Confirm password', ui2.rect(32, 248, f64(field_width), 18),
		ui2.TextStyle{
			color: body_text
			size:  11
			bold:  true
		})
	card_children << registration_field_element(action_registration_confirm, r.confirm_mask,
		'Repeat the password', r.field == .confirm, d.hover == action_registration_confirm, field_x,
		268, field_width)

	card_children << ui2.label('registration.error', r.error, ui2.rect(32, 316, f64(field_width),
		24), ui2.TextStyle{
		color: registration_error
		size:  11
	})
	card_children << ui2.button(action_registration_create, 'Create user', ui2.rect(32, 350,
		f64(field_width), 40), ui2.BoxStyle{
		bg:     if d.hover == action_registration_create { u32(0x4a8ee7) } else { app_accent }
		radius: 6
	}, ui2.TextStyle{
		color: app_on_accent
		size:  13
		bold:  true
		align: .center
	})

	mut screen_children := frame_elements(1)
	screen_children << ui2.view('registration.window', ui2.rect(f64(card_x), f64(card_y),
		f64(card_width), f64(card_height)), ui2.BoxStyle{
		bg:            registration_card
		radius:        12
		border_color:  body_rule
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, card_children)
	return ui2.screen(registration_backdrop, screen_children)
}

fn (mut r RegistrationState) poll_pointer(mut d Desktop, mut pointer PointerDevice, home string) bool {
	packet := pointer.poll() or { return false }
	if packet.max_x <= 0 || packet.max_y <= 0 {
		d.pointer_present = false
		return true
	}
	d.pointer_present = true
	d.pointer_x = int(i64(packet.x) * i64(d.canvas.width - 1) / i64(packet.max_x))
	d.pointer_y = int(i64(packet.y) * i64(d.canvas.height - 1) / i64(packet.max_y))
	d.buttons = packet.buttons
	d.hover = d.hit_action(d.pointer_x, d.pointer_y)
	if packet.pressed & button_left != 0 {
		r.handle_action(d.hover, home)
	}
	return true
}

// No ordinary desktop state is created until this returns. Consequently the
// registration card is not an overlay: it is the entire interactive desktop
// and has no close/minimise path to bypass it.
fn (mut d Desktop) ensure_registered_user(mut fb Framebuffer, mut pointer PointerDevice,
	mut keyboard Keyboard, frame_interval i64, idle_interval i64) {
	if desktop_user_registered(desktop_home) {
		return
	}
	mut registration := new_registration_state()
	defer { registration.close() }
	mut dirty := true
	for !registration.complete {
		if !dirty {
			desktop_wait_for_input(pointer.fd, keyboard.fd, idle_interval)
		}
		power := desktop_pending_power_action()
		if power != .keep_running {
			desktop_power_apply(power)
		}
		if registration.poll_pointer(mut d, mut pointer, desktop_home) {
			dirty = true
		}
		keys := keyboard.poll()
		if keys.len > 0 {
			registration.key_input(keys, desktop_home)
			dirty = true
		}
		if registration.complete || !dirty {
			continue
		}
		frame_started := monotonic_millis()
		begin_frame_elements()
		tree := registration.element(d)
		d.render(tree)
		fb.present(&d.canvas, desktop_current_scale())
		free_tree(tree)
		dirty = false
		sleep_to_next_frame(frame_started, frame_interval)
	}
	// Do not let the first ordinary input sample see setup hit targets or a
	// button level left over from pressing Create user.
	d.targets.clear()
	d.hover = ''
	d.buttons = 0
	d.drag = Drag{}
	d.pointer_capture = 0
	d.dirty = true
}
