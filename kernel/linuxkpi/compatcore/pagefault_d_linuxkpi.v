// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

#include "linuxkpi_pagefault_v_contract.h"

fn C.vinix_linuxkpi_fault_depth() &u32

// The aliases share the existing native ABI without redeclaring task.v's
// V function names in this module. These callbacks own no algorithm state.
@[c: 'vinix_linuxkpi_irq_save']
fn C.vkf_irq_save() u64
@[c: 'vinix_linuxkpi_irq_restore']
fn C.vkf_irq_restore(u64)
@[c: 'vinix_linuxkpi_preempt_count']
fn C.vkf_preempt_count() u32
fn C.vinix_linuxkpi_maskable_irq_depth() u32

// Linux needs compiler ordering, rather than an inter-CPU hardware fence,
// around its task-local depth change. This lowers to a compiler primitive.
@[c: '__atomic_signal_fence']
fn C.vkf_compiler_barrier(i32)

fn fault_depth_problem(flags u64, message &char) {
	C.vkf_irq_restore(flags)
	C.vinix_linuxkpi_bug(message, 0)
}

// The native getter borrows the running task's counter only for this call.
// IRQ capture protects the read/modify/write against interrupt nesting. It
// never leaves a preemption pin or changed interrupt state behind.
@[export: 'pagefault_disable']
pub fn pagefault_disable() {
	flags := C.vkf_irq_save()
	depth := C.vinix_linuxkpi_fault_depth()
	if depth == unsafe { nil } {
		fault_depth_problem(flags, c'pagefault_disable without a current task')
		return
	}
	previous := C.vkp_load32(depth, 0)
	if previous == u32(-1) {
		fault_depth_problem(flags, c'pagefault_disable depth overflow')
		return
	}
	C.vkp_store32(depth, previous + 1, 0)
	C.vkf_compiler_barrier(5)
	C.vkf_irq_restore(flags)
}

@[export: 'pagefault_enable']
pub fn pagefault_enable() {
	flags := C.vkf_irq_save()
	depth := C.vinix_linuxkpi_fault_depth()
	if depth == unsafe { nil } {
		fault_depth_problem(flags, c'pagefault_enable without a current task')
		return
	}
	previous := C.vkp_load32(depth, 0)
	if previous == 0 {
		fault_depth_problem(flags, c'pagefault_enable depth underflow')
		return
	}
	C.vkf_compiler_barrier(5)
	C.vkp_store32(depth, previous - 1, 0)
	C.vkf_irq_restore(flags)
}

// No current task exists during early bootstrap. Queries have no synthetic
// fallback counter, and do not change interrupt or preemption state.
@[export: 'pagefault_disabled']
pub fn pagefault_disabled() bool {
	depth := C.vinix_linuxkpi_fault_depth()
	return depth != unsafe { nil } && C.vkp_load32(depth, 0) != 0
}

// Explicit native pins and actual maskable IRQ nesting prohibit fault handling.
// Full Linux preempt-count encoding, softirq and NMI remain separate services.
@[export: 'faulthandler_disabled']
pub fn faulthandler_disabled() bool {
	return pagefault_disabled() || C.vkf_preempt_count() != 0
		|| C.vinix_linuxkpi_maskable_irq_depth() != 0
}
