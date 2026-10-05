// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import errno
import katomic
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal

// Linux's high-priority workqueue pools use ordinary scheduling with nice -20.
// Anonymous native kernel pthreads share kernel_process, so changing its nice
// would also change every unrelated kernel thread. A worker sets its own
// override before it publishes readiness; the ordinary scheduler uses that
// value for the same timeslice weighting as process nice. This does not change
// scheduling policy or allocate memory.
@[export: 'vinix_linuxkpi_worker_set_nice']
fn worker_set_nice(nice i32) int {
	if nice < -20 || nice > 19 {
		return -errno.einval
	}
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	if !ints || preempt_depth[index] != 0 {
		cpu.interrupt_toggle(ints)
		return -errno.ewouldblock
	}
	mut t := proc.current_thread()
	if t == unsafe { nil } || t.process != kernel_process || katomic.load(&t.is_dead) {
		cpu.interrupt_toggle(ints)
		return -errno.eperm
	}
	// The running Thread holds its scheduler lock, so another CPU cannot
	// schedule it while these fields are published. Publish the value first,
	// then the enabling flag; the scheduler reads the flag before the value.
	katomic.store(mut &t.sched_nice_override, int(nice))
	katomic.store(mut &t.sched_has_nice_override, true)
	cpu.interrupt_toggle(ints)
	// Re-enter the scheduler so it arms the new quantum before this worker
	// publishes readiness, including when no other runnable thread exists.
	sched.reschedule()
	return 0
}

// Read-only probes expose the actual scheduler inputs/results to the native
// regression tests. IRQ protection keeps current stable throughout each read.
// Nice 20 and timeslice 0 are outside their valid ranges and indicate no task.
@[export: 'vinix_linuxkpi_worker_nice']
fn worker_nice() int {
	ints := cpu.interrupt_toggle(false)
	t := proc.current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } {
		cpu.interrupt_toggle(ints)
		return 20
	}
	nice := if katomic.load(&t.sched_has_nice_override) {
		katomic.load(&t.sched_nice_override)
	} else {
		katomic.load(&t.process.nice)
	}
	cpu.interrupt_toggle(ints)
	return nice
}

@[export: 'vinix_linuxkpi_worker_timeslice']
fn worker_timeslice() u64 {
	ints := cpu.interrupt_toggle(false)
	t := proc.current_thread()
	if t == unsafe { nil } {
		cpu.interrupt_toggle(ints)
		return 0
	}
	slice := sched.thread_timeslice(t)
	cpu.interrupt_toggle(ints)
	return slice
}
