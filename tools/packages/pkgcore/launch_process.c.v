// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Keep the launch status channel away from standard streams, even when a
// caller deliberately closed one. Only the child keeps the write end at fork.
fn launch_status_pipe() ![2]i32 {
	mut fds := [i32(-1), -1]!
	mut code := -1
	$if linux { code = C.pipe2(unsafe { &fds[0] }, C.O_CLOEXEC) }
	$else { code = C.pipe(unsafe { &fds[0] }) }
	if code != 0 { return error('cannot create application launch status pipe') }
	mut accepted := false
	defer { if !accepted { C.close(fds[0]); C.close(fds[1]) } }
	for index in 0 .. 2 {
		if fds[index] < 3 {
			fd := C.fcntl(fds[index], C.F_DUPFD_CLOEXEC, 3)
			if fd < 0 { return error('cannot retain application launch status pipe') }
			C.close(fds[index]); fds[index] = i32(fd)
		}
		if C.fcntl(fds[index], C.F_SETFD, C.FD_CLOEXEC) != 0 {
			return error('cannot protect application launch status pipe')
		}
	}
	if C.fcntl(fds[0], C.F_SETFL, C.O_NONBLOCK) != 0 { return error('cannot configure application launch status pipe') }
	accepted = true
	return fds
}

// No allocation, formatting or libc environment lookup after fork. A small
// atomic record lets the parent report the original stage and errno safely.
fn launch_child_failure(fd int, stage i32, code i32) {
	record := [stage, code]!
	for {
		written := C.write(fd, unsafe { &record[0] }, 8)
		if written < 0 && C.errno == C.EINTR { continue }
		break
	}
}

fn launch_wait(pid int) !int {
	mut status := i32(0)
	for {
		waited := C.vinix_package_waitpid(pid, unsafe { &status }, 0)
		if waited < 0 && C.errno == C.EINTR { continue }
		if waited != pid { return error('cannot collect application process status') }
		return if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
	}
}

// Borrow the complete plan until its synchronous child has exited. execv
// inherits the caller's environment and streams without rebuilding maps or
// retaining Process/spawn buffers. The existing outer owner keeps the lease.
fn run_launch_process(launch Launch) !int {
	if !launch.program.starts_with('/') || !launch.directory.starts_with('/')
		|| launch.program.contains('\x00') || launch.directory.contains('\x00') {
		return error('application launch requires absolute executable and working-directory paths without NUL')
	}
	for argument in launch.arguments {
		if argument.contains('\x00') { return error('application launch argument contains NUL') }
	}
	mut argv := []&char{cap: launch.arguments.len + 2}
	argv << &char(launch.program.str)
	for argument in launch.arguments { argv << &char(argument.str) }
	argv << &char(unsafe { nil })
	defer { unsafe { (&array(&argv)).free() } }
	fds := launch_status_pipe()!
	defer { C.close(fds[0]) }
	pid := C.fork()
	if pid < 0 { C.close(fds[1]); return error('cannot start application process') }
	if pid == 0 {
		C.close(fds[0])
		if C.chdir(launch.directory.str) != 0 {
			launch_child_failure(fds[1], 1, i32(C.errno)); C._exit(126)
		}
		C.execv(launch.program.str, unsafe { &argv[0] })
		launch_child_failure(fds[1], 2, i32(C.errno)); C._exit(127)
	}
	C.close(fds[1])
	code := launch_wait(pid)!
	mut record := [2]i32{}
	mut count := isize(0)
	for {
		count = C.read(fds[0], unsafe { &record[0] }, 8)
		if count < 0 && C.errno == C.EINTR { continue }
		break
	}
	// A different concurrent fork can still hold a copy of the CLOEXEC writer.
	// Our child has been reaped, so no record pending also means no failure.
	if count == 0 || (count < 0 && C.errno == C.EAGAIN) { return code }
	if count != 8 || record[0] !in [i32(1), 2]! { return error('invalid application launch status') }
	number := record[1].str(); defer { unsafe { number.free() } }
	if record[0] == 1 { return error('cannot enter application working directory ' + launch.directory + ' (errno ' + number + ')') }
	return error('cannot execute application program ' + launch.program + ' (errno ' + number + ')')
}
