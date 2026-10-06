// SPDX-License-Identifier: GPL-2.0-or-later
// Generic Linux exchange operations on borrowed native integer/pointer storage.
@[translated]
module exchangecore

fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.__builtin_trap()

@[c: '__atomic_exchange_n']
fn C.vhx_exchange8(&u8, u8, i32) u8
@[c: '__atomic_exchange_n']
fn C.vhx_exchange16(&u16, u16, i32) u16
@[c: '__atomic_exchange_n']
fn C.vhx_exchange32(&u32, u32, i32) u32
@[c: '__atomic_exchange_n']
fn C.vhx_exchange64(&u64, u64, i32) u64
@[c: '__atomic_compare_exchange_n']
fn C.vhx_compare8(&u8, &u8, u8, bool, i32, i32) bool
@[c: '__atomic_compare_exchange_n']
fn C.vhx_compare16(&u16, &u16, u16, bool, i32, i32) bool
@[c: '__atomic_compare_exchange_n']
fn C.vhx_compare32(&u32, &u32, u32, bool, i32, i32) bool
@[c: '__atomic_compare_exchange_n']
fn C.vhx_compare64(&u64, &u64, u64, bool, i32, i32) bool

// All input and result records retain the caller's exact native object width.
// No pointer or signed integer is narrowed through a numeric conversion.
@[export: 'vinix_arch_exchange_bits']
pub fn exchange(storage voidptr, value voidptr, result voidptr, width usize) {
	unsafe {
		match width {
			1 {
				mut next := u8(0)
				C.memcpy(&next, value, 1)
				mut old := C.vhx_exchange8(&u8(storage), next, 0)
				C.memcpy(result, &old, 1)
			}
			2 {
				mut next := u16(0)
				C.memcpy(&next, value, 2)
				mut old := C.vhx_exchange16(&u16(storage), next, 0)
				C.memcpy(result, &old, 2)
			}
			4 {
				mut next := u32(0)
				C.memcpy(&next, value, 4)
				mut old := C.vhx_exchange32(&u32(storage), next, 0)
				C.memcpy(result, &old, 4)
			}
			8 {
				mut next := u64(0)
				C.memcpy(&next, value, 8)
				mut old := C.vhx_exchange64(&u64(storage), next, 0)
				C.memcpy(result, &old, 8)
			}
			else { C.__builtin_trap() }
		}
	}
}

@[export: 'vinix_arch_compare_exchange_bits']
pub fn compare_exchange(storage voidptr, expected voidptr, value voidptr, result voidptr, width usize) {
	unsafe {
		match width {
			1 {
				mut old := u8(0)
				mut next := u8(0)
				C.memcpy(&old, expected, 1)
				C.memcpy(&next, value, 1)
				C.vhx_compare8(&u8(storage), &old, next, false, 0, 0)
				C.memcpy(result, &old, 1)
			}
			2 {
				mut old := u16(0)
				mut next := u16(0)
				C.memcpy(&old, expected, 2)
				C.memcpy(&next, value, 2)
				C.vhx_compare16(&u16(storage), &old, next, false, 0, 0)
				C.memcpy(result, &old, 2)
			}
			4 {
				mut old := u32(0)
				mut next := u32(0)
				C.memcpy(&old, expected, 4)
				C.memcpy(&next, value, 4)
				C.vhx_compare32(&u32(storage), &old, next, false, 0, 0)
				C.memcpy(result, &old, 4)
			}
			8 {
				mut old := u64(0)
				mut next := u64(0)
				C.memcpy(&old, expected, 8)
				C.memcpy(&next, value, 8)
				C.vhx_compare64(&u64(storage), &old, next, false, 0, 0)
				C.memcpy(result, &old, 8)
			}
			else { C.__builtin_trap() }
		}
	}
}
