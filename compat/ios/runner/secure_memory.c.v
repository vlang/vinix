// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.__atomic_store_n(&u8, u8, i32)

// Darwin's Annex K entry returns errno_t directly without changing errno.
// Relaxed byte stores retain the required observable overwrite even when the
// optimizer proves that the caller never reads the destination again.
fn darwin_memset_s(destination voidptr, maximum usize, fill i32, count usize) i32 {
	if destination == unsafe { nil } { return 22 }
	limit := usize(u64(-1) >> 1)
	if maximum > limit { return 7 }
	mut result := i32(0)
	if count > limit { result = 7 }
	mut length := count
	if length > maximum {
		length = maximum
		if result == 0 { result = 84 }
	}
	for i in usize(0) .. length {
		C.__atomic_store_n(unsafe { &u8(usize(destination) + i) }, u8(fill), 0)
	}
	return result
}
