// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import usercopy
import linuxkpi.compatcore

#include "stack_slots.h"

fn C.vinix_stack_alloc(u64) voidptr

// This result is an eight-byte synchronous kernel borrow. The public frontend
// publishes it only after a complete ordinary faulting task-context read.
@[export: 'vinix_linuxkpi_read_user_scalar']
fn native_read_user_scalar(source voidptr, size usize, result &u64) i32 {
	require_usercopy_context()
	return if usercopy.read_scalar_user(u64(source), u64(size), result) { 0 } else { -14 }
}

fn scalar_uaccess_native_selftest() bool {
	if !usercopy.scalar_selftest() { return false }
	// Exercise the exported frontend/native bridge with actual fault and
	// invalid-width results. Successful page reads are measured above on the
	// fixture's independently owned, unpublished pagemaps.
	bits := C.vinix_stack_alloc(sizeof(u64))
	unsafe { *(&u64(bits)) = ~u64(0) }
	if compatcore.get_user_value(unsafe { nil }, 8, bits) != -14
		|| unsafe { *(&u64(bits)) } != 0 { return false }
	unsafe { *(&u64(bits)) = ~u64(0) }
	return compatcore.get_user_value(voidptr(usize(-1)), 3, bits) == -22
		&& unsafe { *(&u64(bits)) } == 0
}
