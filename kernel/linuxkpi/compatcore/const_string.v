// SPDX-License-Identifier: GPL-2.0-only
// Conditional string ownership from Linux 6.6.157 mm/util.c.
@[translated]
module compatcore

#include "linuxkpi_const_string_v_primitives.h"

fn C.vinix_linuxkpi_is_kernel_rodata(&C.vks_const_void) bool

// Only the native image's real read-only-data interval is borrowed forever.
// Every other pointer retains the ordinary kfree ownership requirements.
@[export: 'vkc_kfree_const']
pub fn const_string_kfree(ptr voidptr) {
	if !C.vinix_linuxkpi_is_kernel_rodata(unsafe { &C.vks_const_void(ptr) }) {
		C.kfree(ptr)
	}
}

// Preserve Linux's pointer-identity fast path before consulting GFP flags.
// The existing checked kstrdup path owns both NULL and allocation failure.
@[export: 'vkc_kstrdup_const']
pub fn const_string_kstrdup(src voidptr, flags u32) voidptr {
	if C.vinix_linuxkpi_is_kernel_rodata(unsafe { &C.vks_const_void(src) }) {
		return src
	}
	return unsafe { voidptr(kstrdup(&char(src), flags)) }
}
