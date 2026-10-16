// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import desktop.sessionipc

__global session_child_pid int

struct SessionMessage {
mut:
	pid    int
	fields [24]sessioncore.Text
	count  int
}

fn session_runtime_directory() string { return sessionipc.session_runtime_directory() }

fn session_private_directory(path string) bool { return sessionipc.session_private_directory(path) }

fn session_peer(fd int) ?sessionipc.SessionCredentials { return sessionipc.session_peer(fd) }

fn session_connect() ?int { return sessionipc.session_connect() }

fn session_send_message(fd int, data string) bool {
	return sessionipc.session_send_message(fd, data)
}

fn session_receive(fd int) !string { return sessionipc.session_receive(fd) }

fn session_call(command string, args []string) !string {
	return sessionipc.session_call(command, args)
}

fn session_call_ok(command string, args []string) bool {
	return sessionipc.session_call_ok(command, args)
}

fn session_start(home string) bool {
	if session_call_ok('ping', []) { return true }
	if session_child_pid > 0 {
		mut status := 0
		if C.waitpid(session_child_pid, &status, C.WNOHANG) == 0 { return true }
		session_child_pid = 0
	}
	executable := sessionipc.helper_path('vinix-session')
	home_arg := '--session-home=${home}'
	owner_arg := '--session-owner=${C.getpid()}'
	defer { unsafe { owner_arg.free() } }
	argv := [&char(executable.str), &char(home_arg.str), &char(owner_arg.str), &char(unsafe { nil })]!
	defer {
		unsafe {
			executable.free()
			home_arg.free()
		}
	}
	pid := C.fork()
	if pid < 0 { return false }
	if pid == 0 {
		C.setsid()
		for fd in 3 .. 4096 { C.close(fd) }
		C.execv(&char(executable.str), &argv[0])
		C._exit(127)
	}
	// No startup wait on the compositor's input thread. Later polls connect.
	session_child_pid = pid
	return true
}

fn session_exec_helper(name string, args []string) {
	sessionipc.exec_helper(name, args) or {
		eprintln(err)
		exit(127)
	}
}
