// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sqlite3.h>
#flag -lsqlite3

@[typedef]
struct C.sqlite3 {}

@[typedef]
struct C.sqlite3_stmt {}

type SqliteDestructor = fn (voidptr)
type SqliteCallback = fn (voidptr, i32, &&char, &&char) i32

fn C.sqlite3_bind_blob(&C.sqlite3_stmt, i32, voidptr, i32, SqliteDestructor) i32
fn C.sqlite3_bind_int(&C.sqlite3_stmt, i32, i32) i32
fn C.sqlite3_bind_int64(&C.sqlite3_stmt, i32, i64) i32
fn C.sqlite3_bind_text(&C.sqlite3_stmt, i32, &char, i32, SqliteDestructor) i32
fn C.sqlite3_changes(&C.sqlite3) i32
fn C.sqlite3_close(&C.sqlite3) i32
fn C.sqlite3_column_int(&C.sqlite3_stmt, i32) i32
fn C.sqlite3_column_int64(&C.sqlite3_stmt, i32) i64
fn C.sqlite3_column_text(&C.sqlite3_stmt, i32) &u8
fn C.sqlite3_errcode(&C.sqlite3) i32
fn C.sqlite3_errmsg(&C.sqlite3) &char
fn C.sqlite3_errstr(i32) &char
fn C.sqlite3_exec(&C.sqlite3, &char, SqliteCallback, voidptr, &&char) i32
fn C.sqlite3_finalize(&C.sqlite3_stmt) i32
fn C.sqlite3_free(voidptr)
fn C.sqlite3_open_v2(&char, &&C.sqlite3, i32, &char) i32
fn C.sqlite3_prepare_v2(&C.sqlite3, &char, i32, &&C.sqlite3_stmt, &&char) i32
fn C.sqlite3_step(&C.sqlite3_stmt) i32

// These fixed-argument C APIs have the same Darwin/Linux ARM64 ABI. Use one
// engine for handles, allocations and callbacks. It owns SQLite state and VFS
// I/O; the Objective-C runtime neither wraps nor takes ownership of it.
// Variadic and Apple-only SQLite extensions are deliberately not exported.
fn sqlite_symbol(symbol string) ?u64 {
	return match symbol {
		'_sqlite3_bind_blob' { u64(unsafe { voidptr(C.sqlite3_bind_blob) }) }
		'_sqlite3_bind_int' { u64(unsafe { voidptr(C.sqlite3_bind_int) }) }
		'_sqlite3_bind_int64' { u64(unsafe { voidptr(C.sqlite3_bind_int64) }) }
		'_sqlite3_bind_text' { u64(unsafe { voidptr(C.sqlite3_bind_text) }) }
		'_sqlite3_changes' { u64(unsafe { voidptr(C.sqlite3_changes) }) }
		'_sqlite3_close' { u64(unsafe { voidptr(C.sqlite3_close) }) }
		'_sqlite3_column_int' { u64(unsafe { voidptr(C.sqlite3_column_int) }) }
		'_sqlite3_column_int64' { u64(unsafe { voidptr(C.sqlite3_column_int64) }) }
		'_sqlite3_column_text' { u64(unsafe { voidptr(C.sqlite3_column_text) }) }
		'_sqlite3_errcode' { u64(unsafe { voidptr(C.sqlite3_errcode) }) }
		'_sqlite3_errmsg' { u64(unsafe { voidptr(C.sqlite3_errmsg) }) }
		'_sqlite3_errstr' { u64(unsafe { voidptr(C.sqlite3_errstr) }) }
		'_sqlite3_exec' { u64(unsafe { voidptr(C.sqlite3_exec) }) }
		'_sqlite3_finalize' { u64(unsafe { voidptr(C.sqlite3_finalize) }) }
		'_sqlite3_free' { u64(unsafe { voidptr(C.sqlite3_free) }) }
		'_sqlite3_open_v2' { u64(unsafe { voidptr(C.sqlite3_open_v2) }) }
		'_sqlite3_prepare_v2' { u64(unsafe { voidptr(C.sqlite3_prepare_v2) }) }
		'_sqlite3_step' { u64(unsafe { voidptr(C.sqlite3_step) }) }
		else { return none }
	}
}
