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

// Policy and priority belong to a thread, and the `pid` these calls take is a
// tid, exactly as on Linux: 0 means the calling thread, and the main thread of
// a process answers to the number that is also its pid.
//
// The scheduler behind them is in sched/: SCHED_FIFO and SCHED_RR at priorities
// 1 to 99 outrank every ordinary thread, SCHED_DEADLINE outranks those, and
// SCHED_IDLE runs only when nothing else will.

// Which thread a scheduling call is about, or none if it names one that is not
// there.
fn sched_target_tid(pid int) ?int {
	if pid < 0 {
		return none
	}
	if pid == 0 {
		return proc.current_thread().tid
	}
	proc.thread_sched_params(pid) or { return none }
	return pid
}

// Why sched_target_tid() had nothing to give back. A negative id is not one a
// thread could ever hold, which is a different answer from an id that simply
// does not belong to a thread just now.
fn sched_target_errno(pid int) u64 {
	return if pid < 0 { u64(errno.einval) } else { u64(errno.esrch) }
}

// May the caller give this thread that priority? Root may do anything;
// everybody else is held to RLIMIT_RTPRIO, and may not touch a thread outside
// their own user.
fn may_set_sched_params(target_tid int, policy int, priority int) bool {
	caller := proc.current_thread().process
	if caller.euid == 0 {
		return true
	}

	target := proc.thread_by_tid(target_tid)
	if target == unsafe { nil } || unsafe { target.process == nil } {
		return false
	}
	if caller.euid != target.process.euid && caller.euid != target.process.uid {
		return false
	}

	// Asking for less never needs permission. Asking for a deadline does, and
	// there is no limit that grants it.
	if policy == proc.sched_deadline {
		return false
	}
	if policy != proc.sched_fifo && policy != proc.sched_rr {
		return true
	}
	return proc.limit_allows(caller, proc.rlimit_rtprio, u64(priority))
}

// The priority a policy takes, or none if that is not a priority it can have.
fn validate_sched_priority(policy int, priority int) ?int {
	match policy {
		proc.sched_fifo, proc.sched_rr {
			if priority < proc.rt_priority_min || priority > proc.rt_priority_max {
				return none
			}
			return priority
		}
		proc.sched_other, proc.sched_batch, proc.sched_idle {
			// Every policy scheduled by turn has exactly one priority and it is
			// zero. What separates them is the timeslice and nice, which
			// setpriority(2) sets.
			if priority != 0 {
				return none
			}
			return 0
		}
		else {
			return none
		}
	}
}

fn syscall_linux_sched_getscheduler(_ voidptr, pid int) (u64, u64) {
	tid := sched_target_tid(pid) or { return errno.err, sched_target_errno(pid) }
	params := proc.thread_sched_params(tid) or { return errno.err, errno.esrch }
	if params.reset_on_fork {
		return u64(params.policy | proc.sched_reset_on_fork), 0
	}
	return u64(params.policy), 0
}

fn syscall_linux_sched_setscheduler(_ voidptr, pid int, policy int, param u64) (u64, u64) {
	tid := sched_target_tid(pid) or { return errno.err, sched_target_errno(pid) }

	reset_on_fork := policy & proc.sched_reset_on_fork != 0
	wanted := policy & ~proc.sched_reset_on_fork

	// SCHED_DEADLINE takes three times rather than one priority, so it can only
	// be asked for through sched_setattr(2). Linux refuses it here too.
	if wanted == proc.sched_deadline {
		return errno.err, errno.einval
	}

	if param == 0 {
		return errno.err, errno.efault
	}
	mut priority32 := i32(0)
	if !usercopy.copy_from_user(voidptr(&priority32), param, sizeof(i32)) {
		return errno.err, errno.efault
	}
	priority := int(priority32)

	checked := validate_sched_priority(wanted, priority) or { return errno.err, errno.einval }
	if !may_set_sched_params(tid, wanted, checked) {
		return errno.err, errno.eperm
	}

	if !proc.set_thread_sched_params(tid, proc.SchedParams{
		policy: wanted
		priority: checked
		reset_on_fork: reset_on_fork
	}) {
		return errno.err, errno.esrch
	}
	return 0, 0
}

// sched_getparam/sched_setparam: the priority on its own, leaving the policy
// where it is.
fn syscall_linux_sched_getparam(_ voidptr, pid int, param u64) (u64, u64) {
	if param == 0 {
		return errno.err, errno.efault
	}
	tid := sched_target_tid(pid) or { return errno.err, sched_target_errno(pid) }
	params := proc.thread_sched_params(tid) or { return errno.err, errno.esrch }

	priority := i32(params.priority)
	if !usercopy.copy_to_user(param, voidptr(&priority), sizeof(i32)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn syscall_linux_sched_setparam(_ voidptr, pid int, param u64) (u64, u64) {
	if param == 0 {
		return errno.err, errno.einval
	}
	tid := sched_target_tid(pid) or { return errno.err, sched_target_errno(pid) }
	mut params := proc.thread_sched_params(tid) or { return errno.err, errno.esrch }

	mut priority32 := i32(0)
	if !usercopy.copy_from_user(voidptr(&priority32), param, sizeof(i32)) {
		return errno.err, errno.efault
	}
	priority := int(priority32)

	// A deadline thread's parameters have to be checked against each other and
	// against the machine, which is sched_setattr(2)'s job and not this call's.
	if params.policy == proc.sched_deadline {
		return errno.err, errno.einval
	}

	checked := validate_sched_priority(params.policy, priority) or {
		return errno.err, errno.einval
	}
	if !may_set_sched_params(tid, params.policy, checked) {
		return errno.err, errno.eperm
	}

	params.priority = checked
	if !proc.set_thread_sched_params(tid, params) {
		return errno.err, errno.esrch
	}
	return 0, 0
}

fn syscall_linux_sched_get_priority_max(_ voidptr, policy int) (u64, u64) {
	match policy {
		proc.sched_fifo, proc.sched_rr {
			return u64(proc.rt_priority_max), 0
		}
		proc.sched_other, proc.sched_batch, proc.sched_idle, proc.sched_deadline {
			return 0, 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

fn syscall_linux_sched_get_priority_min(_ voidptr, policy int) (u64, u64) {
	match policy {
		proc.sched_fifo, proc.sched_rr {
			return u64(proc.rt_priority_min), 0
		}
		proc.sched_other, proc.sched_batch, proc.sched_idle, proc.sched_deadline {
			return 0, 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

// struct sched_attr, the form sched_setattr(2) and sched_getattr(2) carry. It
// is the only way to ask for SCHED_DEADLINE, whose parameters are three times
// rather than one priority.
struct SchedAttr {
mut:
	size           u32
	sched_policy   u32
	sched_flags    u64
	sched_nice     i32
	sched_priority u32
	sched_runtime  u64
	sched_deadline u64
	sched_period   u64
}

const sched_flag_reset_on_fork = u64(0x01)

// What the deadline threads may be promised between them, in parts per million
// of one CPU. The rest is what is left for every thread that is not one, and
// for the kernel itself.
const deadline_bandwidth_budget_ppm = u64(950000)

fn syscall_linux_sched_setattr(_ voidptr, pid int, attr_ptr u64, flags u32) (u64, u64) {
	if flags != 0 {
		return errno.err, errno.einval
	}
	if attr_ptr == 0 {
		return errno.err, errno.efault
	}
	tid := sched_target_tid(pid) or { return errno.err, sched_target_errno(pid) }

	mut size := u32(0)
	if !usercopy.copy_from_user(voidptr(&size), attr_ptr, sizeof(u32)) {
		return errno.err, errno.efault
	}
	if size < sizeof(SchedAttr) {
		return errno.err, errno.einval
	}

	mut attr := SchedAttr{}
	if !usercopy.copy_from_user(voidptr(&attr), attr_ptr, sizeof(SchedAttr)) {
		return errno.err, errno.efault
	}
	if attr.sched_flags & ~sched_flag_reset_on_fork != 0 {
		return errno.err, errno.einval
	}

	policy := int(attr.sched_policy)
	mut params := proc.SchedParams{
		policy: policy
		reset_on_fork: attr.sched_flags & sched_flag_reset_on_fork != 0
	}

	if policy == proc.sched_deadline {
		// Runtime has to fit inside the deadline and the deadline inside the
		// period: a thread cannot be promised more of a period than the period
		// holds, and one whose deadline falls after its next release has no
		// deadline worth the name.
		if attr.sched_runtime == 0 || attr.sched_period == 0 {
			return errno.err, errno.einval
		}
		mut relative_deadline := attr.sched_deadline
		if relative_deadline == 0 {
			relative_deadline = attr.sched_period
		}
		if attr.sched_runtime > relative_deadline || relative_deadline > attr.sched_period {
			return errno.err, errno.einval
		}
		if proc.current_thread().process.euid != 0 {
			return errno.err, errno.eperm
		}

		// Admission control, which is what makes a deadline a promise rather
		// than a priority: one is only given out while the machine can still
		// keep every deadline it has already agreed to.
		wanted_ppm := attr.sched_runtime * 1000000 / attr.sched_period
		if proc.deadline_bandwidth_ppm(tid) + wanted_ppm > deadline_bandwidth_budget_ppm {
			return errno.err, errno.ebusy
		}

		params.dl_runtime = attr.sched_runtime
		params.dl_deadline = relative_deadline
		params.dl_period = attr.sched_period
	} else {
		checked := validate_sched_priority(policy, int(attr.sched_priority)) or {
			return errno.err, errno.einval
		}
		if !may_set_sched_params(tid, policy, checked) {
			return errno.err, errno.eperm
		}
		params.priority = checked
	}

	if !proc.set_thread_sched_params(tid, params) {
		return errno.err, errno.esrch
	}

	// sched_attr carries nice alongside the policy, and a caller that has
	// filled it in should not need a second call to have it take effect.
	if policy != proc.sched_deadline && attr.sched_nice >= -20 && attr.sched_nice <= 19 {
		mut target := proc.thread_by_tid(tid)
		if target != unsafe { nil } && unsafe { target.process != nil } {
			if attr.sched_nice >= target.process.nice
				|| proc.current_thread().process.euid == 0 {
				target.process.nice = int(attr.sched_nice)
			}
		}
	}

	return 0, 0
}

fn syscall_linux_sched_getattr(_ voidptr, pid int, attr_ptr u64, size u32, flags u32) (u64, u64) {
	if flags != 0 {
		return errno.err, errno.einval
	}
	if attr_ptr == 0 {
		return errno.err, errno.efault
	}
	if size < sizeof(SchedAttr) {
		return errno.err, errno.einval
	}
	tid := sched_target_tid(pid) or { return errno.err, sched_target_errno(pid) }
	params := proc.thread_sched_params(tid) or { return errno.err, errno.esrch }

	mut nice := int(0)
	target := proc.thread_by_tid(tid)
	if target != unsafe { nil } && unsafe { target.process != nil } {
		nice = target.process.nice
	}

	mut attr := SchedAttr{
		size: u32(sizeof(SchedAttr))
		sched_policy: u32(params.policy)
		sched_nice: i32(nice)
		sched_priority: u32(params.priority)
		sched_runtime: params.dl_runtime
		sched_deadline: params.dl_deadline
		sched_period: params.dl_period
	}
	if params.reset_on_fork {
		attr.sched_flags |= sched_flag_reset_on_fork
	}

	if !usercopy.copy_to_user(attr_ptr, voidptr(&attr), sizeof(SchedAttr)) {
		return errno.err, errno.efault
	}
	return 0, 0
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
	tid := if pid == 0 { proc.current_thread().tid } else { pid }
	configured := proc.thread_affinity(tid) or { return errno.err, errno.esrch }
	bits &= configured

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
	tid := if pid == 0 { proc.current_thread().tid } else { pid }
	if !proc.set_thread_affinity(tid, bits & present) {
		return errno.err, errno.esrch
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

fn syscall_linux_mlock(_ voidptr, _addr u64, _length u64) (u64, u64) {
	return 0, 0
}

fn syscall_linux_mlock2(_ voidptr, _addr u64, _length u64, flags int) (u64, u64) {
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
