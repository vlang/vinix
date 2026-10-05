// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module headercore

#include "linuxkpi_wait_v_contract.h"

struct C.wait_queue_head {}
struct C.wait_queue_entry {}
@[typedef]
struct C.raw_spinlock_t {}
@[typedef]
struct C.atomic_t {}
fn C.init_waitqueue_head(&C.wait_queue_head)
fn C.prepare_to_wait(&C.wait_queue_head, &C.wait_queue_entry, i32)
fn C.prepare_to_wait_exclusive(&C.wait_queue_head, &C.wait_queue_entry, i32) bool
fn C.finish_wait(&C.wait_queue_head, &C.wait_queue_entry)
fn C.waitqueue_active(&C.wait_queue_head) bool
fn C.__wake_up(&C.wait_queue_head, u32, i32, voidptr) i32
fn C.autoremove_wake_function(&C.wait_queue_entry, u32, i32, voidptr) i32
fn C.test_bit(i32, voidptr) bool
fn C.test_bit_acquire(i32, voidptr) bool
fn C.test_and_set_bit(i32, voidptr) bool
fn C.wake_bit_function(&C.wait_queue_entry, u32, i32, voidptr) i32
fn C.vinix_linuxkpi_var_wake_function(&C.wait_queue_entry, u32, i32, voidptr) i32
fn C.set_current_state(u32)
fn C.wake_up_process(&C.task_struct) i32
fn C.wake_up_state(&C.task_struct, u32) i32
fn C.irqs_disabled() bool
fn C.raw_spin_lock_irq(&C.raw_spinlock_t)
fn C.raw_spin_unlock_irq(&C.raw_spinlock_t)
fn C.atomic_add_unless(&C.atomic_t, i32, i32) bool
fn C.atomic_dec_and_test(&C.atomic_t) bool

@[aligned: 64]
struct HeaderWaitTable { entries [256]C.wait_queue_head }
$if linuxkpi_host_test ? {
	__global vkh_bit_wait_table HeaderWaitTable
} $else {
	@[_linker_section: '.data..cacheline_aligned']
	__global vkh_bit_wait_table HeaderWaitTable
}
@[export: 'vkw_wait_table']
pub fn wait_table() voidptr { return unsafe { &vkh_bit_wait_table.entries[0] } }
@[export: 'vkw_wait_init']
pub fn wait_init(storage voidptr) { unsafe { C.init_waitqueue_head(&C.wait_queue_head(storage)) } }
@[export: 'vkw_wait_prepare']
pub fn wait_prepare(queue voidptr, entry voidptr, state u32) { unsafe { C.prepare_to_wait(&C.wait_queue_head(queue), &C.wait_queue_entry(entry), i32(state)) } }
@[export: 'vkw_wait_prepare_exclusive']
pub fn wait_prepare_exclusive(queue voidptr, entry voidptr, state u32) { unsafe { C.prepare_to_wait_exclusive(&C.wait_queue_head(queue), &C.wait_queue_entry(entry), i32(state)) } }
@[export: 'vkw_wait_finish']
pub fn wait_finish(queue voidptr, entry voidptr) { unsafe { C.finish_wait(&C.wait_queue_head(queue), &C.wait_queue_entry(entry)) } }
@[export: 'vkw_wait_active']
pub fn wait_active(queue voidptr) bool { return unsafe { C.waitqueue_active(&C.wait_queue_head(queue)) } }
@[export: 'vkw_wait_wake']
pub fn wait_wake(queue voidptr, mode u32, count i32, key voidptr) { unsafe { C.__wake_up(&C.wait_queue_head(queue), mode, count, key) } }
@[export: 'vkw_wait_autoremove']
pub fn wait_autoremove(entry voidptr, mode u32, sync i32, key voidptr) i32 { return unsafe { C.autoremove_wake_function(&C.wait_queue_entry(entry), mode, sync, key) } }
@[export: 'vkw_test_bit']
pub fn wait_test_bit(bit i32, storage voidptr) bool { return C.test_bit(bit, storage) }
@[export: 'vkw_test_bit_acquire']
pub fn wait_test_bit_acquire(bit i32, storage voidptr) bool { return C.test_bit_acquire(bit, storage) }
@[export: 'vkw_test_and_set_bit']
pub fn wait_test_and_set_bit(bit i32, storage voidptr) bool { return C.test_and_set_bit(bit, storage) }
@[export: 'vkw_bit_wake_callback']
pub fn wait_bit_wake_callback() voidptr { return voidptr(C.wake_bit_function) }
@[export: 'vkw_var_wake_callback']
pub fn wait_var_wake_callback() voidptr { return voidptr(C.vinix_linuxkpi_var_wake_function) }
@[export: 'vkw_signal_state']
pub fn wait_signal_state(state u32, task voidptr) bool { return unsafe { C.signal_pending_state(i32(state), &C.task_struct(task)) } }
@[export: 'vkw_current_state']
pub fn wait_current_state(state u32) { C.set_current_state(state) }
@[export: 'vkw_wake_task']
pub fn wait_wake_task(task voidptr) i32 { return unsafe { C.wake_up_process(&C.task_struct(task)) } }
@[export: 'vkw_wake_state']
pub fn wait_wake_state(task voidptr, state u32) i32 { return unsafe { C.wake_up_state(&C.task_struct(task), state) } }
@[export: 'vkw_irqs_disabled']
pub fn wait_irqs_disabled() bool { return C.irqs_disabled() }
@[export: 'vkw_spin_lock_irq']
pub fn wait_spin_lock_irq(storage voidptr) { unsafe { C.raw_spin_lock_irq(&C.raw_spinlock_t(storage)) } }
@[export: 'vkw_spin_unlock_irq']
pub fn wait_spin_unlock_irq(storage voidptr) { unsafe { C.raw_spin_unlock_irq(&C.raw_spinlock_t(storage)) } }
@[export: 'vkw_atomic_add_unless']
pub fn wait_atomic_add_unless(storage voidptr, add i32, unless i32) bool { return unsafe { C.atomic_add_unless(&C.atomic_t(storage), add, unless) } }
@[export: 'vkw_atomic_dec_and_test']
pub fn wait_atomic_dec_and_test(storage voidptr) bool { return unsafe { C.atomic_dec_and_test(&C.atomic_t(storage)) } }
@[export: 'vkw_autoremove_callback']
pub fn wait_autoremove_callback() voidptr { return voidptr(C.autoremove_wake_function) }
