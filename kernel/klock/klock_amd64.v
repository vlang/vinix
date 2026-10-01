@[has_globals]
module klock

import katomic
import x86.cpu

__global (
	// Run by a CPU spinning for a lock. One spinning with interrupts off
	// cannot take the IPI of a TLB shootdown, and the CPU that sent it, which
	// may hold the lock, waits for it: this is how it answers. See
	// sched/tlb_amd64.v.
	spin_hook voidptr
)

type SpinHook = fn ()

// C compatibility locks need the same shootdown progress as native locks.
pub fn spin_hint() {
	if spin_hook != unsafe { nil } {
		hook := unsafe { SpinHook(spin_hook) }
		hook()
	}
	asm volatile amd64 {
		pause
		; ; ; memory
	}
}

pub fn register_spin_hook(hook voidptr) {
	spin_hook = hook
}

pub struct Lock {
pub mut:
	l    bool
	ints bool
}

fn C.__builtin_return_address(int) voidptr

pub fn (mut l Lock) acquire() {
	for {
		if l.test_and_acquire() == true {
			return
		}
		spin_hint()
	}
}

pub fn (mut l Lock) release() {
	// Snapshot before unlocking: another CPU can then overwrite l.ints.
	// Keep the same ordering as the ARM64 implementation.
	ints := l.ints
	katomic.store(mut &l.l, false)
	cpu.interrupt_toggle(ints)
}

// Peek at the lock without taking it. The scheduler's run-queue scan needs to
// look past the threads other CPUs are already running -- a running thread
// stays in the queue holding its own lock -- to reach the one this CPU should
// pick, and it cannot find that out by taking every lock it looks at.
pub fn (l &Lock) is_held() bool {
	return katomic.load(&l.l)
}

pub fn (mut l Lock) test_and_acquire() bool {
	ints := cpu.interrupt_toggle(false)

	ret := katomic.cas(mut &l.l, false, true)
	if ret == true {
		l.ints = ints
	} else {
		cpu.interrupt_toggle(ints)
	}

	return ret
}
