module admission

import event
import event.eventstruct
import katomic
import proc
import time

// The owning file lock protects held. Only ioctl submitters acquire this
// gate. The worker can retire accepted jobs while the holder sleeps.
pub struct Gate {
mut:
	held bool
	released eventstruct.Event
}

pub fn (mut gate Gate) try_enter() bool {
	if gate.held { return false }
	gate.held = true
	return true
}

pub fn (mut gate Gate) leave() {
	assert gate.held
	gate.held = false
	event.trigger_n(mut gate.released, 1)
}

// Caller holds the lock which protects held.
pub fn (mut gate Gate) generation() u64 {
	return event.generation(mut gate.released)
}

pub fn (mut gate Gate) wait(generation u64) bool {
	return wait_release(mut gate.released, generation)
}

fn interrupted() bool {
	task := proc.current_thread()
	return katomic.load(&task.must_exit) || proc.pending_signals(task) & ~task.masked_signals != 0
		|| (task.process != unsafe { nil } && katomic.load(&task.process.job_stop_signal) != 0)
}

// Recheck periodically for silent ASC transitions, group stop and waiters
// skipped by a single-waiter notification.
pub fn wait_release(mut released eventstruct.Event, generation u64) bool {
	if interrupted() { return false }
	mut retry := time.new_timer(time.TimeSpec{tv_nsec: 10000000}) @[freed]
	defer {
		retry.disarm()
		unsafe { free(retry) }
	}
	mut storage := [unsafe { &released }, &retry.event]!
	mut events := unsafe { event.stack_list(&storage[0], storage.len) }
	event.await_from_generation(mut events, true, 0, generation) or {
		if interrupted() { return false }
		// The bounded shared listener table may be full. The private
		// timer can still block this submitter.
		event.await_one(mut retry.event, true) or { return false }
	}
	return !interrupted()
}
