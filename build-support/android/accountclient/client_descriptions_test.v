// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import accountipc
import nativeaccountauth

#include <sys/socket.h>

fn C.socketpair(i32, i32, i32, &i32) i32

// A verified connected stream isolates asynchronous reply validation.
// Separate admission tests cover kernel peer authentication.
fn descriptions_client_pair(op nativeaccountauth.Operation) (&Client, &accountipc.Stream) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return &Client{
		id:        87
		operation: op
		verified:  true
		stream:    accountipc.open_stream(int(fds[0])) or { panic(err) }
	}, accountipc.open_stream(int(fds[1])) or { panic(err) }
}

fn descriptions_send(mut peer accountipc.Stream, event accountipc.Event) {
	wire := accountipc.encode_event(event, false) or { panic(err) }
	defer { unsafe { wire.free() } }
	peer.enqueue(wire) or { panic(err) }
	peer.flush() or { panic(err) }
}

fn descriptions_client_entry() nativeaccountauth.AuthenticatorDescription {
	return nativeaccountauth.AuthenticatorDescription{
		account_type:           'com.google'
		package_name:           'com.google.android.gms'
		label_id:               0x7f010203
		icon_id:                0x80000001
		small_icon_id:          0xffffffff
		account_preferences_id: 0x01020304
		custom_tokens:          true
	}
}

fn test_authenticator_builder_is_header_only_and_legacy_abi_rejects_op6() {
	assert abi_authenticators_request(0) == unsafe { nil }
	assert abi_request(87, 6, unsafe { nil }, unsafe { nil }) == unsafe { nil }
	builder := abi_authenticators_request(87)
	assert builder != unsafe { nil }
	defer { abi_request_free(builder) }
	value := unsafe { &RequestBuilder(builder) }
	assert value.id == 87 && value.op == .get_authenticator_types
	assert value.account_name == none && value.account_type == none
	assert value.auth_token_type == none && value.token_value == none
	assert value.features.len == 0 && value.options.len == 0
	// Complete validation rejects generic builder mutators before connection.
	assert abi_option(builder, c'packageName', 1, c'com.google.android.gms', 0) == 0
	request := nativeaccountauth.Request{ id: value.id, operation: value.op, options: value.options }
	if wire := nativeaccountauth.encode_request(request) {
		unsafe { wire.free() }
		assert false, 'metadata builder options were accepted'
	}
}

fn test_authenticator_getters_borrow_terminal_decoded_event_until_close() {
	mut client, mut peer := descriptions_client_pair(.get_authenticator_types)
	defer {
		abi_close(client)
		peer.close()
		unsafe { free(peer) }
	}
	assert abi_authenticator_count(client) == 0
	assert abi_authenticator_count(unsafe { nil }) == 0
	assert abi_authenticator_type(unsafe { nil }, 0) == unsafe { nil }
	assert abi_authenticator_package(unsafe { nil }, 0) == unsafe { nil }
	assert abi_authenticator_resource(unsafe { nil }, 0, 0) == 0
	assert abi_authenticator_custom_tokens(unsafe { nil }, 0) == -1
	values := [descriptions_client_entry()]
	defer { unsafe { values.free() } }
	descriptions_send(mut peer, accountipc.Event{ kind: .authenticators, id: 87, authenticators: values })
	assert client.read(0)!
	assert client.terminal && client.closed
	assert client.current.kind == .authenticators && abi_authenticator_count(client) == 1
	assert unsafe { cstring_to_vstring(abi_authenticator_type(client, 0)) } == 'com.google'
	assert unsafe { cstring_to_vstring(abi_authenticator_package(client, 0)) } == 'com.google.android.gms'
	assert abi_authenticator_resource(client, 0, 0) == 0x7f010203
	assert abi_authenticator_resource(client, 0, 1) == 0x80000001
	assert abi_authenticator_resource(client, 0, 2) == 0xffffffff
	assert abi_authenticator_resource(client, 0, 3) == 0x01020304
	assert abi_authenticator_resource(client, 0, 4) == 0
	assert abi_authenticator_resource(client, 0, 0xffff) == 0
	assert abi_authenticator_custom_tokens(client, 0) == 1
	for index in [u32(1), 0xffffffff] {
		assert abi_authenticator_type(client, index) == unsafe { nil }
		assert abi_authenticator_package(client, index) == unsafe { nil }
		assert abi_authenticator_resource(client, index, 0) == 0
		assert abi_authenticator_custom_tokens(client, index) == -1
	}
	assert !client.read(0)!
	assert abi_authenticator_count(client) == 1
	client.close()
	assert abi_authenticator_count(client) == 0
	assert abi_authenticator_type(client, 0) == unsafe { nil }
	assert abi_authenticator_package(client, 0) == unsafe { nil }
	assert abi_authenticator_resource(client, 0, 0) == 0
	assert abi_authenticator_custom_tokens(client, 0) == -1
}

fn test_authenticator_snapshot_cannot_satisfy_other_account_operations() {
	values := [descriptions_client_entry()]
	defer { unsafe { values.free() } }
	for op in [nativeaccountauth.Operation.get_accounts, .add_account, .redeem_interaction,
		.get_auth_token, .invalidate_auth_token] {
		mut client, mut peer := descriptions_client_pair(op)
		descriptions_send(mut peer, accountipc.Event{ kind: .authenticators, id: 87, authenticators: values })
		mut rejected := false
		client.read(0) or { rejected = true }
		assert rejected && client.closed && !client.terminal
		assert abi_authenticator_count(client) == 0
		abi_close(client)
		peer.close()
		unsafe { free(peer) }
	}
}

fn test_authenticator_query_rejects_wrong_reply_shapes_and_request_id() {
	for kind in [accountipc.Kind.result, .accounts, .continued, .interaction, .cancel] {
		mut client, mut peer := descriptions_client_pair(.get_authenticator_types)
		mut event := accountipc.Event{ kind: kind, id: 87 }
		mut ticket := []u8{}
		if kind == .interaction {
			ticket = []u8{len: 32, init: 7}
			event = accountipc.Event{ ...event, interaction: accountipc.Interaction{ handle: ticket } }
		}
		descriptions_send(mut peer, event)
		mut rejected := false
		client.read(0) or { rejected = true }
		assert rejected && client.closed && abi_authenticator_count(client) == 0
		abi_close(client)
		peer.close()
		unsafe {
			free(peer)
			ticket.free()
		}
	}
	mut client, mut peer := descriptions_client_pair(.get_authenticator_types)
	defer {
		abi_close(client)
		peer.close()
		unsafe { free(peer) }
	}
	descriptions_send(mut peer, accountipc.Event{ kind: .authenticators, id: 88 })
	mut rejected := false
	client.read(0) or { rejected = true }
	assert rejected && client.closed && abi_authenticator_count(client) == 0
}

fn test_authenticator_query_accepts_structured_failure_without_metadata() {
	mut client, mut peer := descriptions_client_pair(.get_authenticator_types)
	defer {
		abi_close(client)
		peer.close()
		unsafe { free(peer) }
	}
	event := accountipc.failure(87, 1, 'Authenticator metadata unavailable')
	defer { unsafe { event.options.free() } }
	descriptions_send(mut peer, event)
	assert client.read(0)! && client.terminal && client.closed
	assert client.current.kind == .failure && abi_authenticator_count(client) == 0
	assert abi_authenticator_type(client, 0) == unsafe { nil }
}
