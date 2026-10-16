// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// vinix-authd: the authentication service. It is the one program that
// reads the password file, and the one way from an ordinary account to
// something done as root: there are no set-user-id programs on Vinix.
//
// It listens on a Unix socket anyone may connect to. The kernel says who is
// on the other end; the request cannot. Each connection is one request and
// one reply, handled in a process of its own that exits afterwards, so a
// request can neither leave anything behind in the service nor take it
// down, and a request that never finishes is ended by an alarm.
//
//	vinix-authd                          serve on /run/vinix/auth.sock
//	vinix-authd --root DIR --foreground  serve DIR/run/vinix/auth.sock from
//	                                     the accounts and actions under DIR,
//	                                     as whoever runs it: for tests
module main

import accountcore
import authcore
import authproto
import os

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
$if !linux {
	#include <sys/ucred.h>
}

fn C.socket(domain int, kind int, protocol int) int
fn C.bind(fd int, address voidptr, length u32) int
fn C.listen(fd int, backlog int) int
fn C.accept(fd int, address voidptr, length voidptr) int
fn C.getsockopt(fd int, level int, name int, value voidptr, length &u32) int
fn C.fork() int
fn C.waitpid(pid int, status &i32, options int) int
fn C.alarm(seconds u32) u32
fn C.signal(signal int, handler voidptr) voidptr
fn C.geteuid() u32
fn C.chmod(path &char, mode u32) int
fn C.unlink(path &char) int
fn C._exit(status int)
fn C.umask(mask u32) u32
$if !linux {
	fn C.getpeereid(fd int, uid &u32, gid &u32) int
}

struct C.sockaddr_un {
mut:
	sun_family u16
	sun_path   [108]char
}

struct Ucred {
mut:
	pid i32
	uid u32
	gid u32
}

// How long one request may take, password check and action included.
const request_seconds = u32(150)
// How long the request itself may take to arrive.
const read_seconds = u32(10)
// Requests in progress at once, in all and from one user. What is over is
// not queued: the connection is closed and the caller may try again.
const max_children = 16
const max_per_user = 4

struct Child {
mut:
	pid int
	uid u32
}

fn peer_of(fd int) ?authcore.Peer {
	$if linux {
		mut cred := Ucred{}
		mut length := u32(sizeof(Ucred))
		// SOL_SOCKET 1, SO_PEERCRED 17.
		if C.getsockopt(fd, 1, 17, &cred, &length) != 0 || length != u32(sizeof(Ucred)) {
			return none
		}
		return authcore.Peer{
			pid: int(cred.pid)
			uid: cred.uid
			gid: cred.gid
		}
	} $else {
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(fd, &uid, &gid) != 0 {
			return none
		}
		return authcore.Peer{
			uid: uid
			gid: gid
		}
	}
}

fn reap(mut children []Child, block bool) {
	for {
		mut status := i32(0)
		pid := C.waitpid(-1, &status, if block { 0 } else { C.WNOHANG })
		if pid <= 0 {
			return
		}
		for i, child in children {
			if child.pid == pid {
				children.delete(i)
				break
			}
		}
		if block {
			return
		}
	}
}

fn serve(env authcore.Env, connection int, peer authcore.Peer) {
	// A caller that connects and says nothing is not waited for long.
	C.alarm(read_seconds)
	mut request := authproto.read_frame(connection) or { return }
	defer { request.close() }
	C.alarm(request_seconds)
	mut response := authcore.handle(env, peer, mut request)
	defer { response.close() }
	authproto.write_frame(connection, response) or {}
}

fn fail(message string) {
	eprintln('vinix-authd: ${message}')
	exit(1)
}

fn main() {
	mut root := ''
	mut args := os.args[1..].clone()
	for args.len > 0 {
		match args[0] {
			'--root' {
				if args.len < 2 {
					fail('--root needs a directory')
				}
				root = args[1]
				args = args[2..].clone()
			}
			'--foreground' {
				args = args[1..].clone()
			}
			else {
				fail('unknown argument ${args[0]}')
			}
		}
	}
	testing := root != ''
	if !testing && C.geteuid() != 0 {
		fail('must be started as root')
	}
	run_dir := os.join_path(root + '/run', 'vinix')
	socket_path := os.join_path(run_dir, 'auth.sock')
	cost := accountcore.configured_cost(root + '/etc/vinix/auth.conf', !testing) or {
		fail(err.msg())
		return
	}
	env := authcore.Env{
		store:    accountcore.Store{
			etc:   root + '/etc'
			owned: !testing
		}
		throttle: accountcore.Throttle{
			directory: os.join_path(run_dir, 'auth', 'failures')
		}
		actions:  root + '/usr/share/vinix/actions'
		session:  os.join_path(run_dir, 'session', 'active')
		log:      root + '/var/log/vinix/auth.log'
		cost:     cost
	}
	// Fail now rather than at the first login if the accounts are unusable.
	env.store.load() or { fail('cannot use the account database: ${err.msg()}') }

	C.umask(0o022)
	os.mkdir_all(run_dir, mode: 0o755) or { fail('cannot create ${run_dir}') }
	if socket_path.len >= 100 {
		fail('socket path too long')
	}
	C.unlink(&char(socket_path.str))
	listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if listener < 0 {
		fail('cannot create a socket')
	}
	mut address := C.sockaddr_un{}
	address.sun_family = u16(C.AF_UNIX)
	unsafe { vmemcpy(&address.sun_path[0], socket_path.str, socket_path.len) }
	if C.bind(listener, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		fail('cannot bind ${socket_path}')
	}
	// Anyone may ask; what they are told depends on who they are.
	if C.chmod(&char(socket_path.str), 0o666) != 0 || C.listen(listener, 16) != 0 {
		fail('cannot listen on ${socket_path}')
	}
	C.signal(C.SIGPIPE, voidptr(1))
	println('vinix-authd: listening on ${socket_path}')

	mut children := []Child{cap: max_children}
	for {
		reap(mut children, false)
		connection := C.accept(listener, unsafe { nil }, unsafe { nil })
		if connection < 0 {
			continue
		}
		peer := peer_of(connection) or {
			C.close(connection)
			continue
		}
		reap(mut children, false)
		mut from_user := 0
		for child in children {
			if child.uid == peer.uid {
				from_user++
			}
		}
		if children.len >= max_children || from_user >= max_per_user {
			C.close(connection)
			continue
		}
		pid := C.fork()
		if pid == 0 {
			C.close(listener)
			serve(env, connection, peer)
			C._exit(0)
		}
		C.close(connection)
		if pid > 0 {
			children << Child{
				pid: pid
				uid: peer.uid
			}
		}
	}
}
