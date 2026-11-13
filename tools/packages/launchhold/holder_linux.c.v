// SPDX-License-Identifier: GPL-2.0-or-later
module launchhold

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <poll.h>
#include <errno.h>
const wait_message = 'Generation lease holder cannot collect children; retaining lease and retrying.\n'
// Linux AMD64/AArch64 kernel UAPI, distinct from libc's larger sigaction.
struct SignalAction { handler u64 flags u64 restorer u64 mask u64 }
fn C.pipe2(&i32, i32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C._Fork() i32
fn C.close(i32) i32
fn C.execv(&char, &&char) i32
fn C.chdir(&char) i32
fn C._exit(i32)
fn C.prctl(i32, ...voidptr) i32
#define vinix_launchhold_read read
fn C.vinix_launchhold_read(i32, voidptr, u64) i64
fn C.syscall(i64, ...) i64

fn set_mask(mask &u64, previous &u64) i32 {
	return i32(C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, mask, previous, u64(8)))
}
fn action(signal i32, replacement &SignalAction, previous &SignalAction) i32 {
	return i32(C.syscall(C.SYS_rt_sigaction, signal, replacement, previous, u64(8)))
}
fn raw_wait(pid i32, status &i32) i32 { return i32(C.syscall(C.SYS_wait4, pid, status, i32(0), voidptr(0))) }
fn child_close(fd i32) { C.syscall(C.SYS_close, fd) }

fn fail(fd i32, stage i32) {
	record := [stage, i32(C.errno)]!
	for {
		count := C.syscall(C.SYS_write, fd, unsafe { &record[0] }, u64(8))
		if count < 0 && C.errno == C.EINTR { continue }
		break
	}
	C._exit(126)
}

fn close_interval(first u32, last u32) bool {
	if first > last { return true }
	// Both supported Linux architectures use syscall 436 for close_range.
	return C.syscall(436, first, last, u32(0)) == 0
}

// No V allocation, formatting, environment lookup or Process object after
// fork. All masks and wait/status records are genuine stack ABI objects.
fn holder(program &char, directory &char, argv &&char, lease i32, report i32, inherited &u64) {
	default_action := SignalAction{}
	mut inherited_action := SignalAction{}
	if action(C.SIGCHLD, unsafe { &default_action }, unsafe { &inherited_action }) != 0 { fail(report, 2) }
	mut enabled := i32(0)
	if C.prctl(36, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) != 0
		|| C.prctl(37, unsafe { &enabled }, voidptr(0), voidptr(0), voidptr(0)) != 0 { fail(report, 3) }
	if enabled != 1 { C.errno = C.EINVAL; fail(report, 3) }
	low := u32(if lease < report { lease } else { report })
	high := u32(if lease < report { report } else { lease })
	if !close_interval(3, low - 1) || !close_interval(low + 1, high - 1)
		|| !close_interval(high + 1, ~u32(0)) { fail(report, 4) }
	client := C._Fork()
	if client < 0 { fail(report, 5) }
	if client == 0 {
		child_close(lease)
		if action(C.SIGCHLD, unsafe { &inherited_action }, unsafe { nil }) != 0 { fail(report, 6) }
		$if lease_holder_fixture ? {
			$if lease_holder_signal_window ? {
				if C.syscall(C.SYS_kill, C.syscall(C.SYS_getpid), C.SIGUSR1) != 0 { fail(report, 6) }
			}
		}
		// Match exec's disposition transition before unmasking: no inherited
		// allocating/locking handler may run in this post-fork interval.
		for signal := i32(1); signal <= 64; signal++ {
			$if lease_holder_fixture ? { $if lease_holder_keep_handlers ? { break } }
			mut previous := SignalAction{}
			if action(signal, unsafe { nil }, unsafe { &previous }) != 0 { fail(report, 6) }
			if previous.handler > 1 && action(signal, unsafe { &default_action }, unsafe { nil }) != 0 { fail(report, 6) }
		}
		if set_mask(inherited, unsafe { nil }) != 0 { fail(report, 6) }
		if C.chdir(directory) != 0 { fail(report, 7) }
		C.execv(program, argv)
		fail(report, 8)
	}
	child_close(0); child_close(1)
	mut notified := false
	mut status := i32(0)
	for {
		answer := raw_wait(client, unsafe { &status })
		if answer == client { break }
		if answer < 0 && C.errno == C.EINTR { continue }
		wait_fault(unsafe { &notified })
	}
	saved := if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
	for {
		answer := descendant_wait(unsafe { &status })
		if answer > 0 || (answer < 0 && C.errno == C.EINTR) { continue }
		if answer < 0 && C.errno == C.ECHILD { break }
		wait_fault(unsafe { &notified })
	}
	C._exit(saved)
}

fn descendant_wait(status &i32) i32 {
	$if lease_holder_fixture ? {
		$if lease_holder_wait_fault ? { C.errno = C.EIO; return -1 }
	}
	return raw_wait(-1, status)
}

fn wait_fault(notified &bool) {
	if !unsafe { *notified } {
		C.syscall(C.SYS_write, i32(2), wait_message.str, u64(wait_message.len))
		unsafe { *notified = true }
	}
	delay := [i64(0), 100000000]!
	C.syscall(C.SYS_ppoll, voidptr(0), u64(0), unsafe { &delay[0] }, voidptr(0), u64(8))
}

fn run_linux(command Command, lease i32) !int {
	flags := C.fcntl(lease, C.F_GETFD)
	if lease < 3 || flags < 0 || flags & C.FD_CLOEXEC == 0 { return error('holder requires a live close-on-exec lease descriptor above standard streams') }
	if !command.program.starts_with('/') || !command.directory.starts_with('/')
		|| command.program.contains('\x00') || command.directory.contains('\x00') { return error('holder requires absolute paths without NUL') }
	for argument in command.arguments { if argument.contains('\x00') { return error('holder argument contains NUL') } }
	mut caller_action := SignalAction{}
	if action(C.SIGCHLD, unsafe { nil }, unsafe { &caller_action }) != 0
		|| caller_action.handler != 0 || caller_action.flags & u64(C.SA_NOCLDWAIT) != 0 {
		return error('holder requires the caller default SIGCHLD disposition and waitable children')
	}
	mut argv := []&char{cap: command.arguments.len + 2}
	defer { unsafe { argv.free() } }
	argv << command.program.str
	for argument in command.arguments { argv << argument.str }
	argv << &char(unsafe { nil })
	mut fds := [i32(-1), -1]!
	if C.pipe2(unsafe { &fds[0] }, C.O_CLOEXEC) != 0 { return error('cannot create holder status pipe') }
	defer { C.close(fds[0]); C.close(fds[1]) }
	for index in 0 .. 2 {
		if fds[index] < 3 {
			fd := C.fcntl(fds[index], C.F_DUPFD_CLOEXEC, 3)
			if fd < 0 { return error('cannot retain holder status pipe') }
			C.close(fds[index]); fds[index] = fd
		}
	}
	if C.fcntl(fds[0], C.F_SETFL, C.O_NONBLOCK) != 0 { return error('cannot configure holder status pipe') }
	program := command.program.str; directory := command.directory.str
	blocked := ~u64(0)
	mut inherited := u64(0)
	if set_mask(unsafe { &blocked }, unsafe { &inherited }) != 0 { return error('cannot protect holder fork signal mask') }
	// _Fork does not invoke arbitrary caller pthread_atfork callbacks.
	pid := C._Fork()
	if pid == 0 {
		child_close(fds[0])
		$if lease_holder_fixture ? {
			$if lease_holder_signal_window ? {
				if C.syscall(C.SYS_kill, C.syscall(C.SYS_getpid), C.SIGUSR1) != 0 { fail(fds[1], 1) }
			}
		}
		holder(program, directory, unsafe { &&char(argv.data) }, lease, fds[1], unsafe { &inherited })
		C._exit(126)
	}
	mask_result := set_mask(unsafe { &inherited }, unsafe { nil })
	defer { if mask_result != 0 { set_mask(unsafe { &inherited }, unsafe { nil }) } }
	if pid < 0 { return error('cannot fork generation lease holder') }
	C.close(fds[1]); fds[1] = -1
	mut status := i32(0)
	for {
		answer := raw_wait(pid, unsafe { &status })
		if answer == pid { break }
		if answer < 0 && C.errno == C.EINTR { continue }
		return error('cannot collect generation lease holder; holder may still retain its lease')
	}
	if mask_result != 0 { return error('cannot restore caller signal mask after holder fork') }
	mut record := [2]i32{}
	mut count := i64(0)
	for {
		count = C.vinix_launchhold_read(fds[0], unsafe { &record[0] }, 8)
		if count < 0 && C.errno == C.EINTR { continue }
		break
	}
	if count == 0 || (count < 0 && C.errno == C.EAGAIN) {
		return if status & 0x7f == 0 { int((status >> 8) & 0xff) } else { int(128 + (status & 0x7f)) }
	}
	if count != 8 || record[0] < 1 || record[0] > 8 { return error('invalid holder failure record') }
	stage := record[0].str(); code := record[1].str()
	defer { unsafe { stage.free(); code.free() } }
	return error('generation lease holder setup stage ' + stage + ' failed (errno ' + code + ')')
}
