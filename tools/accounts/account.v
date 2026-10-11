// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-account: the administrator's tool for the account database. It is
// run by root -- at boot, by an installer, or by the authentication service
// on behalf of an administrator who gave their password -- and does no
// authentication of its own.
//
//	vinix-account init                   the accounts every system has, and
//	                                     the person registered before there
//	                                     were accounts, if any
//	vinix-account add [--admin] NAME [FULL-NAME [admin|standard]]
//	                                     the password, if any, on standard input
//	vinix-account remove [--remove-home] NAME
//	vinix-account passwd NAME            the new password on standard input
//	vinix-account admin NAME on|off
//	vinix-account lock NAME on|off
//	vinix-account rename NAME FULL-NAME
//	vinix-account make-home NAME
//	vinix-account list
//	vinix-account check
//
// `--root DIR` before the command works on the system installed under DIR.
module main

import accountcore
import os

#include <unistd.h>
#include <sys/mount.h>
#include <errno.h>

fn C.geteuid() u32
fn C.lchown(path &char, owner u32, group u32) int
$if linux {
	fn C.mount(source &char, target &char, kind &char, flags u64, data voidptr) int
}
fn C.sync()

// The folders a home starts with.
const home_folders = ['Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos']
// Where the desktop kept the one registered person's record and folders.
const registration_record = '/root/.vinix-user'
const legacy_homes = '/root/home'

struct Tool {
	root  string
	store accountcore.Store
	cost  accountcore.Cost
}

fn fail(message string) {
	eprintln('vinix-account: ${message}')
	exit(1)
}

fn usage() {
	eprintln('usage: vinix-account [--root DIR] init | add [--admin] NAME [FULL-NAME [admin|standard]] | remove [--remove-home] NAME | passwd NAME | admin NAME on|off | lock NAME on|off | rename NAME FULL-NAME | make-home NAME | list | check')
	exit(2)
}

// One line from standard input: a password someone chose. Empty when there
// is none to read.
fn read_password() []u8 {
	mut line := []u8{cap: 64}
	mut one := [1]u8{}
	for line.len <= accountcore.max_password {
		if C.read(0, &one[0], 1) != 1 || one[0] == `\n` {
			break
		}
		line << one[0]
	}
	return line
}

fn chown_tree(path string, uid u32, gid u32) {
	C.lchown(&char(path.str), uid, gid)
	if os.is_link(path) || !os.is_dir(path) {
		return
	}
	entries := os.ls(path) or { return }
	for entry in entries {
		chown_tree(os.join_path(path, entry), uid, gid)
	}
}

// The home of an account: its directory, private to it, and the usual
// folders. What is already there is kept and only given to its owner.
fn (t Tool) make_home(user accountcore.User) ! {
	home := t.root + user.home
	os.mkdir_all(os.dir(home), mode: 0o755) or {}
	if os.is_link(home) {
		// The desktop's link into /root/home: the home is now the real
		// directory behind /home, or is about to be made.
		os.rm(home) or {}
	}
	if !os.is_dir(home) {
		os.mkdir(home, mode: 0o700) or { return error('cannot create ${home}') }
	}
	os.chmod(home, 0o700) or { return error('cannot protect ${home}') }
	for folder in home_folders {
		path := os.join_path(home, folder)
		if !os.exists(path) {
			os.mkdir(path, mode: 0o755) or {}
		}
	}
	chown_tree(home, user.uid, user.gid)
}

// A system whose only persistent directory is /root keeps homes in
// /root/home. Nobody but root can pass through /root, so that directory is
// mounted at /home, where the accounts say the homes are.
fn (t Tool) attach_legacy_homes() {
	if t.root != '' {
		return
	}
	entries := os.ls(legacy_homes) or { return }
	if entries.len == 0 {
		return
	}
	os.mkdir_all('/home', mode: 0o755) or {}
	// Anything under /home that links into the old place would hide what
	// the mount brings.
	for entry in os.ls('/home') or { []string{} } {
		path := os.join_path('/home', entry)
		if os.is_link(path) {
			os.rm(path) or {}
		}
	}
	os.chmod(legacy_homes, 0o755) or {}
	$if linux {
		// MS_BIND.
		if C.mount(c'/root/home', c'/home', c'', u64(4096), unsafe { nil }) != 0 {
			eprintln('vinix-account: cannot mount ${legacy_homes} on /home')
		}
	}
}

fn (t Tool) init() ! {
	held := t.store.lock(true)!
	defer { held.release() }
	if !os.exists(t.store.shadow_path()) {
		os.write_file(t.store.shadow_path(), '')!
		os.chmod(t.store.shadow_path(), 0o600)!
	}
	mut db := t.store.load()!
	db.ensure_system_accounts()!
	mut imported := ''
	record_path := t.root + registration_record
	if db.people().len == 0 && os.is_file(record_path) {
		record := os.read_file(record_path) or { '' }
		if display, hash := accountcore.import_registration(record) {
			mut name := accountcore.login_name_for(display)
			db.add_user(name: name, gecos: display.replace(',', ' ').replace(':', ' '), admin: true, hash: hash) or {
				name = 'user'
				db.add_user(name: name, gecos: 'User', admin: true, hash: hash)!
			}
			imported = name
		} else {
			eprintln('vinix-account: ${record_path} is not a registration record; ignored')
		}
	}
	t.store.save(db)!
	t.attach_legacy_homes()
	for user in db.people() {
		t.make_home(user) or { eprintln('vinix-account: ${err.msg()}') }
	}
	if imported != '' {
		println('vinix-account: ${imported} is now an account, with the password it was registered with')
	}
	C.sync()
}

fn (t Tool) add(arguments []string) ! {
	mut rest := arguments.clone()
	mut admin := false
	if rest.len > 0 && rest[0] == '--admin' {
		admin = true
		rest = rest[1..].clone()
	}
	if rest.len < 1 || rest.len > 3 {
		usage()
	}
	name := rest[0]
	gecos := if rest.len > 1 { rest[1] } else { '' }
	if rest.len > 2 {
		match rest[2] {
			'admin' { admin = true }
			'standard' {}
			else { usage() }
		}
	}
	mut password := read_password()
	mut hash := ''
	if password.len > 0 {
		accountcore.check_new_password(name, password)!
		hash = accountcore.hash_password(password, t.cost)!
		accountcore.wipe(mut password)
	}
	held := t.store.lock(true)!
	defer { held.release() }
	mut db := t.store.load()!
	user := db.add_user(name: name, gecos: gecos, admin: admin, hash: hash)!
	t.store.save(db)!
	t.make_home(user)!
	C.sync()
}

fn (t Tool) remove(arguments []string) ! {
	mut rest := arguments.clone()
	mut remove_home := false
	if rest.len > 0 && rest[0] == '--remove-home' {
		remove_home = true
		rest = rest[1..].clone()
	}
	if rest.len != 1 {
		usage()
	}
	held := t.store.lock(true)!
	defer { held.release() }
	mut db := t.store.load()!
	user := db.user(rest[0]) or { return error('no user ${rest[0]}') }
	if !accountcore.is_person(user) {
		return error('${user.name} is not a person\'s account')
	}
	db.remove_user(user.name)!
	t.store.save(db)!
	if remove_home && user.home.starts_with('/home/') {
		os.rmdir_all(t.root + user.home) or {}
	}
	C.sync()
}

fn (t Tool) passwd(name string) ! {
	mut password := read_password()
	accountcore.check_new_password(name, password)!
	hash := accountcore.hash_password(password, t.cost)!
	accountcore.wipe(mut password)
	held := t.store.lock(true)!
	defer { held.release() }
	mut db := t.store.load()!
	current := db.shadow(name) or { accountcore.Shadow{} }
	db.set_hash(name, if accountcore.is_locked(current.hash) {
		accountcore.lock_prefix + hash
	} else {
		hash
	})!
	t.store.save(db)!
	C.sync()
}

fn on_off(word string) bool {
	if word != 'on' && word != 'off' {
		usage()
	}
	return word == 'on'
}

fn (t Tool) list() ! {
	db := t.store.load()!
	for user in db.people() {
		shadow := db.shadow(user.name) or { accountcore.Shadow{} }
		state := if accountcore.is_locked(shadow.hash) {
			'locked'
		} else if accountcore.has_password(shadow.hash) {
			'active'
		} else {
			'no-password'
		}
		kind := if db.is_admin(user) { 'admin' } else { 'standard' }
		println('${user.name}\t${user.uid}\t${kind}\t${state}\t${user.gecos}')
	}
}

fn main() {
	mut args := os.args[1..].clone()
	mut root := ''
	if args.len >= 2 && args[0] == '--root' {
		root = args[1].trim_right('/')
		args = args[2..].clone()
	}
	if args.len == 0 {
		usage()
	}
	if C.geteuid() != 0 && root == '' {
		fail('only root may change accounts; ask through vinix-auth')
	}
	tool := Tool{
		root:  root
		store: accountcore.Store{
			etc:   root + '/etc'
			owned: C.geteuid() == 0
		}
		cost:  accountcore.configured_cost(root + '/etc/vinix/auth.conf', C.geteuid() == 0) or {
			fail(err.msg())
			return
		}
	}
	command := args[0]
	rest := args[1..].clone()
	match command {
		'init' {
			tool.init() or { fail(err.msg()) }
		}
		'add' {
			tool.add(rest) or { fail(err.msg()) }
		}
		'remove' {
			tool.remove(rest) or { fail(err.msg()) }
		}
		'passwd' {
			if rest.len != 1 {
				usage()
			}
			tool.passwd(rest[0]) or { fail(err.msg()) }
		}
		'admin', 'lock', 'rename' {
			if rest.len != 2 {
				usage()
			}
			held := tool.store.lock(true) or {
				fail(err.msg())
				return
			}
			mut db := tool.store.load() or {
				fail(err.msg())
				return
			}
			match command {
				'admin' { db.set_admin(rest[0], on_off(rest[1])) or { fail(err.msg()) } }
				'lock' { db.set_locked(rest[0], on_off(rest[1])) or { fail(err.msg()) } }
				else { db.set_gecos(rest[0], rest[1]) or { fail(err.msg()) } }
			}
			tool.store.save(db) or { fail(err.msg()) }
			held.release()
			C.sync()
		}
		'make-home' {
			if rest.len != 1 {
				usage()
			}
			db := tool.store.load() or {
				fail(err.msg())
				return
			}
			user := db.user(rest[0]) or {
				fail('no user ${rest[0]}')
				return
			}
			tool.make_home(user) or { fail(err.msg()) }
		}
		'list' {
			tool.list() or { fail(err.msg()) }
		}
		'check' {
			tool.store.load() or { fail(err.msg()) }
			println('vinix-account: the account database is consistent')
		}
		else {
			usage()
		}
	}
}
