// SPDX-License-Identifier: GPL-2.0-or-later
module local

import x86.cpu

#include "x86_irq_v_contract.h"

// Each boot-online CPU owns its counters for its entire lifetime. The native
// thunks call these with kernel GS installed and maskable interrupts disabled;
// exceptions, NMI and software bottom halves have separate contracts.
@[export: 'vinix_x86_maskable_irq_enter']
pub fn maskable_irq_enter(vector u32, saved_cs u64) {
	if cpu.interrupt_state() {
		panic('x86: maskable IRQ entry requires disabled interrupts')
	}
	if vector < 32 || vector > 255 {
		panic('x86: invalid maskable IRQ entry vector')
	}
	mut cpu_local := current()
	user_entry := saved_cs & 3 == 3
	if cpu_local.maskable_irq_depth == u32(-1)
		|| cpu_local.maskable_irq_entries == u64(-1)
		|| (user_entry && cpu_local.maskable_irq_user_entries == u64(-1)) {
		panic('x86: maskable IRQ accounting overflow')
	}
	depth := cpu_local.maskable_irq_depth + 1
	cpu_local.maskable_irq_depth = depth
	cpu_local.maskable_irq_entries++
	if user_entry {
		cpu_local.maskable_irq_user_entries++
	}
	if depth > cpu_local.maskable_irq_peak_depth {
		cpu_local.maskable_irq_peak_depth = depth
	}
}

// Normal thunk returns and the scheduler's noreturn handoff each consume one
// actual entry. The scheduler must consume its entry before changing GS or
// abandoning its interrupt stack; it must not also return through this exit.
@[export: 'vinix_x86_maskable_irq_exit']
pub fn maskable_irq_exit(vector u32) {
	if cpu.interrupt_state() {
		panic('x86: maskable IRQ exit requires disabled interrupts')
	}
	if vector < 32 || vector > 255 {
		panic('x86: invalid maskable IRQ exit vector')
	}
	mut cpu_local := current()
	if cpu_local.maskable_irq_depth == 0 {
		panic('x86: unbalanced maskable IRQ exit')
	}
	cpu_local.maskable_irq_depth--
}

// This synchronous CPU borrow preserves the caller's IF. It is valid only
// after this CPU has installed kernel GS, including between runnable threads;
// there is no pre-initialization zero fallback or postboot activation/reset.
@[export: 'vinix_x86_maskable_irq_depth']
pub fn maskable_irq_depth() u32 {
	interrupts := cpu.interrupt_toggle(false)
	depth := current().maskable_irq_depth
	cpu.interrupt_toggle(interrupts)
	return depth
}
