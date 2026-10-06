// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import katomic
import memory
import proc
import usercopy
import linuxkpi.compatcore

// A synchronous borrow from the running Thread. Running ownership protects
// the counter across preemption and migration; no caller retains this pointer.
@[export: 'vinix_linuxkpi_fault_depth']
fn native_fault_depth() &u32 {
	mut caller := proc.current_thread()
	if caller == unsafe { nil } { return unsafe { nil } }
	return unsafe { &caller.linuxkpi_fault_depth }
}

fn native_fault_resolution_disabled() bool {
	depth := native_fault_depth()
	return (depth != unsafe { nil } && katomic.load(depth) != 0)
		|| native_preempt_count() != 0
}

fn initialise_pagefault_policy() {
	memory.register_fault_resolution_guard(native_fault_resolution_disabled)
}

fn pagefault_native_selftest() bool {
	if !usercopy.pagefault_selftest() { return false }
	// Public V frontends reach the same resident-only native backend. Reject
	// invalid ranges without touching either pointer, including IRQ-off calls.
	flags := irq_save()
	from := compatcore.inatomic_from_user(unsafe { nil }, voidptr(usize(-1)), 8)
	to := compatcore.inatomic_to_user(voidptr(usize(-1)), unsafe { nil }, 8)
	zero_from := compatcore.inatomic_from_user(unsafe { nil }, voidptr(usize(-1)), 0)
	zero_to := compatcore.inatomic_to_user(voidptr(usize(-1)), unsafe { nil }, 0)
	irq_restore(flags)
	return from == 8 && to == 8 && zero_from == 0 && zero_to == 0
}
