// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

#define vinix_wine_client_exec execve
fn C.vinix_wine_client_exec(&char, &&char, &&char) i32

fn client_close_interval(first u32, last u32) bool {
	return first > last || C.vinix_wine_peer_syscall(436, first, last, u32(0)) == 0
}

// Post-_Fork: stack ABI records and async-safe calls only. Everything pointed
// to by argv/environment was prepared before fork; there is no setenv/getenv.
fn client_exec(program &char, argv &&char, environment &&char, prefix i32, socket i32, report i32, inherited &u64) {
	$if wine_client_signal_window ? {
		if C.vinix_wine_peer_syscall(C.SYS_kill, C.vinix_wine_peer_syscall(C.SYS_getpid), i32(C.SIGTERM)) != 0 { child_report_failure(report, 3) }
	}
	if C.vinix_wine_spawn_fchdir(prefix) != 0 { child_report_failure(report, 1) }
	low := u32(if socket < report { socket } else { report })
	high := u32(if socket < report { report } else { socket })
	if !client_close_interval(3, low - 1) || !client_close_interval(low + 1, high - 1)
		|| !client_close_interval(high + 1, ~u32(0)) { child_report_failure(report, 2) }
	default_action := ServerSignalAction{}
	for signal := i32(1); signal <= 64; signal++ {
		mut previous := ServerSignalAction{}
		if C.vinix_wine_peer_syscall(C.SYS_rt_sigaction, signal, voidptr(0), unsafe { &previous }, u64(8)) != 0 {
			child_report_failure(report, 3)
		}
		if previous.handler > 1 && C.vinix_wine_peer_syscall(C.SYS_rt_sigaction, signal, unsafe { &default_action }, voidptr(0), u64(8)) != 0 {
			child_report_failure(report, 3)
		}
	}
	if child_mask(inherited, unsafe { nil }) != 0 { child_report_failure(report, 3) }
	flags := C.vinix_wine_guard_fcntl(socket, C.F_GETFD)
	if flags < 0 || C.vinix_wine_guard_fcntl(socket, C.F_SETFD, flags & ~i32(C.FD_CLOEXEC)) != 0 { child_report_failure(report, 2) }
	C.vinix_wine_client_exec(program, argv, environment)
	child_report_failure(report, 4)
}

fn client_command(command ServerCommand, environment []string) ! {
	if !command.program.starts_with('/') || command.program.contains('\x00') {
		return error('Wine client requires an absolute executable without NUL')
	}
	if command.arguments.len > 4096 || environment.len > 4096 { return error('Wine client command exceeds entry bound') }
	mut size := u64(command.program.len)
	for argument in command.arguments {
		if argument.contains('\x00') { return error('Wine client argument contains NUL') }
		size += u64(argument.len) + 1
	}
	for entry in environment {
		if entry.contains('\x00') || entry.len == 0 || entry[0] == `=` || !entry.contains('=') {
			return error('Wine client environment requires NAME=VALUE entries without NUL')
		}
		size += u64(entry.len) + 1
	}
	if size > 1024 * 1024 { return error('Wine client command exceeds byte bound') }
}

fn (mut connection ServerConnection) start_client_linux(server &ServerDirectory, guard &LaunchGuard, data string, command ServerCommand, environment []string, working_directory i32) !ClientChild {
	client_command(command, environment)!
	child_signal_policy()!
	connection.recheck(server, guard, data)!
	// Capture before fork. Never close the caller's descriptor, even on refusal.
	// F_DUPFD_CLOEXEC also accepts O_PATH directory descriptors on Linux.
	cwd := C.vinix_wine_guard_fcntl(working_directory, C.F_DUPFD_CLOEXEC, 3)
	if cwd < 0 { return error('cannot capture Wine client working directory') }
	defer { child_close_descriptor(cwd) }
	mut cwd_info := C.stat{}
	if C.fstat(cwd, unsafe { &cwd_info }) != 0 || u32(cwd_info.st_mode) & 0o170000 != 0o040000 {
		return error('Wine client working directory must be a directory descriptor')
	}
	status := C.vinix_wine_guard_fcntl(connection.fd, C.F_GETFL)
	if status < 0 || status & C.O_NONBLOCK != 0 { return error('Wine client handoff requires a blocking socket') }
	mut argv := []&char{cap: command.arguments.len + 2}
	defer { unsafe { argv.free() } }
	argv << command.program.str
	for argument in command.arguments { argv << argument.str }
	argv << &char(unsafe { nil })
	text := connection.fd.str()
	handoff := 'WINESERVERSOCKET=' + text
	defer { unsafe { text.free(); handoff.free() } }
	mut envp := []&char{cap: environment.len + 2}
	defer { unsafe { envp.free() } }
	for entry in environment {
		if !entry.starts_with('WINESERVERSOCKET=') { envp << entry.str }
	}
	envp << handoff.str
	envp << &char(unsafe { nil })
	mut fds := [i32(-1), -1]!
	if C.vinix_wine_spawn_pipe(unsafe { &fds[0] }, C.O_CLOEXEC) != 0 { return error('cannot create Wine client exec report') }
	defer { child_close_descriptor(fds[0]); child_close_descriptor(fds[1]) }
	for index in 0 .. 2 {
		if fds[index] < 3 {
			fd := C.vinix_wine_guard_fcntl(fds[index], C.F_DUPFD_CLOEXEC, 3)
			if fd < 0 { return error('cannot retain Wine client exec report') }
			child_close_descriptor(fds[index]); fds[index] = fd
		}
	}
	if C.vinix_wine_guard_fcntl(fds[0], C.F_SETFL, C.O_NONBLOCK) != 0 { return error('cannot configure Wine client exec report') }
	connection.recheck(server, guard, data)!
	program := command.program.str
	socket := connection.fd
	blocked := ~u64(0)
	mut inherited := u64(0)
	if child_mask(unsafe { &blocked }, unsafe { &inherited }) != 0 { return error('cannot protect Wine client fork signal mask') }
	pid := C.vinix_wine_spawn_fork()
	if pid == 0 {
		client_exec(program, unsafe { &&char(argv.data) }, unsafe { &&char(envp.data) }, cwd, socket, fds[1], unsafe { &inherited })
		C._exit(126)
	}
	if pid > 0 {
		// Drop every parent connection reference before unmasking or returning.
		// Raw close avoids a cancellation point after creating an owned child.
		child_close_descriptor(connection.fd)
		child_close_descriptor(connection.endpoint.node)
		child_close_descriptor(connection.endpoint.directory)
		connection = ServerConnection{}
	}
	mask_result := child_mask(unsafe { &inherited }, unsafe { nil })
	if pid < 0 {
		if mask_result != 0 && child_mask(unsafe { &inherited }, unsafe { nil }) != 0 {
			return error('cannot fork Wine client or restore caller signal mask')
		}
		return error('cannot fork Wine client')
	}
	owned := ClientChild{process: ServerChild{pid: pid, report: fds[0], restore_pending: mask_result != 0, inherited_mask: inherited}}
	fds[0] = -1
	return owned
}
