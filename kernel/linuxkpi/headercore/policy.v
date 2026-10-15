// SPDX-License-Identifier: GPL-2.0-or-later
// Runtime pointer and scheduler policy; compiler primitives and constant native
// expressions are generated separately from structured ABI metadata.
@[translated]
module headercore

#include "linuxkpi_header_primitive_v_contract.h"
fn C.vinix_linuxkpi_preempt_count() u32
fn C.irqs_disabled() bool
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_bug(C.vkh_const_char_p, i32)

@[export: 'vinix_zero_or_null_ptr']
pub fn zero_or_null(pointer usize) bool { return pointer <= 16 }

@[export: 'vinix_preemptible']
pub fn preemptible() bool {
	// Observe IF, pins and actual maskable IRQ depth together. An IRQ-enabled
	// nested handler still borrows its interrupted task rather than task context.
	return C.vinix_linuxkpi_may_sleep()
}

// A false condition carries no sleep annotation. The true path uses the same
// native task-context invariant as might_sleep(), without changing scheduling.
@[export: 'vinix_might_sleep_if_native']
pub fn might_sleep_if(condition bool, file C.vkh_const_char_p, line i32) {
	if !condition { return }
	if !C.vinix_linuxkpi_may_sleep() { C.vinix_linuxkpi_bug(file, line) }
}
