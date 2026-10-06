// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module headercore

#include "linuxkpi_common_v_contract.h"

@[typedef]
struct C.spinlock_t { locked u32 }
@[typedef]
struct C.refcount_t {}
struct C.mutex {}
struct C.task_struct { in_iowait u32, __state u32, vinix_thread voidptr, pid i32, tgid i32 }
struct C.wait_bit_key { timeout usize }
@[typedef]
struct C.vkh_const_char_p {}
fn C.spin_lock_init(&C.spinlock_t)
fn C.spin_lock(&C.spinlock_t)
fn C.spin_unlock(&C.spinlock_t)
fn C.spin_lock_irqsave(&C.spinlock_t, usize)
fn C.spin_unlock_irqrestore(&C.spinlock_t, usize)
fn C.mutex_lock(&C.mutex)
fn C.mutex_unlock(&C.mutex)
fn C.refcount_dec_and_test(&C.refcount_t) bool
fn C.WARN_ON_ONCE(bool) bool
@[c_extern]
__global C.current &C.task_struct
fn C.schedule()
fn C.schedule_timeout(isize) isize
fn C.signal_pending_state(u32, &C.task_struct) i32
@[c_extern]
__global C.jiffies usize
fn C.READ_ONCE(usize) usize
fn C.vinix_linuxkpi_warn_format(C.vkh_const_char_p, i32, &char, ...)
fn C._printk(&char, ...) i32
fn C.vinix_linuxkpi_test_warn_note(C.vkh_const_char_p, i32)
fn C.vinix_linuxkpi_test_refcount_note(i32)
@[export: '__per_cpu_offset']
__global vkh_percpu_offsets [256]usize
@[c_extern]
__global C.__vinix_percpu_start u8
@[c_extern]
__global C.__vinix_percpu_end u8

@[export: 'vkp_spin_init']
pub fn common_spin_init(storage voidptr) { unsafe { C.spin_lock_init(&C.spinlock_t(storage)) } }
@[export: 'vkp_spin_lock']
pub fn common_spin_lock(storage voidptr) { unsafe { C.spin_lock(&C.spinlock_t(storage)) } }
@[export: 'vkp_spin_unlock']
pub fn common_spin_unlock(storage voidptr) { unsafe { C.spin_unlock(&C.spinlock_t(storage)) } }
@[export: 'vkp_spin_lock_irqsave']
pub fn common_spin_lock_irqsave(storage voidptr) usize {
	mut flags := usize(0)
	unsafe { C.spin_lock_irqsave(&C.spinlock_t(storage), flags) }
	return flags
}
@[export: 'vkp_spin_unlock_irqrestore']
pub fn common_spin_unlock_irqrestore(storage voidptr, flags usize) { unsafe { C.spin_unlock_irqrestore(&C.spinlock_t(storage), flags) } }
@[export: 'vkp_mutex_lock']
pub fn common_mutex_lock(storage voidptr) { unsafe { C.mutex_lock(&C.mutex(storage)) } }
@[export: 'vkp_mutex_unlock']
pub fn common_mutex_unlock(storage voidptr) { unsafe { C.mutex_unlock(&C.mutex(storage)) } }
@[export: 'vkp_refcount_dec_and_test']
pub fn common_refcount_dec_and_test(storage voidptr) bool { return unsafe { C.refcount_dec_and_test(&C.refcount_t(storage)) } }
@[export: 'vkp_cache_ctor_warning']
pub fn common_cache_ctor_warning(invalid bool) { C.WARN_ON_ONCE(invalid) }
@[export: 'vkp_current']
pub fn common_current() voidptr { return C.current }
@[export: 'vkp_iowait_field']
pub fn common_iowait_field(task voidptr) voidptr { return unsafe { &(&C.task_struct(task)).in_iowait } }
@[export: 'vkp_schedule']
pub fn common_schedule() { C.schedule() }
@[export: 'vkp_schedule_timeout']
pub fn common_schedule_timeout(timeout isize) isize { return C.schedule_timeout(timeout) }
@[export: 'vkp_signal_pending']
pub fn common_signal_pending(mode i32) bool { return C.signal_pending_state(u32(mode), C.current) != 0 }
@[export: 'vkp_jiffies']
pub fn common_jiffies() usize { return C.READ_ONCE(C.jiffies) }
@[export: 'vkp_bit_timeout']
pub fn common_bit_timeout(key voidptr) usize { return unsafe { (&C.wait_bit_key(key)).timeout } }
@[export: 'vkp_warn']
pub fn common_warn(file C.vkh_const_char_p, line i32) { unsafe { C.vinix_linuxkpi_warn_format(file, line, nil) } }
@[export: 'vkp_refcount_warning']
pub fn common_refcount_warning(kind i32) { C._printk(c'\x01\x34linuxkpi: refcount saturated after invalid operation %d; retaining object\n', kind) }
@[export: 'vkp_warn_note']
pub fn common_warn_note(file C.vkh_const_char_p, line i32) { $if linuxkpi_host_test ? { C.vinix_linuxkpi_test_warn_note(file, line) } }
@[export: 'vkp_refcount_note']
pub fn common_refcount_note(kind i32) { $if linuxkpi_host_test ? { C.vinix_linuxkpi_test_refcount_note(kind) } }
@[export: 'vkp_percpu_offsets']
pub fn common_percpu_offsets() voidptr { return unsafe { &vkh_percpu_offsets[0] } }
@[export: 'vkp_percpu_begin']
pub fn common_percpu_begin() voidptr {
	$if linuxkpi_host_test ? { return unsafe { nil } } $else { return unsafe { &C.__vinix_percpu_start } }
}
@[export: 'vkp_percpu_end']
pub fn common_percpu_end() voidptr {
	$if linuxkpi_host_test ? { return unsafe { nil } } $else { return unsafe { &C.__vinix_percpu_end } }
}
