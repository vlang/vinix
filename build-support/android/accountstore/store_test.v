// SPDX-License-Identifier: GPL-2.0-or-later
module accountstore

import os

#include <fcntl.h>
#include <sys/wait.h>

fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int

struct C.flock {
mut:
	l_type i16
	l_whence i16
	l_start i64
	l_len i64
	l_pid i32
}

@[c: 'waitpid']
fn C.vinix_accountstore_waitpid(i32, &i32, i32) i32

fn has_parent_lock(fd int) bool {
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(pipe[0])
		mut query := C.flock{ l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1 }
		mut answer := u8(0)
		if unsafe { C.fcntl(i32(fd), C.F_GETLK, &query) } == 0 && query.l_type != i16(C.F_UNLCK) {
			answer = 1
		}
		unsafe { C.write(pipe[1], &answer, 1) }
		C._exit(0)
		return false
	}
	C.close(pipe[1])
	mut answer := u8(0)
	count := unsafe { C.read(pipe[0], &answer, 1) }
	C.close(pipe[0])
	mut status := i32(-1)
	assert unsafe { C.vinix_accountstore_waitpid(pid, &status, 0) } == pid
	assert count == 1 && status == 0
	return answer == 1
}

const owner = 'com.google.android.gms'
const maps = 'com.google.android.apps.maps'
const kind = 'com.google'

fn fixture(label string) string {
	// /tmp can be a symlink or world-writable; the production path validator
	// deliberately rejects those ancestors instead of relaxing its boundary.
	path := os.join_path(os.home_dir(), '.local', 'state', 'vinix', 'android', 'accountstore-test-${os.getpid()}-${label}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path, mode: 0o700) or { panic(err) }
	os.chmod(path, 0o700) or { panic(err) }
	return path
}

fn account(name string) Account { return Account{name, kind} }

fn snapshot(mut store Store, package_name string) []Account {
	return store.accounts(none, package_name) or { panic(err) }
}

fn test_real_sqlite_insert_reopen_visibility_and_duplicate_preservation() {
	path := fixture('persistence')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	name := "test');DROP TABLE accounts;--@example.test"
	assert store.add(account(name), 'original-password', {
		'gaia':     ?string('one')
		'nullable': ?string(none)
	}, {
		maps:                 2
		'com.example.hidden': 4
	})!
	assert !store.add(account(name), 'replacement-password', {
		'gaia': ?string('two')
	}, {
		'com.example.hidden': 1
	})!
	mut original := snapshot(mut store, maps)
	assert original == [account(name)]
	dispose_accounts(original)
	assert (store.user_data(account(name), 'gaia')!).value == ?string('one')
	assert (store.user_data(account(name), 'nullable')!).value == none
	statement := prepare(store.db, 'SELECT password FROM accounts')!
	assert C.sqlite3_step(statement) == C.SQLITE_ROW
	password := column_text(statement, 0, max_payload)!
	assert password == 'original-password'
	unsafe { password.free() }
	C.sqlite3_finalize(statement)
	store.close()!
	mut reopened := open(path, u32(os.geteuid()), owner, kind)!
	defer { reopened.close() or { panic(err) } }
	for package_name, count in {
		owner:                 1
		maps:                  1
		'com.example.hidden':  0
		'com.example.unknown': 0
	} {
		values := snapshot(mut reopened, package_name)
		assert values.len == count
		dispose_accounts(values)
	}
	values := reopened.accounts('unrelated.type', owner)!
	assert values.len == 0
	dispose_accounts(values)
	assert (reopened.user_data(account(name), 'gaia')!).value == ?string('one')
}

fn test_userdata_and_visibility_changes_are_durable_and_missing_accounts_are_distinct() {
	path := fixture('metadata')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	assert store.add(account('a@example.test'), none, map[string]?string{}, map[string]int{})!
	store.set_user_data(account('a@example.test'), 'empty', '')!
	store.set_user_data(account('a@example.test'), 'key', 'value')!
	assert (store.user_data(account('a@example.test'), 'empty')!).value == ?string('')
	store.set_user_data(account('a@example.test'), 'key', none)!
	assert (store.user_data(account('a@example.test'), 'key')!).value == none
	assert !store.set_visibility(account('missing@example.test'), maps, 2)!
	mut missing := false
	store.set_user_data(account('missing@example.test'), 'key', 'value') or { missing = true }
	assert missing
	assert store.set_visibility(account('a@example.test'), maps, 2)!
	values := snapshot(mut store, maps)
	assert values.len == 1
	dispose_accounts(values)
	assert store.set_visibility(account('a@example.test'), maps, 3)!
	store.close()!
	mut reopened := open(path, u32(os.geteuid()), owner, kind)!
	defer { reopened.close() or { panic(err) } }
	hidden := snapshot(mut reopened, maps)
	assert hidden.len == 0
	dispose_accounts(hidden)
	assert (reopened.user_data(account('a@example.test'), 'empty')!).value == ?string('')
	assert (reopened.user_data(account('a@example.test'), 'key')!).value == none
}

fn test_password_updates_persist_with_distinct_null_and_empty_and_owned_results() {
	path := fixture('password')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	assert store.add(account('a'), 'original', {}, {})!
	old := store.password(account('a'))!
	defer { dispose_nullable(old) }
	store.set_password(account('a'), 'changed')!
	assert old.value == ?string('original')
	mut rejected := false
	store.set_password(account('a'), 'x'.repeat(max_payload + 1)) or { rejected = true }
	assert rejected
	current := store.password(account('a'))!
	assert current.value == ?string('changed')
	dispose_nullable(current)
	store.close()!
	assert old.value == ?string('original')
	mut reopened := open(path, u32(os.geteuid()), owner, kind)!
	defer { reopened.close() or {} }
	persisted := reopened.password(account('a'))!
	assert persisted.value == ?string('changed')
	dispose_nullable(persisted)
	reopened.set_password(account('a'), '')!
	empty := reopened.password(account('a'))!
	assert empty.value == ?string('')
	dispose_nullable(empty)
	reopened.set_password(account('a'), none)!
	assert (reopened.password(account('a'))!).value == none
	mut missing := false
	reopened.set_password(account('missing'), 'value') or { missing = true }
	assert missing
	mut wrong_type := false
	reopened.password(Account{'a', 'untrusted.type'}) or { wrong_type = true }
	assert wrong_type
}

fn test_failed_sqlite_transaction_rolls_back_account_and_metadata_together() {
	path := fixture('rollback')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	defer { store.close() or { panic(err) } }
	execute(store.db, "CREATE TRIGGER reject_visibility BEFORE INSERT ON visibility BEGIN SELECT RAISE(ABORT,'fixture'); END")!
	mut failed := false
	store.add(account('rollback@example.test'), 'password', {
		'gaia': ?string('value')
	}, {
		maps: 2
	}) or { failed = true }
	assert failed
	values := snapshot(mut store, owner)
	assert values.len == 0
	dispose_accounts(values)
	execute(store.db, 'DROP TRIGGER reject_visibility')!
	assert store.add(account('rollback@example.test'), 'password', {
		'gaia': ?string('value')
	}, {
		maps: 2
	})!
}

fn test_wrong_type_and_invalid_input_never_create_account() {
	path := fixture('authority')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	defer { store.close() or { panic(err) } }
	for value in [Account{'a', 'other.type'}, Account{'', kind}, Account{'\xff', kind},
		Account{'x'.repeat(1025), kind}] {
		mut rejected := false
		store.add(value, none, map[string]?string{}, map[string]int{}) or { rejected = true }
		assert rejected
	}
	for visibility in [0, 5, -1] {
		mut rejected := false
		store.add(account('a'), none, map[string]?string{}, {
			maps: visibility
		}) or { rejected = true }
		assert rejected
	}
	mut invalid_package := false
	store.add(account('a'), none, map[string]?string{}, {
		'forged/package': 2
	}) or { invalid_package = true }
	assert invalid_package
	values := snapshot(mut store, owner)
	assert values.len == 0
	dispose_accounts(values)
}

fn test_bounded_metadata_updates_preserve_previous_transaction() {
	path := fixture('bounds')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	defer { store.close() or { panic(err) } }
	mut metadata := map[string]?string{}
	for i in 0 .. max_entries { metadata['key${i}'] = 'value' }
	assert store.add(account('a'), none, metadata, map[string]int{})!
	mut rejected := false
	store.set_user_data(account('a'), 'overflow', 'value') or { rejected = true }
	assert rejected
	assert (store.user_data(account('a'), 'overflow')!).value == none
	store.set_user_data(account('a'), 'key0', 'updated')!
	assert (store.user_data(account('a'), 'key0')!).value == ?string('updated')
	store.set_user_data(account('a'), 'key1', none)!
	store.set_user_data(account('a'), 'replacement', 'value')!
	mut oversized := false
	store.set_user_data(account('a'), 'key0', 'x'.repeat(max_payload)) or { oversized = true }
	assert oversized
	assert (store.user_data(account('a'), 'key0')!).value == ?string('updated')
}

fn test_store_authority_is_pinned_across_reopen_and_closed_operations_fail() {
	path := fixture('identity')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	store.close()!
	store.close()!
	mut closed := false
	store.accounts(none, owner) or { closed = true }
	assert closed
	for pair in [[owner, 'other.type'], ['com.example.other', kind]] {
		mut rejected := false
		open(path, u32(os.geteuid()), pair[0], pair[1]) or { rejected = true }
		assert rejected
	}
	mut wrong_uid := false
	open(path, u32(os.geteuid()) + 1, owner, kind) or { wrong_uid = true }
	assert wrong_uid
}

fn test_final_disposal_releases_store_after_owned_results_escape() {
	path := fixture('dispose')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	assert store.add(account('retained'), 'password', {}, {})!
	values := store.accounts(none, owner)!
	password := store.password(account('retained'))!
	store.close()!
	dispose(mut store)!
	assert values.len == 1 && values[0].name == 'retained'
	assert password.value == ?string('password')
	dispose_nullable(password)
	dispose_accounts(values)
}

fn test_directory_symlinks_and_nonprivate_data_are_rejected() {
	path := fixture('directories')
	defer { os.rmdir_all(path) or {} }
	os.mkdir(path + '/real', mode: 0o700)!
	os.symlink(path + '/real', path + '/link')!
	mut linked := false
	open(path + '/link', u32(os.geteuid()), owner, kind) or { linked = true }
	assert linked
	os.chmod(path + '/real', 0o755)!
	mut public_data := false
	open(path + '/real', u32(os.geteuid()), owner, kind) or { public_data = true }
	assert public_data
	os.chmod(path + '/real', 0o700)!
	os.symlink(path + '/real', path + '/accounts')!
	mut linked_store := false
	open(path, u32(os.geteuid()), owner, kind) or { linked_store = true }
	assert linked_store
}

fn test_database_symlink_hardlink_fifo_and_modes_are_rejected_without_touching_target() {
	for attack in ['symlink', 'hardlink', 'fifo', 'mode'] {
		path := fixture('file-${attack}')
		os.mkdir(path + '/accounts', mode: 0o700)!
		target := path + '/target'
		file := path + '/accounts/accounts.sqlite'
		os.write_file(target, 'unchanged')!
		os.chmod(target, 0o600)!
		match attack {
			'symlink' { os.symlink(target, file)! }
			'hardlink' {
				assert unsafe { C.link(target.str, file.str) } == 0
			}
			'fifo' {
				assert unsafe { C.mkfifo(file.str, u32(0o600)) } == 0
			}
			else {
				os.write_file(file, '')!
				os.chmod(file, 0o666)!
			}
		}
		mut rejected := false
		open(path, u32(os.geteuid()), owner, kind) or { rejected = true }
		assert rejected, attack
		assert os.read_file(target)! == 'unchanged'
		os.rmdir_all(path)!
	}
}

fn test_unsafe_journal_and_corrupt_database_fail_instead_of_returning_empty_snapshot() {
	path := fixture('journal')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	store.close()!
	os.write_file(path + '/target', 'unchanged')!
	os.symlink(path + '/target', path + '/accounts/accounts.sqlite-journal')!
	mut rejected := false
	open(path, u32(os.geteuid()), owner, kind) or { rejected = true }
	assert rejected
	assert os.read_file(path + '/target')! == 'unchanged'
	os.rm(path + '/accounts/accounts.sqlite-journal')!
	os.write_file(path + '/accounts/accounts.sqlite', 'not a SQLite database')!
	mut corrupt := false
	open(path, u32(os.geteuid()), owner, kind) or { corrupt = true }
	assert corrupt
}

fn test_metadata_validation_does_not_drop_an_existing_sqlite_kernel_lock() {
	path := fixture('kernel-lock')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path, u32(os.geteuid()), owner, kind)!
	defer { dispose(mut store) or { panic(err) } }
	file := os.join_path(path, 'accounts', 'accounts.sqlite')
	fd := unsafe { C.open(file.str, C.O_RDWR | C.O_CLOEXEC | C.O_NOFOLLOW) }
	assert fd >= 0
	defer { C.close(fd) }
	execute(store.db, 'BEGIN IMMEDIATE')!
	// Pin an ordinary POSIX lock on byte zero: some host SQLite builds use
	// a different lock style. Closing any same-inode descriptor must preserve
	// this lock too. SQLite's own lock bytes are above the first GiB.
	mut guard := C.flock{ l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1 }
	assert unsafe { C.fcntl(i32(fd), C.F_SETLK, &guard) } == 0
	assert has_parent_lock(fd)
	check_file(store.directory, 'accounts.sqlite', u32(os.geteuid()), true)!
	assert has_parent_lock(fd)
	execute(store.db, 'ROLLBACK')!
	guard.l_type = i16(C.F_UNLCK)
	assert unsafe { C.fcntl(i32(fd), C.F_SETLK, &guard) } == 0
	assert !has_parent_lock(fd)
}
