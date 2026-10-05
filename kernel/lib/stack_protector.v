// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module lib

#include "stack_protector.h"

// The compiler uses this native-word symbol for global stack protection.
// It must have its placeholder before any V runtime initialization runs.
@[cinit]
@[export: '__stack_chk_guard']
__global stack_chk_guard = usize(0x595e9fbd94fda700)

@[noreturn]
@[export: '__stack_chk_fail']
fn stack_chk_fail() {
	kpanic(unsafe { nil }, charptr(c'stack protector: a stack frame was overwritten past its buffers'))
}

fn stack_mix64(value u64) u64 {
	mut mixed := value
	mixed ^= mixed >> 30
	mixed *= u64(0xbf58476d1ce4e5b9)
	mixed ^= mixed >> 27
	mixed *= u64(0x94d049bb133111eb)
	mixed ^= mixed >> 31
	return mixed
}

// The declarations in stack_protector.h give this body and its ABI wrapper
// no_stack_protector. Changing the guard under a protected frame would make
// that frame's own return fail. Only the boot CPU calls it, before SMP starts.
@[export: 'vinix_stack_guard_init']
fn stack_guard_init() {
	mut guard := stack_boot_entropy()
	// Borrow the address of the stack local without moving it to the heap.
	guard ^= u64(usize(unsafe { &guard }))
	guard = stack_mix64(guard ^ u64(stack_chk_guard))
	// A NUL low byte stops string overflows at the first canary byte.
	stack_chk_guard = usize(guard & ~u64(0xff))
}
