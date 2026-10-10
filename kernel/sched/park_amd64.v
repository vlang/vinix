// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Taking processors out of the scheduler, for a sleep that powers them down.
//
// Before a suspend to RAM every processor but the one that carries it out
// has to be doing nothing that will be missed: firmware resumes one
// processor, and the others come back as if they had just been switched on.
// A processor that is idle in this scheduler holds nothing -- no thread, no
// lock, a stack it starts again from the top every time it is entered -- so
// parking one is making it idle and keeping it there:
//
//   - may_run_here() says no to every thread on a parking processor, which
//     is the question the run-queue scan, the placement of a woken thread and
//     the timer interrupt already ask. The thread it was running is put down
//     at its next scheduler interrupt exactly as one whose affinity changed
//     is, and the keeper picks it up;
//   - with nothing to run it reaches await(), which, instead of halting until
//     the next interrupt, takes the processor offline -- no shootdown, wake
//     or placement counts on it from then on -- runs the hook the platform
//     registered, and halts with interrupts off for good.
//
// It does not come back by being woken. The platform starts it again from
// real mode (x86/wake), whether the machine slept or not, and it re-enters
// the idle loop through enter_idle() as it did at boot.
@[has_globals]
module sched

import katomic
import x86.apic
import x86.cpu.local as cpulocal

__global (
	// Nonzero while every processor but the keeper is to park.
	sched_parking     u32
	sched_park_keeper u64
	// Called on a processor as it parks, offline, with interrupts off.
	sched_park_hook voidptr
)

type ParkHook = fn (cpu_number u64)

pub fn set_park_hook(hook voidptr) {
	sched_park_hook = hook
}

// Whether `cpu_number` is to stop running threads.
@[inline]
fn parking(cpu_number u64) bool {
	return katomic.load(&sched_parking) != 0 && cpu_number != katomic.load(&sched_park_keeper)
}

// Send every processor but `keeper` to park. The caller runs on `keeper`,
// stays there, and waits for the hook to have run on each of the others.
pub fn park_others(keeper u64) {
	katomic.store(mut &sched_park_keeper, keeper)
	katomic.store(mut &sched_parking, u32(1))
	for entry in cpu_locals {
		if entry.cpu_number != keeper {
			wake_cpu(u32(entry.cpu_number))
		}
	}
}

// Threads may run everywhere again. The parked processors themselves are
// started by the platform.
pub fn end_parking() {
	katomic.store(mut &sched_parking, u32(0))
}

// The end of this processor's part in the scheduler until it is started
// again. Interrupts off, no thread, on a stack of the processor's own.
@[noreturn]
fn park_here(mut cpu_local cpulocal.Local) {
	apic.lapic_timer_stop()
	// A shootdown counts the processors it asks while it holds this lock,
	// and waits for each of them: go offline between two of them, not in
	// the middle of one.
	for !tlb_lock.test_and_acquire() {
		answer_tlb_shootdown()
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}
	katomic.store(mut &cpu_local.online, u64(0))
	tlb_lock.release()
	if sched_park_hook != unsafe { nil } {
		hook := unsafe { ParkHook(sched_park_hook) }
		hook(cpu_local.cpu_number)
	}
	for {
		asm volatile amd64 {
			cli
			hlt
			; ; ; memory
		}
	}
}
