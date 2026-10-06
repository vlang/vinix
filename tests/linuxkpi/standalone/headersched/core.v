// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module headersched

#include "headersched_v_contract.h"
@[typedef]
struct C.ktime_t {}
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.ktime_set(...) C.ktime_t
fn C.ktime_to_ns(C.ktime_t) C.ktime_t
fn C.ktime_add_ns(C.ktime_t, ...) C.ktime_t
fn C.ktime_sub_ns(C.ktime_t, ...) C.ktime_t
fn C.ktime_before(C.ktime_t, C.ktime_t) bool
fn C.ktime_after(C.ktime_t, C.ktime_t) bool
fn C.assert(bool)
@[c_extern]
__global C.KTIME_SEC_MAX C.ktime_t
@[c_extern]
__global C.KTIME_MAX C.ktime_t

fn bits(native C.ktime_t) i64 {
    mut value := i64(0)
    unsafe { C.memcpy(&value, &native, sizeof(i64)) }
    return value
}

@[export: 'main']
pub fn run() i32 {
    unsafe {
        value := C.ktime_set(i64(1), usize(123))
        C.assert(bits(C.ktime_to_ns(value)) == 1000000123)
        C.assert(bits(C.ktime_to_ns(C.ktime_add_ns(value, i64(77)))) == 1000000200)
        C.assert(bits(C.ktime_to_ns(C.ktime_sub_ns(value, i64(124)))) == 999999999)
        C.assert(bits(C.ktime_set(C.KTIME_SEC_MAX, usize(0))) == i64(C.KTIME_MAX))
        C.assert(C.ktime_before(value, C.ktime_add_ns(value, i64(1))))
        C.assert(C.ktime_after(value, C.ktime_sub_ns(value, i64(1))))
        return 0
    }
}
