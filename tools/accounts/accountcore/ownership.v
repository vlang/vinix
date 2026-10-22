// SPDX-License-Identifier: GPL-2.0-or-later
module accountcore

// Lookups borrow their strings from the database. A session that outlives its
// snapshot takes this independent copy and closes it when the session ends.
pub fn (user User) owned_copy() User {
	return User{ name: user.name.clone(), uid: user.uid, gid: user.gid,
		gecos: user.gecos.clone(), home: user.home.clone(), shell: user.shell.clone() }
}

pub fn (mut user User) close() {
	unsafe { user.name.free(); user.gecos.free(); user.home.free(); user.shell.free() }
	user = User{}
}

fn close_users(mut users []User) {
	for mut user in users { user.close() }
	unsafe { users.free() }
}

fn close_groups(mut groups []Group) {
	for mut group in groups {
		unsafe { group.name.free(); group.members.free() }
	}
	unsafe { groups.free() }
}

fn close_shadows(mut shadows []Shadow) {
	for mut shadow in shadows {
		unsafe { shadow.name.free(); shadow.hash.free(); shadow.changed.free(); shadow.ageing.free() }
	}
	unsafe { shadows.free() }
}

// Only the owner of a freshly loaded/parsed database closes it. Values returned
// by user(), group(), people() and shadow() remain borrowed until this call.
// people() owns only its array buffer; release that buffer without closing its
// borrowed User entries, or take owned_copy() for entries kept beyond the snapshot.
pub fn (mut db Database) close() {
	close_users(mut db.users)
	close_groups(mut db.groups)
	close_shadows(mut db.shadows)
	db = Database{}
}
