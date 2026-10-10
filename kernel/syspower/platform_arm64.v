// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module syspower

import aarch64.cpu
import aarch64.firmware
import aarch64.kio
import aarch64.wdt
import apple.ans
import devcore
import lib
import memory
import sched

// The power button bit of QEMU's event register.
const qemu_event_power_down = u32(2)
// How often the register is looked at. No device on this architecture has an
// interrupt of its own yet, and a button need not be answered faster.
const qemu_event_poll_ms = u64(200)

__global (
	syspower_qemu_events u64
)

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

// A virtual machine's power button: what the host's "shut down" presses.
fn qemu_events() {
	for {
		devcore.sleep_ms(qemu_event_poll_ms)
		raised := kio.mmin32(unsafe { &u32(syspower_qemu_events) })
		if raised & qemu_event_power_down != 0 {
			button(.power)
		}
	}
}

fn platform_start() {
	base := firmware.qemu_event_register() or { return }
	syspower_qemu_events = memory.map_mmio(base, 0x1000)
	if syspower_qemu_events == 0 {
		return
	}
	sched.new_kernel_thread(voidptr(qemu_events), unsafe { nil }, true)
	C.kprintf(c'syspower: power button through the event device at 0x%llx\n', base)
}

// No machine this runs on has a suspend to RAM the kernel can ask for.
fn platform_deep_available() bool {
	return false
}

fn platform_deep_sleep() bool {
	return false
}

fn platform_deep_reason() string {
	return 'no machine this kernel runs on has a suspend to RAM it can ask for'
}

fn platform_deep_failure() string {
	return ''
}

fn platform_deep_blocker() &devcore.Device {
	return unsafe { nil }
}

fn platform_deep_report(mut _ lib.Text) {
}
