// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// Sending signals, the same on both architectures: kill(2), tkill(2),
// tgkill(2), the kernel's own senders, and the pid a process is told it has.

import errno
import katomic
import posixtimer
import proc
import sched
import usercopy

// Linux ignores these signals when the process has not installed a handler.
// Discard them before queueing so an ignored signal cannot spuriously wake and
// interrupt a blocking syscall.
fn has_default_ignore_action(signum int) bool {
	return signum == sigchld || signum == sigurg || signum == sigwinch
}

pub fn syscall_getpid(_ voidptr) (u64, u64) {
	mut t := unsafe { proc.current_thread() }

	return u64(proc.own_pid(t.process)), 0
}

// A parent outside the caller's pid namespace is 0 to it, as a container's
// init sees the runtime that started it.
pub fn syscall_getppid(_ voidptr) (u64, u64) {
	mut t := unsafe { proc.current_thread() }
	process := t.process
	if !proc.numbers_own(process.numbered_in) {
		return u64(process.ppid), 0
	}
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	return u64(proc.pid_in(proc.process_at(process.ppid), process.numbered_in)), 0
}

pub fn sendsig(_thread &proc.Thread, signal u8) {
	sendsig_from(_thread, signal, unsafe { nil })
}

pub fn signal_broken_pipe() {
	current := proc.current_thread()
	process := current.process
	mut source := sender_source(proc.si_user, process)
	source.uid = proc.own_visible_id(process, process.uid, false)
	sendsig_from(current, u8(sigpipe), unsafe { &source })
}

// sendsig(), recording `source` (nil: none) as the signal's sender.
fn sendsig_from(_thread &proc.Thread, signal u8, source &proc.SignalSource) {
	if signal == 0 || signal > 64 { return }
	mut t := unsafe { _thread }
	// Storage pins alone do not preserve Thread.process during exit or exec.
	// Validate its owner and keep teardown out through the private delivery.
	posixtimer.lock_signal_info()
	proc.lock_table()
	mut target := &proc.Process(unsafe { nil })
	// A retained corpse can outlive its Process; inspect only Thread fields
	// before borrowing the owner under the table lock.
	if !katomic.load(&t.is_dead) && katomic.load(&t.exit_claimed) == 0 {
		target = t.process
	}
	mut changed := false
	if target != unsafe { nil } && !target.exiting {
		target.threads_lock.acquire()
		mut member := false
		for owned in target.threads {
			if voidptr(owned) == voidptr(t) { member = true; break }
		}
		// Exec retains its original thread explicitly until pending handoff.
		member = member || (target.exec_transition
			&& voidptr(target.exec_signal_thread) == voidptr(t))
		if member && voidptr(t.process) == voidptr(target) {
			changed = apply_job_signal_locked(mut target, int(signal))
			if target.exec_transition {
				target.exec_pending_signals |= u64(1) << (signal - 1)
			} else {
				sendsig_with_timer_lock(t, signal, true, source)
			}
			if changed { proc.pin_process(target) }
		}
		target.threads_lock.release()
	}
	proc.unlock_table()
	posixtimer.unlock_signal_info()
	if changed { notify_signal_parent(target); proc.unpin_process(target) }
}

fn sendsig_with_timer_lock(_thread &proc.Thread, signal u8, timer_locked bool, source &proc.SignalSource) {
	mut t := unsafe { _thread }

	if signal == 0 || signal > 64 || katomic.load(&t.is_dead) {
		return
	}

	// An ignored signal is dropped, unless the thread blocks it: as on Linux,
	// a blocked signal is kept pending whatever its disposition, for
	// sigwait(2) and signalfd(2) to take. MariaDB's signal thread waits in
	// sigwait() for the one its shutdown sends it, and the bootstrap server
	// that creates its data directory never finished stopping.
	handler := t.sigactions[signal].sa_sigaction
	blocked := signal != sigkill && signal != sigstop
		&& katomic.load(&t.masked_signals) & (u64(1) << (signal - 1)) != 0
	orphan_stop := handler == sig_dfl && signal != sigstop && stop_signal(int(signal))
		&& if timer_locked { proc.job_group_orphaned_locked(t.process.pgid, t.process.sid) } else { proc.job_group_orphaned(t.process.pgid, t.process.sid) }
	ignored := signal != sigkill && signal != sigstop && !blocked && (handler == sig_ign || orphan_stop
		|| (handler == sig_dfl && (has_default_ignore_action(int(signal)) || signal == sigcont)))
	// Job-control queuing may set the pending bit itself; note whether an
	// instance was already pending before this send.
	was_pending := katomic.load(&t.pending_signals) & (u64(1) << (signal - 1)) != 0
	job_signal := if timer_locked { queue_job_signal_locked(mut t, int(signal), !ignored) }
		else { queue_job_signal(mut t, int(signal), !ignored) }
	if ignored {
		return
	}

	if timer_locked && source != unsafe { nil } {
		posixtimer.record_thread_source_locked(mut t, int(signal), source, was_pending)
	} else if timer_locked {
		posixtimer.forget_thread_source_locked(mut t, int(signal), was_pending)
	} else {
		posixtimer.clear_signal_info(mut t, int(signal))
	}
	if !job_signal { katomic.bts(mut &t.pending_signals, signal - 1) }
	if t.process != unsafe { nil } {
		notify_signalfds(t.process.pid, int(signal))
	}

	// Wake the thread when it can take the signal now, or waits for it in
	// sigtimedwait(). A signal it blocks otherwise just stays pending: waking
	// it for one ended whatever it was waiting in with EINTR for nothing.
	if !blocked || katomic.load(&t.sigwait_set) & (u64(1) << (signal - 1)) != 0 {
		sched.enqueue_thread(t, true)
	}
}

// Ordinary process signals use a shared pending pool. Choosing a thread to
// wake does not give that thread exclusive ownership: a sibling entering
// sigwait later can claim a signal queued while everybody blocked it.
fn signal_process(mut target proc.Process, signal int) bool {
	return signal_process_from(mut target, signal, unsafe { nil })
}

// signal_process(), recording `source` (nil: none) as the signal's sender.
fn signal_process_from(mut target proc.Process, signal int, source &proc.SignalSource) bool {
	if signal <= 0 || signal > 64 { return false }
	posixtimer.lock_signal_info()
	proc.lock_table()
	accepted, changed := signal_process_with_timer_lock(mut target, signal, true, source)
	if changed { proc.pin_process(&target) }
	proc.unlock_table()
	posixtimer.unlock_signal_info()
	// Job-control event/runqueue wakes and parent delivery happen after all
	// owner locks are released, with the changed Process retained across them.
	if changed { notify_signal_parent(&target); proc.unpin_process(&target) }
	return accepted
}

// The caller holds signal-info and process-table locks, in that order.
// Keep the thread list locked through delivery to exclude group teardown.
// A true second result requires the caller to pin target under the table,
// then notify its parent and unpin only after releasing all delivery locks.
pub fn signal_process_locked(mut target proc.Process, signal int) (bool, bool) {
	return signal_process_with_timer_lock(mut target, signal, true, unsafe { nil })
}

fn signal_process_locked_from(mut target proc.Process, signal int, source &proc.SignalSource) (bool, bool) {
	return signal_process_with_timer_lock(mut target, signal, true, source)
}

fn begin_exec_signals(mut target proc.Process, old_thread &proc.Thread) {
	proc.lock_table()
	target.threads_lock.acquire()
	katomic.inc(mut &target.exec_count)
	target.exec_transition = true
	target.exec_pending_signals = katomic.load(&old_thread.pending_signals)
	target.exec_signal_thread = unsafe { old_thread }
	target.threads_lock.release()
	proc.unlock_table()
}

// The old thread stays alive until exec's final dequeue. The replacement is
// fully initialized before it becomes signalable or runnable, and no pidfd
// delivery can select a thread temporarily carrying kernel_process.
fn finish_exec_signals(mut target proc.Process, mut replacement proc.Thread,
	old_thread &proc.Thread, trace bool) bool {
	posixtimer.lock_signal_info()
	proc.lock_table()
	target.threads_lock.acquire()
	replacement.pending_signals = target.exec_pending_signals
		| katomic.load(&old_thread.pending_signals)
	target.exec_pending_signals = 0
	target.exec_transition = false
	target.exec_signal_thread = unsafe { nil }
	for signal := 1; signal <= 64; signal++ {
		bit := u64(1) << (signal - 1)
		if (replacement.pending_signals | katomic.load(&target.shared_pending_signals)) & bit == 0 { continue }
		handler := replacement.sigactions[signal].sa_sigaction
		if replacement.masked_signals & bit == 0 && (handler == sig_ign
			|| (handler == sig_dfl && (has_default_ignore_action(signal) || signal == sigcont))) {
			replacement.pending_signals &= ~bit
			katomic.btr(mut &target.shared_pending_signals, u8(signal - 1))
			continue
		}
		notify_signalfds(target.pid, signal)
	}
	mut enqueued := false
	$if arm64 {
		enqueued = if trace { sched.enqueue_thread_traced(&replacement, false) }
			else { sched.enqueue_thread(&replacement, false) }
	} $else {
		enqueued = sched.enqueue_thread(&replacement, false)
	}
	target.threads_lock.release()
	proc.unlock_table()
	posixtimer.unlock_signal_info()
	return enqueued
}

fn signal_process_with_timer_lock(mut target proc.Process, signal int, timer_locked bool, source &proc.SignalSource) (bool, bool) {
	bit := u64(1) << (signal - 1)
	unblockable := signal == sigkill || signal == sigstop
	target.threads_lock.acquire()
	if timer_locked && target.exiting {
		target.threads_lock.release()
		return false, false
	}
	changed := apply_job_signal_locked(mut target, signal)
	if changed && !timer_locked { proc.pin_process(&target) }
	if target.exec_transition {
		if stop_signal(signal) || signal == sigcont || signal == sigkill {
			target.exec_pending_signals |= bit
		} else {
			if timer_locked && source != unsafe { nil } {
				posixtimer.record_process_source_locked(mut target, signal, source)
			} else if timer_locked {
				posixtimer.forget_process_source_locked(mut target, signal)
			}
			katomic.bts(mut &target.shared_pending_signals, u8(signal - 1))
		}
		target.threads_lock.release()
		return true, changed
	}
	mut chosen := &proc.Thread(unsafe { nil })
	mut waiting := &proc.Thread(unsafe { nil })
	for t in target.threads {
		if katomic.load(&t.is_dead) || katomic.load(&t.exit_claimed) != 0 {
			continue
		}
		if chosen == unsafe { nil } {
			chosen = t
		}
		if unblockable || t.masked_signals & bit == 0 {
			chosen = t
			waiting = unsafe { nil }
			break
		}
		if waiting == unsafe { nil } && katomic.load(&t.sigwait_set) & bit != 0 {
			waiting = t
		}
	}
	if waiting != unsafe { nil } {
		chosen = waiting
	}
	if chosen != unsafe { nil } {
		proc.pin_thread(chosen)
		if timer_locked {
			// Keep claim_teardown out until delivery finishes: exit changes
			// the final thread's Process before clearing this thread list.
			queue_process_signal(mut target, chosen, signal, timer_locked, source)
		}
	}
	target.threads_lock.release()

	if chosen == unsafe { nil } {
		return false, changed
	}

	if !timer_locked { queue_process_signal(mut target, chosen, signal, timer_locked, source) }
	if !stop_signal(signal) && signal != sigcont && signal != sigkill {
		wake_shared_signal_waiters(mut target, signal)
	}
	proc.unpin_thread(chosen)
	return true, changed
}

// A failed siginfo usercopy returns the shared signal to its original pool.
// Wake every eligible observer: one may already have slept after the first
// waiter claimed it. Pins cover each runqueue operation outside the list lock.
fn requeue_shared_signal(mut process proc.Process, signal int) {
	katomic.bts(mut &process.shared_pending_signals, u8(signal - 1))
	notify_signalfds(process.pid, signal)
	wake_shared_signal_waiters(mut process, signal)
}

fn wake_shared_signal_waiters(mut process proc.Process, signal int) {
	bit := u64(1) << (signal - 1)
	if katomic.load(&process.shared_pending_signals) & bit == 0 { return }
	mut previous := -1
	for {
		process.threads_lock.acquire()
		mut chosen := &proc.Thread(unsafe { nil })
		for t in process.threads {
			if t.tid > previous && !katomic.load(&t.is_dead) && katomic.load(&t.exit_claimed) == 0
				&& (katomic.load(&t.masked_signals) & bit == 0 || katomic.load(&t.sigwait_set) & bit != 0)
				&& (chosen == unsafe { nil } || t.tid < chosen.tid) { chosen = t }
		}
		if chosen != unsafe { nil } { proc.pin_thread(chosen) }
		process.threads_lock.release()
		if chosen == unsafe { nil } { return }
		previous = chosen.tid
		sched.enqueue_thread(chosen, true)
		proc.unpin_thread(chosen)
	}
}

fn queue_process_signal(mut target proc.Process, chosen &proc.Thread, signal int, timer_locked bool, source &proc.SignalSource) {
	// Stop/continue carry a per-thread selection generation for the existing
	// process job-control protocol; fatal kill must also retain its priority.
	if stop_signal(signal) || signal == sigcont || signal == sigkill {
		sendsig_with_timer_lock(chosen, u8(signal), timer_locked, source)
		return
	}
	bit := u64(1) << (signal - 1)
	blocked := katomic.load(&chosen.masked_signals) & bit != 0
	handler := chosen.sigactions[signal].sa_sigaction
	if !blocked && (handler == sig_ign || (handler == sig_dfl && has_default_ignore_action(signal))) { return }
	if timer_locked && source != unsafe { nil } {
		posixtimer.record_process_source_locked(mut target, signal, source)
	} else if timer_locked {
		posixtimer.forget_process_source_locked(mut target, signal)
	}
	katomic.bts(mut &target.shared_pending_signals, u8(signal - 1))
	notify_signalfds(target.pid, signal)
	if !blocked || katomic.load(&chosen.sigwait_set) & bit != 0 {
		sched.enqueue_thread(chosen, true)
	}
}

// Send `signal` to process `pid` from inside the kernel: cgroup.kill, the death
// of a pid namespace's init, and PR_SET_PDEATHSIG all end up here.
pub fn signal_pid(pid int, signal int) {
	if pid <= 0 || pid >= proc.max_pid || signal <= 0 || signal > 64 {
		return
	}
	mut target := proc.pin_process_at(pid)
	if target == unsafe { nil } { return }
	defer { proc.unpin_process(target) }
	if target.exiting { return }
	signal_process(mut target, signal)
}

// kill(2). Signal 0 raises nothing: it is the "does this pid exist?" probe that
// shells and daemons use, so it must never fail loudly.
// cgroup.kill: fs asks the signal layer to kill a member of a cgroup. Kept
// here because fs cannot reach the signal code, which sits above it.
pub fn cgroup_kill_process(pid int, signal int) {
	if pid <= 0 || pid >= proc.max_pid {
		return
	}
	mut target := proc.pin_process_at(pid)
	if target == unsafe { nil } { return }
	defer { proc.unpin_process(target) }
	signal_process(mut target, signal)
}

pub fn syscall_kill(_ voidptr, pid int, signal int) (u64, u64) {
	if signal < 0 || signal > 64 {
		return errno.err, errno.einval
	}

	mut current_process := proc.current_thread().process
	// Pids and groups are the caller's namespace's numbers.
	viewer := current_process.numbered_in

	if pid > 0 {
		if pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		global := proc.pid_from(viewer, pid)
		if global <= 0 {
			return errno.err, errno.esrch
		}
		mut target := proc.pin_process_at(global)
		defer { if target != unsafe { nil } { proc.unpin_process(target) } }
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
		if !may_signal(current_process, target, signal) {
			return errno.err, errno.eperm
		}
		if signal == 0 {
			return 0, 0
		}
		source := sender_source(proc.si_user, target)
		if !signal_process_from(mut target, signal, unsafe { &source }) {
			// A zombie still owns its pid but has no thread left to signal.
			return 0, 0
		}
		return 0, 0
	}

	// 0 means our own process group, anything below -1 names a group directly,
	// and -1 means every process we are allowed to signal.
	mut pgid := 0
	if pid == 0 {
		pgid = current_process.pgid
	} else if pid < -1 {
		pgid = proc.group_from(viewer, -pid)
		if pgid == 0 {
			return errno.err, errno.esrch
		}
	}
	// A namespace's -1 reaches its own members only, and spares its init.
	init_pid := if proc.numbers_own(viewer) { viewer.init_pid } else { 1 }

	mut found := false
	mut permitted := false
	for i := 1; i < proc.max_pid; i++ {
		mut target := proc.pin_process_at(i)
		if target == unsafe { nil } {
			continue
		}
		if pgid != 0 && target.pgid != pgid {
			proc.unpin_process(target)
			continue
		}
		if proc.numbers_own(viewer) && voidptr(target.numbered_in) != voidptr(viewer) {
			proc.unpin_process(target)
			continue
		}
		if pid == -1 && (target.pid == init_pid || target.pid == current_process.pid) {
			proc.unpin_process(target)
			continue
		}

		found = true
		if !may_signal(current_process, target, signal) { proc.unpin_process(target); continue }
		permitted = true
		if signal != 0 {
			source := sender_source(proc.si_user, target)
			signal_process_from(mut target, signal, unsafe { &source })
		}
		proc.unpin_process(target)
	}

	if !found {
		return errno.err, errno.esrch
	}
	if !permitted { return errno.err, errno.eperm }

	return 0, 0
}

// tkill(2): musl's raise() and pthread_kill() aim at one thread rather than at
// the process as a whole.
pub fn syscall_tkill(_ voidptr, tid int, signal int) (u64, u64) {
	return signal_thread(0, tid, signal)
}

// tgkill(2): the same, with the thread group checked so that a recycled tid
// cannot be signalled by mistake. Linux refuses a group of 0 or less.
pub fn syscall_tgkill(_ voidptr, tgid int, tid int, signal int) (u64, u64) {
	if tgid <= 0 {
		return errno.err, errno.einval
	}
	return signal_thread(tgid, tid, signal)
}

fn signal_thread(tgid int, tid int, signal int) (u64, u64) {
	if signal < 0 || signal > 64 || tid <= 0 {
		return errno.err, errno.einval
	}

	// Go preempts its threads with tgkill(SIGURG) from every CPU, and those
	// threads come and go all the time; the pin keeps a target that exits in the
	// meantime from being freed and reused before the signal is on it.
	viewer := proc.current_pid_namespace()
	mut target := proc.thread_in(viewer, tid)
	if target == unsafe { nil } {
		return errno.err, errno.esrch
	}
	defer {
		proc.unpin_thread(target)
	}
	if katomic.load(&target.is_dead) || target.process == unsafe { nil } {
		return errno.err, errno.esrch
	}
	if tgid > 0 && proc.pid_in(target.process, viewer) != tgid {
		return errno.err, errno.esrch
	}
	if !may_signal(proc.current_thread().process, target.process, signal) {
		return errno.err, errno.eperm
	}
	if signal == 0 {
		return 0, 0
	}

	source := sender_source(proc.si_tkill, target.process)
	sendsig_from(target, u8(signal), unsafe { &source })

	return 0, 0
}

// CPU timers and limits use process-directed delivery, including a sibling
// that can receive a signal the charging thread blocks.
pub fn cpu_signal_process(target &proc.Process, signal int) {
	mut p := unsafe { target }
	if !p.exiting { signal_process(mut p, signal) }
}

// What kill, tkill and tgkill record: the caller's process as `target`'s pid
// namespace numbers it (0 when it cannot see it) and the caller's real uid.
fn sender_source(code int, target &proc.Process) proc.SignalSource {
	sender := proc.current_thread().process
	return proc.SignalSource{
		code: i32(code)
		pid:  i32(proc.pid_in(sender, target.numbered_in))
		uid:  sender.uid
	}
}

// Whether Linux knows the siginfo layout of `code` for `signal`: SI_KERNEL,
// the signal's own positive codes (NSIGPOLL's for most signals), and the
// negative codes from SI_DETHREAD up, plus SI_ASYNCNL.
fn known_siginfo_layout(signal int, code int) bool {
	if code == 0x80 { return true }
	if code > 0 {
		limit := match signal {
			4 { 11 } // SIGILL
			8 { 15 } // SIGFPE
			11 { 10 } // SIGSEGV
			7 { 5 } // SIGBUS
			5 { 6 } // SIGTRAP
			17 { 6 } // SIGCHLD
			31 { 2 } // SIGSYS
			else { 6 }
		}
		return code <= limit
	}
	return code >= -7 || code == -60
}

// Read a caller's siginfo_t as Linux does: the 48 bytes of its kernel copy,
// and, for a layout it does not know by `layout_signal` (or the given
// si_signo when 0) and si_code, the rest of the 128, which must be zero
// (E2BIG). Keeps si_code, si_pid, si_uid and si_value; returns an errno and
// the given si_signo.
fn read_user_siginfo(info_ptr u64, layout_signal int, mut source proc.SignalSource) (u64, int) {
	raw := unsafe { &u8(C.vinix_stack_alloc(128)) }
	if !usercopy.copy_from_user(voidptr(raw), info_ptr, 48) { return errno.efault, 0 }
	unsafe {
		signo := int(*&i32(raw))
		source.code = *&i32(u64(raw) + 8)
		source.pid = *&i32(u64(raw) + 16)
		source.uid = *&u32(u64(raw) + 20)
		source.value = *&u64(u64(raw) + 24)
		layout := if layout_signal > 0 { layout_signal } else { signo }
		if !known_siginfo_layout(layout, int(source.code)) {
			if !usercopy.copy_from_user(voidptr(u64(raw) + 48), info_ptr + 48, 80) {
				return errno.efault, signo
			}
			for i in 48 .. 128 {
				if raw[i] != 0 { return errno.e2big, signo }
			}
		}
		return 0, signo
	}
}

// Only a call aimed at the caller itself may carry a kernel's si_code (zero or
// positive) or SI_TKILL, which kill and tgkill add themselves.
fn forged_source(source &proc.SignalSource) bool {
	return source.code >= 0 || source.code == proc.si_tkill
}

// Vinix keeps one pending instance per signal. A second real-time signal
// queued with its own information is refused, as Linux refuses one past
// RLIMIT_SIGPENDING; a standard signal that is already pending is merged, as
// on Linux.
fn queue_full(pending u64, signal int) bool {
	return signal >= 32 && pending & (u64(1) << (signal - 1)) != 0
}

// rt_sigqueueinfo(pid, sig, info): `sig` with the caller's siginfo for the
// process with that pid (or containing that thread). Linux's order: EFAULT,
// EPERM for a forged code, ESRCH, EINVAL for the signal, EPERM.
pub fn syscall_rt_sigqueueinfo(_ voidptr, pid_word u64, signal_word u64, info_ptr u64) (u64, u64) {
	local := int(i32(u32(pid_word)))
	signal := int(i32(u32(signal_word)))
	mut source := proc.SignalSource{}
	failure, _ := read_user_siginfo(info_ptr, signal, mut source)
	if failure != 0 { return errno.err, failure }
	caller := proc.current_thread()
	if forged_source(&source) && proc.own_tid(caller) != local { return errno.err, errno.eperm }
	if local <= 0 { return errno.err, errno.esrch }
	// The process with that pid, or else the live process owning that thread:
	// an exiting or execing thread briefly belongs to the kernel's process.
	proc.lock_table()
	global := proc.kernel_id_locked(local)
	mut target := &proc.Process(unsafe { nil })
	if global > 0 && global < proc.max_pid {
		target = proc.process_at(global)
		t := threads_by_tid[global]
		if target == unsafe { nil } && t != unsafe { nil } && t.process != unsafe { nil }
			&& voidptr(proc.process_at(t.process.pid)) == voidptr(t.process) {
			target = t.process
		}
	}
	if target == unsafe { nil } {
		proc.unlock_table()
		return errno.err, errno.esrch
	}
	proc.pin_process(target)
	proc.unlock_table()
	defer { proc.unpin_process(target) }
	if signal < 0 || signal > 64 { return errno.err, errno.einval }
	if !may_signal(caller.process, target, signal) { return errno.err, errno.eperm }
	if signal == 0 { return 0, 0 }
	if queue_full(katomic.load(&target.shared_pending_signals), signal) {
		return errno.err, errno.eagain
	}
	// A zombie still owns its pid but has no thread left to signal.
	signal_process_from(mut target, signal, unsafe { &source })
	return 0, 0
}

// rt_tgsigqueueinfo(tgid, tid, sig, info): the same for one thread. Linux's
// order: EFAULT, EINVAL for a nonpositive id, EPERM for a forged code, ESRCH,
// EINVAL for the signal, EPERM.
pub fn syscall_rt_tgsigqueueinfo(_ voidptr, tgid_word u64, tid_word u64, signal_word u64, info_ptr u64) (u64, u64) {
	tgid := int(i32(u32(tgid_word)))
	tid := int(i32(u32(tid_word)))
	signal := int(i32(u32(signal_word)))
	mut source := proc.SignalSource{}
	failure, _ := read_user_siginfo(info_ptr, signal, mut source)
	if failure != 0 { return errno.err, failure }
	if tid <= 0 || tgid <= 0 { return errno.err, errno.einval }
	caller := proc.current_thread()
	if forged_source(&source) && proc.own_tid(caller) != tid { return errno.err, errno.eperm }
	viewer := proc.current_pid_namespace()
	mut target := proc.thread_in(viewer, tid)
	if target == unsafe { nil } { return errno.err, errno.esrch }
	defer { proc.unpin_thread(target) }
	if katomic.load(&target.is_dead) || target.process == unsafe { nil }
		|| proc.pid_in(target.process, viewer) != tgid {
		return errno.err, errno.esrch
	}
	if signal < 0 || signal > 64 { return errno.err, errno.einval }
	if !may_signal(caller.process, target.process, signal) { return errno.err, errno.eperm }
	if signal == 0 { return 0, 0 }
	if queue_full(katomic.load(&target.pending_signals), signal) { return errno.err, errno.eagain }
	sendsig_from(target, u8(signal), unsafe { &source })
	return 0, 0
}

// A POSIX message queue's SIGEV_SIGNAL notification: SI_MESGQ, with the
// sending process as the registered one numbers it, the sender's real uid and
// the registration's value. Like Linux it bypasses the permission check, and
// matches the process and the executable that registered it.
pub fn signal_message_queue_owner(pid int, start u64, exec_count u64, signal int, value u64) {
	if pid <= 0 || pid >= proc.max_pid || signal <= 0 || signal > 64 {
		return
	}
	posixtimer.lock_signal_info()
	proc.lock_table()
	mut target := proc.process_at(pid)
	mut changed := false
	// Match and enqueue under the same table lock used by begin_exec_signals.
	if target != unsafe { nil } && !target.exiting && target.start_time_ticks == start
		&& katomic.load(&target.exec_count) == exec_count {
		sender := proc.current_thread().process
		source := proc.SignalSource{
			code:  i32(proc.si_mesgq)
			pid:   i32(proc.pid_in(sender, target.numbered_in))
			uid:   sender.uid
			value: value
		}
		_, changed = signal_process_locked_from(mut target, signal, unsafe { &source })
		if changed { proc.pin_process(target) }
	}
	proc.unlock_table()
	posixtimer.unlock_signal_info()
	if changed { notify_signal_parent(target); proc.unpin_process(target) }
}
