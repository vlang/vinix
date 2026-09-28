// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov

module usercopy

// The 32-bit word at `ptr`. An aligned load is atomic on x86-64, and x86 does
// not reorder it with later loads.
fn word_load(ptr voidptr) u32 {
	return unsafe { *&u32(ptr) }
}

// Store `desired` at `ptr` if the word there is still `expected`; either way,
// return what it held. cmpxchg leaves the old value in eax.
fn word_cas(ptr voidptr, expected u32, desired u32) u32 {
	mut previous := expected
	mut target := unsafe { &u32(ptr) }
	asm volatile amd64 {
		lock cmpxchg target, desired
		; +a (previous)
		  +m (*target) as target
		; r (desired)
		; memory
	}
	return previous
}
