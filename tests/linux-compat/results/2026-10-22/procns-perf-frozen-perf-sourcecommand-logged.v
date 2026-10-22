// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecommand

import os

// Keep an idle private stdin pipe open through the observer and final reap,
// as Popen(stdin=PIPE) does, without changing the parent's standard slots.
pub fn run_logged_pipe_owned(argv []string, environment map[string]string, cancel fn () bool, log string, spawned fn (int, voidptr) !, context voidptr, shutdown_grace f64) !Output {
	if log == '' || log.contains('\x00') { return error('invalid command log') }
	mut pipes := [i32(-1), -1]!
	defer { for fd in pipes { if fd >= 0 { C.close(fd) } }
	 }
	if C.pipe(&pipes[0]) != 0 { return os.error_posix() }
	for index in 0 .. 2 {
		if pipes[index] < 3 {
			moved := C.fcntl(pipes[index], C.F_DUPFD_CLOEXEC, 3)
			if moved < 0 { return os.error_posix() }
			C.close(pipes[index])
			pipes[index] = moved
		} else if C.fcntl(pipes[index], C.F_SETFD, C.FD_CLOEXEC) != 0 {
			return os.error_posix()
		}
	}
	return capture_stream_input_arch(argv, environment, -1, 0, cancel, unsafe { nil }, spawned, context, shutdown_grace, false, true, '', log, false, '', '', false, 64 * 1024, false, pipes[0])!
}
