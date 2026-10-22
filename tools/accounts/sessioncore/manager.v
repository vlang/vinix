// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The session manager: what stands between the machine being on and a
// person using it. It shows the login screen, starts a session for whoever
// logs in, and comes back to the login screen when that session ends or
// its owner asks to let someone else in.
//
// It is root and stays root, so it does as little as it can. The login
// screen is another program, running as the `greeter` account, which can
// draw and read the keyboard and nothing else; it hands a name and a
// password to the manager over a socket, and the manager asks the
// authentication service. The login screen is never believed about who may
// log in -- only about what was typed.
//
// A session whose owner asked to switch is not ended. Its processes are
// stopped, every one, and the seat is taken from it; when its owner logs in
// again they are continued where they were. Stopped rather than left
// running because a session keeps the display's memory mapped, and the
// kernel does not take a mapping back when the seat moves.
//
// Both the login screen and a session talk to the manager on descriptor 3,
// in the frames of the authentication service (authproto):
//
//	from the login screen
//	  login USER PASSWORD   -> ok | denied | wait SECONDS | failed TEXT
//	  power off|restart     -> the machine goes down
//	from a session
//	  switch                -> the session is stopped; the login screen shows
//	  logout                -> the session's processes are ended
module sessioncore

import accountcore
import authclient
import authproto
import os

#include <sys/socket.h>
#include <signal.h>
#include <poll.h>
#include <sys/time.h>

fn C.socketpair(domain int, kind int, protocol int, fds &i32) int
fn C.kill(pid int, signal int) int
fn C.poll(fds voidptr, count u64, timeout int) int
fn C.usleep(microseconds u32) int
fn C.setsockopt(int, int, int, voidptr, u32) int
fn C.signal(int, voidptr) voidptr

struct ChannelTimeout {
	seconds      i64
	microseconds i64
}

// Borrow only the field's array header while copying its bytes. Calling a
// pointer receiver on a nested Frame field would promote the whole Frame to
// the heap in a manual-free build.
fn copy_login_field(field []u8) []u8 { return field.clone() }

fn login_field_text(field []u8) string { return field.bytestr() }

fn mark_active_uid(uid u32) {
	text := uid.str()
	mark_active(text)
	unsafe { text.free() }
}

__global manager_signal = i32(0)

fn manager_signal_handler(signal i32) { manager_signal = signal }

fn bound_channel(fd int) ! {
	timeout := ChannelTimeout{ seconds: 2 }
	if C.setsockopt(fd, C.SOL_SOCKET, C.SO_RCVTIMEO, &timeout, u32(sizeof(timeout))) != 0
		|| C.setsockopt(fd, C.SOL_SOCKET, C.SO_SNDTIMEO, &timeout, u32(sizeof(timeout))) != 0 {
		return error('cannot bound the session channel')
	}
}

pub const op_login = u16(64)
pub const op_power = u16(65)
pub const op_switch = u16(66)
pub const op_logout = u16(67)

struct PollFd {
mut:
	fd      i32
	events  i16
	revents i16
}

pub struct ManagerConfig {
pub:
	greeter []string // the login screen's program and arguments
	desktop []string // a session's first program and arguments
	greeter_fallback []string // tried in the same child only if execve fails
	desktop_fallback []string
	socket  string = authclient.default_socket
	system  string = '/usr/sbin/vinix-system'
	// Started in each new session with the password that was typed, to
	// open the account's credential store. Not started if it is not there.
	keyring []string = ['/usr/bin/vinix-keyring', 'daemon', '--unlock-stdin']
}

struct Session {
mut:
	user    accountcore.User
	pid     int // the session's first process
	session u32 // its login session
	control int = -1 // the manager's end of its line
	stopped bool
}

struct Manager {
	config ManagerConfig
mut:
	sessions []Session
}

fn load_accounts() !accountcore.Database {
	store := accountcore.Store{}
	held := store.lock(false)!
	defer { held.release() }
	// Session selection needs public account/group identities, never hashes.
	return store.load_public()
}

// The processes of a login session, as the kernel lists them.
fn session_pids(session u32) []int {
	mut pids := []int{}
	pids.flags |= .noslices
	entries := os.ls('/proc') or {
		discard_manager_error(err)
		return pids
	}
	defer { unsafe { entries.free() } }
	for entry in entries {
		pid := entry.int()
		if pid <= 1 {
			continue
		}
		path := '/proc/' + entry + '/sessionid'
		text := os.read_file(path) or {
			discard_manager_error(err)
			unsafe { path.free() }
			continue
		}
		unsafe { path.free() }
		trimmed := text.trim_space()
		matched := u32(trimmed.u64()) == session
		unsafe {
			trimmed.free()
			text.free()
		}
		if matched {
			pids << pid
		}
	}
	return pids
}

// Send `signal` to every process of a login session, again and again until
// a pass finds none that the one before had not: a process can fork between
// being listed and being signalled, and the child must not be missed. For a
// stop this ends because a stopped process cannot fork; for a kill, because
// a dead one cannot.
fn signal_session(session u32, signal int) {
	if session == 0 {
		return
	}
	mut seen := map[int]bool{}
	defer { unsafe { seen.free() } }
	for _ in 0 .. 50 {
		mut fresh := 0
		pids := session_pids(session)
		for pid in pids {
			if pid !in seen {
				fresh++
				seen[pid] = true
			}
			C.kill(pid, signal)
		}
		unsafe { pids.free() }
		if fresh == 0 {
			return
		}
	}
}

// End everything a login session still runs: ask, wait a little, insist.
fn end_session(session u32) {
	signal_session(session, C.SIGCONT)
	signal_session(session, C.SIGTERM)
	for _ in 0 .. 20 {
		pids := session_pids(session)
		empty := pids.len == 0
		unsafe { pids.free() }
		if empty {
			return
		}
		C.usleep(100_000)
	}
	signal_session(session, C.SIGKILL)
}

fn reply(fd int, status u16, text string) {
	mut frame := if text == '' {
		authproto.Frame{
			code: status
		}
	} else {
		authproto.text_frame(status, text)
	}
	authproto.write_frame(fd, frame) or { discard_manager_error(err) }
	frame.close()
}

// Whether there is something to read on `fd` within the time given.
fn readable(fd int, milliseconds int) bool {
	mut poll_fd := PollFd{
		fd:     i32(fd)
		events: 1
	}
	return C.poll(voidptr(&poll_fd), 1, milliseconds) > 0
}

fn (mut m Manager) find_session(uid u32) int {
	for index, session in m.sessions {
		if session.user.uid == uid {
			return index
		}
	}
	return -1
}

// Check a name and a password from the login screen. The answer is the
// frame to send back; the user is set when the answer is yes.
fn (m &Manager) check_login(request authproto.Frame) (authproto.Frame, ?accountcore.User) {
	if request.fields.len != 2 {
		return authproto.text_frame(authproto.status_invalid, 'login takes a user and a password'), none
	}
	name := login_field_text(request.fields[0])
	defer { unsafe { name.free() } }
	if !accountcore.valid_name(name) || request.fields[1].len == 0 || request.fields[1].len > 128 {
		return authproto.Frame{ code: authproto.status_denied }, none
	}
	mut answer := verify_login(m.config.socket, name, request.fields[1]) or {
		return manager_failure(err), none
	}
	if answer.code != authproto.status_ok {
		return answer, none
	}
	answer.close()
	mut db := load_accounts() or { return manager_failure(err), none }
	defer { db.close() }
	user := db.user(name) or {
		return authproto.Frame{
			code: authproto.status_denied
		}, none
	}
	// The password of an account that is not a person's, if it had one,
	// would still not be a way to a session.
	if !accountcore.is_person(user) {
		return authproto.Frame{
			code: authproto.status_denied
		}, none
	}
	return authproto.Frame{
		code: authproto.status_ok
	}, user.owned_copy()
}

// Show the login screen until someone has logged in, and return who, and
// the password they typed -- for their credential store, and to be wiped
// by the caller as soon as the session has been started.
fn (mut m Manager) greet() (accountcore.User, []u8) {
	for {
		if manager_signal != 0 { return accountcore.User{}, []u8{} }
		mut db := load_accounts() or {
			report_manager_error(err, 'vinix-session: ')
			C.usleep(2_000_000)
			continue
		}
		defer { db.close() }
		greeter := db.user('greeter') or {
			eprintln('vinix-session: there is no greeter account; run vinix-account init')
			C.usleep(2_000_000)
			continue
		}
		mut line := [2]i32{}
		if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &line[0]) != 0 {
			C.usleep(1_000_000)
			continue
		}
		bound_channel(int(line[0])) or {
			discard_manager_error(err)
			C.close(line[0])
			C.close(line[1])
			continue
		}
		mark_active('')
		started := start_fallback(db, greeter, m.config.greeter, m.config.greeter_fallback, true, int(line[1]), Unlock{}) or {
			report_manager_error(err, 'vinix-session: the login screen could not be started: ')
			C.close(line[0])
			C.close(line[1])
			C.usleep(2_000_000)
			continue
		}
		C.close(line[1])
		mut chosen := ?accountcore.User(none)
		mut typed := []u8{}
		for {
			if manager_signal != 0 { break }
			mut status := i32(0)
			if C.waitpid(started.pid, &status, C.WNOHANG) == started.pid { break }
			if !readable(int(line[0]), 500) { continue }
			mut request := authproto.read_frame(int(line[0])) or {
				discard_manager_error(err)
				break
			}
			match request.code {
				op_login {
					// A copy first: asking the service wipes what it was sent.
					mut password := if request.fields.len == 2 {
						copy_login_field(request.fields[1])
					} else {
						[]u8{}
					}
					mut answer, user := m.check_login(request)
					if _ := user {
						typed = unsafe { password }
					} else {
						accountcore.wipe(mut password)
						unsafe { password.free() }
					}
					request.close()
					authproto.write_frame(int(line[0]), answer) or { discard_manager_error(err) }
					answer.close()
					if who := user {
						chosen = who
						break
					}
				}
				op_power {
					what := if request.fields.len == 1 {
						login_field_text(request.fields[0])
					} else {
						''.clone()
					}
					request.close()
					if what == 'off' || what == 'restart' {
						reply(int(line[0]), authproto.status_ok, '')
						manager_signal = if what == 'off' { C.SIGUSR2 } else { C.SIGTERM }
						unsafe { what.free() }
						break
					}
					unsafe { what.free() }
					reply(int(line[0]), authproto.status_invalid, 'power off or restart')
				}
				else {
					request.close()
					reply(int(line[0]), authproto.status_invalid, 'unknown request')
				}
			}
		}
		C.close(line[0])
		// The login screen has done its part, or has gone wrong. Either
		// way nothing of it stays.
		end_session(started.session)
		wait(started.pid)
		release_seat(started.session)
		if who := chosen {
			return who, typed
		}
		// It ended without a login: show it again, but not in a tight loop.
		C.usleep(500_000)
	}
	return accountcore.User{}, []u8{}
}

// Run `user`'s session until it ends or steps aside: start it, or continue
// it if it was stopped.
fn (mut m Manager) prepare_session(user accountcore.User, typed []u8) ?int {
	// start() forks the unlock helper's address space. The root parent must
	// erase its copy before entering the potentially hours-long session loop.
	defer { retire_login_password(typed) }
	mut index := m.find_session(user.uid)
	if index >= 0 {
		// Theirs was waiting. The seat first: a continued process may use
		// the display at once.
		give_seat(m.sessions[index].session) or {
			report_manager_error(err, 'vinix-session: ')
			return none
		}
		mark_active_uid(user.uid)
		m.sessions[index].stopped = false
		signal_session(m.sessions[index].session, C.SIGCONT)
	} else {
		mut db := load_accounts() or {
			report_manager_error(err, 'vinix-session: ')
			return none
		}
		defer { db.close() }
		mut line := [2]i32{}
		if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &line[0]) != 0 {
			return none
		}
		bound_channel(int(line[0])) or {
			discard_manager_error(err)
			C.close(line[0])
			C.close(line[1])
			return none
		}
		started := start_fallback(db, user, m.config.desktop, m.config.desktop_fallback, true, int(line[1]), Unlock{
			secret: typed
			helper: m.config.keyring
		}) or {
			report_manager_error(err, 'vinix-session: ')
			C.close(line[0])
			C.close(line[1])
			return none
		}
		C.close(line[1])
		mark_active_uid(user.uid)
		m.sessions << Session{
			user:    user.owned_copy()
			pid:     started.pid
			session: started.session
			control: int(line[0])
		}
		index = m.sessions.len - 1
	}
	return index
}

fn (mut m Manager) attend(user accountcore.User, typed []u8) {
	index := m.prepare_session(user, typed) or { return }
	session := m.sessions[index]
	for {
		if manager_signal != 0 { break }
		// The session's first process ending is the session ending.
		mut status := i32(0)
		if C.waitpid(session.pid, &status, C.WNOHANG) == session.pid {
			break
		}
		if !readable(session.control, 500) {
			continue
		}
		mut request := authproto.read_frame(session.control) or {
			// A broken or stalled control line ends the seat owner. It must
			// not leave a compositor running while a new greeter takes over.
			discard_manager_error(err)
			break
		}
		code := request.code
		if code == op_power {
			what := if request.fields.len == 1 {
				login_field_text(request.fields[0])
			} else {
				''.clone()
			}
			request.close()
			if what == 'off' || what == 'restart' {
				reply(session.control, authproto.status_ok, '')
				manager_signal = if what == 'off' { C.SIGUSR2 } else { C.SIGTERM }
				unsafe { what.free() }
				break
			}
			unsafe { what.free() }
			reply(session.control, authproto.status_invalid, 'power off or restart')
			continue
		}
		valid := request.fields.len == 0
		request.close()
		if !valid {
			reply(session.control, authproto.status_invalid, 'unexpected fields')
			continue
		}
		if code == op_switch {
			// Away from the seat before the answer, stopped after it: the
			// session reads the answer when it is continued.
			release_seat(session.session)
			mark_active('')
			reply(session.control, authproto.status_ok, '')
			signal_session(session.session, C.SIGSTOP)
			m.sessions[index].stopped = true
			return
		}
		if code == op_logout {
			reply(session.control, authproto.status_ok, '')
			break
		}
		reply(session.control, authproto.status_invalid, 'unknown request')
	}
	// Over. Whatever the session left running goes with it.
	mark_active('')
	release_seat(session.session)
	end_session(session.session)
	C.close(session.control)
	// end_session has sent SIGKILL if the bounded graceful interval did not
	// finish. Retire our direct child before forgetting the session or
	// admitting another greeter; a nonblocking wait can leave its corpse.
	wait(session.pid)
	m.sessions[index].user.close()
	m.sessions.delete(index)
}

// A signal interrupts bounded channel waits. Revoke and end every owned login
// before returning to init or handing a fixed power request to the system tool.
pub fn run_manager(config ManagerConfig) {
	manager_signal = 0
	for signal in [C.SIGHUP, C.SIGTERM, C.SIGUSR1, C.SIGUSR2] {
		unsafe { C.signal(signal, voidptr(manager_signal_handler)) }
	}
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	mut manager := Manager{
		config: config
	}
	manager.sessions.flags |= .noslices
	for manager_signal == 0 {
		mut user, mut typed := manager.greet()
		if manager_signal == 0 { manager.attend(user, typed) }
		user.close()
		// The session has it now, or did not need it: either way it does
		// not stay in a process that is root.
		accountcore.wipe(mut typed)
		unsafe { typed.free() }
	}
	mark_active('')
	for mut session in manager.sessions {
		release_seat(session.session)
		end_session(session.session)
		C.close(session.control)
		wait(session.pid)
		session.user.close()
	}
	unsafe { manager.sessions.free() }
	if manager_signal == C.SIGTERM || manager_signal == C.SIGUSR1 || manager_signal == C.SIGUSR2 {
		what := if manager_signal == C.SIGTERM { 'restart' } else { 'off' }
		os.execvp(config.system, ['power', what]) or {
			discard_manager_error(err)
			eprintln('vinix-session: power request failed')
		}
	}
}
