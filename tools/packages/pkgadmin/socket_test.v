// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

import os
import time

#include <signal.h>
#include <sys/wait.h>
fn C.socketpair(int, int, int, &i32) int
fn C.fork() int
fn C.getpid() int
fn C.kill(int, int) int
fn C.signal(int, voidptr) voidptr
fn C.siginterrupt(int, int) int
fn C.usleep(u32) int
fn C.waitpid(int, &i32, int) int
fn C._exit(int)

fn ignore_admin_interrupt(_ i32) {}

fn admin_interrupt_handler() voidptr {
	previous := C.signal(C.SIGUSR1, voidptr(ignore_admin_interrupt))
	assert previous != voidptr(C.SIG_ERR)
	assert C.siginterrupt(C.SIGUSR1, 1) == 0
	return previous
}

fn interrupt_admin_waiter(parent int, count int) {
	for _ in 0 .. count {
		C.usleep(20_000)
		if C.kill(parent, C.SIGUSR1) != 0 { C._exit(92) }
	}
}

fn wait_for_admin_peer(pid int) {
	mut status := i32(0)
	for {
		result := C.waitpid(pid, &status, 0)
		if result < 0 && C.errno == C.EINTR { continue }
		assert result == pid && status == 0
		return
	}
}

fn test_admin_listener_accepts_delayed_root_after_signals() {
	if os.geteuid() != 0 { return }
	previous := admin_interrupt_handler()
	defer { C.signal(C.SIGUSR1, previous) }
	directory := '/tmp/vadm-accept-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir(directory) or {}; unsafe { directory.free() } }
	nonce := '0123456789abcdef0123456789abcdef'
	mut listener := listen_private(directory, 0, nonce)!
	defer { listener.close() }
	parent := C.getpid()
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(listener.fd)
		interrupt_admin_waiter(parent, 12)
		fd := connect_private(directory, 0, nonce) or { C._exit(93); return }
		if C.write(fd, c'r', 1) != 1 { C._exit(94) }
		C.close(fd)
		C._exit(0)
	}
	defer { wait_for_admin_peer(pid) }
	fd := listener.accept_root()!
	defer { C.close(fd) }
	mut byte := u8(0)
	assert C.read(fd, &byte, 1) == 1 && byte == `r`
}

fn test_admin_socket_deadline_survives_repeated_interruptions() {
	previous := admin_interrupt_handler()
	defer { C.signal(C.SIGUSR1, previous) }
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	parent := C.getpid()
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(pair[0])
		interrupt_admin_waiter(parent, 30)
		C._exit(0)
	}
	C.close(pair[1])
	defer { C.close(pair[0]) }
	defer { wait_for_admin_peer(pid) }
	start := time.sys_mono_now()
	assert !socket_ready(pair[0], 1, start + 150_000_000)
	elapsed := time.sys_mono_now() - start
	assert elapsed >= 150_000_000 && elapsed < 500_000_000
}

fn test_admin_socket_recovers_write_readiness_after_signals() {
	previous := admin_interrupt_handler()
	defer { C.signal(C.SIGUSR1, previous) }
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
	mut data := [4096]u8{}
	mut queued := 0
	limit := 2 * 1024 * 1024
	for queued < limit {
		written := C.write(pair[0], &data[0], data.len)
		if written < 0 {
			assert C.errno == C.EAGAIN
			break
		}
		assert written > 0
		queued += written
	}
	assert queued > 0 && queued < limit
	mut readiness := Poll{ fd: pair[0], events: 4 }
	assert C.vinix_package_admin_poll(voidptr(&readiness), 1, 0) == 0
	parent := C.getpid()
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(pair[0])
		interrupt_admin_waiter(parent, 4)
		for queued > 0 {
			count := C.read(pair[1], &data[0], if queued < data.len { queued } else { data.len })
			if count <= 0 { C._exit(95) }
			queued -= count
		}
		if C.read(pair[1], &data[0], 1) != 1 || data[0] != `w` { C._exit(96) }
		C._exit(0)
	}
	C.close(pair[1])
	defer {
		C.close(pair[0])
		wait_for_admin_peer(pid)
	}
	assert socket_ready(pair[0], 4, time.sys_mono_now() + 2_000_000_000)
	assert C.write(pair[0], c'w', 1) == 1
}

fn test_private_socket_admits_only_its_account_and_never_removes_existing_names() {
	directory := os.temp_dir() + '/vinix-package-admin-socket-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {} }
	uid := u32(os.geteuid())
	nonce := 'a'.repeat(32)
	mut listener := listen_private(directory, uid, nonce)!
	defer { listener.close() }
	assert os.lstat(listener.path)!.get_filetype() == .socket
	fd := connect_private(directory, uid, nonce)!
	C.close(fd)
	mut existing := false
	listen_private(directory, uid, nonce) or { existing = true; unsafe { err.free() } }
	assert existing && os.exists(listener.path)
	os.chmod(directory, 0o755)!
	mut unsafe_directory := false
	connect_private(directory, uid, nonce) or { unsafe_directory = true; unsafe { err.free() } }
	assert unsafe_directory
	os.chmod(directory, 0o700)!
	alias := directory + '-link'
	os.symlink(directory, alias)!
	defer { os.rm(alias) or {} }
	mut linked := false
	listen_private(alias, uid, nonce) or { linked = true; unsafe { err.free() } }
	assert linked
}
