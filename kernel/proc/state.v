// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import katomic

// Caller holds the table lock, retaining the validated selected task. Linux
// stat/status report that task even when another sibling is runnable.
pub fn task_state(process &Process, task &Thread) u8 {
	if process.exiting || task == unsafe { nil } || katomic.load(&task.is_dead) { return `Z` }
	if katomic.load(&process.job_stop_complete) { return `T` }
	if katomic.load(&task.is_in_queue) || katomic.load(&task.running_on) != u64(-1) { return `R` }
	return `S`
}

// Caller holds the process table lock. A process sleeps only when none of its
// live threads is running or queued; waiting on I/O must not read as running.
pub fn process_state(process &Process) u8 {
	if process.exiting { return `Z` }
	if katomic.load(&process.job_stop_complete) { return `T` }
	mut owner := unsafe { process }
	owner.threads_lock.acquire()
	defer { owner.threads_lock.release() }
	return process_state_unlocked(process)
}

// Caller holds both the process table and this process's thread-list lock.
// SysRq acquires the latter without waiting, so a busy list cannot block the
// diagnostic before it reaches the explicit busy-list report.
fn process_state_unlocked(process &Process) u8 {
	if process.exiting { return `Z` }
	if katomic.load(&process.job_stop_complete) { return `T` }
	for task in process.threads {
		if !katomic.load(&task.is_dead) && (katomic.load(&task.is_in_queue)
			|| katomic.load(&task.running_on) != u64(-1)) { return `R` }
	}
	return `S`
}
