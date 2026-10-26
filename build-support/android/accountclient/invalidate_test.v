// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import nativeaccountauth

fn test_invalidation_builder_owns_copies_and_existing_builder_remains_narrow() {
	assert abi_invalidate_request(0, c'com.google', c'fixture') == unsafe { nil }
	assert abi_invalidate_request(1, unsafe { nil }, c'fixture') == unsafe { nil }
	assert abi_invalidate_request(1, c'com.google', unsafe { nil }) == unsafe { nil }
	mut kind := 'com.google'.clone()
	mut token := 'stored-fixture'.clone()
	builder := abi_invalidate_request(93, kind.str, token.str)
	assert builder != unsafe { nil }
	defer { abi_request_free(builder) }
	unsafe { kind.str[0] = `x`; token.str[0] = `x` }
	value := unsafe { &RequestBuilder(builder) }
	assert value.op == .invalidate_auth_token && value.account_type == ?string('com.google')
	assert value.token_value == ?string('stored-fixture')
	assert value.account_name == none && value.auth_token_type == none
	assert abi_request(1, 5, c'com.google', c'fixture') == unsafe { nil }
	// Builder extensions cannot smuggle an option into the narrow op5 wire.
	assert abi_option(builder, c'unexpected', 1, c'fixture', 0) == 0
	mut rejected := false
	nativeaccountauth.encode_request(nativeaccountauth.Request{
		id: value.id, operation: value.op, account_type: value.account_type,
		token_value: value.token_value, options: value.options}) or { rejected = true }
	assert rejected
	unsafe { kind.free(); token.free() }
}
