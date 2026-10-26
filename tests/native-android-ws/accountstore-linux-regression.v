// SPDX-License-Identifier: GPL-2.0-or-later
// Synthetic SQLite path/security regression; never opens a provisioned account store.
module main

import accountstore
import os

#include <fcntl.h>
#include <sqlite3.h>
#include <unistd.h>

fn C.sqlite3_extended_errcode(voidptr) int
fn C.link(&char, &char) int

const owner = 'com.google.android.gms'
const kind = 'com.google'
const maps = 'com.google.android.apps.maps'

fn make_private(path string) ! {
	os.mkdir(path, mode: 0o700)!
	os.chmod(path, 0o700)!
}

fn reject(path string) ! {
	mut store := accountstore.open(path, u32(os.geteuid()), owner, kind) or { return }
	accountstore.dispose(mut store)!
	return error('unsafe store was accepted')
}

fn canonical_and_procfd(path string) ! {
	make_private(path)!
	mut first := accountstore.open(path, u32(os.geteuid()), owner, kind)!
	account := accountstore.Account{'synthetic@example.test', kind}
	assert first.add(account, 'synthetic-password', {'fixture': ?string('retained')}, {maps: 2})!
	accountstore.dispose(mut first)!
	mut reopened := accountstore.open(path, u32(os.geteuid()), owner, kind)!
	values := reopened.accounts(none, maps)!
	assert values == [account]
	accountstore.dispose_accounts(values)
	metadata := reopened.user_data(account, 'fixture')!
	assert metadata.value == ?string('retained')
	accountstore.dispose_nullable(metadata)
	accountstore.dispose(mut reopened)!
	println('ACCOUNTSTORE-CANONICAL-PASS persistence reopen visibility userdata')
	$if linux {
		// Reproduce the old production spelling with identical SQLite flags.
		// NOFOLLOW rejects deliberate /proc magic links as well as hostile links.
		directory_path := path + '/accounts'
		directory := unsafe { C.open(directory_path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW) }
		if directory < 0 { return error('cannot open synthetic account directory') }
		defer { C.close(directory) }
		old_path := '/proc/self/fd/${directory}/accounts.sqlite'
		mut db := &C.sqlite3(unsafe { nil })
		code := unsafe { C.sqlite3_open_v2(old_path.str, &db, C.SQLITE_OPEN_READWRITE | C.SQLITE_OPEN_FULLMUTEX | C.SQLITE_OPEN_NOFOLLOW, nil) }
		extended := if db != unsafe { nil } { C.sqlite3_extended_errcode(db) } else { -1 }
		if db != unsafe { nil } { C.sqlite3_close(db) }
		assert code == C.SQLITE_CANTOPEN
		assert extended == C.SQLITE_CANTOPEN_SYMLINK
		println('ACCOUNTSTORE-PROCFD-REJECTED code=${code} extended=${extended}')
	}
}

fn unsafe_links(root string) ! {
	data := root + '/ancestor-real'
	make_private(data)!
	os.symlink(data, root + '/ancestor-link')!
	reject(root + '/ancestor-link')!
	println('ACCOUNTSTORE-REJECTION-PASS symlink-ancestor')
	for attack in ['directory', 'symlink', 'hardlink', 'journal'] {
		path := root + '/' + attack
		make_private(path)!
		// Use a valid database: a malformed target could hide a missing link
		// guard behind SQLite's later corruption rejection.
		make_private(path + '/target-store')!
		mut target_store := accountstore.open(path + '/target-store', u32(os.geteuid()), owner, kind)!
		accountstore.dispose(mut target_store)!
		target := path + '/target-store/accounts/accounts.sqlite'
		before := os.read_file(target)!
		if attack == 'directory' {
			make_private(path + '/real')!
			os.symlink(path + '/real', path + '/accounts')!
		} else {
			make_private(path + '/accounts')!
			file := path + '/accounts/accounts.sqlite'
			if attack == 'journal' {
				mut store := accountstore.open(path, u32(os.geteuid()), owner, kind)!
				accountstore.dispose(mut store)!
				os.symlink(target, file + '-journal')!
			} else if attack == 'hardlink' {
				if unsafe { C.link(target.str, file.str) } != 0 { return error('cannot create synthetic hard link') }
			} else {
				os.symlink(target, file)!
			}
		}
		reject(path)!
		assert os.read_file(target)! == before
		println('ACCOUNTSTORE-REJECTION-PASS ${attack} target-unchanged')
	}
}

fn main() {
	if os.args.len != 2 {
		eprintln('usage: accountstore-linux-regression FRESH_PRIVATE_DIRECTORY')
		exit(2)
	}
	path := os.args[1]
	// A newly-created leaf prevents accidental access to a real account store.
	if path.len < 2 || !os.is_abs_path(path) || os.exists(path) || os.is_link(path) {
		eprintln('fixture requires a fresh absolute directory beneath trusted ancestors')
		exit(2)
	}
	make_private(path) or { eprintln(err.msg()); exit(1) }
	// Keep only this synthetic tree if any check fails, for inspection.
	canonical_and_procfd(path + '/canonical') or { eprintln(err.msg()); exit(1) }
	unsafe_links(path) or { eprintln(err.msg()); exit(1) }
	os.rmdir_all(path) or { eprintln(err.msg()); exit(1) }
	$if linux {
		println('ACCOUNTSTORE-LINUX-PASS canonical-persistence procfd-nofollow-rejection unsafe-links')
	} $else {
		println('ACCOUNTSTORE-HOST-PASS canonical-persistence unsafe-links linux-procfd-unexecuted')
	}
}
