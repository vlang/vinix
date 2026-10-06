// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import usercopy
import linuxkpi.compatcore

// Ordinary put_user stores can resolve missing or COW pages and therefore use
// the existing faulting process-context contract. Values are synchronous
// scalar arguments, with no borrowed kernel buffer or retained user pointer.
@[export: 'vinix_linuxkpi_write_user_scalar']
fn native_write_user_scalar(destination voidptr, size usize, value u64) i32 {
	require_usercopy_context()
	return if usercopy.write_scalar_user(u64(destination), u64(size), value) { 0 } else { -14 }
}

fn scalar_store_native_selftest() bool {
	if !usercopy.scalar_store_selftest() { return false }
	// Successful stores use the fixture's privately owned pagemaps. Exercise
	// the real exported frontend/bridge for checked fault and width errors.
	return compatcore.put_user_value(unsafe { nil }, 8, ~u64(0)) == -14
		&& compatcore.put_user_value(voidptr(usize(-1)), 3, ~u64(0)) == -22
}
