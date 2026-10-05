// SPDX-License-Identifier: GPL-2.0-or-later
module lib

#include <stack_slots.h>

// Compiler builtin, expanded in the caller. Never retain its result outside
// that function's synchronous call chain.
fn C.vinix_stack_alloc(bytes u64) voidptr
