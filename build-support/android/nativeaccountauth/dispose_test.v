// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

fn test_decoded_feature_ownership_releases_each_string_once_on_success_and_failure() {
	request := Request{
		id: 31
		operation: .add_account
		account_type: 'org.vinix.fixture'
		auth_token_type: 'fixture-token'
		features: ['first', 'Zoë 🌍', 'third']
	}
	mut wire := encode_request(request)!
	defer { unsafe { wire.free() } }
	for _ in 0 .. 4 {
		decoded := decode_request_bytes(wire)!
		assert decoded == request
		dispose_request(decoded)
	}
	// The final byte is the option count. Reject it only after allocating
	// every feature, exercising the decoder's partial-result cleanup too.
	wire[wire.len - 1] = 33
	for _ in 0 .. 4 {
		mut rejected := false
		decode_request_bytes(wire) or {
			assert err.msg().contains('too many account options')
			rejected = true
		}
		assert rejected
	}
}
