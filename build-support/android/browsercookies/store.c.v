// SPDX-License-Identifier: GPL-2.0-or-later
// The helper owns this snapshot; WebKit remains the cookie policy authority.
// Call replace only with a completed, bounded WebKit cookie enumeration.
module browsercookies

import dl
import encoding.utf8
import os
import sync

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, int, ...voidptr) int
fn C.openat(int, &char, int, ...voidptr) int
fn C.close(int) int
fn C.mkdirat(int, &char, u32) int
fn C.fstat(int, &C.stat) int
fn C.fsync(int) int

@[c: 'fstatat']
fn C.vinix_browsercookies_fstatat(int, &char, &C.stat, int) int

const max_cookies = 4096
const max_field = 64 * 1024
const max_payload = 4 * 1024 * 1024
const sqlite_ok = 0
const sqlite_row = 100
const sqlite_done = 101
const sqlite_integer = 1
const sqlite_text = 3
const sqlite_null = 5

// SQLite's C int is 32 bits, including on V compilers with a 64-bit int.
type Open = fn (&char, &voidptr, i32, &char) i32
type Close = fn (voidptr) i32
type Timeout = fn (voidptr, i32) i32
type Prepare = fn (voidptr, &char, i32, &voidptr, voidptr) i32
type Finalize = fn (voidptr) i32
type BindText = fn (voidptr, i32, &char, i32, voidptr) i32
type BindNull = fn (voidptr, i32) i32
type BindInt64 = fn (voidptr, i32, i64) i32
type Step = fn (voidptr) i32
type ColumnText = fn (voidptr, i32) &u8
type ColumnInt = fn (voidptr, i32) i32
type ColumnInt64 = fn (voidptr, i32) i64

struct Api {
	open_v2      Open        @[required]
	close        Close       @[required]
	busy_timeout Timeout     @[required]
	prepare_v2   Prepare     @[required]
	finalize     Finalize    @[required]
	bind_text    BindText    @[required]
	bind_null    BindNull    @[required]
	bind_int64   BindInt64   @[required]
	step         Step        @[required]
	column_text  ColumnText  @[required]
	column_bytes ColumnInt   @[required]
	column_int64 ColumnInt64 @[required]
	column_type  ColumnInt   @[required]
}

// The builder audits this exact dynamic dependency, with no SQLite headers or
// link library needed by the V compiler or helper executable.
pub fn required_symbols() []string {
	return ['sqlite3_open_v2', 'sqlite3_close', 'sqlite3_busy_timeout', 'sqlite3_prepare_v2',
		'sqlite3_finalize', 'sqlite3_bind_text', 'sqlite3_bind_null', 'sqlite3_bind_int64',
		'sqlite3_step', 'sqlite3_column_text', 'sqlite3_column_bytes', 'sqlite3_column_int64',
		'sqlite3_column_type']
}

fn load_api() !(voidptr, Api) {
	mut library := unsafe { nil }
	$if macos {
		library = dl.open_opt('/usr/lib/libsqlite3.dylib', dl.rtld_now)!
	} $else {
		library = dl.open_opt('libsqlite3.so.0', dl.rtld_now)!
	}
	mut ready := false
	defer { if !ready { dl.close(library) } }
	a := Api{
		open_v2:      unsafe { Open(dl.sym_opt(library, 'sqlite3_open_v2')!) }
		close:        unsafe { Close(dl.sym_opt(library, 'sqlite3_close')!) }
		busy_timeout: unsafe { Timeout(dl.sym_opt(library, 'sqlite3_busy_timeout')!) }
		prepare_v2:   unsafe { Prepare(dl.sym_opt(library, 'sqlite3_prepare_v2')!) }
		finalize:     unsafe { Finalize(dl.sym_opt(library, 'sqlite3_finalize')!) }
		bind_text:    unsafe { BindText(dl.sym_opt(library, 'sqlite3_bind_text')!) }
		bind_null:    unsafe { BindNull(dl.sym_opt(library, 'sqlite3_bind_null')!) }
		bind_int64:   unsafe { BindInt64(dl.sym_opt(library, 'sqlite3_bind_int64')!) }
		step:         unsafe { Step(dl.sym_opt(library, 'sqlite3_step')!) }
		column_text:  unsafe { ColumnText(dl.sym_opt(library, 'sqlite3_column_text')!) }
		column_bytes: unsafe { ColumnInt(dl.sym_opt(library, 'sqlite3_column_bytes')!) }
		column_int64: unsafe { ColumnInt64(dl.sym_opt(library, 'sqlite3_column_int64')!) }
		column_type:  unsafe { ColumnInt(dl.sym_opt(library, 'sqlite3_column_type')!) }
	}
	ready = true
	return library, a
}

pub struct Cookie {
pub:
	name      string
	value     string
	domain    string
	path      string
	expires   ?i64
	secure    bool
	http_only bool
	same_site int
}

@[heap]
pub struct Store {
	api       Api
	library   voidptr
	directory int
	uid       u32
mut:
	mutex sync.Mutex
	db    voidptr
}

fn directory_info(fd int, uid u32, private bool) ! {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFDIR)
		|| (info.st_uid != 0 && info.st_uid != uid) || u32(info.st_mode) & 0o022 != 0
		|| (private && (info.st_uid != uid || u32(info.st_mode) & 0o777 != 0o700)) {
		return error('cookie snapshot directory ownership or mode is unsafe')
	}
}

fn open_data_directory(path string, uid u32) !int {
	if path.len < 2 || path.len > 4096 || !path.starts_with('/') || path.ends_with('/')
		|| path.contains('\x00') || path.contains('\\') {
		return error('cookie snapshot requires a canonical absolute directory')
	}
	parts := path.split('/')
	defer { unsafe { parts.free() } }
	for i in 1 .. parts.len {
		if parts[i] == '' || parts[i] == '.' || parts[i] == '..' {
			return error('cookie snapshot directory is not canonical')
		}
	}
	mut fd := unsafe { C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
	if fd < 0 { return error('cannot open cookie snapshot filesystem root') }
	for i in 1 .. parts.len {
		directory_info(fd, uid, false) or {
			C.close(fd)
			return err
		}
		next := unsafe { C.openat(fd, parts[i].str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
		C.close(fd)
		if next < 0 {
			return error('cannot open cookie snapshot directory without following links')
		}
		fd = next
		directory_info(fd, uid, i == parts.len - 1) or {
			C.close(fd)
			return err
		}
	}
	return fd
}

fn check_file(directory int, name string, uid u32, create bool) ! {
	mut info := C.stat{}
	// Closing any descriptor for a database inode can drop this process's
	// POSIX locks, even if another SQLite connection owns those locks. Inspect
	// existing files without opening/closing them. A new file is exclusive.
	if unsafe { C.vinix_browsercookies_fstatat(directory, name.str, &info, C.AT_SYMLINK_NOFOLLOW) } != 0 {
		if C.errno != C.ENOENT { return error('cannot inspect private cookie snapshot file') }
		if !create { return }
		fd := unsafe { C.openat(directory, name.str, C.O_RDWR | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CREAT | C.O_EXCL, u32(0o600)) }
		if fd < 0 { return error('cannot create private cookie snapshot file') }
		status := C.fstat(fd, unsafe { &info })
		C.close(fd)
		if status != 0 { return error('cannot inspect new cookie snapshot file') }
	}
	if u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_uid != uid || u32(info.st_mode) & 0o777 != 0o600 || info.st_nlink != 1 {
		return error('cookie snapshot file ownership, mode or link count is unsafe')
	}
}

fn check_files(directory int, uid u32, create bool) ! {
	check_file(directory, 'snapshot.sqlite', uid, create)!
	for name in ['snapshot.sqlite-journal', 'snapshot.sqlite-wal', 'snapshot.sqlite-shm']! {
		check_file(directory, name, uid, false)!
	}
}

fn (a &Api) prepare(db voidptr, query string) !voidptr {
	mut statement := unsafe { nil }
	if unsafe { a.prepare_v2(db, query.str, i32(query.len), &statement, nil) } != sqlite_ok {
		if statement != unsafe { nil } { a.finalize(statement) }
		return error('cannot prepare cookie snapshot operation')
	}
	return statement
}

fn (a &Api) execute(db voidptr, query string) ! {
	statement := a.prepare(db, query)!
	defer { a.finalize(statement) }
	if a.step(statement) != sqlite_done { return error('cookie snapshot operation failed') }
}

fn (a &Api) integer(db voidptr, query string) !i64 {
	statement := a.prepare(db, query)!
	defer { a.finalize(statement) }
	if a.step(statement) != sqlite_row || a.column_type(statement, 0) != sqlite_integer {
		return error('cookie snapshot configuration query failed')
	}
	return a.column_int64(statement, 0)
}

fn valid_text(value string, empty bool) bool {
	return (empty || value.len > 0) && value.len <= max_field && !value.contains('\x00')
		&& utf8.validate_str(value)
}

fn cookie_size(cookie Cookie) !int {
	if !valid_text(cookie.name, true) || !valid_text(cookie.value, true)
		|| !valid_text(cookie.domain, false) || !valid_text(cookie.path, false)
		|| cookie.same_site < 0 || cookie.same_site > 2 {
		return error('cookie snapshot has an invalid cookie')
	}
	// Include fixed metadata, not just string bytes, in the wire-sized bound.
	return cookie.name.len + cookie.value.len + cookie.domain.len + cookie.path.len + 32
}

fn validate(cookies []Cookie) ! {
	if cookies.len > max_cookies { return error('cookie snapshot cookie count exceeds its bound') }
	mut size := 0
	for cookie in cookies {
		size += cookie_size(cookie)!
		if size > max_payload { return error('cookie snapshot payload exceeds its bound') }
	}
}

fn (a &Api) text(statement voidptr, column int) !string {
	if a.column_type(statement, i32(column)) != sqlite_text {
		return error('cookie snapshot contains a non-text field')
	}
	length := int(a.column_bytes(statement, i32(column)))
	data := a.column_text(statement, i32(column))
	if length < 0 || length > max_field || data == unsafe { nil } {
		return error('cookie snapshot contains an invalid text field')
	}
	value := unsafe { data.vstring_with_len(length).clone() }
	if !valid_text(value, true) {
		unsafe { value.free() }
		return error('cookie snapshot contains invalid UTF-8 text')
	}
	return value
}

pub fn open(private_data_dir string) !&Store {
	uid := u32(os.geteuid())
	parent := open_data_directory(private_data_dir, uid)!
	defer { C.close(parent) }
	if unsafe { C.mkdirat(parent, c'browser-cookies', u32(0o700)) } != 0 && C.errno != C.EEXIST {
		return error('cannot create private cookie snapshot directory')
	}
	directory := unsafe { C.openat(parent, c'browser-cookies', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
	if directory < 0 { return error('cannot open private cookie snapshot directory') }
	mut ready := false
	defer { if !ready { C.close(directory) } }
	directory_info(directory, uid, true)!
	check_files(directory, uid, true)!
	library, a := load_api()!
	defer { if !ready { dl.close(library) } }
	mut path := ''
	$if linux {
		path = '/proc/self/fd/${directory}/snapshot.sqlite'
	} $else {
		path = private_data_dir + '/browser-cookies/snapshot.sqlite'
	}
	defer { unsafe { path.free() } }
	mut db := unsafe { nil }
	// READWRITE | FULLMUTEX | NOFOLLOW. The file was securely precreated.
	status := unsafe { a.open_v2(path.str, &db, 0x00000002 | 0x00010000 | 0x01000000, nil) }
	if status != sqlite_ok {
		if db != unsafe { nil } { a.close(db) }
		return error('cannot open cookie snapshot database')
	}
	defer { if !ready { a.close(db) } }
	if a.busy_timeout(db, 1000) != sqlite_ok {
		return error('cannot bound cookie snapshot lock wait')
	}
	a.execute(db, 'PRAGMA trusted_schema=OFF')!
	mode := a.prepare(db, 'PRAGMA journal_mode=DELETE')!
	if a.step(mode) != sqlite_row {
		a.finalize(mode)
		return error('cannot configure cookie snapshot journal')
	}
	journal := a.text(mode, 0) or {
		a.finalize(mode)
		return err
	}
	a.finalize(mode)
	valid_journal := journal == 'delete'
	unsafe { journal.free() }
	if !valid_journal { return error('cookie snapshot requires DELETE journal mode') }
	// EXTRA includes the directory synchronization after rollback-journal
	// unlink. It strengthens FULL; verify the effective level instead of
	// trusting an ignored PRAGMA or relying on a post-commit best effort.
	a.execute(db, 'PRAGMA synchronous=EXTRA')!
	if a.integer(db, 'PRAGMA synchronous')! != 3 {
		return error('cookie snapshot requires FULL synchronization plus directory durability')
	}
	version := a.integer(db, 'PRAGMA user_version')!
	if version != 0 && version != 1 {
		return error('cookie snapshot schema version is unsupported')
	}
	a.execute(db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { a.execute(db, 'ROLLBACK') or {} } }
	a.execute(db, 'CREATE TABLE IF NOT EXISTS cookies (position INTEGER PRIMARY KEY CHECK(position BETWEEN 0 AND 4095), name TEXT NOT NULL, value TEXT NOT NULL, domain TEXT NOT NULL, path TEXT NOT NULL, expires INTEGER, secure INTEGER NOT NULL CHECK(secure IN (0,1)), http_only INTEGER NOT NULL CHECK(http_only IN (0,1)), same_site INTEGER NOT NULL CHECK(same_site BETWEEN 0 AND 2), UNIQUE(name,domain,path))')!
	a.execute(db, 'PRAGMA user_version=1')!
	a.execute(db, 'COMMIT')!
	committed = true
	check_files(directory, uid, false)!
	if C.fsync(directory) != 0 || C.fsync(parent) != 0 {
		return error('cannot synchronize cookie snapshot directory')
	}
	ready = true
	return &Store{ api: a, library: library, directory: directory, uid: uid, db: db }
}

fn (s &Store) require_open() ! {
	if s.db == unsafe { nil } { return error('cookie snapshot store is closed') }
}

fn (a &Api) bind_string(statement voidptr, column int, value string) ! {
	// SQLITE_STATIC: replace borrows its input until each statement finalizes.
	if unsafe { a.bind_text(statement, i32(column), value.str, i32(value.len), nil) } != sqlite_ok {
		return error('cannot bind cookie snapshot text')
	}
}

// A successful return is a durable, atomic complete snapshot, including an
// empty list. On any database error the operation throws and rolls back. The
// caller must not treat a thrown I/O error as evidence of unchanged media.
pub fn (mut s Store) replace(cookies []Cookie) ! {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	validate(cookies)!
	directory_info(s.directory, s.uid, true)!
	check_files(s.directory, s.uid, false)!
	s.api.execute(s.db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { s.api.execute(s.db, 'ROLLBACK') or {} } }
	s.api.execute(s.db, 'DELETE FROM cookies')!
	for position, cookie in cookies {
		statement := s.api.prepare(s.db, 'INSERT INTO cookies(position,name,value,domain,path,expires,secure,http_only,same_site) VALUES(?,?,?,?,?,?,?,?,?)')!
		insert_cookie(s.api, statement, position, cookie) or {
			s.api.finalize(statement)
			return err
		}
		if s.api.finalize(statement) != sqlite_ok {
			return error('cannot finalize cookie snapshot insertion')
		}
	}
	s.api.execute(s.db, 'COMMIT')!
	committed = true
}

fn insert_cookie(a &Api, statement voidptr, position int, cookie Cookie) ! {
	if a.bind_int64(statement, 1, position) != sqlite_ok {
		return error('cannot bind cookie snapshot position')
	}
	a.bind_string(statement, 2, cookie.name)!
	a.bind_string(statement, 3, cookie.value)!
	a.bind_string(statement, 4, cookie.domain)!
	a.bind_string(statement, 5, cookie.path)!
	if expires := cookie.expires {
		if a.bind_int64(statement, 6, expires) != sqlite_ok {
			return error('cannot bind cookie snapshot expiry')
		}
	} else if a.bind_null(statement, 6) != sqlite_ok {
		return error('cannot bind cookie snapshot session expiry')
	}
	if a.bind_int64(statement, 7, int(cookie.secure)) != sqlite_ok
		|| a.bind_int64(statement, 8, int(cookie.http_only)) != sqlite_ok
		|| a.bind_int64(statement, 9, cookie.same_site) != sqlite_ok {
		return error('cannot bind cookie snapshot attributes')
	}
	if a.step(statement) != sqlite_done { return error('cannot replace cookie snapshot') }
}

fn read_cookie(a &Api, statement voidptr) !Cookie {
	mut ready := false
	name := a.text(statement, 1)!
	defer { if !ready { unsafe { name.free() } } }
	value := a.text(statement, 2)!
	defer { if !ready { unsafe { value.free() } } }
	domain := a.text(statement, 3)!
	defer { if !ready { unsafe { domain.free() } } }
	path := a.text(statement, 4)!
	defer { if !ready { unsafe { path.free() } } }
	mut expires := ?i64(none)
	kind := a.column_type(statement, 5)
	if kind == sqlite_integer {
		expires = a.column_int64(statement, 5)
	} else if kind != sqlite_null {
		return error('cookie snapshot contains an invalid expiry')
	}
	for column in 6 .. 9 {
		if a.column_type(statement, i32(column)) != sqlite_integer {
			return error('cookie snapshot contains an invalid attribute')
		}
	}
	secure := a.column_int64(statement, 6)
	http_only := a.column_int64(statement, 7)
	same_site := a.column_int64(statement, 8)
	if secure < 0 || secure > 1 || http_only < 0 || http_only > 1 || same_site < 0 || same_site > 2 {
		return error('cookie snapshot contains an invalid attribute value')
	}
	ready = true
	return Cookie{
		name:      name
		value:     value
		domain:    domain
		path:      path
		expires:   expires
		secure:    secure == 1
		http_only: http_only == 1
		same_site: int(same_site)
	}
}

// Strings and the returned array are owned by the caller, independent of the
// Store lifetime. Use dispose_cookies after WebKit has copied the values.
pub fn (mut s Store) load() ![]Cookie {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	directory_info(s.directory, s.uid, true)!
	check_files(s.directory, s.uid, false)!
	statement := s.api.prepare(s.db, 'SELECT position,name,value,domain,path,expires,secure,http_only,same_site FROM cookies ORDER BY position')!
	defer { s.api.finalize(statement) }
	mut cookies := []Cookie{}
	mut size := 0
	mut ready := false
	defer { if !ready { dispose_cookies(cookies) } }
	for {
		status := s.api.step(statement)
		if status == sqlite_done { break }
		if status != sqlite_row || cookies.len >= max_cookies
			|| s.api.column_type(statement, 0) != sqlite_integer
			|| s.api.column_int64(statement, 0) != cookies.len {
			return error('cookie snapshot contains an invalid sequence')
		}
		cookie := read_cookie(s.api, statement)!
		bytes := cookie_size(cookie) or {
			dispose_cookie(cookie)
			return err
		}
		size += bytes
		if size > max_payload {
			dispose_cookie(cookie)
			return error('cookie snapshot payload exceeds its bound')
		}
		cookies << cookie
	}
	ready = true
	return cookies
}

fn dispose_cookie(cookie Cookie) {
	unsafe {
		cookie.name.free()
		cookie.value.free()
		cookie.domain.free()
		cookie.path.free()
	}
}

pub fn dispose_cookies(cookies []Cookie) {
	for cookie in cookies { dispose_cookie(cookie) }
	unsafe { cookies.free() }
}

pub fn (mut s Store) close() ! {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	if s.db == unsafe { nil } { return }
	if s.api.close(s.db) != sqlite_ok { return error('cannot close cookie snapshot database') }
	s.db = unsafe { nil }
	C.close(s.directory)
	dl.close(s.library)
}

// Requires sole ownership. No operation may retain or use Store after dispose.
pub fn dispose(mut store Store) ! {
	store.close()!
	store.mutex.destroy()
	unsafe { free(&store) }
}
