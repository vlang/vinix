// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Turning a root process into a person's: the one-way step at the start of
// every session. After become() the process has the account's ids and
// groups and nothing of root's -- no capability in any set, no way to get
// one back through exec, and none of the descriptors it was started with
// beyond the first three.
//
// Each step is checked, and then the result is checked as a whole, because
// a session that is quietly still root is the failure this exists to
// prevent: on any doubt the process exits instead of going on.
module sessioncore

import accountcore
import os

#include <unistd.h>
#include <fcntl.h>
#include <grp.h>

$if linux {
	#include <sys/prctl.h>
}

#include <sys/stat.h>

fn C.setgroups(count usize, list &u32) int
fn C.getgroups(count int, list &u32) int
fn C.setresgid(real u32, effective u32, saved u32) int
fn C.setresuid(real u32, effective u32, saved u32) int
fn C.getresuid(real &u32, effective &u32, saved &u32) int
fn C.getresgid(real &u32, effective &u32, saved &u32) int
fn C.prctl(option int, a u64, b u64, c u64, d u64) int
fn C.chdir(path &char) int
fn C.execve(path &char, argv &&char, envp &&char) int
fn C.umask(mask u32) u32
fn C.setsid() int
fn C.syscall(number i64, ...voidptr) i64

struct CapHeader {
	version u32 = 0x20080522
	pid     i32
}

struct CapData {
mut:
	effective   u32
	permitted   u32
	inheritable u32
}

pub const runtime_base = '/run/user'

// What a session's environment is made of: the caller's own, which init
// fixed, minus everything that names root's identity or places, plus the
// account's.
const dropped_variables = ['HOME', 'USER', 'LOGNAME', 'SHELL', 'MAIL', 'XDG_RUNTIME_DIR',
	'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'VINIX_SYSTEM_SESSION',
	'VINIX_SESSION_FD', 'PS1', 'ENV', 'BASH_ENV', 'LD_PRELOAD', 'LD_AUDIT']

pub fn session_environment(user accountcore.User, inherited []string) []string {
	mut environment := []string{cap: inherited.len + 8}
	environment.flags |= .noslices
	for variable in inherited {
		length := variable.index_u8(`=`)
		name := unsafe { tos(variable.str, if length < 0 { variable.len } else { length }) }
		if name in dropped_variables {
			continue
		}
		environment << variable.clone()
	}
	shell := if user.shell == '' { '/bin/sh' } else { user.shell }
	environment << 'HOME=${user.home}'
	environment << 'USER=${user.name}'
	environment << 'LOGNAME=${user.name}'
	environment << 'SHELL=${shell}'
	number := user.uid.str()
	environment << 'XDG_RUNTIME_DIR=' + runtime_base + '/' + number
	unsafe { number.free() }
	if !environment.any(it.starts_with('PATH=')) {
		environment << 'PATH=/usr/local/bin:/usr/bin:/bin'.clone()
	}
	return environment
}

// The account's private directory for sockets and the like, made by root
// before the ids are dropped.
pub fn make_runtime_directory(user accountcore.User) ! {
	os.mkdir_all(runtime_base, mode: 0o755) or { discard_manager_error(err) }
	number := user.uid.str()
	path := runtime_base + '/' + number
	defer { unsafe {
		number.free()
		path.free()
	}
	 }
	if os.is_link(path) {
		return error('${path} is a link')
	}
	if !os.is_dir(path) {
		os.mkdir(path, mode: 0o700) or {
			discard_manager_error(err)
			return error('cannot create ${path}')
		}
	}
	os.chown(path, int(user.uid), int(user.gid)) or {
		discard_manager_error(err)
		return error('cannot give ${path} to ${user.name}')
	}
	os.chmod(path, 0o700) or {
		discard_manager_error(err)
		return error('cannot protect ${path}')
	}
}

// Become `user`. Does not return an error for the caller to ignore: the
// string is why the caller must not go on.
pub fn become(db accountcore.Database, user accountcore.User) ! {
	groups := db.supplementary_gids(user)
	defer { unsafe { groups.free() } }
	become_with_groups(user, groups)!
}

// Drop account memberships while still privileged: the application's later
// sandbox cannot clear supplementary groups once the session has become a user.
pub fn become_isolated(user accountcore.User) ! {
	if !accountcore.is_person(user) || user.gid == 0 {
		return error('an isolated session requires an ordinary account and group')
	}
	become_with_groups(user, []u32{})!
}

fn become_with_groups(user accountcore.User, groups []u32) ! {
	if user.uid == accountcore.uid_root {
		return error("a session is never root's")
	}
	// Capabilities that could come back through exec go first, while the
	// process may still drop them: the bounding set, then ambient.
	for capability in 0 .. 64 {
		// PR_CAPBSET_READ 23, PR_CAPBSET_DROP 24.
		if C.prctl(23, u64(capability), 0, 0, 0) == 1 && C.prctl(24, u64(capability), 0, 0, 0) != 0 {
			return error('cannot drop capability ${capability} from the bounding set')
		}
	}
	// PR_CAP_AMBIENT 47, PR_CAP_AMBIENT_CLEAR_ALL 4.
	C.prctl(47, 4, 0, 0, 0)
	// PR_SET_KEEPCAPS 8.
	C.prctl(8, 0, 0, 0, 0)
	if C.setgroups(usize(groups.len), if groups.len > 0 { &groups[0] } else { unsafe { nil } }) != 0 {
		return error('cannot set the groups')
	}
	if C.setresgid(user.gid, user.gid, user.gid) != 0 {
		return error('cannot set the group id')
	}
	if C.setresuid(user.uid, user.uid, user.uid) != 0 {
		return error('cannot set the user id')
	}
	// Whatever the kernel left of root's capabilities: none may stay.
	header := CapHeader{}
	mut empty := [2]CapData{}
	$if linux {
		$if amd64 {
			C.syscall(126, &header, &empty[0])
		} $else {
			C.syscall(91, &header, &empty[0])
		}
	}
	// PR_SET_NO_NEW_PRIVS 38: nothing this session executes may gain what
	// the session does not have.
	$if linux {
		if C.prctl(38, 1, 0, 0, 0) != 0 {
			return error('cannot set no_new_privs')
		}
	}
	verify(user, groups)!
	C.umask(0o022)
}

// The whole result, read back.
fn verify(user accountcore.User, groups []u32) ! {
	mut real := u32(0)
	mut effective := u32(0)
	mut saved := u32(0)
	if C.getresuid(&real, &effective, &saved) != 0 || real != user.uid || effective != user.uid
		|| saved != user.uid {
		return error('the user ids were not all changed')
	}
	if C.getresgid(&real, &effective, &saved) != 0 || real != user.gid || effective != user.gid
		|| saved != user.gid {
		return error('the group ids were not all changed')
	}
	mut held := []u32{len: 64}
	defer { unsafe { held.free() } }
	count := C.getgroups(64, unsafe { &held[0] })
	if count != groups.len {
		return error('the supplementary groups were not set')
	}
	for i in 0 .. count {
		if held[i] !in groups {
			return error('an unexpected supplementary group remains')
		}
	}
	// And root must be out of reach.
	if C.setresuid(0, 0, 0) == 0 {
		return error('root could be taken back')
	}
	$if linux {
		header := CapHeader{}
		mut now := [2]CapData{}
		number := $if amd64 { i64(125) } $else { i64(90) }
		if C.syscall(number, &header, &now[0]) != 0 {
			return error('cannot read the capability sets')
		}
		for set in now {
			if set.effective != 0 || set.permitted != 0 || set.inheritable != 0 {
				return error('a capability remains')
			}
		}
	}
}

// Replace this process with `argv`, in `user`'s home. Only returns if the
// program could not be started.
pub fn exec_as(user accountcore.User, argv []string, environment []string, keep_control bool) {
	if C.chdir(&char(user.home.str)) != 0 {
		C.chdir(c'/')
	}
	// Nothing of root's but the first three descriptors and, where the
	// session has a line to its starter, the fourth.
	for fd in (if keep_control { 4 } else { 3 }) .. 1024 {
		C.close(fd)
	}
	mut c_argv := []&char{cap: argv.len + 1}
	defer { unsafe { c_argv.free() } }
	for argument in argv {
		c_argv << &char(argument.str)
	}
	c_argv << &char(unsafe { nil })
	mut c_env := []&char{cap: environment.len + 1}
	defer { unsafe { c_env.free() } }
	for variable in environment {
		c_env << &char(variable.str)
	}
	c_env << &char(unsafe { nil })
	C.execve(c_argv[0], &c_argv[0], &c_env[0])
}

// One write() of `text` to a file that exists, with the kernel's answer: the
// buffered writes of the library report success for a write the kernel
// refused.
fn write_whole(path string, text string) ! {
	fd := C.open(&char(path.str), C.O_WRONLY)
	if fd < 0 {
		number := C.errno.str()
		defer { unsafe { number.free() } }
		return error('cannot open ${path} (errno ${number})')
	}
	put := C.write(fd, text.str, usize(text.len))
	code := C.errno
	C.close(fd)
	if put != text.len {
		number := code.str()
		defer { unsafe { number.free() } }
		return error('cannot write ${path} (errno ${number})')
	}
}

// Label this process, still root, as the start of a login by `uid`: the
// kernel then knows everything it goes on to start as that login, whatever
// those processes later do to their ids. It can be done once. Returns the
// number the kernel gave the login session.
pub fn start_login(uid u32) !u32 {
	number := uid.str()
	defer { unsafe { number.free() } }
	write_whole('/proc/self/loginuid', number) or {
		message := err.msg()
		defer { unsafe {
			message.free()
			err.free()
		}
		 }
		return error('the kernel did not accept the login: ${message}')
	}
	text := os.read_file('/proc/self/sessionid') or {
		discard_manager_error(err)
		return error('cannot read the login session')
	}
	trimmed := text.trim_space()
	session := u32(trimmed.u64())
	unsafe {
		trimmed.free()
		text.free()
	}
	if session == 0 {
		return error('the kernel started no login session')
	}
	return session
}

const seat_file = '/proc/sys/kernel/seat_session'

// Give the seat -- the display, the keyboard, the pointer, sound -- to a
// login session. Whoever held it loses the use of those devices at once.
pub fn give_seat(session u32) ! {
	number := session.str()
	defer { unsafe { number.free() } }
	write_whole(seat_file, number) or {
		message := err.msg()
		defer { unsafe {
			message.free()
			err.free()
		}
		 }
		return error('cannot give the seat: ${message}')
	}
}

// Take the seat back from `session` if it still holds it.
pub fn release_seat(session u32) {
	text := os.read_file(seat_file) or {
		discard_manager_error(err)
		return
	}
	trimmed := text.trim_space()
	matched := u32(trimmed.u64()) == session
	unsafe {
		trimmed.free()
		text.free()
	}
	if matched {
		write_whole(seat_file, '0') or { discard_manager_error(err) }
	}
}
