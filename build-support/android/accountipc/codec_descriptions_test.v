// SPDX-License-Identifier: GPL-2.0-or-later
module accountipc

import nativeaccountauth

fn descriptions_decode(wire []u8, service bool) !Event {
	if wire.len < header_size { return error('short test frame') }
	return decode_event(decode_header(wire[..header_size])!, wire[header_size..], service)
}

fn descriptions_wire_rejected(wire []u8, service bool) bool {
	value := descriptions_decode(wire, service) or { return true }
	dispose_event(value)
	return false
}

fn descriptions_event_rejected(value Event, service bool) bool {
	wire := encode_event(value, service) or { return true }
	unsafe { wire.free() }
	return false
}

fn descriptions_entry() nativeaccountauth.AuthenticatorDescription {
	return nativeaccountauth.AuthenticatorDescription{
		account_type:           'com.google'
		package_name:           'com.google.android.gms'
		label_id:               0x7f010203
		icon_id:                0x80010203
		small_icon_id:          0xffffffff
		account_preferences_id: 0x01020304
		custom_tokens:          true
	}
}

fn descriptions_raw_entry(account_type []u8, package []u8, flag u8) []u8 {
	mut body := []u8{}
	uint_bytes(mut body, u64(account_type.len), 4)
	body << account_type
	uint_bytes(mut body, u64(package.len), 4)
	body << package
	for _ in 0 .. 16 { body << u8(0) }
	body << flag
	return body
}

fn descriptions_raw_frame(count u16, entries []u8) []u8 {
	mut body := []u8{}
	defer { unsafe { body.free() } }
	uint_bytes(mut body, count, 2)
	body << entries
	return frame(.authenticators, 73, body) or { panic(err) }
}

fn test_authenticator_snapshot_preserves_resources_and_owns_decoded_identity() {
	value := descriptions_entry()
	values := [value]
	defer { unsafe { values.free() } }
	mut wire := encode_event(Event{ kind: .authenticators, id: 73, authenticators: values }, false)!
	defer { unsafe { wire.free() } }
	assert wire[..8] == [u8(`V`), `X`, `A`, `R`, 0, 1, 0, 9]
	decoded := descriptions_decode(wire, false)!
	defer { dispose_event(decoded) }
	assert terminal(decoded.kind)
	assert decoded.kind == .authenticators && decoded.id == 73
	assert decoded.authenticators == values
	assert decoded.capability.len == 0 && decoded.accounts.len == 0 && decoded.options.len == 0
	// The decoder must retain independent strings after the receive buffer dies.
	for index in header_size .. wire.len { wire[index] = 0 }
	assert decoded.authenticators[0] == value
	assert decoded.authenticators[0].account_type.str != value.account_type.str
	assert decoded.authenticators[0].package_name.str != value.package_name.str
}

fn test_authenticator_decoder_rejects_each_truncated_field_and_trailing_data() {
	values := [descriptions_entry()]
	defer { unsafe { values.free() } }
	wire := encode_event(Event{ kind: .authenticators, id: 73, authenticators: values }, false)!
	defer { unsafe { wire.free() } }
	for length in 0 .. wire.len {
		assert descriptions_wire_rejected(wire[..length], false)
		if length >= header_size {
			// Exercise reader cleanup at each interior boundary, not just the
			// initial header/body size comparison.
			mut shorter := wire[..length].clone()
			body_length := u32(length - header_size)
			for index in 0 .. 4 { shorter[16 + index] = u8(body_length >> (24 - index * 8)) }
			assert descriptions_wire_rejected(shorter, false)
			unsafe { shorter.free() }
		}
	}
	mut trailing := wire.clone()
	defer { unsafe { trailing.free() } }
	trailing << u8(0)
	assert descriptions_wire_rejected(trailing, false)
	trailing[19]++
	assert descriptions_wire_rejected(trailing, false)
}

fn test_authenticator_metadata_is_broker_only_and_cannot_mix_event_shapes() {
	values := [descriptions_entry()]
	capability := []u8{len: 32, init: 7}
	defer {
		unsafe {
			values.free()
			capability.free()
		}
	}
	event := Event{ kind: .authenticators, id: 73, authenticators: values }
	assert descriptions_event_rejected(Event{ ...event, capability: capability }, true)
	assert descriptions_event_rejected(Event{ ...event, capability: capability }, false)
	assert descriptions_event_rejected(Event{
		...event
		accounts: [Account{'alice@example.test', 'com.google'}]
	}, false)
	assert descriptions_event_rejected(Event{
		...event
		options: [nativeaccountauth.Option{'key', nativeaccountauth.Scalar{}}]
	}, false)
	for kind in [Kind.result, .failure, .accounts, .continued, .cancel] {
		assert descriptions_event_rejected(Event{ ...event, kind: kind }, false)
	}
	wire := encode_event(event, false)!
	defer { unsafe { wire.free() } }
	assert descriptions_wire_rejected(wire, true)
	// Even a correctly sized service capability cannot make kind 9 service-owned.
	mut body := capability.clone()
	defer { unsafe { body.free() } }
	body << wire[header_size..]
	forged := frame(.authenticators, 73, body)!
	defer { unsafe { forged.free() } }
	assert descriptions_wire_rejected(forged, true)
}

fn test_authenticator_metadata_rejects_duplicate_type_invalid_text_count_and_boolean() {
	entry := descriptions_raw_entry('com.google'.bytes(), 'com.google.android.gms'.bytes(), 0)
	defer { unsafe { entry.free() } }
	mut duplicated := entry.clone()
	defer { unsafe { duplicated.free() } }
	duplicated << entry
	duplicate_wire := descriptions_raw_frame(2, duplicated)
	count_wire := descriptions_raw_frame(17, []u8{})
	defer {
		unsafe {
			duplicate_wire.free()
			count_wire.free()
		}
	}
	assert descriptions_wire_rejected(duplicate_wire, false)
	assert descriptions_wire_rejected(count_wire, false)
	for invalid_type in [[]u8{}, [u8(0)], [u8(0xff)], []u8{len: 256, init: `x`}] {
		bad_entry := descriptions_raw_entry(invalid_type, 'pkg'.bytes(), 0)
		bad_wire := descriptions_raw_frame(1, bad_entry)
		assert descriptions_wire_rejected(bad_wire, false)
		unsafe {
			bad_entry.free()
			bad_wire.free()
		}
	}
	for invalid_package in [[]u8{}, [u8(0)], [u8(0xc0), 0x80], []u8{len: 256, init: `x`}] {
		bad_entry := descriptions_raw_entry('type'.bytes(), invalid_package, 0)
		bad_wire := descriptions_raw_frame(1, bad_entry)
		assert descriptions_wire_rejected(bad_wire, false)
		unsafe {
			bad_entry.free()
			bad_wire.free()
		}
	}
	bad_boolean := descriptions_raw_entry('type'.bytes(), 'pkg'.bytes(), 2)
	bad_boolean_wire := descriptions_raw_frame(1, bad_boolean)
	defer {
		unsafe {
			bad_boolean.free()
			bad_boolean_wire.free()
		}
	}
	assert descriptions_wire_rejected(bad_boolean_wire, false)
	values := [descriptions_entry(), descriptions_entry()]
	defer { unsafe { values.free() } }
	assert descriptions_event_rejected(Event{ kind: .authenticators, id: 73, authenticators: values }, false)
	too_many := []nativeaccountauth.AuthenticatorDescription{len: 17, init: descriptions_entry()}
	defer { unsafe { too_many.free() } }
	assert descriptions_event_rejected(Event{ kind: .authenticators, id: 73, authenticators: too_many }, false)
	for flag in [u8(0), 1] {
		valid_entry := descriptions_raw_entry('type'.bytes(), 'pkg'.bytes(), flag)
		valid_wire := descriptions_raw_frame(1, valid_entry)
		decoded := descriptions_decode(valid_wire, false)!
		assert decoded.authenticators[0].custom_tokens == (flag == 1)
		dispose_event(decoded)
		unsafe {
			valid_entry.free()
			valid_wire.free()
		}
	}
}

fn test_authenticator_query_is_not_a_service_dispatch_command() {
	capability := []u8{len: 32, init: 7}
	defer { unsafe { capability.free() } }
	command := Command{
		session:    73
		capability: capability
		caller:     nativeaccountauth.Caller{'com.google.android.apps.maps', 10001, 10001, 1234, 'a'.repeat(64), 'b'.repeat(64)}
		request:    nativeaccountauth.Request{ id: 87, operation: .get_authenticator_types }
	}
	if wire := encode_command(command) {
		unsafe { wire.free() }
		assert false, 'broker metadata query was forwarded to a service'
	}
	// Replace a valid dispatch's nested getAccounts request with the valid
	// header-only metadata query. The outer envelope remains well formed.
	wire := encode_command(Command{
		...command
		request: nativeaccountauth.Request{ id: 87, operation: .get_accounts }
	})!
	defer { unsafe { wire.free() } }
	mut forged := wire[..wire.len - 4].clone()
	defer { unsafe { forged.free() } }
	request_start := forged.len - nativeaccountauth.request_header_size
	forged[request_start + 7] = 6
	for index in 16 .. 20 { forged[request_start + index] = 0 }
	length := u32(forged.len - header_size)
	for index in 0 .. 4 { forged[16 + index] = u8(length >> (24 - index * 8)) }
	if decoded := decode_command(decode_header(forged[..header_size])!, forged[header_size..]) {
		dispose_command(decoded)
		assert false, 'service accepted a broker-only metadata query'
	}
}

fn test_authenticator_snapshot_accepts_empty_and_maximum_distinct_descriptions() {
	empty := encode_event(Event{ kind: .authenticators, id: 73 }, false)!
	defer { unsafe { empty.free() } }
	empty_event := descriptions_decode(empty, false)!
	defer { dispose_event(empty_event) }
	assert empty_event.authenticators.len == 0 && terminal(empty_event.kind)
	mut values := []nativeaccountauth.AuthenticatorDescription{}
	defer { nativeaccountauth.dispose_authenticator_descriptions(values) }
	for index in 0 .. 16 {
		values << nativeaccountauth.AuthenticatorDescription{
			account_type: if index == 0 { 'x'.repeat(255) } else { 'org.example.type${index}' }
			package_name: 'p'.repeat(255)
		}
	}
	wire := encode_event(Event{ kind: .authenticators, id: 73, authenticators: values }, false)!
	defer { unsafe { wire.free() } }
	decoded := descriptions_decode(wire, false)!
	defer { dispose_event(decoded) }
	assert decoded.authenticators == values
	assert decoded.authenticators.len == 16
	assert decoded.authenticators[0].label_id == 0
	assert !decoded.authenticators[0].custom_tokens
}
