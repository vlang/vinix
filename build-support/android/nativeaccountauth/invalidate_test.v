// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

fn invalidation_bad(request Request) bool {
	wire := encode_request(request) or { return true }
	unsafe { wire.free() }
	return false
}

fn test_invalidation_wire_preserves_exact_value_and_rejects_every_truncation() {
	for token in ['', 'stored-fixture-🌍', 'x'.repeat(4096)] {
		request := Request{id: 72, operation: .invalidate_auth_token,
			account_type: 'com.google', token_value: token}
		wire := encode_request(request)!
		assert wire[..8] == [u8(`V`), `X`, `A`, `1`, 0, 1, 0, 5]
		decoded := decode_request_bytes(wire)!
		assert decoded == request
		dispose_request(decoded)
		for length in 0 .. wire.len {
			mut rejected := false
			decode_request_bytes(wire[..length]) or { rejected = true }
			assert rejected
		}
		mut trailing := wire.clone()
		trailing << u8(0)
		mut rejected := false
		decode_request_bytes(trailing) or { rejected = true }
		assert rejected
		unsafe { wire.free(); trailing.free() }
	}
}

fn test_invalidation_requires_only_bounded_type_and_value_without_caller_claims() {
	valid := Request{id: 1, operation: .invalidate_auth_token,
		account_type: 'com.google', token_value: 'fixture'}
	assert invalidation_bad(Request{...valid, id: 0})
	assert invalidation_bad(Request{...valid, account_type: none})
	assert invalidation_bad(Request{...valid, account_type: ''})
	assert invalidation_bad(Request{...valid, account_type: 'x'.repeat(256)})
	assert invalidation_bad(Request{...valid, token_value: none})
	assert invalidation_bad(Request{...valid, token_value: 'x'.repeat(4097)})
	assert invalidation_bad(Request{...valid, token_value: 'x\x00y'})
	bad_utf8 := [u8(0xff)].bytestr()
	assert invalidation_bad(Request{...valid, token_value: bad_utf8})
	assert invalidation_bad(Request{...valid, account_name: 'unexpected'})
	assert invalidation_bad(Request{...valid, auth_token_type: 'unexpected'})
	assert invalidation_bad(Request{...valid, features: ['unexpected']})
	assert invalidation_bad(Request{...valid,
		options: [Option{'callerUid', Scalar{kind: .int32, number: 0}}]})
	for operation in [Operation.get_accounts, .add_account, .get_auth_token, .redeem_interaction] {
		assert invalidation_bad(Request{...valid, operation: operation})
	}
}
