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
import proc

const max_deferred_reaps = 64

__global (
	// Corpses still pinned when their turn to be freed came. See defer_reap().
	reap_deferred_slots [max_deferred_reaps]&proc.Thread
	reap_deferred_lock  klock.Lock
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

// A pinned corpse waits here. Pins last only as long as a signal delivery or a
// sibling's teardown, so the list stays short; one that does not fit is kept
// for good rather than freed under somebody's feet.
fn defer_reap(t &proc.Thread) {
	reap_deferred_lock.acquire()
	defer {
		reap_deferred_lock.release()
	}
	for i := 0; i < max_deferred_reaps; i++ {
		if unsafe { reap_deferred_slots[i] == nil } {
			reap_deferred_slots[i] = unsafe { t }
			return
		}
	}
}

// Free every waiting corpse whose last pin has gone. Nothing can pin a corpse
// again: it left the tid table and its process' thread list before it died.
fn reap_deferred() {
	if !reap_deferred_lock.test_and_acquire() {
		return
	}
	mut ready := unsafe { [max_deferred_reaps]&proc.Thread{} }
	mut count := 0
	for i := 0; i < max_deferred_reaps; i++ {
		t := reap_deferred_slots[i]
		if unsafe { t == nil } || proc.thread_is_pinned(t) {
			continue
		}
		reap_deferred_slots[i] = unsafe { nil }
		ready[count] = t
		count++
	}
	reap_deferred_lock.release()
	for i := 0; i < count; i++ {
		free_thread_memory(ready[i])
	}
}
