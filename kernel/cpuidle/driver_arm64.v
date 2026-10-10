// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The idle state of an AArch64 CPU: WFI, wait for interrupt.
//
// sched.await() waits with interrupts masked and looks at the timer and the
// interrupt controller itself. WFI fits that loop without a gap: it returns
// when an interrupt is pending whether or not the CPU would take it, so one
// that arrives between the loop's last look and the WFI is not lost -- the
// WFI returns at once -- and the loop looks again. What this file adds, the
// choice and the two readings of the counter, sits between that look and the
// WFI with interrupts still masked, and changes none of it.
//
// Where it is used
//
// In a virtual machine, where the scheduler already used WFI: the virtual
// timer and the scheduler's SGI both wake it, and a host that parks an idle
// vCPU is the whole point.
//
// On physical Apple hardware the loop polls instead, as it did, and no state
// is offered. That is deliberate. The loop is also what polls the keyboard
// and trackpad there, and Apple's interrupt controller has no targeted
// interrupt this kernel can rely on to end a wait early. There is a second
// reason to hold back: an Apple core can lose its state in WFI. Whether it
// keeps its registers is selected in an implementation-defined system
// register, CYC_OVRD, and a core that drops them comes back at its reset
// vector rather than after the WFI. This kernel does not program that
// register, and its fields are not something to guess at.
//
// vinix.apple_idle=wfi on the command line uses WFI there all the same, for
// whoever is in a position to try it: the loop then polls its input once per
// wake, which the idle timer makes a thousand times a second, instead of
// continuously. It has not been run on hardware. It relies on the bootloader
// having left the cores in the retention mode, and on the timer's FIQ waking
// a WFI while masked.
module cpuidle

import katomic
import devcore
import sched
import aarch64.cpu

__global (
	cpuidle_started     bool
	cpuidle_wfi_allowed bool
)

// Whether the idle loop waits in WFI on this machine rather than polling.
// `virtual` is the scheduler's own knowledge that it runs in a virtual
// machine, which is where it has always used WFI.
@[inline]
pub fn waits(virtual bool) bool {
	return virtual || cpuidle_wfi_allowed
}

// One wait: until an interrupt is pending. Called with interrupts masked from
// the scheduler's idle loop, which looks at what woke it when this returns.
// `timer_us` is how far off the loop's own timer is.
pub fn idle_wait(cpu_number u64, timer_us u64) {
	if cpu_number >= max_cpus || katomic.load(&cpuidle_ready) == 0 {
		// Before the table exists: the instruction the loop always used.
		cpu.wfi()
		return
	}
	state := idle_pick(cpu_number, timer_us)
	if state == no_state {
		// WFI is switched off for this CPU, or the latency limit rules it
		// out: go round the loop again without stopping.
		asm volatile aarch64 {
			yield
			; ; ; memory
		}
		return
	}
	idle_begin(cpu_number, state, cpu.read_cntvct_el0())
	cpu.wfi()
	idle_account(cpu_number, cpu.read_cntvct_el0())
}

// Find this machine's states and put them to use. Once, from publish().
fn driver_start() {
	if cpuidle_started {
		return
	}
	cpuidle_started = true
	cpuidle_driver_name = 'none'
	if choice := devcore.boot_option('vinix.cpuidle=') {
		if choice == 'off' {
			print('cpuidle: switched off by vinix.cpuidle=off\n')
			return
		}
	}
	virtual := sched.idle_is_virtual()
	mut on_hardware := false
	if choice := devcore.boot_option('vinix.apple_idle=') {
		on_hardware = choice == 'wfi'
	}
	if !virtual && !on_hardware {
		print('cpuidle: no idle state on this hardware; the idle loop polls (vinix.apple_idle=wfi to try WFI)\n')
		return
	}
	if !virtual {
		print('cpuidle: WFI on physical hardware by vinix.apple_idle=wfi; untested\n')
	}
	cpuidle_tick_hz = cpu.read_cntfrq_el0()
	// Linux's figures for WFI on arm64 (drivers/cpuidle/dt_idle_states and
	// the ARM_CPUIDLE_WFI_STATE they all start with).
	add_state('WFI', 'ARM WFI', 1, 1, 0, 0)
	cpuidle_driver_name = 'wfi'
	C.kprintf(c'cpuidle: driver wfi, 1 state, counter %llu Hz\n', cpuidle_tick_hz)
	katomic.store(mut &cpuidle_ready, u32(1))
	// Only now: the loop must not find WFI allowed before the table is there
	// to count it in.
	cpuidle_wfi_allowed = on_hardware
}
