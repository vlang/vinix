// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-session: where sessions come from. Run by root -- by init, or by
// something init started -- it is the only place a process stops being
// root and becomes a person's.
//
//	vinix-session run [--seat|--isolated] USER COMMAND [ARGUMENT...]
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
import authproto
import os
import sessioncore
import tools.packages.pkgadmin
import tools.packages.pkglaunch

#include <termios.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>

fn C.geteuid() u32
fn C.tcgetattr(fd int, termios voidptr) int
fn C.tcsetattr(fd int, action int, termios voidptr) int
fn C.sleep(seconds u32) u32
fn C.alarm(u32) u32

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
fn run_as(db accountcore.Database, user accountcore.User, argv []string, at_seat bool, isolated bool) int {
	started := if isolated {
		sessioncore.start_isolated(db, user, argv) or {
			eprintln('vinix-session: ${err.msg()}')
			return 126
		}
	} else {
		sessioncore.start(db, user, argv, at_seat, -1, sessioncore.Unlock{}) or {
			eprintln('vinix-session: ${err.msg()}')
			return 126
		}
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
		reply := sessioncore.verify_login('/run/vinix/auth.sock', name,
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
		run_as(db, user, [shell, '-l'], true, false)
	}
}

fn main() {
	args := os.args[1..]
	if C.geteuid() != 0 {
		fail('must be started by root')
	}
	if args == ['package-launch'] {
		exit(package_launch() or { eprintln('vinix-session: ${err}'); 126 })
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
	mut isolated := false
	if rest.len >= 2 && rest[0] == 'run' && rest[1] == '--seat' {
		at_seat = true
		rest.delete(1)
	} else if rest.len >= 2 && rest[0] == 'run' && rest[1] == '--isolated' {
		isolated = true
		rest.delete(1)
	}
	if rest.len < 3 || rest[0] != 'run' || rest[1].starts_with('--') {
		eprintln('usage: vinix-session run [--seat|--isolated] USER COMMAND [ARGUMENT...] | console | manager [--greeter COMMAND...] [--desktop COMMAND...]')
		exit(2)
	}
	db := load()
	user := db.user(rest[1]) or {
		fail('no user ${rest[1]}')
		return
	}
	exit(run_as(db, user, rest[2..].clone(), at_seat, isolated))
}

// Called only by the fixed account action. The kernel-authenticated caller
// chooses an installed package, never the executable or identity to run.
fn package_launch() !int {
	identity := os.getenv('VINIX_AUTH_UID')
	if identity.len == 0 || identity.len > 10 || identity[0] == `0` || !identity.bytes().all(it >= `0` && it <= `9`) || identity.u64() > 0xffffffff {
		return error('the account service supplied no ordinary launch identity')
	}
	uid := u32(identity.u64())
	// This process will become the caller. Never bring shadow hashes into
	// its address space; the isolated profile needs only public identities.
	store := accountcore.Store{}
	held := store.lock(false)!
	db := accountcore.Database{
		users: accountcore.parse_passwd(accountcore.read_trusted(store.passwd_path(), false, store.owned)!)!
		groups: accountcore.parse_group(accountcore.read_trusted(store.group_path(), false, store.owned)!)!
	}
	held.release()
	db.validate()!
	user := db.user_by_uid(uid) or { return error('the launch account no longer exists') }
	if !accountcore.is_person(user) || user.gid == 0 { return error('isolated launch requires an ordinary account and group') }
	for path in ['/usr', '/usr/bin', '/usr/bin/vinix-package'] {
		info := os.lstat(path)!
		if info.uid != 0 || info.mode & 0o022 != 0 || (if path == '/usr/bin/vinix-package' { info.mode & 0o170000 != 0o100000 || info.mode & 0o111 == 0 } else { info.get_filetype() != .directory }) {
			return error('the installed package service is not root-owned and protected')
		}
	}
	mut bytes := [33]u8{}
	mut used := 0
	for used < bytes.len {
		count := C.read(0, unsafe { &bytes[used] }, usize(bytes.len - used))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read isolated launch invitation') }
		if count == 0 { break }
		used += int(count)
	}
	nonce := unsafe { tos(&bytes[0], used) }
	if !pkglaunch.valid_nonce(nonce) { return error('invalid isolated launch invitation') }
	directory := pkgadmin.runtime_directory(uid)!
	fd := pkgadmin.connect_private(directory, uid, nonce)!
	defer { C.close(fd) }
	child := C.fork()
	if child < 0 { return error('cannot start isolated launch worker') }
	if child == 0 {
		C.alarm(0)
		if C.setsid() < 0 { C._exit(126) }
		// Release the authentication action's pipes before waiting for the
		// client's request/rights: its reply requires EOF on those pipes.
		empty := C.open(c'/dev/null', C.O_RDWR | C.O_NOFOLLOW)
		if empty < 0 { C._exit(126) }
		for descriptor in 0 .. 3 { if C.dup2(empty, descriptor) != descriptor { C._exit(126) } }
		C.close(empty)
		code := package_launch_worker(fd, nonce, db, user) or { 126 }
		C._exit(code)
	}
	println(nonce)
	return 0
}

fn package_launch_worker(fd int, nonce string, db accountcore.Database, user accountcore.User) !int {
	mut request := pkglaunch.receive_request(fd)!
	defer { request.close() }
	if request.nonce != nonce { return error('isolated launch invitation changed') }
	mut streams := pkglaunch.receive_streams(fd)!
	defer { for stream in streams { if stream >= 0 { C.close(stream) } } }
	for index, stream in streams { if C.dup2(stream, index) != index { return error('cannot attach application streams') } }
	for index in 0 .. streams.len { C.close(streams[index]); streams[index] = -1 }
	// No inherited auth-service descriptor is passed to the session child;
	// exec_as closes everything except the caller's three existing streams.
	for descriptor in 3 .. 1024 { if descriptor != fd { C.close(descriptor) } }
	started := sessioncore.start_isolated(db, user, ['/usr/bin/vinix-package', ...request.arguments])!
	// The supervisor also sheds root and account memberships before waiting.
	// Its cached socket peer credentials still prove who made the connection.
	sessioncore.become_isolated(user)!
	for descriptor in 0 .. 3 { C.close(descriptor) }
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	code := sessioncore.wait(started.pid)
	pkglaunch.send_result(fd, request, code)!
	return code
}
