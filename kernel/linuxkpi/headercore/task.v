// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module headercore

#include "linuxkpi_task_v_contract.h"

fn C.vtime_account_guest_enter()
fn C.vtime_account_guest_exit()
@[c_extern]
__global C.MAX_SEC_IN_JIFFIES u64
@[c_extern]
__global C.SEC_CONVERSION u32
@[c_extern]
__global C.NSEC_CONVERSION u32
struct C.vkw_list { next &C.vkw_list, prev &C.vkw_list }
struct C.vkw_swait_head { lock u32, task_list C.vkw_list }
struct C.vkw_completion { done u32, @wait C.vkw_swait_head }
@[cinit]
__global vkh_worker_ready C.vkw_completion = C.vkw_completion{@wait: C.vkw_swait_head{task_list: C.vkw_list{next: unsafe { &vkh_worker_ready.@wait.task_list }, prev: unsafe { &vkh_worker_ready.@wait.task_list }}}}
fn C.complete(voidptr)
fn C.wait_for_completion(voidptr)
@[typedef]
struct C.pthread_t {}
type HeaderThreadFn = fn (voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, HeaderThreadFn, voidptr) i32
fn C.pthread_detach(C.pthread_t) i32

@[export: 'vkt_jiffies_address']
pub fn task_jiffies_address() usize { return unsafe { usize(&C.jiffies) } }
@[export: 'vkt_guest_enter']
pub fn task_guest_enter() { C.vtime_account_guest_enter() }
@[export: 'vkt_guest_exit']
pub fn task_guest_exit() { C.vtime_account_guest_exit() }
@[export: 'vkt_max_sec_in_jiffies']
pub fn task_max_sec_in_jiffies() u64 { return C.MAX_SEC_IN_JIFFIES }
@[export: 'vkt_sec_conversion']
pub fn task_sec_conversion() u32 { return C.SEC_CONVERSION }
@[export: 'vkt_nsec_conversion']
pub fn task_nsec_conversion() u32 { return C.NSEC_CONVERSION }
@[export: 'vkt_timer_worker_ready']
pub fn task_timer_worker_ready() voidptr { return unsafe { &vkh_worker_ready } }
@[export: 'vkt_completion_complete']
pub fn task_completion_complete(completion voidptr) { C.complete(completion) }
@[export: 'vkt_completion_wait']
pub fn task_completion_wait(completion voidptr) { C.wait_for_completion(completion) }
@[export: 'vkt_pthread_create']
pub fn task_pthread_create(storage voidptr, callback HeaderThreadFn, argument voidptr) i32 { return unsafe { C.pthread_create(storage, nil, callback, argument) } }
@[export: 'vkt_pthread_detach']
pub fn task_pthread_detach(storage voidptr) i32 { return unsafe { C.pthread_detach(*(&C.pthread_t(storage))) } }
