// SPDX-License-Identifier: GPL-2.0-or-later
module sched

import katomic
import lib
import proc
import x86.cpu
import x86.cpu.local as cpulocal

// The current task has just cleared its outer migration pin with IRQs off.
// This shares the actual scheduler's eligibility and placement policy instead
// of introducing a second affinity interpretation. Both IPIs are notifications;
// no lock, completion, queue mutation, allocation or explicit yield is needed.
pub fn request_migration_reschedule(task &proc.Thread, source_cpu u32) bool {
	if cpu.interrupt_state() {
		lib.kpanic(unsafe { nil }, c'sched: migration release requires disabled IRQs')
	}
	count := cpu_locals.len
	if count < 1 || count > 256 || source_cpu >= u32(count)
		|| cpulocal.current().cpu_number != u64(source_cpu)
		|| katomic.load(&cpu_locals[source_cpu].online) != 1 {
		lib.kpanic(unsafe { nil }, c'sched: invalid migration release CPU domain')
	}
	if task == unsafe { nil } || voidptr(task) != voidptr(proc.current_thread())
		|| task.self != voidptr(task) || task.process == unsafe { nil }
		|| katomic.load(&task.is_dead) || katomic.load(&task.running_on) != u64(source_cpu)
		|| katomic.load(&task.linuxkpi_migration_pin) != 0 {
		lib.kpanic(unsafe { nil }, c'sched: migration release requires an unpinned live current task')
	}
	// A remote native affinity setter can publish another valid mask at any
	// point. Select and validate against one atomic snapshot, so that a later
	// publication cannot turn an ordinary stale wake hint into a false fatal.
	affinity := katomic.load(&task.affinity_mask)
	if may_run_here_with_affinity(task, u64(source_cpu), affinity) { return false }
	// Share the actual scorer and eligibility owner. Default zero must pass
	// the same snapshot too; otherwise it genuinely had no eligible CPU.
	// CPU hotplug and concurrent parking are outside this fixed boot domain.
	target := placement_cpu_with_affinity(task, affinity)
	if target >= u64(count) || katomic.load(&cpu_locals[target].online) != 1
		|| !may_run_here_with_affinity(task, target, affinity) {
		lib.kpanic(unsafe { nil }, c'sched: migration release has no eligible destination')
	}
	// Notification does not promise that a later mask still includes target.
	// Actual dispatch and the post-task-unlock wake use the latest policy.
	if !wake_cpu(source_cpu) || !wake_cpu(u32(target)) {
		lib.kpanic(unsafe { nil }, c'sched: migration release CPU wake failed')
	}
	return true
}
