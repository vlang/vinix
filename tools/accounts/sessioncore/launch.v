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
	os.mkdir_all('/run/vinix/session', mode: 0o755) or { discard_manager_error(err) }
	if uid == '' {
		os.rm(active_file) or { discard_manager_error(err) }
		return
	}
	temporary := '/run/vinix/session/active.new'
	text := uid + '\n'
	defer { unsafe { text.free() } }
	os.write_file(temporary, text) or {
		discard_manager_error(err)
		return
	}
	os.chmod(temporary, 0o644) or { discard_manager_error(err) }
	os.rename(temporary, active_file) or { discard_manager_error(err) }
}

// Keep one owned copy of each inherited entry. os.environ() also allocates
// a map, keys and values, which are unnecessary in a long-lived manager.
fn inherited_environment() []string {
	entries := unsafe { &&char(voidptr(C.environ)) }
	mut count := 0
	for unsafe { entries[count] } != unsafe { nil } { count++ }
	mut result := []string{cap: count}
	for index in 0 .. count {
		entry := unsafe { cstring_to_vstring(entries[index]) }
		unsafe { result.push_many(&entry, 1) }
	}
	return result
}

// The child writes a positive u32 and a newline in one pipe write. Decode
// without slices or temporary strings in the manager, and refuse truncation,
// overflow and trailing bytes rather than accepting a partial session id.
fn reported_session(bytes &u8, length int) u32 {
	if length < 2 || length > 11 || unsafe { bytes[0] } == `0`
		|| unsafe { bytes[length - 1] } != `\n` {
		return 0
	}
	mut value := u64(0)
	for index in 0 .. length - 1 {
		digit := unsafe { bytes[index] }
		if digit < `0` || digit > `9` { return 0 }
		value = value * 10 + u64(digit - `0`)
		if value > u64(0xffffffff) { return 0 }
	}
	return u32(value)
}

// What a login was made with, to be handed to one program of the session
// and to nothing else: the password that was typed, and the program that
// gets it on its standard input -- the account's credential store, which it
// opens. The program is started inside the session, as the account.
pub struct Unlock {
pub:
	secret []u8
	helper []string
}

// Hand `unlock.secret` to `unlock.helper`, as the account this process has
// just become. The helper is its own process, detached from this one, and
// stays in the login session.
//
// The helper is given descriptor 3 and closes it when it is ready to be
// asked things; this waits for that, a few seconds at most, so that the
// session's first program does not start before the service it will ask.
fn run_unlock_helper(unlock Unlock, environment []string) {
	if unlock.helper.len == 0 || unlock.secret.len == 0 || !os.exists(unlock.helper[0]) {
		return
	}
	mut line := [2]i32{}
	mut ready := [2]i32{}
	if C.pipe(&line[0]) != 0 {
		return
	}
	if C.pipe(&ready[0]) != 0 {
		C.close(line[0])
		C.close(line[1])
		return
	}
	first := C.fork()
	if first == 0 {
		// Forked twice, so that the session's first program is not the
		// parent of something it did not start.
		if C.fork() != 0 {
			C._exit(0)
		}
		C.dup2(line[0], 0)
		// The ready line as descriptor 3, by way of a number that cannot
		// be 3 already.
		spare := C.dup2(ready[1], 200)
		C.dup2(spare, 3)
		mut c_argv := []&char{cap: unlock.helper.len + 1}
		for argument in unlock.helper {
			c_argv << &char(argument.str)
		}
		c_argv << &char(unsafe { nil })
		mut c_env := []&char{cap: environment.len + 1}
		for variable in environment {
			c_env << &char(variable.str)
		}
		c_env << &char(unsafe { nil })
		for fd in 4 .. 1024 {
			C.close(fd)
		}
		C.execve(c_argv[0], &c_argv[0], &c_env[0])
		C._exit(127)
	}
	C.close(line[0])
	C.close(ready[1])
	C.write(line[1], unlock.secret.data, usize(unlock.secret.len))
	C.write(line[1], c'\n', 1)
	C.close(line[1])
	if first > 0 {
		mut status := i32(0)
		C.waitpid(first, &status, 0)
	}
	// Ready, gone, or not saying: in no case is the session held up for
	// longer than this.
	mut waiting := PollFd{
		fd:     ready[0]
		events: 1
	}
	C.poll(voidptr(&waiting), 1, 5000)
	C.close(ready[0])
}

// Start `argv` as `user` in a login session of its own. With `at_seat` the
// session is given the display and the input devices. `control`, when not
// negative, is a descriptor the session's first program gets as number 3
// (and is told of in VINIX_SESSION_FD): its line to whoever started it.
// Returns once the child has become a login, before it has become the user.
pub fn start(db accountcore.Database, user accountcore.User, argv []string, at_seat bool, control int, unlock Unlock) !Started {
	return start_profile(db, user, argv, []string{}, at_seat, control, unlock, false)
}

fn start_fallback(db accountcore.Database, user accountcore.User, argv []string, fallback []string, at_seat bool, control int, unlock Unlock) !Started {
	return start_profile(db, user, argv, fallback, at_seat, control, unlock, false)
}

// The same login attribution and checked identity transition, without any
// supplementary account groups. This profile does not take the display seat.
pub fn start_isolated(db accountcore.Database, user accountcore.User, argv []string) !Started {
	return start_profile(db, user, argv, []string{}, false, -1, Unlock{}, true)
}

fn start_profile(db accountcore.Database, user accountcore.User, argv []string, fallback []string, at_seat bool, control int, unlock Unlock, isolated bool) !Started {
	if !accountcore.is_person(user) && user.name != 'greeter' {
		return error('${user.name} is not an account sessions are for')
	}
	if isolated && (!accountcore.is_person(user) || user.gid == 0) {
		return error('an isolated session requires an ordinary account and group')
	}
	make_runtime_directory(user)!
	inherited := inherited_environment()
	defer { unsafe { inherited.free() } }
	mut environment := session_environment(user, inherited)
	defer { unsafe { environment.free() } }
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
		if isolated {
			become_isolated(user) or {
				eprintln('vinix-session: ${err.msg()}')
				C._exit(126)
			}
		} else {
			become(db, user) or {
				eprintln('vinix-session: ${err.msg()}')
				C._exit(126)
			}
		}
		// As the account, and before its first program: the store is open
		// by the time anything asks it.
		run_unlock_helper(unlock, environment)
		retire_login_password(unlock.secret)
		exec_as_fallback(user, argv, fallback, environment, control >= 0)
		eprintln('vinix-session: cannot run ${argv[0]}')
		C._exit(127)
	}
	C.close(report[1])
	mut digits := [16]u8{}
	mut got := C.read(report[0], &digits[0], 16)
	for got < 0 && C.errno == C.EINTR { got = C.read(report[0], &digits[0], 16) }
	C.close(report[0])
	session := reported_session(&digits[0], int(got))
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
