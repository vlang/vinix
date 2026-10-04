// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module sched

// TLB shootdown: dropping a translation from the other CPUs that may hold it,
// which x86 can only do by asking each of them. See memory/virtual_amd64.v.
//
// The CPU asking holds its page map's lock with interrupts off and waits for
// every answer. A CPU that cannot take the IPI because its own interrupts are
// off is spinning -- for a lock, or for its turn to ask -- and answers from
// that loop instead; otherwise it would wait for the lock the asking CPU
// holds, while the asking CPU waited for it.

import katomic
import klock
import memory
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt

const max_tlb_cpus = 256

// How long a shootdown waits for a CPU to answer before sending it the IPI
// again, in spins: some milliseconds.
const tlb_resend_spins = 1000000

__global (
	tlb_vector u8
	// One shootdown at a time: what it drops, and which CPUs are yet to.
	tlb_lock               klock.Lock
	tlb_request_cr3        u64
	tlb_request_virt       u64
	tlb_request_everywhere bool
	tlb_pending            [max_tlb_cpus]u32
	// Nonzero while a shootdown is waiting, so a spinning CPU checks nothing
	// more the rest of the time.
	tlb_in_flight u32
)

fn initialise_tlb_shootdown() {
	tlb_vector = idt.allocate_vector()
	interrupt_table[tlb_vector] = voidptr(tlb_isr)
	klock.register_spin_hook(voidptr(answer_tlb_shootdown))
	memory.register_tlb_shootdown(tlb_shootdown)
}

fn tlb_isr(_ u32, _ &cpulocal.GPRState) {
	answer_tlb_shootdown()
	apic.lapic_eoi()
}

// Drop what the shootdown in flight asks of this CPU, if it asks anything. A
// CPU with interrupts on leaves it to the IPI.
fn answer_tlb_shootdown() {
	if katomic.load(&tlb_in_flight) == 0 || cpu.interrupt_state() {
		return
	}
	me := cpulocal.current().cpu_number
	if me >= max_tlb_cpus || katomic.load(&tlb_pending[me]) == 0 {
		return
	}
	if tlb_request_everywhere || cpu.read_cr3() == tlb_request_cr3 {
		cpu.invlpg(tlb_request_virt)
	}
	katomic.store(mut &tlb_pending[me], u32(0))
}

// Drop `virt` of the page map at `cr3` from every other CPU that may hold it,
// and return once each has; `everywhere` for a kernel mapping, which every
// page map shares. The caller has changed the entry and fenced.
fn tlb_shootdown(cr3 u64, virt u64, everywhere bool) {
	if cpu_locals.len <= 1 {
		return
	}
	ints := cpu.interrupt_toggle(false)
	defer {
		cpu.interrupt_toggle(ints)
	}
	me := cpulocal.current().cpu_number
	if !everywhere && !tlb_needed_elsewhere(me, cr3) {
		return
	}

	for !tlb_lock.test_and_acquire() {
		answer_tlb_shootdown()
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}
	tlb_request_cr3 = cr3
	tlb_request_virt = virt
	tlb_request_everywhere = everywhere
	katomic.inc(mut &tlb_in_flight)

	count := if cpu_locals.len < max_tlb_cpus { cpu_locals.len } else { max_tlb_cpus }
	for i := 0; i < count; i++ {
		if u64(i) == me || katomic.load(&cpu_locals[i].online) == 0 {
			continue
		}
		if !everywhere && !memory.pagemap_may_be_active_on(u64(i), cr3) {
			continue
		}
		katomic.store(mut &tlb_pending[i], u32(1))
		apic.lapic_send_ipi(cpu_locals[i].lapic_id, tlb_vector)
	}
	for i := 0; i < count; i++ {
		// An IPI can go astray; ask again rather than wait for good.
		mut spins := 0
		for katomic.load(&tlb_pending[i]) != 0 {
			spins++
			if spins % tlb_resend_spins == 0 {
				apic.lapic_send_ipi(cpu_locals[i].lapic_id, tlb_vector)
			}
			asm volatile amd64 {
				pause
				; ; ; memory
			}
		}
	}

	katomic.dec(mut &tlb_in_flight)
	tlb_lock.release()
}

fn tlb_needed_elsewhere(me u64, cr3 u64) bool {
	count := if cpu_locals.len < max_tlb_cpus { cpu_locals.len } else { max_tlb_cpus }
	for i := 0; i < count; i++ {
		if u64(i) != me && memory.pagemap_may_be_active_on(u64(i), cr3) {
			return true
		}
	}
	return false
}
