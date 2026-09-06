@[has_globals]
module aic

// Apple Interrupt Controller v1 (AICv1)
// MMIO base typically at 0x23B100000 (from device tree)
// Handles IRQ routing on Apple Silicon (t8103 / base M1).
//
// NOTE: AICv2 (M1 Pro/Max and later) uses a different register layout whose
// offsets are computed from AIC_INFO; that variant needs a separate backend.

import aarch64.kio
import aarch64.exception
import klock
import memory
import term

// AIC registers (offsets from base)
const aic_info = u32(0x0004)
const aic_whoami = u32(0x2000)
const aic_event = u32(0x2004)
const aic_ipi_set = u32(0x2008)
const aic_ipi_clr = u32(0x200c)
const aic_ipi_mask_set = u32(0x2024)
const aic_ipi_mask_clr = u32(0x2028)
const aic_hw_state = u32(0x3000) // base for per-irq state

// Per-IRQ register offsets (indexed by IRQ number, 32 IRQs per 32-bit reg).
// AICv1 layout (matches Linux irq-apple-aic.c):
//   SW set/clear at 0x4000/0x4080, mask set/clear at 0x4100/0x4180.
const aic_sw_set = u32(0x4000)
const aic_sw_clr = u32(0x4080)
const aic_mask_set = u32(0x4100)
const aic_mask_clr = u32(0x4180)

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
	aic_fiq_handler fn (voidptr)
)

fn aic_read(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(aic_base + offset) })
}

fn aic_write(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(aic_base + offset) }, value)
}

// Returns false if the controller does not answer plausibly, so the caller can
// continue without it rather than programming thousands of nonexistent mask
// registers off a garbage AIC_INFO.
// Every step below is announced on two channels: a numbered text line, and a
// colour bar drawn straight into the framebuffer by term.early_stage_mark
// (no lock, no allocation, no flanterm). On the M1 the boot stops somewhere in
// here with no text at all, so the bars tell execution progress apart from a
// wedged text path. Bars sit at rows 41..46 (mid-screen), one colour each.
pub fn initialise(base u64) bool {
	term.early_stage_mark(41) // green: entered initialise
	print('aic.1 entered initialise\n')
	println('aic.2 base 0x${base:x}, mapping MMIO aperture...')

	// Map the AIC register aperture as Device memory (it lives far above the
	// 4 GiB HHDM window, so plain `base + higher_half` is not valid).
	aic_base = memory.map_mmio(base, 0x8000)
	term.early_stage_mark(42) // blue: map_mmio returned
	println('aic.3 MMIO mapped at 0x${aic_base:x}, reading AIC_INFO...')

	info := aic_read(aic_info)
	term.early_stage_mark(43) // yellow: first MMIO read returned
	println('aic.4 AIC_INFO=0x${info:x}')
	aic_nr_irqs = info & 0xffff

	// AICv1 parts carry a few hundred to ~1k IRQs (t8103: 896). 0 means the
	// register did not respond; all-ones means an unbacked read.
	if aic_nr_irqs == 0 || aic_nr_irqs > 4096 || info == 0xffffffff {
		println('aic: implausible AIC_INFO, leaving the AIC uninitialised')
		return false
	}

	println('aic: Apple Interrupt Controller at 0x${base:x}')
	println('aic: ${aic_nr_irqs} hardware IRQs')

	// Mask all IRQs initially
	nr_regs := (aic_nr_irqs + 31) / 32
	print('aic.5 masking ${nr_regs} mask registers\n')
	for i := u32(0); i < nr_regs; i++ {
		aic_write(aic_mask_set + i * 4, 0xffffffff)
	}
	term.early_stage_mark(44) // cyan: mask writes done
	print('aic.6 masked\n')

	// Clear any pending IPIs
	aic_write(aic_ipi_clr, aic_ipi_other | aic_ipi_self)
	print('aic.7 ipi cleared\n')

	// Unmask IPIs
	aic_write(aic_ipi_mask_clr, aic_ipi_other | aic_ipi_self)
	term.early_stage_mark(45) // magenta: IPI writes done
	print('aic.8 ipi unmasked\n')

	// Register our dispatch handler with the exception system
	exception.register_irq_dispatch(aic_dispatch)
	term.early_stage_mark(46) // white: dispatch registered
	print('aic.9 dispatch registered\n')
	return true
}

fn aic_dispatch(gpr_state voidptr) {
	// The Apple architectural timer is delivered as an FIQ handled directly by
	// the CPU, not as an AIC event. Give the FIQ handler first look on every
	// entry; it self-gates on the timer's pending status.
	if aic_fiq_handler != unsafe { nil } {
		aic_fiq_handler(gpr_state)
	}

	for {
		evt := aic_read(aic_event)
		evt_type := (evt >> 16) & 0xff

		match evt_type {
			aic_event_type_hw {
				irq := evt & aic_event_irq_mask
				if aic_hw_handler != unsafe { nil } {
					aic_hw_handler(irq, gpr_state)
				}
				// Reading AIC_EVENT auto-masks the delivered hardware IRQ; the
				// EOI/unmask lifecycle must re-enable it so it can fire again.
				unmask_irq(irq)
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

// Register a handler invoked at the top of every interrupt dispatch, before
// AIC events are read. Used for FIQ-delivered sources such as the Apple
// architectural timer, which never appear as AIC events.
pub fn register_fiq_handler(handler fn (voidptr)) {
	aic_fiq_handler = handler
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
