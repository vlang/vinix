// SPDX-License-Identifier: GPL-2.0-or-later
module sessionipc

import desktop.sessioncore

// This endpoint is created before launching the broker. It is never obtained
// through the public socket, an environment variable, or a request argument.
__global session_control_fd int
__global session_control_owner int
__global session_control_pending bool

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.getppid() int

pub fn session_has_control() bool {
	return session_control_fd >= 3 && session_control_owner == C.getpid()
}

pub fn session_close_control() {
	// A forked child may discard its copy, but cannot use it through the API.
	if session_control_fd >= 3 { desktop_close(session_control_fd) }
	session_control_fd = 0
	session_control_owner = 0
	session_control_pending = false
}

// A broker accepts only a connected stream inherited from its launching parent.
// The descriptor, rather than a reconnecting process's numeric PID, grants the
// compositor domain. Peer credentials still identify clipboard/dialog owners.
pub fn session_control_peer(fd int) ?SessionCredentials {
	if fd < 3 { return none }
	mut kind := 0
	mut length := u32(sizeof(int))
	if C.getsockopt(fd, C.SOL_SOCKET, C.SO_TYPE, &kind, &length) != 0 || kind != C.SOCK_STREAM {
		return none
	}
	peer := session_peer(fd) or { return none }
	if peer.pid <= 0 || peer.pid != C.getppid() { return none }
	if !desktop_set_cloexec(fd, true) || !desktop_set_nonblocking(fd, true) { return none }
	return peer
}

pub fn session_start_broker(home string) ?int {
	executable := helper_path('vinix-session')
	defer { unsafe { executable.free() } }
	return session_start_broker_at(home, executable)
}

// Explicit executable selection also supports the desktop's legacy exec wrapper.
pub fn session_start_broker_at(home string, executable string) ?int {
	session_close_control()
	mut pair := [i32(-1), i32(-1)]!
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) != 0 { return none }
	if pair[0] < 3 || pair[1] < 3 || !desktop_set_cloexec(pair[0], true)
		|| !desktop_set_cloexec(pair[1], true) || !desktop_set_nonblocking(pair[0], true) {
		desktop_close(pair[0])
		desktop_close(pair[1])
		return none
	}
	home_arg := '--session-home=${home}'
	mut control_writer := sessioncore.Writer{}
	control_writer.add('--session-control-fd=')
	control_writer.number(pair[1])
	control_arg := control_writer.finish()
	defer {
		unsafe {
			home_arg.free()
			control_arg.free()
		}
	}
	argv := [&char(executable.str), c'--session-services', &char(home_arg.str), &char(control_arg.str),
		&char(unsafe { nil })]!
	pid := C.fork()
	if pid == 0 {
		if C.setsid() < 0 { C._exit(127) }
		for fd in 3 .. 4096 { if fd != pair[1] { C.close(fd) } }
		if !desktop_set_cloexec(pair[1], false) { C._exit(127) }
		C.execv(argv[0], &argv[0])
		C._exit(127)
	}
	desktop_close(pair[1])
	if pid < 0 {
		desktop_close(pair[0])
		return none
	}
	session_control_fd = pair[0]
	session_control_owner = C.getpid()
	session_control_pending = true
	return pid
}
