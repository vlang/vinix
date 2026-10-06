// SPDX-License-Identifier: GPL-2.0-or-later
// Compiled separately so unused 128-bit Linux operations retain dormant linkage.
@[translated]
module exchange128core

fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.__atomic_exchange_n(&u128, u128, i32) u128
fn C.__atomic_compare_exchange_n(&u128, &u128, u128, bool, i32, i32) bool

@[export: 'vinix_arch_exchange_128']
pub fn exchange(storage voidptr, value voidptr, result voidptr) {
	unsafe {
		mut next := u128(0)
		C.memcpy(&next, value, 16)
		mut old := C.__atomic_exchange_n(&u128(storage), next, 0)
		C.memcpy(result, &old, 16)
	}
}

@[export: 'vinix_arch_compare_exchange_128']
pub fn compare_exchange(storage voidptr, expected voidptr, value voidptr, result voidptr) {
	unsafe {
		mut old := u128(0)
		mut next := u128(0)
		C.memcpy(&old, expected, 16)
		C.memcpy(&next, value, 16)
		C.__atomic_compare_exchange_n(&u128(storage), &old, next, false, 0, 0)
		C.memcpy(result, &old, 16)
	}
}
