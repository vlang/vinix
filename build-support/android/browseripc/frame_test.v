// SPDX-License-Identifier: GPL-2.0-or-later
module browseripc

import encoding.binary

fn packet(op Op, request u64, view u64, generation u64, navigation u64, payload []u8) Header {
	return Header{
		op:           op
		request:      request
		view:         view
		generation:   generation
		navigation:   navigation
		payload_size: u32(payload.len)
	}
}

fn test_header_limits_round_trip_and_cookie_replies() {
	h := packet(.navigate, 0x102030405060708, 17, 2, 4, 'https://example.test/'.bytes())
	mut wire := encode_header(h, .client_to_engine) or { panic(err) }
	assert wire.len == 48
	assert (decode_header(wire, .client_to_engine) or { panic(err) }) == h
	wire[44] = 1
	if _ := decode_header(wire, .client_to_engine) {
		assert false
	}
	wire[44] = 0
	binary.little_endian_put_u32(mut wire[40..44], u32(max_payload + 1))
	if _ := decode_header(wire, .client_to_engine) {
		assert false
	}
	for op in [Op.ack, .failure, .cookie_result] {
		payload := if op == .failure { 'engine unavailable'.bytes() } else { []u8{} }
		reply := packet(op, 1, 0, 0, 0, payload)
		bytes := encode_header(reply, .engine_to_client) or { panic(err) }
		assert (decode_header(bytes, .engine_to_client) or { panic(err) }) == reply
		validate_payload(reply, payload) or { panic(err) }
		if _ := encode_header(packet(op, 1, 0, 2, 0, payload), .engine_to_client) {
			assert false
		}
	}
}

fn test_policy_requires_correlated_decision_and_boolean() {
	mut payload := []u8{len: 8}
	binary.little_endian_put_u64(mut payload, 23)
	payload << 'https://example.test/callback'.bytes()
	validate_payload(packet(.policy_request, 1, 1, 1, 1, payload), payload) or { panic(err) }
	mut reply := []u8{len: 9}
	binary.little_endian_put_u64(mut reply[..8], 23)
	reply[8] = 1
	validate_payload(packet(.policy_reply, 2, 1, 1, 1, reply), reply) or { panic(err) }
	reply[8] = 2
	if _ := validate_payload(packet(.policy_reply, 2, 1, 1, 1, reply), reply) {
		assert false
	}
	reply[8] = 0
	reply[0] = 0
	if _ := validate_payload(packet(.policy_reply, 2, 1, 1, 1, reply), reply) {
		assert false
	}
}

fn test_malformed_utf8_and_pixel_stride_are_rejected() {
	for bytes in [[u8(0xc0), 0x80], [u8(`a`), 0]] {
		if _ := validate_payload(packet(.navigate, 1, 1, 1, 1, bytes), bytes) {
			assert false
		}
	}
	mut pixels := []u8{len: 20}
	binary.little_endian_put_u32(mut pixels[..4], 1)
	binary.little_endian_put_u32(mut pixels[4..8], 1)
	binary.little_endian_put_u32(mut pixels[8..12], 4)
	binary.little_endian_put_u32(mut pixels[12..16], 1)
	validate_payload(packet(.pixels, 0, 1, 1, 1, pixels), pixels) or { panic(err) }
	pixels[8] = 8
	if _ := validate_payload(packet(.pixels, 0, 1, 1, 1, pixels), pixels) {
		assert false
	}
}
