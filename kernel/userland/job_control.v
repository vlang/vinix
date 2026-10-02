// SPDX-License-Identifier: GPL-2.0-or-later
module userland

import event
import katomic
import proc
import posixtimer
import sched

fn may_signal(caller &proc.Process, target &proc.Process, signal int) bool {
	if !proc.mac_peer_allowed(caller, target) { return false }
	// Capabilities acquired in a user namespace cannot signal its host.
	same_namespace := voidptr(caller.ns.user) == voidptr(target.ns.user)
	if proc.has_capability(caller, proc.cap_kill)
		&& (same_namespace || proc.is_initial_namespace(caller.ns.user)) {
		return true
	}
	if signal == sigcont && caller.sid == target.sid { return true }
	return same_namespace && (caller.uid == target.uid || caller.uid == target.suid
		|| caller.euid == target.uid || caller.euid == target.suid)
}

fn clear_job_signals_locked(mut p proc.Process, clear_mask u64) {
	p.exec_pending_signals &= ~clear_mask
	for t in p.threads {
		mut sibling_thread := unsafe { t }
		for bit := u8(0); bit < 64; bit++ {
			if clear_mask & (u64(1) << bit) != 0 {
				katomic.btr(mut &sibling_thread.pending_signals, bit)
			}
		}
	}
	// Exec can already have replaced its thread list. Its original thread is
	// still live until finish_exec_signals hands off and clears this borrow.
	if p.exec_transition && p.exec_signal_thread != unsafe { nil } {
		mut original := p.exec_signal_thread
		for bit := u8(0); bit < 64; bit++ {
			if clear_mask & (u64(1) << bit) != 0 {
				katomic.btr(mut &original.pending_signals, bit)
			}
		}
	}
}


fn stop_signal(signal int) bool {
	return signal == sigstop || signal == sigtstp || signal == sigttin || signal == sigttou
}

// Each thread is pinned under the owner lock, then woken after releasing it.
// No runqueue/event lock is acquired under threads_lock or job_lock. Picking
// the next tid avoids allocating a snapshot for every stop/continue operation.
fn wake_job_threads(mut process proc.Process) {
	mut previous := -1
	for {
		process.threads_lock.acquire()
		mut chosen := &proc.Thread(unsafe { nil })
		for t in process.threads {
			if t.tid > previous && !katomic.load(&t.is_dead)
				&& (chosen == unsafe { nil } || t.tid < chosen.tid) {
				chosen = t
			}
		}
		if chosen != unsafe { nil } { proc.pin_thread(chosen) }
		process.threads_lock.release()
		if chosen == unsafe { nil } { return }
		previous = chosen.tid
		event.trigger(mut &chosen.job_event, false)
		sched.enqueue_thread(chosen, true)
		proc.unpin_thread(chosen)
	}
}

// Stop/continue discard each other's pending signals process-wide even when
// blocked or ignored. A generation recorded at queue time prevents a stop
// already selected for dispatch from undoing a newer SIGCONT.
// Caller holds threads_lock; notifications and event/runqueue wakes are deferred.
fn apply_job_signal_locked(mut process proc.Process, signal int) bool {
	if !stop_signal(signal) && signal != sigcont && signal != sigkill { return false }
	process.job_lock.acquire()
	mut resumed := false
	if signal == sigcont || signal == sigkill {
		process.job_continue_generation++
		resumed = process.job_stop_signal != 0
		if resumed {
			process.job_generation++
			if signal == sigcont {
				process.wait_continue_epoch = process.job_generation
				process.job_notify_pending = true
			}
			process.wait_stop_epoch = 0
			katomic.store(mut &process.job_stop_complete, false)
			katomic.store(mut &process.job_stop_signal, 0)
			process.job_wake_pending = true
		}
		if signal == sigcont {
			mask := (u64(1) << (sigstop - 1)) | (u64(1) << (sigtstp - 1))
				| (u64(1) << (sigttin - 1)) | (u64(1) << (sigttou - 1))
			clear_job_signals_locked(mut process, mask)
		}
	} else {
		clear_job_signals_locked(mut process, u64(1) << (sigcont - 1))
	}
	process.job_lock.release()
	return resumed
}

fn queue_job_signal_locked(mut t proc.Thread, signal int, queue bool) bool {
	if !stop_signal(signal) && signal != sigcont && signal != sigkill { return false }
	mut process := t.process
	process.job_lock.acquire()
	if stop_signal(signal) { t.job_stop_generation = process.job_continue_generation }
	if queue { katomic.bts(mut &t.pending_signals, u8(signal - 1)) }
	process.job_lock.release()
	return true
}

fn queue_job_signal(mut t proc.Thread, signal int, queue bool) bool {
	if !stop_signal(signal) && signal != sigcont && signal != sigkill { return false }
	mut process := t.process
	if process == unsafe { nil } { return false }
	process.threads_lock.acquire()
	changed := apply_job_signal_locked(mut process, signal)
	job_signal := queue_job_signal_locked(mut t, signal, queue)
	if changed { proc.pin_process(process) }
	process.threads_lock.release()
	if changed { notify_signal_parent(process); proc.unpin_process(process) }
	return job_signal
}

// Locked signal senders retain a Process and invoke this only after dropping
// signal-info, table and thread-list locks. The embedded flags never escape.
pub fn notify_signal_parent(target &proc.Process) {
	mut process := unsafe { target }
	process.job_lock.acquire()
	wake := process.job_wake_pending
	notify := process.job_notify_pending
	process.job_wake_pending = false
	process.job_notify_pending = false
	process.job_lock.release()
	if wake { wake_job_threads(mut process) }
	if notify { publish_child_change(process, true) }
}

// Select a pending signal while retaining the generation of a stop signal.
// SIGKILL wins over a stop request, and neither KILL nor STOP is maskable.
fn take_pending_signal(mut t proc.Thread) int {
	if katomic.btr(mut &t.pending_signals, u8(sigkill - 1)) { return sigkill }
	for i := u8(0); i < 64; i++ {
		signal := int(i) + 1
		if signal != sigstop && t.masked_signals & (u64(1) << i) != 0 { continue }
		if stop_signal(signal) {
			mut process := t.process
			process.job_lock.acquire()
			present := katomic.btr(mut &t.pending_signals, i)
			if present { t.job_delivered_stop_generation = t.job_stop_generation }
			process.job_lock.release()
			if present { return signal }
		} else if katomic.btr(mut &t.pending_signals, i) {
			return signal
		}
	}
	return -1
}

fn request_group_stop(mut t proc.Thread, signal int) {
	mut process := t.process
	if signal != sigstop && proc.job_group_orphaned(process.pgid, process.sid) { return }
	process.threads_lock.acquire()
	process.job_lock.acquire()
	mut requested := false
	if !process.exiting && t.job_delivered_stop_generation == process.job_continue_generation
		&& process.job_stop_signal == 0 {
		process.job_generation++
		katomic.store(mut &process.job_stop_complete, false)
		process.wait_continue_epoch = 0
		katomic.store(mut &process.job_stop_signal, signal)
		requested = true
	}
	process.job_lock.release()
	process.threads_lock.release()
	if requested { wake_job_threads(mut process) }
	job_boundary()
}

// Caller holds threads_lock then job_lock. A thread acknowledges only on its
// owned kernel stack after all syscall locks have unwound. No user instruction
// runs after acknowledgement until CONT releases the group.
fn complete_group_stop(mut process proc.Process) bool {
	if process.job_stop_signal == 0 || process.job_stop_complete || process.exiting { return false }
	mut live := false
	for t in process.threads {
		if !katomic.load(&t.is_dead) && !katomic.load(&t.must_exit) { live = true }
		if !katomic.load(&t.is_dead) && !katomic.load(&t.must_exit)
			&& t.job_parked_generation != process.job_generation {
			return false
		}
	}
	if !live { return false }
	katomic.store(mut &process.job_stop_complete, true)
	process.wait_stop_signal = process.job_stop_signal
	process.wait_stop_epoch = process.job_generation
	return true
}

fn recheck_group_stop(mut process proc.Process) {
	process.threads_lock.acquire()
	process.job_lock.acquire()
	completed := complete_group_stop(mut process)
	process.job_lock.release()
	process.threads_lock.release()
	if completed { publish_child_change(process, true) }
}

fn owes_job_stop(t &proc.Thread) bool {
	return t.process != unsafe { nil } && katomic.load(&t.process.job_stop_signal) != 0
}

fn job_boundary() {
	mut t := proc.current_thread()
	mut process := t.process
	if process == unsafe { nil } { return }
	for owes_job_stop(t) && !katomic.load(&t.must_exit)
		&& katomic.load(&t.pending_signals) & (u64(1) << (sigkill - 1)) == 0 {
		process.threads_lock.acquire()
		process.job_lock.acquire()
		if process.job_stop_signal != 0 { t.job_parked_generation = process.job_generation }
		completed := complete_group_stop(mut process)
		process.job_lock.release()
		process.threads_lock.release()
		if completed { publish_child_change(process, true) }
		if owes_job_stop(t) {
			event.await_one_masked(mut &t.job_event, u64(1) << (sigkill - 1)) or {}
		}
	}
	process.job_lock.acquire()
	t.job_parked_generation = 0
	process.job_lock.release()
	exit_if_told_to()
}

// Kernel terminal senders use global group/session identities. Process structs
// are pinned across delivery; signal_process also pins its chosen live thread
// before any enqueue. sid=0 permits any session (ordinary kernel group signal).
pub fn signal_group(pgid int, sid int, signal int) bool {
	if pgid <= 0 || signal <= 0 || signal > 64 { return false }
	mut delivered := false
	// Match pidfd/queued timer delivery: signal-info -> table -> thread list.
	// Only scalar group/session numbers remain across notification unlocks.
	posixtimer.lock_signal_info()
	proc.lock_table()
	for pid := 1; pid < proc.max_pid; pid++ {
		mut target := proc.process_at(pid)
		if target == unsafe { nil } || target.exiting || target.pgid != pgid
			|| (sid != 0 && target.sid != sid) { continue }
		accepted, changed := signal_process_locked(mut target, signal)
		delivered = accepted || delivered
		if changed {
			proc.pin_process(target)
			proc.unlock_table()
			posixtimer.unlock_signal_info()
			notify_signal_parent(target)
			proc.unpin_process(target)
			posixtimer.lock_signal_info()
			proc.lock_table()
		}
	}
	proc.unlock_table()
	posixtimer.unlock_signal_info()
	return delivered
}

// proc keeps scalar group/session ID holds across this callback. Delivery
// pins each current member and queues HUP before the unconditional CONT resume.
pub fn signal_orphaned_job_group(pgid int, sid int) {
	signal_group(pgid, sid, sighup)
	signal_group(pgid, sid, sigcont)
}

fn publish_child_change(child &proc.Process, stop_or_continue bool) {
	mut parent := proc.pin_process_at(child.ppid)
	if parent == unsafe { nil } { return }
	wake_child_waiters(mut parent)
	mut notify := true
	if stop_or_continue {
		parent.threads_lock.acquire()
		if parent.threads.len != 0 {
			notify = parent.threads[0].sigactions[sigchld].sa_flags & 1 == 0
		}
		parent.threads_lock.release()
	}
	if notify { signal_process(mut parent, sigchld) }
	proc.unpin_process(parent)
}

// SysV message waits are never restarted for a caught handler, even with
// SA_RESTART. A default group stop has no user handler, so its internal wake
// must leave the wait restartable after CONT rather than expose a false EINTR.
fn job_wake_restarts_syscall(t &proc.Thread) bool {
	if owes_job_stop(t) { return true }
	pending := katomic.load(&t.pending_signals)
	if pending & (u64(1) << (sigstop - 1)) != 0 { return true }
	for signal in [sigtstp, sigttin, sigttou]! {
		bit := u64(1) << (signal - 1)
		if pending & bit != 0 && t.masked_signals & bit == 0 && t.sigactions[signal].sa_sigaction == sig_dfl
			&& !proc.job_group_orphaned(t.process.pgid, t.process.sid) {
			return true
		}
	}
	return false
}
