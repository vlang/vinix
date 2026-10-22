// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn registration_secret_assert_zero(data voidptr, length int) {
	bytes := unsafe { &u8(data) }
	for index in 0 .. length { assert unsafe { bytes[index] } == 0 }
}

fn registration_secret_retire(text string) {
	wipe_login_input(text)
	registration_secret_assert_zero(text.str, text.len)
	if text.len > 0 { unsafe { text.free() } }
}

fn test_registration_erases_capacity_after_truncation_and_emptying() {
	mut bytes := []u8{len: registration_max_password, cap: registration_max_password, init: `s`}
	bytes.flags |= .noslices
	defer { registration_zero_and_free(mut bytes) }
	bytes.trim(3)
	registration_zero(bytes)
	registration_secret_assert_zero(bytes.data, bytes.cap)
	unsafe {
		for index in 0 .. bytes.cap { (&u8(bytes.data))[index] = `t` }
	}
	bytes.clear()
	assert bytes.len == 0
	registration_zero(bytes)
	registration_secret_assert_zero(bytes.data, bytes.cap)
}

fn test_registration_backspace_erases_password_and_confirmation_immediately() {
	mut state := new_registration_state()
	defer { state.close() }
	for field in [RegistrationField.password, .confirm]! {
		state.focus(field)
		state.key_input('secret', '')
		state.backspace()
		if field == .password {
			assert registration_text(state.password) == 'secre'
			assert unsafe { (&u8(state.password.data))[5] } == 0
		} else {
			assert registration_text(state.confirm) == 'secre'
			assert unsafe { (&u8(state.confirm.data))[5] } == 0
		}
		for _ in 0 .. 5 { state.backspace() }
		if field == .password { registration_secret_assert_zero(state.password.data, 6) }
		else { registration_secret_assert_zero(state.confirm.data, 6) }
	}
}

fn test_registration_secret_buffers_stay_bounded_and_close_retires_them() {
	mut state := new_registration_state()
	for field in [RegistrationField.password, .confirm]! {
		state.focus(field)
		for _ in 0 .. registration_max_password + 20 { state.append(`x`) }
		if field == .password {
			assert state.password.len == registration_max_password
			assert state.password.cap == registration_max_password
		} else {
			assert state.confirm.len == registration_max_password
			assert state.confirm.cap == registration_max_password
		}
	}
	state.close()
	assert state.password.len == 0 && state.password.cap == 0
	assert state.confirm.len == 0 && state.confirm.cap == 0
	state.close()
}

fn test_registration_secret_poll_owns_legacy_text_and_erases_retired_copy() {
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]); desktop_close(pair[1]) }
	mut keyboard := Keyboard{fd: pair[0]}
	assert desktop_write(pair[1], c'secret', 6) == 6
	text := keyboard.poll_secret_text()
	assert text == 'secret'
	registration_secret_retire(text)
}

fn test_registration_secret_poll_scrubs_completed_and_invalid_physical_packets() {
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]); desktop_close(pair[1]) }
	assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
	mut keyboard := Keyboard{fd: pair[0], key_events: true}
	assert desktop_write(pair[1], c'\x1b[?31;', 6) == 6
	assert keyboard.poll_secret_text() == ''
	assert keyboard.packet_used == 6
	assert keyboard.packet[0] == 27 && keyboard.packet[5] == `;`
	assert desktop_write(pair[1], c'1k\x1b[?31;0k', 10) == 10
	text := keyboard.poll_secret_text()
	assert text == 's'
	assert keyboard.packet_used == 0 && !keyboard.held[31]
	registration_secret_assert_zero(&keyboard.packet[0], keyboard.packet.len)
	registration_secret_retire(text)
	assert desktop_write(pair[1], c'\x1b[?999;1k', 9) == 9
	assert keyboard.poll_secret_text() == ''
	registration_secret_assert_zero(&keyboard.packet[0], keyboard.packet.len)
	assert keyboard.poll_secret_text() == ''
}

fn test_registration_secret_input_repeatedly_retires_packet_text_and_state() {
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]); desktop_close(pair[1]) }
	mut keyboard := Keyboard{fd: pair[0], key_events: true}
	mut state := new_registration_state()
	defer { state.close() }
	state.focus(.password)
	packet := '\x1b[?31;1k\x1b[?31;0k'
	for _ in 0 .. 1000 {
		assert desktop_write(pair[1], packet.str, u64(packet.len)) == packet.len
		text := keyboard.poll_secret_text()
		assert text == 's'
		state.key_input(text, '')
		registration_secret_retire(text)
		state.backspace()
		assert state.password.len == 0
		registration_secret_assert_zero(state.password.data, 1)
		registration_secret_assert_zero(&keyboard.packet[0], keyboard.packet.len)
	}
}
