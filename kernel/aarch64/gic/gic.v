@[has_globals]
module gic

// GICv3 driver for QEMU virt machine.
//
// QEMU 10.x emulates GICv3 in userspace (no platform vGIC in QEMU 10.2).
// GICD and GICR are accessed via MMIO, with QEMU handling Stage 2 data
// aborts. The CPU interface uses ICC system registers.
//
// UEFI firmware disables all interrupts and the distributor before
// handing off to the OS, so we must fully reinitialise.

import aarch64.cpu
import aarch64.exception
import aarch64.uart

// Interrupt IDs
const intid_timer = u32(27) // EL1 Virtual Timer PPI (INTID 27)
const intid_spurious = u32(1023)

// QEMU virt GIC addresses (from DTB: intc@8000000)
const gicd_base_phys = u64(0x08000000)
const gicr_base_phys = u64(0x080a0000)

// GICD register offsets
const gicd_ctlr = u64(0x0000)

// GICD_CTLR bits
const gicd_ctlr_enable_grp1_ns = u64(1) << 1
const gicd_ctlr_are_ns = u64(1) << 4

// GICR register offsets (from GICR base)
const gicr_igroupr0 = u64(0x10080) // Interrupt group (0=G0, 1=G1NS)
const gicr_isenabler0 = u64(0x10100) // Set-enable
const gicr_icpendr0 = u64(0x10280) // Clear-pending
const gicr_ipriorityr_base = u64(0x10400) // Priority (byte per INTID)

__global (
	gic_timer_callback fn (voidptr)
	gicd_base          u64
	gicr_base          u64
)

// ── MMIO helpers ──
// Use direct pointer dereference (V inline asm for ldr/str generates
// incorrect code on aarch64). DSB/DMB barriers ensure Device memory ordering.

fn gicd_read32(offset u64) u32 {
	addr := gicd_base + offset
	val := unsafe { *&u32(addr) }
	cpu.dmb_ish()
	return val
}

fn gicd_write32(offset u64, val u32) {
	addr := gicd_base + offset
	cpu.dmb_ish()
	unsafe {
		*&u32(addr) = val
	}
}

fn gicr_read32(offset u64) u32 {
	addr := gicr_base + offset
	val := unsafe { *&u32(addr) }
	cpu.dmb_ish()
	return val
}

fn gicr_write32(offset u64, val u32) {
	addr := gicr_base + offset
	cpu.dmb_ish()
	unsafe {
		*&u32(addr) = val
	}
}

// ── ICC system register access ──

fn read_icc_iar1() u32 {
	mut val := u64(0)
	asm volatile aarch64 {
		mrs val, icc_iar1_el1
		; =r (val)
		; ; memory
	}
	return u32(val)
}

fn write_icc_eoir1(intid u32) {
	v := u64(intid)
	asm volatile aarch64 {
		msr icc_eoir1_el1, v
		; ; r (v)
		; memory
	}
}

fn read_icc_sre() u64 {
	mut val := u64(0)
	asm volatile aarch64 {
		mrs val, icc_sre_el1
		; =r (val)
	}
	return val
}

fn write_icc_sre(v u64) {
	asm volatile aarch64 {
		msr icc_sre_el1, v
		isb
		; ; r (v)
		; memory
	}
}

fn write_icc_pmr(v u64) {
	asm volatile aarch64 {
		msr icc_pmr_el1, v
		; ; r (v)
		; memory
	}
}

fn write_icc_bpr1(v u64) {
	asm volatile aarch64 {
		msr icc_bpr1_el1, v
		; ; r (v)
		; memory
	}
}

fn write_icc_ctlr(v u64) {
	asm volatile aarch64 {
		msr icc_ctlr_el1, v
		; ; r (v)
		; memory
	}
}

fn write_icc_igrpen1(v u64) {
	asm volatile aarch64 {
		msr icc_igrpen1_el1, v
		; ; r (v)
		; memory
	}
}

// ── Hex output helper ──

fn gic_put_hex(val u64) {
	hex := c'0123456789abcdef'
	mut buf := [17]u8{}
	mut i := 16
	buf[i] = 0
	mut v := val
	if v == 0 {
		uart.putc(u8(`0`))
		return
	}
	for v > 0 && i > 0 {
		i--
		buf[i] = u8(unsafe { hex[v & 0xf] })
		v >>= 4
	}
	for i < 16 {
		uart.putc(buf[i])
		i++
	}
}

// ── Public API ──

pub fn initialise(hhdm u64) {
	gicd_base = hhdm + gicd_base_phys
	gicr_base = hhdm + gicr_base_phys

	uart.puts(c'  gic: GICD at 0x')
	gic_put_hex(gicd_base)
	uart.puts(c' GICR at 0x')
	gic_put_hex(gicr_base)
	uart.putc(u8(`\n`))

	// ── Step 1: Enable ICC system registers ──
	write_icc_sre(read_icc_sre() | 0x7)
	cpu.isb()

	// ── Step 2: Configure GICD (distributor) ──
	// Enable distributor with ARE (affinity routing) and Group 1 NS
	gicd_write32(gicd_ctlr, u32(gicd_ctlr_are_ns | gicd_ctlr_enable_grp1_ns))
	cpu.isb()

	// ── Step 3: Configure GICR (redistributor) for CPU 0 ──
	// Wake up redistributor (clear ProcessorSleep if needed)
	waker := gicr_read32(0x14)
	if waker & 0x2 != 0 {
		gicr_write32(0x14, waker & ~u32(0x2))
		for gicr_read32(0x14) & 0x4 != 0 {
		}
	}

	// Set all SGIs/PPIs (INTIDs 0-31) to Group 1 Non-Secure
	gicr_write32(gicr_igroupr0, u32(0xFFFFFFFF))

	// Clear all pending interrupts
	gicr_write32(gicr_icpendr0, u32(0xFFFFFFFF))

	// Set priority for all SGIs/PPIs to 0xA0 (reasonable default)
	for off := u64(0); off < 32; off += 4 {
		gicr_write32(gicr_ipriorityr_base + off, u32(0xA0A0A0A0))
	}

	// Enable timer PPI (INTID 27) and SGIs 0-15
	gicr_write32(gicr_isenabler0, u32(1) << 27 | u32(0xFFFF))

	// ── Step 4: Configure ICC (CPU interface) ──
	write_icc_pmr(0xFF) // Accept all priorities
	write_icc_bpr1(0) // No sub-priority bits
	write_icc_ctlr(0) // EOImode=0
	write_icc_igrpen1(1) // Enable Group 1 interrupts
	cpu.isb()

	// Register as global IRQ dispatch handler
	exception.register_irq_dispatch(gic_dispatch)
}

pub fn set_timer_handler(handler fn (voidptr)) {
	gic_timer_callback = handler
}

// Poll ICC_IAR1 (acknowledge interrupt) - for polled mode
pub fn poll_iar1() u32 {
	return read_icc_iar1()
}

// Handle an interrupt in polled mode (bypass exception vector).
// Used as HVF workaround since QEMU+HVF doesn't inject IRQs to guest.
pub fn dispatch_polled(intid u32, gpr_state voidptr) {
	if intid == intid_timer {
		cpu.write_cntv_ctl_el0(0x2) // Mask timer to clear level IRQ
		write_icc_eoir1(intid)

		if gic_timer_callback != unsafe { nil } {
			gic_timer_callback(gpr_state)
		}
		return
	}

	write_icc_eoir1(intid)
}

fn gic_dispatch(gpr_state voidptr) {
	intid := read_icc_iar1()

	if intid >= intid_spurious {
		return
	}

	if intid == intid_timer {
		cpu.write_cntv_ctl_el0(0x2) // Mask timer to clear level IRQ
		write_icc_eoir1(intid)

		if gic_timer_callback != unsafe { nil } {
			gic_timer_callback(gpr_state)
		}
		return
	}

	write_icc_eoir1(intid)
}
