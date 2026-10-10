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
// MWAIT
//
// A state entered with MWAIT has two forms, and which a state uses is
// decided once, in mwait_table_amd64.v.
//
// Where the processor can treat a masked interrupt as a reason to wake
// (CPUID.5:ECX[1]) the wait is made with interrupts off throughout:
//
//	cli ... monitor; look again; mwait with ECX[0] = 1 ... note the time; sti
//
// An interrupt that is pending when MWAIT executes, or becomes pending while
// it waits, ends it although it cannot be delivered yet; it is delivered at
// the STI. Nothing can slip in between the look and the wait, because nothing
// is delivered at all until the wait is over. "Look again" is the scheduler's
// own note that a reschedule interrupt is on its way to this CPU: with that
// set there is no point in stopping, and the state is counted as rejected.
// The deep states are entered this way and only this way, as intel_idle
// enters them.
//
// Without that bit MWAIT is used as it was first defined, no hints and no
// extensions, and exactly as HLT is: `monitor; sti; mwait`. The STI again
// takes effect only after the instruction behind it, and a pending interrupt
// that is no longer masked ends an MWAIT as it ends a HLT.
//
// MONITOR needs an address to watch, and gets a word of this CPU's record
// that nothing writes: wake-ups stay what they were, interrupts. The address
// only has to be valid.
//
// On the command line
//
//	vinix.cpuidle=off     no driver: the scheduler idles as it did before
//	vinix.cpuidle=halt    HLT even where MWAIT would be used
//	vinix.cpuidle=mwait   MWAIT for C1 although CPUID enumerates no C1
//	                      sub-state; for trying the MWAIT path in an emulator
//	vinix.max_cstate=N    offer only the first N states
//
// Under QEMU's emulation (-accel tcg) the default is HLT although MONITOR is
// advertised, and has to be: its MWAIT does not wait when the machine has more
// than one CPU, so an idle CPU would spin, and it faults on ECX[0] = 1 while
// advertising the interrupt-break bit. Its CPUID leaf 5 enumerates no C1
// sub-state, which is the case mwait_table() answers with HLT, as Linux does.
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
// A masked MWAIT is the exception: it returns here before any handler has run,
// so its time is taken on the spot and is exact.
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
		flags := cpuidle_states[state].flags
		if flags & state_mwait == 0 {
			idle_begin(cpu_number, state, now)
			asm volatile amd64 {
				sti
				hlt
				cli
				; ; ; memory
			}
			continue
		}
		hint := cpuidle_states[state].hint
		monitor_arm(&cpuidle_cpus[cpu_number].watched)
		if flags & state_masked == 0 {
			// MWAIT in HLT's place, EAX and ECX both zero.
			idle_begin(cpu_number, state, now)
			unmasked := u32(0)
			asm volatile amd64 {
				sti
				mwait
				cli
				; ; a (hint)
				  c (unmasked)
				; memory
			}
			continue
		}
		if katomic.load(wake_pending) != 0 {
			// A reschedule interrupt is already on its way here. Let it in
			// instead of stopping, as for the case with no state at all.
			idle_reject(cpu_number, state)
			asm volatile amd64 {
				sti
				pause
				cli
				; ; ; memory
			}
			continue
		}
		idle_begin(cpu_number, state, now)
		break_on_interrupt := u32(1)
		asm volatile amd64 {
			mwait
			; ; a (hint)
			  c (break_on_interrupt)
			; memory
		}
		idle_account(cpu_number, cpu.rdtsc())
		// Now the interrupt that ended it. STI holds it back for one more
		// instruction, so there has to be one before the CLI: `sti; cli`
		// would let nothing in.
		asm volatile amd64 {
			sti
			nop
			cli
			; ; ; memory
		}
	}
}

// Arm MONITOR on `address`, with no extensions and no hints.
@[inline]
fn monitor_arm(address voidptr) {
	extensions := u32(0)
	hints := u32(0)
	asm volatile amd64 {
		monitor
		; ; a (address)
		  c (extensions)
		  d (hints)
		; memory
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

	mut described := describe_cpu()
	if choice := devcore.boot_option('vinix.cpuidle=') {
		if choice == 'halt' {
			described.monitor = false
		} else if choice == 'mwait' {
			described.forced = true
		}
	}
	if limit := devcore.boot_option('vinix.max_cstate=') {
		described.limit = small_number(limit)
	}
	table := mwait_table(described)
	for i in 0 .. table.count {
		s := table.states[i]
		add_state(s.name, s.desc, s.exit_latency_us, s.target_residency_us, s.hint, s.flags)
	}
	cpuidle_driver_name = table.driver
	C.kprintf(c'cpuidle: driver %s, %llu states (%s), TSC %llu Hz\n', table.driver.str,
		u64(cpuidle_state_count), table.reason.str, hz)
	katomic.store(mut &cpuidle_ready, u32(1))
}

// What CPUID says about this processor's idle states. Read on the CPU that
// publishes /sys and taken to hold for all of them, as intel_idle takes the
// boot CPU's.
fn describe_cpu() MwaitCpu {
	mut c := MwaitCpu{}
	_, _, vendor_b, vendor_c, vendor_d := cpu.cpuid(0, 0)
	// "GenuineIntel" and "AuthenticAMD", four letters a register.
	c.intel = vendor_b == 0x756e6547 && vendor_d == 0x49656e69 && vendor_c == 0x6c65746e
	c.amd = vendor_b == 0x68747541 && vendor_d == 0x69746e65 && vendor_c == 0x444d4163
	_, signature, _, features, _ := cpu.cpuid(1, 0)
	c.family = (signature >> 8) & 0xf
	c.model = (signature >> 4) & 0xf
	if c.family == 0xf {
		c.family += (signature >> 20) & 0xff
	}
	if c.family == 6 || c.family >= 0xf {
		c.model += ((signature >> 16) & 0xf) << 4
	}
	c.monitor = features & (u32(1) << 3) != 0
	leaf5, _, _, extensions, substates := cpu.cpuid(5, 0)
	c.leaf5 = leaf5
	c.extensions = extensions
	c.substates = substates
	leaf6, thermal, _, _, _ := cpu.cpuid(6, 0)
	c.arat = leaf6 && thermal & (u32(1) << 2) != 0
	advanced, _, _, _, power := cpu.cpuid(0x80000007, 0)
	c.nonstop_tsc = advanced && power & (u32(1) << 8) != 0
	return c
}

// A command-line value as a small number: 0 for anything that is not one.
fn small_number(text string) int {
	mut value := 0
	for i in 0 .. text.len {
		if text[i] < `0` || text[i] > `9` || value > 1000 {
			return 0
		}
		value = value * 10 + int(text[i] - `0`)
	}
	return value
}
