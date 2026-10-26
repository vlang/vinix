// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import accountipc
import nativeaccountauth
import os

#include <sys/socket.h>
fn C.socketpair(i32, i32, i32, &i32) i32

// Production auth_open requires a root peer. This internal factory gives the
// rootless suite the same framed command stream without weakening that check.
fn store_bridge_pair() (&Authenticator, &accountipc.Stream) {
	mut fds := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &fds[0]) == 0
	return &Authenticator{stream: accountipc.open_stream(int(fds[0])) or { panic(err) }},
		accountipc.open_stream(int(fds[1])) or { panic(err) }
}

fn store_bridge_path(label string) string {
	path := os.join_path(os.home_dir(), '.local', 'state', 'vinix', 'android',
		'account-store-bridge-${os.getpid()}-${label}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path, mode: 0o700) or { panic(err) }
	os.chmod(path, 0o700) or { panic(err) }
	return path
}

fn store_bridge_dispatch(mut peer accountipc.Stream, id u64, package_name string,
	operation nativeaccountauth.Operation, account_type ?string) {
	wire := accountipc.encode_command(accountipc.Command{
		session: id
		capability: []u8{len: 32, init: u8(id)}
		caller: nativeaccountauth.Caller{package_name, 10001, 10001, 1234,
			'a'.repeat(64), 'b'.repeat(64)}
		request: nativeaccountauth.Request{
			id: id
			operation: operation
			account_type: account_type
			options: if operation == .add_account {
				[nativeaccountauth.Option{'claimedPackage',
					nativeaccountauth.Scalar{kind: .text, text: 'com.google.android.gms'}}]
			} else { []nativeaccountauth.Option{} }
		}
	}) or { panic(err) }
	defer { unsafe { wire.free() } }
	peer.enqueue(wire) or { panic(err) }
	peer.flush() or { panic(err) }
}

fn store_bridge_event(owner voidptr, mut peer accountipc.Stream) accountipc.Event {
	mut id := u64(0)
	assert auth_read(owner, &id, 0) == 0 // flush and release borrowed getter view
	packet := peer.read(0) or { panic(err) }
	assert packet.available
	defer { unsafe { packet.body.free() } }
	return accountipc.decode_event(packet.header, packet.body, true) or { panic(err) }
}

fn store_bridge_insert(store voidptr, name &char, visible bool) {
	b := store_insertion(store, name, c'com.google', unsafe { nil })
	assert b != unsafe { nil }
	assert store_userdata(b, c'GoogleUserId', c'δοκιμή 🌍') == 0
	if visible { assert store_visibility(b, c'com.google.android.apps.maps', 2) == 0 }
	assert store_commit(b) == 1
	assert store_commit(b) == -1
	assert store_userdata(b, c'late', c'value') == -1
	store_insertion_free(b)
}

fn test_store_bridge_persistence_nullable_cells_and_owner_snapshot() {
	mut owner, mut peer := store_bridge_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	path := store_bridge_path('persist')
	defer { os.rmdir_all(path) or {} }
	assert store_open(unsafe { nil }, &char(path.str), c'com.google', c'com.google.android.gms') == unsafe { nil }
	store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert store != unsafe { nil } && owner.refs == 2
	store_bridge_insert(store, c'Zoë 🌍@example.test', false)
	assert store_insertion(store, c'wrong', c'org.other', unsafe { nil }) == unsafe { nil }
	cell := store_password(store, c'Zoë 🌍@example.test', c'com.google')
	assert cell != unsafe { nil } && store_cell_text(cell) == unsafe { nil }
	store_cell_free(cell)
	assert store_set_password(store, c'Zoë 🌍@example.test', c'com.google', c'') == 0
	empty := store_password(store, c'Zoë 🌍@example.test', c'com.google')
	assert empty != unsafe { nil } && store_cell_text(empty) != unsafe { nil }
	assert unsafe { cstring_to_vstring(store_cell_text(empty)) } == ''
	store_cell_free(empty)
	assert store_set_password(store, c'Zoë 🌍@example.test', c'com.google', c'long-lived credential') == 0
	assert store_set_data(store, c'Zoë 🌍@example.test', c'com.google', c'GoogleUserId', c'持続 🌍') == 0
	assert store_set_data(store, c'Zoë 🌍@example.test', c'com.google', c'deleted', c'temporary') == 0
	assert store_set_data(store, c'Zoë 🌍@example.test', c'com.google', c'deleted', unsafe { nil }) == 0
	assert store_set_visibility(store, c'missing', c'com.google', c'com.google.android.apps.maps', 2) == 0
	assert store_set_visibility(store, c'Zoë 🌍@example.test', c'com.google', c'com.google.android.apps.maps', 2) == 1
	duplicate := store_insertion(store, c'Zoë 🌍@example.test', c'com.google', c'replacement')
	assert store_userdata(duplicate, c'GoogleUserId', c'replacement') == 0
	assert store_commit(duplicate) == 0
	store_insertion_free(duplicate)
	assert store_close(store) == 0 && owner.refs == 1
	reopened := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert reopened != unsafe { nil }
	defer { assert store_close(reopened) == 0 }
	password := store_password(reopened, c'Zoë 🌍@example.test', c'com.google')
	assert unsafe { cstring_to_vstring(store_cell_text(password)) } == 'long-lived credential'
	store_cell_free(password)
	data := store_get_data(reopened, c'Zoë 🌍@example.test', c'com.google', c'GoogleUserId')
	assert unsafe { cstring_to_vstring(store_cell_text(data)) } == '持続 🌍'
	store_cell_free(data)
	deleted := store_get_data(reopened, c'Zoë 🌍@example.test', c'com.google', c'deleted')
	assert deleted != unsafe { nil } && store_cell_text(deleted) == unsafe { nil }
	store_cell_free(deleted)
	assert store_password(reopened, c'missing', c'com.google') == unsafe { nil }
	assert store_set_password(reopened, c'Zoë 🌍@example.test', c'org.other', c'bad') == -1
	snapshot := store_snapshot(reopened, unsafe { nil })
	assert snapshot != unsafe { nil } && store_snapshot_count(snapshot) == 1
	assert unsafe { cstring_to_vstring(store_snapshot_name(snapshot, 0)) } == 'Zoë 🌍@example.test'
	assert unsafe { cstring_to_vstring(store_snapshot_type(snapshot, 0)) } == 'com.google'
	assert store_snapshot_name(snapshot, 1) == unsafe { nil }
	assert store_snapshot_type(snapshot, 0xffffffff) == unsafe { nil }
	store_snapshot_free(snapshot)
	wrong_type := store_snapshot(reopened, c'org.other')
	assert wrong_type != unsafe { nil } && store_snapshot_count(wrong_type) == 0
	store_snapshot_free(wrong_type)
}

fn test_store_bridge_query_uses_framed_caller_not_options_or_current_borrow() {
	mut owner, mut peer := store_bridge_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	path := store_bridge_path('query')
	defer { os.rmdir_all(path) or {} }
	store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert store != unsafe { nil }
	defer { assert store_close(store) == 0 }
	store_bridge_insert(store, c'hidden@example.test', false)
	store_bridge_insert(store, c'可視 🌍@example.test', true)
	mut id := u64(0)
	for index, pkg in ['com.google.android.apps.maps', 'org.untrusted.app', 'com.google.android.gms'] {
		session := u64(index + 1)
		store_bridge_dispatch(mut peer, session, pkg, .get_accounts, none)
		assert auth_read(owner, &id, 0) == 1 && id == session
		assert auth_operation(owner) == 1
		assert auth_read(owner, &id, 0) == 0 && owner.current == unsafe { nil }
		assert store_query(store, owner, session + 100) == -1
		assert store_query(store, owner, session) == 0
		assert store_query(store, owner, session) == -1
		event := store_bridge_event(owner, mut peer)
		assert event.kind == .accounts && event.id == session && event.options.len == 0
		assert event.capability == []u8{len: 32, init: u8(session)}
		if index == 0 {
			assert event.accounts.len == 1 && event.accounts[0].name == '可視 🌍@example.test'
		} else { assert event.accounts.len == if index == 1 { 0 } else { 2 } }
		accountipc.dispose_event(event)
	}
	assert store_set_visibility(store, c'可視 🌍@example.test', c'com.google', c'com.google.android.apps.maps', 3) == 1
	store_bridge_dispatch(mut peer, 8, 'com.google.android.apps.maps', .get_accounts, 'com.google')
	assert auth_read(owner, &id, 0) == 1 && store_query(store, owner, 8) == 0
	hidden := store_bridge_event(owner, mut peer)
	assert hidden.accounts.len == 0
	accountipc.dispose_event(hidden)
	store_bridge_dispatch(mut peer, 9, 'com.google.android.gms', .get_accounts, 'org.other')
	assert auth_read(owner, &id, 0) == 1 && store_query(store, owner, 9) == 0
	other := store_bridge_event(owner, mut peer)
	assert other.accounts.len == 0
	accountipc.dispose_event(other)
	store_bridge_dispatch(mut peer, 10, 'com.google.android.apps.maps', .add_account, 'com.google')
	assert auth_read(owner, &id, 0) == 1 && store_query(store, owner, 10) == -1
	mut second, mut second_peer := store_bridge_pair()
	assert store_query(store, second, 10) == -1
	auth_close(second); second_peer.close(); unsafe { free(second_peer) }
}

fn test_store_bridge_builders_snapshots_and_cells_survive_both_close_orders() {
	for auth_first in [true, false] {
		mut owner, mut peer := store_bridge_pair()
		defer { peer.close(); unsafe { free(peer) } }
		path := store_bridge_path(if auth_first { 'auth-first' } else { 'store-first' })
		defer { os.rmdir_all(path) or {} }
		store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
		assert store != unsafe { nil }
		store_bridge_insert(store, c'saved@example.test', true)
		assert store_set_password(store, c'saved@example.test', c'com.google', c'credential') == 0
		builder := store_insertion(store, c'late@example.test', c'com.google', c'pending')
		assert builder != unsafe { nil }
		snapshot := store_snapshot(store, unsafe { nil })
		cell := store_password(store, c'saved@example.test', c'com.google')
		assert store_snapshot_count(snapshot) == 1 && cell != unsafe { nil }
		assert owner.refs == 2
		if auth_first {
			auth_close(owner)
			assert owner.closed && owner.refs == 1
			assert store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms') == unsafe { nil }
		} else {
			assert store_close(store) == 0
			assert !owner.closed && owner.refs == 2
		}
		assert store_commit(builder) == -1
		assert store_userdata(builder, c'late', c'data') == -1
		assert store_visibility(builder, c'org.caller', 2) == -1
		assert store_snapshot_count(snapshot) == -1
		assert store_snapshot_name(snapshot, 0) == unsafe { nil }
		assert store_snapshot_type(snapshot, 0) == unsafe { nil }
		assert store_cell_text(cell) == unsafe { nil }
		assert store_password(store, c'saved@example.test', c'com.google') == unsafe { nil }
		assert store_get_data(store, c'saved@example.test', c'com.google', c'GoogleUserId') == unsafe { nil }
		assert store_snapshot(store, unsafe { nil }) == unsafe { nil }
		assert store_insertion(store, c'another', c'com.google', unsafe { nil }) == unsafe { nil }
		assert store_set_password(store, c'saved@example.test', c'com.google', c'bad') == -1
		assert store_set_data(store, c'saved@example.test', c'com.google', c'key', c'bad') == -1
		assert store_set_visibility(store, c'saved@example.test', c'com.google', c'org.caller', 2) == -1
		assert store_query(store, owner, 1) == -1
		if auth_first { assert store_close(store) == 0 } else { auth_close(owner) }
		assert store_close(store) == -1 // retained derived handles keep this safe
		store_insertion_free(builder)
		store_snapshot_free(snapshot)
		store_cell_free(cell) // last store/auth references are released here
	}
}

fn test_store_bridge_rejected_partial_insertions_are_atomic_and_bounded() {
	mut owner, mut peer := store_bridge_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	path := store_bridge_path('bounds')
	defer { os.rmdir_all(path) or {} }
	store := store_open(owner, &char(path.str), c'com.google', c'com.google.android.gms')
	assert store != unsafe { nil }
	defer { assert store_close(store) == 0 }
	mut invalid := [u8(255), u8(0)]!
	assert store_insertion(store, &char(&invalid[0]), c'com.google', unsafe { nil }) == unsafe { nil }
	too_long := 'x'.repeat(65537)
	defer { unsafe { too_long.free() } }
	assert store_insertion(store, c'oversized', c'com.google', &char(too_long.str)) == unsafe { nil }
	for variant in ['duplicate-data', 'bad-utf8', 'oversized', 'entry-count', 'bad-visibility', 'bad-package'] {
		builder := store_insertion(store, &char(variant.str), c'com.google', unsafe { nil })
		assert builder != unsafe { nil }
		assert store_userdata(builder, c'initial', c'valid') == 0
		match variant {
			'duplicate-data' { assert store_userdata(builder, c'initial', c'replacement') == -1 }
			'bad-utf8' { assert store_userdata(builder, c'other', &char(&invalid[0])) == -1 }
			'oversized' { assert store_userdata(builder, c'other', &char(too_long.str)) == -1 }
			'entry-count' {
				for i in 0 .. 63 {
					key := 'key-${i}'
					assert store_userdata(builder, &char(key.str), c'') == 0
					unsafe { key.free() }
				}
				assert store_userdata(builder, c'overflow', c'') == -1
			}
			'bad-visibility' { assert store_visibility(builder, c'org.caller', 0) == -1 }
			else { assert store_visibility(builder, c'bad/package', 2) == 0 }
		}
		assert store_commit(builder) == -1
		assert store_commit(builder) == -1
		store_insertion_free(builder)
	}
	snapshot := store_snapshot(store, unsafe { nil })
	assert snapshot != unsafe { nil } && store_snapshot_count(snapshot) == 0
	store_snapshot_free(snapshot)
	assert store_snapshot_count(unsafe { nil }) == -1
	assert store_close(unsafe { nil }) == -1
	store_cell_free(unsafe { nil }); store_snapshot_free(unsafe { nil }); store_insertion_free(unsafe { nil })
}

fn test_authenticator_get_accounts_response_shape_unicode_and_bound() {
	mut owner, mut peer := store_bridge_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	store_bridge_dispatch(mut peer, 31, 'com.google.android.apps.maps', .get_accounts, none)
	mut id := u64(0)
	assert auth_read(owner, &id, 0) == 1 && auth_operation(owner) == 1
	assert auth_response(owner, 31, 1) == unsafe { nil }
	assert auth_response(owner, 31, 4) == unsafe { nil }
	response := auth_response(owner, 31, 3)
	assert response != unsafe { nil }
	assert auth_response_option(response, c'invalid', 1, c'value', 0) == -1
	assert auth_response_account(response, c'', c'com.google') == -1
	assert auth_response_account(response, c'name', c'') == -1
	mut invalid := [u8(255), u8(0)]!
	assert auth_response_account(response, &char(&invalid[0]), c'com.google') == -1
	too_long := 'x'.repeat(4097)
	assert auth_response_account(response, &char(too_long.str), c'com.google') == -1
	unsafe { too_long.free() }
	assert auth_response_account(response, c'Zoë 🌍@example.test', c'com.google') == 0
	assert auth_response_account(response, c'Zoë 🌍@example.test', c'com.google') == -1
	for i in 1 .. 64 {
		name := 'account-${i}@example.test'
		assert auth_response_account(response, &char(name.str), c'com.google') == 0
		unsafe { name.free() }
	}
	assert auth_response_account(response, c'overflow', c'com.google') == -1
	assert auth_response_send(response) == 0 && auth_response_send(response) == -1
	auth_response_free(response)
	event := store_bridge_event(owner, mut peer)
	assert event.kind == .accounts && event.accounts.len == 64 && event.options.len == 0
	assert event.accounts[0].name == 'Zoë 🌍@example.test'
	assert event.accounts[0].account_type == 'com.google'
	accountipc.dispose_event(event)
	assert owner.sessions.len == 0
}
