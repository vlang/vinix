// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the authentication service decides. A request arrives with the
// identity of the process that sent it, which the kernel vouches for
// (SO_PEERCRED) and the request cannot claim; this module turns the two into
// a reply, and, for an allowed action, into one program started as root.
//
// The rules, in one place:
//
//	- A password is only ever checked for the caller's own account, except
//	  that root may check anyone's: that is what a login is. The login
//	  screen is not root; it hands what was typed to the session manager,
//	  which asks.
//	- Wrong passwords for an account make the next tries for it wait
//	  (accountcore's throttle), whoever sent them.
//	- An action is allowed to root; to the person at the machine without a
//	  password if the action says `session`; to a member of the admin group
//	  with their own password; and, if it says `self`, to anyone with their
//	  own password. To nobody else, and never with someone else's password.
//	  An explicit `account` action uses a known ordinary peer without a
//	  password; its fixed program must bound the public operation itself.
//	- Every decision is written to the log, with who asked.
module authcore

import accountcore
import authproto
import os
import time

#include <fcntl.h>
#include <unistd.h>

pub struct Peer {
pub:
	pid int
	uid u32
	gid u32
}

pub struct RunResult {
pub:
	started bool
	status  int
	output  []u8
}

pub struct Env {
pub:
	store    accountcore.Store
	throttle accountcore.Throttle
	// Where the action files are, the file naming the uid of the person at
	// the machine, and the log.
	actions string = '/usr/share/vinix/actions'
	session string = '/run/vinix/session/active'
	log     string = '/var/log/vinix/auth.log'
	// Where the kernel takes reports of a service's decisions, so that they
	// are in one stream with its own (kernel/security/events.v); '' for none.
	events  string = '/proc/security_events'
	cost    accountcore.Cost = accountcore.default_cost
	clock   fn () i64 = wall_clock
	runner  fn (action Action, argv []string, input []u8, peer Peer, user string) RunResult = run_action
}

pub fn wall_clock() i64 {
	return time.now().unix()
}

fn reply(status u16, fields ...string) authproto.Frame {
	return authproto.text_frame(status, ...fields)
}

// One line in the log. What is written was either validated as a name or is
// made printable here; nothing a caller sends can start a second line.
fn (env Env) record(peer Peer, what string, result string) {
	mut clean := []u8{cap: what.len}
	for i in 0 .. what.len {
		if i == 200 {
			break
		}
		ch := what[i]
		clean << if ch >= 0x20 && ch < 0x7f { ch } else { `?` }
	}
	line := '${env.clock()} pid=${peer.pid} uid=${peer.uid} ${clean.bytestr()}: ${result}\n'
	os.mkdir_all(os.dir(env.log), mode: 0o700) or {}
	mut file := os.open_file(env.log, 'a', 0o600) or { return }
	file.write_string(line) or {}
	file.close()
	env.report(peer, clean.bytestr(), result)
}

// The same decision, to the kernel's stream: about the caller's process,
// which the kernel attributes to its login. One write is one report.
fn (env Env) report(peer Peer, what string, result string) {
	if env.events == '' || peer.pid <= 0 {
		return
	}
	outcome := result.all_before(':')
	allowed := outcome == 'ok' || outcome == 'changed' || outcome == 'exit 0'
	text := '${peer.pid} ${if allowed { 0 } else { 1 }} auth:${what}:${outcome}'
	fd := C.open(&char(env.events.str), C.O_WRONLY)
	if fd < 0 {
		return
	}
	C.write(fd, text.str, usize(if text.len > 120 { 120 } else { text.len }))
	C.close(fd)
}

fn (env Env) load_action(name string) !Action {
	if !valid_action_name(name) {
		return error('invalid action name')
	}
	// The directory must be as trustworthy as the files in it: whoever can
	// write it can replace them.
	info := os.lstat(env.actions) or { return error('no action directory') }
	if info.get_filetype() != .directory || info.mode & 0o022 != 0
		|| (env.store.owned && info.uid != 0) {
		return error('the action directory is not root\'s alone')
	}
	text := accountcore.read_trusted(os.join_path(env.actions, name), false, env.store.owned)!
	return parse_action(name, text)
}

// The uid of the person at the machine, as the session manager wrote it.
fn (env Env) session_uid() ?u32 {
	text := accountcore.read_trusted(env.session, false, env.store.owned) or { return none }
	trimmed := text.trim_space()
	if trimmed.len == 0 || trimmed.len > 10 {
		return none
	}
	for i in 0 .. trimmed.len {
		if trimmed[i] < `0` || trimmed[i] > `9` {
			return none
		}
	}
	return u32(trimmed.u64())
}

fn (env Env) load() !accountcore.Database {
	held := env.store.lock(false)!
	defer { held.release() }
	return env.store.load()
}

// Check `password` for `user`, with the throttle. Returns the status to
// reply with and, for a wait, the seconds.
fn (env Env) check_password(db accountcore.Database, user accountcore.User, password []u8) (u16, i64) {
	now := env.clock()
	wait := accountcore.wait_for(env.throttle.read(user.name, now), now)
	if wait > 0 {
		return authproto.status_wait, wait
	}
	shadow := db.shadow(user.name) or { accountcore.Shadow{} }
	if !accountcore.verify_password_at(shadow.hash, password, env.cost) {
		env.throttle.record_failure(user.name, now)
		return authproto.status_denied, 0
	}
	env.throttle.record_success(user.name)
	if accountcore.needs_rehash(shadow.hash, env.cost) {
		env.rehash(user.name, shadow.hash, password)
	}
	return authproto.status_ok, 0
}

// Replace a record made at a lower cost, now that the password is at hand.
// Failing to is not a reason to refuse the login.
fn (env Env) rehash(name string, old_hash string, password []u8) {
	hash := accountcore.hash_password(password, env.cost) or { return }
	held := env.store.lock(true) or { return }
	defer { held.release() }
	mut db := env.store.load() or { return }
	current := db.shadow(name) or { return }
	// Only if nobody changed the password in between.
	if current.hash != old_hash {
		return
	}
	db.set_hash(name, hash) or { return }
	env.store.save(db) or {}
}

fn (env Env) info(peer Peer) authproto.Frame {
	db := env.load() or { return reply(authproto.status_failed, 'the account database is unreadable') }
	user := db.user_by_uid(peer.uid) or { return reply(authproto.status_denied, 'unknown user') }
	at_machine := if uid := env.session_uid() { uid == peer.uid } else { false }
	return reply(authproto.status_ok, user.name, if db.is_admin(user) { '1' } else { '0' },
		if at_machine { '1' } else { '0' }, user.gecos)
}

fn (env Env) verify(peer Peer, request authproto.Frame) authproto.Frame {
	if request.fields.len != 2 {
		return reply(authproto.status_invalid, 'verify takes a user and a password')
	}
	name := request.text(0)
	if !accountcore.valid_name(name) {
		return reply(authproto.status_invalid, 'invalid user name')
	}
	db := env.load() or { return reply(authproto.status_failed, 'the account database is unreadable') }
	mut may_ask := peer.uid == accountcore.uid_root
	user := db.user(name) or {
		if may_ask {
			// The same work as for an account that exists.
			accountcore.verify_password_at('', request.fields[1], env.cost)
			env.record(peer, 'verify ${name}', 'denied: no such user')
		}
		return reply(authproto.status_denied)
	}
	if user.uid == peer.uid {
		may_ask = true
	}
	if !may_ask {
		env.record(peer, 'verify ${name}', 'denied: not the caller\'s account')
		return reply(authproto.status_denied)
	}
	status, wait := env.check_password(db, user, request.fields[1])
	match status {
		authproto.status_ok {
			env.record(peer, 'verify ${name}', 'ok')
			return reply(authproto.status_ok, user.name, user.uid.str())
		}
		authproto.status_wait {
			env.record(peer, 'verify ${name}', 'wait ${wait}s')
			return reply(authproto.status_wait, wait.str())
		}
		else {
			env.record(peer, 'verify ${name}', 'denied: wrong password')
			return reply(authproto.status_denied)
		}
	}
}

fn (env Env) change_password(peer Peer, request authproto.Frame) authproto.Frame {
	if request.fields.len != 3 {
		return reply(authproto.status_invalid, 'expected a user, the old and the new password')
	}
	name := request.text(0)
	if !accountcore.valid_name(name) {
		return reply(authproto.status_invalid, 'invalid user name')
	}
	db := env.load() or { return reply(authproto.status_failed, 'the account database is unreadable') }
	user := db.user(name) or { return reply(authproto.status_denied) }
	if peer.uid != accountcore.uid_root {
		if user.uid != peer.uid {
			env.record(peer, 'password ${name}', 'denied: not the caller\'s account')
			return reply(authproto.status_denied)
		}
		status, wait := env.check_password(db, user, request.fields[1])
		if status == authproto.status_wait {
			env.record(peer, 'password ${name}', 'wait ${wait}s')
			return reply(authproto.status_wait, wait.str())
		}
		if status != authproto.status_ok {
			env.record(peer, 'password ${name}', 'denied: wrong password')
			return reply(authproto.status_denied)
		}
		if request.fields[1] == request.fields[2] {
			return reply(authproto.status_invalid, 'the new password is the old one')
		}
	}
	accountcore.check_new_password(name, request.fields[2]) or {
		return reply(authproto.status_invalid, err.msg())
	}
	hash := accountcore.hash_password(request.fields[2], env.cost) or {
		return reply(authproto.status_failed, err.msg())
	}
	held := env.store.lock(true) or { return reply(authproto.status_failed, err.msg()) }
	defer { held.release() }
	mut fresh := env.store.load() or { return reply(authproto.status_failed, err.msg()) }
	// A locked account stays locked: changing the password is not the way
	// around a lock.
	current := fresh.shadow(name) or { accountcore.Shadow{} }
	stored := if accountcore.is_locked(current.hash) { accountcore.lock_prefix + hash } else { hash }
	fresh.set_hash(name, stored) or { return reply(authproto.status_failed, err.msg()) }
	env.store.save(fresh) or { return reply(authproto.status_failed, err.msg()) }
	env.record(peer, 'password ${name}', 'changed')
	return reply(authproto.status_ok)
}

// Whether `user` may run `action`, and whether a password is part of that:
// (allowed, password needed).
fn (env Env) may_run(db accountcore.Database, peer Peer, user accountcore.User, action Action) (bool, bool) {
	if peer.uid == accountcore.uid_root {
		return true, false
	}
	if !accountcore.is_person(user) {
		return false, false
	}
	match action.auth {
		.account { return true, false }
		.self {
			return true, true
		}
		.session {
			if uid := env.session_uid() {
				if uid == peer.uid {
					return true, false
				}
			}
			return db.is_admin(user), true
		}
		.admin {
			return db.is_admin(user), true
		}
	}
}

fn (env Env) describe(peer Peer, request authproto.Frame) authproto.Frame {
	if request.fields.len != 1 {
		return reply(authproto.status_invalid, 'describe takes an action')
	}
	action := env.load_action(request.text(0)) or { return reply(authproto.status_invalid, 'no such action') }
	db := env.load() or { return reply(authproto.status_failed, 'the account database is unreadable') }
	user := db.user_by_uid(peer.uid) or { return reply(authproto.status_denied, 'unknown user') }
	allowed, password := env.may_run(db, peer, user, action)
	return reply(authproto.status_ok, action.description, if allowed { '1' } else { '0' },
		if password { '1' } else { '0' })
}

fn (env Env) run(peer Peer, request authproto.Frame) authproto.Frame {
	if request.fields.len < 3 {
		return reply(authproto.status_invalid, 'run takes an action, a password and an input')
	}
	name := request.text(0)
	action := env.load_action(name) or {
		env.record(peer, 'run ${name}', 'invalid: ${err.msg()}')
		return reply(authproto.status_invalid, 'no such action')
	}
	mut supplied := []string{}
	for i in 3 .. request.fields.len {
		supplied << request.text(i)
	}
	argv := action.arguments(supplied) or {
		env.record(peer, 'run ${name}', 'invalid: ${err.msg()}')
		return reply(authproto.status_invalid, err.msg())
	}
	if request.fields[2].len > 0 && !action.input {
		return reply(authproto.status_invalid, '${name} takes no input')
	}
	db := env.load() or { return reply(authproto.status_failed, 'the account database is unreadable') }
	user := db.user_by_uid(peer.uid) or {
		env.record(peer, 'run ${name}', 'denied: unknown user')
		return reply(authproto.status_denied)
	}
	allowed, password := env.may_run(db, peer, user, action)
	if !allowed {
		env.record(peer, 'run ${name}', 'denied: ${user.name} may not')
		return reply(authproto.status_denied, 'not permitted')
	}
	if password {
		if request.fields[1].len == 0 {
			return reply(authproto.status_password_needed, action.description)
		}
		status, wait := env.check_password(db, user, request.fields[1])
		if status == authproto.status_wait {
			env.record(peer, 'run ${name}', 'wait ${wait}s')
			return reply(authproto.status_wait, wait.str())
		}
		if status != authproto.status_ok {
			env.record(peer, 'run ${name}', 'denied: wrong password')
			return reply(authproto.status_denied)
		}
	}
	result := env.runner(action, argv, request.fields[2], peer, user.name)
	if !result.started {
		env.record(peer, 'run ${name} as ${user.name}', 'failed to start')
		return reply(authproto.status_failed, 'the action could not be started')
	}
	env.record(peer, 'run ${name} as ${user.name}', 'exit ${result.status}')
	return authproto.Frame{
		code:   if result.status == 0 { authproto.status_ok } else { authproto.status_failed }
		fields: [result.status.str().bytes(), result.output]
	}
}

// Answer one request. The request is wiped before this returns.
pub fn handle(env Env, peer Peer, mut request authproto.Frame) authproto.Frame {
	defer { request.wipe() }
	return match request.code {
		authproto.op_info { env.info(peer) }
		authproto.op_verify { env.verify(peer, request) }
		authproto.op_change_password { env.change_password(peer, request) }
		authproto.op_describe { env.describe(peer, request) }
		authproto.op_run { env.run(peer, request) }
		else { reply(authproto.status_invalid, 'unknown request') }
	}
}
