// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

fn descriptions_request_rejected(request Request) bool {
	wire := encode_request(request) or { return true }
	unsafe { wire.free() }
	return false
}

fn descriptions_frame_rejected(wire []u8) bool {
	request := decode_request_bytes(wire) or { return true }
	dispose_request(request)
	return false
}

fn test_authenticator_query_has_only_a_header_and_roundtrips_its_full_id() {
	query := Request{ id: u64(0x1020304050607080), operation: .get_authenticator_types }
	wire := encode_request(query)!
	defer { unsafe { wire.free() } }
	assert wire == [u8(`V`), `X`, `A`, `1`, 0, 1, 0, 6, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70,
		0x80, 0, 0, 0, 0]
	decoded := decode_request_bytes(wire)!
	defer { dispose_request(decoded) }
	assert decoded == query
	for length in 0 .. wire.len {
		assert descriptions_frame_rejected(wire[..length])
	}
	mut trailing := wire.clone()
	defer { unsafe { trailing.free() } }
	trailing << u8(0)
	assert descriptions_frame_rejected(trailing)
	// Correcting the frame length must not make an unrelated body acceptable.
	trailing[19] = 1
	assert descriptions_frame_rejected(trailing)
}

fn test_authenticator_query_rejects_every_application_selected_field() {
	query := Request{ id: 1, operation: .get_authenticator_types }
	assert descriptions_request_rejected(Request{ ...query, id: 0 })
	assert descriptions_request_rejected(Request{ ...query, account_name: 'alice@example.test' })
	assert descriptions_request_rejected(Request{ ...query, account_type: 'com.google' })
	assert descriptions_request_rejected(Request{ ...query, account_type: '' })
	assert descriptions_request_rejected(Request{ ...query, auth_token_type: 'oauth2:scope' })
	assert descriptions_request_rejected(Request{ ...query, token_value: 'secret' })
	assert descriptions_request_rejected(Request{ ...query, features: ['feature'] })
	assert descriptions_request_rejected(Request{
		...query
		options: [Option{'packageName', Scalar{ kind: .text, text: 'com.google.android.gms' }}]
	})
	assert descriptions_request_rejected(Request{ ...query, redemption: Redemption{} })
	mut wire := encode_request(query)!
	defer { unsafe { wire.free() } }
	wire[7] = 7
	assert descriptions_frame_rejected(wire)
}
