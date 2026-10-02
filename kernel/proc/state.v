// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import katomic

// Caller holds the process table lock. A process sleeps only when none of its
// live threads is running or queued; waiting on I/O must not read as running.
pub fn process_state(process &Process) u8 {
	if process.exiting { return `Z` }
	if katomic.load(&process.job_stop_complete) { return `T` }
	mut owner := unsafe { process }
	owner.threads_lock.acquire()
	defer { owner.threads_lock.release() }
	for task in process.threads {
		if !katomic.load(&task.is_dead) && (katomic.load(&task.is_in_queue)
			|| katomic.load(&task.running_on) != u64(-1)) { return `R` }
	}
	return `S`
}
