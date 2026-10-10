// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module syspower

import aarch64.cpu
import aarch64.wdt
import apple.ans

// Apple's NVMe is not a device-core driver. Its orderly shutdown marks the
// data volume clean as well, so it is done first, and a controller that will
// not shut down refuses the transition as a failed flush does.
fn platform_prepare() bool {
	return ans.shutdown()
}

// PSCI where there is firmware to answer it: every virtual machine. An Apple
// machine has none for this, and switching one off is the SMC's business,
// which this kernel cannot yet ask.
fn platform_power_off() {
	cpu.psci_call(cpu.psci_system_off)
}

// An Apple SoC is restarted through its watchdog; there is no firmware call
// for it. Everything else has PSCI.
fn platform_restart() {
	if wdt.present() {
		wdt.restart()
	}
	cpu.psci_call(cpu.psci_system_reset)
}

fn platform_halt() {
	cpu.interrupt_toggle(false)
	for {
		cpu.wfi()
	}
}
