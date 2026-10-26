module nativeaccountauth

import os

#include <poll.h>
#include <signal.h>
#include <sys/wait.h>

fn C.getpid() i32
fn C.getuid() u32
fn C.getgid() i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.pipe(&i32) i32
fn C.close(int) int
fn C.fork() i32
fn C._exit(i32)
fn C.kill(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn rejected_peer(fd int) bool {
	peer_credentials(fd) or { return true }
	return false
}

fn test_account_peer_reads_kernel_identity_from_unix_stream() {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	for fd in sockets {
		peer := peer_credentials(fd)!
		assert peer.pid == C.getpid()
		assert peer.uid == C.getuid()
		assert peer.gid == u32(C.getgid())
	}
}

fn test_account_peer_rejects_non_connection_descriptors() {
	assert rejected_peer(-1)
	too_large := i64(0x100000000)
	if sizeof(int) > sizeof(i32) { assert rejected_peer(int(too_large)) }
	mut pipes := [2]i32{}
	assert C.pipe(&pipes[0]) == 0
	assert rejected_peer(pipes[0])
	assert rejected_peer(pipes[1])
	C.close(pipes[0])
	C.close(pipes[1])
	mut file := os.open(@FILE)!
	assert rejected_peer(file.fd)
	file.close()
	for family in [C.AF_UNIX, C.AF_INET] {
		for kind in [C.SOCK_STREAM, C.SOCK_DGRAM] {
			fd := C.socket(family, kind, 0)
			assert fd >= 0
			assert rejected_peer(fd)
			C.close(fd)
		}
	}
	mut datagrams := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_DGRAM, 0, &datagrams[0]) == 0
	assert rejected_peer(datagrams[0])
	assert rejected_peer(datagrams[1])
	C.close(datagrams[0])
	C.close(datagrams[1])
}

fn test_account_peer_identifies_the_remote_process() {
	path := '/tmp/vinix-account-peer-${C.getpid()}'
	assert !os.exists(path)
	mut address := C.sockaddr_un{}
	$if macos { address.sun_len = u8(sizeof(C.sockaddr_un)) }
	address.sun_family = C.AF_UNIX
	assert path.len < address.sun_path.len
	for i, byte in path { address.sun_path[i] = char(byte) }
	listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	assert listener >= 0
	defer { C.close(listener) }
	assert C.bind(listener, voidptr(&address), u32(sizeof(C.sockaddr_un))) == 0
	defer { os.rm(path) or {} }
	assert C.listen(listener, 1) == 0
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.close(listener)
		client := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		if client < 0 || C.connect(client, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
			C._exit(1)
		}
		// Hold the endpoint until its parent has inspected the connection.
		mut ready := C.pollfd{ fd: client, events: C.POLLIN }
		C.poll(&ready, 1, 3000)
		C.close(client)
		C._exit(0)
	}
	defer {
		C.kill(child, C.SIGKILL)
		mut status := i32(0)
		C.waitpid(child, &status, 0)
	}
	mut ready := C.pollfd{ fd: listener, events: C.POLLIN }
	assert C.poll(&ready, 1, 2000) == 1
	assert ready.revents & C.POLLIN != 0
	accepted := C.accept(listener, unsafe { nil }, unsafe { nil })
	assert accepted >= 0
	defer { C.close(accepted) }
	peer := peer_credentials(accepted)!
	assert peer.pid == child
	assert peer.pid != C.getpid()
	assert peer.uid == C.getuid()
	assert peer.gid == u32(C.getgid())
}
