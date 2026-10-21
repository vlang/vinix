// SPDX-License-Identifier: Apache-2.0
// Android SQLite JNI over the system SQLite provider. CursorWindow remains
// Java-owned. Based on AOSP's SQLiteConnection contract and ATL's Java window.
@[translated]
module atlframework

#include "sqlite3.h"

fn C.sqlite3_open_v2(&char, voidptr, i32, &char) i32
fn C.sqlite3_close(voidptr) i32
fn C.sqlite3_extended_errcode(voidptr) i32
fn C.sqlite3_errmsg(voidptr) &char
fn C.sqlite3_errstr(i32) &char
fn C.sqlite3_busy_timeout(voidptr, i32) i32
fn C.sqlite3_prepare16_v2(voidptr, voidptr, i32, voidptr, voidptr) i32
fn C.sqlite3_finalize(voidptr) i32
fn C.sqlite3_reset(voidptr) i32
fn C.sqlite3_clear_bindings(voidptr) i32
fn C.sqlite3_bind_parameter_count(voidptr) i32
fn C.sqlite3_bind_null(voidptr, i32) i32
fn C.sqlite3_bind_int64(voidptr, i32, i64) i32
fn C.sqlite3_bind_double(voidptr, i32, f64) i32
fn C.sqlite3_bind_text16(voidptr, i32, voidptr, i32, voidptr) i32
fn C.sqlite3_bind_blob(voidptr, i32, voidptr, i32, voidptr) i32
fn C.sqlite3_stmt_readonly(voidptr) i32
fn C.sqlite3_column_count(voidptr) i32
fn C.sqlite3_column_name16(voidptr, i32) voidptr
fn C.sqlite3_step(voidptr) i32
fn C.sqlite3_column_type(voidptr, i32) i32
fn C.sqlite3_column_int64(voidptr, i32) i64
fn C.sqlite3_column_double(voidptr, i32) f64
fn C.sqlite3_column_text16(voidptr, i32) voidptr
fn C.sqlite3_column_blob(voidptr, i32) voidptr
fn C.sqlite3_column_bytes(voidptr, i32) i32
fn C.sqlite3_column_bytes16(voidptr, i32) i32
fn C.sqlite3_changes(voidptr) i32
fn C.sqlite3_last_insert_rowid(voidptr) i64
fn C.sqlite3_interrupt(voidptr)
fn C.sqlite3_progress_handler(voidptr, i32, voidptr, voidptr)
fn C.sqlite3_db_status(voidptr, i32, &i32, &i32, i32) i32
fn C.sqlite3_release_memory(i32) i32
fn C.sqlite3_create_collation_v2(voidptr, &char, i32, voidptr, voidptr, voidptr) i32

struct WsDatabase {
mut:
	db       voidptr
	canceled u32
}

type WsNewByteArray = fn (voidptr, i32) voidptr
type WsCollatorOpen = fn (&char, &i32) voidptr
type WsCollatorCompare = fn (voidptr, voidptr, i32, voidptr, i32, &i32) i32
type WsCollatorClose = fn (voidptr)
// V's function pointers do not express const void* parameters. The callback
// uses the identical C ABI and reads both key buffers without modifying them.
type WsCreateCollation = fn (voidptr, &char, i32, voidptr, voidptr, voidptr) i32

struct WsCollation {
	provider voidptr
	handle   voidptr
	compare  WsCollatorCompare
	close    WsCollatorClose
}

fn ws_sql_db(connection i64) voidptr {
	unsafe { return (&WsDatabase(connection)).db
	 }
}

fn ws_sql_error(e voidptr, connection i64, status i32) {
	if status == 0 || pending(e) { return }
	unsafe {
		db := if connection == 0 { nil } else { ws_sql_db(connection) }
		code := if db == nil { status & 255 } else { C.sqlite3_extended_errcode(db) & 255 }
		class_name := match code {
			10 { &char(c'android/database/sqlite/SQLiteDiskIOException') }
			11, 26 { &char(c'android/database/sqlite/SQLiteDatabaseCorruptException') }
			19 { &char(c'android/database/sqlite/SQLiteConstraintException') }
			4 { &char(c'android/database/sqlite/SQLiteAbortException') }
			101 { &char(c'android/database/sqlite/SQLiteDoneException') }
			13 { &char(c'android/database/sqlite/SQLiteFullException') }
			21 { &char(c'android/database/sqlite/SQLiteMisuseException') }
			3 { &char(c'android/database/sqlite/SQLiteAccessPermException') }
			5 { &char(c'android/database/sqlite/SQLiteDatabaseLockedException') }
			6 { &char(c'android/database/sqlite/SQLiteTableLockedException') }
			14 { &char(c'android/database/sqlite/SQLiteCantOpenDatabaseException') }
			9 { &char(c'android/os/OperationCanceledException') }
			7 { &char(c'java/lang/OutOfMemoryError') }
			else { &char(c'android/database/sqlite/SQLiteException') }
		}
		message := if db == nil {
			&char(C.sqlite3_errstr(status))
		} else {
			&char(C.sqlite3_errmsg(db))
		}
		ThrowNew(slot(e, 14))(e, cls(e, class_name), message)
	}
}

fn ws_sql_compare(context voidptr, left_count i32, left voidptr, right_count i32, right voidptr) i32 {
	unsafe {
		collation := &WsCollation(context)
		mut status := i32(0)
		return collation.compare(collation.handle, left, left_count, right, right_count, &status)
	}
}

fn ws_sql_collation_free(context voidptr) {
	unsafe {
		collation := &WsCollation(context)
		collation.close(collation.handle)
		C.dlclose(collation.provider)
		C.free(collation)
	}
}

fn ws_sql_collation(e voidptr, connection i64, name &char, locale &char) {
	unsafe {
		provider := C.dlopen(c'libicui18n.so.78', 2 | 256)
		if provider == nil {
			ThrowNew(slot(e, 14))(e, cls(e, c'java/lang/IllegalStateException'), c'ICU collation provider is unavailable')
			return
		}
		open := WsCollatorOpen(C.dlsym(provider, c'ucol_open_78'))
		compare := WsCollatorCompare(C.dlsym(provider, c'ucol_strcollUTF8_78'))
		close := WsCollatorClose(C.dlsym(provider, c'ucol_close_78'))
		if voidptr(open) == nil || voidptr(compare) == nil || voidptr(close) == nil {
			C.dlclose(provider)
			ThrowNew(slot(e, 14))(e, cls(e, c'java/lang/IllegalStateException'), c'ICU collation API is unavailable')
			return
		}
		mut status := i32(0)
		handle := open(locale, &status)
		if status > 0 || handle == nil {
			if handle != nil { close(handle) }
			C.dlclose(provider)
			ThrowNew(slot(e, 14))(e, cls(e, c'android/database/sqlite/SQLiteException'), c'Cannot create database collation')
			return
		}
		collation := &WsCollation(C.malloc(sizeof(WsCollation)))
		*collation = WsCollation{provider, handle, compare, close}
		create := WsCreateCollation(C.dlsym(nil, c'sqlite3_create_collation_v2'))
		if voidptr(create) == nil {
			ws_sql_collation_free(collation)
			ThrowNew(slot(e, 14))(e, cls(e, c'java/lang/IllegalStateException'), c'SQLite collation ABI is unavailable')
			return
		}
		result := create(ws_sql_db(connection), name, 1, collation, voidptr(ws_sql_compare), voidptr(ws_sql_collation_free))
		if result != 0 {
			ws_sql_collation_free(collation)
			ws_sql_error(e, connection, result)
		}
	}
}

fn ws_sql_open(e voidptr, path voidptr, flags i32) i64 {
	unsafe {
		output := &voidptr(C.alloca(sizeof(voidptr)))
		*output = nil
		name := ws_utf(e, path)
		sqlite_flags := if flags & 0x10000000 != 0 {
			2 + 4
		} else if flags & 1 != 0 {
			1
		} else {
			2
		}
		status := C.sqlite3_open_v2(name, voidptr(output), sqlite_flags, nil)
		ws_release(e, path, name)
		connection := &WsDatabase(C.calloc(1, sizeof(WsDatabase)))
		connection.db = *output
		if status != 0 {
			ws_sql_error(e, i64(connection), status)
			if *output != nil { C.sqlite3_close(*output) }
			C.free(connection)
			return 0
		}
		C.sqlite3_busy_timeout(*output, 2500)
		ws_sql_collation(e, i64(connection), c'LOCALIZED', c'en_US')
		ws_sql_collation(e, i64(connection), c'UNICODE', c'')
		if pending(e) {
			C.sqlite3_close(*output)
			C.free(connection)
			return 0
		}
		return i64(connection)
	}
}

fn ws_sql_close(e voidptr, connection i64) {
	if connection == 0 { return }
	result := C.sqlite3_close(ws_sql_db(connection))
	if result == 0 { C.free(voidptr(connection)) } else { ws_sql_error(e, connection, result) }
}

fn ws_sql_prepare(e voidptr, connection i64, query voidptr) i64 {
	unsafe {
		chars := WsChars(slot(e, 165))(e, query, nil)
		length := WsLength(slot(e, 164))(e, query)
		statement := &voidptr(C.alloca(sizeof(voidptr)))
		*statement = nil
		status := C.sqlite3_prepare16_v2(ws_sql_db(connection), voidptr(chars), length * 2, voidptr(statement), nil)
		WsCharsRelease(slot(e, 166))(e, query, chars)
		ws_sql_error(e, connection, status)
		return i64(*statement)
	}
}

fn ws_sql_column_name(e voidptr, statement i64, column i32) voidptr {
	unsafe {
		name := &u16(C.sqlite3_column_name16(voidptr(statement), column))
		if name == nil { return nil }
		mut count := i32(0)
		for name[count] != 0 { count++ }
		return WsNewString(slot(e, 163))(e, name, count)
	}
}

fn ws_sql_lookaside(connection i64) i32 {
	unsafe {
		values := &i32(C.alloca(2 * sizeof(i32)))
		values[0] = 0
		values[1] = 0
		C.sqlite3_db_status(ws_sql_db(connection), 0, &values[0], &values[1], 0)
		return values[0]
	}
}

fn ws_sql_bind_string(e voidptr, connection i64, statement i64, index i32, text voidptr) {
	unsafe {
		chars := WsChars(slot(e, 165))(e, text, nil)
		length := WsLength(slot(e, 164))(e, text)
		status := C.sqlite3_bind_text16(voidptr(statement), index, voidptr(chars), length * 2, voidptr(usize(-1)))
		WsCharsRelease(slot(e, 166))(e, text, chars)
		ws_sql_error(e, connection, status)
	}
}

fn ws_sql_bind_blob(e voidptr, connection i64, statement i64, index i32, array voidptr) {
	length := ws_array_len(e, array)
	data := C.malloc(usize(length + 1))
	defer { C.free(data) }
	unsafe { WsByteRegion(slot(e, 200))(e, array, 0, length, data) }
	ws_sql_error(e, connection, C.sqlite3_bind_blob(voidptr(statement), index, data, length, voidptr(usize(-1))))
}

fn ws_sql_execute(e voidptr, connection i64, statement i64) i32 {
	mut status := C.sqlite3_step(voidptr(statement))
	for status == 100 { status = C.sqlite3_step(voidptr(statement)) }
	if status != 101 { ws_sql_error(e, connection, status) }
	return status
}

fn ws_sql_string(e voidptr, statement i64, column i32) voidptr {
	unsafe {
		chars := &u16(C.sqlite3_column_text16(voidptr(statement), column))
		if chars == nil { return nil }
		return WsNewString(slot(e, 163))(e, chars, C.sqlite3_column_bytes16(voidptr(statement), column) / 2)
	}
}

fn ws_sql_one_row(e voidptr, connection i64, statement i64) bool {
	status := C.sqlite3_step(voidptr(statement))
	if status == 100 { return true }
	if status == 101 {
		unsafe { ThrowNew(slot(e, 14))(e, cls(e, c'android/database/sqlite/SQLiteDoneException'), c'Query returned no rows') }
	} else {
		ws_sql_error(e, connection, status)
	}
	return false
}

fn ws_sql_row(e voidptr, window voidptr, statement i64, row i32) bool {
	unsafe {
		if boolean(e, window, c'android/database/CursorWindow', c'allocRow', c'()Z', nil) == 0 {
			return false
		}
		count := C.sqlite3_column_count(voidptr(statement))
		for column := i32(0); column < count; column++ {
			push_frame(e)
			mut args := [Value{}, Value{ i: row }, Value{ i: column }]!
			kind := C.sqlite3_column_type(voidptr(statement), column)
			mut result := u8(0)
			if kind == 5 {
				null_args := [Value{ i: row }, Value{ i: column }]!
				result = boolean(e, window, c'android/database/CursorWindow', c'putNull', c'(II)Z', &null_args[0])
			} else if kind == 1 {
				args[0] = Value{ j: C.sqlite3_column_int64(voidptr(statement), column) }
				result = boolean(e, window, c'android/database/CursorWindow', c'putLong', c'(JII)Z', &args[0])
			} else if kind == 2 {
				args[0] = Value{ d: C.sqlite3_column_double(voidptr(statement), column) }
				result = boolean(e, window, c'android/database/CursorWindow', c'putDouble', c'(DII)Z', &args[0])
			} else if kind == 3 {
				args[0] = Value{ l: ws_sql_string(e, statement, column) }
				result = boolean(e, window, c'android/database/CursorWindow', c'putString', c'(Ljava/lang/String;II)Z', &args[0])
			} else {
				length := C.sqlite3_column_bytes(voidptr(statement), column)
				array := WsNewByteArray(slot(e, 176))(e, length)
				if length > 0 {
					WsByteRegion(slot(e, 208))(e, array, 0, length, voidptr(C.sqlite3_column_blob(voidptr(statement), column)))
				}
				args[0] = Value{ l: array }
				result = boolean(e, window, c'android/database/CursorWindow', c'putBlob', c'([BII)Z', &args[0])
			}
			pop_frame(e)
			if result == 0 || pending(e) {
				call(e, window, c'android/database/CursorWindow', c'freeLastRow', c'()V', nil)
				return false
			}
		}
		return true
	}
}

fn ws_sql_window(e voidptr, connection i64, statement i64, window voidptr, start i32, required i32, count_all u8) i64 {
	unsafe {
		call(e, window, c'android/database/CursorWindow', c'clear', c'()V', nil)
		count := C.sqlite3_column_count(voidptr(statement))
		args := [Value{ i: count }]!
		if boolean(e, window, c'android/database/CursorWindow', c'setNumColumns', c'(I)Z', &args[0]) == 0 {
			return 0
		}
		mut row := i32(0)
		mut first := start
		mut accepting := true
		mut status := C.sqlite3_step(voidptr(statement))
		for status == 100 && !pending(e) {
			if row >= first && accepting {
				accepting = ws_sql_row(e, window, statement, row - first)
				if !accepting && row <= required && !pending(e) {
					call(e, window, c'android/database/CursorWindow', c'clear', c'()V', nil)
					boolean(e, window, c'android/database/CursorWindow', c'setNumColumns', c'(I)Z', &args[0])
					first = row
					accepting = ws_sql_row(e, window, statement, 0)
				}
				if !accepting && count_all == 0 { break }
			}
			row++
			status = C.sqlite3_step(voidptr(statement))
		}
		if status != 100 && status != 101 { ws_sql_error(e, connection, status) }
		reset := C.sqlite3_reset(voidptr(statement))
		ws_sql_error(e, connection, reset)
		return i64((u64(u32(first)) << 32) + u64(u32(row)))
	}
}

fn ws_sql_progress(context voidptr) i32 {
	unsafe { return i32(C.__atomic_load_n(&(&WsDatabase(context)).canceled, 2))
	 }
}

fn ws_sql_reset_cancel(connection i64, cancelable u8) {
	unsafe {
		state := &WsDatabase(connection)
		C.__atomic_store_n(&state.canceled, 0, 3)
		C.sqlite3_progress_handler(state.db, if cancelable != 0 { 1000 } else { 0 }, if cancelable != 0 {
			voidptr(ws_sql_progress)
		} else {
			nil
		}, state)
	}
}
