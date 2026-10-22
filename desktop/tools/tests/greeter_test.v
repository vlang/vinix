// SPDX-License-Identifier: GPL-2.0-or-later
module main

import authproto
import loginchannel
import ui2

fn test_greeter_keeps_bounded_password_out_of_display_and_erases_removed_bytes() {
	mut state := new_greeter_state()
	defer { state.close() }
	state.key_input('person\tprivate phrase', 0)
	assert state.name.bytestr() == 'person'
	assert state.password.bytestr() == 'private phrase'
	assert state.mask.bytestr() == '**************|'
	assert state.password.cap == loginchannel.max_password
	storage := state.password.data
	state.key_input('\x7f', 0)
	assert state.password.len == 13
	assert unsafe { (&u8(storage))[13] } == 0
	state.clear_password()
	assert state.password.len == 0
	for i in 0 .. 14 { assert unsafe { (&u8(storage))[i] } == 0 }
	state.key_input('x'.repeat(200), 0)
	assert state.password.len == loginchannel.max_password && state.password.data == storage
	state.key_input('\x1brest must be discarded', 0)
	assert state.password.len == 0
}

fn test_greeter_authentication_status_is_bounded_and_does_not_echo_service_fields() {
	mut state := new_greeter_state()
	defer { state.close() }
	mut denied := authproto.text_frame(authproto.status_denied, 'PRIVATE SERVICE DIAGNOSTIC')
	state.answer(denied, 100)
	denied.close()
	assert state.message == 'Login incorrect. Please try again.'
	mut waiting := authproto.text_frame(authproto.status_wait, '30')
	state.answer(waiting, 100)
	waiting.close()
	assert state.retry_at == 30_100
	state.key_input('ignored secret', 200)
	assert state.password.len == 0
	assert state.tick(30_100) && state.retry_at == 0
	for text in ['', '0', '3601', '1x', '99999', '-1'] {
		mut malformed := authproto.text_frame(authproto.status_wait, text)
		state.answer(malformed, 100)
		malformed.close()
		assert state.failed && !state.accepted
		state.failed = false
	}
	mut malformed_ok := authproto.text_frame(authproto.status_ok, 'unexpected identity')
	state.answer(malformed_ok, 100)
	malformed_ok.close()
	assert state.failed && !state.accepted
}

fn test_greeter_scenes_contain_only_masked_secret_and_fit_small_displays() {
	mut state := new_greeter_state()
	defer { state.close() }
	state.key_input('person\tDO-NOT-RENDER', 0)
	for size in [[320, 240], [640, 480], [1024, 768]] {
		desktop := Desktop{ canvas: Canvas{width: size[0], height: size[1], scale: 1} }
		begin_frame_elements()
		tree := state.element(&desktop)
		assert_greeter_tree(tree, f64(size[0]), f64(size[1]))
		free_tree(tree)
	}
}

fn assert_greeter_tree(tree ui2.Element, width f64, height f64) {
	assert !tree.text.contains('DO-NOT-RENDER')
	assert tree.frame.x >= 0 && tree.frame.y >= 0
	if tree.id == 'greeter.window' {
		assert tree.frame.x + tree.frame.width <= width && tree.frame.y + tree.frame.height <= height
		for child in tree.children {
			assert child.frame.x + child.frame.width <= tree.frame.width
			assert child.frame.y + child.frame.height <= tree.frame.height
		}
	}
	for child in tree.children { assert_greeter_tree(child, width, height) }
}
