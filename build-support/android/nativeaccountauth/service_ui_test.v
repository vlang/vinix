// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

fn C.pipe(&i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32

fn ui_channel_fd_count() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(i32(fd), C.F_GETFD) >= 0 { count++ } }
	return count
}

fn test_ui_control_requires_kernel_root_stream_peer_without_closing_caller_fd() {
	for fd in [-1, 0, 1, 2, 0x7fffffff] {
		protect_ui_channel(fd) or { continue }
		panic('accepted invalid UI descriptor')
	}
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	defer { C.close(pipe[0]); C.close(pipe[1]) }
	protect_ui_channel(int(pipe[0])) or {
		assert C.fcntl(pipe[0], C.F_GETFD) >= 0
		return
	}
	panic('accepted pipe as root UI channel')
}

fn test_ui_control_rejects_datagrams_and_authenticates_stream_before_inheritance() {
	initial := ui_channel_fd_count()
	for kind in [C.SOCK_DGRAM, C.SOCK_STREAM] {
		mut pair := [2]i32{}
		assert C.socketpair(C.AF_UNIX, kind, 0, &pair[0]) == 0
		mut rejected := false
		protect_ui_channel(int(pair[0])) or { rejected = true }
		if kind == C.SOCK_STREAM && C.getuid() == 0 && C.getgid() == 0 {
			assert !rejected
			assert C.fcntl(pair[0], C.F_GETFD) & C.FD_CLOEXEC != 0
			inherit_ui_channel(int(pair[0]))!
			assert C.fcntl(pair[0], C.F_GETFD) & C.FD_CLOEXEC == 0
			protect_ui_channel(int(pair[0]))!
			assert C.fcntl(pair[0], C.F_GETFD) & C.FD_CLOEXEC != 0
		} else {
			assert rejected
			rejected = false
			inherit_ui_channel(int(pair[0])) or { rejected = true }
			assert rejected
			assert C.fcntl(pair[0], C.F_GETFD) >= 0
		}
		C.close(pair[0])
		C.close(pair[1])
	}
	assert ui_channel_fd_count() == initial
}
