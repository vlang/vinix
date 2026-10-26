// SPDX-License-Identifier: GPL-2.0-or-later
module browseripc

fn test_cookie_flush_and_clear_session_identity_payload_and_exact_completion() {
	for op in [Op.cookie_flush, .cookie_clear] {
		payload := if op == .cookie_clear { [u8(1)] } else { []u8{} }
		h := Header{ op: op, request: 1, payload_size: u32(payload.len) }
		assert decode_header(encode_header(h, .client_to_engine)!, .client_to_engine)! == h
		mut state := State{}
		state.submit(h, payload)!
		reply := Header{
			op:           if op == .cookie_clear { Op.cookie_cleared } else { Op.ack }
			request:      1
			payload_size: if op == .cookie_clear { u32(1) } else { u32(0) }
		}
		assert state.receive(reply, payload)!
		mut replay := false
		state.receive(reply, payload) or { replay = true }
		assert replay
	}
	for value in [u8(0), 1] {
		validate_payload(Header{ op: .cookie_clear, request: 1, payload_size: 1 }, [value])!
	}
	for bytes in [[]u8{}, [u8(2)], [u8(0), 1]] {
		mut rejected := false
		validate_payload(Header{ op: .cookie_clear, request: 1, payload_size: u32(bytes.len) }, bytes) or { rejected = true }
		assert rejected
	}
	mut state := State{}
	state.submit(Header{ op: .cookie_clear, request: 1, payload_size: 1 }, [u8(0)])!
	mut wrong := false
	state.receive(Header{ op: .ack, request: 1 }, []u8{}) or { wrong = true }
	assert wrong
	mut bad_identity := false
	encode_header(Header{ op: .cookie_flush, request: 1, view: 1, generation: 1 }, .client_to_engine) or { bad_identity = true }
	assert bad_identity
}
