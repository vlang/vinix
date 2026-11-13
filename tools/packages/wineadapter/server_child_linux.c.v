// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

#include <unistd.h>
#include <sys/syscall.h>
#include <signal.h>
#define vinix_wine_spawn_pipe pipe2
#define vinix_wine_spawn_fork _Fork
#define vinix_wine_spawn_exec execv
#define vinix_wine_spawn_fchdir fchdir
fn C.vinix_wine_spawn_pipe(&i32, i32) i32
fn C.vinix_wine_spawn_fork() i32
fn C.vinix_wine_spawn_exec(&char, &&char) i32
fn C.vinix_wine_spawn_fchdir(i32) i32
fn C._exit(i32)

fn child_signal_policy() ! {
	mut policy := ServerSignalAction{}
	if C.vinix_wine_peer_syscall(C.SYS_rt_sigaction, C.SIGCHLD, voidptr(0), unsafe { &policy }, u64(8)) != 0
		|| policy.handler != 0 || policy.flags & u64(C.SA_NOCLDWAIT) != 0 {
		return error('Wine server child requires default waitable SIGCHLD')
	}
}

fn child_mask(mask &u64, previous &u64) i32 {
	return i32(C.vinix_wine_peer_syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, mask, previous, u64(8)))
}

fn child_close_descriptor(fd i32) {
	if fd >= 0 { C.vinix_wine_peer_syscall(C.SYS_close, fd) }
}

fn child_report_failure(report i32, stage i32) {
	record := [stage, i32(C.errno)]!
	for {
		n := C.vinix_wine_peer_syscall(C.SYS_write, report, unsafe { &record[0] }, u64(8))
		if n < 0 && C.errno == C.EINTR { continue }
		break
	}
	C._exit(126)
}

// Post-_Fork: raw syscalls and async-signal-safe libc only; no V allocation,
// environment lookup, formatting, deferred cleanup or caller atfork handlers.
fn child_exec(program &char, argv &&char, prefix i32, report i32, inherited &u64) {
	if C.vinix_wine_spawn_fchdir(prefix) != 0 { child_report_failure(report, 1) }
	$if wine_child_signal_window ? {
		if C.vinix_wine_peer_syscall(C.SYS_kill, C.vinix_wine_peer_syscall(C.SYS_getpid), i32(C.SIGTERM)) != 0 { child_report_failure(report, 3) }
	}
	$if wine_child_close_failure ? { C.errno = C.EIO; child_report_failure(report, 2) }
	if (report > 3 && C.vinix_wine_peer_syscall(436, u32(3), u32(report - 1), u32(0)) != 0)
		|| C.vinix_wine_peer_syscall(436, u32(report + 1), ~u32(0), u32(0)) != 0 { child_report_failure(report, 2) }
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
	C.vinix_wine_spawn_exec(program, argv)
	child_report_failure(report, 4)
}

fn (server &ServerDirectory) start_child_linux(guard &LaunchGuard, data string, command ServerCommand) !ServerChild {
	if !command.program.starts_with('/') || command.program.contains('\x00') {
		return error('Wine server child requires an absolute executable without NUL')
	}
	for argument in command.arguments {
		if argument.contains('\x00') { return error('Wine server child argument contains NUL') }
	}
	child_signal_policy()!
	mut argv := []&char{cap: command.arguments.len + 2}
	defer { unsafe { argv.free() } }
	argv << command.program.str
	for argument in command.arguments { argv << argument.str }
	argv << &char(unsafe { nil })
	mut fds := [i32(-1), -1]!
	if C.vinix_wine_spawn_pipe(unsafe { &fds[0] }, C.O_CLOEXEC) != 0 { return error('cannot create Wine child exec report') }
	defer { child_close_descriptor(fds[0]); child_close_descriptor(fds[1]) }
	for index in 0 .. 2 {
		if fds[index] < 3 {
			fd := C.vinix_wine_guard_fcntl(fds[index], C.F_DUPFD_CLOEXEC, 3)
			if fd < 0 { return error('cannot retain Wine child exec report') }
			child_close_descriptor(fds[index]); fds[index] = fd
		}
	}
	if C.vinix_wine_guard_fcntl(fds[0], C.F_SETFL, C.O_NONBLOCK) != 0 { return error('cannot configure Wine child exec report') }
	server.require_idle(guard, data)!
	program := command.program.str
	blocked := ~u64(0)
	mut inherited := u64(0)
	if child_mask(unsafe { &blocked }, unsafe { &inherited }) != 0 { return error('cannot protect Wine child fork signal mask') }
	pid := C.vinix_wine_spawn_fork()
	if pid == 0 {
		child_exec(program, unsafe { &&char(argv.data) }, guard.directory, fds[1], unsafe { &inherited })
		C._exit(126)
	}
	mut mask_result := i32(0)
	$if wine_child_mask_failure ? { mask_result = -1 }
	$else { mask_result = child_mask(unsafe { &inherited }, unsafe { nil }) }
	if pid < 0 {
		if mask_result != 0 && child_mask(unsafe { &inherited }, unsafe { nil }) != 0 {
			return error('cannot fork Wine server child or restore caller signal mask')
		}
		return error('cannot fork Wine server child')
	}
	owned := ServerChild{pid: pid, report: fds[0], restore_pending: mask_result != 0, inherited_mask: inherited}
	fds[0] = -1
	return owned
}

fn (mut child ServerChild) restore_child_caller_mask() ! {
	if child.restore_pending {
		if child_mask(unsafe { &child.inherited_mask }, unsafe { nil }) != 0 {
			return error('cannot restore caller signal mask; Wine child ownership retained')
		}
		child.restore_pending = false
	}
}

fn (mut child ServerChild) exec_ready_linux() !bool {
	if child.pid <= 0 { return error('Wine server child is already collected or closed') }
	child.restore_child_caller_mask()!
	child_signal_policy()!
	if child.failure_stage == 0 && !child.exec_complete {
		mut record := [2]i32{}
		mut n := i64(0)
		for {
			n = C.vinix_wine_peer_syscall(C.SYS_read, child.report, unsafe { &record[0] }, u64(8))
			if n < 0 && C.errno == C.EINTR { continue }
			break
		}
		if n < 0 && C.errno == C.EAGAIN { return false }
		if n < 0 { return error('cannot read Wine child exec report') }
		if n == 0 { child.exec_complete = true }
		else if n == 8 && record[0] >= 1 && record[0] <= 4 {
			child.failure_stage = record[0]; child.failure_errno = record[1]
		} else { child.failure_stage = 6 }
		child_close_descriptor(child.report); child.report = -1
	}
	if child.failure_stage != 0 {
		stage := child.failure_stage.str(); code := child.failure_errno.str()
		defer { unsafe { stage.free(); code.free() } }
		return error('Wine child setup stage ' + stage + ' failed (errno ' + code + ')')
	}
	return child.exec_complete
}

fn (mut child ServerChild) collect_linux(blocking bool) !ServerChildExit {
	if child.pid <= 0 { return error('Wine server child is already collected or closed') }
	child.restore_child_caller_mask()!
	child_signal_policy()!
	mut status := i32(0)
	for {
		answer := C.vinix_wine_peer_syscall(C.SYS_wait4, child.pid, unsafe { &status }, i32(if blocking { 0 } else { C.WNOHANG }), voidptr(0))
		if answer == 0 { return ServerChildExit{} }
		if answer < 0 && C.errno == C.EINTR { continue }
		if answer != child.pid { return error('cannot collect owned Wine child; ownership retained') }
		child_close_descriptor(child.report)
		child = ServerChild{}
		return ServerChildExit{collected: true, code: if status & 0x7f == 0 { int((status >> 8) & 0xff) } else { int(128 + (status & 0x7f)) }}
	}
	return error('unreachable Wine child wait')
}

fn (mut child ServerChild) terminate_linux() !int {
	if child.pid <= 0 { return error('Wine server child is already collected or closed') }
	child.restore_child_caller_mask()!
	child_signal_policy()!
	// WNOWAIT both checks direct-child ownership and keeps an exited child's PID
	// reserved. Exclude all other waiters throughout observation, kill and wait.
	mut info := C.vinix_wine_child_info{}
	if C.vinix_wine_peer_waitid(C.P_PID, u32(child.pid), unsafe { &info }, C.WEXITED | C.WNOHANG | C.WNOWAIT) != 0 {
		return error('cannot verify owned Wine child before termination')
	}
	if info.si_pid == 0 && C.vinix_wine_peer_syscall(C.SYS_kill, child.pid, i32(C.SIGKILL)) != 0 {
		return error('cannot terminate owned Wine child')
	}
	result := child.collect_linux(true)!
	return result.code
}
