// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov

module usercopy

fn C.vinix_ldar32(addr voidptr) u32
fn C.vinix_cas32(addr voidptr, expected u32, desired u32) u32

// The 32-bit word at `ptr`, read with acquire ordering.
fn word_load(ptr voidptr) u32 {
	return C.vinix_ldar32(ptr)
}

// Store `desired` at `ptr` if the word there is still `expected`; either way,
// return what it held.
fn word_cas(ptr voidptr, expected u32, desired u32) u32 {
	return C.vinix_cas32(ptr, expected, desired)
}
