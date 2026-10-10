// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Reading a model-specific register on a particular CPU.
//
// A core's temperature is in a register of that core, and RDMSR reads the
// registers of the CPU it runs on. So the CPU that wants the value asks the
// one that has it: it posts a request, sends an interrupt, and waits for the
// answer -- for a bounded time, because a CPU that is spinning with its
// interrupts off, or that a hypervisor has set aside, answers late, and a
// temperature that arrives late is a failed reading, not a reason to hang.
//
// One request is in flight at a time. Its state is one word, a sequence
// number above three bits that say how far it has got, and every step is a
// compare-and-swap on that word: the asker posts, the target takes the
// request up, the target finishes or the asker gives up. An interrupt that
// arrives after its request was given up finds the word changed and does
// nothing; a target that was already reading when the asker gave up finds
// that out when it finishes, and returns the slot itself.
//
// The asker waits with its interrupts on. Unlike a TLB shootdown, it holds
// no lock another CPU may be spinning for.
@[has_globals]
module thermal

import devcore
import katomic
import klock
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt
import x86.msr

const cross_idle = u64(0)
const cross_posted = u64(1)
const cross_running = u64(2)
const cross_done = u64(3)
const cross_abandoned = u64(4)
const cross_phase = u64(7)

// How long a request waits for its turn, for its answer, and before the
// interrupt is sent a second time: one can go astray.
const cross_claim_ns = 50 * devcore.millisecond
const cross_answer_ns = 20 * devcore.millisecond
const cross_resend_ns = 5 * devcore.millisecond

__global (
	// 0 until cross_cpu_start(): there is then no other CPU to ask.
	thermal_cross_vector u8
	// A request is being made.
	thermal_cross_busy     u32
	thermal_cross_sequence u64
	thermal_cross_state    u64
	// The request, written before it is posted.
	thermal_cross_target u64
	thermal_cross_index  u32
	// The answer, written before it is marked done.
	thermal_cross_value u64
	thermal_cross_found bool
	// Requests given up, for x86_probe.
	thermal_cross_timeouts u64
)

// Take an interrupt vector for the requests. Called once, on a machine with
// more than one CPU.
fn cross_cpu_start() {
	if thermal_cross_vector != 0 || cpu_locals.len <= 1 {
		return
	}
	vector := idt.allocate_vector()
	interrupt_table[vector] = voidptr(cross_cpu_isr)
	thermal_cross_vector = vector
}

fn cross_cpu_isr(_ u32, _ &cpulocal.GPRState) {
	cross_cpu_answer()
	apic.lapic_eoi()
}

// Runs on the CPU the interrupt was sent to, with interrupts off.
fn cross_cpu_answer() {
	state := katomic.load(&thermal_cross_state)
	phase := state & cross_phase
	if phase != cross_posted {
		return
	}
	target := thermal_cross_target
	index := thermal_cross_index
	if cpulocal.current().cpu_number != target {
		return
	}
	// Taken up only if it is still the request `target` and `index` were
	// read for: nothing else may write those two while it is posted.
	sequence := state & ~cross_phase
	running := sequence | cross_running
	finished := sequence | cross_done
	if !katomic.cas(mut &thermal_cross_state, state, running) {
		return
	}
	mut value := u64(0)
	mut found := false
	if read := msr.read_safe(index) {
		value = read
		found = true
	}
	thermal_cross_value = value
	thermal_cross_found = found
	if !katomic.cas(mut &thermal_cross_state, running, finished) {
		// The asker gave up while this ran and left the slot to be returned.
		katomic.store(mut &thermal_cross_state, cross_idle)
		katomic.store(mut &thermal_cross_busy, u32(0))
	}
}

// How a read on another CPU ended.
enum CrossRead {
	// The register was read.
	found
	// That CPU has no such register, or there is no such CPU.
	absent
	// It did not answer in time: nothing is known.
	unanswered
}

// Read register `index` on CPU `cpu_number` into `value`. May sleep; not for
// interrupt handlers.
fn cross_read(cpu_number u64, index u32, value &u64) CrossRead {
	if cpu_number >= u64(cpu_locals.len) {
		return .absent
	}
	// With interrupts off this thread stays on the CPU it asks about.
	ints := cpu.interrupt_toggle(false)
	if cpulocal.current().cpu_number == cpu_number {
		mut found := false
		if read := msr.read_safe(index) {
			unsafe {
				*value = read
			}
			found = true
		}
		cpu.interrupt_toggle(ints)
		return if found { CrossRead.found } else { CrossRead.absent }
	}
	cpu.interrupt_toggle(ints)
	if thermal_cross_vector == 0 || katomic.load(&cpu_locals[cpu_number].online) == 0 {
		return .absent
	}

	claim := devcore.deadline(cross_claim_ns)
	for !katomic.cas(mut &thermal_cross_busy, u32(0), u32(1)) {
		if claim.expired() {
			katomic.inc(mut &thermal_cross_timeouts)
			return .unanswered
		}
		devcore.sleep_ms(1)
	}
	thermal_cross_sequence++
	sequence := thermal_cross_sequence << 3
	posted := sequence | cross_posted
	running := sequence | cross_running
	done := sequence | cross_done
	abandoned := sequence | cross_abandoned
	thermal_cross_target = cpu_number
	thermal_cross_index = index
	katomic.store(mut &thermal_cross_state, posted)
	lapic_id := cpu_locals[cpu_number].lapic_id
	apic.lapic_send_ipi(lapic_id, thermal_cross_vector)

	wait := devcore.deadline(cross_answer_ns)
	mut resent := false
	for katomic.load(&thermal_cross_state) != done {
		if wait.expired() {
			break
		}
		if !resent && wait.elapsed() >= cross_resend_ns {
			resent = true
			apic.lapic_send_ipi(lapic_id, thermal_cross_vector)
		}
		klock.spin_hint()
	}
	if katomic.load(&thermal_cross_state) != done {
		if katomic.cas(mut &thermal_cross_state, posted, cross_idle) {
			// Never taken up, and now it cannot be.
			katomic.store(mut &thermal_cross_busy, u32(0))
			katomic.inc(mut &thermal_cross_timeouts)
			return .unanswered
		}
		if katomic.cas(mut &thermal_cross_state, running, abandoned) {
			// The target is in the middle of it, and returns the slot.
			katomic.inc(mut &thermal_cross_timeouts)
			return .unanswered
		}
		// It finished between the two looks.
	}
	found := thermal_cross_found
	if found {
		unsafe {
			*value = thermal_cross_value
		}
	}
	katomic.store(mut &thermal_cross_state, cross_idle)
	katomic.store(mut &thermal_cross_busy, u32(0))
	return if found { CrossRead.found } else { CrossRead.absent }
}

// Register `index` as CPU `cpu_number` reads it. None when that CPU has no
// such register, and when it did not answer in time: either way there is no
// value, and a caller that reads a sensor counts both as a failed reading.
fn read_msr_on(cpu_number u64, index u32) ?u64 {
	mut value := u64(0)
	if cross_read(cpu_number, index, unsafe { &value }) != .found {
		return none
	}
	return value
}

// Whether CPU `cpu_number` has register `index`, and said so in time.
fn msr_readable_on(cpu_number u64, index u32) bool {
	mut value := u64(0)
	return cross_read(cpu_number, index, unsafe { &value }) == .found
}
