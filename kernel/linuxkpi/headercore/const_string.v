// SPDX-License-Identifier: GPL-2.0-only
// Original Linux const-qualified interfaces; ownership stays in compatcore.
@[translated]
module headercore

#include "linuxkpi_const_string_v_contract.h"

@[typedef]
struct C.vks_const_char {}

@[typedef]
struct C.vks_const_void {}

fn C.vkc_kfree_const(voidptr)
fn C.vkc_kstrdup_const(voidptr, u32) voidptr

@[export: 'kfree_const']
pub fn const_string_free(ptr &C.vks_const_void) {
	C.vkc_kfree_const(unsafe { voidptr(ptr) })
}

@[export: 'kstrdup_const']
pub fn const_string_dup(src &C.vks_const_char, flags u32) &C.vks_const_char {
	return unsafe { &C.vks_const_char(C.vkc_kstrdup_const(voidptr(src), flags)) }
}
