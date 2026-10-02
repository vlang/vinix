// SPDX-License-Identifier: GPL-2.0-or-later
module sched

import lib
import proc

// A native fixture owns a nonsaturated retained task reference throughout this
// process-context query, after joining an ordinary self-exiting x86 pthread.
// TASK_DEAD and running_on == -1 precede the scheduler's final off-stack
// handoff. Membership in the deferred list proves that handoff completed:
// the retained reference makes reap_thread defer rather than free the Thread.
// This observer consumes no reference and must never be called after last put.
// It does not claim that a later last put waits for another CPU's final free.
@[export: 'vinix_linuxkpi_test_thread_reap_ready']
fn linuxkpi_test_thread_reap_ready(owner voidptr) bool {
	$if linuxkpi ? {
		if owner == unsafe { nil } {
			lib.kpanic(unsafe { nil }, c'linuxkpi: invalid retained reaper test target')
		}
		t := unsafe { &proc.Thread(owner) }
		if !proc.thread_is_pinned(t) {
			lib.kpanic(unsafe { nil }, c'linuxkpi: unretained reaper test target')
		}
		reap_deferred_lock.acquire()
		ready := t.reap_queued
		reap_deferred_lock.release()
		return ready
	}
	return false
}

// The fixture first observes every retained worker above, then releases all
// of its references. No worker can subsequently enter this list for the first
// time. A CPU may already own an unlinked ready list: count it through its
// actual free, rather than interpreting an empty public list as completion.
// This observes the deferred path only, not all kernel allocation activity.
@[export: 'vinix_linuxkpi_test_reap_quiescent']
fn linuxkpi_test_reap_quiescent() bool {
	$if linuxkpi ? {
		reap_deferred_lock.acquire()
		quiet := reap_deferred_head == unsafe { nil } && linuxkpi_reap_in_flight == 0
		reap_deferred_lock.release()
		return quiet
	}
	return false
}
