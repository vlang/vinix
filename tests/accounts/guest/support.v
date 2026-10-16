// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What every scenario is written with: lines on the serial port, checks
// that are remembered, programs started as root or as an account, and the
// way out. The line format is the hardware tests', because the same
// controller reads it.
module main

import accountcore
import authclient
import authproto
import os
import sessioncore

#include <fcntl.h>
#include <unistd.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <errno.h>

fn C.sync()
fn C.reboot(command int) int
fn C.fork() int
fn C.pipe(fds &i32) int
fn C.dup2(old int, new int) int
fn C.waitpid(pid int, status &i32, options int) int
fn C._exit(status int)
fn C.execve(path &char, argv &&char, envp &&char) int
fn C.usleep(microseconds u32) int

const console_path = $if arm64 {
	'/dev/console'
} $else {
	'/dev/com1'
}

struct Test {
mut:
	scenario string
	console  int = 1
	failures int
}

fn new_test() Test {
	mut t := Test{}
	fd := C.open(&char(console_path.str), C.O_WRONLY)
	if fd >= 0 {
		t.console = fd
	}
	return t
}

fn (mut t Test) say(line string) {
	text := line + '\n'
	C.write(t.console, text.str, usize(text.len))
}

fn (mut t Test) info(text string) {
	t.say('HWTEST INFO ${text}')
}

// Records a failure unless `condition` holds. The scenario goes on either
// way: one run should report everything that is wrong.
fn (mut t Test) check(condition bool, message string) bool {
	if !condition {
		t.failures++
		t.say('HWTEST FAIL ${t.scenario}: ${message}')
	}
	return condition
}

fn idle() {
	for {
		C.usleep(1_000_000)
	}
}

fn (mut t Test) finish() {
	C.usleep(200_000)
	if t.failures == 0 {
		t.say('HWTEST PASS ${t.scenario}')
	} else {
		t.say('HWTEST FAIL ${t.scenario}')
	}
	C.sync()
	C.reboot(0x4321fedc)
	idle()
}

fn read_text(path string) string {
	return os.read_file(path) or { '' }
}

fn mode_of(path string) int {
	info := os.lstat(path) or { return -1 }
	return int(info.mode & 0o7777)
}

fn owner_of(path string) int {
	info := os.lstat(path) or { return -1 }
	return int(info.uid)
}

// The result of a program: how it exited and everything it printed.
struct Ran {
	status int
	output string
}

// Run a program with `input` on its standard input, as root or, with a
// user, as that account in the way a session becomes it.
fn run(argv []string, input string, db ?accountcore.Database, user ?accountcore.User) Ran {
	mut to_child := [2]i32{}
	mut from_child := [2]i32{}
	if C.pipe(&to_child[0]) != 0 {
		return Ran{
			status: -1
		}
	}
	if C.pipe(&from_child[0]) != 0 {
		C.close(to_child[0]); C.close(to_child[1])
		return Ran{status: -1, output: 'cannot create guest capture pipe'}
	}
	child := C.fork()
	if child < 0 {
		C.close(to_child[0]); C.close(to_child[1]); C.close(from_child[0]); C.close(from_child[1])
		return Ran{status: -1, output: 'cannot fork guest command; check process/kernel resource limits'}
	}
	if child == 0 {
		C.dup2(to_child[0], 0)
		C.dup2(from_child[1], 1)
		C.dup2(from_child[1], 2)
		for fd in 3 .. 64 {
			C.close(fd)
		}
		mut environment := ['PATH=/usr/sbin:/usr/bin:/sbin:/bin']
		// What a program run from inside a session needs of that session.
		for variable in ['HOME', 'XDG_RUNTIME_DIR', 'VINIX_KEYRING_TEST_COST'] {
			if user == none && os.getenv(variable) != '' {
				environment << '${variable}=${os.getenv(variable)}'
			}
		}
		if account := user {
			if database := db {
				sessioncore.become(database, account) or {
					println('become: ${err.msg()}')
					C._exit(126)
				}
			}
			environment << 'HOME=${account.home}'
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
		C._exit(127)
	}
	C.close(to_child[0])
	C.close(from_child[1])
	if input.len > 0 {
		C.write(to_child[1], input.str, usize(input.len))
	}
	C.close(to_child[1])
	mut output := []u8{}
	mut chunk := []u8{len: 4096}
	echo := if os.exists('/etc/hwtest-echo') { C.open(&char(console_path.str), C.O_WRONLY) } else { -1 }
	for {
		got := C.read(from_child[0], chunk.data, usize(chunk.len))
		if got <= 0 {
			break
		}
		output << chunk[..got]
		if echo >= 0 {
			// For finding out where a program stopped: what it prints, as
			// it prints it.
			C.write(echo, chunk.data, usize(got))
		}
	}
	C.close(from_child[0])
	mut status := i32(0)
	for C.waitpid(child, &status, 0) < 0 {
		if C.errno != C.EINTR {
			break
		}
	}
	return Ran{
		status: if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
		output: output.bytestr()
	}
}

// The guest's own probes, run as an account: `/sbin/init probe <what>`.
fn probe(what []string, db accountcore.Database, user accountcore.User) Ran {
	mut argv := ['/sbin/init', 'probe']
	argv << what
	return run(argv, '', db, user)
}

fn load_db() accountcore.Database {
	return accountcore.Store{}.load() or {
		println('cannot load the account database: ${err.msg()}')
		accountcore.Database{}
	}
}

fn must_user(db accountcore.Database, name string) accountcore.User {
	return db.user(name) or { accountcore.User{} }
}

// The system as the scenarios start from: the accounts every system has,
// an administrator and someone who is not one.
const alex_password = 'alex has a password'
const sam_password = 'sam has another'

fn (mut t Test) make_accounts() accountcore.Database {
	init := run(['/usr/sbin/vinix-account', 'init'], '', none, none)
	t.check(init.status == 0, 'vinix-account init: ${init.output}')
	alex := run(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex Example', 'admin'], alex_password +
		'\n', none, none)
	t.check(alex.status == 0, 'adding alex: ${alex.output}')
	sam := run(['/usr/sbin/vinix-account', 'add', 'sam', 'Sam Example'], sam_password + '\n',
		none, none)
	t.check(sam.status == 0, 'adding sam: ${sam.output}')
	return load_db()
}

fn has_user(db accountcore.Database, name string) bool {
	db.user(name) or { return false }
	return true
}

fn has_group(db accountcore.Database, name string) bool {
	db.group(name) or { return false }
	return true
}

fn has_shadow(db accountcore.Database, name string) bool {
	db.shadow(name) or { return false }
	return true
}

// Start the authentication service and wait until it listens.
fn (mut t Test) start_authd() {
	child := C.fork()
	if child == 0 {
		argv := [&char(c'/usr/sbin/vinix-authd'), &char(unsafe { nil })]
		envp := [&char(c'PATH=/usr/sbin:/usr/bin:/sbin:/bin'), &char(unsafe { nil })]
		C.execve(argv[0], &argv[0], &envp[0])
		C._exit(127)
	}
	for _ in 0 .. 100 {
		if os.exists('/run/vinix/auth.sock') {
			// An installed root can retain yesterday's socket. Require a live,
			// root-authenticated response rather than only the pathname.
			mut reply := authclient.ask_root(authclient.default_socket, authproto.op_info) or {
				C.usleep(100_000)
				continue
			}
			ready := reply.code == authproto.status_ok
			reply.close()
			if ready { return }
		}
		C.usleep(100_000)
	}
	t.check(false, 'the authentication service did not start')
}
