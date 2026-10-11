// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Starting a session: a child that labels itself as a login, takes the seat
// if it is to be the session at the machine, becomes the account and runs
// the session's first program.
module sessioncore

import accountcore
import os

#include <sys/wait.h>

fn C.fork() int
fn C.pipe(fds &i32) int
fn C.dup2(old int, new int) int
fn C.waitpid(pid int, status &i32, options int) int
fn C._exit(status int)

pub const active_file = '/run/vinix/session/active'

// A session that was started: its first process and the number the kernel
// gave the login.
pub struct Started {
pub:
	pid     int
	session u32
}

// Say who is at the machine, for the authentication service's `session`
// rule; '' when nobody is.
pub fn mark_active(uid string) {
	os.mkdir_all(os.dir(active_file), mode: 0o755) or {}
	if uid == '' {
		os.rm(active_file) or {}
		return
	}
	temporary := active_file + '.new'
	os.write_file(temporary, uid + '\n') or { return }
	os.chmod(temporary, 0o644) or {}
	os.rename(temporary, active_file) or {}
}

// Start `argv` as `user` in a login session of its own. With `at_seat` the
// session is given the display and the input devices. `control`, when not
// negative, is a descriptor the session's first program gets as number 3
// (and is told of in VINIX_SESSION_FD): its line to whoever started it.
// Returns once the child has become a login, before it has become the user.
pub fn start(db accountcore.Database, user accountcore.User, argv []string, at_seat bool, control int) !Started {
	if !accountcore.is_person(user) && user.name != 'greeter' {
		return error('${user.name} is not an account sessions are for')
	}
	make_runtime_directory(user)!
	mut inherited := []string{}
	for name, value in os.environ() {
		inherited << '${name}=${value}'
	}
	mut environment := session_environment(user, inherited)
	if control >= 0 {
		environment << 'VINIX_SESSION_FD=3'
	}
	mut report := [2]i32{}
	if C.pipe(&report[0]) != 0 {
		return error('cannot make a pipe')
	}
	child := C.fork()
	if child < 0 {
		C.close(report[0])
		C.close(report[1])
		return error('cannot fork')
	}
	if child == 0 {
		C.close(report[0])
		session := start_login(user.uid) or {
			eprintln('vinix-session: ${err.msg()}')
			C._exit(126)
			return err
		}
		if at_seat {
			give_seat(session) or {
				eprintln('vinix-session: ${err.msg()}')
				C._exit(126)
			}
		}
		number := session.str() + '\n'
		C.write(report[1], number.str, usize(number.len))
		C.close(report[1])
		if control >= 0 && control != 3 {
			C.dup2(control, 3)
		}
		become(db, user) or {
			eprintln('vinix-session: ${err.msg()}')
			C._exit(126)
		}
		exec_as(user, argv, environment, control >= 0)
		eprintln('vinix-session: cannot run ${argv[0]}')
		C._exit(127)
	}
	C.close(report[1])
	mut digits := []u8{len: 16}
	got := C.read(report[0], digits.data, 16)
	C.close(report[0])
	session := if got > 0 { u32(digits[..got].bytestr().trim_space().u64()) } else { u32(0) }
	if session == 0 {
		// The child could not become a login and has said why.
		wait(child)
		return error('the session could not be started')
	}
	return Started{
		pid:     child
		session: session
	}
}

// Wait for a process and return its exit status the way a shell would.
pub fn wait(pid int) int {
	mut status := i32(0)
	for C.waitpid(pid, &status, 0) < 0 {
		if C.errno != C.EINTR {
			return 1
		}
	}
	return exit_code(status)
}

pub fn exit_code(status i32) int {
	return if status & 0x7f == 0 { int((status >> 8) & 0xff) } else { 128 + int(status & 0x7f) }
}
