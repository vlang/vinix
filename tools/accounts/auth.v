// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-auth: ask the authentication service for something, from a
// terminal or a script.
//
//	vinix-auth info                     who the service takes you for
//	vinix-auth verify [USER]            check a password
//	vinix-auth passwd                   change your own password
//	vinix-auth describe ACTION          what an action is and whether you may
//	vinix-auth run ACTION [ARGUMENT...] do something as root, if allowed
//
// Passwords are read from the terminal without echo, or, when standard
// input is not a terminal, one per line from it. `run --input` reads one
// more line and hands it to the action. Exit status: 0 done, 1 refused or
// failed, 2 the request was wrong, 3 wait and try again; `run` passes the
// action's own status on.
module main

import authclient
import authproto
import os

#include <termios.h>
#include <unistd.h>

fn C.isatty(fd int) int
fn C.tcgetattr(fd int, termios voidptr) int
fn C.tcsetattr(fd int, action int, termios voidptr) int
fn C.geteuid() u32

struct C.termios {
mut:
	c_lflag u32
}

fn socket_path() string {
	override := os.getenv('VINIX_AUTH_SOCKET')
	return if override != '' { override } else { authclient.default_socket }
}

// One line from standard input, without its line break and without echo
// when it is typed.
fn read_secret(prompt string) []u8 {
	typed := C.isatty(0) == 1
	mut saved := C.termios{}
	if typed {
		eprint(prompt)
		C.tcgetattr(0, &saved)
		mut quiet := saved
		quiet.c_lflag &= ~u32(C.ECHO)
		C.tcsetattr(0, C.TCSAFLUSH, &quiet)
	}
	mut line := []u8{cap: 64}
	mut one := [1]u8{}
	for line.len < authproto.max_field {
		if C.read(0, &one[0], 1) != 1 || one[0] == `\n` {
			break
		}
		line << one[0]
	}
	if typed {
		C.tcsetattr(0, C.TCSAFLUSH, &saved)
		eprintln('')
	}
	return line
}

fn usage() {
	eprintln('usage: vinix-auth info | verify [USER] | passwd | describe ACTION | run [--input] ACTION [ARGUMENT...]')
	exit(2)
}

fn finish(reply authproto.Frame) {
	match reply.code {
		authproto.status_ok {
			exit(0)
		}
		authproto.status_wait {
			eprintln('vinix-auth: too many wrong passwords; try again in ${reply.text(0)} seconds')
			exit(3)
		}
		authproto.status_invalid {
			eprintln('vinix-auth: ${reply.text(0)}')
			exit(2)
		}
		authproto.status_denied {
			eprintln('vinix-auth: denied')
			exit(1)
		}
		else {
			eprintln('vinix-auth: failed${if reply.text(0) != '' {
				': ' + reply.text(0)
			} else {
				''
			}}')
			exit(1)
		}
	}
}

fn own_name() string {
	reply := authclient.ask(socket_path(), authproto.op_info) or {
		eprintln('vinix-auth: ${err.msg()}')
		exit(1)
	}
	if reply.code != authproto.status_ok {
		eprintln('vinix-auth: the service does not know this account')
		exit(1)
	}
	return reply.text(0)
}

fn main() {
	args := os.args[1..]
	if args.len == 0 {
		usage()
	}
	match args[0] {
		'info' {
			reply := authclient.ask(socket_path(), authproto.op_info) or {
				eprintln('vinix-auth: ${err.msg()}')
				exit(1)
			}
			if reply.code == authproto.status_ok {
				println('user: ${reply.text(0)}')
				println('administrator: ${if reply.text(1) == '1' { 'yes' } else { 'no' }}')
				println('at the machine: ${if reply.text(2) == '1' { 'yes' } else { 'no' }}')
			}
			finish(reply)
		}
		'verify' {
			name := if args.len > 1 { args[1] } else { own_name() }
			password := read_secret('Password for ${name}: ')
			reply := authclient.ask(socket_path(), authproto.op_verify, name.bytes(), password) or {
				eprintln('vinix-auth: ${err.msg()}')
				exit(1)
			}
			finish(reply)
		}
		'passwd' {
			name := if args.len > 1 { args[1] } else { own_name() }
			old := if C.geteuid() == 0 { []u8{} } else { read_secret('Current password: ') }
			new := read_secret('New password: ')
			if C.isatty(0) == 1 {
				again := read_secret('New password again: ')
				if again != new {
					eprintln('vinix-auth: the two do not match')
					exit(2)
				}
			}
			reply := authclient.ask(socket_path(), authproto.op_change_password, name.bytes(),
				old, new) or {
				eprintln('vinix-auth: ${err.msg()}')
				exit(1)
			}
			if reply.code == authproto.status_ok {
				eprintln('vinix-auth: password changed')
			}
			finish(reply)
		}
		'describe' {
			if args.len != 2 {
				usage()
			}
			reply := authclient.ask(socket_path(), authproto.op_describe, args[1].bytes()) or {
				eprintln('vinix-auth: ${err.msg()}')
				exit(1)
			}
			if reply.code == authproto.status_ok {
				println(reply.text(0))
				println('allowed: ${if reply.text(1) == '1' { 'yes' } else { 'no' }}')
				println('password: ${if reply.text(2) == '1' { 'yes' } else { 'no' }}')
			}
			finish(reply)
		}
		'run' {
			mut rest := args[1..].clone()
			mut with_input := false
			if rest.len > 0 && rest[0] == '--input' {
				with_input = true
				rest = rest[1..].clone()
			}
			if rest.len == 0 {
				usage()
			}
			described := authclient.ask(socket_path(), authproto.op_describe, rest[0].bytes()) or {
				eprintln('vinix-auth: ${err.msg()}')
				exit(1)
			}
			if described.code != authproto.status_ok {
				finish(described)
			}
			if described.text(1) != '1' {
				eprintln('vinix-auth: ${described.text(0)}: not permitted for this account')
				exit(1)
			}
			mut password := []u8{}
			if described.text(2) == '1' {
				eprintln(described.text(0))
				password = read_secret('Your password: ')
			}
			input := if with_input { read_secret('Input: ') } else { []u8{} }
			mut fields := [rest[0].bytes(), password, input]
			for argument in rest[1..] {
				fields << argument.bytes()
			}
			reply := authclient.ask(socket_path(), authproto.op_run, ...fields) or {
				eprintln('vinix-auth: ${err.msg()}')
				exit(1)
			}
			if reply.code == authproto.status_ok || (reply.code == authproto.status_failed
				&& reply.fields.len == 2) {
				print(reply.text(1))
				exit(reply.text(0).int())
			}
			finish(reply)
		}
		else {
			usage()
		}
	}
}
