// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import accountstore
import encoding.utf8
import os

// These owner capabilities retain the selected authenticator's root-peer
// channel. Only query() exposes accounts to another package, using the caller
// identity decoded from that channel rather than application options.
@[heap]
struct AccountStoreHandle {
	auth &Authenticator = unsafe { nil }
	db &accountstore.Store = unsafe { nil }
	owner string
	allowed_type string
mut:
	refs int = 1
	released bool
}

@[heap]
struct AccountInsertion {
	store &AccountStoreHandle = unsafe { nil }
	account accountstore.Account
	password accountstore.NullableString
mut:
	data map[string]?string
	visibility map[string]int
	bytes int
	finished bool
	failed bool
}

@[heap]
struct AccountSnapshot {
	store &AccountStoreHandle = unsafe { nil }
	accounts []accountstore.Account
}

@[heap]
struct AccountCell {
	store &AccountStoreHandle = unsafe { nil }
	value accountstore.NullableString
}

fn store_text(value &char, limit int) !string {
	if value == unsafe { nil } { return error('missing account store text') }
	unsafe {
		mut length := 0
		for length <= limit && value[length] != 0 { length++ }
		if length > limit { return error('account store text exceeds limit') }
		text := value.vstring_with_len(length)
		if !utf8.validate_str(text) { return error('invalid account store UTF-8') }
		return text.clone()
	}
}

fn store_optional(value &char, limit int) !accountstore.NullableString {
	if value == unsafe { nil } { return accountstore.NullableString{} }
	return accountstore.NullableString{value: store_text(value, limit)!}
}

fn store_account(name &char, account_type &char) !accountstore.Account {
	n := store_text(name, 1024)!
	t := store_text(account_type, 255) or { unsafe { n.free() }; return err }
	if n.len == 0 || t.len == 0 {
		unsafe { n.free(); t.free() }
		return error('empty account identity')
	}
	return accountstore.Account{n, t}
}

fn store_account_free(account accountstore.Account) {
	unsafe { account.name.free(); account.account_type.free() }
}

// The authenticator mutex guards bridge handles and their references. The
// database mutex is always acquired after this mutex.
fn store_live(s &AccountStoreHandle) bool {
	return !s.released && !s.auth.closed && !s.auth.released
}

fn store_release(mut s AccountStoreHandle) {
	mut a := s.auth
	a.mutex.lock()
	s.refs--
	if s.refs != 0 { a.mutex.unlock(); return }
	// Statements never escape the core. Unexpected SQLite close failures retain
	// the allocation rather than freeing a still-live connection.
	mut db := s.db
	accountstore.dispose(mut db) or { a.mutex.unlock(); return }
	a.refs--
	dispose_auth := a.refs == 0
	unsafe { s.owner.free(); s.allowed_type.free(); free(s) }
	a.mutex.unlock()
	if dispose_auth { auth_free(mut a) }
}

@[export: 'vinix_android_account_store_open']
pub fn store_open(auth voidptr, data &char, account_type &char, owner &char) voidptr {
	if auth == unsafe { nil } { return unsafe { nil } }
	path := store_text(data, 4096) or { return unsafe { nil } }
	defer { unsafe { path.free() } }
	t := store_text(account_type, 255) or { return unsafe { nil } }
	defer { unsafe { t.free() } }
	pkg := store_text(owner, 255) or { return unsafe { nil } }
	defer { unsafe { pkg.free() } }
	mut a := unsafe { &Authenticator(auth) }
	a.mutex.lock()
	defer { a.mutex.unlock() }
	if a.closed || a.released { return unsafe { nil } }
	db := accountstore.open(path, u32(os.geteuid()), pkg, t) or { return unsafe { nil } }
	a.refs++
	return &AccountStoreHandle{auth: a, db: db, owner: pkg.clone(), allowed_type: t.clone()}
}

@[export: 'vinix_android_account_store_close']
pub fn store_close(handle voidptr) i32 {
	if handle == unsafe { nil } { return -1 }
	mut s := unsafe { &AccountStoreHandle(handle) }
	mut a := s.auth
	a.mutex.lock()
	if s.released { a.mutex.unlock(); return -1 }
	s.released = true
	mut result := i32(0)
	s.db.close() or { result = -1 }
	a.mutex.unlock()
	store_release(mut s)
	return result
}

@[export: 'vinix_android_account_store_insertion']
pub fn store_insertion(handle voidptr, name &char, account_type &char, password &char) voidptr {
	if handle == unsafe { nil } { return unsafe { nil } }
	account := store_account(name, account_type) or { return unsafe { nil } }
	mut accepted := false
	defer { if !accepted { store_account_free(account) } }
	value := store_optional(password, 65536) or { return unsafe { nil } }
	defer { if !accepted { accountstore.dispose_nullable(value) } }
	mut size := account.name.len + account.account_type.len
	if text := value.value { size += text.len }
	mut s := unsafe { &AccountStoreHandle(handle) }
	s.auth.mutex.lock()
	defer { s.auth.mutex.unlock() }
	if !store_live(s) || account.account_type != s.allowed_type || size > 65536 {
		return unsafe { nil }
	}
	s.refs++
	accepted = true
	return &AccountInsertion{store: s, account: account, password: value, bytes: size}
}

@[export: 'vinix_android_account_store_userdata']
pub fn store_userdata(handle voidptr, key &char, value &char) i32 {
	if handle == unsafe { nil } { return -1 }
	mut b := unsafe { &AccountInsertion(handle) }
	b.store.auth.mutex.lock()
	defer { b.store.auth.mutex.unlock() }
	if !store_live(b.store) || b.finished || b.failed { return -1 }
	k := store_text(key, 4096) or { b.failed = true; return -1 }
	defer { unsafe { k.free() } }
	v := store_optional(value, 65536) or { b.failed = true; return -1 }
	mut size := k.len
	if text := v.value { size += text.len }
	if k.len == 0 || k in b.data || b.data.len >= 64 || b.bytes + size > 65536 {
		accountstore.dispose_nullable(v)
		b.failed = true
		return -1
	}
	b.data[k] = v.value
	b.bytes += size
	return 0
}

@[export: 'vinix_android_account_store_visibility']
pub fn store_visibility(handle voidptr, package_name &char, visibility i32) i32 {
	if handle == unsafe { nil } { return -1 }
	mut b := unsafe { &AccountInsertion(handle) }
	b.store.auth.mutex.lock()
	defer { b.store.auth.mutex.unlock() }
	if !store_live(b.store) || b.finished || b.failed { return -1 }
	pkg := store_text(package_name, 255) or { b.failed = true; return -1 }
	defer { unsafe { pkg.free() } }
	if pkg.len == 0 || pkg in b.visibility || b.visibility.len >= 64
		|| visibility < 1 || visibility > 4 || b.bytes + pkg.len > 65536 {
		b.failed = true
		return -1
	}
	b.visibility[pkg] = int(visibility)
	b.bytes += pkg.len
	return 0
}

@[export: 'vinix_android_account_store_commit']
pub fn store_commit(handle voidptr) i32 {
	if handle == unsafe { nil } { return -1 }
	mut b := unsafe { &AccountInsertion(handle) }
	b.store.auth.mutex.lock()
	defer { b.store.auth.mutex.unlock() }
	if !store_live(b.store) || b.finished { return -1 }
	b.finished = true
	if b.failed { return -1 }
	inserted := b.store.db.add(b.account, b.password.value, b.data, b.visibility) or { return -1 }
	return if inserted { 1 } else { 0 }
}

@[export: 'vinix_android_account_store_insertion_free']
pub fn store_insertion_free(handle voidptr) {
	if handle == unsafe { nil } { return }
	b := unsafe { &AccountInsertion(handle) }
	mut s := b.store
	store_account_free(b.account)
	accountstore.dispose_nullable(b.password)
	for _, value in b.data { if text := value { unsafe { text.free() } } }
	unsafe { b.data.free(); b.visibility.free(); free(b) }
	store_release(mut s)
}

@[export: 'vinix_android_account_store_snapshot']
pub fn store_snapshot(handle voidptr, account_type &char) voidptr {
	if handle == unsafe { nil } { return unsafe { nil } }
	value := store_optional(account_type, 255) or { return unsafe { nil } }
	defer { accountstore.dispose_nullable(value) }
	mut s := unsafe { &AccountStoreHandle(handle) }
	s.auth.mutex.lock()
	defer { s.auth.mutex.unlock() }
	if !store_live(s) { return unsafe { nil } }
	accounts := s.db.accounts(value.value, s.owner) or { return unsafe { nil } }
	s.refs++
	return &AccountSnapshot{store: s, accounts: accounts}
}

@[export: 'vinix_android_account_store_snapshot_count']
pub fn store_snapshot_count(handle voidptr) i32 {
	if handle == unsafe { nil } { return -1 }
	b := unsafe { &AccountSnapshot(handle) }
	b.store.auth.mutex.lock()
	defer { b.store.auth.mutex.unlock() }
	return if store_live(b.store) { i32(b.accounts.len) } else { -1 }
}

@[export: 'vinix_android_account_store_snapshot_name']
pub fn store_snapshot_name(handle voidptr, index u32) &char {
	if handle == unsafe { nil } { return unsafe { nil } }
	b := unsafe { &AccountSnapshot(handle) }
	b.store.auth.mutex.lock()
	defer { b.store.auth.mutex.unlock() }
	if !store_live(b.store) || index >= u32(b.accounts.len) { return unsafe { nil } }
	return &char(b.accounts[index].name.str)
}

@[export: 'vinix_android_account_store_snapshot_type']
pub fn store_snapshot_type(handle voidptr, index u32) &char {
	if handle == unsafe { nil } { return unsafe { nil } }
	b := unsafe { &AccountSnapshot(handle) }
	b.store.auth.mutex.lock()
	defer { b.store.auth.mutex.unlock() }
	if !store_live(b.store) || index >= u32(b.accounts.len) { return unsafe { nil } }
	return &char(b.accounts[index].account_type.str)
}

@[export: 'vinix_android_account_store_snapshot_free']
pub fn store_snapshot_free(handle voidptr) {
	if handle == unsafe { nil } { return }
	b := unsafe { &AccountSnapshot(handle) }
	mut s := b.store
	accountstore.dispose_accounts(b.accounts)
	unsafe { free(b) }
	store_release(mut s)
}

// The session's caller comes from the authenticated root channel. Preserve its
// capability across response creation to reject an id reused after cancellation.
@[export: 'vinix_android_account_store_query']
pub fn store_query(handle voidptr, auth voidptr, session u64) i32 {
	if handle == unsafe { nil } || auth == unsafe { nil } { return -1 }
	mut s := unsafe { &AccountStoreHandle(handle) }
	mut a := s.auth
	if voidptr(a) != auth { return -1 }
	a.mutex.lock()
	if !store_live(s) { a.mutex.unlock(); return -1 }
	command := a.sessions[session] or { a.mutex.unlock(); return -1 }
	if command.command.request.operation != .get_accounts { a.mutex.unlock(); return -1 }
	accounts := s.db.accounts(command.command.request.account_type, command.command.caller.package_name) or {
		a.mutex.unlock(); return -1
	}
	capability := command.command.capability.clone()
	s.refs++
	a.mutex.unlock()
	defer {
		accountstore.dispose_accounts(accounts)
		unsafe { capability.free() }
		store_release(mut s)
	}
	response := auth_response(auth, session, 3)
	if response == unsafe { nil } { return -1 }
	defer { auth_response_free(response) }
	b := unsafe { &AuthResponse(response) }
	if !same_capability(capability, b.capability) { return -1 }
	for account in accounts {
		if auth_response_account(response, &char(account.name.str), &char(account.account_type.str)) != 0 { return -1 }
	}
	return auth_response_send(response)
}

fn store_get(handle voidptr, name &char, account_type &char, key &char, password bool) voidptr {
	if handle == unsafe { nil } { return unsafe { nil } }
	account := store_account(name, account_type) or { return unsafe { nil } }
	defer { store_account_free(account) }
	mut s := unsafe { &AccountStoreHandle(handle) }
	s.auth.mutex.lock()
	defer { s.auth.mutex.unlock() }
	if !store_live(s) { return unsafe { nil } }
	mut value := accountstore.NullableString{}
	if password {
		value = s.db.password(account) or { return unsafe { nil } }
	} else {
		k := store_text(key, 4096) or { return unsafe { nil } }
		defer { unsafe { k.free() } }
		value = s.db.user_data(account, k) or { return unsafe { nil } }
	}
	s.refs++
	return &AccountCell{store: s, value: value}
}

@[export: 'vinix_android_account_store_password']
pub fn store_password(handle voidptr, name &char, account_type &char) voidptr {
	return store_get(handle, name, account_type, unsafe { nil }, true)
}

@[export: 'vinix_android_account_store_get_data']
pub fn store_get_data(handle voidptr, name &char, account_type &char, key &char) voidptr {
	return store_get(handle, name, account_type, key, false)
}

@[export: 'vinix_android_account_store_cell_text']
pub fn store_cell_text(handle voidptr) &char {
	if handle == unsafe { nil } { return unsafe { nil } }
	b := unsafe { &AccountCell(handle) }
	b.store.auth.mutex.lock()
	defer { b.store.auth.mutex.unlock() }
	if !store_live(b.store) { return unsafe { nil } }
	if text := b.value.value { return &char(text.str) }
	return unsafe { nil }
}

@[export: 'vinix_android_account_store_cell_free']
pub fn store_cell_free(handle voidptr) {
	if handle == unsafe { nil } { return }
	b := unsafe { &AccountCell(handle) }
	mut s := b.store
	accountstore.dispose_nullable(b.value)
	unsafe { free(b) }
	store_release(mut s)
}

fn store_set(handle voidptr, name &char, account_type &char, key &char, value &char, password bool) i32 {
	if handle == unsafe { nil } { return -1 }
	account := store_account(name, account_type) or { return -1 }
	defer { store_account_free(account) }
	v := store_optional(value, 65536) or { return -1 }
	defer { accountstore.dispose_nullable(v) }
	mut s := unsafe { &AccountStoreHandle(handle) }
	s.auth.mutex.lock()
	defer { s.auth.mutex.unlock() }
	if !store_live(s) { return -1 }
	if password {
		s.db.set_password(account, v.value) or { return -1 }
	} else {
		k := store_text(key, 4096) or { return -1 }
		defer { unsafe { k.free() } }
		s.db.set_user_data(account, k, v.value) or { return -1 }
	}
	return 0
}

@[export: 'vinix_android_account_store_set_password']
pub fn store_set_password(handle voidptr, name &char, account_type &char, value &char) i32 {
	return store_set(handle, name, account_type, unsafe { nil }, value, true)
}

@[export: 'vinix_android_account_store_set_data']
pub fn store_set_data(handle voidptr, name &char, account_type &char, key &char, value &char) i32 {
	return store_set(handle, name, account_type, key, value, false)
}

@[export: 'vinix_android_account_store_set_visibility']
pub fn store_set_visibility(handle voidptr, name &char, account_type &char, package_name &char, visibility i32) i32 {
	if handle == unsafe { nil } { return -1 }
	account := store_account(name, account_type) or { return -1 }
	defer { store_account_free(account) }
	pkg := store_text(package_name, 255) or { return -1 }
	defer { unsafe { pkg.free() } }
	mut s := unsafe { &AccountStoreHandle(handle) }
	s.auth.mutex.lock()
	defer { s.auth.mutex.unlock() }
	if !store_live(s) { return -1 }
	changed := s.db.set_visibility(account, pkg, int(visibility)) or { return -1 }
	return if changed { 1 } else { 0 }
}
