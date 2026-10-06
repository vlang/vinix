// SPDX-License-Identifier: GPL-2.0-or-later
// Observe native IRQ macro argument sequencing independently of its implementation.
@[translated]
module spinfixture

#include "linuxkpi_header_primitive_v_contract.h"

@[typedef]
struct C.spinlock_t { locked u32 }
fn C.spin_lock_init(&C.spinlock_t)
fn C.spin_lock_irqsave(&C.spinlock_t, usize)
fn C.spin_unlock_irqrestore(&C.spinlock_t, usize)
fn C.spin_trylock_irqsave(&C.spinlock_t, usize) bool
@[c: 'spin_lock_irqsave']
fn C.vhst_lock_u32(&C.spinlock_t, u32)
@[c: 'spin_unlock_irqrestore']
fn C.vhst_unlock_u32(&C.spinlock_t, u32)
@[c: 'spin_lock_irqsave']
fn C.vhst_lock_i16(&C.spinlock_t, i16)
@[c: 'spin_unlock_irqrestore']
fn C.vhst_unlock_i16(&C.spinlock_t, i16)
fn C.vinix_spin_fixture_guard() &C.spinlock_t
fn C.vinix_spin_fixture_flags() &usize
fn C.printf(&char, ...) i32

@[cinit]
__global (
	vhst_irq usize = 0x202
	vhst_saved usize
	vhst_preempt u32
	vhst_guard C.spinlock_t
	vhst_guard_calls u32
	vhst_flag_calls u32
	vhst_failures i32
	vhst_unlock bool
)

@[export: 'vinix_linuxkpi_irq_save']
pub fn irq_save() usize {
	unsafe { old := vhst_irq; vhst_irq &= ~(usize(1)<<9); return old }
}

@[export: 'vinix_linuxkpi_irq_restore']
pub fn irq_restore(flags usize) { unsafe { vhst_irq = flags } }

@[export: 'vinix_linuxkpi_irq_flags']
pub fn irq_flags() usize { return unsafe { vhst_irq } }

@[export: 'vinix_linuxkpi_preempt_disable']
pub fn preempt_disable() { unsafe { vhst_preempt++ } }

@[export: 'vinix_linuxkpi_preempt_enable']
pub fn preempt_enable() { unsafe { vhst_preempt-- } }

@[export: 'vinix_linuxkpi_spin_wait']
pub fn spin_wait() { unsafe { vhst_failures++ } }

@[export: 'vinix_spin_fixture_guard']
pub fn guard_argument() &C.spinlock_t {
	unsafe {
		vhst_guard_calls++
		if vhst_irq != 2 || vhst_saved != 0x202 { vhst_failures++ }
		return &vhst_guard
	}
}

@[export: 'vinix_spin_fixture_flags']
pub fn flag_argument() &usize {
	unsafe {
		vhst_flag_calls++
		if vhst_unlock && vhst_preempt != 0 { vhst_failures++ }
		return &vhst_saved
	}
}

@[export: 'main']
pub fn main_entry() i32 {
	unsafe {
		vhst_irq = 0x202; vhst_saved = 0x55; vhst_preempt = 0
		C.spin_lock_init(&vhst_guard)
		C.spin_lock_irqsave(C.vinix_spin_fixture_guard(), *C.vinix_spin_fixture_flags())
		if vhst_guard.locked != 1 || vhst_preempt != 1 || vhst_saved != 0x202 || vhst_flag_calls != 1 || vhst_guard_calls != 1 { vhst_failures++ }
		vhst_unlock = true
		C.spin_unlock_irqrestore(&vhst_guard, *C.vinix_spin_fixture_flags())
		if vhst_guard.locked != 0 || vhst_preempt != 0 || vhst_irq != 0x202 || vhst_flag_calls != 2 { vhst_failures++ }
		vhst_unlock = false; vhst_flag_calls = 0; vhst_guard_calls = 0; vhst_saved = 0x55
		if !C.spin_trylock_irqsave(C.vinix_spin_fixture_guard(), *C.vinix_spin_fixture_flags()) || vhst_preempt != 1 || vhst_irq != 2 || vhst_flag_calls != 1 || vhst_guard_calls != 1 { vhst_failures++ }
		C.spin_unlock_irqrestore(&vhst_guard, vhst_saved)
		// A failed try restores flags, and only that branch rereads the lvalue.
		vhst_guard.locked = 1; vhst_flag_calls = 0; vhst_guard_calls = 0; vhst_saved = 0x55
		if C.spin_trylock_irqsave(C.vinix_spin_fixture_guard(), *C.vinix_spin_fixture_flags()) || vhst_preempt != 0 || vhst_irq != 0x202 || vhst_flag_calls != 2 || vhst_guard_calls != 1 { vhst_failures++ }
		// Native assignment preserves the original conversion for every lvalue type.
		C.spin_lock_init(&vhst_guard)
		mut narrow32 := u32(0)
		C.vhst_lock_u32(&vhst_guard, narrow32)
		if narrow32 != 0x202 || vhst_preempt != 1 || vhst_irq != 2 { vhst_failures++ }
		C.vhst_unlock_u32(&vhst_guard, narrow32)
		if vhst_preempt != 0 || vhst_irq != 0x202 { vhst_failures++ }
		mut narrow16 := i16(0)
		C.vhst_lock_i16(&vhst_guard, narrow16)
		if narrow16 != 0x202 || vhst_preempt != 1 || vhst_irq != 2 { vhst_failures++ }
		C.vhst_unlock_i16(&vhst_guard, narrow16)
		if vhst_preempt != 0 || vhst_irq != 0x202 { vhst_failures++ }
		C.printf(c'LinuxKPI IRQ macro native expression sequencing errors=%d\n', vhst_failures)
		return if vhst_failures == 0 { i32(0) } else { i32(1) }
	}
}
