// SPDX-License-Identifier: GPL-2.0-or-later
module accountstore

import os

const token_owner = 'com.google.android.gms'
const token_maps = 'com.google.android.apps.maps'
const token_kind = 'com.google'

fn token_fixture(label string) string {
	path := os.join_path(os.home_dir(), '.local', 'state', 'vinix', 'android', 'accountstore-token-test-${os.getpid()}-${label}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path, mode: 0o700) or { panic(err) }
	os.chmod(path, 0o700) or { panic(err) }
	return path
}

fn token_account(name string) Account { return Account{name, token_kind} }

fn assert_token(mut store Store, account Account, token_type string, expected ?string) {
	value := store.auth_token(account, token_type) or { panic(err) }
	defer { dispose_nullable(value) }
	// Failure output must not print the token value.
	matches := value.value == expected
	assert matches
}

fn token_row_count(store &Store, query string) i64 {
	statement := prepare(store.db, query) or { panic(err) }
	defer { C.sqlite3_finalize(statement) }
	assert C.sqlite3_step(statement) == C.SQLITE_ROW
	return C.sqlite3_column_int64(statement, 0)
}

fn test_explicit_tokens_migrate_old_store_and_survive_reopen_without_changing_metadata() {
	path := token_fixture('migration')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), token_owner, token_kind)!
	name := "bound');DELETE FROM accounts;--@example.test"
	a := token_account(name)
	assert store.add(a, 'fixture-password', {'gaia': ?string('fixture-id')}, {token_maps: 2})!
	// Reproduce the schema shipped before explicit token persistence existed.
	execute(store.db, 'DROP TABLE authtokens')!
	store.close()!
	mut migrated := open(path, u32(os.geteuid()), token_owner, token_kind)!
	assert_token(mut migrated, a, 'oauth2:fixture-scope', none)
	migrated.set_auth_token(a, 'oauth2:fixture-scope', 'fixture-value')!
	retained := migrated.auth_token(a, 'oauth2:fixture-scope')!
	defer { dispose_nullable(retained) }
	migrated.set_auth_token(a, 'oauth2:fixture-scope', 'fixture-updated')!
	migrated.close()!
	retained_matches := retained.value == ?string('fixture-value')
	assert retained_matches
	mut reopened := open(path, u32(os.geteuid()), token_owner, token_kind)!
	defer { reopened.close() or { panic(err) } }
	assert_token(mut reopened, a, 'oauth2:fixture-scope', 'fixture-updated')
	password := reopened.password(a)!
	password_matches := password.value == ?string('fixture-password')
	assert password_matches
	dispose_nullable(password)
	data := reopened.user_data(a, 'gaia')!
	assert data.value == ?string('fixture-id')
	dispose_nullable(data)
	accounts := reopened.accounts(none, token_maps)!
	assert accounts == [a]
	dispose_accounts(accounts)
	for entry, mode in {'accounts': u32(0o700), 'accounts/accounts.sqlite': u32(0o600)} {
		info := os.stat(path + '/' + entry)!
		assert u32(info.mode) & 0o777 == mode
	}
}

fn test_explicit_token_identity_nullable_delete_and_account_cascade() {
	path := token_fixture('identity')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), token_owner, token_kind)!
	defer { store.close() or { panic(err) } }
	a := token_account('first')
	b := token_account('second')
	assert store.add(a, none, {}, {})!
	assert store.add(b, none, {}, {})!
	assert_token(mut store, token_account('missing'), 'scope', none)
	assert_token(mut store, a, 'missing-scope', none)
	store.set_auth_token(a, 'scope', 'fixture-one')!
	store.set_auth_token(a, 'other-scope', 'fixture-two')!
	store.set_auth_token(b, 'scope', 'fixture-three')!
	store.set_auth_token(a, 'scope', '')!
	assert_token(mut store, a, 'scope', '')
	assert_token(mut store, a, 'other-scope', 'fixture-two')
	assert_token(mut store, b, 'scope', 'fixture-three')
	store.set_auth_token(a, 'scope', none)!
	assert_token(mut store, a, 'scope', none)
	store.set_auth_token(a, 'missing-scope', none)!
	mut missing := false
	store.set_auth_token(token_account('missing'), 'scope', 'fixture') or { missing = true }
	assert missing
	execute(store.db, "DELETE FROM accounts WHERE name='first'")!
	assert token_row_count(store, 'SELECT count(*) FROM authtokens') == 1
	assert_token(mut store, a, 'other-scope', none)
	assert_token(mut store, b, 'scope', 'fixture-three')
}

fn test_invalidation_matches_exact_value_across_selected_type_only() {
	path := token_fixture('invalidate')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), token_owner, token_kind)!
	defer { store.close() or { panic(err) } }
	a := token_account('first')
	b := token_account('second')
	assert store.add(a, none, {}, {})!
	assert store.add(b, none, {}, {})!
	for pair in [[a.name, 'one'], [a.name, 'two'], [b.name, 'one']] {
		store.set_auth_token(token_account(pair[0]), pair[1], 'fixture-shared')!
	}
	store.set_auth_token(b, 'two', 'fixture-shared-suffix')!
	// Defensive type isolation also applies if another account type is present.
	execute(store.db, "INSERT INTO accounts(name,type) VALUES('foreign','other.type')")!
	execute(store.db, "INSERT INTO authtokens(account,token_type,token) SELECT id,'one','fixture-shared' FROM accounts WHERE type='other.type'")!
	mut wrong_type := false
	store.invalidate_auth_token('other.type', 'fixture-shared') or { wrong_type = true }
	assert wrong_type
	store.invalidate_auth_token(token_kind, 'fixture-shared')!
	assert_token(mut store, a, 'one', none)
	assert_token(mut store, a, 'two', none)
	assert_token(mut store, b, 'one', none)
	assert_token(mut store, b, 'two', 'fixture-shared-suffix')
	assert token_row_count(store, "SELECT count(*) FROM authtokens t JOIN accounts a ON a.id=t.account WHERE a.type='other.type'") == 1
	store.invalidate_auth_token(token_kind, 'fixture-shared')!
	store.set_auth_token(a, 'empty', '')!
	store.invalidate_auth_token(token_kind, '')!
	assert_token(mut store, a, 'empty', none)
}

fn test_explicit_token_scalar_validation_and_closed_store() {
	path := token_fixture('scalars')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), token_owner, token_kind)!
	a := token_account('first')
	assert store.add(a, none, {}, {})!
	store.set_auth_token(a, 'scope', 'fixture-preserved')!
	for invalid in ['', '\x00', '\xff', 'x'.repeat(max_token_scalar + 1)] {
		mut rejected_set := false
		store.set_auth_token(a, invalid, 'fixture') or { rejected_set = true }
		assert rejected_set
		mut rejected_peek := false
		store.auth_token(a, invalid) or { rejected_peek = true }
		assert rejected_peek
	}
	for invalid in ['\x00', '\xff', 'x'.repeat(max_token_scalar + 1)] {
		mut rejected_set := false
		store.set_auth_token(a, 'scope', invalid) or { rejected_set = true }
		assert rejected_set
		mut rejected_invalidate := false
		store.invalidate_auth_token(token_kind, invalid) or { rejected_invalidate = true }
		assert rejected_invalidate
	}
	for invalid in [Account{'first', 'other.type'}, Account{'', token_kind}, Account{'\xff', token_kind}] {
		mut rejected_set := false
		store.set_auth_token(invalid, 'scope', 'fixture') or { rejected_set = true }
		assert rejected_set
		mut rejected_peek := false
		store.auth_token(invalid, 'scope') or { rejected_peek = true }
		assert rejected_peek
	}
	assert_token(mut store, a, 'scope', 'fixture-preserved')
	store.set_auth_token(a, 'unicode-\u03b1', 'fixture-\u03b2')!
	assert_token(mut store, a, 'unicode-\u03b1', 'fixture-\u03b2')
	store.close()!
	mut set_closed := false
	store.set_auth_token(a, 'scope', none) or { set_closed = true }
	assert set_closed
	mut peek_closed := false
	store.auth_token(a, 'scope') or { peek_closed = true }
	assert peek_closed
	mut invalidate_closed := false
	store.invalidate_auth_token(token_kind, 'fixture') or { invalidate_closed = true }
	assert invalidate_closed
}

fn test_explicit_token_entry_and_byte_limits_preserve_previous_transaction() {
	path := token_fixture('limits')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), token_owner, token_kind)!
	defer { store.close() or { panic(err) } }
	a := token_account('entries')
	b := token_account('bytes')
	assert store.add(a, none, {}, {})!
	assert store.add(b, none, {}, {})!
	for i in 0 .. max_entries { store.set_auth_token(a, 'scope${i}', 'fixture')! }
	mut entries_rejected := false
	store.set_auth_token(a, 'overflow', 'fixture') or { entries_rejected = true }
	assert entries_rejected
	assert_token(mut store, a, 'overflow', none)
	store.set_auth_token(a, 'scope0', 'fixture-updated')!
	store.set_auth_token(a, 'scope1', none)!
	store.set_auth_token(a, 'replacement', 'fixture')!
	assert_token(mut store, a, 'scope0', 'fixture-updated')
	long_type := 't'.repeat(max_token_scalar - 1)
	long_value := 'v'.repeat(max_token_scalar)
	for i in 0 .. 8 { store.set_auth_token(b, long_type + i.str(), long_value)! }
	mut bytes_rejected := false
	store.set_auth_token(b, 'overflow', '') or { bytes_rejected = true }
	assert bytes_rejected
	assert token_row_count(store, 'SELECT count(*) FROM authtokens') == max_entries + 8
	store.set_auth_token(b, long_type + '0', long_value)!
	store.set_auth_token(b, long_type + '1', none)!
	store.set_auth_token(b, 'replacement', '')!
	assert_token(mut store, b, 'replacement', '')
}

fn test_explicit_token_failed_sqlite_writes_and_invalidations_roll_back() {
	path := token_fixture('rollback')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), token_owner, token_kind)!
	defer { store.close() or { panic(err) } }
	a := token_account('first')
	b := token_account('second')
	assert store.add(a, none, {}, {})!
	assert store.add(b, none, {}, {})!
	store.set_auth_token(a, 'scope', 'fixture-shared')!
	store.set_auth_token(b, 'scope', 'fixture-shared')!
	execute(store.db, "CREATE TRIGGER reject_token_insert BEFORE INSERT ON authtokens BEGIN SELECT RAISE(ABORT,'fixture'); END")!
	mut insert_rejected := false
	store.set_auth_token(a, 'scope', 'fixture-new') or { insert_rejected = true }
	assert insert_rejected
	assert_token(mut store, a, 'scope', 'fixture-shared')
	execute(store.db, 'DROP TRIGGER reject_token_insert')!
	execute(store.db, "CREATE TRIGGER reject_token_delete BEFORE DELETE ON authtokens WHEN OLD.account=(SELECT id FROM accounts WHERE name='second') BEGIN SELECT RAISE(ABORT,'fixture'); END")!
	mut invalidate_rejected := false
	store.invalidate_auth_token(token_kind, 'fixture-shared') or { invalidate_rejected = true }
	assert invalidate_rejected
	assert_token(mut store, a, 'scope', 'fixture-shared')
	assert_token(mut store, b, 'scope', 'fixture-shared')
	mut delete_rejected := false
	store.set_auth_token(b, 'scope', none) or { delete_rejected = true }
	assert delete_rejected
	assert_token(mut store, b, 'scope', 'fixture-shared')
	execute(store.db, 'DROP TRIGGER reject_token_delete')!
	store.invalidate_auth_token(token_kind, 'fixture-shared')!
	assert token_row_count(store, 'SELECT count(*) FROM authtokens') == 0
	store.set_auth_token(a, 'scope', 'fixture-after-rollback')!
	assert_token(mut store, a, 'scope', 'fixture-after-rollback')
}

fn test_password_changes_clear_only_account_tokens_in_the_same_transaction() {
	path := token_fixture('password')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), token_owner, token_kind)!
	defer { store.close() or { panic(err) } }
	a := token_account('first')
	b := token_account('second')
	assert store.add(a, 'fixture-old-password', {}, {})!
	assert store.add(b, none, {}, {})!
	store.set_auth_token(a, 'one', 'fixture-one')!
	store.set_auth_token(a, 'two', 'fixture-two')!
	store.set_auth_token(b, 'one', 'fixture-other-account')!
	execute(store.db, "CREATE TRIGGER reject_password_token_purge BEFORE DELETE ON authtokens BEGIN SELECT RAISE(ABORT,'fixture'); END")!
	mut rejected := false
	store.set_password(a, 'fixture-new-password') or { rejected = true }
	assert rejected
	password := store.password(a)!
	password_matches := password.value == ?string('fixture-old-password')
	assert password_matches
	dispose_nullable(password)
	assert_token(mut store, a, 'one', 'fixture-one')
	assert_token(mut store, a, 'two', 'fixture-two')
	execute(store.db, 'DROP TRIGGER reject_password_token_purge')!
	store.set_password(a, 'fixture-new-password')!
	assert_token(mut store, a, 'one', none)
	assert_token(mut store, a, 'two', none)
	assert_token(mut store, b, 'one', 'fixture-other-account')
	store.set_auth_token(a, 'one', 'fixture-new')!
	store.set_password(a, none)!
	assert_token(mut store, a, 'one', none)
	assert_token(mut store, b, 'one', 'fixture-other-account')
}
