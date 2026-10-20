// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type SqOpen = fn (&char, &u64, i32, &char) i32
type SqPrepare = fn (u64, &char, i32, &u64, &u64) i32
type SqBind = fn (u64, i32, u64, i32, u64) i32
type SqBindInt = fn (u64, i32, i32) i32
type SqBindInt64 = fn (u64, i32, i64) i32
type SqUnary = fn (u64) i32
type SqColumnInt = fn (u64, i32) i32
type SqColumnInt64 = fn (u64, i32) i64
type SqColumnText = fn (u64, i32) u64
type SqErrstr = fn (i32) u64
type SqText = fn (u64) u64
type SqExec = fn (u64, &char, u64, u64, &u64) i32
type SqFree = fn (u64)
type SqProbe = fn (&u64, u64, &u64)

const sq_names = ['_sqlite3_bind_blob', '_sqlite3_bind_int', '_sqlite3_bind_int64', '_sqlite3_bind_text',
	'_sqlite3_changes', '_sqlite3_close', '_sqlite3_column_int', '_sqlite3_column_int64',
	'_sqlite3_column_text', '_sqlite3_errcode', '_sqlite3_errmsg', '_sqlite3_errstr', '_sqlite3_exec',
	'_sqlite3_finalize', '_sqlite3_free', '_sqlite3_open_v2', '_sqlite3_prepare_v2', '_sqlite3_step']!

struct SqApi {
	native  bool
	handle  voidptr
	entries [18]u64
}

fn sq_api(native bool) SqApi {
	handle := if native { C.dlopen(c'/usr/lib/libsqlite3.dylib', 2) } else { unsafe { nil } }
	if native {
		assert handle != unsafe { nil }
	}
	mut entries := [18]u64{}
	for i, name in sq_names {
		entries[i] = if native {
			u64(C.dlsym(handle, unsafe { &char(name.str + 1) }))
		} else {
			runtime_symbol('/usr/lib/libsqlite3.dylib', name) or { panic(err) }
		}
		assert entries[i] != 0
	}
	return SqApi{native, handle, entries}
}

fn sq_open(api SqApi, path &char, flags i32) u64 {
	mut db := u64(0)
	assert unsafe { SqOpen(voidptr(api.entries[15]))(path, &db, flags, unsafe { nil }) } == 0 && db != 0
	return db
}

fn sq_prepare(api SqApi, db u64, statement_sql &char) u64 {
	mut stmt := u64(0)
	mut tail := u64(0)
	assert unsafe { SqPrepare(voidptr(api.entries[16]))(db, statement_sql, -1, &stmt, &tail) } == 0 && stmt != 0
	return stmt
}

fn sq_exec(api SqApi, db u64, statement_sql &char) {
	mut error_text := u64(0)
	assert unsafe { SqExec(voidptr(api.entries[12]))(db, statement_sql, 0, 0, &error_text) } == 0 && error_text == 0
}

fn sq_step(api SqApi, stmt u64) i32 { return unsafe { SqUnary(voidptr(api.entries[17]))(stmt) } }

fn sq_finalize(api SqApi, stmt u64) i32 {
	return unsafe { SqUnary(voidptr(api.entries[13]))(stmt) }
}

fn sq_close(api SqApi, db u64) {
	assert unsafe { SqUnary(voidptr(api.entries[5]))(db) } == 0
}

fn sq_column(api SqApi, stmt u64, index i32) string {
	address := unsafe { SqColumnText(voidptr(api.entries[8]))(stmt, index) }
	assert address != 0
	return unsafe { (&char(voidptr(address))).vstring() }
}

__global sq_destructs = i64(0)

fn sq_destructor(pointer u64) {
	assert read64(pointer - 16) == 0x73716c697465 && read64(pointer - 8) == pointer
	$if ios_sqlite ? {
		assert (runtime_symbol('/usr/lib/libsqlite3.dylib', '_sqlite3_bind_blob') or { panic(err) }) != 0
	}
	C.ios_ref_change(unsafe { &sq_destructs }, 1)
	C.free(unsafe { voidptr(pointer - 16) })
}

fn sq_owned() u64 {
	base := u64(C.calloc(1, 32))
	assert base != 0
	unsafe {
		*(&u64(voidptr(base))) = 0x73716c697465
		*(&u64(voidptr(base + 8))) = base + 16
		*(&u8(voidptr(base + 16))) = 65
		*(&u8(voidptr(base + 17))) = 0
		*(&u8(voidptr(base + 18))) = 66
	}
	return base + 16
}

fn sq_bindings(api SqApi, probe SqProbe, guard u64, page usize) {
	db := sq_open(api, c':memory:', 6 | 0x10000)
	sq_exec(api, db, c'create table t(i integer,j integer,txt text,b blob)')
	stmt := sq_prepare(api, db, c'insert into t values(?1,?2,?3,?4)')
	assert unsafe { SqBindInt(voidptr(api.entries[1]))(stmt, 1, -7) } == 0
	assert unsafe { SqBindInt64(voidptr(api.entries[2]))(stmt, 2, -9223372036854775807) } == 0
	text := sq_owned()
	blob := sq_owned()
	before := C.ios_ref_change(unsafe { &sq_destructs }, 0)
	assert unsafe { SqBind(voidptr(api.entries[3]))(stmt, 3, text, 3, u64(voidptr(sq_destructor))) } == 0
	assert unsafe { SqBind(voidptr(api.entries[0]))(stmt, 4, blob, 3, u64(voidptr(sq_destructor))) } == 0
	assert sq_step(api, stmt) == 101 && unsafe { SqUnary(voidptr(api.entries[4]))(db) } == 1
	assert C.ios_ref_change(unsafe { &sq_destructs }, 0) == before && sq_finalize(api, stmt) == 0 && C.ios_ref_change(unsafe { &sq_destructs }, 0) == before + 2
	row := sq_prepare(api, db, c'select i,j,hex(txt),hex(b),NULL from t')
	assert sq_step(api, row) == 100
	assert unsafe { SqColumnInt(voidptr(api.entries[6]))(row, 0) } == -7 && unsafe { SqColumnInt64(voidptr(api.entries[7]))(row, 1) } == -9223372036854775807
	assert sq_column(api, row, 2) == '410042', sq_column(api, row, 2)
	assert sq_column(api, row, 3) == '410042', sq_column(api, row, 3)
	assert unsafe { SqColumnText(voidptr(api.entries[8]))(row, 4) } == 0
	assert sq_step(api, row) == 101 && sq_finalize(api, row) == 0
	// TRANSIENT copies exact, nonterminated bytes before the guarded source is
	// retired. STATIC observes a later caller mutation. Raw calls also protect
	// unused registers/stack/Self/x8 and verify both bind entries' fifth argument.
	for slot in [0, 3]! {
		base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != u64(-1) && C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
		pointer := base + u64(page) - 3
		unsafe {
			*(&u8(voidptr(pointer))) = 0
			*(&u8(voidptr(pointer + 1))) = 65
			*(&u8(voidptr(pointer + 2))) = 255
		}
		bound := sq_prepare(api, db, c'select hex(?1)')
		input := [bound, u64(1), pointer, u64(3), ~u64(0), guard, guard, guard, guard, guard, guard,
			guard, guard]!
		mut output := [6]u64{}
		probe(unsafe { &input[0] }, api.entries[slot], unsafe { &output[0] })
		assert i32(output[0]) == 0 && output[4] == guard && output[5] == guard && C.mprotect(voidptr(base), page, C.PROT_NONE) == 0
		assert sq_step(api, bound) == 100 && sq_column(api, bound, 0) == '0041FF' && sq_finalize(api, bound) == 0
		assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
		static_stmt := sq_prepare(api, db, c'select hex(?1)')
		assert unsafe { SqBind(voidptr(api.entries[slot]))(static_stmt, 1, pointer, 3, 0) } == 0
		unsafe { *(&u8(voidptr(pointer + 1))) = 66 }
		assert sq_step(api, static_stmt) == 100 && sq_column(api, static_stmt, 0) == '0042FF' && sq_finalize(api, static_stmt) == 0
		assert C.munmap(voidptr(base), page * 2) == 0
		invalid := sq_prepare(api, db, c'select ?1')
		calls := C.ios_ref_change(unsafe { &sq_destructs }, 0)
		assert unsafe { SqBind(voidptr(api.entries[slot]))(invalid, 99, sq_owned(), 3, u64(voidptr(sq_destructor))) } == 25 && C.ios_ref_change(unsafe { &sq_destructs }, 0) == calls + 1
		assert unsafe { SqBind(voidptr(api.entries[slot]))(invalid, 1, 0, 100, u64(voidptr(sq_destructor))) } == 0 && C.ios_ref_change(unsafe { &sq_destructs }, 0) == calls + 1
		assert sq_step(api, invalid) == 100 && unsafe { SqColumnText(voidptr(api.entries[8]))(invalid, 0) } == 0 && sq_finalize(api, invalid) == 0
		zero := sq_prepare(api, db, c'select hex(?1)')
		assert unsafe { SqBind(voidptr(api.entries[slot]))(zero, 1, sq_owned(), 0, u64(voidptr(sq_destructor))) } == 0
		assert sq_step(api, zero) == 100 && sq_column(api, zero, 0) == '' && sq_finalize(api, zero) == 0 && C.ios_ref_change(unsafe { &sq_destructs }, 0) == calls + 2
	}
	busy := sq_prepare(api, db, c'select 1')
	assert unsafe { SqUnary(voidptr(api.entries[5]))(db) } == 5
	assert sq_finalize(api, busy) == 0
	sq_close(api, db)
}

struct SqRows {
	api SqApi
	db  u64
mut:
	seen   int
	abort  bool
	nested bool
}

fn sq_rows(data u64, count i32, values u64, names u64) i32 {
	mut state := unsafe { &SqRows(voidptr(data)) }
	assert count == 2 && read64(names) != 0 && read64(names + 8) != 0
	assert unsafe { (&char(voidptr(read64(names)))).vstring() } == 'answer' && unsafe { (&char(voidptr(read64(values)))).vstring() } == '42' && read64(values + 8) == 0
	state.seen++
	$if ios_sqlite ? {
		if !state.api.native {
			assert runtime_symbol('/usr/lib/libsqlite3.dylib', '_sqlite3_exec') or { panic(err) } == state.api.entries[12]
		}
	}
	if state.nested { sq_exec(state.api, state.db, c'select 1') }
	return if state.abort { i32(1) } else { i32(0) }
}

fn sq_errors_callbacks(api SqApi) {
	db := sq_open(api, c':memory:', 6 | 0x10000)
	mut rows := SqRows{ api: api, db: db, nested: true }
	mut message := u64(0)
	assert unsafe { SqExec(voidptr(api.entries[12]))(db, c'select 42 as answer,NULL as empty', u64(voidptr(sq_rows)), u64(&rows), &message) } == 0 && rows.seen == 1 && message == 0
	rows.abort = true
	rows.nested = false
	assert unsafe { SqExec(voidptr(api.entries[12]))(db, c'select 42 as answer,NULL as empty', u64(voidptr(sq_rows)), u64(&rows), &message) } == 4 && rows.seen == 2 && message != 0
	unsafe { SqFree(voidptr(api.entries[14]))(message) }
	message = 0
	assert unsafe { SqExec(voidptr(api.entries[12]))(db, c'this is not SQL', 0, 0, &message) } == 1 && message != 0
	assert unsafe { SqUnary(voidptr(api.entries[9]))(db) } == 1 && unsafe { (&char(voidptr(SqText(voidptr(api.entries[10]))(db)))).vstring() }.len > 0 && unsafe { (&char(voidptr(SqErrstr(voidptr(api.entries[11]))(1)))).vstring() }.len > 0
	unsafe {
		SqFree(voidptr(api.entries[14]))(message)
		SqFree(voidptr(api.entries[14]))(0)
	}
	sq_exec(api, db, c'create table u(i primary key);insert into u values(1)')
	duplicate := sq_prepare(api, db, c'insert into u values(1)')
	assert sq_step(api, duplicate) == 19 && sq_finalize(api, duplicate) == 19
	mut failed := u64(0)
	assert unsafe { SqOpen(voidptr(api.entries[15]))(c':memory:', &failed, 6, c'VinixMissingVFS') } == 1 && failed != 0
	sq_close(api, failed)
	sq_close(api, db)
}

fn sq_worker(api SqApi, db u64) {
	for _ in 0 .. 32 { sq_exec(api, db, c'insert into threads values(1)') }
}

fn sq_threads(api SqApi) {
	db := sq_open(api, c':memory:', 6 | 0x10000)
	sq_exec(api, db, c'create table threads(i)')
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn sq_worker(api, db) }
	workers.wait()
	unsafe { workers.free() }
	stmt := sq_prepare(api, db, c'select count(*) from threads')
	assert sq_step(api, stmt) == 100 && unsafe { SqColumnInt(voidptr(api.entries[6]))(stmt, 0) } == 256 && sq_finalize(api, stmt) == 0
	sq_close(api, db)
}

fn sq_file(api SqApi, tag string) {
	path := os.temp_dir() + '/vinix-ios-sqlite-' + tag + '-' + os.getpid().str() + '.db'
	assert !os.exists(path)
	db := sq_open(api, unsafe { &char(path.str) }, 6 | 0x10000)
	sq_exec(api, db, c'pragma journal_mode=delete;create table f(i);begin immediate;insert into f values(42);rollback;insert into f values(7)')
	sq_close(api, db)
	readonly := sq_open(api, unsafe { &char(path.str) }, 1)
	stmt := sq_prepare(api, readonly, c'select i from f')
	assert sq_step(api, stmt) == 100 && unsafe { SqColumnInt(voidptr(api.entries[6]))(stmt, 0) } == 7 && sq_step(api, stmt) == 101 && sq_finalize(api, stmt) == 0
	mut error_text := u64(0)
	assert unsafe { SqExec(voidptr(api.entries[12]))(readonly, c'insert into f values(8)', 0, 0, &error_text) } == 8 && error_text != 0
	unsafe { SqFree(voidptr(api.entries[14]))(error_text) }
	sq_close(api, readonly)
	bytes := os.read_bytes(path) or { panic(err) }
	assert bytes[..16].bytestr() == 'SQLite format 3\x00'
	unsafe { bytes.free() }
	os.rm(path) or { panic(err) }
	for suffix in ['-journal', '-wal', '-shm']! {
		assert !os.exists(path + suffix)
	}
	unsafe { path.free() }
}

fn test_sqlite() {
	$if ios_sqlite ? {
		page := usize(C.getpagesize())
		code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert code != u64(-1)
		for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f1, 0xaa0103f0, 0xaa0203f3,
			0xd10043ff, 0xa9400620, 0xa9410e22, 0xa9421624, 0xa9431e26, 0xa9442a29, 0xa9002be9,
			0xf9402a28, 0xf9402e34, 0xf9403235, 0xd63f0200, 0xa9000660, 0xa9010e62, 0xa9025674,
			0x910043ff, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
			write32(code + u64(i * 4), op)
		}
		C.__builtin___clear_cache(voidptr(code), voidptr(code + 100))
		assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(code + u64(page)), page, C.PROT_NONE) == 0
		probe := unsafe { SqProbe(voidptr(code)) }
		guard := code + u64(page)
		$if macos {
			native := sq_api(true)
			sq_bindings(native, probe, guard, page)
			sq_errors_callbacks(native)
			sq_threads(native)
			sq_file(native, 'native')
			assert C.dlclose(native.handle) == 0
			println('NATIVE-SQLITE: 18 fixed-argument exports, static/transient/custom ownership, errors, reentrant/abort callbacks, signed integers, shared full-mutex concurrency and persistent database files')
		}
		api := sq_api(false)
		for name in sq_names {
			assert runtime_symbol('/usr/lib/libsqlite3.dylib', name) or { panic(err) } == (sqlite_symbol(name) or { panic('sqlite symbol') })
			for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib',
				'/System/Library/Frameworks/Foundation.framework/Foundation']! {
				if _ := runtime_symbol(library, name) {
					assert false
				}
			}
		}
		for name in ['sqlite3_bind_blob', '_sqlite3_bind_blobExtra', '_sqlite3_config',
			'_sqlite3_mprintf', '_sqlite3_load_extension']! {
			if _ := sqlite_symbol(name) {
				assert false
			}
		}
		for round in 0 .. 2 {
			objc_start()
			sq_bindings(api, probe, guard, page)
			sq_errors_callbacks(api)
			sq_threads(api)
			sq_file(api, if round == 0 { 'compat-one' } else { 'compat-two' })
			persistent := sq_open(api, c':memory:', 6)
			sq_exec(api, persistent, c'create table live(i);insert into live values(42)')
			objc_stop()
			stmt := sq_prepare(api, persistent, c'select i from live')
			assert sq_step(api, stmt) == 100 && unsafe { SqColumnInt(voidptr(api.entries[6]))(stmt, 0) } == 42 && sq_finalize(api, stmt) == 0
			sq_close(api, persistent)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		assert C.munmap(voidptr(code), page * 2) == 0
		println('IOS-SQLITE: 18 exact native backend aliases, static/transient/custom and failed/empty/null binds, guarded raw ARM64 fifth-argument calls, signed 32/64-bit values, owned errors, reentrant/abort callbacks, busy close, constraint errors, eight shared-connection writers, transactional disk persistence/read-only failure and handles across two drained Objective-C runtimes')
	} $else {
		for _ in 0 .. 2 {
			objc_start()
			for name in sq_names {
				if _ := runtime_symbol('/usr/lib/libsqlite3.dylib', name) {
					assert false
				}
			}
			objc_stop()
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		println('IOS-SQLITE: backend disabled; all 18 imports remain unresolved across two drained runtimes')
	}
}
