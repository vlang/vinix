// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module sched

// Freeing a thread that has died. Something that found it before it died -- a
// signal on its way to it, a sibling stopping it -- may still be using it, and
// pins it for as long as it does; a pinned corpse waits here until the last of
// them has let go. Each arch supplies free_thread_memory(), which gives back
// the thread's stacks and the Thread itself.

import klock
import lib
import proc

__global (
	// Corpses still pinned when their turn to be freed came. See defer_reap().
	reap_deferred_head &proc.Thread = unsafe { nil }
	reap_deferred_lock klock.Lock
	// LinuxKPI native fixtures observe final frees as well as list removal.
	// Protected by reap_deferred_lock; never holds a pointer to freed storage.
	linuxkpi_reap_in_flight u64
)

// Free `t` now, or once nothing has it pinned.
fn reap_thread(t &proc.Thread) {
	if proc.thread_is_pinned(t) {
		defer_reap(t)
	} else {
		free_thread_memory(t)
	}
	reap_deferred()
}

// An intrusive list needs no allocation and has no fixed capacity. Linux
// task references can keep more than 64 exited threads alive at once.
fn defer_reap(t &proc.Thread) {
	reap_deferred_lock.acquire()
	defer {
		reap_deferred_lock.release()
	}
	mut thr := unsafe { t }
	if thr.reap_queued {
		return
	}
	thr.reap_next = reap_deferred_head
	thr.reap_queued = true
	reap_deferred_head = thr
}

// Free every waiting corpse whose last pin has gone. Nothing can pin a corpse
// from an unowned pointer: it left the tid table and its process' thread list
// before it died. Existing reference owners may acquire another pin while the
// count remains nonzero.
pub fn reap_deferred() {
	// The last put must finish a scan even if another CPU just scanned while
	// its pin was still held. A trylock could leave that corpse forever.
	reap_deferred_lock.acquire()
	mut ready := &proc.Thread(unsafe { nil })
	mut previous := &proc.Thread(unsafe { nil })
	mut t := reap_deferred_head
	for t != unsafe { nil } {
		next := t.reap_next
		if proc.thread_is_pinned(t) {
			previous = t
		} else {
			$if linuxkpi ? {
				if linuxkpi_reap_in_flight == ~u64(0) {
					lib.kpanic(unsafe { nil }, c'LinuxKPI deferred reaper counter overflow')
				}
				linuxkpi_reap_in_flight++
			}
			if previous == unsafe { nil } {
				reap_deferred_head = next
			} else {
				previous.reap_next = next
			}
			t.reap_next = ready
			t.reap_queued = false
			ready = t
		}
		t = next
	}
	reap_deferred_lock.release()
	for ready != unsafe { nil } {
		next := ready.reap_next
		free_thread_memory(ready)
		$if linuxkpi ? {
			reap_deferred_lock.acquire()
			if linuxkpi_reap_in_flight == 0 {
				lib.kpanic(unsafe { nil }, c'LinuxKPI deferred reaper counter underflow')
			}
			linuxkpi_reap_in_flight--
			reap_deferred_lock.release()
		}
		ready = next
	}
}

// Constructor failure before publication: no CPU or event ever owned t.
pub fn discard_unstarted_thread(t &proc.Thread) {
	assert !t.is_in_queue && t.running_on == u64(-1) && !proc.thread_is_pinned(t)
	free_thread_memory(t)
}
