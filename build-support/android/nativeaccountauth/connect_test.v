// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

import os

fn connection_fd_count() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(i32(fd), C.F_GETFD) >= 0 { count++ } }
	return count
}

fn test_authenticator_connector_rejects_invalid_or_missing_paths_without_fd_leaks() {
	path := '/tmp/vinix-auth-connect-${C.getpid()}.sock'
	assert !os.exists(path)
	initial := connection_fd_count()
	for _ in 0 .. 32 {
		for invalid in ['', '/', 'relative.sock', path + '/', '/tmp/../tmp/x', path + '\x00x', path] {
			mut refused := false
			connect_authenticator(invalid) or { refused = true; -1 }
			assert refused, invalid
		}
	}
	assert connection_fd_count() == initial
}

fn test_authenticator_connector_authenticates_kernel_peer_and_protects_descriptor() {
	path := '/tmp/vinix-auth-peer-${C.getpid()}.sock'
	assert !os.exists(path)
	mut address := C.sockaddr_un{}
	$if macos { address.sun_len = u8(sizeof(C.sockaddr_un)) }
	address.sun_family = C.AF_UNIX
	for index, byte in path { address.sun_path[index] = char(byte) }
	listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	assert listener >= 0
	defer { C.close(listener); os.rm(path) or {} }
	assert C.bind(listener, voidptr(&address), u32(sizeof(C.sockaddr_un))) == 0
	initial := connection_fd_count()
	mut refused := false
	connect_authenticator(path) or { refused = true; -1 }
	assert refused && connection_fd_count() == initial
	assert C.listen(listener, 1) == 0
	refused = false
	fd := connect_authenticator(path) or { refused = true; -1 }
	if C.getuid() == 0 && C.getgid() == 0 {
		assert !refused && fd >= 3
		assert C.fcntl(i32(fd), C.F_GETFD) & C.FD_CLOEXEC != 0
		assert C.fcntl(i32(fd), C.F_GETFL) & C.O_NONBLOCK != 0
		C.close(i32(fd))
	} else {
		assert refused && fd == -1
	}
	assert connection_fd_count() == initial
}
