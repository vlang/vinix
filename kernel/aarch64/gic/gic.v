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
import memory

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

// GICR register offsets, from the base of one CPU's redistributor frame. The
// ones past 0x10000 are in the frame's second 64 KiB page, which is where a
// GICv3 redistributor keeps everything to do with its own SGIs and PPIs.
const gicr_waker = u64(0x0014) // ProcessorSleep / ChildrenAsleep
const gicr_igroupr0 = u64(0x10080) // Interrupt group (0=G0, 1=G1NS)
const gicr_isenabler0 = u64(0x10100) // Set-enable
const gicr_icpendr0 = u64(0x10280) // Clear-pending
const gicr_ipriorityr_base = u64(0x10400) // Priority (byte per INTID)

// Every CPU has a redistributor frame of its own, laid out one after another
// from the base of the region: two 64 KiB pages each, RD then SGI.
const gicr_stride = u64(0x20000)

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
	return frame_read32(gicr_base, offset)
}

fn gicr_write32(offset u64, val u32) {
	frame_write32(gicr_base, offset, val)
}

// A redistributor is addressed by the frame it lives in, because each CPU has
// one of its own.
//
// Both of these stay out of line, and it matters. Inlined into a run of
// accesses at fixed offsets from one base -- which is exactly what configuring
// a redistributor is -- the compiler keeps the base in a register and folds the
// first offset into the store as `str w8, [x9, #0x80]!`. A store that writes
// its base register back leaves a data abort with no instruction syndrome, and
// a hypervisor with nothing to decode the access from: QEMU under HVF asserts
// and takes the machine with it. Out of line, the address arrives as a plain
// register and the access is one the syndrome can describe.
@[noinline]
fn frame_read32(frame u64, offset u64) u32 {
	addr := frame + offset
	val := unsafe { *&u32(addr) }
	cpu.dmb_ish()
	return val
}

@[noinline]
fn frame_write32(frame u64, offset u64, val u32) {
	addr := frame + offset
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

// Was the GIC the interrupt controller this machine turned out to have? Apple
// hardware has an AIC instead and never calls initialise(), so a CPU coming up
// has to ask before it configures a redistributor that is not there.
pub fn is_initialised() bool {
	return gicd_base != 0
}

// Bring up QEMU virt's GIC, at the addresses its device tree gives it.
pub fn initialise(hhdm u64) {
	gicd_base = hhdm + gicd_base_phys
	gicr_base = hhdm + gicr_base_phys
	start()
}

// Bring up a GIC at the addresses firmware reported (the ACPI MADT on a UEFI
// machine such as VirtualBox's). They are anywhere in the physical address
// space, so they are mapped as Device memory first.
pub fn initialise_at(dist_phys u64, redist_phys u64, redist_len u64) {
	gicd_base = memory.map_mmio(dist_phys, 0x10000)
	gicr_base = memory.map_mmio(redist_phys, if redist_len != 0 { redist_len } else { gicr_stride })
	start()
}

fn start() {
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

// Bring a secondary CPU's side of the GIC up.
//
// Everything in initialise() below the distributor is per-CPU state: the CPU's
// own redistributor frame, and its own ICC system registers. A CPU which has
// not done this receives no interrupts at all -- Group 1 is disabled at its
// CPU interface and its timer PPI is not even enabled -- and until it did,
// the scheduler's timer fired on the boot CPU and nowhere else.
//
// What that cost is worth spelling out, because it is not a missing feature so
// much as a missing half of the scheduler: a thread busy in userspace on any
// CPU but the first ran until it made a syscall. Its timeslice never expired,
// affinity changes did not move it, and nothing more urgent could take the CPU
// from it. Preemption, and with it every guarantee a scheduling policy makes,
// begins here.
pub fn initialise_secondary(cpu_number u64) {
	// The CPU interface is reached through system registers, which have to be
	// turned on for this CPU before any of the writes below mean anything.
	write_icc_sre(read_icc_sre() | 0x7)
	cpu.isb()

	// The frames are laid out in CPU order from the base of the region, which
	// is how this machine describes itself and all this driver claims to
	// support -- GICR_TYPER would name the CPU each frame serves, but reading
	// its two halves next to each other is exactly the paired load that leaves
	// a hypervisor with no syndrome to decode the MMIO access from.
	frame := gicr_base + cpu_number * gicr_stride

	wake_redistributor(frame)
	configure_redistributor(frame)

	write_icc_pmr(0xFF) // Accept all priorities
	write_icc_bpr1(0) // No sub-priority bits
	write_icc_ctlr(0) // EOImode=0
	write_icc_igrpen1(1) // Enable Group 1 interrupts
	cpu.isb()
}

// Clear ProcessorSleep and wait for the redistributor to come out of it.
fn wake_redistributor(frame u64) {
	waker := frame_read32(frame, gicr_waker)
	if waker & 0x2 != 0 {
		frame_write32(frame, gicr_waker, waker & ~u32(0x2))
		for frame_read32(frame, gicr_waker) & 0x4 != 0 {
		}
	}
}

// The SGIs and PPIs this CPU is to receive: Group 1 Non-Secure, nothing left
// pending from the firmware, one priority for all of them, and the timer.
fn configure_redistributor(frame u64) {
	frame_write32(frame, gicr_igroupr0, u32(0xFFFFFFFF))
	frame_write32(frame, gicr_icpendr0, u32(0xFFFFFFFF))
	for off := u64(0); off < 32; off += 4 {
		frame_write32(frame, gicr_ipriorityr_base + off, u32(0xA0A0A0A0))
	}
	frame_write32(frame, gicr_isenabler0, u32(1) << 27 | u32(0xFFFF))
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
