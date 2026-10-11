// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module proc

// Login sessions, and the seat.
//
// A login session is what a person's processes have in common however many
// times they fork, exec, change group or start a session of the terminal
// kind: the uid that logged in and a number for that login. Both are set
// once, by the program that makes the session while it is still root
// (/proc/self/loginuid, as on Linux), and can never be set again, so
// nothing the session runs can relabel itself as another login or as none.
// Processes that belong to the system -- init, services, what they start --
// have no login: uid 4294967295 and session 0.
//
// The seat is the display, the keyboard, the pointer and the speakers: the
// devices of whoever is at the machine. One login session holds it at a
// time. A descriptor for a seat device works for the session that opened it
// while that session holds the seat, and stops working -- every read,
// write, ioctl and mapping -- the moment another does, without the
// descriptor being closed or the session being told: a session in the
// background must not see what is typed into the one in front. It works
// again when the seat comes back. The system's own descriptors, opened by
// root outside any login, always work for the system: the kernel console,
// init and the session manager are how the machine is recovered.

import errno
import katomic

pub const login_uid_unset = u32(0xffffffff)
pub const cap_audit_control = 30

__global (
	login_session_last u64
	seat_session_now   u64
)

// The uid that logged in and the login session of a process: unset and 0
// for one that belongs to the system or does not exist.
pub fn login_identity(pid int) (u32, u32) {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } {
		return login_uid_unset, 0
	}
	return process.login_uid, process.login_session
}

pub fn current_login_session() u32 {
	return current_thread().process.login_session
}

// Start a login session for the calling process as `uid`. Only a process
// may label itself, only as root with CAP_AUDIT_CONTROL outside any
// confinement, and only once.
pub fn start_login_session(pid int, uid u32) ? {
	mut caller := current_thread().process
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } || voidptr(process) != voidptr(caller) {
		errno.set(errno.eperm)
		return none
	}
	// A container's runtime writes its own idea of a login here. It is
	// taken and not acted on: a login is something the host has.
	if !is_initial_namespace(caller.ns.user) {
		return
	}
	if caller.euid != 0 || !has_capability(caller, cap_audit_control) || !mac_trusted() {
		errno.set(errno.eperm)
		return none
	}
	if uid == login_uid_unset {
		errno.set(errno.einval)
		return none
	}
	if caller.login_session != 0 {
		errno.set(errno.eperm)
		return none
	}
	caller.login_uid = uid
	// inc() returns what the counter was. Session 0 is "no login", so the
	// numbers start at 1 and skip 0 should the counter ever wrap.
	mut session := u32(katomic.inc(mut &login_session_last)) + 1
	if session == 0 {
		session = u32(katomic.inc(mut &login_session_last)) + 1
	}
	caller.login_session = session
}

// The login session that holds the seat, or 0 when none does.
pub fn seat_session() u32 {
	return u32(katomic.load(&seat_session_now))
}

pub fn set_seat_session(session u32) {
	katomic.store(mut &seat_session_now, u64(session))
}

// Whether the calling process may open a seat device: the session that
// holds the seat, or root outside any login.
pub fn seat_may_open() bool {
	process := current_thread().process
	if process.login_session == 0 {
		return process.euid == 0
	}
	return process.login_session == seat_session()
}

// Whether the calling process may use a descriptor that login session
// `owner` opened. A session's own descriptor works while that session
// holds the seat. One the system opened (owner 0) and handed down -- init's
// console, inherited by everything -- works for the system, and for a login
// session only while it holds the seat: inheriting a descriptor is not a
// way around not being at the machine.
pub fn seat_allows(owner u32) bool {
	seat := seat_session()
	if owner != 0 {
		return owner == seat
	}
	mine := current_thread().process.login_session
	return mine == 0 || mine == seat
}

// The real and effective uid of a process: 0 and 0 for one that is gone.
pub fn process_uids(pid int) (u32, u32) {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } {
		return 0, 0
	}
	return process.uid, process.euid
}
