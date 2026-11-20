// SPDX-License-Identifier: GPL-2.0-or-later
module browseripc

import encoding.binary

fn js_packet(op Op, request u64, view u64, generation u64, navigation u64, payload []u8) Header {
	return Header{
		op:           op
		request:      request
		view:         view
		generation:   generation
		navigation:   navigation
		payload_size: u32(payload.len)
	}
}

fn call_payload(id u64, body string) []u8 {
	mut bytes := []u8{len: 8}
	binary.little_endian_put_u64(mut bytes, id)
	bytes << body.bytes()
	return bytes
}

fn reply_payload(id u64, status u8, body string) []u8 {
	mut bytes := call_payload(id, '')
	bytes << status
	bytes << body.bytes()
	return bytes
}

fn rejected_payload(h Header, payload []u8) bool {
	validate_payload(h, payload) or { return true }
	return false
}

fn test_interface_list_parses_and_rejects_bad_identifiers() {
	list := parse_js_interfaces('mm getAndroidId addAccount\n\$x y_1'.bytes()) or { panic(err) }
	assert list.len == 2
	assert list[0].name == 'mm' && list[0].methods == ['getAndroidId', 'addAccount']
	assert list[1].name == r'$x' && list[1].methods == ['y_1']
	assert (parse_js_interfaces([]u8{}) or { panic(err) }).len == 0
	for bad in ['mm', 'mm  get', '1mm get', 'mm get-x', 'mm get\nmm put', 'mm get\n', 'mm get\x00'] {
		if _ := parse_js_interfaces(bad.bytes()) {
			assert false, bad
		}
	}
	mut many := []string{}
	for i in 0 .. max_js_interfaces + 1 {
		many << 'i${i} m'
	}
	if _ := parse_js_interfaces(many.join('\n').bytes()) {
		assert false
	}
}

fn test_call_and_tagged_values() {
	call := parse_js_call(call_payload(7, 'mm\nsetAccountIdentifier\n6:sabcde1:z2:b1')) or { panic(err) }
	assert call.id == 7 && call.iface == 'mm' && call.method == 'setAccountIdentifier'
	assert call.arguments == '6:sabcde1:z2:b1'
	parse_js_call(call_payload(8, 'mm\ngetAndroidId\n')) or { panic(err) }
	// Lengths are UTF-16 units: one astral character counts twice.
	tagged_list('3:séx3:s\U0001F600', 2) or { panic(err) }
	for bad in ['mm\ngetAndroidId', 'mm\n\nx', 'mm\nget\n0:s', 'mm\nget\n4:sab', 'mm\nget\n2:qa',
		'mm\nget\n2:s', 'mm\nget\nx:sa'] {
		if _ := parse_js_call(call_payload(9, bad)) {
			assert false, bad
		}
	}
	if _ := parse_js_call(call_payload(0, 'mm\nget\n')) {
		assert false
	}
	if _ := tagged_list('1:z1:z', 1) {
		assert false
	}
}

fn test_bridge_frames_need_identity_and_valid_payloads() {
	interfaces := 'mm getAndroidId'.bytes()
	h := js_packet(.js_interfaces, 3, 1, 1, 0, interfaces)
	encode_header(h, .client_to_engine) or { panic(err) }
	validate_payload(h, interfaces) or { panic(err) }
	if _ := encode_header(js_packet(.js_interfaces, 3, 1, 1, 0, interfaces), .engine_to_client) {
		assert false
	}
	call := call_payload(5, 'mm\ngetAndroidId\n')
	encode_header(js_packet(.js_call, 5, 1, 1, 2, call), .engine_to_client) or { panic(err) }
	// A call belongs to the current page: request and navigation are required.
	for bad in [js_packet(.js_call, 0, 1, 1, 2, call), js_packet(.js_call, 5, 1, 1, 0, call)] {
		if _ := encode_header(bad, .engine_to_client) {
			assert false
		}
	}
	value := reply_payload(5, 0, '17:s0123456789abcdef')
	encode_header(js_packet(.js_reply, 9, 1, 1, 2, value), .client_to_engine) or { panic(err) }
	validate_payload(js_packet(.js_reply, 9, 1, 1, 2, value), value) or { panic(err) }
	thrown := reply_payload(5, 1, '')
	validate_payload(js_packet(.js_reply, 9, 1, 1, 2, thrown), thrown) or { panic(err) }
	for bad in [reply_payload(5, 2, '1:u'), reply_payload(0, 0, '1:u'), reply_payload(5, 0, ''),
		reply_payload(5, 0, '1:u1:u'), reply_payload(5, 0, '2:q1')] {
		assert rejected_payload(js_packet(.js_reply, 9, 1, 1, 2, bad), bad)
	}
	if _ := encode_header(js_packet(.js_reply, 9, 1, 1, 0, value), .client_to_engine) {
		assert false
	}
}

fn test_state_accepts_calls_only_for_the_current_navigation() {
	mut s := State{}
	size := [u8(8), 0, 0, 0, 8, 0, 0, 0]
	s.submit(js_packet(.create, 1, 1, 1, 0, size), size) or { panic(err) }
	s.submit(js_packet(.js_interfaces, 2, 1, 1, 0, 'mm get'.bytes()), 'mm get'.bytes()) or { panic(err) }
	s.submit(js_packet(.navigate, 3, 1, 1, 1, 'https://a.test/'.bytes()), 'https://a.test/'.bytes()) or { panic(err) }
	call := call_payload(4, 'mm\nget\n')
	assert s.receive(js_packet(.js_call, 4, 1, 1, 1, call), call) or { panic(err) }
	s.submit(js_packet(.navigate, 5, 1, 1, 2, 'https://b.test/'.bytes()), 'https://b.test/'.bytes()) or { panic(err) }
	assert !(s.receive(js_packet(.js_call, 6, 1, 1, 1, call), call) or { panic(err) })
	reply := reply_payload(4, 0, '1:u')
	s.submit(js_packet(.js_reply, 7, 1, 1, 2, reply), reply) or { panic(err) }
	if _ := s.submit(js_packet(.js_reply, 8, 1, 1, 1, reply), reply) {
		assert false
	}
}
