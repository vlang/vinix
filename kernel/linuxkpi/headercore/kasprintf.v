// SPDX-License-Identifier: GPL-2.0-only
// Genuine original va_list and const-qualified Linux allocation interfaces.
@[translated]
module headercore

#include "linuxkpi_kasprintf_v_contract.h"

@[typedef]
struct C.vkf_native_va {}

fn C.vkf_va_parameter(C.vkf_native_va) voidptr
fn C.vkf_kvasprintf(u32, voidptr, voidptr) voidptr
fn C.vkf_kvasprintf_const(u32, voidptr, voidptr) voidptr

@[export: 'kvasprintf']
pub fn format_alloc_vasprintf(flags u32, fmt &C.vks_const_char, ap C.vkf_native_va) &char {
	return unsafe { &char(C.vkf_kvasprintf(flags, voidptr(fmt), C.vkf_va_parameter(ap))) }
}

@[export: 'kvasprintf_const']
pub fn format_alloc_vasprintf_const(flags u32, fmt &C.vks_const_char, ap C.vkf_native_va) &C.vks_const_char {
	return unsafe { &C.vks_const_char(C.vkf_kvasprintf_const(flags, voidptr(fmt), C.vkf_va_parameter(ap))) }
}
