@[has_globals]
module aic

// Apple Interrupt Controller v2 (AICv2)
// MMIO base typically at 0x23B100000 (from device tree)
// Handles IRQ routing on Apple Silicon

import aarch64.kio
import aarch64.exception
import klock

// AIC registers (offsets from base)
const aic_info = u32(0x0004)
const aic_whoami = u32(0x2000)
const aic_event = u32(0x2004)
const aic_ipi_set = u32(0x2008)
const aic_ipi_clr = u32(0x200c)
const aic_ipi_mask_set = u32(0x2024)
const aic_ipi_mask_clr = u32(0x2028)
const aic_hw_state = u32(0x3000) // base for per-irq state

// Per-IRQ register offsets (indexed by IRQ number)
const aic_mask_set = u32(0x4000)  // base for mask set registers (32 IRQs per reg)
const aic_mask_clr = u32(0x4080)  // base for mask clear registers
const aic_sw_set = u32(0x4100)
const aic_sw_clr = u32(0x4180)

// Event types from AIC_EVENT register
const aic_event_type_hw = u32(1)
const aic_event_type_ipi = u32(4)
const aic_event_die_shift = u32(0)
const aic_event_irq_mask = u32(0xffff)

// IPI types
const aic_ipi_other = u32(1)
const aic_ipi_self = u32(0x80000000)

__global (
	aic_base       = u64(0)
	aic_nr_irqs    = u32(0)
	aic_lock       klock.Lock
	aic_hw_handler fn (u32, voidptr)
	aic_ipi_handler fn ()
)

fn aic_read(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(aic_base + offset) })
}

fn aic_write(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(aic_base + offset) }, value)
}

pub fn initialise(base u64) {
	aic_base = base + higher_half

	info := aic_read(aic_info)
	aic_nr_irqs = info & 0xffff

	println('aic: Apple Interrupt Controller at 0x${base:x}')
	println('aic: ${aic_nr_irqs} hardware IRQs')

	// Mask all IRQs initially
	nr_regs := (aic_nr_irqs + 31) / 32
	for i := u32(0); i < nr_regs; i++ {
		aic_write(aic_mask_set + i * 4, 0xffffffff)
	}

	// Clear any pending IPIs
	aic_write(aic_ipi_clr, aic_ipi_other | aic_ipi_self)

	// Unmask IPIs
	aic_write(aic_ipi_mask_clr, aic_ipi_other | aic_ipi_self)

	// Register our dispatch handler with the exception system
	exception.register_irq_dispatch(aic_dispatch)
}

fn aic_dispatch(gpr_state voidptr) {
	for {
		evt := aic_read(aic_event)
		evt_type := (evt >> 16) & 0xff

		match evt_type {
			aic_event_type_hw {
				irq := evt & aic_event_irq_mask
				if aic_hw_handler != unsafe { nil } {
					aic_hw_handler(irq, gpr_state)
				}
			}
			aic_event_type_ipi {
				// Clear IPI
				aic_write(aic_ipi_clr, aic_ipi_other)
				if aic_ipi_handler != unsafe { nil } {
					aic_ipi_handler()
				}
			}
			else {
				// No more events
				break
			}
		}
	}
}

// Register a handler for hardware IRQs. The handler receives the IRQ number.
pub fn register_hw_handler(handler fn (u32, voidptr)) {
	aic_hw_handler = handler
}

// Register a handler for IPI (inter-processor interrupt) events.
pub fn register_ipi_handler(handler fn ()) {
	aic_ipi_handler = handler
}

pub fn mask_irq(irq u32) {
	reg := irq / 32
	bit := irq % 32
	aic_write(aic_mask_set + reg * 4, u32(1) << bit)
}

pub fn unmask_irq(irq u32) {
	reg := irq / 32
	bit := irq % 32
	aic_write(aic_mask_clr + reg * 4, u32(1) << bit)
}

pub fn send_ipi(cpu_id u32) {
	// On AIC, IPIs are sent via the IPI_SET register
	// The target CPU is implicit (routed via cluster/core config)
	aic_write(aic_ipi_set, aic_ipi_other)
}

pub fn eoi() {
	// AIC doesn't have a separate EOI register --
	// events are acknowledged by reading AIC_EVENT
}
