// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import katomic
import lib
import proc
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt

#include "linuxkpi_irq_work_v_primitives.h"

fn C.vkiw_bootstrap(u32) i32
fn C.vkiw_ready() bool
fn C.vkiw_drain(u32)
fn C.vkiw_tick_all()

__global (
	irqwork_vector u32
	irqwork_vector_ready u32
	irqwork_pit_ticks u64
	irqwork_ipi_sends [256]u64
)

fn irqwork_interrupt(vector u32, _frame &cpulocal.GPRState) {
	apic.lapic_eoi()
	if vector != irqwork_vector || cpu.interrupt_state()
		|| cpulocal.current().maskable_irq_depth == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid IRQ work interrupt context')
	}
	if C.vkiw_ready() { C.vkiw_drain(u32(cpulocal.current().cpu_number)) }
}

@[export: 'vinix_linuxkpi_irqwork_send_ipi']
fn irqwork_send_ipi(target u32) {
	if katomic.load(&irqwork_vector_ready) == 0 || !C.vkiw_ready()
		|| target >= u32(cpu_locals.len) || katomic.load(&cpu_locals[target].online) == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid IRQ work IPI target')
	}
	katomic.inc(mut &irqwork_ipi_sends[target])
	// Publish intrusive records before the native x2APIC weakly ordered WRMSR.
	asm volatile amd64 {
		mfence
		lfence
		; ; ; memory
	}
	apic.lapic_send_ipi(cpu_locals[target].lapic_id, u8(irqwork_vector))
}

// Called only by the actual PIT maskable handler, before its clock promotion.
// Generic time hooks also run from ordinary syscalls and must not call here.
@[export: 'vinix_linuxkpi_irqwork_pit_tick']
fn irqwork_pit_tick() {
	// Do not enter any compatibility export from cold PIT delivery. The boot
	// owner installs this gate after ordinary RCU has warmed module exports.
	if katomic.load(&irqwork_vector_ready) == 0 || !C.vkiw_ready() { return }
	if cpu.interrupt_state() || cpulocal.current().maskable_irq_depth == 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ work tick outside real PIT context')
	}
	katomic.inc(mut &irqwork_pit_ticks)
	C.vkiw_tick_all()
}

@[export: 'vinix_linuxkpi_irqwork_tick_count']
fn irqwork_tick_count() u64 { return katomic.load(&irqwork_pit_ticks) }
@[export: 'vinix_linuxkpi_irqwork_ipi_count']
fn irqwork_ipi_count(target u32) u64 {
	if target >= u32(cpu_locals.len) { return 0 }
	return katomic.load(&irqwork_ipi_sends[target])
}

fn initialise_irq_work() {
	if !smp_boot_context() || !C.vks_smp_ready() || !C.vkr_rcu_ready()
		|| katomic.load(&irqwork_vector_ready) != 0 {
		lib.kpanic(unsafe { nil }, c'linuxkpi: invalid IRQ work boot prerequisites')
	}
	vector := idt.allocate_vector()
	idt.set_ist(u16(vector), 0)
	interrupt_table[vector] = voidptr(irqwork_interrupt)
	irqwork_vector = u32(vector)
	katomic.store(mut &irqwork_vector_ready, u32(1))
	count := u32(cpu_locals.len)
	test_alloc_oom(0)
	ints := cpu.interrupt_toggle(false)
	irq_off := C.vkiw_bootstrap(count)
	valid_irq := !cpu.interrupt_state() && proc.current_thread().linuxkpi_alloc_fail_after == 0
	cpu.interrupt_toggle(ints)
	preempt_disable()
	preempt_disable()
	pinned := C.vkiw_bootstrap(count)
	valid_pins := cpu.interrupt_state() && native_preempt_count() == 2
		&& proc.current_thread().linuxkpi_alloc_fail_after == 0
	release_preemption(false)
	release_preemption(false)
	test_alloc_oom(-1)
	if irq_off != -1 || pinned != -1 || !valid_irq || !valid_pins || C.vkiw_ready()
		|| C.vkiw_bootstrap(count) != 0 || !C.vkiw_ready() {
		lib.kpanic(unsafe { nil }, c'linuxkpi: IRQ work initialization failed')
	}
}
