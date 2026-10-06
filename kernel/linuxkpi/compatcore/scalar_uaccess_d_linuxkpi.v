// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

#include "linuxkpi_scalar_uaccess_v_contract.h"

fn C.vinix_linuxkpi_read_user_scalar(voidptr, usize, &u64) i32

// Ordinary scalar reads use the native faulting process-context contract.
// Both the user source and writable kernel result are synchronous borrows.
// The native helper preserves a single-width load within a physical page
// and publishes the scalar only after the complete read succeeds.
@[export: 'vinix_linuxkpi_get_user']
pub fn get_user_value(source voidptr, size usize, result voidptr) i32 {
	unsafe { C.memset(result, 0, 8) }
	if size != 1 && size != 2 && size != 4 && size != 8 {
		return -22
	}
	mut value := u64(0)
	status := C.vinix_linuxkpi_read_user_scalar(source, size, unsafe { &value })
	if status == 0 {
		unsafe { C.memcpy(result, &value, 8) }
	}
	return status
}
