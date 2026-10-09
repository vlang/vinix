// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import katomic
import lib
import memory
import proc
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt

#include "linuxkpi_smp_call_v_primitives.h"

fn C.vks_smp_bootstrap(u32) i32
fn C.vks_smp_ready() bool
fn C.vks_smp_drain(u32)

__global (
	smp_call_vector       u32
	smp_call_vector_ready u32
)

@[export: 'vinix_linuxkpi_smp_task_present']
fn smp_task_present() bool {
	ints := cpu.interrupt_toggle(false)
	present := proc.current_thread() != unsafe { nil }
	cpu.interrupt_toggle(ints)
	return present
}

// Constructor allocation requires a real ordinary running task. Checking
// current_thread directly avoids materializing a Linux task view in an IRQ or
// before the native scheduler has installed its current thread.
@[export: 'vinix_linuxkpi_smp_boot_context']
fn smp_boot_context() bool {
	ints := cpu.interrupt_toggle(false)
	local := cpulocal.current()
	valid := ints && local.maskable_irq_depth == 0
		&& preempt_depth[local.cpu_number] == 0 && proc.current_thread() != unsafe { nil }
	cpu.interrupt_toggle(ints)
	return valid
}

fn smp_call_interrupt(vector u32, _frame &cpulocal.GPRState) {
	// EOI precedes callbacks, which may submit another call to this CPU. The
	// existing maskable THUNK owns entry/exit accounting and the actual IRET.
	apic.lapic_eoi()
	if vector != smp_call_vector || cpu.interrupt_state()
		|| cpulocal.current().maskable_irq_depth == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid SMP call interrupt context')
	}
	// The vector is permanent and installed before constructor failure tests.
	// Failed construction must not make any uninitialized queue consumable.
	if !C.vks_smp_ready() { return }
	C.vks_smp_drain(u32(cpulocal.current().cpu_number))
}

@[export: 'vinix_linuxkpi_smp_send_ipi']
fn smp_send_ipi(target u32) {
	if katomic.load(&smp_call_vector_ready) == 0 || !C.vks_smp_ready()
		|| target >= u32(cpu_locals.len) || katomic.load(&cpu_locals[target].online) == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid SMP call IPI target')
	}
	// Logical IDs are compact; firmware LAPIC IDs are not. Keep the full u32
	// identity for the existing x2APIC transport. xAPIC serializes its two ICR
	// writes and restores the producer's original interrupt state itself.
	// x2APIC's ICR WRMSR is weakly ordered. Match the original Linux
	// weak_wrmsr_fence requirement before ringing the target doorbell.
	asm volatile amd64 {
		mfence
		lfence
		; ; ; memory
	}
	apic.lapic_send_ipi(cpu_locals[target].lapic_id, u8(smp_call_vector))
}

fn smp_call_install_vector() {
	if katomic.load(&smp_call_vector_ready) != 0 { return }
	if !smp_boot_context() {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unsafe SMP call vector installation')
	}
	vector := idt.allocate_vector()
	// Every ordinary vector already uses the real maskable interrupt THUNK.
	// IST0 keeps the interrupted stack; no synthetic polling dispatch exists.
	idt.set_ist(u16(vector), 0)
	interrupt_table[vector] = voidptr(smp_call_interrupt)
	smp_call_vector = u32(vector)
	katomic.store(mut &smp_call_vector_ready, u32(1))
}

fn initialise_smp_calls() {
	if !smp_boot_context() || !C.vkm_cpu_masks_ready()
		|| C.vkm_cpu_ids() != u32(cpu_locals.len) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid boot SMP call prerequisites')
	}
	for index, local in cpu_locals {
		if local.cpu_number != u64(index) || katomic.load(&local.online) == 0
			|| (!x2apic_mode && local.lapic_id > 255) {
			lib.kpanic(unsafe { nil }, c'linuxkpi: unsupported SMP call CPU topology')
		}
	}
	smp_call_install_vector()
	count := u32(cpu_locals.len)
	// Cold invalid contexts must reject before touching the fallible allocator.
	// Keep the one-shot failure armed to demonstrate that ordering, and restore
	// every caller state before the real reclaim-capable constructor executes.
	test_alloc_oom(0)
	ints := cpu.interrupt_toggle(false)
	irq_off_result := C.vks_smp_bootstrap(count)
	irq_off_valid := !cpu.interrupt_state() && proc.current_thread().linuxkpi_alloc_fail_after == 0
	cpu.interrupt_toggle(ints)
	preempt_disable()
	preempt_disable()
	pinned_result := C.vks_smp_bootstrap(count)
	pinned_valid := cpu.interrupt_state() && native_preempt_count() == 2
		&& proc.current_thread().linuxkpi_alloc_fail_after == 0
	release_preemption(false)
	release_preemption(false)
	test_alloc_oom(-1)
	if irq_off_result != -1 || pinned_result != -1 || !irq_off_valid || !pinned_valid {
		lib.kpanic(unsafe { nil }, c'linuxkpi: unsafe SMP constructor context was accepted')
	}
	// The permanent vector is installed once, before these baselines. Native
	// checked allocation failures must unwind both raw owners without publishing
	// readiness, consuming another vector or leaving an aligned interior owner.
	for fail_after in 0 .. 2 {
		before := memory.free_bytes()
		test_alloc_oom(i32(fail_after))
		result := C.vks_smp_bootstrap(count)
		test_alloc_oom(-1)
		if result != -12 || C.vks_smp_ready() || memory.free_bytes() != before {
			lib.kpanic(unsafe { nil }, c'linuxkpi: SMP call constructor rollback failed')
		}
	}
	if C.vks_smp_bootstrap(count) != 0 || !C.vks_smp_ready() {
		lib.kpanic(unsafe { nil }, c'linuxkpi: SMP call initialization failed')
	}
}
