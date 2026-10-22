// SPDX-License-Identifier: GPL-2.0-or-later
// The socketpair is created by root before the real client drops all IDs.
module main

import authproto
import loginchannel
import os
import time

#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>

fn C.socketpair(int, int, int, &i32) int
fn C.fork() int
fn C.setgroups(usize, voidptr) int
fn C.setresgid(u32, u32, u32) int
fn C.setresuid(u32, u32, u32) int
fn C.getuid() u32
fn C.getgid() i32
fn C.geteuid() u32
fn C.getegid() i32
fn C.dup2(int, int) int
fn C.close(int) int
fn C.open(&char, int, ...int) int
fn C.waitpid(int, &int, int) int
fn C.write(int, voidptr, usize) isize
fn C.recv(int, voidptr, usize, int) isize
fn C._exit(int)
fn C.signal(int, voidptr) voidptr

fn drop() {
	assert C.setgroups(0, unsafe { nil }) == 0
	assert C.setresgid(100, 100, 100) == 0
	assert C.setresuid(100, 100, 100) == 0
	assert C.getuid() == 100 && C.geteuid() == 100 && C.getgid() == 100 && C.getegid() == 100
}

fn reap(pid int) {
	mut status := 0
	assert C.waitpid(pid, &status, 0) == pid
	assert status == 0
}

fn refuse(err IError) {
	message := err.msg()
	assert message.len > 0
	unsafe {
		message.free()
		err.free()
	}
}

fn ordinary_refusals() {
	C.close(3)
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	if pair[0] != 3 {
		assert C.dup2(pair[0], 3) == 3
		C.close(pair[0])
	}
	os.setenv('VINIX_SESSION_FD', '3', true)
	name := 'person'.bytes()
	password := 'forged socket must never receive this'.bytes()
	defer { unsafe {
		name.free()
		password.free()
	}
	 }
	mut refused := false
	loginchannel.login(name, password) or {
		refuse(err)
		refused = true
	}
	assert refused && password.all(it == 0)
	mut byte := u8(0)
	assert C.recv(pair[1], &byte, 1, C.MSG_DONTWAIT) < 0 && C.errno == C.EAGAIN
	C.close(pair[1])
	C.close(3)
	println('LOGIN CHANNEL ordinary forged peer refused before disclosure PASS')
	fd := C.open(c'/dev/null', C.O_RDONLY)
	assert fd >= 0
	if fd != 3 {
		assert C.dup2(fd, 3) == 3
		C.close(fd)
	}
	refused = false
	loginchannel.inherited() or {
		refuse(err)
		refused = true
	}
	assert refused
	C.close(3)
	os.setenv('VINIX_SESSION_FD', '4', true)
	refused = false
	loginchannel.inherited() or {
		refuse(err)
		refused = true
	}
	assert refused
	println('LOGIN CHANNEL regular fd and arbitrary descriptor refused PASS')
}

fn root_pair(partial bool) {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(pair[0])
		assert C.dup2(pair[1], 3) == 3
		if pair[1] != 3 { C.close(pair[1]) }
		drop()
		os.setenv('VINIX_SESSION_FD', '3', true)
		loginchannel.inherited() or { panic(err) }
		assert C.fcntl(3, C.F_GETFD) & C.FD_CLOEXEC != 0
		if partial {
			started := time.sys_mono_now()
			mut refused := false
			loginchannel.reply() or {
				refuse(err)
				refused = true
			}
			elapsed := time.sys_mono_now() - started
			assert refused && elapsed >= 1_000_000_000 && elapsed < 6_000_000_000
			println('LOGIN CHANNEL partial reply bounded refusal PASS')
			C._exit(0)
		}
		loginchannel.prepare_replacement() or { panic(err) }
		assert C.fcntl(3, C.F_GETFD) & C.FD_CLOEXEC == 0
		loginchannel.inherited() or { panic(err) }
		grandchild := C.fork()
		assert grandchild >= 0
		if grandchild == 0 {
			os.execvp('/sbin/init', ['--exec-probe']) or { panic(err) }
			C._exit(99)
		}
		reap(grandchild)
		println('LOGIN CHANNEL ordinary exec loses manager capability PASS')
		name := 'person'.bytes()
		password := 'literal ; bounded secret'.bytes()
		loginchannel.login(name, password) or { panic(err) }
		assert password.all(it == 0)
		unsafe {
			name.free()
			password.free()
		}
		mut answer := loginchannel.reply() or { panic(err) }
		assert answer.code == authproto.status_ok && answer.fields.len == 0
		answer.close()
		assert C.fcntl(3, C.F_GETFD) >= 0
		println('LOGIN CHANNEL root-created peer survives ordinary UID drop PASS')
		deadline := time.sys_mono_now() + 3_000_000_000
		for !loginchannel.ready() && time.sys_mono_now() < deadline {
			time.sleep(10 * time.millisecond)
		}
		assert loginchannel.ready()
		mut refused := false
		loginchannel.reply() or {
			refuse(err)
			refused = true
		}
		assert refused && C.fcntl(3, C.F_GETFD) >= 0
		println('LOGIN CHANNEL hangup fails without closing borrowed descriptor PASS')
		ordinary_refusals()
		C._exit(0)
	}
	C.close(pair[1])
	if partial {
		byte := u8(0)
		assert C.write(pair[0], &byte, 1) == 1
		reap(pid)
		C.close(pair[0])
		return
	}
	mut frame := authproto.read_frame(pair[0]) or { panic(err) }
	assert frame.code == loginchannel.op_login && frame.fields.len == 2
	assert frame.fields[0] == 'person'.bytes() && frame.fields[1] == 'literal ; bounded secret'.bytes()
	frame.close()
	authproto.write_frame(pair[0], authproto.Frame{ code: authproto.status_ok }) or { panic(err) }
	C.close(pair[0])
	reap(pid)
}

fn main() {
	if '--exec-probe' in os.args {
		assert C.geteuid() == 100 && C.fcntl(3, C.F_GETFD) < 0
		return
	}
	$if amd64 {
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		if serial >= 0 {
			C.dup2(serial, 1)
			C.dup2(serial, 2)
			if serial > 2 { C.close(serial) }
		}
	}
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	println('HWTEST START login-channel')
	assert C.geteuid() == 0
	root_pair(false)
	root_pair(true)
	println('HWTEST PASS login-channel')
	for { time.sleep(time.second) }
}
