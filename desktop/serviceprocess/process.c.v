// SPDX-License-Identifier: GPL-2.0-or-later
// Launch services through a small dedicated guardian. Closing the broker's
// lease still terminates the whole service group if the broker disappears.
module serviceprocess

import desktop.sessioncore
import desktop.sessionipc

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.execv(&char, &&char) int

pub struct Process {
pub:
	pid   int
	lease int
}

pub fn status(lease int, fallback int) int {
	if lease <= 0 { return fallback }
	defer { C.close(lease) }
	mut result := i32(0)
	if C.read(lease, &result, sizeof(i32)) != sizeof(i32) { return fallback }
	return int(result)
}

pub fn start(service sessioncore.Service, home string) Process {
	directory := '${home}/.vinix-service-logs'
	defer { unsafe { directory.free() } }
	if !sessionipc.session_private_directory(directory) { return Process{-1, -1} }
	path := '${directory}/${service.name.str()}.log'
	defer { unsafe { path.free() } }
	log := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_APPEND | C.O_NOFOLLOW | C.O_CLOEXEC, u32(0o600))
	if log < 0 { return Process{-1, -1} }
	defer { C.close(log) }
	mut lease := [i32(-1), i32(-1)]!
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &lease[0]) != 0 { return Process{-1, -1} }
	if !sessionipc.desktop_set_cloexec(lease[0], true)
		|| !sessionipc.desktop_set_cloexec(lease[1], true)
		|| !sessionipc.desktop_set_nonblocking(lease[0], true) {
		C.close(lease[0])
		C.close(lease[1])
		return Process{-1, -1}
	}
	runner := sessionipc.helper_path('vinix-service-runner')
	lease_arg := '--lease-fd=${lease[1]}'
	defer { unsafe {
		runner.free()
		lease_arg.free()
	}
	 }
	mut argv := unsafe { [21]&char{} }
	argv[0] = &char(runner.str)
	argv[1] = &char(lease_arg.str)
	argv[2] = c'--'
	argv[3] = &char(service.executable.str().str)
	for i in 0 .. service.argument_count { argv[i + 4] = &char(service.arguments[i].str().str) }
	pid := C.fork()
	if pid == 0 {
		if C.setsid() < 0 { C._exit(127) }
		input := C.open(c'/dev/null', C.O_RDONLY, 0)
		if input >= 0 { C.dup2(input, 0) }
		C.dup2(log, 1)
		C.dup2(log, 2)
		for fd in 3 .. 4096 { if fd != lease[1] { C.close(fd) } }
		if !sessionipc.desktop_set_cloexec(lease[1], false) { C._exit(127) }
		C.execv(argv[0], &argv[0])
		C._exit(127)
	}
	C.close(lease[1])
	if pid < 0 {
		C.close(lease[0])
		return Process{-1, -1}
	}
	return Process{pid, lease[0]}
}
