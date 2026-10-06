// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import lib
import memory
import usercopy
import linuxkpi.compatcore

@[export: 'vinix_linuxkpi_user_address_limit']
fn native_user_address_limit() usize {
	return usize(memory.user_address_limit())
}

fn require_usercopy_context() {
	// Disabled fault resolution permits resident-only copies even when the
	// ordinary faulting context is unavailable. The memory resolvers consult
	// this same task policy; changing it does not disable ordinary scheduling.
	if !memory.fault_resolution_disabled() && !may_sleep() {
		lib.kpanic(unsafe { nil }, c'linuxkpi: faulting user copy requires enabled interrupts and preemption')
	}
}

// Kernel buffers are synchronous borrows. The current syscall owns its
// process/pagemap; page acquisition independently retains its backing source.
@[export: 'vinix_linuxkpi_raw_copy_from_user']
fn native_raw_from_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	require_usercopy_context()
	return usize(usercopy.raw_copy_from_user(destination, u64(source), u64(length)))
}

@[export: 'vinix_linuxkpi_raw_copy_to_user']
fn native_raw_to_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	require_usercopy_context()
	return usize(usercopy.raw_copy_to_user(u64(destination), source, u64(length)))
}

@[export: 'vinix_linuxkpi_raw_copy_from_user_inatomic']
fn native_raw_from_user_inatomic(destination voidptr, source voidptr, length usize) usize {
	return usize(usercopy.raw_copy_from_user_inatomic(destination, u64(source), u64(length)))
}

@[export: 'vinix_linuxkpi_raw_copy_to_user_inatomic']
fn native_raw_to_user_inatomic(destination voidptr, source voidptr, length usize) usize {
	return usize(usercopy.raw_copy_to_user_inatomic(u64(destination), source, u64(length)))
}

fn uaccess_native_selftest() bool {
	if !usercopy.remaining_selftest() { return false }
	limit := usize(memory.user_address_limit())
	if !compatcore.user_access_ok(unsafe { nil }, 1)
		|| !compatcore.user_access_ok(voidptr(limit), 0)
		|| compatcore.user_access_ok(voidptr(limit), 1)
		|| compatcore.user_access_ok(voidptr(usize(-1)), 0)
		|| compatcore.user_access_ok(voidptr(limit - 1), 2) { return false }
	// Public access rejection clears the full destination, whereas object-size
	// rejection leaves it untouched. No invalid user pointer is dereferenced.
	mut bytes := [16]u8{}
	for i in 0 .. bytes.len { bytes[i] = 0xa5 }
	if compatcore.checked_copy_from_user(unsafe { &bytes[0] }, voidptr(limit), 16, 8) != 16 {
		return false
	}
	for byte in bytes { if byte != 0xa5 { return false } }
	if compatcore.checked_from_user(unsafe { &bytes[0] }, voidptr(limit), 16) != 16 {
		return false
	}
	for byte in bytes { if byte != 0 { return false } }
	// The zero-count fast paths also work with IRQs disabled and invalid
	// pointers. Restoring the original flags is required on every return path.
	flags := irq_save()
	from := native_raw_from_user(unsafe { nil }, voidptr(usize(-1)), 0)
	to := native_raw_to_user(voidptr(usize(-1)), unsafe { nil }, 0)
	irq_restore(flags)
	return from == 0 && to == 0
}
