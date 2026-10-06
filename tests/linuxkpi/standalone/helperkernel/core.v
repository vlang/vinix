// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module helperkernel

#include "helperkernel_v_contract.h"
@[typedef]
struct C.vks_volatile_ulong {}
@[typedef]
struct C.vks_volatile_u32 {}
@[typedef]
struct C.vks_volatile_u64 {}
fn C.assert(bool)
fn C.__atomic_store_n(voidptr, ...)
fn C.is_power_of_2(C.vks_volatile_ulong) bool
fn C.order_base_2(C.vks_volatile_ulong) usize
fn C.ilog2(...) usize
fn C.roundup_pow_of_two(C.vks_volatile_ulong) usize
fn C.rounddown_pow_of_two(C.vks_volatile_ulong) usize
fn C.min(...) u32
fn C.max(...) u32
fn C.clamp_val(...) usize
fn C.clamp(...) i32
fn C.min_not_zero(...) u32
fn C.min_t(...) u64
fn C.max_t(...) u64
@[c_extern]
__global C.vks_linux_u64 u64
@[c_extern]
__global C.BITS_PER_LONG usize

fn increment(value &u32) u32 {
    unsafe { old := *value; (*value)++; return old }
}

@[export: 'main']
pub fn run() i32 {
    unsafe {
        highest := usize(1) << (C.BITS_PER_LONG - 1)
        values := [usize(0), 1, 2, 3, 4, 7, 8, 15, 16, highest, highest + 1, ~usize(0)]!
        powers := [false, true, true, false, true, false, true, false, true, true, false, false]!
        // A qualified native view preserves the original volatile reads while
        // the fixed array's ordinary initializer stays on the V stack.
        volatile_values := &C.vks_volatile_ulong(&values[0])
        for i in 0 .. 12 { C.assert(C.is_power_of_2(volatile_values[i]) == powers[i]) }
        mut value := C.vks_volatile_ulong{}
        C.__atomic_store_n(&value, usize(0), i32(0))
        C.assert(C.order_base_2(value) == 0)
        C.__atomic_store_n(&value, usize(1), i32(0))
        C.assert(C.order_base_2(value) == 0 && C.ilog2(value) == 0)
        C.assert(C.roundup_pow_of_two(value) == 1 && C.rounddown_pow_of_two(value) == 1)
        C.__atomic_store_n(&value, usize(3), i32(0))
        C.assert(C.order_base_2(value) == 2 && C.ilog2(value) == 1)
        C.assert(C.roundup_pow_of_two(value) == 4 && C.rounddown_pow_of_two(value) == 2)
        C.__atomic_store_n(&value, usize(17), i32(0))
        C.assert(C.order_base_2(value) == 5 && C.ilog2(value) == 4)
        C.assert(C.roundup_pow_of_two(value) == 32 && C.rounddown_pow_of_two(value) == 16)
        C.__atomic_store_n(&value, highest, i32(0))
        C.assert(C.order_base_2(value) == C.BITS_PER_LONG - 1)
        C.assert(C.ilog2(value) == C.BITS_PER_LONG - 1)
        C.assert(C.roundup_pow_of_two(value) == highest && C.rounddown_pow_of_two(value) == highest)
        C.__atomic_store_n(&value, ~usize(0), i32(0))
        C.assert(C.order_base_2(value) == C.BITS_PER_LONG)
        C.assert(C.ilog2(value) == C.BITS_PER_LONG - 1 && C.rounddown_pow_of_two(value) == highest)
        mut small := C.vks_volatile_u32{}
        mut large := C.vks_volatile_u64{}
        C.__atomic_store_n(&small, u32(0x80000000), i32(0))
        C.__atomic_store_n(&large, u64(1) << 63, i32(0))
        C.assert(C.ilog2(small) == 31 && C.ilog2(large) == 63)
        mut a := u32(7)
        mut b := u32(9)
        C.assert(C.min(increment(&a), increment(&b)) == 7 && a == 8 && b == 10)
        C.assert(C.max(increment(&a), increment(&b)) == 10 && a == 9 && b == 11)
        mut lo := u32(2)
        mut hi := u32(8)
        mut number := u32(10)
        C.assert(C.clamp_val(increment(&number), increment(&lo), increment(&hi)) == 8)
        C.assert(number == 11 && lo == 3 && hi == 9)
        C.assert(C.clamp_val(u32(0), i32(2), i32(8)) == 2)
        C.assert(C.clamp_val(u32(5), i32(2), i32(8)) == 5)
        C.assert(C.clamp_val(~u32(0), i32(2), i32(8)) == 8)
        C.assert(C.clamp_val(highest, i32(0), highest) == highest)
        C.assert(C.clamp(i32(-10), i32(-8), i32(8)) == -8 && C.clamp(i32(10), i32(-8), i32(8)) == 8)
        C.assert(C.min_not_zero(u32(0), u32(9)) == 9 && C.min_not_zero(u32(7), u32(0)) == 7)
        // Foreign metadata emits the actual native typename argument to min_t.
        C.assert(C.min_t(C.vks_linux_u64, u64(1) << 63, u32(7)) == 7)
        C.assert(C.max_t(C.vks_linux_u64, u64(1) << 63, u32(7)) == u64(1) << 63)
        return 0
    }
}
