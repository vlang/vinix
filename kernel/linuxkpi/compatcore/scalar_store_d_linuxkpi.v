// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

#include "linuxkpi_scalar_store_v_contract.h"

fn C.vinix_linuxkpi_write_user_scalar(voidptr, usize, u64) i32

// The C caller converts to its destination scalar type before passing bits.
// Ordinary split-page writes may commit a prefix before returning -EFAULT;
// no zeroing, rollback, atomic or pagefault-disabled contract is supplied.
@[export: 'vinix_linuxkpi_put_user']
pub fn put_user_value(destination voidptr, size usize, value u64) i32 {
	if size != 1 && size != 2 && size != 4 && size != 8 {
		return -22
	}
	return C.vinix_linuxkpi_write_user_scalar(destination, size, value)
}
