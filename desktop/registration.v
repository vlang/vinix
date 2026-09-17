// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// First-launch user registration. This runs before ordinary desktop windows are
// created, so there is no taskbar, shortcut, or closable window to get around.
module main

import crypto.scrypt
import encoding.hex
import io.util
import os
import ui2

const desktop_user_record_name = '.vinix-user'
const desktop_user_record_max_bytes = 1024
const registration_max_name = 48
const registration_max_password = 128
const registration_salt_bytes = 16
const registration_hash_bytes = u64(32)
const registration_scrypt_n = u64(16_384)
const registration_scrypt_r = u32(8)
const registration_scrypt_p = u32(1)
const registration_user_home_mode = 0o700

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
		password:      []u8{cap: registration_max_password}
		password_mask: []u8{cap: registration_max_password}
		confirm:       []u8{cap: registration_max_password}
		confirm_mask:  []u8{cap: registration_max_password}
	}
	unsafe {
		state.name.flags |= .noslices
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

fn registration_zero_and_free(mut value []u8) {
	for i in 0 .. value.len {
		value[i] = 0
	}
	if value.cap > 0 {
		unsafe { value.free() }
	}
	value = []u8{}
}

fn (mut r RegistrationState) close() {
	registration_zero_and_free(mut r.name)
	registration_zero_and_free(mut r.password)
	registration_zero_and_free(mut r.password_mask)
	registration_zero_and_free(mut r.confirm)
	registration_zero_and_free(mut r.confirm_mask)
	r.error = ''
}

fn registration_valid_name(name string) bool {
	if name.len == 0 || name.len > registration_max_name {
		return false
	}
	mut visible := false
	for i in 0 .. name.len {
		ch := name[i]
		if ch < 0x20 || ch >= 0x7f {
			return false
		}
		if ch != ` ` {
			visible = true
		}
	}
	return visible
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

fn desktop_user_record_path(home string) string {
	return '${home}/${desktop_user_record_name}'
}

// The system image is disposable while /root is the persistent desktop volume.
// Turn the display name into one portable directory component under that volume.
fn registration_directory_name(name string) string {
	mut bytes := []u8{cap: name.len}
	mut separator := false
	for i in 0 .. name.len {
		ch := name[i]
		if (ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) {
			if separator && bytes.len > 0 {
				bytes << `-`
			}
			bytes << ch
			separator = false
		} else if ch >= `A` && ch <= `Z` {
			if separator && bytes.len > 0 {
				bytes << `-`
			}
			bytes << ch + 32
			separator = false
		} else if bytes.len > 0 {
			separator = true
		}
	}
	if bytes.len == 0 {
		unsafe { bytes.free() }
		return 'user'.clone()
	}
	result := bytes.bytestr()
	unsafe { bytes.free() }
	return result
}

fn desktop_user_home_path(home string, name string) string {
	directory := registration_directory_name(name)
	path := '${home}/${directory}'
	unsafe { directory.free() }
	return path
}

// Registration is still a single-user desktop, but it now has a real persistent
// home directory. An already-created profile from an older image repairs its
// missing directory here the next time the desktop starts.
fn desktop_ensure_user_directory(home string, name string) bool {
	path := desktop_user_home_path(home, name)
	defer { unsafe { path.free() } }
	info := os.lstat(path) or {
		os.mkdir(path) or { return false }
		os.chmod(path, registration_user_home_mode) or {
			os.rmdir(path) or {}
			return false
		}
		$if vinix {
			// Vinix's persistent /root is a separate block-backed filesystem.
			// Make a repaired directory durable even when no profile write follows.
			C.sync()
		}
		return true
	}
	if info.get_filetype() != .directory {
		return false
	}
	os.chmod(path, registration_user_home_mode) or { return false }
	return true
}

// A valid profile is the registration marker. Keep enough information for a
// later login screen to verify the password without ever storing it directly.
fn desktop_load_user_name(home string) ?string {
	if home == '' {
		return none
	}
	path := desktop_user_record_path(home)
	info := os.lstat(path) or { return none }
	if info.get_filetype() != .regular || info.size == 0
		|| info.size > u64(desktop_user_record_max_bytes) || info.mode & 0o077 != 0 {
		return none
	}
	record := os.read_file(path) or { return none }
	if record.len == 0 || record.len > desktop_user_record_max_bytes {
		unsafe { record.free() }
		return none
	}
	clean := record.trim_space()
	unsafe { record.free() }
	lines := clean.split_into_lines()
	defer {
		unsafe {
			lines.free()
			clean.free()
		}
	}
	if lines.len != 8 || lines[0] != 'version=1' || !lines[1].starts_with('name=')
		|| lines[2] != 'kdf=scrypt' || lines[3] != 'n=16384' || lines[4] != 'r=8'
		|| lines[5] != 'p=1' || !lines[6].starts_with('salt=')
		|| !lines[7].starts_with('hash=') {
		return none
	}
	name_bytes := hex.decode(lines[1][5..]) or { return none }
	defer { unsafe { name_bytes.free() } }
	name := name_bytes.bytestr()
	if !registration_valid_name(name) {
		unsafe { name.free() }
		return none
	}
	salt := hex.decode(lines[6][5..]) or {
		unsafe { name.free() }
		return none
	}
	defer { unsafe { salt.free() } }
	digest := hex.decode(lines[7][5..]) or {
		unsafe { name.free() }
		return none
	}
	defer { unsafe { digest.free() } }
	if salt.len != registration_salt_bytes || digest.len != int(registration_hash_bytes) {
		unsafe { name.free() }
		return none
	}
	return name
}

fn desktop_user_registered(home string) bool {
	name := desktop_load_user_name(home) or { return false }
	ok := desktop_ensure_user_directory(home, name)
	unsafe { name.free() }
	return ok
}

fn registration_random_bytes(count int) ?[]u8 {
	mut file := os.open('/dev/urandom') or { return none }
	defer { file.close() }
	mut bytes := []u8{len: count}
	mut offset := 0
	for offset < bytes.len {
		read := file.read(mut bytes[offset..]) or {
			registration_zero_and_free(mut bytes)
			return none
		}
		if read <= 0 {
			registration_zero_and_free(mut bytes)
			return none
		}
		offset += read
	}
	return bytes
}

fn desktop_save_user(home string, name string, password []u8) bool {
	if home == '' || !os.is_dir(home) || !registration_valid_name(name) || password.len == 0 {
		return false
	}
	if !desktop_ensure_user_directory(home, name) {
		return false
	}
	mut salt := registration_random_bytes(registration_salt_bytes) or { return false }
	mut digest := scrypt.scrypt(password, salt, registration_scrypt_n, registration_scrypt_r,
		registration_scrypt_p, registration_hash_bytes) or {
		registration_zero_and_free(mut salt)
		return false
	}
	name_bytes := name.bytes()
	name_hex := hex.encode(name_bytes)
	unsafe { name_bytes.free() }
	salt_hex := hex.encode(salt)
	hash_hex := hex.encode(digest)
	registration_zero_and_free(mut salt)
	registration_zero_and_free(mut digest)

	record := 'version=1\nname=${name_hex}\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=${salt_hex}\nhash=${hash_hex}\n'
	path := desktop_user_record_path(home)
	mut file, temporary := util.temp_file(path: home, pattern: '${desktop_user_record_name}.*') or {
		return false
	}
	mut published := false
	defer {
		file.close()
		if !published {
			os.rm(temporary) or {}
		}
		unsafe { temporary.free() }
	}
	os.chmod(temporary, 0o600) or { return false }
	file.set_unbuffered()
	file.write_string(record) or { return false }
	if !desktop_preferences_fsync(file.fd) {
		return false
	}
	os.rename_dir(temporary, path) or { return false }
	published = true
	if !desktop_preferences_sync_directory(home, file.fd) {
		os.rm(path) or {}
		return false
	}
	return true
}

fn (mut r RegistrationState) submit(home string) {
	name := registration_text(r.name).trim_space()
	defer { unsafe { name.free() } }
	if !registration_valid_name(name) {
		r.field = .name
		r.error = 'Enter a name.'
		return
	}
	if r.password.len == 0 {
		r.field = .password
		r.error = 'Enter a password.'
		return
	}
	if !registration_bytes_equal(r.password, r.confirm) {
		r.field = .confirm
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
			r.field = .name
			r.error = ''
		}
		action_registration_password {
			r.field = .password
			r.error = ''
		}
		action_registration_confirm {
			r.field = .confirm
			r.error = ''
		}
		action_registration_create {
			r.submit(home)
		}
		else {}
	}
}

fn (mut r RegistrationState) backspace() {
	match r.field {
		.name {
			if r.name.len > 0 {
				r.name.delete_last()
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
	r.error = ''
}

fn (mut r RegistrationState) append(ch u8) {
	match r.field {
		.name {
			if r.name.len < registration_max_name {
				r.name << ch
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
	r.error = ''
}

fn (mut r RegistrationState) advance() {
	r.field = match r.field {
		.name { .password }
		.password { .confirm }
		.confirm { .name }
	}
	r.error = ''
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

fn registration_field_text_width(d &Desktop, value []u8) int {
	if value.len == 0 {
		return 0
	}
	if d.fonts.len == 0 {
		return value.len * 7
	}
	face := d.face_for(ui2.TextStyle{
		size: 13
	})
	return face.text_width(registration_text(value))
}

fn registration_field_element(d &Desktop, action string, value []u8, placeholder string, active bool,
	hovered bool, x int, y int, width int) ui2.Element {
	mut text := placeholder
	mut color := body_muted
	if value.len > 0 {
		text = registration_text(value)
		color = body_text
	}
	border := if active { 2 } else { 1 }
	mut text_x := 10
	if active && value.len == 0 {
		// Leave the caret clear of the placeholder when the field is empty.
		text_x = 15
	}
	mut children := frame_elements(2)
	children << ui2.label('', text, ui2.rect(f64(text_x), 0, f64(width - text_x - 8), 38),
		ui2.TextStyle{
			color: color
			size: 13
			align: .left
		})
	if active {
		mut caret_x := 10 + registration_field_text_width(d, value) + 1
		if value.len == 0 {
			caret_x = 10
		}
		if caret_x > width - 12 {
			caret_x = width - 12
		}
		children << ui2.view('registration.caret', ui2.rect(f64(caret_x), 10, 2, 18),
			ui2.BoxStyle{
				bg: body_text
			}, [])
	}
	return ui2.clickable_view(action, ui2.rect(f64(x), f64(y), f64(width), 38), ui2.BoxStyle{
		bg:            registration_field_bg
		radius:        6
		border_color:  if active || hovered { app_accent } else { body_rule }
		border_left:   border
		border_top:    border
		border_right:  border
		border_bottom: border
	}, children)
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
	card_children << registration_field_element(d, action_registration_name, r.name, 'Enter your name',
		r.field == .name, d.hover == action_registration_name, field_x, 124, field_width)

	card_children << ui2.label('', 'Password', ui2.rect(32, 176, f64(field_width), 18), ui2.TextStyle{
		color: body_text
		size:  11
		bold:  true
	})
	card_children << registration_field_element(d, action_registration_password, r.password_mask,
		'Enter a password', r.field == .password, d.hover == action_registration_password, field_x,
		196, field_width)

	card_children << ui2.label('', 'Confirm password', ui2.rect(32, 248, f64(field_width), 18),
		ui2.TextStyle{
			color: body_text
			size:  11
			bold:  true
		})
	card_children << registration_field_element(d, action_registration_confirm, r.confirm_mask,
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
