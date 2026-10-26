// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

import time

fn C.socketpair(i32, i32, i32, &i32) i32

fn bad_frame(frame []u8) bool {
	decoded := decode_request_bytes(frame) or { return true }
	dispose_request(decoded)
	return false
}

fn bad_request(request Request) bool {
	encoded := encode_request(request) or { return true }
	unsafe { encoded.free() }
	return false
}

fn wire_request(frame []u8, end_write bool, timeout time.Duration) !Request {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	assert C.send(sockets[1], frame.data, uint(frame.len), 0) == frame.len
	if end_write { assert C.shutdown(sockets[1], C.SHUT_WR) == 0 }
	return receive_request_frame(sockets[0], time.sys_mono_now() + timeout)
}

fn redemption_fixture() Request {
	return Request{
		id: 0x1020304050607080
		operation: .redeem_interaction
		redemption: Redemption{request: 0x8877665544332211, capability: []u8{len: 32, init: u8(index + 1)}}
	}
}

fn test_redemption_frame_contains_only_original_request_and_ticket() {
	expected := redemption_fixture()
	mut frame := encode_request(expected)!
	defer { unsafe { frame.free() } }
	assert frame.len == 60
	assert frame[..8] == [u8(`V`), `X`, `A`, `1`, 0, 1, 0, 3]
	assert frame[16..20] == [u8(0), 0, 0, 40]
	assert frame[20..28] == [u8(0x88), 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11]
	decoded := decode_request_bytes(frame)!
	defer { dispose_request(decoded) }
	assert decoded == expected
	assert decoded.account_type == none && decoded.auth_token_type == none
	assert decoded.features.len == 0 && decoded.options.len == 0
	// The decoder owns its ticket independently of the encoded input.
	value := decoded.redemption or { panic('missing ticket') }
	frame[28] = 255
	assert value.capability[0] == 1
}

fn test_redemption_decoder_rejects_truncation_zero_ids_and_trailing_fields() {
	frame := encode_request(redemption_fixture())!
	defer { unsafe { frame.free() } }
	for length in 0 .. frame.len { assert bad_frame(frame[..length]) }
	for bounds in [[8, 16]!, [20, 28]!, [28, 60]!] {
		mut changed := frame.clone()
		for offset in bounds[0] .. bounds[1] { changed[offset] = 0 }
		assert bad_frame(changed)
		unsafe { changed.free() }
	}
	mut trailing := frame.clone()
	defer { unsafe { trailing.free() } }
	trailing << u8(1)
	assert bad_frame(trailing)
	trailing[19]++
	assert bad_frame(trailing)
}

fn test_redemption_encoder_rejects_mixed_fields_and_invalid_capabilities() {
	value := redemption_fixture().redemption or { panic('missing ticket') }
	assert bad_request(Request{id: 1, operation: .redeem_interaction})
	assert bad_request(Request{id: 0, operation: .redeem_interaction, redemption: value})
	assert bad_request(Request{id: 1, operation: .redeem_interaction, account_type: 'com.google', redemption: value})
	assert bad_request(Request{id: 1, operation: .redeem_interaction, auth_token_type: '', redemption: value})
	assert bad_request(Request{id: 1, operation: .redeem_interaction, features: ['x'], redemption: value})
	assert bad_request(Request{id: 1, operation: .redeem_interaction, options: [Option{'x', Scalar{}}], redemption: value})
	assert bad_request(Request{id: 1, operation: .get_accounts, redemption: value})
	assert bad_request(Request{id: 1, operation: .add_account, account_type: 'com.google', redemption: value})
	for length in [0, 31, 33] {
		assert bad_request(Request{id: 1, operation: .redeem_interaction, redemption: Redemption{request: 1, capability: []u8{len: length, init: 1}}})
	}
	assert bad_request(Request{id: 1, operation: .redeem_interaction, redemption: Redemption{request: 0, capability: value.capability}})
	assert bad_request(Request{id: 1, operation: .redeem_interaction, redemption: Redemption{request: 1, capability: []u8{len: 32}}})
}

fn test_redemption_socket_requires_write_half_close_and_rejects_second_frame() {
	frame := encode_request(redemption_fixture())!
	defer { unsafe { frame.free() } }
	decoded := wire_request(frame, true, time.second)!
	assert decoded == redemption_fixture()
	dispose_request(decoded)
	wire_request(frame, false, 20 * time.millisecond) or {
		assert err.msg().contains('EOF') || err.msg().contains('deadline')
		mut duplicate := frame.clone()
		defer { unsafe { duplicate.free() } }
		duplicate << frame
		wire_request(duplicate, true, time.second) or {
			assert err.msg().contains('trailing')
			return
		}
		assert false, 'accepted a second request frame'
		return
	}
	assert false, 'accepted a request without write-half close'
}
