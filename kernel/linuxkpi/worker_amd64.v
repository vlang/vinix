// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import errno
import katomic
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal

// Bind an anonymous native kernel pthread before its C worker publishes its
// ready completion. LinuxKPI cannot look it up by TID: these pthreads are not
// in the userspace thread table. Its existing scheduler reference keeps the
// Thread alive throughout this operation; no additional object is allocated.
//
// Affinity is a 64-bit mask in the native scheduler. Reject a larger machine
// even for a low target CPU because native CPUs beyond 63 are unconstrained.
// CPU hotplug is not supported, so the boot CPU table and online bits remain
// stable after LinuxKPI initialization.
@[export: 'vinix_linuxkpi_worker_bind']
fn worker_bind(target u32) int {
	ints := cpu.interrupt_toggle(false)
	index := cpulocal.current().cpu_number
	if !ints || preempt_depth[index] != 0 {
		cpu.interrupt_toggle(ints)
		return -errno.ewouldblock
	}
	if cpu_locals.len > 64 {
		cpu.interrupt_toggle(ints)
		return -errno.eopnotsupp
	}
	if target >= u32(cpu_locals.len) || katomic.load(&cpu_locals[target].online) == 0 {
		cpu.interrupt_toggle(ints)
		return -errno.einval
	}
	mut t := proc.current_thread()
	if t == unsafe { nil } || t.process != kernel_process || katomic.load(&t.is_dead) {
		cpu.interrupt_toggle(ints)
		return -errno.eperm
	}
	// No other CPU can hold this running thread's scheduling lock. Publish its
	// new mask atomically for the run-queue scans, and let the target CPU claim
	// its memory node instead of preferring the source node indefinitely.
	katomic.store(mut &t.numa_node, -1)
	katomic.store(mut &t.affinity_mask, u64(1) << target)
	cpu.interrupt_toggle(ints)

	for {
		check_ints := cpu.interrupt_toggle(false)
		placed := cpulocal.current().cpu_number == u64(target)
		cpu.interrupt_toggle(check_ints)
		if placed {
			return 0
		}
		// The scheduler also wakes an eligible CPU after releasing a migrated
		// thread's lock, closing the case where this IPI arrives too early for
		// the target's scan to take the still-running thread.
		assert sched.wake_cpu(target)
		sched.reschedule()
	}
	return 0
}
