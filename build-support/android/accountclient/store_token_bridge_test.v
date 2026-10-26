// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import accountipc
import nativeaccountauth
import os
import time

#include <sys/socket.h>
fn C.socketpair(i32, i32, i32, &i32) i32

fn cache_bridge_pair() (&Authenticator, &accountipc.Stream) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return &Authenticator{stream: accountipc.open_stream(int(fds[0])) or { panic(err) }},
		accountipc.open_stream(int(fds[1])) or { panic(err) }
}

fn cache_bridge_path(label string) string {
	path := os.join_path(os.home_dir(), '.local', 'state', 'vinix', 'android',
		'account-cache-bridge-${os.getpid()}-${label}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path, mode: 0o700) or { panic(err) }
	os.chmod(path, 0o700) or { panic(err) }
	return path
}

fn cache_bridge_insert(store voidptr, name &char) {
	builder := store_insertion(store, name, c'com.google', unsafe { nil })
	assert builder != unsafe { nil }
	assert store_commit(builder) == 1
	store_insertion_free(builder)
}

fn cache_bridge_expect(cell voidptr, expected ?string) {
	assert cell != unsafe { nil }
	defer { store_cell_free(cell) }
	text := store_cell_text(cell)
	if value := expected {
		assert text != unsafe { nil }
		assert unsafe { cstring_to_vstring(text) } == value
	} else {
		assert text == unsafe { nil }
	}
}

fn cache_bridge_dispatch(mut peer accountipc.Stream, id u64, operation nativeaccountauth.Operation,
	account_type string, token ?string) {
	wire := accountipc.encode_command(accountipc.Command{
		session: id
		capability: []u8{len: 32, init: u8(id)}
		caller: nativeaccountauth.Caller{'org.untrusted.app', 10001, 10001, 4321,
			'a'.repeat(64), 'b'.repeat(64)}
		request: nativeaccountauth.Request{id: id, operation: operation,
			account_type: account_type, token_value: token}
	}) or { panic(err) }
	defer { unsafe { wire.free() } }
	peer.enqueue(wire) or { panic(err) }
	peer.flush() or { panic(err) }
}

fn cache_bridge_ack(owner voidptr, mut peer accountipc.Stream, session u64) {
	mut id := u64(0)
	assert auth_read(owner, &id, 0) == 0
	packet := peer.read(0) or { panic(err) }
	assert packet.available
	event := accountipc.decode_event(packet.header, packet.body, true) or { panic(err) }
	assert event.kind == .result && event.id == session && event.options.len == 0 && event.accounts.len == 0
	accountipc.dispose_event(event)
	unsafe { packet.body.free() }
}

fn test_cache_bridge_explicit_nullable_values_bounds_and_persistence() {
	mut owner, mut peer := cache_bridge_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	path := cache_bridge_path('persist')
	defer { os.rmdir_all(path) or {} }
	store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert store != unsafe { nil }
	cache_bridge_insert(store, c'Zoë 🌍@example.test')
	cache_bridge_expect(store_peek_token(store, c'missing', c'com.google', c'oauth2:scope'), none)
	assert store_set_token(store, c'missing', c'com.google', c'oauth2:scope', c'value') == -1
	assert store_set_token(store, c'Zoë 🌍@example.test', c'org.other', c'oauth2:scope', c'value') == -1
	assert store_peek_token(store, c'Zoë 🌍@example.test', c'org.other', c'oauth2:scope') == unsafe { nil }
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope', c'') == 0
	cache_bridge_expect(store_peek_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope'), '')
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope', c'持続 token 🌍') == 0
	prior := store_peek_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope')
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope', unsafe { nil }) == 0
	cache_bridge_expect(prior, '持続 token 🌍')
	cache_bridge_expect(store_peek_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope'), none)
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope', c'persisted token') == 0
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'to-delete', c'') == 0
	assert store_invalidate_token(store, c'com.google', c'') == 0
	cache_bridge_expect(store_peek_token(store, c'Zoë 🌍@example.test', c'com.google', c'to-delete'), none)
	assert store_invalidate_token(store, c'org.other', c'persisted token') == -1
	assert store_invalidate_token(store, c'com.google', unsafe { nil }) == -1
	assert store_invalidate_token(store, c'com.google', c'unmatched token') == 0
	oversized := 'x'.repeat(4097)
	invalid_utf8 := [u8(0xff), 0]
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'', c'value') == -1
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', &char(oversized.str), c'value') == -1
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope', &char(oversized.str)) == -1
	assert store_set_token(store, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope', &char(invalid_utf8.data)) == -1
	assert store_invalidate_token(store, c'com.google', &char(oversized.str)) == -1
	assert store_peek_token(store, c'Zoë 🌍@example.test', c'com.google', unsafe { nil }) == unsafe { nil }
	assert store_set_token(unsafe { nil }, c'n', c'com.google', c't', c'v') == -1
	assert store_peek_token(unsafe { nil }, c'n', c'com.google', c't') == unsafe { nil }
	assert store_invalidate_token(unsafe { nil }, c'com.google', c't') == -1
	assert store_close(store) == 0
	reopened := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert reopened != unsafe { nil }
	cache_bridge_expect(store_peek_token(reopened, c'Zoë 🌍@example.test', c'com.google', c'oauth2:scope'), 'persisted token')
	assert store_close(reopened) == 0
}

fn test_cache_bridge_cells_retain_both_close_orders() {
	for auth_first in [true, false] {
		mut owner, mut peer := cache_bridge_pair()
		path := cache_bridge_path('close-${auth_first}')
		store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
		assert store != unsafe { nil }
		cache_bridge_insert(store, c'n')
		assert store_set_token(store, c'n', c'com.google', c't', c'value') == 0
		cell := store_peek_token(store, c'n', c'com.google', c't')
		assert cell != unsafe { nil }
		if auth_first { auth_close(owner) } else { assert store_close(store) == 0 }
		assert store_cell_text(cell) == unsafe { nil }
		assert store_set_token(store, c'n', c'com.google', c't', c'replacement') == -1
		assert store_peek_token(store, c'n', c'com.google', c't') == unsafe { nil }
		assert store_invalidate_token(store, c'com.google', c'value') == -1
		if auth_first { assert store_close(store) == 0 } else { auth_close(owner) }
		assert store_close(store) == -1
		store_cell_free(cell)
		peer.close()
		unsafe { free(peer) }
		os.rmdir_all(path) or { panic(err) }
	}
}

fn test_cache_bridge_invalidation_requires_live_exact_type_session_and_acknowledges_durable_deletion() {
	mut owner, mut peer := cache_bridge_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	path := cache_bridge_path('invalidate')
	defer { os.rmdir_all(path) or {} }
	store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert store != unsafe { nil }
	cache_bridge_insert(store, c'a')
	cache_bridge_insert(store, c'b')
	assert store_set_token(store, c'a', c'com.google', c'first', c'exact token') == 0
	assert store_set_token(store, c'b', c'com.google', c'second', c'exact token') == 0
	assert store_set_token(store, c'a', c'com.google', c'other', c'exact token suffix') == 0
	mut id := u64(0)
	for index, operation in [nativeaccountauth.Operation.get_accounts, .invalidate_auth_token, .invalidate_auth_token] {
		session := u64(index + 1)
		cache_bridge_dispatch(mut peer, session, operation, if index == 1 { 'org.other' } else { 'com.google' },
			if operation == .invalidate_auth_token { ?string('exact token') } else { none })
		assert auth_read(owner, &id, 0) == 1 && id == session
		assert auth_read(owner, &id, 0) == 0
		if index == 2 {
			owner.mutex.lock()
			prior := owner.sessions[session] or { panic('missing cache session') }
			owner.sessions[session] = &AuthSession{command: prior.command, started: time.sys_mono_now() - 5 * time.minute}
			unsafe { free(prior) }
			owner.mutex.unlock()
		}
		assert store_invalidate(store, owner, session) == -1
		owner.mutex.lock(); owner.retire(session); owner.mutex.unlock()
	}
	cache_bridge_expect(store_peek_token(store, c'a', c'com.google', c'first'), 'exact token')
	cache_bridge_dispatch(mut peer, 10, .invalidate_auth_token, 'com.google', 'exact token')
	assert auth_read(owner, &id, 0) == 1 && id == 10
	assert auth_read(owner, &id, 0) == 0
	mut stranger, mut stranger_peer := cache_bridge_pair()
	assert store_invalidate(store, stranger, 10) == -1
	auth_close(stranger); stranger_peer.close(); unsafe { free(stranger_peer) }
	assert store_invalidate(store, owner, 999) == -1
	assert store_invalidate(store, owner, 10) == 0
	assert store_invalidate(store, owner, 10) == -1
	cache_bridge_ack(owner, mut peer, 10)
	assert store_set_token(store, c'a', c'com.google', c'empty', c'') == 0
	cache_bridge_dispatch(mut peer, 11, .invalidate_auth_token, 'com.google', '')
	assert auth_read(owner, &id, 0) == 1 && id == 11
	assert store_invalidate(store, owner, 11) == 0
	cache_bridge_ack(owner, mut peer, 11)
	assert store_close(store) == 0
	reopened := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert reopened != unsafe { nil }
	cache_bridge_expect(store_peek_token(reopened, c'a', c'com.google', c'first'), none)
	cache_bridge_expect(store_peek_token(reopened, c'b', c'com.google', c'second'), none)
	cache_bridge_expect(store_peek_token(reopened, c'a', c'com.google', c'empty'), none)
	cache_bridge_expect(store_peek_token(reopened, c'a', c'com.google', c'other'), 'exact token suffix')
	assert store_close(reopened) == 0
}
