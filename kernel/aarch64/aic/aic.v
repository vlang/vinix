@[has_globals]
module aic

// Apple Interrupt Controller.
//
// AICv1 (t8103, the base M1) has fixed register offsets and carries IPIs.
// AICv2 (M1 Pro/Max, M2) and AICv3 (M3 and later, the M5 included) place one
// block of per-IRQ registers per die at offsets the ADT gives, read events
// from a separate acknowledge register, and carry no IPIs: those go through
// the cores' fast-IPI system registers. initialise_v2 takes the layout from
// the ADT the way m1n1's aic23_init does.

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

// AICv2/v3 per-IRQ config words and the bit fields of their capability
// registers (m1n1's aic_regs.h).
const aic2_cap0_nr_irq_mask = u32(0xffff)
const aic2_cap0_last_die_shift = u32(24)
const aic2_max_irq_limit = u32(0x1000)
const aic2_max_dies = u32(4)

__global (
	aic_base       = u64(0)
	aic_nr_irqs    = u32(0)
	aic_lock       klock.Lock
	aic_hw_handler fn (u32, voidptr)
	aic_ipi_handler fn ()
	aic_fiq_handler fn (voidptr)
	// AICv2/v3 only; aic_v2 is false on AICv1.
	aic_v2                  bool
	aic_v2_event            u32
	aic_v2_mask_set         u32
	aic_v2_mask_clr         u32
	aic_v2_mask_set_stride  u32
	aic_v2_mask_clr_stride  u32
	aic_v2_max_irq          u32
	aic_v2_nr_die           u32
)

// Where an AICv2/v3 keeps its registers, from the ADT's /arm-io/aic node.
// AICv2 fixes cap0 and maxnumirq at 0x4 and 0xc; AICv3 names them.
pub struct V2Layout {
pub:
	version             u32
	base                u64
	size                u64
	event               u64 // aic-iack-offset
	cap0                u32 // cap0-offset
	maxnumirq           u32 // maxnumirq-offset
	config              u32 // extint-baseaddress: the first die's IRQ config words
	global_config       u32 // aicglbcfg-offset; 0 when there is none
	extintrcfg_stride   u32 // 0 when the ADT leaves them to be computed
	intmaskset_stride   u32
	intmaskclear_stride u32
}

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
	C.kprintf(c'aic.2 base 0x%llx, mapping MMIO aperture...\n', u64(base))

	// Map the AIC register aperture as Device memory (it lives far above the
	// 4 GiB HHDM window, so plain `base + higher_half` is not valid).
	aic_base = memory.map_mmio(base, 0x8000)
	term.early_stage_mark(42) // blue: map_mmio returned
	C.kprintf(c'aic.3 MMIO mapped at 0x%llx, reading AIC_INFO...\n', u64(aic_base))

	info := aic_read(aic_info)
	term.early_stage_mark(43) // yellow: first MMIO read returned
	C.kprintf(c'aic.4 AIC_INFO=0x%llx\n', u64(info))
	aic_nr_irqs = info & 0xffff

	// AICv1 parts carry a few hundred to ~1k IRQs (t8103: 896). 0 means the
	// register did not respond; all-ones means an unbacked read.
	if aic_nr_irqs == 0 || aic_nr_irqs > 4096 || info == 0xffffffff {
		println('aic: implausible AIC_INFO, leaving the AIC uninitialised')
		return false
	}

	C.kprintf(c'aic: Apple Interrupt Controller at 0x%llx\n', u64(base))
	C.kprintf(c'aic: %llu hardware IRQs\n', u64(aic_nr_irqs))

	// Mask all IRQs initially
	nr_regs := (aic_nr_irqs + 31) / 32
	C.kprintf(c'aic.5 masking %llu mask registers\n', u64(nr_regs))
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

// Returns false, leaving the controller alone, if the layout does not fit
// the register window or the controller does not answer plausibly.
pub fn initialise_v2(layout V2Layout) bool {
	C.kprintf(c'aic: AICv%llu at 0x%llx+0x%llx, events at +0x%llx\n', u64(layout.version),
		layout.base, layout.size, layout.event)
	if layout.size == 0 || layout.event + 4 > layout.size || u64(layout.cap0) + 4 > layout.size
		|| u64(layout.maxnumirq) + 4 > layout.size || layout.config == 0 {
		println('aic: the ADT layout does not fit the register window')
		return false
	}
	aic_base = memory.map_mmio(layout.base, layout.size)

	cap0 := aic_read(layout.cap0)
	max := aic_read(layout.maxnumirq)
	nr_irqs := cap0 & aic2_cap0_nr_irq_mask
	nr_die := ((cap0 >> aic2_cap0_last_die_shift) & 0xf) + 1
	max_irq := max & aic2_cap0_nr_irq_mask
	C.kprintf(c'aic: cap0 0x%llx (%llu IRQs, %llu dies), maxnumirq 0x%llx\n', u64(cap0),
		u64(nr_irqs), u64(nr_die), u64(max))
	if cap0 == 0xffffffff || nr_irqs == 0 || max_irq == 0 || max_irq > aic2_max_irq_limit
		|| nr_irqs > max_irq || nr_die > aic2_max_dies || max_irq % 32 != 0 {
		println('aic: implausible capability registers, leaving the AIC uninitialised')
		return false
	}

	// Each die's block: a config word per IRQ, then software-set,
	// software-clear, mask-set, mask-clear and hardware-state bitmaps.
	words := max_irq / 32
	sw_set := layout.config + 4 * max_irq
	mask_set := sw_set + 8 * words
	mask_clr := mask_set + 4 * words
	die_span := mask_clr + 8 * words - layout.config
	set_stride := if layout.intmaskset_stride != 0 { layout.intmaskset_stride } else { die_span }
	clr_stride := if layout.intmaskclear_stride != 0 {
		layout.intmaskclear_stride
	} else {
		die_span
	}
	last_die := nr_die - 1
	if u64(mask_set) + u64(last_die) * u64(set_stride) + u64(4 * words) > layout.size
		|| u64(mask_clr) + u64(last_die) * u64(clr_stride) + u64(4 * words) > layout.size {
		println('aic: per-die registers run past the register window')
		return false
	}

	aic_v2_event = u32(layout.event)
	aic_v2_mask_set = mask_set
	aic_v2_mask_clr = mask_clr
	aic_v2_mask_set_stride = set_stride
	aic_v2_mask_clr_stride = clr_stride
	aic_v2_max_irq = max_irq
	aic_v2_nr_die = nr_die
	aic_nr_irqs = nr_irqs
	aic_v2 = true

	// Nothing is wanted until a driver asks for it; iBoot may have left
	// sources unmasked.
	for die := u32(0); die < nr_die; die++ {
		for word := u32(0); word < (nr_irqs + 31) / 32; word++ {
			aic_write(mask_set + die * set_stride + word * 4, 0xffffffff)
		}
	}
	// Bit 0 of the global config enables delivery; Linux sets it on AICv2
	// and AICv3 names the same register.
	if layout.global_config != 0 && u64(layout.global_config) + 4 <= layout.size {
		aic_write(layout.global_config, aic_read(layout.global_config) | 1)
	}
	exception.register_irq_dispatch(aic_dispatch)
	C.kprintf(c'aic: masked, mask registers at +0x%llx/+0x%llx\n', u64(mask_set),
		u64(mask_clr))
	return true
}

fn aic_dispatch(gpr_state voidptr) {
	// The Apple architectural timer is delivered as an FIQ handled directly by
	// the CPU, not as an AIC event. Give the FIQ handler first look on every
	// entry; it self-gates on the timer's pending status.
	if aic_fiq_handler != unsafe { nil } {
		aic_fiq_handler(gpr_state)
	}

	if aic_v2 {
		for {
			evt := aic_read(aic_v2_event)
			if (evt >> 16) & 0xff != aic_event_type_hw {
				break
			}
			// Numbered across dies: die * max_irq + the die's own number.
			irq := (evt >> 24) * aic_v2_max_irq + (evt & aic_event_irq_mask)
			if aic_hw_handler != unsafe { nil } {
				aic_hw_handler(irq, gpr_state)
			}
			// Acknowledging masked it, as on AICv1.
			unmask_irq(irq)
		}
		return
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
	if aic_v2 {
		die := irq / aic_v2_max_irq
		local := irq % aic_v2_max_irq
		aic_write(aic_v2_mask_set + die * aic_v2_mask_set_stride + (local / 32) * 4,
			u32(1) << (local % 32))
		return
	}
	reg := irq / 32
	bit := irq % 32
	aic_write(aic_mask_set + reg * 4, u32(1) << bit)
}

pub fn unmask_irq(irq u32) {
	if aic_v2 {
		die := irq / aic_v2_max_irq
		local := irq % aic_v2_max_irq
		aic_write(aic_v2_mask_clr + die * aic_v2_mask_clr_stride + (local / 32) * 4,
			u32(1) << (local % 32))
		return
	}
	reg := irq / 32
	bit := irq % 32
	aic_write(aic_mask_clr + reg * 4, u32(1) << bit)
}

pub fn send_ipi(cpu_id u32) {
	if aic_v2 {
		// AICv2 and later carry no IPIs; the cores' fast-IPI registers do,
		// and nothing starts a second core on these machines yet.
		return
	}
	// On AIC, IPIs are sent via the IPI_SET register
	// The target CPU is implicit (routed via cluster/core config)
	aic_write(aic_ipi_set, aic_ipi_other)
}

pub fn eoi() {
	// AIC doesn't have a separate EOI register --
	// events are acknowledged by reading AIC_EVENT
}
