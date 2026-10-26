// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

fn token_bad_frame(frame []u8) bool {
	request := decode_request_bytes(frame) or { return true }
	dispose_request(request)
	return false
}

fn token_bad_request(request Request) bool {
	wire := encode_request(request) or { return true }
	unsafe { wire.free() }
	return false
}

fn token_fixture() Request {
	return Request{id: 71, operation: .get_auth_token, account_name: 'Zoë 🌍@example.test',
		account_type: 'com.google', auth_token_type: 'oauth2:https://www.googleapis.com/auth/webhistory',
		options: [Option{'scope', Scalar{kind: .text, text: 'bounded'}}]}
}

fn test_token_request_roundtrip_exact_identity_and_rejects_all_truncations() {
	request := token_fixture()
	wire := encode_request(request)!
	defer { unsafe { wire.free() } }
	assert wire[..8] == [u8(`V`), `X`, `A`, `1`, 0, 1, 0, 4]
	decoded := decode_request_bytes(wire)!
	defer { dispose_request(decoded) }
	assert decoded == request
	for length in 0 .. wire.len { assert token_bad_frame(wire[..length]) }
	mut trailing := wire.clone(); trailing << u8(0)
	defer { unsafe { trailing.free() } }
	assert token_bad_frame(trailing)
}

fn test_token_request_rejects_missing_identity_features_and_claimed_caller() {
	valid := token_fixture()
	assert token_bad_request(Request{...valid, account_name: none})
	assert token_bad_request(Request{...valid, account_name: ''})
	assert token_bad_request(Request{...valid, account_name: 'x'.repeat(1025)})
	assert token_bad_request(Request{...valid, account_type: none})
	assert token_bad_request(Request{...valid, account_type: ''})
	assert token_bad_request(Request{...valid, account_type: 'x'.repeat(256)})
	assert token_bad_request(Request{...valid, auth_token_type: none})
	assert token_bad_request(Request{...valid, auth_token_type: ''})
	assert token_bad_request(Request{...valid, features: ['unexpected']})
	for key in ['callerUid', 'callerPid', 'androidPackageName', 'accountAuthenticatorResponse'] {
		assert token_bad_request(Request{...valid, options: [Option{key, Scalar{kind: .int32, number: 0}}]})
	}
	assert token_bad_request(Request{id: 1, operation: .get_accounts, account_name: 'unexpected'})
	assert token_bad_request(Request{id: 1, operation: .add_account, account_type: 'com.google', account_name: 'unexpected'})
}
