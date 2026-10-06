// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import usercopy
import linuxkpi.compatcore

@[export: 'vinix_linuxkpi_raw_copy_from_user_nocache']
fn native_nocache_from_user(destination voidptr, source voidptr, length u32) u32 {
	return u32(usercopy.raw_copy_from_user_nocache(destination, u64(source), u64(length)))
}

fn nocache_native_selftest() bool {
	return usercopy.nocache_selftest()
		&& compatcore.nocache_from_user(unsafe { nil }, voidptr(usize(-1)), 0) == 0
		&& compatcore.nocache_from_user(unsafe { nil }, voidptr(usize(-1)), u32(-1)) == -1
		&& compatcore.nocache_from_user(unsafe { nil }, voidptr(usize(-1)), 8) == 8
}
