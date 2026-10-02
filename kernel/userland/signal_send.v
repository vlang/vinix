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
	mut t := unsafe { _thread }

	if signal == 0 || signal > 64 {
		return
	}
	// SIGCONT resumes even when blocked or ignored. SIGSTOP cannot be caught
	// and stops every sibling, including threads which are not the recipient.
	if signal == u8(sigcont) {
		change_job_state(t.process, false, int(signal))
	} else if signal == u8(sigstop) {
		change_job_state(t.process, true, int(signal))
		return
	} else if is_stop_signal(int(signal)) && t.process != unsafe { nil } {
		mut process := t.process
		process.threads_lock.acquire()
		for sibling in process.threads {
			mut sibling_thread := unsafe { sibling }
			katomic.btr(mut &sibling_thread.pending_signals, u8(sigcont - 1))
		}
		process.threads_lock.release()
	}

	// An ignored signal is dropped, unless the thread blocks it: as on Linux,
	// a blocked signal is kept pending whatever its disposition, for
	// sigwait(2) and signalfd(2) to take. MariaDB's signal thread waits in
	// sigwait() for the one its shutdown sends it, and the bootstrap server
	// that creates its data directory never finished stopping.
	handler := t.sigactions[signal].sa_sigaction
	blocked := katomic.load(&t.masked_signals) & (u64(1) << (signal - 1)) != 0
	if !blocked && (handler == sig_ign
		|| (handler == sig_dfl && (has_default_ignore_action(int(signal)) || signal == u8(sigcont)))) {
		return
	}

	posixtimer.clear_signal_info(mut t, int(signal))
	katomic.bts(mut &t.pending_signals, signal - 1)
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
	bit := u64(1) << (signal - 1)
	unblockable := signal == sigkill || signal == sigstop
	target.threads_lock.acquire()
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
	}
	target.threads_lock.release()

	if chosen == unsafe { nil } {
		return false
	}

	sendsig(chosen, u8(signal))
	proc.unpin_thread(chosen)
	return true
}

// Send `signal` to process `pid` from inside the kernel: cgroup.kill, the death
// of a pid namespace's init, and PR_SET_PDEATHSIG all end up here.
pub fn signal_pid(pid int, signal int) {
	if pid <= 0 || pid >= proc.max_pid || signal <= 0 || signal > 64 {
		return
	}
	mut target := processes[pid]
	if target == unsafe { nil } || target.exiting {
		return
	}
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
	mut target := processes[pid]
	if target == unsafe { nil } {
		return
	}
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
		mut target := processes[global]
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
		mut target := processes[i]
		if target == unsafe { nil } {
			continue
		}
		if pgid != 0 && target.pgid != pgid {
			continue
		}
		if proc.numbers_own(viewer) && voidptr(target.numbered_in) != voidptr(viewer) {
			continue
		}
		if pid == -1 && (target.pid == init_pid || target.pid == current_process.pid) {
			continue
		}

		found = true
		if !may_signal(current_process, target, signal) { continue }
		permitted = true
		if signal != 0 {
			signal_process(mut target, signal)
		}
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
