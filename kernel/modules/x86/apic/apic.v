module apic

import kio
import msr
import cpu.local as cpulocal
import katomic
import idt

__global (
	x86_pit_ticks = u64(0)
	x86_pit_vector = byte(0)
)

fn handler(_ u32, _ voidptr) {
	katomic.inc(x86_pit_ticks)
}

pub fn pit_initialise() {
	if x86_pit_vector == 0 {
		x86_pit_vector = idt.allocate_vector()
		interrupt_table[x86_pit_vector] = voidptr(handler)
		println('pit: Using vector $x86_pit_vector')
	}

	apic.io_apic_set_irq_redirect(cpulocal.current().lapic_id, x86_pit_vector, 0, true)
}

pub fn pit_mask() {
	apic.io_apic_set_irq_redirect(0, 0, 0, false)
}

pub fn pit_set_freq(freq u32) {
	dividend := u32(1193182)

	mut ticks := dividend / freq
	if dividend % freq > freq / 2 {
		ticks++
	}

	kio.outb(0x40, byte(ticks))
	kio.outb(0x40, byte(ticks >> 8))
}

const lapic_reg_icr0 = 0x300
const lapic_reg_icr1 = 0x310
const lapic_reg_spurious = 0x0f0
const lapic_reg_eoi = 0x0b0
const lapic_reg_timer = 0x320
const lapic_reg_timer_initcnt = 0x380
const lapic_reg_timer_curcnt = 0x390
const lapic_reg_timer_div = 0x3e0

fn lapic_read(reg u32) u32 {
	lapic_base := u64(msr.rdmsr(0x1b) & 0xfffff000) + higher_half
	return kio.mmind(lapic_base + reg)
}

fn lapic_write(reg u32, val u32) {
	lapic_base := u64(msr.rdmsr(0x1b) & 0xfffff000) + higher_half
	kio.mmoutd(lapic_base + reg, val)
}

pub fn lapic_timer_calibrate() {
	pit_initialise()

	lapic_write(lapic_reg_timer_initcnt, 0)
	lapic_write(lapic_reg_timer, (1 << 16))

	lapic_write(lapic_reg_timer, (1 << 16) | 0xff) // Vector 0xff, masked
	lapic_write(lapic_reg_timer_div, 0)
	lapic_write(lapic_reg_timer_initcnt, 0xfffff)

	pit_freq := u64(47727)

	pit_set_freq(u32(pit_freq))

	initial_pit_tick := katomic.load(x86_pit_ticks)

	for lapic_read(lapic_reg_timer_curcnt) != 0 {}

	final_pit_tick := katomic.load(x86_pit_ticks)

	pit_mask()

	pit_ticks := final_pit_tick - initial_pit_tick

	mut cpu_local := cpulocal.current()

	cpu_local.lapic_timer_freq = (0xfffff / pit_ticks) * pit_freq

	print('apic: Local APIC timer frequency is ${cpu_local.lapic_timer_freq} Hz\n')
}

pub fn lapic_timer_oneshot(vec u8, us u64) {
	lapic_write(lapic_reg_timer_initcnt, 0)
	lapic_write(lapic_reg_timer, (1 << 16))

	cpu_local := cpulocal.current()

	ticks := us * (cpu_local.lapic_timer_freq / 1000000)

	lapic_write(lapic_reg_timer, vec)
	lapic_write(lapic_reg_timer_div, 0)
	lapic_write(lapic_reg_timer_initcnt, u32(ticks))
}

pub fn lapic_enable(spurious_vect u8) {
	lapic_write(lapic_reg_spurious, lapic_read(lapic_reg_spurious) | (1 << 8) | spurious_vect)
}

pub fn lapic_eoi() {
	lapic_write(lapic_reg_eoi, 0)
}

pub fn lapic_send_ipi(lapic_id u8, vector u8) {
	lapic_write(lapic_reg_icr1, u32(lapic_id) << 24)
	lapic_write(lapic_reg_icr0, vector)
}

fn io_apic_read(io_apic int, reg u32) u32 {
	base := u64(madt_io_apics[io_apic].address) + higher_half
	kio.mmoutd(base, reg)
	return kio.mmind(base + 16)
}

fn io_apic_write(io_apic int, reg u32, value u32) {
	base := u64(madt_io_apics[io_apic].address) + higher_half
	kio.mmoutd(base, reg)
	kio.mmoutd(base + 16, value)
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
			if status { print('apic: IRQ $irq using override\n') }
			io_apic_set_gsi_redirect(lapic_id, vector, madt_isos[i].gsi, madt_isos[i].flags, status)
			return
		}
	}
	io_apic_set_gsi_redirect(lapic_id, vector, irq, 0, status)
}
