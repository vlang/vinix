// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-session: where sessions come from. Run by root -- by init, or by
// something init started -- it is the only place a process stops being
// root and becomes a person's.
//
//	vinix-session run USER COMMAND [ARGUMENT...]
//	    become USER and run COMMAND: for services and scripts that must
//	    not be root
//	vinix-session console
//	    ask for a name and a password on the terminal, run that person's
//	    shell as them until it exits, and ask again
//
// The console login checks the password through the authentication service,
// like everything else: one place counts failures and writes the log.
module main

import accountcore
import authclient
import authproto
import os
import sessioncore

#include <termios.h>
#include <unistd.h>
#include <sys/wait.h>

fn C.geteuid() u32
fn C.fork() int
fn C.waitpid(pid int, status &i32, options int) int
fn C.tcgetattr(fd int, termios voidptr) int
fn C.tcsetattr(fd int, action int, termios voidptr) int
fn C._exit(status int)
fn C.sleep(seconds u32) u32

struct C.termios {
mut:
	c_lflag u32
}

const active_file = '/run/vinix/session/active'

fn fail(message string) {
	eprintln('vinix-session: ${message}')
	exit(1)
}

fn load() accountcore.Database {
	store := accountcore.Store{}
	held := store.lock(false) or {
		fail(err.msg())
		return accountcore.Database{}
	}
	defer { held.release() }
	return store.load() or {
		fail('cannot use the account database: ${err.msg()}')
		return accountcore.Database{}
	}
}

// Say who is at the machine, for the service's `session` rule; '' when
// nobody is.
fn mark_active(uid string) {
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

// Start `argv` as `user` in a session of its own and wait for it.
fn run_as(db accountcore.Database, user accountcore.User, argv []string) int {
	sessioncore.make_runtime_directory(user) or { fail(err.msg()) }
	environment := sessioncore.session_environment(user, os.environ().keys().map('${it}=${os.getenv(it)}'))
	child := C.fork()
	if child < 0 {
		fail('cannot fork')
	}
	if child == 0 {
		sessioncore.become(db, user) or {
			eprintln('vinix-session: ${err.msg()}')
			C._exit(126)
		}
		sessioncore.exec_as(user, argv, environment)
		eprintln('vinix-session: cannot run ${argv[0]}')
		C._exit(127)
	}
	mut status := i32(0)
	for C.waitpid(child, &status, 0) < 0 {
		if C.errno != C.EINTR {
			return 1
		}
	}
	return if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
}

// A line from the terminal, or none when there is nothing more to read.
fn read_line(echo bool) ?[]u8 {
	mut saved := C.termios{}
	if !echo {
		C.tcgetattr(0, &saved)
		mut quiet := saved
		quiet.c_lflag &= ~u32(C.ECHO)
		C.tcsetattr(0, C.TCSAFLUSH, &quiet)
	}
	mut line := []u8{cap: 64}
	mut one := [1]u8{}
	mut ended := false
	for line.len < 1024 {
		if C.read(0, &one[0], 1) != 1 {
			ended = true
			break
		}
		if one[0] == `\n` {
			break
		}
		if one[0] != `\r` {
			line << one[0]
		}
	}
	if !echo {
		C.tcsetattr(0, C.TCSAFLUSH, &saved)
		println('')
	}
	if ended && line.len == 0 {
		return none
	}
	return line
}

fn console() {
	for {
		print('\nlogin: ')
		typed := read_line(true) or { return }
		name := typed.bytestr().trim_space()
		if name == '' {
			continue
		}
		print('Password: ')
		password := read_line(false) or { return }
		reply := authclient.ask(authclient.default_socket, authproto.op_verify, name.bytes(),
			password) or {
			println('Login is not possible: ${err.msg()}.')
			C.sleep(2)
			continue
		}
		if reply.code == authproto.status_wait {
			println('Too many wrong passwords. Try again in ${reply.text(0)} seconds.')
			continue
		}
		if reply.code != authproto.status_ok {
			C.sleep(1)
			println('Login incorrect.')
			continue
		}
		db := load()
		user := db.user(name) or { continue }
		if !accountcore.is_person(user) {
			println('This account cannot log in.')
			continue
		}
		shell := if user.shell == '' { '/bin/sh' } else { user.shell }
		mark_active(user.uid.str())
		run_as(db, user, [shell, '-l'])
		mark_active('')
	}
}

fn main() {
	args := os.args[1..]
	if C.geteuid() != 0 {
		fail('must be started by root')
	}
	if args.len >= 1 && args[0] == 'console' {
		console()
		return
	}
	if args.len < 3 || args[0] != 'run' {
		eprintln('usage: vinix-session run USER COMMAND [ARGUMENT...] | console')
		exit(2)
	}
	db := load()
	user := db.user(args[1]) or {
		fail('no user ${args[1]}')
		return
	}
	exit(run_as(db, user, args[2..].clone()))
}
