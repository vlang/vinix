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
#include <grp.h>
#include <sys/prctl.h>
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
	'PS1', 'ENV', 'BASH_ENV', 'LD_PRELOAD', 'LD_AUDIT']

pub fn session_environment(user accountcore.User, inherited []string) []string {
	mut environment := []string{cap: inherited.len + 8}
	for variable in inherited {
		name := variable.all_before('=')
		if name in dropped_variables {
			continue
		}
		environment << variable
	}
	shell := if user.shell == '' { '/bin/sh' } else { user.shell }
	environment << 'HOME=${user.home}'
	environment << 'USER=${user.name}'
	environment << 'LOGNAME=${user.name}'
	environment << 'SHELL=${shell}'
	environment << 'XDG_RUNTIME_DIR=${runtime_base}/${user.uid}'
	if !environment.any(it.starts_with('PATH=')) {
		environment << 'PATH=/usr/local/bin:/usr/bin:/bin'
	}
	return environment
}

// The account's private directory for sockets and the like, made by root
// before the ids are dropped.
pub fn make_runtime_directory(user accountcore.User) ! {
	os.mkdir_all(runtime_base, mode: 0o755) or {}
	path := '${runtime_base}/${user.uid}'
	if os.is_link(path) {
		return error('${path} is a link')
	}
	if !os.is_dir(path) {
		os.mkdir(path, mode: 0o700) or { return error('cannot create ${path}') }
	}
	os.chown(path, int(user.uid), int(user.gid)) or { return error('cannot give ${path} to ${user.name}') }
	os.chmod(path, 0o700) or { return error('cannot protect ${path}') }
}

// Become `user`. Does not return an error for the caller to ignore: the
// string is why the caller must not go on.
pub fn become(db accountcore.Database, user accountcore.User) ! {
	if user.uid == accountcore.uid_root {
		return error('a session is never root\'s')
	}
	groups := db.supplementary_gids(user)
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
pub fn exec_as(user accountcore.User, argv []string, environment []string) {
	if C.chdir(&char(user.home.str)) != 0 {
		C.chdir(c'/')
	}
	for fd in 3 .. 1024 {
		C.close(fd)
	}
	mut c_argv := []&char{cap: argv.len + 1}
	for argument in argv {
		c_argv << &char(argument.str)
	}
	c_argv << &char(unsafe { nil })
	mut c_env := []&char{cap: environment.len + 1}
	for variable in environment {
		c_env << &char(variable.str)
	}
	c_env << &char(unsafe { nil })
	C.execve(c_argv[0], &c_argv[0], &c_env[0])
}
