// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Idle states on x86-64, and the loop an idle CPU waits in.
//
// What must not be broken
//
// A CPU goes idle when its run queue is empty, and is given work by another
// CPU or by a device, in both cases with an interrupt: the scheduler's vector,
// sent as an IPI or raised by the local APIC timer the scheduler armed before
// idling. Nothing else wakes it -- there is no flag it looks at -- so the one
// thing the idle loop has to get right is that an interrupt which arrives at
// any moment ends the wait. It may never arrive just before the CPU stops and
// find nobody listening.
//
// sched.await() has always done this with `sti; hlt`. Interrupts are off while
// the timer is armed; STI does not take effect until the instruction after it
// has run, so an interrupt that became pending while they were off is taken
// with HLT already executed, and ends it. There is no instruction boundary at
// which interrupts are on and the CPU has not yet halted.
//
// The loop below keeps that sequence and wraps it:
//
//	cli ... choose a state, note the time ... sti; hlt; cli ...
//
// Everything this file adds runs in the stretches where interrupts are off. An
// interrupt that becomes pending there stays pending until the STI, which is
// still followed at once by the HLT.
//
// Who closes the books
//
// The interrupt that ends an idle usually does not come back: the scheduler's
// handler finds a thread and resumes it, or finds none and calls await()
// afresh on its own stack, and this loop is abandoned where it stood. So the
// time is taken at the top of that handler (idle_interrupted()), not after the
// HLT. Any other interrupt -- a device's, a TLB shootdown -- returns here, and
// the next turn of the loop closes the idle it ended before it starts another.
// Both run with interrupts off on the CPU the record belongs to, so they never
// meet.
module cpuidle

import katomic
import devcore
import x86.cpu
import x86.hpet as hpet_clock

__global (
	cpuidle_started bool
)

// Close the idle this CPU's interrupt has just ended. For the scheduler's
// interrupt handler, first thing, with interrupts off.
@[inline]
pub fn idle_interrupted(cpu_number u64) {
	if cpu_number < max_cpus && cpuidle_cpus[cpu_number].open != 0 {
		idle_account(cpu_number, cpu.rdtsc())
	}
}

// Wait for an interrupt in the states the driver found, for an idle the
// scheduler's timer ends in `timer_us`. Called with interrupts off and the
// timer armed, and does not return: see the top of this file. It returns at
// once, for the caller to wait as it used to, only for a CPU it keeps no
// record for.
//
// `wake_pending` is the scheduler's note that this CPU has been sent a
// reschedule interrupt it has not taken yet.
pub fn idle_loop(cpu_number u64, timer_us u64, wake_pending &u32) {
	if cpu_number >= max_cpus {
		return
	}
	hz := cpuidle_tick_hz
	span := us_to_ticks(timer_us, hz)
	start := cpu.rdtsc()
	deadline := if span > no_limit - start { no_limit } else { start + span }
	for {
		// Interrupts are off here on every turn.
		now := cpu.rdtsc()
		// An interrupt whose handler came back ended the last wait.
		idle_account(cpu_number, now)
		remaining := if deadline > now { ticks_to_us(deadline - now, hz) } else { u64(0) }
		state := idle_pick(cpu_number, remaining)
		if state == no_state {
			// Every state is switched off, or the latency limit rules them
			// all out: wait without stopping. The interrupt is taken after
			// the PAUSE, which is the instruction STI holds it back for.
			asm volatile amd64 {
				sti
				pause
				cli
				; ; ; memory
			}
			continue
		}
		idle_begin(cpu_number, state, now)
		asm volatile amd64 {
			sti
			hlt
			cli
			; ; ; memory
		}
	}
}

// The TSC's rate, against the kernel's nanosecond clock over 10 ms. Both keep
// counting while a virtual CPU is set aside, so their ratio holds; interrupts
// are off so that the two readings at each end are taken together.
fn measure_tick_hz() u64 {
	ints := cpu.interrupt_toggle(false)
	start_ns := hpet_clock.nanoseconds()
	start_tick := cpu.rdtsc()
	for hpet_clock.nanoseconds() - start_ns < 10000000 {}
	elapsed := hpet_clock.nanoseconds() - start_ns
	ticks := cpu.rdtsc() - start_tick
	cpu.interrupt_toggle(ints)
	if elapsed == 0 {
		return 0
	}
	return ticks * 1000000000 / elapsed
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
	mut hz := measure_tick_hz()
	if hz < 1000000 {
		// No TSC this slow exists. Counts stay right; times are a guess.
		C.kprintf(c'cpuidle: implausible TSC rate %llu Hz; assuming 1 GHz\n', hz)
		hz = 1000000000
	}
	cpuidle_tick_hz = hz

	// What every x86-64 processor has. Linux's figures for a C1 entered by
	// HLT (drivers/acpi/processor_idle.c): out again in a microsecond.
	add_state('C1', 'HLT', 1, 1, 0, 0)
	cpuidle_driver_name = 'halt'

	C.kprintf(c'cpuidle: driver %s, %llu states, TSC %llu Hz\n', cpuidle_driver_name.str,
		u64(cpuidle_state_count), hz)
	katomic.store(mut &cpuidle_ready, u32(1))
}
