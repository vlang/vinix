// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module syspower

import devcore
import katomic
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt
import x86.msr

const msr_efer = u32(0xc0000080)
const msr_spec_ctrl = u32(0x48)

const security_max_cpus = 256
// How long a processor is given to answer, and when it is asked again: one
// that has its interrupts off for a while answers late, and an interrupt can
// go astray.
const security_answer_ns = 500 * devcore.millisecond
const security_resend_ns = 20 * devcore.millisecond

// The registers that hold a CPU's protections: write protection of kernel
// pages (CR0.WP), supervisor execution and access prevention and user-mode
// instruction prevention (CR4.SMEP, SMAP, UMIP), no-execute (EFER.NXE), and
// the speculation controls the mitigation policy set (IA32_SPEC_CTRL, where
// the CPU has one). A CPU that comes back from a sleep without one of them
// runs the same kernel with a hole in it and gives no sign, so they are
// recorded before the sleep and compared after it.
//
// On every processor, each for itself: these are registers of the processor
// that reads them. The one that carries out the sleep reads its own and asks
// the others with an interrupt; after a suspend to RAM the others have been
// started from nothing, and this is what says they were set up as they had
// been.
struct CpuProtections {
mut:
	cr0       u64
	cr4       u64
	efer      u64
	spec_ctrl u64
}

// What was recorded: how many processors answered. The registers themselves
// are kept by processor number below; a sleep is one at a time.
pub struct SecurityState {
pub:
	cpus u64
}

__global (
	syspower_security_vector u8
	// What each processor had before the sleep, and has now. One sleep is in
	// progress at a time, and with it one request.
	syspower_security_before [security_max_cpus]CpuProtections
	syspower_security_now    [security_max_cpus]CpuProtections
	// The number of the request in flight, and the last one each processor
	// answered.
	syspower_security_request u64
	syspower_security_answers [security_max_cpus]u64
	// Nonzero when the request is to write the recorded registers back first.
	syspower_security_restoring u32
	// Processors that were online and did not answer a request in time.
	syspower_security_silent u64
)

fn protections_here() CpuProtections {
	return CpuProtections{
		cr0:       cpu.read_cr0()
		cr4:       cpu.read_cr4()
		efer:      msr.rdmsr(msr_efer)
		spec_ctrl: msr.read_safe(msr_spec_ctrl) or { u64(0) }
	}
}

fn (a CpuProtections) differs(b CpuProtections) bool {
	return a.cr0 != b.cr0 || a.cr4 != b.cr4 || a.efer != b.efer || a.spec_ctrl != b.spec_ctrl
}

// This processor's part of a request. Interrupts off.
fn security_answer() {
	number := cpulocal.current().cpu_number
	if number >= security_max_cpus {
		return
	}
	request := katomic.load(&syspower_security_request)
	if katomic.load(&syspower_security_answers[number]) == request {
		return
	}
	before := syspower_security_before[number]
	// A processor that did not answer before the sleep has no record to go
	// back to, only zeroes, which are not to be written anywhere.
	if katomic.load(&syspower_security_restoring) != 0 && (before.cr0 != 0 || before.cr4 != 0) {
		now := protections_here()
		if now.efer != before.efer {
			msr.wrmsr(msr_efer, before.efer)
		}
		if now.cr4 != before.cr4 {
			cpu.write_cr4(before.cr4)
		}
		if now.cr0 != before.cr0 {
			cpu.write_cr0(before.cr0)
		}
		if now.spec_ctrl != before.spec_ctrl {
			msr.write_safe(msr_spec_ctrl, before.spec_ctrl)
		}
	}
	syspower_security_now[number] = protections_here()
	katomic.store(mut &syspower_security_answers[number], request)
}

fn security_interrupt(_ u32, _ &cpulocal.GPRState) {
	security_answer()
	apic.lapic_eoi()
}

fn security_all_answered(_ voidptr) bool {
	request := katomic.load(&syspower_security_request)
	for entry in cpu_locals {
		number := entry.cpu_number
		if number < security_max_cpus && katomic.load(&entry.online) != 0
			&& katomic.load(&syspower_security_answers[number]) != request {
			return false
		}
	}
	return true
}

fn security_ask_others() {
	request := katomic.load(&syspower_security_request)
	for entry in cpu_locals {
		number := entry.cpu_number
		if number < security_max_cpus && katomic.load(&entry.online) != 0
			&& katomic.load(&syspower_security_answers[number]) != request {
			apic.lapic_send_ipi(entry.lapic_id, syspower_security_vector)
		}
	}
}

// Have every online processor read its registers into
// syspower_security_now, after writing back the recorded ones if `restore`.
// Returns how many answered. Called from the thread carrying out the sleep.
fn security_collect(restore bool) u64 {
	if syspower_security_vector == 0 {
		vector := idt.allocate_vector()
		interrupt_table[vector] = voidptr(security_interrupt)
		syspower_security_vector = vector
	}
	katomic.store(mut &syspower_security_restoring, if restore { u32(1) } else { u32(0) })
	katomic.inc(mut &syspower_security_request)
	// This processor by itself, the others by interrupt. Should the thread
	// move in between, the one it moved to is simply asked as well.
	ints := cpu.interrupt_toggle(false)
	security_answer()
	cpu.interrupt_toggle(ints)
	security_ask_others()
	if !devcore.spin_until(security_all_answered, unsafe { nil }, security_resend_ns) {
		security_ask_others()
		devcore.sleep_until(security_all_answered, unsafe { nil }, security_answer_ns, 1)
	}
	request := katomic.load(&syspower_security_request)
	mut answered := u64(0)
	for entry in cpu_locals {
		number := entry.cpu_number
		if number >= security_max_cpus || katomic.load(&entry.online) == 0 {
			continue
		}
		if katomic.load(&syspower_security_answers[number]) == request {
			answered++
		} else {
			syspower_security_silent++
			C.kprintf(c'syspower: CPU %llu did not report its protection registers\n', number)
		}
	}
	return answered
}

fn platform_security_state() SecurityState {
	answered := security_collect(false)
	request := katomic.load(&syspower_security_request)
	for entry in cpu_locals {
		number := entry.cpu_number
		if number < security_max_cpus && katomic.load(&syspower_security_answers[number]) == request {
			syspower_security_before[number] = syspower_security_now[number]
		} else if number < security_max_cpus {
			// Nothing to compare with afterwards.
			syspower_security_before[number] = CpuProtections{}
		}
	}
	return SecurityState{
		cpus: answered
	}
}

fn platform_security_restore(_ SecurityState) {
	security_collect(true)
}

// Whether any processor's registers differ from what it had before the
// sleep. A processor that is not there to ask -- it did not come back -- has
// nothing that can differ, and is reported where it failed to start.
fn security_changed(_ SecurityState) bool {
	security_collect(false)
	request := katomic.load(&syspower_security_request)
	mut changed := false
	for entry in cpu_locals {
		number := entry.cpu_number
		if number >= security_max_cpus || katomic.load(&entry.online) == 0
			|| katomic.load(&syspower_security_answers[number]) != request {
			continue
		}
		before := syspower_security_before[number]
		now := syspower_security_now[number]
		if before.cr0 == 0 && before.cr4 == 0 {
			// It did not answer before the sleep.
			continue
		}
		if now.differs(before) {
			changed = true
			C.kprintf(c'syspower: CPU %llu protections: CR0 %llx -> %llx, CR4 %llx -> %llx, EFER %llx -> %llx, SPEC_CTRL %llx -> %llx\n',
				number, before.cr0, now.cr0, before.cr4, now.cr4, before.efer, now.efer, before.spec_ctrl,
				now.spec_ctrl)
		}
	}
	return changed
}

// How many processors the last check covered.
fn platform_security_cpus(state SecurityState) u64 {
	return state.cpus
}
