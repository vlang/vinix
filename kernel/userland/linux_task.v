// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// The parts of the Linux thread and process lifecycle that do not depend on
// the architecture: the clone flags and argument block, the tid word and robust
// futex list a thread hands back when it exits, and wait4/waitid. Each
// architecture's clone and exit are built on these.

import errno
import event
import futex
import katomic
import proc
import usercopy

// clone(2) flags. Only the ones that change what we build are listed.
pub const clone_thread = u64(0x00010000)

pub const clone_settls = u64(0x00080000)

pub const clone_parent_settid = u64(0x00100000)

pub const clone_child_cleartid = u64(0x00200000)

pub const clone_child_settid = u64(0x01000000)

// The child's parent is the caller's parent, as for a sibling.
pub const clone_parent = u64(0x00008000)

pub const clone_pidfd = u64(0x00001000)

// clone3 only: start the child in the cgroup the args' directory fd names.
pub const clone_into_cgroup = u64(0x200000000)

// wait4(2)/waitid(2) options. `wnohang` lives with each architecture's
// waitpid.
const wstopped = 2

const wexited = 4

const wcontinued = 8

const wnowait = 0x01000000

// waitid(2) id types.
const p_all = 0

const p_pid = 1

const p_pgid = 2

// siginfo si_code values for SIGCHLD.
const cld_exited = 1

const cld_killed = 2

// Robust futex list, as laid out by glibc/musl.
const robust_list_head_size = u64(24)

const robust_list_limit = 2048

const futex_waiters = u32(0x80000000)

const futex_owner_died = u32(0x40000000)

const futex_tid_mask = u32(0x3fffffff)

// struct rusage, 18 longs on LP64.
struct Rusage {
mut:
	ru_utime_sec  i64
	ru_utime_usec i64
	ru_stime_sec  i64
	ru_stime_usec i64
	ru_maxrss     i64
	ru_ixrss      i64
	ru_idrss      i64
	ru_isrss      i64
	ru_minflt     i64
	ru_majflt     i64
	ru_nswap      i64
	ru_inblock    i64
	ru_oublock    i64
	ru_msgsnd     i64
	ru_msgrcv     i64
	ru_nsignals   i64
	ru_nvcsw      i64
	ru_nivcsw     i64
}

// The SIGCHLD arm of siginfo_t, padded to the full 128-byte structure.
struct SigInfoChld {
mut:
	si_signo  i32
	si_errno  i32
	si_code   i32
	pad0      i32
	si_pid    i32
	si_uid    u32
	si_status i32
	pad1      i32
	si_utime  i64
	si_stime  i64
	pad       [80]u8
}

// struct clone_args as of CLONE_ARGS_SIZE_VER2.
struct CloneArgs {
mut:
	flags        u64
	pidfd        u64
	child_tid    u64
	parent_tid   u64
	exit_signal  u64
	stack        u64
	stack_size   u64
	tls          u64
	set_tid      u64
	set_tid_size u64
	cgroup       u64
}

const clone_args_size_ver0 = u64(64)

// ── tid address and robust futex lists ───────────────────────────────────────

// set_tid_address(2): remember where to publish this thread's death.
pub fn syscall_set_tid_address(_ voidptr, tidptr u64) (u64, u64) {
	mut current_thread := proc.current_thread()

	current_thread.clear_child_tid = tidptr

	return u64(proc.own_tid(current_thread)), 0
}

pub fn syscall_set_robust_list(_ voidptr, head u64, len u64) (u64, u64) {
	if len != robust_list_head_size {
		return errno.err, errno.einval
	}

	mut current_thread := proc.current_thread()
	current_thread.robust_list_head = head

	return 0, 0
}

pub fn syscall_get_robust_list(_ voidptr, tid int, head_ptr u64, len_ptr u64) (u64, u64) {
	mut head := proc.current_thread().robust_list_head
	if tid != 0 {
		target := proc.thread_in(proc.current_pid_namespace(), tid)
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
		head = target.robust_list_head
		proc.unpin_thread(target)
	}

	if head_ptr == 0 || len_ptr == 0 {
		return errno.err, errno.efault
	}

	len := robust_list_head_size

	if !usercopy.copy_to_user(head_ptr, voidptr(&head), sizeof(u64)) {
		return errno.err, errno.efault
	}
	if !usercopy.copy_to_user(len_ptr, voidptr(&len), sizeof(u64)) {
		return errno.err, errno.efault
	}

	return 0, 0
}

// CLONE_CHILD_CLEARTID / set_tid_address(2): zero the word and wake whoever is
// blocked on it. This is how pthread_join() learns the thread is gone.
fn clear_child_tid(mut t proc.Thread) {
	address := t.clear_child_tid
	if address == 0 {
		return
	}
	t.clear_child_tid = 0

	zero := u32(0)
	if !usercopy.copy_to_user(address, voidptr(&zero), sizeof(u32)) {
		return
	}

	futex.wake(address)
}

// Walk the list registered with set_robust_list(2) and pass on every lock the
// dying thread still holds, flagged FUTEX_OWNER_DIED so the next owner knows
// the state it inherits may be inconsistent.
fn release_robust_list(mut t proc.Thread) {
	head := t.robust_list_head
	if head == 0 {
		return
	}
	t.robust_list_head = 0

	mut entry := u64(0)
	mut offset := i64(0)
	mut pending := u64(0)
	if !usercopy.copy_from_user(voidptr(&entry), head, sizeof(u64)) {
		return
	}
	if !usercopy.copy_from_user(voidptr(&offset), head + 8, sizeof(i64)) {
		return
	}
	if !usercopy.copy_from_user(voidptr(&pending), head + 16, sizeof(u64)) {
		return
	}

	// The head itself is a list member, so the walk stops when it comes back
	// round; the iteration cap guards against a corrupted list.
	for i := 0; i < robust_list_limit && entry != 0 && entry != head; i++ {
		mut next := u64(0)
		if !usercopy.copy_from_user(voidptr(&next), entry, sizeof(u64)) {
			break
		}
		if entry != pending {
			abandon_robust_futex(proc.own_tid(t), u64(i64(entry) + offset))
		}
		entry = next
	}

	// list_op_pending covers the lock the thread was in the middle of taking
	// or releasing when it died.
	if pending != 0 {
		abandon_robust_futex(proc.own_tid(t), u64(i64(pending) + offset))
	}
}

// `tid` is the thread's own number, which is what userspace stored as the
// owner.
fn abandon_robust_futex(tid int, address u64) {
	mut value := u32(0)
	if !usercopy.copy_from_user(voidptr(&value), address, sizeof(u32)) {
		return
	}
	if value & futex_tid_mask != u32(tid) {
		return
	}

	new_value := (value & futex_waiters) | futex_owner_died
	if !usercopy.copy_to_user(address, voidptr(&new_value), sizeof(u32)) {
		return
	}

	if value & futex_waiters != 0 {
		futex.wake(address)
	}
}

// ── wait ─────────────────────────────────────────────────────────────────────

// Selector semantics shared by wait4() and waitid(): >0 one pid, 0 the caller's
// process group, -1 any child, < -1 the process group -pid.
// `pid` is as the caller's pid namespace numbers processes and groups.
fn child_matches(current_process &proc.Process, child &proc.Process, pid int) bool {
	if pid == -1 {
		return true
	}
	viewer := current_process.numbered_in
	if pid > 0 {
		return proc.pid_in(child, viewer) == pid
	}
	if pid == 0 {
		return child.pgid == current_process.pgid
	}
	return proc.pgid_in(child, viewer) == -pid
}

// Scan under the parent's child-list lock; only a selected result escapes,
// carrying one reference through copy-out. Blocking waits use the parent's
// single child-change event, so a child beyond max_events cannot starve and a
// concurrent reap wakes the other waiters to rescan instead of dangling.
fn take_child_change(mut parent proc.Process, pid int, block bool, exits bool,
	stops bool, continues bool, keep bool) (&proc.Process, int, int, u64) {
	for {
		parent.children_lock.acquire()
		mut found := false
		for candidate in parent.children {
			if !child_matches(parent, candidate, pid) { continue }
			found = true
			mut child := unsafe { candidate }
			if exits {
				if _ := event.await_one(mut &child.event, false) {
					proc.pin_process(child)
					parent.children_lock.release()
					return child, child.status, 1, u64(0)
				}
			}
			child.job_lock.acquire()
			if stops && child.job_stop_pending {
				status := (child.job_stop_signal << 8) | 0x7f
				if !keep { child.job_stop_pending = false }
				child.job_lock.release()
				proc.pin_process(child)
				parent.children_lock.release()
				return child, status, 2, u64(0)
			}
			if continues && child.job_continue_pending {
				if !keep { child.job_continue_pending = false }
				child.job_lock.release()
				proc.pin_process(child)
				parent.children_lock.release()
				return child, 0xffff, 3, u64(0)
			}
			child.job_lock.release()
		}
		parent.children_lock.release()
		if !found { return unsafe { nil }, 0, 0, errno.echild }
		if !block { return unsafe { nil }, 0, 0, u64(0) }
		event.await_one(mut &parent.child_event, true) or {
			last, last_status, last_kind, last_error := take_child_change(mut parent, pid,
				false, exits, stops, continues, keep)
			if last == unsafe { nil } && last_error == 0 {
				return unsafe { nil }, 0, 0, errno.eintr
			}
			return last, last_status, last_kind, last_error
		}
	}
	return unsafe { nil }, 0, 0, u64(0)
}

fn put_back_change(mut child proc.Process, status int, kind int) u64 {
	if kind == 1 { return put_back(mut child) }
	child.job_lock.acquire()
	if kind == 2 {
		child.job_stop_signal = status >> 8
		child.job_stop_pending = true
	} else { child.job_continue_pending = true }
	child.job_lock.release()
	mut parent := proc.current_thread().process
	event.trigger(mut &parent.child_event, false)
	return errno.efault
}

fn release_child(mut current_process proc.Process, child &proc.Process) {
	current_process.children_lock.acquire()
	index := current_process.children.index(child)
	if index >= 0 {
		current_process.children.delete(index)
	}
	current_process.children_lock.release()
	event.trigger(mut &current_process.child_event, false)

	proc.account_reaped_child(mut current_process, child)
	proc.free_pid(child.pid)
}

// A failed copy-out must not swallow the exit: hand the event back so the child
// is still reapable, and report EFAULT.
fn put_back(mut child proc.Process) u64 {
	event.trigger(mut &child.event, false)
	mut parent := proc.current_thread().process
	event.trigger(mut &parent.child_event, false)
	return errno.efault
}

fn write_child_rusage(rusage_ptr u64, child &proc.Process) bool {
	if rusage_ptr == 0 {
		return true
	}

	user := katomic.load(&child.cpu_user_ns)
	system := katomic.load(&child.cpu_system_ns)
	usage := Rusage{
		ru_utime_sec:  i64(user / 1000000000)
		ru_utime_usec: i64((user % 1000000000) / 1000)
		ru_stime_sec: i64(system / 1000000000)
		ru_stime_usec: i64((system % 1000000000) / 1000)
	}
	return usercopy.copy_to_user(rusage_ptr, voidptr(&usage), sizeof(Rusage))
}

// wait4(pid, status, options, rusage).
pub fn syscall_wait4(_ voidptr, pid int, status_ptr u64, options int, rusage_ptr u64) (u64, u64) {
	mut current_process := proc.current_thread().process

	mut child, raw_status, kind, err := take_child_change(mut current_process, pid,
		options & wnohang == 0, true, options & wstopped != 0, options & wcontinued != 0, false)
	if child == unsafe { nil } {
		if err != 0 { return errno.err, err }
		return 0, 0
	}
	defer { proc.unpin_process(child) }
	status := i32(raw_status)
	reaped := proc.pid_in(child, current_process.numbered_in)
	if status_ptr != 0 && !usercopy.copy_to_user(status_ptr, voidptr(&status), sizeof(i32)) {
		return errno.err, put_back_change(mut child, raw_status, kind)
	}
	if !write_child_rusage(rusage_ptr, child) {
		return errno.err, put_back_change(mut child, raw_status, kind)
	}
	if kind == 1 { release_child(mut current_process, child) }

	return u64(reaped), 0
}

// waitid(idtype, id, infop, options, rusage).
pub fn syscall_waitid(_ voidptr, idtype int, id u64, infop u64, options int, rusage_ptr u64) (u64, u64) {
	mut current_process := proc.current_thread().process

	// Exactly which state changes to report has to be asked for.
	if options & (wexited | wstopped | wcontinued) == 0 {
		return errno.err, errno.einval
	}

	mut pid := 0
	match idtype {
		p_all {
			pid = -1
		}
		p_pid {
			if id == 0 || id > u64(0x7fffffff) {
				return errno.err, errno.einval
			}
			pid = int(id)
		}
		p_pgid {
			if id > u64(0x7fffffff) {
				return errno.err, errno.einval
			}
			pid = if id == 0 { 0 } else { -int(id) }
		}
		else {
			return errno.err, errno.einval
		}
	}

	mut child, status, kind, err := take_child_change(mut current_process, pid,
		options & wnohang == 0, options & wexited != 0, options & wstopped != 0,
		options & wcontinued != 0, options & wnowait != 0)
	if child == unsafe { nil } {
		if err != 0 {
			return errno.err, err
		}
		// WNOHANG with nothing to report: Linux signals that with si_pid == 0.
		if infop != 0 {
			info := SigInfoChld{}
			if !usercopy.copy_to_user(infop, voidptr(&info), sizeof(SigInfoChld)) {
				return errno.err, errno.efault
			}
		}
		return 0, 0
	}

	defer { proc.unpin_process(child) }
	mut info := SigInfoChld{
		si_signo:  i32(sigchld)
		si_code:   i32(cld_exited)
		si_pid:    i32(proc.pid_in(child, current_process.numbered_in))
		si_status: i32((status >> 8) & 0xff)
	}
	if kind == 2 {
		info.si_code = 5 // CLD_STOPPED
		info.si_status = i32(status >> 8)
	} else if kind == 3 {
		info.si_code = 6 // CLD_CONTINUED
		info.si_status = i32(sigcont)
	} else if status & 0x7f != 0 {
		info.si_code = i32(cld_killed)
		info.si_status = i32(status & 0x7f)
	}

	if infop != 0 && !usercopy.copy_to_user(infop, voidptr(&info), sizeof(SigInfoChld)) {
		return errno.err, put_back_change(mut child, status, kind)
	}
	if !write_child_rusage(rusage_ptr, child) {
		return errno.err, put_back_change(mut child, status, kind)
	}

	if kind == 1 {
		if options & wnowait != 0 {
			event.trigger(mut &child.event, false)
			event.trigger(mut &current_process.child_event, false)
		} else { release_child(mut current_process, child) }
	}

	return 0, 0
}
