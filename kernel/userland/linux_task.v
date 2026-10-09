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
pub const clone_vm = u64(0x00000100)
pub const clone_fs = u64(0x00000200)
pub const clone_files = u64(0x00000400)
pub const clone_sighand = u64(0x00000800)
pub const clone_vfork = u64(0x00004000)
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

// Linux requires shared handlers to share VM and threads to share handlers.
fn valid_clone_sharing(flags u64) bool {
	return !(flags & clone_sighand != 0 && flags & clone_vm == 0)
		&& !(flags & clone_thread != 0 && flags & clone_sighand == 0)
}

// FS, descriptor and handler ownership is currently process-scoped. Refuse
// combinations we cannot honor instead of silently copying requested sharing
// or silently sharing state the caller asked to keep independent.
fn supported_clone_sharing(flags u64) bool {
	if flags & clone_thread == 0 { return flags & (clone_fs | clone_files | clone_sighand) == 0 }
	return flags & (clone_fs | clone_files) == (clone_fs | clone_files) && flags & clone_vfork == 0
}

// Called only after switching off and releasing the child's old map. The
// parent owns a Process pin, so a simultaneous waiter cannot recycle the event.
fn complete_vfork(mut process proc.Process) {
	if !katomic.load(&process.vfork_pending) { return }
	katomic.store(mut &process.vfork_pending, false)
	event.trigger(mut &process.vfork_done, false)
}

fn await_vfork(mut child proc.Process) {
	defer { proc.unpin_process(&child) }
	for katomic.load(&child.vfork_pending) {
		// Ordinary caught signals remain pending until clone returns. Fatal
		// kill or sibling teardown may abort the wait, leaving the child's map
		// reference intact until its own exec/exit.
		event.await_one_masked(mut child.vfork_done, u64(1) << 8) or { break }
	}
}

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
		global := proc.kernel_id(tid)
		if global <= 0 || global >= proc.max_pid { return errno.err, errno.esrch }
		proc.lock_table()
		target := threads_by_tid[global]
		if target == unsafe { nil } {
			proc.unlock_table()
			return errno.err, errno.esrch
		}
		// The pointer is process layout. Check and copy under the lookup
		// lock rather than retaining a Thread and borrowing its Process.
		if !proc.may_inspect_locked(target.process) {
			proc.unlock_table()
			return errno.err, errno.eperm
		}
		head = target.robust_list_head
		proc.unlock_table()
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

// A waiter owns one stack event. The parent's children_lock protects list
// traversal and unlink, so arbitrary numbers of children/waiting siblings do
// not depend on the generic 32-event/64-listener limits.
struct ChildWaiter {
mut:
	next &ChildWaiter = unsafe { nil }
	wake eventstruct.Event
}

struct ChildChange {
	child  &proc.Process = unsafe { nil }
	kind   int
	status int
	epoch  u64
	err    u64
}

fn C.__builtin_alloca(usize) voidptr

fn wake_child_waiters(mut parent proc.Process) {
	parent.children_lock.acquire()
	parent.child_generation++
	event.trigger(mut &parent.child_event, false)
	mut waiter := unsafe { &ChildWaiter(parent.child_waiters) }
	for waiter != unsafe { nil } {
		event.trigger(mut &waiter.wake, false)
		waiter = waiter.next
	}
	parent.children_lock.release()
}

fn scan_child_change(mut parent proc.Process, pid int, options int) ChildChange {
	// The parent list owns a child until its exclusive wait claim is committed.
	// Unlike a raw process-table snapshot, a claimed child cannot be reaped and
	// freed while a copy-out faults or another sibling is waiting.
	mut matches := false
	for mut child in parent.children {
		if !child_matches(parent, child, pid) { continue }
		child.job_lock.acquire()
		if child.wait_reaped {
			child.job_lock.release()
			continue
		}
		matches = true
		if child.wait_busy {
			child.job_lock.release()
			continue
		}
		mut kind := 0
		mut status := 0
		mut epoch := u64(0)
		if options & wexited != 0 && child.wait_exit_ready {
			kind = wexited
			status = child.status
		} else if options & wstopped != 0 && child.wait_stop_epoch != 0 {
			kind = wstopped
			status = (child.wait_stop_signal << 8) | 0x7f
			epoch = child.wait_stop_epoch
		} else if options & wcontinued != 0 && child.wait_continue_epoch != 0 {
			kind = wcontinued
			status = 0xffff
			epoch = child.wait_continue_epoch
		}
		if kind != 0 {
			child.wait_busy = true
			proc.pin_process(child)
			child.job_lock.release()
			return ChildChange{ child: child, kind: kind, status: status, epoch: epoch }
		}
		child.job_lock.release()
	}
	return ChildChange{ err: if matches { u64(0) } else { errno.echild } }
}

fn take_child_change(mut parent proc.Process, pid int, options int) ChildChange {
	// alloca stays in this frame until listeners detach and the intrusive link
	// is removed. Taking &ChildWaiter{} or a promoted fixed array would leak.
	mut waiter := unsafe { &ChildWaiter(C.__builtin_alloca(sizeof(ChildWaiter))) }
	unsafe { *waiter = ChildWaiter{} }
	mut interrupted := false
	for {
		parent.children_lock.acquire()
		result := scan_child_change(mut parent, pid, options)
		if result.child != unsafe { nil } || result.err != 0 || options & wnohang != 0 || interrupted {
			parent.children_lock.release()
			if interrupted && result.child == unsafe { nil } && result.err == 0 {
				// Let the signal dispatcher apply SA_RESTART, or preserve the wait
				// across a default group stop with no userspace handler.
				return ChildChange{ err: proc.interrupted_errno }
			}
			return result
		}
		// Scanning and publishing this listener use the same owner lock as wakes.
		// trigger(drop=false) retains a wake before event.await attaches its slot.
		waiter.next = unsafe { &ChildWaiter(parent.child_waiters) }
		parent.child_waiters = voidptr(waiter)
		parent.children_lock.release()
		interrupted = false
		event.await_one(mut &waiter.wake, true) or {
			interrupted = true
			u64(0)
		}
		parent.children_lock.acquire()
		mut previous := &ChildWaiter(unsafe { nil })
		mut current := unsafe { &ChildWaiter(parent.child_waiters) }
		for current != unsafe { nil } {
			if voidptr(current) == voidptr(waiter) {
				if previous == unsafe { nil } {
					parent.child_waiters = voidptr(waiter.next)
				} else {
					previous.next = waiter.next
				}
				break
			}
			previous = current
			current = current.next
		}
		parent.children_lock.release()
	}
	return ChildChange{}
}

fn finish_child_change(mut parent proc.Process, change ChildChange, consume bool) {
	mut child := change.child
	child.job_lock.acquire()
	mut reap := false
	if consume {
		if change.kind == wexited {
			child.wait_reaped = true
			reap = true
		} else if change.kind == wstopped && child.wait_stop_epoch == change.epoch {
			child.wait_stop_epoch = 0
		} else if change.kind == wcontinued && child.wait_continue_epoch == change.epoch {
			child.wait_continue_epoch = 0
		}
	}
	child.wait_busy = false
	child.job_lock.release()
	if reap { release_child(mut parent, child) }
	wake_child_waiters(mut parent)
	proc.unpin_process(child)
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

fn write_child_rusage(rusage_ptr u64, child &proc.Process) bool {
	if rusage_ptr == 0 {
		return true
	}

	mut usage := unsafe { &proc.Rusage(C.vinix_stack_alloc(sizeof(proc.Rusage))) }
	unsafe { *usage = proc.Rusage{} }
	proc.fill_process_rusage(mut usage, child, proc.cpu_time_now_ns(), true)
	return usercopy.copy_to_user(rusage_ptr, usage, sizeof(proc.Rusage))
}

// wait4(pid, status, options, rusage).
pub fn syscall_wait4(_ voidptr, pid int, status_ptr u64, options int, rusage_ptr u64) (u64, u64) {
	mut current_process := proc.current_thread().process

	if options & ~(wnohang | wstopped | wcontinued) != 0 { return errno.err, errno.einval }
	change := take_child_change(mut current_process, pid, options | wexited)
	if change.child == unsafe { nil } {
		if change.err != 0 { return errno.err, change.err }
		return 0, 0
	}
	child := change.child
	status := i32(change.status)
	reaped := proc.pid_in(child, current_process.numbered_in)
	if status_ptr != 0 && !usercopy.copy_to_user(status_ptr, voidptr(&status), sizeof(i32)) {
		finish_child_change(mut current_process, change, false)
		return errno.err, errno.efault
	}
	if !write_child_rusage(rusage_ptr, child) {
		finish_child_change(mut current_process, change, false)
		return errno.err, errno.efault
	}

	finish_child_change(mut current_process, change, true)

	return u64(reaped), 0
}

// waitid(idtype, id, infop, options, rusage).
pub fn syscall_waitid(_ voidptr, idtype int, id u64, infop u64, options int, rusage_ptr u64) (u64, u64) {
	mut current_process := proc.current_thread().process

	// Linux requires an explicit set of child states to report.
	if options & (wexited | wstopped | wcontinued) == 0
		|| options & ~(wnohang | wexited | wstopped | wcontinued | wnowait) != 0 {
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

	change := take_child_change(mut current_process, pid, options)
	if change.child == unsafe { nil } {
		if change.err != 0 {
			return errno.err, change.err
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

	child := change.child
	status := change.status
	mut info := SigInfoChld{
		si_signo:  i32(sigchld)
		si_code:   i32(cld_exited)
		si_pid:    i32(proc.pid_in(child, current_process.numbered_in))
		si_status: i32((status >> 8) & 0xff)
	}
	if change.kind == wstopped {
		info.si_code = 5 // CLD_STOPPED
		info.si_status = i32((status >> 8) & 0xff)
	} else if change.kind == wcontinued {
		info.si_code = 6 // CLD_CONTINUED
		info.si_status = i32(sigcont)
	} else if status & 0x7f != 0 {
		info.si_code = i32(cld_killed)
		info.si_status = i32(status & 0x7f)
	}

	if infop != 0 && !usercopy.copy_to_user(infop, voidptr(&info), sizeof(SigInfoChld)) {
		finish_child_change(mut current_process, change, false)
		return errno.err, errno.efault
	}
	if !write_child_rusage(rusage_ptr, child) {
		finish_child_change(mut current_process, change, false)
		return errno.err, errno.efault
	}

	finish_child_change(mut current_process, change, options & wnowait == 0)

	return 0, 0
}
