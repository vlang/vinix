// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module rcufixture

#include "linuxkpi_rcu_fixture_v_contract.h"

struct C.callback_head {}
struct C.task_struct {
mut:
	__state u32
}
type Callback = fn (&C.callback_head)
fn C.call_rcu(&C.callback_head, Callback)
fn C.rcu_read_lock()
fn C.rcu_read_unlock()
fn C.get_state_synchronize_rcu() uint
fn C.start_poll_synchronize_rcu() uint
fn C.poll_state_synchronize_rcu(uint) bool
fn C.synchronize_rcu()
fn C.synchronize_rcu_expedited()
fn C.rcu_barrier()
fn C.__atomic_load_n(&u32, i32) u32

// Typed calls only: the original reader macros and real native backend own
// every read-side scope, grace period, callback and barrier.
@[export: 'vinix_linuxkpi_rcu_fixture_head_bytes']
pub fn head_bytes() u32 { return u32(sizeof(C.callback_head)) }
@[export: 'vinix_linuxkpi_rcu_fixture_read_lock']
pub fn read_lock() { C.rcu_read_lock() }
@[export: 'vinix_linuxkpi_rcu_fixture_read_unlock']
pub fn read_unlock() { C.rcu_read_unlock() }
@[export: 'vinix_linuxkpi_rcu_fixture_get_state']
pub fn get_state() u64 { return u64(C.get_state_synchronize_rcu()) }
@[export: 'vinix_linuxkpi_rcu_fixture_start_poll']
pub fn start_poll() u64 { return u64(C.start_poll_synchronize_rcu()) }
@[export: 'vinix_linuxkpi_rcu_fixture_poll']
pub fn poll(cookie u64) bool { return C.poll_state_synchronize_rcu(uint(cookie)) }
@[export: 'vinix_linuxkpi_rcu_fixture_synchronize']
pub fn synchronize(expedited bool) {
	if expedited { C.synchronize_rcu_expedited() } else { C.synchronize_rcu() }
}
@[export: 'vinix_linuxkpi_rcu_fixture_barrier']
pub fn barrier() { C.rcu_barrier() }
@[export: 'vinix_linuxkpi_rcu_fixture_call']
pub fn call(head voidptr, callback Callback) {
	unsafe { C.call_rcu(&C.callback_head(head), callback) }
}
@[export: 'vinix_linuxkpi_rcu_fixture_task_sleeping']
pub fn task_sleeping(storage voidptr) bool {
	unsafe { return C.__atomic_load_n(&(&C.task_struct(storage)).__state, 2) == C.TASK_UNINTERRUPTIBLE }
}
