// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-session: where sessions come from. Run by root -- by init, or by
// something init started -- it is the only place a process stops being
// root and becomes a person's.
//
//	vinix-session run [--seat] USER COMMAND [ARGUMENT...]
//	    become USER and run COMMAND, in a login session of its own. With
//	    --seat the session is the one at the machine: it is given the
//	    display and the input devices, and is who the authentication
//	    service takes for the person at the machine, until COMMAND exits.
//	    Without, it is for services and scripts that must not be root.
//	vinix-session console
//	    ask for a name and a password on the terminal, run that person's
//	    shell as them until it exits, and ask again
//	vinix-session manager [--greeter COMMAND...] [--desktop COMMAND...]
//	    show the login screen, run the session of whoever logs in, and
//	    come back to the login screen when it ends or steps aside
//	    (sessioncore/manager.v); COMMAND runs to the next option
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
fn C.tcgetattr(fd int, termios voidptr) int
fn C.tcsetattr(fd int, action int, termios voidptr) int
fn C.sleep(seconds u32) u32

struct C.termios {
mut:
	c_lflag u32
}

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

// Start `argv` as `user` in a login session of its own and wait for it. With
// `at_seat` the session is the one at the machine: it holds the display and
// the input devices, and is who the authentication service takes for the
// person at the machine, until it ends.
fn run_as(db accountcore.Database, user accountcore.User, argv []string, at_seat bool) int {
	started := sessioncore.start(db, user, argv, at_seat, -1) or {
		eprintln('vinix-session: ${err.msg()}')
		return 126
	}
	if at_seat {
		sessioncore.mark_active(user.uid.str())
	}
	status := sessioncore.wait(started.pid)
	if at_seat {
		sessioncore.mark_active('')
		sessioncore.release_seat(started.session)
	}
	return status
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
		run_as(db, user, [shell, '-l'], true)
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
	if args.len >= 1 && args[0] == 'manager' {
		mut greeter := ['/usr/bin/vinix-desktop', '--greeter']
		mut desktop := ['/usr/bin/vinix-desktop']
		mut target := 0
		for argument in args[1..] {
			if argument == '--greeter' {
				greeter = []string{}
				target = 1
			} else if argument == '--desktop' {
				desktop = []string{}
				target = 2
			} else if target == 1 {
				greeter << argument
			} else if target == 2 {
				desktop << argument
			} else {
				fail('unknown argument ${argument}')
			}
		}
		if greeter.len == 0 || desktop.len == 0 {
			fail('--greeter and --desktop each need a command')
		}
		sessioncore.run_manager(greeter: greeter, desktop: desktop)
		return
	}
	mut rest := args.clone()
	mut at_seat := false
	if rest.len >= 2 && rest[0] == 'run' && rest[1] == '--seat' {
		at_seat = true
		rest.delete(1)
	}
	if rest.len < 3 || rest[0] != 'run' {
		eprintln('usage: vinix-session run [--seat] USER COMMAND [ARGUMENT...] | console | manager [--greeter COMMAND...] [--desktop COMMAND...]')
		exit(2)
	}
	db := load()
	user := db.user(rest[1]) or {
		fail('no user ${rest[1]}')
		return
	}
	exit(run_as(db, user, rest[2..].clone(), at_seat))
}
