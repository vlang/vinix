// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module headerww

#include "headerww_v_contract.h"
struct C.task_struct { flags u32 }
struct C.ww_class {}
struct C.ww_acquire_ctx { task &C.task_struct, stamp usize, acquired u32, wounded u16, is_wait_die u16 }
fn C.DEFINE_WW_CLASS(C.ww_class)
fn C.DEFINE_WD_CLASS(C.ww_class)
fn C.ww_acquire_init(&C.ww_acquire_ctx, &C.ww_class)
fn C.ww_acquire_done(&C.ww_acquire_ctx)
fn C.ww_acquire_fini(&C.ww_acquire_ctx)
fn C.assert(bool)
@[c_extern]
__global C.wound_wait C.ww_class
@[c_extern]
__global C.wait_die C.ww_class
@[c_extern]
__global C.PF_VCPU u32
__global header_task C.task_struct

@[export: 'vinix_linuxkpi_current_task']
pub fn current_task() &C.task_struct { return unsafe { &header_task } }

@[export: 'main']
pub fn run() i32 {
    unsafe {
        C.DEFINE_WW_CLASS(C.wound_wait)
        C.DEFINE_WD_CLASS(C.wait_die)
        mut first := C.ww_acquire_ctx{}
        mut second := C.ww_acquire_ctx{}
        mut other := C.ww_acquire_ctx{}
        header_task.flags = C.PF_VCPU
        C.ww_acquire_init(&first, &C.wound_wait)
        C.ww_acquire_init(&second, &C.wound_wait)
        C.ww_acquire_init(&other, &C.wait_die)
        C.assert(usize(first.task) == usize(&header_task) && usize(second.task) == usize(first.task) && usize(other.task) == usize(first.task))
        C.assert(first.stamp == 1 && second.stamp == 2 && other.stamp == 1)
        C.assert(first.acquired == 0 && first.wounded == 0 && first.is_wait_die == 0)
        C.assert(other.acquired == 0 && other.wounded == 0 && other.is_wait_die != 0)
        C.assert(header_task.flags == C.PF_VCPU)
        C.ww_acquire_done(&first)
        C.ww_acquire_fini(&first)
        C.ww_acquire_fini(&second)
        C.ww_acquire_fini(&other)
        return 0
    }
}
