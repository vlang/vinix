// apic.v: APIC driver.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module apic

import x86.kio
import x86.msr
import x86.cpu.local as cpulocal
import time

const (
	lapic_reg_icr0          = 0x300
	lapic_reg_icr1          = 0x310
	lapic_reg_spurious      = 0x0f0
	lapic_reg_eoi           = 0x0b0
	lapic_reg_timer         = 0x320
	lapic_reg_timer_initcnt = 0x380
	lapic_reg_timer_curcnt  = 0x390
	lapic_reg_timer_div     = 0x3e0
)

__global (
	lapic_base = u64(0)
	x2apic_mode = bool(false)
)

fn xapic_read(reg u32) u32 {
	if lapic_base == u64(0) {
		lapic_base = u64(msr.rdmsr(0x1b) & 0xfffff000) + higher_half
	}
	return kio.mmin(&u32(lapic_base + reg))
}

fn x2apic_read(reg u32) u64 {
	return msr.rdmsr(0x800 + (reg >> 4))
}

fn xapic_write(reg u32, val u32) {
	if lapic_base == u64(0) {
		lapic_base = u64(msr.rdmsr(0x1b) & 0xfffff000) + higher_half
	}
	kio.mmout(&u32(lapic_base + reg), val)
}

fn x2apic_write(reg u32, val u64) {
	msr.wrmsr(0x800 + (reg >> 4), val)
}

fn lapic_read(reg u32) u64 {
	if x2apic_mode {
		return x2apic_read(reg)
	} else {
		return xapic_read(reg)
	}
}

fn lapic_write(reg u32, val u64) {
	if x2apic_mode {
		x2apic_write(reg, val)
	} else {
		xapic_write(reg, u32(val))
	}
}

pub fn lapic_timer_stop() {
	lapic_write(apic.lapic_reg_timer_initcnt, 0)
	lapic_write(apic.lapic_reg_timer, (1 << 16))
}

pub fn lapic_timer_calibrate(mut cpu_local cpulocal.Local) {
	lapic_timer_stop()

	samples := u64(0xfffff)

	lapic_write(apic.lapic_reg_timer, (1 << 16) | 0xff) // Vector 0xff, masked
	lapic_write(apic.lapic_reg_timer_div, 0)

	time.pit_set_reload_value(0xffff)

	initial_pit_tick := u64(time.pit_get_current_count())

	lapic_write(apic.lapic_reg_timer_initcnt, u32(samples))

	for lapic_read(apic.lapic_reg_timer_curcnt) != 0 {}

	final_pit_tick := u64(time.pit_get_current_count())

	pit_ticks := initial_pit_tick - final_pit_tick

	cpu_local.lapic_timer_freq = (samples / pit_ticks) * time.pit_dividend

	lapic_timer_stop()
}

pub fn lapic_timer_oneshot(mut cpu_local cpulocal.Local, vec u8, us u64) {
	lapic_timer_stop()

	ticks := us * (cpu_local.lapic_timer_freq / 1000000)

	lapic_write(apic.lapic_reg_timer, vec)
	lapic_write(apic.lapic_reg_timer_div, 0)
	lapic_write(apic.lapic_reg_timer_initcnt, u32(ticks))
}

pub fn lapic_enable(spurious_vect u8) {
	lapic_write(apic.lapic_reg_spurious, lapic_read(apic.lapic_reg_spurious) | (1 << 8) | spurious_vect)
}

pub fn lapic_eoi() {
	lapic_write(apic.lapic_reg_eoi, 0)
}

pub fn lapic_send_ipi(lapic_id u32, vector u8) {
	if x2apic_mode {
		x2apic_write(apic.lapic_reg_icr0, (u64(lapic_id) << 32) | vector)
	} else {
		xapic_write(apic.lapic_reg_icr1, u32(lapic_id) << 24)
		xapic_write(apic.lapic_reg_icr0, vector)
	}
}

fn io_apic_read(io_apic int, reg u32) u32 {
	base := u64(madt_io_apics[io_apic].address) + higher_half
	kio.mmout(&u32(base), reg)
	return kio.mmin(&u32(base + 16))
}

fn io_apic_write(io_apic int, reg u32, value u32) {
	base := u64(madt_io_apics[io_apic].address) + higher_half
	kio.mmout(&u32(base), reg)
	kio.mmout(&u32(base + 16), value)
}

fn io_apic_gsi_count(io_apic int) u32 {
	return (io_apic_read(io_apic, 1) & 0xff0000) >> 16
}

fn io_apic_from_gsi(gsi u32) int {
	for i := 0; i < madt_io_apics.len; i++ {
		if madt_io_apics[i].gsib <= gsi && madt_io_apics[i].gsib + io_apic_gsi_count(i) > gsi {
			return i
		}
	}

	panic('Cannot determine IO APIC from GSI')
}

pub fn io_apic_set_gsi_redirect(lapic_id u32, vector u8, gsi u32, flags u16, status bool) {
	io_apic := io_apic_from_gsi(gsi)

	mut redirect := u64(vector)

	if flags & (1 << 1) != 0 {
		redirect |= (1 << 13)
	}

	if flags & (1 << 3) != 0 {
		redirect |= (1 << 15)
	}

	if status == false {
		redirect |= (1 << 16)
	}

	redirect |= u64(lapic_id) << 56

	ioredtbl := (gsi - madt_io_apics[io_apic].gsib) * 2 + 16

	io_apic_write(io_apic, ioredtbl, u32(redirect))
	io_apic_write(io_apic, ioredtbl + 1, u32(redirect >> 32))
}

pub fn io_apic_set_irq_redirect(lapic_id u32, vector u8, irq u8, status bool) {
	for i := 0; i < madt_isos.len; i++ {
		if madt_isos[i].irq_source == irq {
			if status {
				print('apic: IRQ $irq using override\n')
			}
			io_apic_set_gsi_redirect(lapic_id, vector, madt_isos[i].gsi, madt_isos[i].flags,
				status)
			return
		}
	}
	io_apic_set_gsi_redirect(lapic_id, vector, irq, 0, status)
}
