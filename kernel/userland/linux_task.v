// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// The parts of the Linux thread and process lifecycle that do not depend on
// the architecture: the clone flags and argument block, the tid word and robust
// futex list a thread hands back when it exits, and wait4/waitid. Each
// architecture's clone and exit are built on these.

import errno
import event
import event.eventstruct
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

// Look for a child selected by `pid` that has already exited. A nil child with
// errno 0 means "nothing ready yet", which only happens under WNOHANG.
fn take_exited_child(mut current_process proc.Process, pid int, block bool) (&proc.Process, u64) {
	// Snapshot the selection: event.await() below can block, which no spinlock
	// may be held across. Process structs outlive their pid, so the events
	// stay valid even if another thread reaps one of them meanwhile. Sized
	// for every child, as a list that grew would lose the buffers it outgrew.
	current_process.children_lock.acquire()
	mut candidates := []&proc.Process{cap: current_process.children.len} @[freed]
	mut events := []&eventstruct.Event{cap: current_process.children.len} @[freed]
	defer {
		unsafe {
			candidates.free()
			events.free()
		}
	}
	for c in current_process.children {
		if child_matches(current_process, c, pid) {
			candidates << c
			events << &c.event
		}
	}
	current_process.children_lock.release()

	if candidates.len == 0 {
		return unsafe { nil }, errno.echild
	}

	// A non-blocking look attaches no listeners, so it can cover every child
	// however many there are.
	if which := event.await(mut events, false) {
		return candidates[which], u64(0)
	}
	if !block {
		return unsafe { nil }, u64(0)
	}

	// Blocking does attach listeners, and a thread can only hold
	// proc.max_events of them. With more children than that we sleep on the
	// first batch; any of them waking us sends us round for another full sweep.
	mut watched := unsafe { events }
	if watched.len > proc.max_events {
		watched = events[..proc.max_events]
	}

	which := event.await(mut watched, true) or {
		// A signal cut the wait short. The child's exit itself raises SIGCHLD,
		// so look once more before reporting an interruption.
		retry := event.await(mut events, false) or { return unsafe { nil }, errno.eintr }
		return candidates[retry], u64(0)
	}

	return candidates[which], u64(0)
}

fn release_child(mut current_process proc.Process, child &proc.Process) {
	current_process.children_lock.acquire()
	index := current_process.children.index(child)
	if index >= 0 {
		current_process.children.delete(index)
	}
	current_process.children_lock.release()

	proc.account_reaped_child(mut current_process, child)
	proc.free_pid(child.pid)
}

// A failed copy-out must not swallow the exit: hand the event back so the child
// is still reapable, and report EFAULT.
fn put_back(mut child proc.Process) u64 {
	event.trigger(mut &child.event, false)
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

	mut child, err := take_exited_child(mut current_process, pid, options & wnohang == 0)
	if child == unsafe { nil } {
		if err != 0 {
			return errno.err, err
		}
		return 0, 0
	}

	status := i32(child.status)
	reaped := proc.pid_in(child, current_process.numbered_in)

	if status_ptr != 0 && !usercopy.copy_to_user(status_ptr, voidptr(&status), sizeof(i32)) {
		return errno.err, put_back(mut child)
	}
	if !write_child_rusage(rusage_ptr, child) {
		return errno.err, put_back(mut child)
	}

	release_child(mut current_process, child)

	return u64(reaped), 0
}

// waitid(idtype, id, infop, options, rusage).
pub fn syscall_waitid(_ voidptr, idtype int, id u64, infop u64, options int, rusage_ptr u64) (u64, u64) {
	mut current_process := proc.current_thread().process

	// Exactly which state changes to report has to be asked for; we only ever
	// report exits, since nothing here stops or continues a process yet.
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

	mut child, err := take_exited_child(mut current_process, pid, options & wnohang == 0)
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

	status := child.status
	mut info := SigInfoChld{
		si_signo:  i32(sigchld)
		si_code:   i32(cld_exited)
		si_pid:    i32(proc.pid_in(child, current_process.numbered_in))
		si_status: i32((status >> 8) & 0xff)
	}
	if status & 0x7f != 0 {
		info.si_code = i32(cld_killed)
		info.si_status = i32(status & 0x7f)
	}

	if infop != 0 && !usercopy.copy_to_user(infop, voidptr(&info), sizeof(SigInfoChld)) {
		return errno.err, put_back(mut child)
	}
	if !write_child_rusage(rusage_ptr, child) {
		return errno.err, put_back(mut child)
	}

	if options & wnowait != 0 {
		// Leave the child reapable: put back the event we just consumed.
		event.trigger(mut &child.event, false)
	} else {
		release_child(mut current_process, child)
	}

	return 0, 0
}
