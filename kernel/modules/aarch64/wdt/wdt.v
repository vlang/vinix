@[has_globals]
module wdt

// Apple SoC watchdog (compatible "apple,wdt", t8103: 0x23d2b0000).
//
// U-Boot arms this with a ~60 s timeout and services it while it runs. After
// ExitBootServices nothing does, so the SoC resets about a minute into the
// kernel -- a working Vinix boot on the M1 rebooted into macOS at the shell
// prompt for exactly that reason. The kernel has no periodic service task yet,
// so the watchdog is switched off; re-arming it under kernel control is the
// eventual right answer.
//
// Register layout as in Linux drivers/watchdog/apple_wdt.c. Two instances;
// WD1 is the one the firmware and Linux use. The counters run at the 24 MHz
// reference clock.

import aarch64.kio
import memory

const wd0_cur_time = u32(0x00)
const wd0_bite_time = u32(0x04)
const wd0_ctrl = u32(0x0c)
const wd1_cur_time = u32(0x10)
const wd1_bite_time = u32(0x14)
const wd1_ctrl = u32(0x1c)

const ctrl_irq_en = u32(1) << 0
const ctrl_irq_status = u32(1) << 1
const ctrl_reset_en = u32(1) << 2

__global (
	wdt_base = u64(0)
)

fn rd(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(wdt_base + offset) })
}

fn wr(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(wdt_base + offset) }, value)
}

// Map the watchdog and disarm both instances. Reports what the firmware left
// armed, so the boot log records how long the machine had before resetting.
pub fn initialise(base u64) {
	wdt_base = memory.map_mmio(base, 0x4000)

	ctrl1 := rd(wd1_ctrl)
	bite1 := rd(wd1_bite_time)
	cur1 := rd(wd1_cur_time)
	ctrl0 := rd(wd0_ctrl)
	println('wdt: Apple watchdog at 0x${base:x}: wd1 ctrl=0x${ctrl1:x} bite=${bite1} cur=${cur1} (24 MHz ticks), wd0 ctrl=0x${ctrl0:x}')

	if ctrl1 & ctrl_reset_en != 0 {
		secs := (bite1 - cur1) / 24000000
		println('wdt: firmware left wd1 armed to reset in ~${secs} s; disarming')
	}

	// Clearing RESET_EN (and the IRQ enable) stops the countdown from having
	// any effect; the counter itself is also reset so a later re-arm starts
	// from zero.
	wr(wd1_ctrl, 0)
	wr(wd1_cur_time, 0)
	wr(wd0_ctrl, 0)
	wr(wd0_cur_time, 0)

	println('wdt: disarmed (wd1 ctrl now 0x${rd(wd1_ctrl):x})')
}

// Service the watchdog (for a future periodic task); a no-op while disarmed.
pub fn pet() {
	if wdt_base == 0 {
		return
	}
	wr(wd1_cur_time, 0)
}
