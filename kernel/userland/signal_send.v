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
				sendsig_with_timer_lock(t, signal, true)
			}
			if changed { proc.pin_process(target) }
		}
		target.threads_lock.release()
	}
	proc.unlock_table()
	posixtimer.unlock_signal_info()
	if changed { notify_signal_parent(target); proc.unpin_process(target) }
}

fn sendsig_with_timer_lock(_thread &proc.Thread, signal u8, timer_locked bool) {
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
	job_signal := if timer_locked { queue_job_signal_locked(mut t, int(signal), !ignored) }
		else { queue_job_signal(mut t, int(signal), !ignored) }
	if ignored {
		return
	}

	if timer_locked { posixtimer.acknowledge_signal_locked(mut t, int(signal)) }
	else { posixtimer.clear_signal_info(mut t, int(signal)) }
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

// Deliver a signal aimed at a whole process. Signal state is per-thread here,
// so there is no process-wide pending mask to raise; the signal goes to the
// first thread that does not block it, as Linux picks one, and only when every
// thread blocks it does it wait on the main thread. Always choosing the main
// thread lost signals for good in Go programs, whose main thread commonly sits
// with them blocked while other threads are the ones meant to take them.
//
// Linux keeps such a signal pending on the process, where any thread waiting
// for it in sigwait(2) takes it. The nearest here is to give it to a thread
// that waits for it now: MariaDB blocks SIGTERM in every thread, sends it to
// its own pid to stop the thread that sigwait()s for it, and that thread
// never saw it on the main thread, so the server never stopped.
fn signal_process(mut target proc.Process, signal int) bool {
	if signal <= 0 || signal > 64 { return false }
	posixtimer.lock_signal_info()
	proc.lock_table()
	accepted, changed := signal_process_locked(mut target, signal)
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
	return signal_process_with_timer_lock(mut target, signal, true)
}

fn begin_exec_signals(mut target proc.Process, old_thread &proc.Thread) {
	proc.lock_table()
	target.threads_lock.acquire()
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
		if replacement.pending_signals & bit == 0 { continue }
		handler := replacement.sigactions[signal].sa_sigaction
		if replacement.masked_signals & bit == 0 && (handler == sig_ign
			|| (handler == sig_dfl && (has_default_ignore_action(signal) || signal == sigcont))) {
			replacement.pending_signals &= ~bit
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

fn signal_process_with_timer_lock(mut target proc.Process, signal int, timer_locked bool) (bool, bool) {
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
		target.exec_pending_signals |= bit
		target.threads_lock.release()
		return true, changed
	}
	mut chosen := &proc.Thread(unsafe { nil })
	mut waiting := &proc.Thread(unsafe { nil })
	for t in target.threads {
		if katomic.load(&t.is_dead) {
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
			sendsig_with_timer_lock(chosen, u8(signal), true)
		}
	}
	target.threads_lock.release()

	if chosen == unsafe { nil } {
		return false, changed
	}

	if !timer_locked { sendsig_with_timer_lock(chosen, u8(signal), false) }
	proc.unpin_thread(chosen)
	return true, changed
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
		if !signal_process(mut target, signal) {
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
			signal_process(mut target, signal)
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

	sendsig(target, u8(signal))

	return 0, 0
}

// CPU timers and limits use process-directed delivery, including a sibling
// that can receive a signal the charging thread blocks.
pub fn cpu_signal_process(target &proc.Process, signal int) {
	mut p := unsafe { target }
	if !p.exiting { signal_process(mut p, signal) }
}
