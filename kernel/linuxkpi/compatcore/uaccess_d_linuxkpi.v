// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

#include "linuxkpi_uaccess_v_contract.h"

fn C.vinix_linuxkpi_user_address_limit() usize
fn C.vinix_linuxkpi_raw_copy_from_user(voidptr, voidptr, usize) usize
fn C.vinix_linuxkpi_raw_copy_to_user(voidptr, voidptr, usize) usize
fn C.vinix_linuxkpi_raw_copy_from_user_inatomic(voidptr, voidptr, usize) usize
fn C.vinix_linuxkpi_raw_copy_to_user_inatomic(voidptr, voidptr, usize) usize

// The native user half is exclusive. As in generic Linux access_ok, a zero
// size still checks the address, and NULL is a numerically valid user address.
// This check does not establish that pages are present or accessible.
@[export: 'vinix_linuxkpi_access_ok']
pub fn user_access_ok(address voidptr, length usize) bool {
	limit := C.vinix_linuxkpi_user_address_limit()
	return length <= limit && usize(address) <= limit - length
}

// Public header macros supply the kernel object's size from the callsite.
// Rejected sizes return without touching either buffer, including its tail.
@[export: 'vinix_linuxkpi_check_copy_size']
pub fn check_copy_size(known_size usize, length usize) bool {
	return length <= usize(2147483647)
		&& (known_size == usize(-1) || length <= known_size)
}

// Ordinary copies resolve pages only when the native task permits faults.
// A disabled scope preserves resident prefixes and suppresses page-in/COW.
// Explicit inatomic copies below use a resident-only native policy. NMI and
// nocache variants remain separate unsupported APIs.
@[export: 'raw_copy_from_user']
pub fn raw_from_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	return C.vinix_linuxkpi_raw_copy_from_user(destination, source, length)
}

@[export: 'raw_copy_to_user']
pub fn raw_to_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	return C.vinix_linuxkpi_raw_copy_to_user(destination, source, length)
}

@[export: '__copy_from_user']
pub fn unchecked_from_user(destination voidptr, source voidptr, length usize) usize {
	return raw_from_user(destination, source, length)
}

@[export: '__copy_to_user']
pub fn unchecked_to_user(destination voidptr, source voidptr, length usize) usize {
	return raw_to_user(destination, source, length)
}

@[export: '__copy_from_user_inatomic']
pub fn inatomic_from_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	return C.vinix_linuxkpi_raw_copy_from_user_inatomic(destination, source, length)
}

@[export: '__copy_to_user_inatomic']
pub fn inatomic_to_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	return C.vinix_linuxkpi_raw_copy_to_user_inatomic(destination, source, length)
}

@[export: '_copy_from_user']
pub fn checked_from_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	mut remaining := length
	if user_access_ok(source, length) {
		remaining = raw_from_user(destination, source, length)
	}
	if remaining != 0 {
		unsafe { C.memset(voidptr(usize(destination) + length - remaining), 0, remaining) }
	}
	return remaining
}

// Used by fixed-buffer kernel parsers, whose object bounds are known here.
pub fn checked_copy_from_user(destination voidptr, source voidptr, length usize, known_size usize) usize {
	if !check_copy_size(known_size, length) { return length }
	return checked_from_user(destination, source, length)
}

@[export: '_copy_to_user']
pub fn checked_copy_to_user(destination voidptr, source voidptr, length usize) usize {
	if length == 0 { return 0 }
	if !user_access_ok(destination, length) { return length }
	return raw_to_user(destination, source, length)
}
