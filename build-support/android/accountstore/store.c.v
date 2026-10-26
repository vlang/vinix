// SPDX-License-Identifier: GPL-2.0-or-later
// The selected authenticator owns this store. Callers and the allowed type are
// supplied by the authenticated service adapter, never by application options.
module accountstore

import encoding.utf8
import os
import sync

#flag -lsqlite3
#include <sqlite3.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

struct C.sqlite3 {}
struct C.sqlite3_stmt {}

fn C.open(&char, int, ...voidptr) int
fn C.openat(int, &char, int, ...voidptr) int
fn C.close(int) int
fn C.mkdirat(int, &char, u32) int
fn C.fstat(int, &C.stat) int
fn C.fsync(int) int
@[c: 'fstatat']
fn C.vinix_accountstore_fstatat(int, &char, &C.stat, int) int
fn C.sqlite3_open_v2(&char, &&C.sqlite3, int, &char) int
fn C.sqlite3_close(voidptr) int
fn C.sqlite3_busy_timeout(voidptr, int) int
fn C.sqlite3_prepare_v2(voidptr, &char, int, &&C.sqlite3_stmt, voidptr) int
fn C.sqlite3_finalize(voidptr) int
fn C.sqlite3_bind_text(voidptr, int, &char, int, voidptr) int
fn C.sqlite3_bind_null(voidptr, int) int
fn C.sqlite3_bind_int(voidptr, int, int) int
fn C.sqlite3_bind_int64(voidptr, int, i64) int
fn C.sqlite3_step(voidptr) int
fn C.sqlite3_column_text(voidptr, int) &u8
fn C.sqlite3_column_bytes(voidptr, int) int
fn C.sqlite3_column_int64(voidptr, int) i64
fn C.sqlite3_column_type(voidptr, int) int

const max_accounts = 64
const max_entries = 64
const max_payload = 64 * 1024

pub struct Account {
pub:
	name         string
	account_type string
}

pub struct NullableString {
pub:
	value ?string
}

@[heap]
pub struct Store {
	owner_package string
	allowed_type  string
	directory     int
mut:
	mutex sync.Mutex
	db    voidptr
}

fn valid_text(value string, limit int, empty bool) bool {
	return (empty || value.len > 0) && value.len <= limit && !value.contains('\x00')
		&& utf8.validate_str(value)
}

fn valid_package(value string) bool {
	if value.len == 0 || value.len > 255 { return false }
	mut first := true
	mut separator := false
	for byte in value {
		if byte == `.` {
			if first { return false }
			first = true
			separator = true
		} else {
			if first && !(byte.is_letter() || byte == `_`) { return false }
			if !byte.is_alnum() && byte != `_` { return false }
			first = false
		}
	}
	return separator && !first
}

fn directory_info(fd int, uid u32, private bool) ! {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFDIR)
		|| (info.st_uid != 0 && info.st_uid != uid) || u32(info.st_mode) & 0o022 != 0
		|| (private && (info.st_uid != uid || u32(info.st_mode) & 0o777 != 0o700)) {
		return error('account store directory ownership or mode is unsafe')
	}
}

fn open_data_directory(path string, uid u32) !int {
	if uid != u32(os.geteuid()) || path.len < 2 || path.len > 4096 || !path.starts_with('/')
		|| path.ends_with('/') || path.contains('\x00') || path.contains('\\') {
		return error('account store requires its current UID and canonical absolute directory')
	}
	parts := path.split('/')
	defer {
		unsafe { parts.free() }
	}
	for i in 1 .. parts.len {
		if parts[i] == '' || parts[i] == '.' || parts[i] == '..' {
			return error('account store directory path is not canonical')
		}
	}
	mut fd := unsafe { C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
	if fd < 0 { return error('cannot open account store filesystem root') }
	for i in 1 .. parts.len {
		part := parts[i]
		directory_info(fd, uid, false) or {
			C.close(fd)
			return err
		}
		next := unsafe { C.openat(fd, part.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
		C.close(fd)
		if next < 0 { return error('cannot open account store directory without following links') }
		fd = next
		directory_info(fd, uid, i == parts.len - 1) or {
			C.close(fd)
			return err
		}
	}
	return fd
}

fn database_path(data_directory string) string {
	// SQLite's NOFOLLOW rejects symlinks in every pathname component, including
	// the intentional /proc/self/fd directory links. Keep its complete-path
	// protection by using the canonical path whose ancestors were opened without
	// following links and checked for trusted ownership and no group/world write.
	// Only trusted root or this selected authenticator's UID can rename them.
	return data_directory + '/accounts/accounts.sqlite'
}

fn check_file(directory int, name string, uid u32, create bool) ! {
	mut info := C.stat{}
	// Opening and closing an existing inode can release another SQLite
	// connection's process-owned POSIX locks. Inspect without opening it.
	if unsafe { C.vinix_accountstore_fstatat(directory, name.str, &info, C.AT_SYMLINK_NOFOLLOW) } != 0 {
		if C.errno != C.ENOENT { return error('cannot inspect private account store file') }
		if !create { return }
		fd := unsafe { C.openat(directory, name.str, C.O_RDWR | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CREAT | C.O_EXCL, u32(0o600)) }
		if fd < 0 { return error('cannot create private account store file') }
		status := C.fstat(fd, unsafe { &info })
		C.close(fd)
		if status != 0 { return error('cannot inspect new account store file') }
	}
	if u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_uid != uid || u32(info.st_mode) & 0o777 != 0o600 || info.st_nlink != 1 {
		return error('account store file ownership, mode or link count is unsafe')
	}
}

fn prepare(db voidptr, query string) !voidptr {
	mut statement := &C.sqlite3_stmt(unsafe { nil })
	if unsafe { C.sqlite3_prepare_v2(db, query.str, query.len, &statement, nil) } != C.SQLITE_OK {
		if statement != unsafe { nil } { C.sqlite3_finalize(statement) }
		return error('cannot prepare account store operation')
	}
	return statement
}

fn execute(db voidptr, query string) ! {
	statement := prepare(db, query)!
	defer { C.sqlite3_finalize(statement) }
	if C.sqlite3_step(statement) != C.SQLITE_DONE { return error('account store operation failed') }
}

fn bind_text(statement voidptr, index int, value string) ! {
	// Inputs remain rooted until the statement is finalized (SQLITE_STATIC).
	if unsafe { C.sqlite3_bind_text(statement, index, value.str, value.len, nil) } != C.SQLITE_OK {
		return error('cannot bind account store text')
	}
}

fn bind_nullable(statement voidptr, index int, value ?string) ! {
	if text := value {
		bind_text(statement, index, text)!
	} else if C.sqlite3_bind_null(statement, index) != C.SQLITE_OK {
		return error('cannot bind account store null')
	}
}

fn column_text(statement voidptr, index int, limit int) !string {
	length := C.sqlite3_column_bytes(statement, index)
	data := C.sqlite3_column_text(statement, index)
	if length < 0 || length > limit || data == unsafe { nil } {
		return error('account store contains invalid text')
	}
	value := unsafe { data.vstring_with_len(length).clone() }
	if !valid_text(value, limit, true) {
		unsafe { value.free() }
		return error('account store contains invalid UTF-8 text')
	}
	return value
}

fn identity(db voidptr, owner string, account_type string) ! {
	execute(db, 'CREATE TABLE IF NOT EXISTS authority (id INTEGER PRIMARY KEY CHECK(id=1), owner TEXT NOT NULL, type TEXT NOT NULL)')!
	query := prepare(db, 'SELECT owner,type FROM authority WHERE id=1')!
	defer { C.sqlite3_finalize(query) }
	status := C.sqlite3_step(query)
	if status == C.SQLITE_ROW {
		stored_owner := column_text(query, 0, 255)!
		defer { unsafe { stored_owner.free() } }
		stored_type := column_text(query, 1, 255)!
		defer { unsafe { stored_type.free() } }
		if stored_owner != owner || stored_type != account_type {
			return error('account store authority does not match the selected authenticator')
		}
		return
	}
	if status != C.SQLITE_DONE { return error('cannot read account store authority') }
	insert := prepare(db, 'INSERT INTO authority(id,owner,type) VALUES(1,?,?)')!
	defer { C.sqlite3_finalize(insert) }
	bind_text(insert, 1, owner)!
	bind_text(insert, 2, account_type)!
	if C.sqlite3_step(insert) != C.SQLITE_DONE {
		return error('cannot pin account store authority')
	}
}

// The caller must already have authenticated the selected service and pinned
// its metadata. UID ownership is an additional filesystem boundary.
pub fn open(data_directory string, expected_uid u32, owner_package string, allowed_type string) !&Store {
	if !valid_package(owner_package) || !valid_text(allowed_type, 255, false) {
		return error('account store authority is invalid')
	}
	parent := open_data_directory(data_directory, expected_uid)!
	defer { C.close(parent) }
	if unsafe { C.mkdirat(parent, c'accounts', u32(0o700)) } != 0 && C.errno != C.EEXIST {
		return error('cannot create private account store directory')
	}
	directory := unsafe { C.openat(parent, c'accounts', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
	if directory < 0 { return error('cannot open private account store directory') }
	mut ready := false
	defer { if !ready { C.close(directory) } }
	directory_info(directory, expected_uid, true)!
	check_file(directory, 'accounts.sqlite', expected_uid, true)!
	for name in ['accounts.sqlite-journal', 'accounts.sqlite-wal', 'accounts.sqlite-shm']! {
		check_file(directory, name, expected_uid, false)!
	}
	path := database_path(data_directory)
	defer { unsafe { path.free() } }
	mut db := &C.sqlite3(unsafe { nil })
	status := unsafe { C.sqlite3_open_v2(path.str, &db, C.SQLITE_OPEN_READWRITE | C.SQLITE_OPEN_FULLMUTEX | C.SQLITE_OPEN_NOFOLLOW, nil) }
	if status != C.SQLITE_OK {
		if db != unsafe { nil } { C.sqlite3_close(db) }
		return error('cannot open authoritative account database')
	}
	mut initialized := false
	defer { if !initialized { C.sqlite3_close(db) } }
	if C.sqlite3_busy_timeout(db, 1000) != C.SQLITE_OK {
		return error('cannot configure account database timeout')
	}
	execute(db, 'PRAGMA trusted_schema=OFF')!
	execute(db, 'PRAGMA foreign_keys=ON')!
	// DELETE avoids a second persistent WAL authority; all commits use FULL
	// synchronization and SQLite recovery in the same private directory.
	mode := prepare(db, 'PRAGMA journal_mode=DELETE')!
	if C.sqlite3_step(mode) != C.SQLITE_ROW {
		C.sqlite3_finalize(mode)
		return error('cannot configure account database journal')
	}
	journal_mode := column_text(mode, 0, 16) or {
		C.sqlite3_finalize(mode)
		return err
	}
	C.sqlite3_finalize(mode)
	valid_journal := journal_mode == 'delete'
	unsafe { journal_mode.free() }
	if !valid_journal { return error('account database requires DELETE journal mode') }
	execute(db, 'PRAGMA synchronous=FULL')!
	execute(db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { execute(db, 'ROLLBACK') or {} } }
	identity(db, owner_package, allowed_type)!
	execute(db, 'CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, password TEXT, UNIQUE(name,type))')!
	execute(db, 'CREATE TABLE IF NOT EXISTS userdata (account INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(account,key))')!
	execute(db, 'CREATE TABLE IF NOT EXISTS visibility (account INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, package TEXT NOT NULL, value INTEGER NOT NULL CHECK(value BETWEEN 1 AND 4), PRIMARY KEY(account,package))')!
	// An additive migration preserves stores created before explicit token APIs.
	execute(db, 'CREATE TABLE IF NOT EXISTS authtokens (account INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, token_type TEXT NOT NULL, token TEXT NOT NULL, PRIMARY KEY(account,token_type))')!
	execute(db, 'COMMIT')!
	committed = true
	if C.fsync(directory) != 0 || C.fsync(parent) != 0 {
		return error('cannot synchronize account store directory')
	}
	initialized = true
	ready = true
	return &Store{ owner_package: owner_package.clone(), allowed_type: allowed_type.clone(), directory: directory, db: db }
}

fn (s &Store) check_account(account Account) ! {
	if account.account_type != s.allowed_type || !valid_text(account.name, 1024, false) {
		return error('account does not belong to the selected authenticator')
	}
}

fn (s &Store) require_open() ! {
	if s.db == unsafe { nil } { return error('account store is closed') }
}

fn (s &Store) account_id(account Account) !i64 {
	s.check_account(account)!
	statement := prepare(s.db, 'SELECT id FROM accounts WHERE name=? AND type=?')!
	defer { C.sqlite3_finalize(statement) }
	bind_text(statement, 1, account.name)!
	bind_text(statement, 2, account.account_type)!
	if C.sqlite3_step(statement) != C.SQLITE_ROW {
		return error('account is absent from the authoritative store')
	}
	return C.sqlite3_column_int64(statement, 0)
}

pub fn (mut s Store) add(account Account, password ?string, userdata map[string]?string, visibility map[string]int) !bool {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	s.check_account(account)!
	mut size := account.name.len + account.account_type.len
	if text := password {
		if !valid_text(text, max_payload, true) { return error('account password is invalid') }
		size += text.len
	}
	if userdata.len > max_entries || visibility.len > max_entries {
		return error('account metadata entry limit exceeded')
	}
	for key, value in userdata {
		if !valid_text(key, 4096, false) { return error('account metadata key is invalid') }
		size += key.len
		if text := value {
			if !valid_text(text, max_payload, true) {
				return error('account metadata value is invalid')
			}
			size += text.len
		}
	}
	for package, value in visibility {
		if !valid_package(package) || value < 1 || value > 4 {
			return error('account visibility is invalid')
		}
		size += package.len
	}
	if size > max_payload { return error('account metadata size limit exceeded') }
	execute(s.db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { execute(s.db, 'ROLLBACK') or {} } }
	count := prepare(s.db, 'SELECT count(*) FROM accounts')!
	if C.sqlite3_step(count) != C.SQLITE_ROW {
		C.sqlite3_finalize(count)
		return error('cannot count authoritative accounts')
	}
	n := C.sqlite3_column_int64(count, 0)
	C.sqlite3_finalize(count)
	// Test duplicates before the count limit: an existing account is false,
	// including when the store has reached its bounded capacity.
	query := prepare(s.db, 'SELECT id FROM accounts WHERE name=? AND type=?')!
	bind_text(query, 1, account.name) or {
		C.sqlite3_finalize(query)
		return err
	}
	bind_text(query, 2, account.account_type) or {
		C.sqlite3_finalize(query)
		return err
	}
	status := C.sqlite3_step(query)
	C.sqlite3_finalize(query)
	if status == C.SQLITE_ROW { return false }
	if status != C.SQLITE_DONE { return error('cannot check duplicate account') }
	if n >= max_accounts { return error('account store capacity exceeded') }
	insert := prepare(s.db, 'INSERT INTO accounts(name,type,password) VALUES(?,?,?)')!
	bind_text(insert, 1, account.name) or {
		C.sqlite3_finalize(insert)
		return err
	}
	bind_text(insert, 2, account.account_type) or {
		C.sqlite3_finalize(insert)
		return err
	}
	bind_nullable(insert, 3, password) or {
		C.sqlite3_finalize(insert)
		return err
	}
	inserted := C.sqlite3_step(insert)
	C.sqlite3_finalize(insert)
	if inserted != C.SQLITE_DONE { return error('cannot insert authoritative account') }
	id := s.account_id(account)!
	for key, value in userdata {
		if text := value { write_data(s.db, id, key, text)! }
	}
	for package, value in visibility {
		statement := prepare(s.db, 'INSERT INTO visibility(account,package,value) VALUES(?,?,?)')!
		if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
			C.sqlite3_finalize(statement)
			return error('cannot bind account identity')
		}
		bind_text(statement, 2, package) or {
			C.sqlite3_finalize(statement)
			return err
		}
		if C.sqlite3_bind_int(statement, 3, value) != C.SQLITE_OK {
			C.sqlite3_finalize(statement)
			return error('cannot bind account visibility')
		}
		result := C.sqlite3_step(statement)
		C.sqlite3_finalize(statement)
		if result != C.SQLITE_DONE { return error('cannot store account visibility') }
	}
	execute(s.db, 'COMMIT')!
	committed = true
	return true
}

// caller_package must come from the broker's authenticated registry identity.
// Absence of an explicit visible policy remains hidden to other packages.
pub fn (mut s Store) accounts(account_type ?string, caller_package string) ![]Account {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	if !valid_package(caller_package) { return error('account query caller is invalid') }
	if kind := account_type {
		if !valid_text(kind, 255, false) { return error('account query type is invalid') }
		if kind != s.allowed_type { return []Account{} }
	}
	query := if caller_package == s.owner_package {
		'SELECT name,type FROM accounts WHERE type=? ORDER BY id'
	} else {
		'SELECT a.name,a.type FROM accounts a JOIN visibility v ON v.account=a.id WHERE a.type=? AND v.package=? AND v.value IN (1,2) ORDER BY a.id'
	}
	statement := prepare(s.db, query)!
	defer { C.sqlite3_finalize(statement) }
	bind_text(statement, 1, s.allowed_type)!
	if caller_package != s.owner_package { bind_text(statement, 2, caller_package)! }
	mut output := []Account{cap: max_accounts}
	mut complete := false
	defer { if !complete { dispose_accounts(output) } }
	for {
		status := C.sqlite3_step(statement)
		if status == C.SQLITE_DONE { break }
		if status != C.SQLITE_ROW || output.len >= max_accounts {
			return error('cannot read bounded account snapshot')
		}
		name := column_text(statement, 0, 1024)!
		stored_type := column_text(statement, 1, 255) or {
			unsafe { name.free() }
			return err
		}
		if name.len == 0 || stored_type != s.allowed_type {
			unsafe {
				name.free()
				stored_type.free()
			}
			return error('account store contains an invalid account')
		}
		output << Account{name, stored_type}
	}
	complete = true
	return output
}

fn write_data(db voidptr, id i64, key string, value string) ! {
	statement := prepare(db, 'INSERT OR REPLACE INTO userdata(account,key,value) VALUES(?,?,?)')!
	defer { C.sqlite3_finalize(statement) }
	if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
		return error('cannot bind account identity')
	}
	bind_text(statement, 2, key)!
	bind_text(statement, 3, value)!
	if C.sqlite3_step(statement) != C.SQLITE_DONE { return error('cannot store account metadata') }
}

// Values are owned clones; release a successful result with dispose_nullable.
pub fn (mut s Store) password(account Account) !NullableString {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	id := s.account_id(account)!
	statement := prepare(s.db, 'SELECT password FROM accounts WHERE id=?')!
	defer { C.sqlite3_finalize(statement) }
	if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
		return error('cannot bind account identity')
	}
	if C.sqlite3_step(statement) != C.SQLITE_ROW { return error('cannot read account password') }
	if C.sqlite3_column_type(statement, 0) == C.SQLITE_NULL { return NullableString{} }
	return NullableString{ value: column_text(statement, 0, max_payload)! }
}

pub fn (mut s Store) set_password(account Account, value ?string) ! {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	if text := value {
		if !valid_text(text, max_payload, true) { return error('account password is invalid') }
	}
	execute(s.db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { execute(s.db, 'ROLLBACK') or {} } }
	id := s.account_id(account)!
	statement := prepare(s.db, 'UPDATE accounts SET password=? WHERE id=?')!
	bind_nullable(statement, 1, value) or {
		C.sqlite3_finalize(statement)
		return err
	}
	if C.sqlite3_bind_int64(statement, 2, id) != C.SQLITE_OK {
		C.sqlite3_finalize(statement)
		return error('cannot bind account identity')
	}
	status := C.sqlite3_step(statement)
	C.sqlite3_finalize(statement)
	if status != C.SQLITE_DONE { return error('cannot store account password') }
	delete_account_tokens(s.db, id)!
	execute(s.db, 'COMMIT')!
	committed = true
}

pub fn (mut s Store) user_data(account Account, key string) !NullableString {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	if !valid_text(key, 4096, false) { return error('account metadata key is invalid') }
	id := s.account_id(account)!
	statement := prepare(s.db, 'SELECT value FROM userdata WHERE account=? AND key=?')!
	defer { C.sqlite3_finalize(statement) }
	if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
		return error('cannot bind account identity')
	}
	bind_text(statement, 2, key)!
	status := C.sqlite3_step(statement)
	if status == C.SQLITE_DONE { return NullableString{} }
	if status != C.SQLITE_ROW { return error('cannot read account metadata') }
	return NullableString{ value: column_text(statement, 0, max_payload)! }
}

pub fn (mut s Store) set_user_data(account Account, key string, value ?string) ! {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	if !valid_text(key, 4096, false) { return error('account metadata key is invalid') }
	if text := value {
		if !valid_text(text, max_payload - key.len, true) {
			return error('account metadata value is invalid')
		}
	}
	execute(s.db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { execute(s.db, 'ROLLBACK') or {} } }
	id := s.account_id(account)!
	if text := value {
		count := prepare(s.db, 'SELECT count(*),coalesce(sum(length(CAST(key AS BLOB))+length(CAST(value AS BLOB))),0) FROM userdata WHERE account=? AND key!=?')!
		if C.sqlite3_bind_int64(count, 1, id) != C.SQLITE_OK {
			C.sqlite3_finalize(count)
			return error('cannot bind account identity')
		}
		bind_text(count, 2, key) or {
			C.sqlite3_finalize(count)
			return err
		}
		if C.sqlite3_step(count) != C.SQLITE_ROW {
			C.sqlite3_finalize(count)
			return error('cannot bound account metadata')
		}
		entries := C.sqlite3_column_int64(count, 0)
		bytes := C.sqlite3_column_int64(count, 1)
		C.sqlite3_finalize(count)
		if entries >= max_entries || bytes + key.len + text.len > max_payload {
			return error('account metadata limit exceeded')
		}
		write_data(s.db, id, key, text)!
	} else {
		statement := prepare(s.db, 'DELETE FROM userdata WHERE account=? AND key=?')!
		if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
			C.sqlite3_finalize(statement)
			return error('cannot bind account identity')
		}
		bind_text(statement, 2, key) or {
			C.sqlite3_finalize(statement)
			return err
		}
		status := C.sqlite3_step(statement)
		C.sqlite3_finalize(statement)
		if status != C.SQLITE_DONE { return error('cannot delete account metadata') }
	}
	execute(s.db, 'COMMIT')!
	committed = true
}

pub fn dispose_accounts(accounts []Account) {
	for account in accounts {
		unsafe {
			account.name.free()
			account.account_type.free()
		}
	}
	unsafe { accounts.free() }
}

pub fn dispose_nullable(value NullableString) {
	if text := value.value { unsafe { text.free() } }
}

pub fn (mut s Store) set_visibility(account Account, package_name string, visibility int) !bool {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	s.check_account(account)!
	if !valid_package(package_name) || visibility < 1 || visibility > 4 {
		return error('account visibility is invalid')
	}
	execute(s.db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { execute(s.db, 'ROLLBACK') or {} } }
	lookup := prepare(s.db, 'SELECT id FROM accounts WHERE name=? AND type=?')!
	bind_text(lookup, 1, account.name) or {
		C.sqlite3_finalize(lookup)
		return err
	}
	bind_text(lookup, 2, account.account_type) or {
		C.sqlite3_finalize(lookup)
		return err
	}
	status := C.sqlite3_step(lookup)
	if status == C.SQLITE_DONE {
		C.sqlite3_finalize(lookup)
		return false
	}
	if status != C.SQLITE_ROW {
		C.sqlite3_finalize(lookup)
		return error('cannot find account for visibility update')
	}
	id := C.sqlite3_column_int64(lookup, 0)
	C.sqlite3_finalize(lookup)
	count := prepare(s.db, 'SELECT count(*) FROM visibility WHERE account=? AND package!=?')!
	if C.sqlite3_bind_int64(count, 1, id) != C.SQLITE_OK {
		C.sqlite3_finalize(count)
		return error('cannot bind account identity')
	}
	bind_text(count, 2, package_name) or {
		C.sqlite3_finalize(count)
		return err
	}
	if C.sqlite3_step(count) != C.SQLITE_ROW {
		C.sqlite3_finalize(count)
		return error('cannot bound account visibility')
	}
	n := C.sqlite3_column_int64(count, 0)
	C.sqlite3_finalize(count)
	if n >= max_entries { return error('account visibility entry limit exceeded') }
	statement := prepare(s.db, 'INSERT OR REPLACE INTO visibility(account,package,value) VALUES(?,?,?)')!
	if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
		C.sqlite3_finalize(statement)
		return error('cannot bind account identity')
	}
	bind_text(statement, 2, package_name) or {
		C.sqlite3_finalize(statement)
		return err
	}
	if C.sqlite3_bind_int(statement, 3, visibility) != C.SQLITE_OK {
		C.sqlite3_finalize(statement)
		return error('cannot bind account visibility')
	}
	result := C.sqlite3_step(statement)
	C.sqlite3_finalize(statement)
	if result != C.SQLITE_DONE { return error('cannot store account visibility') }
	execute(s.db, 'COMMIT')!
	committed = true
	return true
}

pub fn (mut s Store) close() ! {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	if s.db == unsafe { nil } { return }
	if C.sqlite3_close(s.db) != C.SQLITE_OK { return error('cannot close account store') }
	s.db = unsafe { nil }
	C.close(s.directory)
	unsafe {
		s.owner_package.free()
		s.allowed_type.free()
	}
}

// The caller must hold sole ownership: no operation or retained reference may
// use this object after disposal. close() remains separately idempotent.
pub fn dispose(mut store Store) ! {
	store.close()!
	store.mutex.destroy()
	unsafe { free(&store) }
}
