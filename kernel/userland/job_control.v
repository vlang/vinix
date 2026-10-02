// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

import katomic
import proc
import sched

fn is_stop_signal(signal int) bool {
	return signal == sigstop || signal == sigtstp || signal == sigttin || signal == sigttou
}

// STOP and CONT cancel their opposite pending dispositions in every sibling.
// Stopping uses scheduler eligibility, never a thread's exit/dead state: its
// saved context, wait listeners and address space remain intact to resume.
fn change_job_state_locked(mut p proc.Process, stop bool, signal int) bool {
	if p.exiting { return false }
	p.job_lock.acquire()
	was_stopped := katomic.load(&p.job_stopped)
	changed := was_stopped != stop
	if stop {
		p.job_continue_pending = false
		if changed {
			p.job_stop_signal = signal
			p.job_stop_pending = true
		}
	} else {
		p.job_stop_pending = false
		if changed { p.job_continue_pending = true }
	}
	katomic.store(mut &p.job_stopped, stop)
	p.job_lock.release()
	mut clear_mask := u64(1) << (sigcont - 1)
	if !stop {
		clear_mask = (u64(1) << (sigstop - 1)) | (u64(1) << (sigtstp - 1))
			| (u64(1) << (sigttin - 1)) | (u64(1) << (sigttou - 1))
	}
	clear_job_signals_locked(mut p, clear_mask)
	$if amd64 {
		if changed && stop {
			// Ask busy siblings to check their new eligibility at an interrupt.
			// The IPI never parks a thread while this delivery lock is held.
			for t in p.threads {
				on := katomic.load(&t.running_on)
				if on != u64(-1) { sched.wake_cpu(u32(on)) }
			}
		}
	}
	return changed
}

// Process-directed delivery may hold signal-info and table locks too. Never
// notify the parent here: that lookup and SIGCHLD delivery acquire them again.
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

// Caller holds threads_lock. STOP and CONT take effect even while exec has
// no signalable replacement; other stopping signals only cancel pending CONT.
fn apply_job_signal_locked(mut p proc.Process, signal int) bool {
	if signal == sigcont { return change_job_state_locked(mut p, false, signal) }
	if signal == sigstop { return change_job_state_locked(mut p, true, signal) }
	if is_stop_signal(signal) { clear_job_signals_locked(mut p, u64(1) << (sigcont - 1)) }
	return false
}

fn change_job_state(target &proc.Process, stop bool, signal int) {
	if target == unsafe { nil } { return }
	mut p := unsafe { target }
	p.threads_lock.acquire()
	changed := change_job_state_locked(mut p, stop, signal)
	if changed { proc.pin_process(p) }
	p.threads_lock.release()
	if changed {
		notify_parent(p)
		proc.unpin_process(p)
	}
}

// The caller owns a process reference and has released signal-info, table,
// and thread-list locks before publishing the parent's wait notification.
pub fn notify_signal_parent(target &proc.Process) {
	notify_parent(target)
}

// Called only for an uncaught default stopping disposition, once a blocked
// TSTP/TTIN/TTOU is delivered. SIGSTOP itself changes state at send time.
fn stop_for_signal(signal int) {
	change_job_state(proc.current_thread().process, true, signal)
	sched.park_for_cgroup()
}

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
