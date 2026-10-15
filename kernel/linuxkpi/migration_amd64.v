// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import katomic
import lib
import proc
import sched
import x86.cpu
import x86.cpu.local as cpulocal

const migration_max_depth = u32(65535)

// Current-task state is observed with IRQs off. The scheduler retains this
// running Thread, including while a balanced maskable IRQ borrows it. The
// permanent boot domain cannot lose a CPU while LinuxKPI is active. Idle has
// no native current Thread; NMI use remains outside the supported contract.
// The single atomic word publishes depth and CPU together to remote scans.
fn migration_context() (bool, &proc.Thread, u32, u64, u32) {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	number := local.cpu_number
	count := cpu_locals.len
	if count < 1 || count > 256 || number >= u64(count)
		|| voidptr(local) != voidptr(cpu_locals[number]) || katomic.load(&local.online) != 1 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid migration CPU domain')
	}
	mut task := proc.current_thread()
	if task == unsafe { nil } || task.self != voidptr(task)
		|| task.process == unsafe { nil } || katomic.load(&task.is_dead)
		|| katomic.load(&task.running_on) != number {
		lib.kpanic(unsafe { nil }, c'linuxkpi: migration API requires a live current task')
	}
	word := katomic.load(&task.linuxkpi_migration_pin)
	depth := u32(word >> 32)
	if word != 0 && (depth == 0 || depth > migration_max_depth
		|| u32(word) != u32(number) + 1) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: corrupt or misplaced migration pin')
	}
	return ints, task, u32(number), word, depth
}

// Unlike a preemption pin, this task-owned nesting survives a sleep or yield.
// IRQs are disabled only across the scalar update, preserving the caller's
// preemption depth and exact entry IF. No affinity mask is overwritten.
@[export: 'migrate_disable']
fn native_migrate_disable() {
	ints, task, number, _, depth := migration_context()
	if depth == migration_max_depth {
		lib.kpanic(unsafe { nil }, c'linuxkpi: migration nesting overflow')
	}
	mut owner := unsafe { task }
	word := (u64(depth + 1) << 32) | u64(number + 1)
	katomic.store(mut &owner.linuxkpi_migration_pin, word)
	cpu.interrupt_toggle(ints)
}

@[export: 'migrate_enable']
fn native_migrate_enable() {
	ints, task, number, word, depth := migration_context()
	if depth == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unbalanced migrate_enable')
	}
	mut owner := unsafe { task }
	if depth > 1 {
		katomic.store(mut &owner.linuxkpi_migration_pin, word - (u64(1) << 32))
		cpu.interrupt_toggle(ints)
		return
	}
	// Once the override disappears, ordinary requested affinity governs every
	// scheduler path again. IPIs notify both CPUs without waiting on another
	// task or yielding here. Existing preemption/IRQ guards retain this pending
	// request until a safe dispatch; the switch wakes the target after unlock.
	katomic.store(mut &owner.linuxkpi_migration_pin, u64(0))
	if sched.request_migration_reschedule(task, number) {
		preempt_pending[number] = true
	}
	cpu.interrupt_toggle(ints)
}
