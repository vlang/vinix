// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module table

// The remainder of the Linux surface that real programs reach for: the
// scheduling queries a libc makes to size its thread pools, the memory hints
// that have nothing to do here but must not fail, and a handful of calls whose
// by-descriptor or by-name twin already existed.

import aarch64.cpu.local as cpulocal
import errno
import file
import katomic
import proc
import socket
import time
import usercopy

// ── scheduling ───────────────────────────────────────────────────────────────

// There is one scheduling policy here and it is not selectable, so the queries
// answer for SCHED_OTHER and the setters accept nothing else.
const sched_other = 0

const sched_fifo = 1

const sched_rr = 2

fn syscall_linux_sched_getscheduler(_ voidptr, pid int) (u64, u64) {
	if pid < 0 {
		return errno.err, errno.einval
	}
	if pid != 0 && (pid >= proc.max_pid || processes[pid] == unsafe { nil }) {
		return errno.err, errno.esrch
	}
	return sched_other, 0
}

fn syscall_linux_sched_setscheduler(_ voidptr, pid int, policy int, param u64) (u64, u64) {
	if pid < 0 {
		return errno.err, errno.einval
	}
	if pid != 0 && (pid >= proc.max_pid || processes[pid] == unsafe { nil }) {
		return errno.err, errno.esrch
	}
	// Asking for a real-time policy would be answered with a lie.
	if policy != sched_other {
		return errno.err, errno.einval
	}
	return 0, 0
}

// sched_getparam/sched_setparam. SCHED_OTHER has one priority and it is zero.
fn syscall_linux_sched_getparam(_ voidptr, pid int, param u64) (u64, u64) {
	if pid < 0 {
		return errno.err, errno.einval
	}
	if param == 0 {
		return errno.err, errno.efault
	}
	priority := int(0)
	if !usercopy.copy_to_user(param, voidptr(&priority), sizeof(int)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn syscall_linux_sched_setparam(_ voidptr, pid int, param u64) (u64, u64) {
	if pid < 0 || param == 0 {
		return errno.err, errno.einval
	}
	mut priority := int(0)
	if !usercopy.copy_from_user(voidptr(&priority), param, sizeof(int)) {
		return errno.err, errno.efault
	}
	if priority != 0 {
		return errno.err, errno.einval
	}
	return 0, 0
}

fn syscall_linux_sched_get_priority_max(_ voidptr, policy int) (u64, u64) {
	match policy {
		sched_other { return 0, 0 }
		sched_fifo, sched_rr { return 0, 0 }
		else { return errno.err, errno.einval }
	}
}

fn syscall_linux_sched_get_priority_min(_ voidptr, policy int) (u64, u64) {
	match policy {
		sched_other, sched_fifo, sched_rr { return 0, 0 }
		else { return errno.err, errno.einval }
	}
}

// sched_getaffinity(pid, size, mask). This is how a libc counts the processors
// for sysconf(_SC_NPROCESSORS_ONLN), so the answer decides how many threads a
// program starts.
fn syscall_linux_sched_getaffinity(_ voidptr, pid int, size u64, mask u64) (u64, u64) {
	if pid < 0 {
		return errno.err, errno.einval
	}
	if pid != 0 && (pid >= proc.max_pid || processes[pid] == unsafe { nil }) {
		return errno.err, errno.esrch
	}
	if mask == 0 {
		return errno.err, errno.efault
	}

	mut cpus := cpu_locals.len
	if cpus <= 0 {
		cpus = 1
	}
	if cpus > 64 {
		cpus = 64
	}

	// The caller's buffer must be able to hold whole words, and at least one.
	if size < sizeof(u64) || size % sizeof(u64) != 0 {
		return errno.err, errno.einval
	}

	mut bits := u64(0)
	for i := 0; i < cpus; i++ {
		bits |= u64(1) << u64(i)
	}

	mut written := size
	if written > sizeof(u64) {
		written = sizeof(u64)
	}
	if !usercopy.copy_to_user(mask, voidptr(&bits), written) {
		return errno.err, errno.efault
	}

	// The return value is the number of bytes filled in.
	return written, 0
}

// Every thread already runs anywhere, so an affinity mask that includes at
// least one present processor is accepted and one that does not is refused.
fn syscall_linux_sched_setaffinity(_ voidptr, pid int, size u64, mask u64) (u64, u64) {
	if pid < 0 || size < sizeof(u64) {
		return errno.err, errno.einval
	}
	if mask == 0 {
		return errno.err, errno.efault
	}

	mut bits := u64(0)
	if !usercopy.copy_from_user(voidptr(&bits), mask, sizeof(u64)) {
		return errno.err, errno.efault
	}

	mut cpus := cpu_locals.len
	if cpus <= 0 {
		cpus = 1
	}
	mut present := u64(0)
	for i := 0; i < cpus && i < 64; i++ {
		present |= u64(1) << u64(i)
	}

	if bits & present == 0 {
		return errno.err, errno.einval
	}

	return 0, 0
}

// ── signals ──────────────────────────────────────────────────────────────────

// rt_sigpending(set, sigsetsize): the signals raised for this thread that its
// mask is holding back.
fn syscall_linux_rt_sigpending(_ voidptr, set u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != sizeof(u64) {
		return errno.err, errno.einval
	}
	if set == 0 {
		return errno.err, errno.efault
	}

	current_thread := proc.current_thread()
	pending := katomic.load(&current_thread.pending_signals) & current_thread.masked_signals

	if !usercopy.copy_to_user(set, voidptr(&pending), sizeof(u64)) {
		return errno.err, errno.efault
	}

	return 0, 0
}

// ── times ────────────────────────────────────────────────────────────────────

// times(buf). No per-process CPU time is accounted, so the four fields are
// zero; the return value is the one part that is real, and it is what callers
// actually use to measure elapsed time.
fn syscall_linux_times(_ voidptr, buf u64) (u64, u64) {
	if buf != 0 {
		mut blank := [4]i64{}
		if !usercopy.copy_to_user(buf, voidptr(&blank[0]), sizeof(i64) * 4) {
			return errno.err, errno.efault
		}
	}

	// Clock ticks since boot, at the 100 Hz every libc assumes.
	now := monotonic_clock
	ticks := u64(now.tv_sec) * 100 + u64(now.tv_nsec) / 10000000

	return ticks, 0
}

// ── sockets ──────────────────────────────────────────────────────────────────

// accept4(fd, addr, addrlen, flags). accept()'s twin, and the one a server
// reaches for when it wants the new connection non-blocking without a second
// syscall to set it.
fn syscall_linux_accept4(gpr_state voidptr, fdnum int, addr u64, addrlen u64, flags int) (u64, u64) {
	ret, err := socket.syscall_accept(gpr_state, fdnum)
	if err != 0 {
		return ret, err
	}

	newfd := int(ret)

	if addr != 0 && addrlen != 0 {
		// Report the peer, ignoring a failure: the connection is already
		// accepted and losing it here would be worse than a missing address.
		socket.syscall_getpeername(gpr_state, newfd, voidptr(addr), unsafe { &u32(addrlen) })
	}

	if flags != 0 {
		mut open_flags := 0
		if flags & sock_nonblock != 0 {
			open_flags |= resource_o_nonblock
		}
		if flags & sock_cloexec != 0 {
			open_flags |= resource_o_cloexec
		}
		if open_flags != 0 {
			file.set_fd_flags(newfd, open_flags)
		}
	}

	return u64(newfd), 0
}

const sock_nonblock = 0o4000

const sock_cloexec = 0o2000000

const resource_o_nonblock = 0o4000

const resource_o_cloexec = 0o2000000

// ── memory hints ─────────────────────────────────────────────────────────────

// Nothing here pages anything out, so a mapping is always resident and always
// synchronised. These exist so that a program asking for the guarantee is told
// it has it rather than that the call does not exist.
fn syscall_linux_msync(_ voidptr, addr u64, length u64, flags int) (u64, u64) {
	// MS_ASYNC | MS_INVALIDATE | MS_SYNC
	if flags & ~0x7 != 0 {
		return errno.err, errno.einval
	}
	if addr % page_size != 0 {
		return errno.err, errno.einval
	}
	return 0, 0
}

fn syscall_linux_mlock(_ voidptr, addr u64, length u64) (u64, u64) {
	return 0, 0
}

fn syscall_linux_mlock2(_ voidptr, addr u64, length u64, flags int) (u64, u64) {
	if flags & ~0x1 != 0 {
		return errno.err, errno.einval
	}
	return 0, 0
}

fn syscall_linux_mlockall(_ voidptr, flags int) (u64, u64) {
	// MCL_CURRENT | MCL_FUTURE | MCL_ONFAULT, and at least one is required.
	if flags == 0 || flags & ~0x7 != 0 {
		return errno.err, errno.einval
	}
	return 0, 0
}

fn syscall_linux_munlockall(_ voidptr) (u64, u64) {
	return 0, 0
}
