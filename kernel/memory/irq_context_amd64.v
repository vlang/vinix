// SPDX-License-Identifier: GPL-2.0-or-later
module memory

import x86.cpu.local as cpulocal

fn maskable_irq_fault_context() bool {
	return cpulocal.maskable_irq_depth() != 0
}

// Called only after all boot CPUs acknowledge installed kernel GS, with
// interrupts disabled and before publishing the scheduler vector.
pub fn initialise_native_irq_fault_guard() {
	register_native_fault_context_guard(maskable_irq_fault_context)
}
