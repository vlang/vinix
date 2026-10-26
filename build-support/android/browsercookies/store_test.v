// SPDX-License-Identifier: GPL-2.0-or-later
module browsercookies

import os

#include <fcntl.h>
#include <sys/wait.h>

fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int

struct C.flock {
mut:
	l_type   i16
	l_whence i16
	l_start  i64
	l_len    i64
	l_pid    i32
}

@[c: 'waitpid']
fn C.vinix_browsercookies_waitpid(i32, &i32, i32) i32

// F_GETLK does not report the calling process's own locks. A forked probe
// checks the actual kernel lock while making only async-signal-safe C calls.
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
	assert unsafe { C.vinix_browsercookies_waitpid(pid, &status, 0) } == pid
	assert count == 1 && status == 0
	return answer == 1
}

fn fixture(label string) string {
	path := os.join_path(os.home_dir(), '.local', 'state', 'vinix', 'android', 'browsercookies-test-${os.getpid()}-${label}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path, mode: 0o700) or { panic(err) }
	os.chmod(path, 0o700) or { panic(err) }
	return path
}

fn sample(value string) Cookie {
	return Cookie{
		name:      'SID'
		value:     value
		domain:    '.example.test'
		path:      '/'
		expires:   none
		secure:    true
		http_only: true
		same_site: 2
	}
}

fn expect_snapshot(mut store Store, expected []Cookie) {
	actual := store.load() or { panic(err) }
	defer { dispose_cookies(actual) }
	assert actual == expected
}

fn test_real_sqlite_atomic_replace_reopen_session_and_exact_attributes() {
	path := fixture('reopen')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	expect_snapshot(mut store, [])
	assert store.api.integer(store.db, 'PRAGMA synchronous')! == 3
	values := [sample("hello'; DROP TABLE cookies; --"), Cookie{
		name:      ''
		value:     'значение🍪'
		domain:    'example.test'
		path:      '/account/é'
		expires:   i64(2_147_483_648)
		secure:    false
		http_only: false
		same_site: 0
	}, Cookie{
		name:      'SID'
		value:     ''
		domain:    '.example.test'
		path:      '/other'
		expires:   i64(-1)
		same_site: 1
	}]
	store.replace(values)!
	expect_snapshot(mut store, values)
	store.close()!
	mut reopened := open(path)!
	defer { dispose(mut reopened) or { panic(err) } }
	expect_snapshot(mut reopened, values)
	// A new snapshot replaces the entire old set, including omitted domains.
	reopened.replace([sample('new')])!
	expect_snapshot(mut reopened, [sample('new')])
	dispose(mut store)!
}

fn test_empty_snapshot_durably_clears_every_cookie() {
	path := fixture('clear')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	store.replace([sample('one')])!
	store.replace([])!
	dispose(mut store)!
	mut reopened := open(path)!
	defer { dispose(mut reopened) or { panic(err) } }
	expect_snapshot(mut reopened, [])
}

fn test_duplicate_identity_rolls_back_entire_replacement() {
	path := fixture('duplicate')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	store.replace([sample('old')])!
	mut rejected := false
	store.replace([sample('first'), sample('duplicate')]) or { rejected = true }
	assert rejected
	expect_snapshot(mut store, [sample('old')])
	store.close()!
	mut reopened := open(path)!
	defer { dispose(mut reopened) or { panic(err) } }
	expect_snapshot(mut reopened, [sample('old')])
}

fn test_real_sqlite_insertion_failure_rolls_back_delete_and_prior_inserts() {
	path := fixture('failure')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	store.replace([sample('old')])!
	store.api.execute(store.db, "CREATE TRIGGER fail_insert BEFORE INSERT ON cookies WHEN NEW.name='reject' BEGIN SELECT RAISE(ABORT,'test failure'); END")!
	mut rejected := false
	store.replace([sample('new'),
		Cookie{ name: 'reject', value: 'x', domain: 'example.test', path: '/' }]) or { rejected = true }
	assert rejected
	expect_snapshot(mut store, [sample('old')])
	store.api.execute(store.db, 'DROP TRIGGER fail_insert')!
	store.replace([sample('recovered')])!
	expect_snapshot(mut store, [sample('recovered')])
}

fn test_invalid_cookie_fields_and_limits_preserve_previous_snapshot() {
	path := fixture('bounds')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	store.replace([sample('old')])!
	oversize := 'v'.repeat(max_field + 1)
	invalid_utf8 := [u8(0xc0), 0xaf].bytestr()
	defer {
		unsafe {
			oversize.free()
			invalid_utf8.free()
		}
	}
	for invalid in [sample(oversize), sample(invalid_utf8), sample('bad\x00value'),
		Cookie{ name: 'x', domain: '', path: '/' },
		Cookie{ name: 'x', domain: 'example.test', path: '' },
		Cookie{ name: 'x', domain: 'example.test', path: '/', same_site: -1 },
		Cookie{ name: 'x', domain: 'example.test', path: '/', same_site: 3 }] {
		mut rejected := false
		store.replace([invalid]) or { rejected = true }
		assert rejected
		expect_snapshot(mut store, [sample('old')])
	}
	too_many := []Cookie{len: max_cookies + 1, init: sample('x')}
	mut rejected := false
	store.replace(too_many) or { rejected = true }
	unsafe { too_many.free() }
	assert rejected
	// Each field is valid, but their combined snapshot exceeds four MiB.
	large := 'v'.repeat(max_field)
	defer { unsafe { large.free() } }
	mut too_large := []Cookie{}
	for i in 0 .. 64 {
		too_large << Cookie{ name: i.str(), value: large, domain: 'example.test', path: '/' }
	}
	rejected = false
	store.replace(too_large) or { rejected = true }
	assert rejected
	unsafe {
		for cookie in too_large { cookie.name.free() }
		too_large.free()
	}
	expect_snapshot(mut store, [sample('old')])
}

fn test_maximum_cookie_count_and_field_length_are_accepted() {
	path := fixture('boundary')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	mut values := []Cookie{cap: max_cookies}
	for i in 0 .. max_cookies {
		values << Cookie{ name: i.str(), domain: '.example.test', path: '/' }
	}
	store.replace(values)!
	expect_snapshot(mut store, values)
	unsafe {
		for cookie in values { cookie.name.free() }
		values.free()
	}
	maximum := 'v'.repeat(max_field)
	defer { unsafe { maximum.free() } }
	store.replace([sample(maximum)])!
	expect_snapshot(mut store, [sample(maximum)])
}

fn test_closed_store_fails_before_using_unloaded_sqlite_and_owned_results_survive() {
	path := fixture('lifetime')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	store.replace([sample('retained')])!
	owned := store.load()!
	store.close()!
	store.close()!
	mut rejected_load := false
	store.load() or { rejected_load = true }
	mut rejected_replace := false
	store.replace([]) or { rejected_replace = true }
	assert rejected_load && rejected_replace
	dispose(mut store)!
	assert owned == [sample('retained')]
	dispose_cookies(owned)
}

fn test_database_lock_is_bounded_and_does_not_claim_success() {
	path := fixture('lock')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	store.replace([sample('old')])!
	mut other := open(path)!
	defer { dispose(mut other) or { panic(err) } }
	store.api.execute(store.db, 'BEGIN IMMEDIATE')!
	mut rejected := false
	other.replace([sample('new')]) or { rejected = true }
	assert rejected
	store.api.execute(store.db, 'ROLLBACK')!
	expect_snapshot(mut other, [sample('old')])
}

fn test_metadata_validation_preserves_another_sqlite_connections_kernel_locks() {
	path := fixture('kernel-lock')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	file := os.join_path(path, 'browser-cookies', 'snapshot.sqlite')
	fd := unsafe { C.open(file.str, C.O_RDWR | C.O_CLOEXEC | C.O_NOFOLLOW) }
	assert fd >= 0
	defer { C.close(fd) }
	store.api.execute(store.db, 'BEGIN IMMEDIATE')!
	// Keep this probe independent of the host SQLite build's lock style.
	mut guard := C.flock{ l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1 }
	assert unsafe { C.fcntl(i32(fd), C.F_SETLK, &guard) } == 0
	assert has_parent_lock(fd)
	check_files(store.directory, u32(os.geteuid()), true)!
	assert has_parent_lock(fd)
	store.api.execute(store.db, 'ROLLBACK')!
	guard.l_type = i16(C.F_UNLCK)
	assert unsafe { C.fcntl(i32(fd), C.F_SETLK, &guard) } == 0
	assert !has_parent_lock(fd)
}

fn test_corrupt_database_rows_are_rejected_and_clean_replacement_recovers() {
	path := fixture('corrupt')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	store.replace([sample('old')])!
	store.api.execute(store.db, 'PRAGMA ignore_check_constraints=ON')!
	for mutation in ['UPDATE cookies SET secure=2', 'UPDATE cookies SET expires=1.5',
		"UPDATE cookies SET name=X'ff'", 'UPDATE cookies SET position=1'] {
		store.api.execute(store.db, mutation)!
		mut rejected := false
		store.load() or { rejected = true }
		assert rejected
		store.replace([sample('restored')])!
	}
	expect_snapshot(mut store, [sample('restored')])
}

fn test_oversized_existing_database_is_rejected_during_incremental_load() {
	path := fixture('database-bound')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	defer { dispose(mut store) or { panic(err) } }
	// Bypass replace's input validation to model a malformed retained file.
	store.api.execute(store.db, "WITH RECURSIVE n(i) AS (VALUES(0) UNION ALL SELECT i+1 FROM n WHERE i<63) INSERT INTO cookies SELECT i, CAST(i AS TEXT), replace(hex(zeroblob(32768)),'0','v'), 'example.test','/',NULL,0,0,0 FROM n")!
	mut rejected := false
	store.load() or { rejected = true }
	assert rejected
	store.replace([])!
	expect_snapshot(mut store, [])
}

fn test_directory_modes_symlinks_and_noncanonical_paths_fail_closed() {
	path := fixture('directory')
	defer { os.rmdir_all(path) or {} }
	for invalid in [path + '/', path + '/.', path + '/../directory', '/' + path, 'relative',
		path + '\x00bad'] {
		mut rejected := false
		open(invalid) or { rejected = true }
		assert rejected
	}
	os.chmod(path, 0o755)!
	mut rejected := false
	open(path) or { rejected = true }
	assert rejected
	os.chmod(path, 0o700)!
	target := os.join_path(path, 'target')
	os.mkdir(target, mode: 0o700)!
	os.symlink(target, os.join_path(path, 'browser-cookies'))!
	rejected = false
	open(path) or { rejected = true }
	assert rejected
	os.rm(os.join_path(path, 'browser-cookies'))!
	mut store := open(path)!
	dispose(mut store)!
	os.chmod(os.join_path(path, 'browser-cookies'), 0o755)!
	rejected = false
	open(path) or { rejected = true }
	assert rejected
}

fn test_database_and_sidecar_links_and_special_files_are_rejected() {
	for name in ['snapshot.sqlite', 'snapshot.sqlite-journal', 'snapshot.sqlite-wal',
		'snapshot.sqlite-shm'] {
		for attack in ['symlink', 'hardlink', 'fifo', 'public'] {
			path := fixture(name + '-' + attack)
			mut store := open(path)!
			dispose(mut store)!
			file := os.join_path(path, 'browser-cookies', name)
			os.rm(file) or {}
			target := os.join_path(path, 'target')
			os.write_file(target, 'private')!
			os.chmod(target, 0o600)!
			if attack == 'symlink' {
				os.symlink(target, file)!
			} else if attack == 'hardlink' {
				assert unsafe { C.link(target.str, file.str) } == 0
			} else if attack == 'fifo' {
				assert unsafe { C.mkfifo(file.str, u32(0o600)) } == 0
			} else {
				os.write_file(file, '')!
				os.chmod(file, 0o644)!
			}
			mut rejected := false
			open(path) or { rejected = true }
			assert rejected
			assert os.read_file(target)! == 'private'
			os.rmdir_all(path)!
		}
	}
}

fn test_unknown_schema_version_is_rejected_without_replacing_cookies() {
	path := fixture('schema')
	defer { os.rmdir_all(path) or {} }
	mut store := open(path)!
	store.replace([sample('old')])!
	store.api.execute(store.db, 'PRAGMA user_version=2')!
	dispose(mut store)!
	mut rejected := false
	open(path) or { rejected = true }
	assert rejected
}
