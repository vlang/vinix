// SPDX-License-Identifier: GPL-2.0-or-later
// Independent bit-pattern and success/failure oracle for generic Linux atomics.
@[translated]
module exchangefixture

#include "vinix/atomic_exchange.h"

fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32,i32) i32
fn C.close(i32) i32

@[c: 'arch_xchg_relaxed']
fn C.vhf_exchange8(&u8, u8) u8
@[c: 'arch_cmpxchg_relaxed']
fn C.vhf_compare8(&u8, u8, u8) u8
@[c: 'arch_xchg_relaxed']
fn C.vhf_exchange16(&i16, i16) i16
@[c: 'arch_cmpxchg_relaxed']
fn C.vhf_compare16(&i16, i16, i16) i16
@[c: 'arch_xchg_relaxed']
fn C.vhf_exchange32(&u32, u32) u32
@[c: 'arch_cmpxchg_relaxed']
fn C.vhf_compare32(&u32, u32, u32) u32
@[c: 'arch_xchg_relaxed']
fn C.vhf_exchange64(&i64, i64) i64
@[c: 'arch_cmpxchg_relaxed']
fn C.vhf_compare64(&i64, i64, i64) i64
@[c: 'arch_xchg_relaxed']
fn C.vhf_exchange128(&u128, u128) u128
@[c: 'arch_cmpxchg_relaxed']
fn C.vhf_compare128(&u128, u128, u128) u128
@[c: 'arch_xchg_relaxed']
fn C.vhf_exchange_pointer(&voidptr, voidptr) voidptr
@[c: 'arch_cmpxchg_relaxed']
fn C.vhf_compare_pointer(&voidptr, voidptr, voidptr) voidptr

fn C.printf(&char, ...) i32
fn C.vinix_exchange_fixture_pointer() &u8
fn C.vinix_exchange_fixture_expected() u8
fn C.vinix_exchange_fixture_value() u8

@[cinit]
__global (
	vhf_native_byte u8 = 9
	vhf_pointer_calls u32
	vhf_expected_calls u32
	vhf_value_calls u32
)

@[export: 'vinix_exchange_fixture_pointer']
pub fn pointer_argument() &u8 {
	unsafe { vhf_pointer_calls++; return &vhf_native_byte }
}

@[export: 'vinix_exchange_fixture_expected']
pub fn expected_argument() u8 {
	unsafe { vhf_expected_calls++; return 9 }
}

@[export: 'vinix_exchange_fixture_value']
pub fn value_argument() u8 {
	unsafe { vhf_value_calls++; return 11 }
}

fn check(condition bool, errors &i32) {
	if !condition { unsafe { (*errors)++ } }
}

@[export: 'main']
pub fn main_entry() i32 {
	unsafe {
		$if exchange_native_guest ? {
			$if amd64 {
				fd := C.open(c'/dev/com1', 2)
				if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); C.close(fd) }
			}
		}
		mut errors := i32(0)
		// High bits distinguish exact width/sign preservation from widening casts.
		mut byte_value := u8(0x81)
		mut byte_next := u8(0xFE)
		mut byte_old := u8(0)
		byte_old = C.vhf_exchange8(&byte_value, byte_next)
		check(byte_old == 0x81 && byte_value == 0xFE, &errors)
		byte_old = C.vhf_compare8(&byte_value, byte_old, byte_next)
		check(byte_old == 0xFE && byte_value == 0xFE, &errors)
		byte_next = 3
		byte_old = C.vhf_compare8(&byte_value, byte_old, byte_next)
		check(byte_old == 0xFE && byte_value == 3, &errors)

		mut short_value := i16(-32767)
		mut short_next := i16(-2)
		mut short_old := i16(0)
		short_old = C.vhf_exchange16(&short_value, short_next)
		check(short_old == -32767 && short_value == -2, &errors)
		short_old = C.vhf_compare16(&short_value, short_old, short_next)
		check(short_old == -2 && short_value == -2, &errors)
		short_next = 3
		short_old = C.vhf_compare16(&short_value, short_old, short_next)
		check(short_old == -2 && short_value == 3, &errors)

		mut int_value := u32(0x80000001)
		mut int_next := u32(0xFFFFFFFE)
		mut int_old := u32(0)
		int_old = C.vhf_exchange32(&int_value, int_next)
		check(int_old == 0x80000001 && int_value == 0xFFFFFFFE, &errors)
		int_old = C.vhf_compare32(&int_value, int_old, int_next)
		check(int_old == 0xFFFFFFFE && int_value == 0xFFFFFFFE, &errors)
		int_next = 3
		int_old = C.vhf_compare32(&int_value, int_old, int_next)
		check(int_old == 0xFFFFFFFE && int_value == 3, &errors)

		mut word_value := i64(-9223372036854775807)
		mut word_next := i64(-2)
		mut word_old := i64(0)
		word_old = C.vhf_exchange64(&word_value, word_next)
		check(word_old == -9223372036854775807 && word_value == -2, &errors)
		word_old = C.vhf_compare64(&word_value, word_old, word_next)
		check(word_old == -2 && word_value == -2, &errors)
		word_next = 3
		word_old = C.vhf_compare64(&word_value, word_old, word_next)
		check(word_old == -2 && word_value == 3, &errors)

		mut pointer_a := i32(7)
		mut pointer_b := i32(11)
		mut pointer_value := voidptr(&pointer_a)
		mut pointer_next := voidptr(&pointer_b)
		mut pointer_old := voidptr(nil)
		pointer_old = C.vhf_exchange_pointer(&pointer_value, pointer_next)
		check(pointer_old == voidptr(&pointer_a) && pointer_value == voidptr(&pointer_b), &errors)
		pointer_old = C.vhf_compare_pointer(&pointer_value, pointer_old, pointer_next)
		check(pointer_old == voidptr(&pointer_b) && pointer_value == voidptr(&pointer_b), &errors)
		pointer_next = nil
		pointer_old = C.vhf_compare_pointer(&pointer_value, pointer_old, pointer_next)
		check(pointer_old == voidptr(&pointer_b) && pointer_value == nil, &errors)

		mut wide_value := (u128(0x8000000000000001) << 64) | u128(0x0102030405060708)
		mut wide_next := (u128(0xFFFFFFFFFFFFFFFE) << 64) | u128(0xFEDCBA9876543210)
		original_wide := wide_value
		next_wide := wide_next
		mut wide_old := u128(0)
		wide_old = C.vhf_exchange128(&wide_value, wide_next)
		check(wide_old == original_wide && wide_value == next_wide, &errors)
		wide_old = C.vhf_compare128(&wide_value, wide_old, wide_next)
		check(wide_old == next_wide && wide_value == next_wide, &errors)
		wide_next = 3
		wide_old = C.vhf_compare128(&wide_value, wide_old, wide_next)
		check(wide_old == next_wide && wide_value == 3, &errors)
		// The generated adapter must capture every expression exactly once.
		vhf_pointer_calls = 0; vhf_expected_calls = 0; vhf_value_calls = 0; vhf_native_byte = 9
		byte_old = C.vhf_exchange8(C.vinix_exchange_fixture_pointer(), C.vinix_exchange_fixture_value())
		check(byte_old == 9 && vhf_native_byte == 11 && vhf_pointer_calls == 1 && vhf_value_calls == 1, &errors)
		vhf_pointer_calls = 0; vhf_expected_calls = 0; vhf_value_calls = 0; vhf_native_byte = 9
		byte_old = C.vhf_compare8(C.vinix_exchange_fixture_pointer(), C.vinix_exchange_fixture_expected(), C.vinix_exchange_fixture_value())
		check(byte_old == 9 && vhf_native_byte == 11 && vhf_pointer_calls == 1 && vhf_expected_calls == 1 && vhf_value_calls == 1, &errors)
		C.printf(c'LinuxKPI generic exchange widths=1,2,4,8,16 and pointer errors=%d\n', errors)
		C.fflush(nil)
		$if exchange_native_guest ? {
			if errors == 0 { for { C.pause() } }
		}
		return if errors == 0 { i32(0) } else { i32(1) }
	}
}
