// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Changes to a database in memory. Each either happens whole or returns an
// error and leaves the database as it was; the caller holds the store's
// lock, loads, calls these and saves.
module accountcore

import time

// Names an account may not take: they are, or read as, something else.
const reserved_names = ['root', 'admin', 'administrator', 'daemon', 'nobody', 'system', 'vinix',
	'wheel', 'users', 'guest', 'operator', 'sudo', 'bin', 'sys', 'adm', 'tty', 'disk', 'audio',
	'video', 'input', 'kmem', 'shadow']

pub struct NewUser {
pub:
	name   string
	gecos  string
	home   string // '' for /home/<name>
	shell  string = '/bin/sh'
	admin  bool
	system bool // a service's account: a low id and no login
	// The password record, already hashed. '' makes an account nobody can
	// log in to until a password is set.
	hash string
}

fn today() string {
	return (time.now().unix() / 86400).str()
}

fn (db &Database) free_id(first u32, last u32) !u32 {
	mut id := first
	for id <= last {
		mut taken := false
		for user in db.users {
			if user.uid == id {
				taken = true
				break
			}
		}
		if !taken {
			for group in db.groups {
				if group.gid == id {
					taken = true
					break
				}
			}
		}
		if !taken {
			return id
		}
		id++
	}
	return error('no free id between ${first} and ${last}')
}

// Add a group, with the next free id of its range unless one is given.
pub fn (mut db Database) add_group(name string, system bool) !Group {
	if !valid_name(name) {
		return error('invalid group name')
	}
	if _ := db.group(name) {
		return error('group ${name} exists')
	}
	gid := if system {
		db.free_id(first_system_id, last_system_id)!
	} else {
		db.free_id(first_user_uid, last_user_uid)!
	}
	group := Group{
		name: name
		gid:  gid
	}
	db.groups << group
	return group
}

// Make sure a group the system relies on exists, with the id Alpine and
// Debian give it when that id is free.
pub fn (mut db Database) ensure_group(name string, preferred u32) !Group {
	if group := db.group(name) {
		return group
	}
	mut gid := preferred
	if _ := db.group_by_gid(gid) {
		gid = db.free_id(first_system_id, last_system_id)!
	}
	group := Group{
		name: name
		gid:  gid
	}
	db.groups << group
	return group
}

pub fn (mut db Database) add_member(group_name string, user_name string) ! {
	if _ := db.user(user_name) {
	} else {
		return error('no user ${user_name}')
	}
	for mut group in db.groups {
		if group.name == group_name {
			if user_name in group.members {
				return
			}
			if group.members.len >= max_members {
				return error('group ${group_name} is full')
			}
			group.members << user_name
			return
		}
	}
	return error('no group ${group_name}')
}

pub fn (mut db Database) remove_member(group_name string, user_name string) ! {
	for mut group in db.groups {
		if group.name == group_name {
			group.members = group.members.filter(it != user_name)
			return
		}
	}
	return error('no group ${group_name}')
}

// How many people could still administer the machine if `without` could not.
fn (db &Database) other_admins(without string) int {
	mut count := 0
	for user in db.people() {
		if user.name == without || !db.is_admin(user) {
			continue
		}
		shadow := db.shadow(user.name) or { continue }
		if has_password(shadow.hash) {
			count++
		}
	}
	return count
}

// Add an account with a primary group of its own.
pub fn (mut db Database) add_user(new NewUser) !User {
	if !valid_name(new.name) {
		return error('invalid user name: use lower-case letters, digits, - and _, starting with a letter')
	}
	if new.name in reserved_names {
		return error('the name ${new.name} is reserved')
	}
	if _ := db.user(new.name) {
		return error('user ${new.name} exists')
	}
	if _ := db.group(new.name) {
		return error('a group named ${new.name} exists')
	}
	if !valid_field(new.gecos, max_gecos) || new.gecos.contains(',') {
		return error('invalid full name')
	}
	home := if new.home == '' { '/home/${new.name}' } else { new.home }
	if !valid_path(home) {
		return error('invalid home directory')
	}
	if new.shell != '' && !valid_path(new.shell) {
		return error('invalid shell')
	}
	if new.hash != '' && !has_password(new.hash) {
		return error('invalid password record')
	}
	mut next := db
	next.users = db.users.clone()
	next.groups = db.groups.clone()
	next.shadows = db.shadows.filter(it.name != new.name)
	id := if new.system {
		next.free_id(first_system_id, last_system_id)!
	} else {
		next.free_id(first_user_uid, last_user_uid)!
	}
	user := User{
		name:  new.name
		uid:   id
		gid:   id
		gecos: new.gecos
		home:  home
		shell: if new.system { '/sbin/nologin' } else { new.shell }
	}
	next.groups << Group{
		name: new.name
		gid:  id
	}
	next.users << user
	next.shadows << Shadow{
		name:    new.name
		hash:    if new.hash == '' || new.system { no_login } else { new.hash }
		changed: today()
		ageing:  ['', '', '', '', '', '']
	}
	if !new.system {
		next.ensure_group(people_group, 100)!
		next.add_member(people_group, new.name)!
		if new.admin {
			next.ensure_group(admin_group, 10)!
			next.add_member(admin_group, new.name)!
		}
	}
	next.validate()!
	db = next
	return user
}

// Remove an account, its own group and its memberships. The last person who
// can administer the machine cannot be removed: there would be nobody left
// to add another.
pub fn (mut db Database) remove_user(name string) ! {
	user := db.user(name) or { return error('no user ${name}') }
	if user.uid == uid_root {
		return error('root cannot be removed')
	}
	if db.is_admin(user) && is_person(user) && db.other_admins(name) == 0 {
		return error('${name} is the only administrator')
	}
	db.users = db.users.filter(it.name != name)
	db.shadows = db.shadows.filter(it.name != name)
	mut groups := []Group{cap: db.groups.len}
	for group in db.groups {
		// The user's own group goes with them, unless someone else was put
		// in it or has it as a primary group.
		if group.name == name && group.gid == user.gid {
			others := group.members.filter(it != name)
			mut shared := others.len > 0
			for other in db.users {
				if other.gid == group.gid {
					shared = true
				}
			}
			if !shared {
				continue
			}
		}
		groups << Group{
			name:    group.name
			gid:     group.gid
			members: group.members.filter(it != name)
		}
	}
	db.groups = groups
}

// Replace an account's password record.
pub fn (mut db Database) set_hash(name string, hash string) ! {
	if _ := db.user(name) {
	} else {
		return error('no user ${name}')
	}
	if !valid_field(hash, max_hash) {
		return error('invalid password record')
	}
	for mut shadow in db.shadows {
		if shadow.name == name {
			shadow.hash = hash
			shadow.changed = today()
			return
		}
	}
	db.shadows << Shadow{
		name:    name
		hash:    hash
		changed: today()
		ageing:  ['', '', '', '', '', '']
	}
}

// Lock an account: its password stops matching but is kept, so unlocking
// gives back the same password.
pub fn (mut db Database) set_locked(name string, locked bool) ! {
	user := db.user(name) or { return error('no user ${name}') }
	if locked && db.is_admin(user) && is_person(user) && db.other_admins(name) == 0 {
		return error('${name} is the only administrator')
	}
	for mut shadow in db.shadows {
		if shadow.name == name {
			if locked && !is_locked(shadow.hash) {
				shadow.hash = lock_prefix + shadow.hash
			} else if !locked {
				shadow.hash = shadow.hash.trim_left(lock_prefix)
			}
			return
		}
	}
	if locked {
		return
	}
	return error('${name} has no password to unlock')
}

pub fn (mut db Database) set_admin(name string, admin bool) ! {
	user := db.user(name) or { return error('no user ${name}') }
	if !is_person(user) {
		return error('${name} is not a person\'s account')
	}
	if admin {
		db.ensure_group(admin_group, 10)!
		db.add_member(admin_group, name)!
		return
	}
	if db.is_admin(user) && db.other_admins(name) == 0 {
		return error('${name} is the only administrator')
	}
	db.remove_member(admin_group, name) or {}
}

pub fn (mut db Database) set_gecos(name string, gecos string) ! {
	if !valid_field(gecos, max_gecos) || gecos.contains(',') {
		return error('invalid full name')
	}
	for mut user in db.users {
		if user.name == name {
			user.gecos = gecos
			return
		}
	}
	return error('no user ${name}')
}

// The accounts and groups every Vinix system has, added to a database that
// lacks them and left alone where they exist. `greeter` is what the login
// screen runs as: it must be able to draw and read the keyboard, and must
// not be able to do anything else.
pub fn (mut db Database) ensure_system_accounts() ! {
	if _ := db.user_by_uid(uid_root) {
	} else {
		return error('the database has no root account')
	}
	db.ensure_group(admin_group, 10)!
	db.ensure_group(people_group, 100)!
	if _ := db.user('nobody') {
	} else {
		if _ := db.group_by_gid(id_nobody) {
		} else {
			db.groups << Group{
				name: if _ := db.group('nobody') { 'nogroup' } else { 'nobody' }
				gid:  id_nobody
			}
		}
		if _ := db.user_by_uid(id_nobody) {
		} else {
			db.users << User{
				name:  'nobody'
				uid:   id_nobody
				gid:   id_nobody
				gecos: 'nobody'
				home:  '/'
				shell: '/sbin/nologin'
			}
		}
	}
	if _ := db.user('greeter') {
	} else {
		db.users = db.users.clone()
		db.shadows = db.shadows.filter(it.name != 'greeter')
		id := db.free_id(first_system_id, last_system_id)!
		db.groups << Group{
			name: if _ := db.group('greeter') { '_greeter' } else { 'greeter' }
			gid:  id
		}
		db.users << User{
			name:  'greeter'
			uid:   id
			gid:   id
			gecos: 'Login screen'
			home:  '/run/vinix/greeter'
			shell: '/sbin/nologin'
		}
		db.shadows << Shadow{
			name:    'greeter'
			hash:    no_login
			changed: today()
			ageing:  ['', '', '', '', '', '']
		}
	}
	// Root is reached through an administrator's own password, never with
	// one of its own: a record that is not already a real password becomes
	// one nothing matches.
	mut found := false
	for mut shadow in db.shadows {
		if shadow.name == 'root' {
			found = true
			if !has_password(shadow.hash) && !is_locked(shadow.hash) {
				shadow.hash = no_login
			}
		}
	}
	if !found {
		root := db.user_by_uid(uid_root) or { return error('the database has no root account') }
		db.shadows << Shadow{
			name:    root.name
			hash:    no_login
			changed: today()
			ageing:  ['', '', '', '', '', '']
		}
	}
	db.validate()!
}
