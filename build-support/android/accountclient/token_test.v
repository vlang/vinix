// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import accountipc
import nativeaccountauth
import os
import time

#include <sys/socket.h>
fn C.socketpair(i32, i32, i32, &i32) i32

fn token_pair() (&Authenticator, &accountipc.Stream) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return &Authenticator{stream: accountipc.open_stream(int(fds[0])) or { panic(err) }},
		accountipc.open_stream(int(fds[1])) or { panic(err) }
}

fn token_path() string {
	path := os.join_path(os.home_dir(), '.local', 'state', 'vinix', 'android',
		'account-token-bridge-${os.getpid()}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path, mode: 0o700) or { panic(err) }
	os.chmod(path, 0o700) or { panic(err) }
	return path
}

fn token_insert(store voidptr, name &char, visible bool) {
	builder := store_insertion(store, name, c'com.google', unsafe { nil })
	assert builder != unsafe { nil }
	defer { store_insertion_free(builder) }
	if visible { assert store_visibility(builder, c'com.google.android.apps.maps', 2) == 0 }
	assert store_commit(builder) == 1
}

fn token_dispatch(mut peer accountipc.Stream, id u64, pkg string, name string) {
	wire := accountipc.encode_command(accountipc.Command{
		session: id
		capability: []u8{len: 32, init: u8(id)}
		caller: nativeaccountauth.Caller{pkg, 10001, 10001, 4321, 'a'.repeat(64), 'b'.repeat(64)}
		request: nativeaccountauth.Request{id: id, operation: .get_auth_token, account_name: name,
			account_type: 'com.google', auth_token_type: 'oauth2:scope',
			options: [nativeaccountauth.Option{'claimedPackage', nativeaccountauth.Scalar{kind: .text, text: 'com.google.android.gms'}}]}
	}) or { panic(err) }
	defer { unsafe { wire.free() } }
	peer.enqueue(wire) or { panic(err) }; peer.flush() or { panic(err) }
}

fn test_token_authorization_requires_live_session_exact_account_and_actual_visibility() {
	mut owner, mut peer := token_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	path := token_path()
	defer { os.rmdir_all(path) or {} }
	store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert store != unsafe { nil }
	defer { assert store_close(store) == 0 }
	token_insert(store, c'hidden@example.test', false)
	token_insert(store, c'visible@example.test', true)
	mut id := u64(0)
	for index, item in [['com.google.android.apps.maps', 'visible@example.test'],
		['com.google.android.apps.maps', 'hidden@example.test'],
		['org.untrusted.app', 'visible@example.test'],
		['com.google.android.gms', 'hidden@example.test'],
		['com.google.android.apps.maps', 'missing@example.test']] {
		session := u64(index + 1)
		token_dispatch(mut peer, session, item[0], item[1])
		assert auth_read(owner, &id, 0) == 1 && id == session
		assert auth_operation(owner) == 4
		assert unsafe { cstring_to_vstring(auth_account_name(owner)) } == item[1]
		assert auth_count(owner) == 4
		assert unsafe { cstring_to_vstring(auth_key(owner, 1)) } == 'callerUid'
		assert auth_number(owner, 1) == 10001 && auth_number(owner, 2) == 4321
		assert unsafe { cstring_to_vstring(auth_text(owner, 3)) } == item[0]
		assert auth_read(owner, &id, 0) == 0
		assert store_token_authorized(store, owner, session) == if index in [0, 3] { 0 } else { -1 }
		assert store_token_authorized(store, owner, session + 100) == -1
		owner.mutex.lock(); owner.retire(session); owner.mutex.unlock()
		assert store_token_authorized(store, owner, session) == -1
	}
	token_dispatch(mut peer, 10, 'com.google.android.apps.maps', 'visible@example.test')
	assert auth_read(owner, &id, 0) == 1
	assert store_token_authorized(store, owner, 10) == 0
	assert store_set_visibility(store, c'visible@example.test', c'com.google', c'com.google.android.apps.maps', 3) == 1
	assert store_token_authorized(store, owner, 10) == -1
	assert store_set_visibility(store, c'visible@example.test', c'com.google', c'com.google.android.apps.maps', 2) == 1
	assert store_token_authorized(store, owner, 10) == 0
	owner.mutex.lock()
	owner.clear_current()
	prior := owner.sessions[10] or { panic('missing token session') }
	owner.sessions[10] = &AuthSession{command: prior.command, started: time.sys_mono_now() - 5 * time.minute}
	unsafe { free(prior) }
	owner.mutex.unlock()
	assert store_token_authorized(store, owner, 10) == -1
}

fn test_token_builder_copies_account_fields_and_preserves_existing_builder_abi() {
	assert abi_token_request(0, c'n', c'com.google', c't') == unsafe { nil }
	assert abi_token_request(1, unsafe { nil }, c'com.google', c't') == unsafe { nil }
	builder := abi_token_request(7, c'Zoë@example.test', c'com.google', c'oauth2:scope')
	assert builder != unsafe { nil }
	defer { abi_request_free(builder) }
	value := unsafe { &RequestBuilder(builder) }
	assert value.op == .get_auth_token && value.account_name == ?string('Zoë@example.test')
	assert value.account_type == ?string('com.google') && value.auth_token_type == ?string('oauth2:scope')
	assert abi_option(builder, c'locale', 1, c'en-GB', 0) == 0
	assert abi_request(1, 4, c'com.google', c'oauth2:scope') == unsafe { nil }
}
