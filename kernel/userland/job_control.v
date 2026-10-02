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
fn change_job_state(target &proc.Process, stop bool, signal int) {
	if target == unsafe { nil } || target.exiting { return }
	mut p := unsafe { target }
	p.threads_lock.acquire()
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
	for t in p.threads {
		mut sibling_thread := unsafe { t }
		for bit := u8(0); bit < 64; bit++ {
			if clear_mask & (u64(1) << bit) != 0 {
				katomic.btr(mut &sibling_thread.pending_signals, bit)
			}
		}
	}
	p.threads_lock.release()
	if changed {
		notify_parent(p)
	}
}

// Called only for an uncaught default stopping disposition, once a blocked
// TSTP/TTIN/TTOU is delivered. SIGSTOP itself changes state at send time.
fn stop_for_signal(signal int) {
	change_job_state(proc.current_thread().process, true, signal)
	sched.park_for_cgroup()
}

fn may_signal(caller &proc.Process, target &proc.Process, signal int) bool {
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
