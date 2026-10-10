// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The interrupt controllers across a loss of power, and the two interrupts a
// processor is started with.
//
// A suspend to RAM leaves memory alone and nothing else. A local APIC comes
// back disabled or in xAPIC mode, with every local vector masked; an I/O APIC
// comes back with every pin masked and unrouted; and the 8259s the boot
// loader had masked for the kernel come back as firmware leaves them. What
// was programmed is read out before the sleep and written back after it: the
// local APIC of each processor by that processor, the rest once by the one
// that slept.
@[has_globals]
module apic

import x86.cpu
import x86.kio
import x86.msr

const msr_apic_base = u32(0x1b)
const apic_base_enable = u64(1) << 11
const apic_base_x2apic = u64(1) << 10

const lapic_reg_id = 0x020
const lapic_reg_version = 0x030
const lapic_reg_tpr = 0x080
const lapic_reg_ldr = 0x0d0
const lapic_reg_dfr = 0x0e0
const lapic_reg_esr = 0x280
const lapic_reg_lvt_thermal = 0x330
const lapic_reg_lvt_perf = 0x340
const lapic_reg_lvt_lint0 = 0x350
const lapic_reg_lvt_lint1 = 0x360
const lapic_reg_lvt_error = 0x370

const lvt_masked = u32(1) << 16

// ICR delivery modes.
const icr_init = u32(0x500)
const icr_startup = u32(0x600)
// Level, asserted: what an INIT is sent as.
const icr_assert = u32(0xc000)
const icr_deassert = u32(0x8000)

const pic_master_data = u16(0x21)
const pic_slave_data = u16(0xa1)

// What one processor's local APIC was set to.
pub struct LocalState {
pub mut:
	valid   bool
	base    u64
	tpr     u32
	ldr     u32
	dfr     u32
	svr     u32
	timer   u32
	thermal u32
	perf    u32
	lint0   u32
	lint1   u32
	error   u32
	divide  u32
	// How many local vector entries the APIC has, less one.
	max_lvt u32
}

__global (
	// Every I/O APIC's redirection table, one after another, and how many
	// entries that is. Made the first time the tables are saved, and kept.
	apic_saved_routes      &u64
	apic_saved_route_count u64
	apic_routes_saved      bool
	apic_saved_pic_master  u8
	apic_saved_pic_slave   u8
)

// Read out this processor's local APIC. Interrupts off.
pub fn lapic_save() LocalState {
	mut state := LocalState{
		valid: true
		base:  msr.rdmsr(msr_apic_base)
	}
	state.max_lvt = (u32(lapic_read(lapic_reg_version)) >> 16) & 0xff
	state.tpr = u32(lapic_read(lapic_reg_tpr))
	if !x2apic_mode {
		state.ldr = u32(lapic_read(lapic_reg_ldr))
		state.dfr = u32(lapic_read(lapic_reg_dfr))
	}
	state.svr = u32(lapic_read(lapic_reg_spurious))
	state.timer = u32(lapic_read(lapic_reg_timer))
	if state.max_lvt >= 5 {
		state.thermal = u32(lapic_read(lapic_reg_lvt_thermal))
	}
	if state.max_lvt >= 4 {
		state.perf = u32(lapic_read(lapic_reg_lvt_perf))
	}
	state.lint0 = u32(lapic_read(lapic_reg_lvt_lint0))
	state.lint1 = u32(lapic_read(lapic_reg_lvt_lint1))
	state.error = u32(lapic_read(lapic_reg_lvt_error))
	state.divide = u32(lapic_read(lapic_reg_timer_div))
	return state
}

// Put this processor's APIC into the mode the kernel runs it in: on, and
// x2APIC if that is what the boot loader chose. Firmware resumes a machine in
// whichever mode it likes. The steps the processor allows are off to xAPIC,
// xAPIC to x2APIC, and either to off.
pub fn lapic_restore_mode(saved_base u64) {
	mode := apic_base_enable | apic_base_x2apic
	now := msr.rdmsr(msr_apic_base)
	wanted := (now & ~mode) | (saved_base & mode)
	if now == wanted {
		return
	}
	mut current := now
	if current & apic_base_x2apic != 0 && wanted & apic_base_x2apic == 0 {
		current &= ~mode
		msr.wrmsr(msr_apic_base, current)
	}
	if wanted & apic_base_x2apic != 0 && current & apic_base_enable == 0 {
		current |= apic_base_enable
		msr.wrmsr(msr_apic_base, current)
	}
	if current != wanted {
		msr.wrmsr(msr_apic_base, wanted)
	}
}

// Write back what lapic_save() read, on the processor it was read on. The
// timer is left stopped: whoever runs the processor next arms it.
pub fn lapic_restore(state &LocalState) {
	if !state.valid {
		return
	}
	lapic_restore_mode(state.base)
	// Nothing is delivered through a half-written table.
	lapic_write(lapic_reg_lvt_error, state.error | lvt_masked)
	lapic_write(lapic_reg_tpr, state.tpr)
	if !x2apic_mode {
		lapic_write(lapic_reg_dfr, state.dfr)
		lapic_write(lapic_reg_ldr, state.ldr)
	}
	lapic_write(lapic_reg_spurious, state.svr)
	lapic_write(lapic_reg_lvt_lint0, state.lint0)
	lapic_write(lapic_reg_lvt_lint1, state.lint1)
	if state.max_lvt >= 5 {
		lapic_write(lapic_reg_lvt_thermal, state.thermal)
	}
	if state.max_lvt >= 4 {
		lapic_write(lapic_reg_lvt_perf, state.perf)
	}
	lapic_write(lapic_reg_timer_initcnt, 0)
	lapic_write(lapic_reg_timer, state.timer | lvt_masked)
	lapic_write(lapic_reg_timer_div, state.divide)
	// The error status register is cleared by writing it.
	lapic_write(lapic_reg_esr, 0)
	lapic_write(lapic_reg_lvt_error, state.error)
}

// The APIC id this processor answers to.
pub fn lapic_id() u32 {
	id := u32(lapic_read(lapic_reg_id))
	return if x2apic_mode { id } else { id >> 24 }
}

fn lapic_command(lapic_id u32, command u32) {
	if x2apic_mode {
		x2apic_write(lapic_reg_icr0, (u64(lapic_id) << 32) | command)
		return
	}
	ints := cpu.interrupt_toggle(false)
	for xapic_read(lapic_reg_icr0) & icr_delivery_pending != 0 {
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}
	xapic_write(lapic_reg_icr1, u32(lapic_id) << 24)
	xapic_write(lapic_reg_icr0, command)
	cpu.interrupt_toggle(ints)
}

// Reset the processor with this APIC id: it stops whatever it was doing and
// waits for a startup IPI. The caller lets 10 ms pass before sending one.
pub fn lapic_send_init(lapic_id u32) {
	lapic_command(lapic_id, icr_init | icr_assert)
	if !x2apic_mode {
		// Older APICs want the level taken away again.
		lapic_command(lapic_id, icr_init | icr_deassert)
	}
}

// Start a processor that is waiting for it, in real mode, at the first byte
// of physical page `page`, which is below 1 MiB.
pub fn lapic_send_startup(lapic_id u32, page u8) {
	lapic_command(lapic_id, icr_startup | u32(page))
}

// How many redirection entries the machine's I/O APICs have between them.
fn io_apic_route_total() u64 {
	io_apic_lock.acquire()
	defer {
		io_apic_lock.release()
	}
	mut total := u64(0)
	for i := 0; i < madt_io_apics.len; i++ {
		total += u64(io_apic_gsi_count(i)) + 1
	}
	return total
}

// Read out every redirection entry of every I/O APIC, and the masks of the
// two 8259s. False when there is no memory to keep them in.
pub fn io_apic_save() bool {
	total := io_apic_route_total()
	if apic_saved_routes == unsafe { nil } || apic_saved_route_count != total {
		// Once, unless the machine's I/O APICs change, which they do not.
		if apic_saved_routes != unsafe { nil } {
			unsafe { free(apic_saved_routes) }
		}
		apic_routes_saved = false
		apic_saved_routes = unsafe { &u64(malloc(total * 8 + 8)) }
		if apic_saved_routes == unsafe { nil } {
			apic_saved_route_count = 0
			return false
		}
		apic_saved_route_count = total
	}
	io_apic_lock.acquire()
	mut slot := u64(0)
	for i := 0; i < madt_io_apics.len; i++ {
		pins := io_apic_gsi_count(i) + 1
		for pin := u32(0); pin < pins && slot < total; pin++ {
			low := u64(io_apic_read(i, 16 + pin * 2))
			high := u64(io_apic_read(i, 17 + pin * 2))
			unsafe {
				apic_saved_routes[slot] = (high << 32) | low
			}
			slot++
		}
	}
	io_apic_lock.release()
	apic_saved_pic_master = kio.port_in[u8](pic_master_data)
	apic_saved_pic_slave = kio.port_in[u8](pic_slave_data)
	apic_routes_saved = true
	return true
}

// Write them back. The 8259s first: firmware resumes with some of their
// lines open, and an interrupt from one would arrive on a vector the kernel
// takes for a processor exception.
pub fn io_apic_restore() {
	if !apic_routes_saved {
		return
	}
	kio.port_out[u8](pic_master_data, apic_saved_pic_master)
	kio.port_out[u8](pic_slave_data, apic_saved_pic_slave)
	io_apic_lock.acquire()
	mut slot := u64(0)
	for i := 0; i < madt_io_apics.len; i++ {
		pins := io_apic_gsi_count(i) + 1
		for pin := u32(0); pin < pins && slot < apic_saved_route_count; pin++ {
			entry := unsafe { apic_saved_routes[slot] }
			slot++
			// Masked until both halves are the entry's own, and the
			// destination before the half that unmasks.
			io_apic_write(i, 16 + pin * 2, u32(entry) | lvt_masked)
			io_apic_write(i, 17 + pin * 2, u32(entry >> 32))
			io_apic_write(i, 16 + pin * 2, u32(entry))
		}
	}
	io_apic_lock.release()
}
