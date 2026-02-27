module klock

// AArch64 spinlock implementation using WFE for power-efficient spinning.
// This file provides the same API as klock_amd64.v but for ARM64.
// The build system selects between this and the x86 version.
//
// IMPORTANT: Lock.l must be u64 (not u32). V's inline asm generates 64-bit
// register operands (X registers) for CAS and STLR even when the V type is u32.
// This causes 8-byte atomic ops on a 4-byte field, corrupting the adjacent
// `ints` field. Using u64 makes the field size match the actual operation width.

import katomic
import aarch64.cpu

pub struct Lock {
pub mut:
	l    u64
	ints bool
}

pub fn (mut l Lock) acquire() {
	for {
		if l.test_and_acquire() == true {
			return
		}
		asm volatile aarch64 {
			wfe
			; ; ; memory
		}
	}
}

pub fn (mut l Lock) release() {
	katomic.store(mut &l.l, u64(0))
	// Send event to wake up any WFE-spinning CPUs
	asm volatile aarch64 {
		sev
		; ; ; memory
	}
	cpu.interrupt_toggle(l.ints)
}

pub fn (mut l Lock) test_and_acquire() bool {
	ints := cpu.interrupt_toggle(false)

	ret := katomic.cas(mut &l.l, u64(0), u64(1))
	if ret == true {
		l.ints = ints
	} else {
		cpu.interrupt_toggle(ints)
	}

	return ret
}
