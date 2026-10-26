// SPDX-License-Identifier: GPL-2.0-or-later
module accountipc

import nativeaccountauth

fn decode_frame(bytes []u8, service bool) !Event {
	return decode_event(decode_header(bytes[..header_size])!, bytes[header_size..], service)
}

fn test_scalar_event_roundtrip_and_strict_bounds() {
	event := Event{
		kind:       .result
		id:         71
		capability: []u8{len: 32, init: 9}
		options:    [
			nativeaccountauth.Option{'null', nativeaccountauth.Scalar{}},
			nativeaccountauth.Option{'text', nativeaccountauth.Scalar{ kind: .text, text: 'é🙂' }},
			nativeaccountauth.Option{'bool', nativeaccountauth.Scalar{ kind: .boolean, boolean: true }},
			nativeaccountauth.Option{'i32', nativeaccountauth.Scalar{ kind: .int32, number: -2147483648 }},
			nativeaccountauth.Option{'i64', nativeaccountauth.Scalar{ kind: .int64, number: -9223372036854775807 }},
		]
	}
	frame := encode_event(event, true) or { panic(err) }
	defer { unsafe { frame.free() } }
	decoded := decode_frame(frame, true) or { panic(err) }
	defer { dispose_event(decoded) }
	assert decoded.id == event.id
	assert decoded.options == event.options
	assert decoded.capability == event.capability
	for length in 0 .. frame.len {
		if length < header_size {
			if _ := decode_header(frame[..length]) {
				assert false, 'short header accepted'
			}
		} else {
			if _ := decode_frame(frame[..length], true) {
				assert false, 'short body accepted'
			}
		}
	}
	mut invalid := frame.clone()
	defer { unsafe { invalid.free() } }
	invalid << u8(0)
	if _ := decode_frame(invalid, true) {
		assert false, 'trailing body accepted'
	}
	if _ := encode_event(Event{
		kind:    .result
		id:      1
		options: [
			nativeaccountauth.Option{'x', nativeaccountauth.Scalar{}},
			nativeaccountauth.Option{'x', nativeaccountauth.Scalar{}},
		]
	}, false) {
		assert false, 'duplicate option accepted'
	}
	if _ := encode_event(Event{
		kind:    .result
		id:      1
		options: [
			nativeaccountauth.Option{'x', nativeaccountauth.Scalar{ kind: .int32, number: 2147483648 }},
		]
	}, false) {
		assert false, 'int32 overflow accepted'
	}
}

fn test_interaction_has_separate_public_and_service_descriptors() {
	local := []u8{len: 32, init: 4}
	ticket := []u8{len: 32, init: 5}
	capability := []u8{len: 32, init: 6}
	defer { unsafe {
		local.free()
		ticket.free()
		capability.free()
	}
	 }
	descriptor := Interaction{local, 'com.google.android.gms', 'com.google.android.gms.auth.uiflows.addaccount.AccountIntroActivity'}
	service := encode_event(Event{
		kind:        .interaction
		id:          19
		capability:  capability
		interaction: descriptor
	}, true) or { panic(err) }
	public := encode_event(Event{
		kind:        .interaction
		id:          71
		interaction: Interaction{ handle: ticket }
	}, false) or { panic(err) }
	defer { unsafe {
		service.free()
		public.free()
	}
	 }
	decoded := decode_frame(service, true) or { panic(err) }
	defer { dispose_event(decoded) }
	assert decoded.interaction == descriptor
	assert public.len == header_size + 32
	client := decode_frame(public, false) or { panic(err) }
	defer { dispose_event(client) }
	assert client.capability.len == 0
	assert client.interaction.handle == ticket
	assert client.interaction.target_package == ''
	assert client.interaction.target_class == ''
	if _ := decode_frame(service, false) {
		assert false, 'service descriptor accepted by public decoder'
	}
	if _ := decode_frame(public, true) {
		assert false, 'public ticket accepted by service decoder'
	}
	if _ := encode_event(Event{ kind: .interaction, id: 71, interaction: descriptor }, false) {
		assert false, 'public event exposed service target'
	}
	if _ := encode_event(Event{
		kind:        .interaction
		id:          71
		interaction: Interaction{ handle: []u8{len: 32} }
	}, false) {
		assert false, 'zero ticket accepted'
	}
	if _ := encode_event(Event{ kind: .continued, id: 71, interaction: descriptor }, false) {
		assert false, 'descriptor accepted on unrelated event'
	}
}

fn test_launch_command_is_distinct_and_rejects_partial_or_trailing_fields() {
	value := Launch{23, []u8{len: 32, init: 1}, Interaction{[]u8{len: 32, init: 2}, 'com.google.android.gms', 'com.google.android.gms.auth.uiflows.addaccount.AccountIntroActivity'}}
	defer { dispose_launch(value) }
	bytes := encode_launch(value) or { panic(err) }
	defer { unsafe { bytes.free() } }
	header := decode_header(bytes[..header_size]) or { panic(err) }
	assert header.kind == .launch
	decoded := decode_launch(header, bytes[header_size..]) or { panic(err) }
	defer { dispose_launch(decoded) }
	assert decoded == value
	if _ := decode_frame(bytes, true) {
		assert false, 'launch accepted as service callback'
	}
	for length in header_size .. bytes.len {
		if _ := decode_launch(Header{.launch, 23, length - header_size}, bytes[header_size..length]) {
			assert false, 'truncated launch accepted'
		}
	}
	mut body := bytes[header_size..].clone()
	defer { unsafe { body.free() } }
	body << u8(0)
	if _ := decode_launch(Header{.launch, 23, body.len}, body) {
		assert false, 'trailing launch accepted'
	}
	if _ := decode_launch(Header{.launch, 0, body.len}, body) {
		assert false, 'zero session accepted'
	}
}

fn test_command_retains_trusted_identity_and_owned_request() {
	caller := nativeaccountauth.Caller{'org.vinix.app', 10001, 10002, 1234, 'a'.repeat(64), 'b'.repeat(64)}
	request := nativeaccountauth.Request{
		id:           99
		operation:    .add_account
		account_type: 'com.google'
		options:      [nativeaccountauth.Option{'allow', nativeaccountauth.Scalar{ kind: .boolean, boolean: true }}]
	}
	value := Command{1, []u8{len: 32, init: 7}, caller, request}
	bytes := encode_command(value) or { panic(err) }
	defer { unsafe {
		bytes.free()
		value.capability.free()
	}
	 }
	decoded := decode_command(decode_header(bytes[..header_size]) or { panic(err) },
		bytes[header_size..]) or { panic(err) }
	defer { dispose_command(decoded) }
	assert decoded.caller == caller
	assert decoded.request == request
	assert decoded.session == 1
	if _ := encode_command(Command{ ...value, caller: nativeaccountauth.Caller{ ...caller, uid: 0 } }) {
		assert false, 'root-forwarded app identity accepted root UID'
	}
}
