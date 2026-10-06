// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

#include "linuxkpi_nocache_v_contract.h"

fn C.vinix_linuxkpi_raw_copy_from_user_nocache(voidptr, voidptr, u32) u32

// Preserve the pinned x86 unsigned-size/int-result ABI, including conversion
// of a large uncopied count to its signed bit pattern. This is never a zero-
// tail operation. The native bridge supplies real non-temporal stores.
@[export: '__copy_from_user_inatomic_nocache']
pub fn nocache_from_user(destination voidptr, source voidptr, length u32) i32 {
	if length == 0 { return 0 }
	return i32(C.vinix_linuxkpi_raw_copy_from_user_nocache(destination, source, length))
}
