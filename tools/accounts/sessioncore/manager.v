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

fn C.socketpair(domain int, kind int, protocol int, fds &i32) int
fn C.kill(pid int, signal int) int
fn C.poll(fds voidptr, count u64, timeout int) int
fn C.usleep(microseconds u32) int

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
	return store.load()
}

// The processes of a login session, as the kernel lists them.
fn session_pids(session u32) []int {
	mut pids := []int{}
	for entry in os.ls('/proc') or { []string{} } {
		pid := entry.int()
		if pid <= 1 {
			continue
		}
		text := os.read_file('/proc/${entry}/sessionid') or { continue }
		if u32(text.trim_space().u64()) == session {
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
	for _ in 0 .. 50 {
		mut fresh := 0
		for pid in session_pids(session) {
			if pid !in seen {
				fresh++
				seen[pid] = true
			}
			C.kill(pid, signal)
		}
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
		if session_pids(session).len == 0 {
			return
		}
		C.usleep(100_000)
	}
	signal_session(session, C.SIGKILL)
}

fn reply(fd int, status u16, text string) {
	frame := if text == '' { authproto.Frame{
			code: status
		} } else { authproto.text_frame(status, text) }
	authproto.write_frame(fd, frame) or {}
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
fn (m &Manager) check_login(mut request authproto.Frame) (authproto.Frame, ?accountcore.User) {
	if request.fields.len != 2 {
		return authproto.text_frame(authproto.status_invalid, 'login takes a user and a password'), none
	}
	name := request.text(0)
	answer := verify_login(m.config.socket, name, request.fields[1]) or {
		return authproto.text_frame(authproto.status_failed, err.msg()), none
	}
	if answer.code != authproto.status_ok {
		return answer, none
	}
	db := load_accounts() or { return authproto.text_frame(authproto.status_failed, err.msg()), none }
	user := db.user(name) or { return authproto.Frame{
		code: authproto.status_denied
	}, none }
	// The password of an account that is not a person's, if it had one,
	// would still not be a way to a session.
	if !accountcore.is_person(user) {
		return authproto.Frame{
			code: authproto.status_denied
		}, none
	}
	return authproto.Frame{
		code: authproto.status_ok
	}, user
}

// Show the login screen until someone has logged in, and return who, and
// the password they typed -- for their credential store, and to be wiped
// by the caller as soon as the session has been started.
fn (mut m Manager) greet() (accountcore.User, []u8) {
	for {
		db := load_accounts() or {
			eprintln('vinix-session: ${err.msg()}')
			C.usleep(2_000_000)
			continue
		}
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
		mark_active('')
		started := start(db, greeter, m.config.greeter, true, int(line[1]), Unlock{}) or {
			eprintln('vinix-session: the login screen could not be started: ${err.msg()}')
			C.close(line[0])
			C.close(line[1])
			C.usleep(2_000_000)
			continue
		}
		C.close(line[1])
		mut chosen := ?accountcore.User(none)
		mut typed := []u8{}
		for {
			mut request := authproto.read_frame(int(line[0])) or { break }
			match request.code {
				op_login {
					// A copy first: asking the service wipes what it was sent.
					mut password := if request.fields.len == 2 { request.fields[1].clone() } else { []u8{} }
					answer, user := m.check_login(mut request)
					if _ := user {
						typed = password.clone()
					}
					accountcore.wipe(mut password)
					request.wipe()
					authproto.write_frame(int(line[0]), answer) or {}
					if who := user {
						chosen = who
						break
					}
				}
				op_power {
					what := request.text(0)
					if what == 'off' || what == 'restart' {
						reply(int(line[0]), authproto.status_ok, '')
						os.execvp(m.config.system, ['power', what]) or {}
					}
					reply(int(line[0]), authproto.status_invalid, 'power off or restart')
				}
				else {
					request.wipe()
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
fn (mut m Manager) attend(user accountcore.User, typed []u8) {
	mut index := m.find_session(user.uid)
	if index >= 0 {
		// Theirs was waiting. The seat first: a continued process may use
		// the display at once.
		give_seat(m.sessions[index].session) or { eprintln('vinix-session: ${err.msg()}') }
		mark_active(user.uid.str())
		m.sessions[index].stopped = false
		signal_session(m.sessions[index].session, C.SIGCONT)
	} else {
		db := load_accounts() or {
			eprintln('vinix-session: ${err.msg()}')
			return
		}
		mut line := [2]i32{}
		if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &line[0]) != 0 {
			return
		}
		started := start(db, user, m.config.desktop, true, int(line[1]), Unlock{
			secret: typed
			helper: m.config.keyring
		}) or {
			eprintln('vinix-session: ${err.msg()}')
			C.close(line[0])
			C.close(line[1])
			return
		}
		C.close(line[1])
		mark_active(user.uid.str())
		m.sessions << Session{
			user:    user
			pid:     started.pid
			session: started.session
			control: int(line[0])
		}
		index = m.sessions.len - 1
	}
	session := m.sessions[index]
	for {
		// The session's first process ending is the session ending.
		mut status := i32(0)
		if C.waitpid(session.pid, &status, C.WNOHANG) == session.pid {
			break
		}
		if !readable(session.control, 500) {
			continue
		}
		mut request := authproto.read_frame(session.control) or {
			// The line closed; wait for the process itself.
			C.usleep(200_000)
			continue
		}
		code := request.code
		request.wipe()
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
	mut status := i32(0)
	C.waitpid(session.pid, &status, C.WNOHANG)
	m.sessions.delete(index)
}

// Run the machine's sessions. Does not return.
pub fn run_manager(config ManagerConfig) {
	mut manager := Manager{
		config: config
	}
	for {
		user, mut typed := manager.greet()
		manager.attend(user, typed)
		// The session has it now, or did not need it: either way it does
		// not stay in a process that is root.
		accountcore.wipe(mut typed)
	}
}
