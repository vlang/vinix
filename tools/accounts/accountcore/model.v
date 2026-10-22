// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The account database: users, groups and the password records that go with
// them, as the three files a Unix system keeps in /etc. This module reads,
// checks and writes them and knows nothing about who is asking: the programs
// that use it (vinix-account, vinix-authd, vinix-session) decide that.
module accountcore

// Identifiers. A person's account is one of first_user_uid..last_user_uid;
// what the system itself runs as is below that.
pub const uid_root = u32(0)
pub const first_system_id = u32(100)
pub const last_system_id = u32(999)
pub const first_user_uid = u32(1000)
pub const last_user_uid = u32(59999)
pub const id_nobody = u32(65534)

// Members of this group may ask for privileged actions with their own
// password; nobody else may.
pub const admin_group = 'wheel'

// The group every person's account is given as its own primary group is
// named after the user. `users` is the group all of them are also in.
pub const people_group = 'users'

pub const max_name = 32
pub const max_gecos = 128
pub const max_path = 255
pub const max_line = 8192
pub const max_file = 1024 * 1024
pub const max_entries = 4096
pub const max_members = 256

pub struct User {
pub mut:
	name  string
	uid   u32
	gid   u32
	gecos string // the name a person is shown by
	home  string
	shell string
}

pub struct Group {
pub mut:
	name    string
	gid     u32
	members []string
}

// A shadow record. Only `hash` and `changed` mean anything to Vinix; the
// ageing fields are kept as they were read so that a file another tool wrote
// is written back unchanged.
pub struct Shadow {
pub mut:
	name    string
	hash    string
	changed string // days since 1970 of the last password change
	ageing  []string // the six fields after it
}

pub struct Database {
pub mut:
	users   []User
	groups  []Group
	shadows []Shadow
}

// A login name: a lower-case letter or underscore, then letters, digits,
// underscores and hyphens. Nothing a shell, a path or one of these files
// would read as anything but a name.
pub fn valid_name(name string) bool {
	if name.len == 0 || name.len > max_name {
		return false
	}
	first := name[0]
	if !((first >= `a` && first <= `z`) || first == `_`) {
		return false
	}
	for i in 1 .. name.len {
		ch := name[i]
		if !((ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) || ch == `_` || ch == `-`) {
			return false
		}
	}
	return true
}

// Whether `text` may be one field of a line: no colon, no line break, no
// control character and nothing that is not valid UTF-8.
pub fn valid_field(text string, limit int) bool {
	if text.len > limit {
		return false
	}
	for i in 0 .. text.len {
		ch := text[i]
		if ch == `:` || ch < 0x20 || ch == 0x7f {
			return false
		}
	}
	return valid_utf8(text)
}

fn valid_utf8(text string) bool {
	mut i := 0
	for i < text.len {
		ch := text[i]
		mut more := 0
		if ch < 0x80 {
			more = 0
		} else if ch & 0xe0 == 0xc0 && ch >= 0xc2 {
			more = 1
		} else if ch & 0xf0 == 0xe0 {
			more = 2
		} else if ch & 0xf8 == 0xf0 && ch <= 0xf4 {
			more = 3
		} else {
			return false
		}
		if i + more >= text.len {
			return false
		}
		for k in 1 .. more + 1 {
			if text[i + k] & 0xc0 != 0x80 {
				return false
			}
		}
		i += more + 1
	}
	return true
}

// An absolute path with no empty, `.` or `..` component.
pub fn valid_path(path string) bool {
	if path.len < 1 || path.len > max_path || path[0] != `/` || !valid_field(path, max_path) {
		return false
	}
	if path == '/' {
		return true
	}
	mut start := 1
	for i in 1 .. path.len + 1 {
		if i < path.len && path[i] != `/` { continue }
		length := i - start
		if length == 0 || (length == 1 && path[start] == `.`)
			|| (length == 2 && path[start] == `.` && path[start + 1] == `.`) { return false }
		start = i + 1
	}
	return true
}

pub fn (db &Database) user(name string) ?User {
	for user in db.users {
		if user.name == name {
			return user
		}
	}
	return none
}

pub fn (db &Database) user_by_uid(uid u32) ?User {
	for user in db.users {
		if user.uid == uid {
			return user
		}
	}
	return none
}

pub fn (db &Database) group(name string) ?Group {
	for group in db.groups {
		if group.name == name {
			return group
		}
	}
	return none
}

pub fn (db &Database) group_by_gid(gid u32) ?Group {
	for group in db.groups {
		if group.gid == gid {
			return group
		}
	}
	return none
}

pub fn (db &Database) shadow(name string) ?Shadow {
	for shadow in db.shadows {
		if shadow.name == name {
			return shadow
		}
	}
	return none
}

// Every group id a user holds besides the primary one, in the order of the
// group file and without repeats.
pub fn (db &Database) supplementary_gids(user User) []u32 {
	mut gids := []u32{}
	for group in db.groups {
		if group.gid == user.gid || group.gid in gids {
			continue
		}
		if user.name in group.members {
			gids << group.gid
		}
	}
	return gids
}

pub fn (db &Database) in_group(user User, group_name string) bool {
	group := db.group(group_name) or { return false }
	return group.gid == user.gid || user.name in group.members
}

// Whether a user may ask for privileged actions. Root may; so may a member
// of the admin group, by membership and not by a primary group id that a
// carelessly made account might share.
pub fn (db &Database) is_admin(user User) bool {
	if user.uid == uid_root {
		return true
	}
	group := db.group(admin_group) or { return false }
	return user.name in group.members
}

// Whether an account belongs to a person rather than to a service.
pub fn is_person(user User) bool {
	return user.uid >= first_user_uid && user.uid <= last_user_uid
}

// The accounts a login screen offers.
pub fn (db &Database) people() []User {
	mut people := []User{}
	for user in db.users {
		if is_person(user) {
			people << user
		}
	}
	return people
}

// What must hold of a database before it is acted on or written: names and
// ids that are unique and well formed, and no reference to something that is
// not there. Anything else is refused rather than repaired, because a file
// that fails this was not written by these tools.
pub fn (db &Database) validate() ! {
	if db.users.len > max_entries || db.groups.len > max_entries || db.shadows.len > max_entries {
		return error('too many entries')
	}
	mut names := map[string]bool{}
	mut uids := map[u32]bool{}
	defer { unsafe { names.free(); uids.free() } }
	for user in db.users {
		if !valid_name(user.name) {
			name := printable(user.name)
			defer { unsafe { name.free() } }
			return error('invalid user name "${name}"')
		}
		if user.name in names {
			return error('user ${user.name} is listed twice')
		}
		if user.uid in uids {
			number := user.uid.str()
			defer { unsafe { number.free() } }
			return error('uid ${number} is used twice')
		}
		if !valid_field(user.gecos, max_gecos) {
			return error('user ${user.name}: invalid description')
		}
		if !valid_path(user.home) {
			return error('user ${user.name}: invalid home directory')
		}
		if user.shell != '' && !valid_path(user.shell) {
			return error('user ${user.name}: invalid shell')
		}
		names[user.name] = true
		uids[user.uid] = true
	}
	mut group_names := map[string]bool{}
	mut gids := map[u32]bool{}
	defer { unsafe { group_names.free(); gids.free() } }
	for group in db.groups {
		if !valid_name(group.name) {
			name := printable(group.name)
			defer { unsafe { name.free() } }
			return error('invalid group name "${name}"')
		}
		if group.name in group_names {
			return error('group ${group.name} is listed twice')
		}
		if group.gid in gids {
			number := group.gid.str()
			defer { unsafe { number.free() } }
			return error('gid ${number} is used twice')
		}
		if group.members.len > max_members {
			return error('group ${group.name} has too many members')
		}
		mut seen := map[string]bool{}
		defer { unsafe { seen.free() } }
		for member in group.members {
			if !valid_name(member) {
				return error('group ${group.name}: invalid member name')
			}
			if member in seen {
				return error('group ${group.name} lists ${member} twice')
			}
			seen[member] = true
		}
		group_names[group.name] = true
		gids[group.gid] = true
	}
	for user in db.users {
		if user.gid !in gids {
			number := user.gid.str()
			defer { unsafe { number.free() } }
			return error('user ${user.name}: primary group ${number} does not exist')
		}
	}
	mut shadow_names := map[string]bool{}
	defer { unsafe { shadow_names.free() } }
	for shadow in db.shadows {
		if !valid_name(shadow.name) {
			return error('invalid name in the password file')
		}
		if shadow.name in shadow_names {
			return error('password of ${shadow.name} is listed twice')
		}
		if !valid_field(shadow.hash, max_hash) || !valid_field(shadow.changed, 20) {
			return error('password of ${shadow.name}: invalid record')
		}
		if shadow.ageing.len != 6 {
			return error('password of ${shadow.name}: wrong number of fields')
		}
		for field in shadow.ageing {
			if !valid_field(field, 20) {
				return error('password of ${shadow.name}: invalid record')
			}
		}
		shadow_names[shadow.name] = true
	}
}

// A name that failed validation, made safe to put in a message.
fn printable(text string) string {
	mut out := []u8{cap: text.len}
	defer { unsafe { out.free() } }
	for i in 0 .. text.len {
		if i == 40 {
			break
		}
		ch := text[i]
		out << if ch >= 0x20 && ch < 0x7f { ch } else { `?` }
	}
	return out.bytestr()
}
