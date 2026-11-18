module mmu

import event
import katomic
import proc
import time

pub fn (mut mgr UatManager) g13_slot_generation() u64 {
	return event.generation(mut mgr.slot_released)
}

fn g13_slot_wait_interrupted() bool {
	task := proc.current_thread()
	return katomic.load(&task.must_exit) || proc.pending_signals(task) & ~task.masked_signals != 0
		|| (task.process != unsafe { nil } && katomic.load(&task.process.job_stop_signal) != 0)
}

// Sample the generation before the bind attempt. A release between that
// attempt and listener registration must cause another attempt. The ASC can
// also switch away from an idle slot without notifying the host.
pub fn (mut mgr UatManager) wait_g13_slot(generation u64) bool {
	if g13_slot_wait_interrupted() { return false }
	mut retry := time.new_timer(time.TimeSpec{tv_nsec: 10000000}) @[freed]
	defer {
		retry.disarm()
		unsafe { free(retry) }
	}
	mut storage := [unsafe { &mgr.slot_released }, &retry.event]!
	mut events := unsafe { event.stack_list(&storage[0], storage.len) }
	event.await_from_generation(mut events, true, 0, generation) or {
		if g13_slot_wait_interrupted() { return false }
		// If the shared listener table is full, the private timer still
		// provides interruptible backpressure for this submitter.
		event.await_one(mut retry.event, true) or { return false }
	}
	return !g13_slot_wait_interrupted()
}
