// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Reading and writing a model-specific register that may not exist.
//
// rdmsr() and wrmsr() are for registers the kernel knows are there: one that
// is not raises #GP, and a #GP in the kernel is a panic. A driver that has to
// ask -- is there a temperature sensor, an energy counter -- uses these
// instead, which say no where the others would stop the machine.
//
// The instructions are in asm/x86_64/msr_safe.S. The #GP handler asks
// fault_resume() about every kernel #GP before it gives up on it.
module msr

fn C.x86_rdmsr_safe(index u32, value &u64) bool
fn C.x86_wrmsr_safe(index u32, value u64) bool
fn C.x86_rdmsr_safe_insn()
fn C.x86_rdmsr_safe_fault()
fn C.x86_wrmsr_safe_insn()
fn C.x86_wrmsr_safe_fault()

// The value of register `index`, or none if this CPU has no such register.
pub fn read_safe(index u32) ?u64 {
	mut value := u64(0)
	if !C.x86_rdmsr_safe(index, unsafe { &value }) {
		return none
	}
	return value
}

// Write `value` to register `index`. False if this CPU has no such register,
// or refuses the value: a reserved bit set, a register that is read-only.
pub fn write_safe(index u32, value u64) bool {
	return C.x86_wrmsr_safe(index, value)
}

// Where a #GP raised by the instruction at `rip` carries on, or 0 when the
// instruction is not one of the two above and the fault is someone else's.
pub fn fault_resume(rip u64) u64 {
	if rip == u64(voidptr(C.x86_rdmsr_safe_insn)) {
		return u64(voidptr(C.x86_rdmsr_safe_fault))
	}
	if rip == u64(voidptr(C.x86_wrmsr_safe_insn)) {
		return u64(voidptr(C.x86_wrmsr_safe_fault))
	}
	return 0
}
