// SPDX-License-Identifier: GPL-2.0-or-later
// First-party LinuxKPI primitives, with native layouts supplied by declarations.
@[translated]
module headercore

#include "linuxkpi_header_primitive_v_contract.h"
@[typedef]
struct C.atomic64_t {
	counter i64
}

@[typedef]
struct C.vhp_s64 {}

@[typedef]
struct C.vhp_const_atomicp {}

@[typedef]
struct C.vhp_const_atomic64p {}

@[typedef]
struct C.vhp_const_spinp {}

@[typedef]
struct C.vhp_const_taskp {}

@[typedef]
struct C.vhp_const_voidp {}

struct C.kmem_cache {}

fn C.memcpy(voidptr, voidptr, usize) voidptr

@[c: '__atomic_load_n']
fn C.vhp_load32(&i32, i32) i32

@[c: '__atomic_store_n']
fn C.vhp_store32(&i32, i32, i32)

@[c: '__atomic_fetch_add']
fn C.vhp_add32(&i32, i32, i32) i32

@[c: '__atomic_fetch_sub']
fn C.vhp_sub32(&i32, i32, i32) i32

@[c: '__atomic_fetch_and']
fn C.vhp_and32(&i32, i32, i32) i32

@[c: '__atomic_fetch_or']
fn C.vhp_or32(&i32, i32, i32) i32

@[c: '__atomic_fetch_xor']
fn C.vhp_xor32(&i32, i32, i32) i32

@[c: '__atomic_add_fetch']
fn C.vhp_add_return32(&i32, i32, i32) i32

@[c: '__atomic_sub_fetch']
fn C.vhp_sub_return32(&i32, i32, i32) i32

@[c: '__atomic_exchange_n']
fn C.vhp_exchange32(&i32, i32, i32) i32

@[c: '__atomic_compare_exchange_n']
fn C.vhp_compare32(&i32, &i32, i32, bool, i32, i32) bool

@[c: '__atomic_load_n']
fn C.vhp_load64(&i64, i32) i64

@[c: '__atomic_store_n']
fn C.vhp_store64(&i64, i64, i32)

@[c: '__atomic_fetch_add']
fn C.vhp_add64(&i64, i64, i32) i64

@[c: '__atomic_fetch_sub']
fn C.vhp_sub64(&i64, i64, i32) i64

@[c: '__atomic_fetch_and']
fn C.vhp_and64(&i64, i64, i32) i64

@[c: '__atomic_fetch_or']
fn C.vhp_or64(&i64, i64, i32) i64

@[c: '__atomic_fetch_xor']
fn C.vhp_xor64(&i64, i64, i32) i64

@[c: '__atomic_add_fetch']
fn C.vhp_add_return64(&i64, i64, i32) i64

@[c: '__atomic_sub_fetch']
fn C.vhp_sub_return64(&i64, i64, i32) i64

@[c: '__atomic_exchange_n']
fn C.vhp_exchange64(&i64, i64, i32) i64

@[c: '__atomic_compare_exchange_n']
fn C.vhp_compare64(&i64, voidptr, i64, bool, i32, i32) bool

@[c: '__atomic_load_n']
fn C.vhp_load_unsigned(&u32, i32) u32

@[c: '__atomic_store_n']
fn C.vhp_store_unsigned(&u32, u32, i32)

@[c: '__atomic_compare_exchange_n']
fn C.vhp_compare_unsigned(&u32, &u32, u32, bool, i32, i32) bool

fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.vinix_linuxkpi_spin_wait()
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_need_resched() bool
fn C.vinix_linuxkpi_cond_resched() i32
fn C.vinix_linuxkpi_task_get(voidptr)
fn C.vinix_linuxkpi_task_put(voidptr)
fn C.vinix_linuxkpi_task_signal_pending(voidptr, bool) bool
fn C.kmem_cache_alloc(&C.kmem_cache, u32) voidptr

@[c_extern]
__global C.__GFP_ZERO u32

fn bits(value C.vhp_s64) i64 {
	mut result := i64(0)
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}

fn native64(value i64) C.vhp_s64 {
	mut result := C.vhp_s64{}
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}

@[export: 'arch_atomic_read']
pub fn atomic_read(p C.vhp_const_atomicp) i32 {
	unsafe { return C.vhp_load32(&(&C.atomic_t(voidptr(p))).counter, 0)
	 }
}

@[export: 'arch_atomic_set']
pub fn atomic_set(p &C.atomic_t, value i32) {
	unsafe { C.vhp_store32(&p.counter, value, 0) }
}

@[export: 'arch_atomic_cmpxchg_relaxed']
pub fn atomic_cmpxchg(p &C.atomic_t, old i32, value i32) i32 {
	mut expected := old
	unsafe { C.vhp_compare32(&p.counter, &expected, value, false, 0, 0) }
	return expected
}

@[export: 'arch_atomic64_read']
pub fn atomic64_read(p C.vhp_const_atomic64p) C.vhp_s64 {
	unsafe { return native64(C.vhp_load64(&(&C.atomic64_t(voidptr(p))).counter, 0))
	 }
}

@[export: 'arch_atomic64_set']
pub fn atomic64_set(p &C.atomic64_t, value C.vhp_s64) {
	unsafe { C.vhp_store64(&p.counter, bits(value), 0) }
}

@[export: 'arch_atomic64_cmpxchg_relaxed']
pub fn atomic64_cmpxchg(p &C.atomic64_t, old C.vhp_s64, value C.vhp_s64) C.vhp_s64 {
	mut expected := old
	unsafe { C.vhp_compare64(&p.counter, &expected, bits(value), false, 0, 0) }
	return expected
}

@[export: 'spin_lock_init']
pub fn spin_init(guard &C.spinlock_t) {
	unsafe { C.vhp_store_unsigned(&guard.locked, 0, 0) }
}

@[export: 'vinix_raw_spin_trylock']
pub fn spin_raw_try(guard &C.spinlock_t) bool {
	mut expected := u32(0)
	unsafe { return C.vhp_compare_unsigned(&guard.locked, &expected, 1, false, 2, 0)
	 }
}

@[export: 'spin_lock']
pub fn spin_lock(guard &C.spinlock_t) {
	C.vinix_linuxkpi_preempt_disable()
	for !spin_raw_try(guard) { C.vinix_linuxkpi_spin_wait() }
}

@[export: 'spin_trylock']
pub fn spin_trylock(guard &C.spinlock_t) bool {
	C.vinix_linuxkpi_preempt_disable()
	if spin_raw_try(guard) { return true }
	C.vinix_linuxkpi_preempt_enable()
	return false
}

@[export: 'spin_unlock']
pub fn spin_unlock(guard &C.spinlock_t) {
	unsafe { C.vhp_store_unsigned(&guard.locked, 0, 3) }
	C.vinix_linuxkpi_preempt_enable()
}

@[export: 'spin_is_locked']
pub fn spin_is_locked(guard C.vhp_const_spinp) bool {
	unsafe { return C.vhp_load_unsigned(&(&C.spinlock_t(voidptr(guard))).locked, 0) != 0
	 }
}

@[export: 'spin_lock_irq']
pub fn spin_lock_irq(guard &C.spinlock_t) {
	C.vinix_linuxkpi_irq_save()
	spin_lock(guard)
}

@[export: 'spin_unlock_irq']
pub fn spin_unlock_irq(guard &C.spinlock_t) {
	spin_unlock(guard)
	C.vinix_linuxkpi_irq_restore(usize(1) << 9)
}

@[export: 'irqs_disabled']
pub fn irqs_disabled() bool {
	return irqs_disabled_flags(C.vinix_linuxkpi_irq_flags())
}

@[export: 'irqs_disabled_flags']
pub fn irqs_disabled_flags(flags usize) bool {
	return (flags & (usize(1) << 9)) == 0
}

@[export: 'vinix_local_irq_disable']
pub fn irq_disable() { C.vinix_linuxkpi_irq_save() }

@[export: 'vinix_local_irq_enable']
pub fn irq_enable() {
	C.vinix_linuxkpi_irq_restore(usize(1) << 9)
}

@[export: 'cpu_relax']
pub fn cpu_relax() { C.vinix_linuxkpi_spin_wait() }

@[export: 'raw_smp_processor_id']
pub fn cpu_id() u32 { return C.vinix_linuxkpi_cpu_id() }

@[export: 'vinix_get_cpu']
pub fn get_cpu() u32 {
	C.vinix_linuxkpi_preempt_disable()
	return cpu_id()
}

@[export: 'task_pid_nr']
pub fn task_pid(task C.vhp_const_taskp) i32 {
	unsafe { return (&C.task_struct(voidptr(task))).pid
	 }
}

@[export: 'task_tgid_nr']
pub fn task_tgid(task C.vhp_const_taskp) i32 {
	unsafe { return (&C.task_struct(voidptr(task))).tgid
	 }
}

@[export: 'need_resched']
pub fn need_resched() bool { return C.vinix_linuxkpi_need_resched() }

@[export: 'cond_resched']
pub fn cond_resched() i32 { return C.vinix_linuxkpi_cond_resched() }

@[export: 'vinix_task_is_running']
pub fn task_running(task C.vhp_const_taskp) bool {
	unsafe { return C.vhp_load_unsigned(&(&C.task_struct(voidptr(task))).__state, 0) == 0
	 }
}

@[export: 'get_task_struct']
pub fn get_task(task &C.task_struct) &C.task_struct {
	C.vinix_linuxkpi_task_get(task.vinix_thread)
	return task
}

@[export: 'put_task_struct']
pub fn put_task(task &C.task_struct) {
	C.vinix_linuxkpi_task_put(task.vinix_thread)
}

@[export: 'signal_pending']
pub fn signal_pending(task &C.task_struct) i32 {
	return i32(C.vinix_linuxkpi_task_signal_pending(task.vinix_thread, false))
}

@[export: 'fatal_signal_pending']
pub fn fatal_signal_pending(task &C.task_struct) i32 {
	return i32(C.vinix_linuxkpi_task_signal_pending(task.vinix_thread, true))
}

@[export: 'signal_pending_state']
pub fn signal_pending_state(state u32, task &C.task_struct) i32 {
	if (state & (u32(1) | u32(0x100))) == 0 { return 0 }
	return if (state & 1) != 0 { signal_pending(task) } else { fatal_signal_pending(task) }
}

@[export: 'kmem_cache_zalloc']
pub fn cache_zalloc(cache &C.kmem_cache, flags u32) voidptr {
	return C.kmem_cache_alloc(cache, flags | C.__GFP_ZERO)
}

@[export: 'array_size']
pub fn array_size(a usize, b usize) usize {
	if a != 0 && b > ~usize(0) / a { return ~usize(0) }
	return a * b
}

@[export: 'size_add']
pub fn size_add(a usize, b usize) usize {
	if b > ~usize(0) - a { return ~usize(0) }
	return a + b
}

@[export: 'size_mul']
pub fn size_mul(a usize, b usize) usize { return array_size(a, b) }

@[export: 'ERR_PTR']
pub fn error_pointer(error isize) voidptr {
	return unsafe { voidptr(usize(error)) }
}

@[export: 'PTR_ERR']
pub fn pointer_error(p C.vhp_const_voidp) isize {
	return isize(usize(voidptr(p)))
}

@[export: 'IS_ERR']
pub fn is_error(p C.vhp_const_voidp) bool {
	return usize(voidptr(p)) >= ~usize(0) - 4094
}

@[export: 'IS_ERR_OR_NULL']
pub fn error_or_null(p C.vhp_const_voidp) bool {
	return voidptr(p) == unsafe { nil } || is_error(p)
}

@[export: 'PTR_ERR_OR_ZERO']
pub fn error_or_zero(p C.vhp_const_voidp) i32 {
	return if is_error(p) { i32(pointer_error(p)) } else { i32(0) }
}

@[export: 'arch_atomic_add']
pub fn atomic_add(value i32, p &C.atomic_t) {
	unsafe { C.vhp_add32(&p.counter, value, 0) }
}

@[export: 'arch_atomic_sub']
pub fn atomic_sub(value i32, p &C.atomic_t) {
	unsafe { C.vhp_sub32(&p.counter, value, 0) }
}

@[export: 'arch_atomic_and']
pub fn atomic_and(value i32, p &C.atomic_t) {
	unsafe { C.vhp_and32(&p.counter, value, 0) }
}

@[export: 'arch_atomic_or']
pub fn atomic_or(value i32, p &C.atomic_t) {
	unsafe { C.vhp_or32(&p.counter, value, 0) }
}

@[export: 'arch_atomic_xor']
pub fn atomic_xor(value i32, p &C.atomic_t) {
	unsafe { C.vhp_xor32(&p.counter, value, 0) }
}

@[export: 'arch_atomic_add_return_relaxed']
pub fn atomic_add_return_relaxed(value i32, p &C.atomic_t) i32 {
	unsafe { return C.vhp_add_return32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic_sub_return_relaxed']
pub fn atomic_sub_return_relaxed(value i32, p &C.atomic_t) i32 {
	unsafe { return C.vhp_sub_return32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic_fetch_add_relaxed']
pub fn atomic_fetch_add_relaxed(value i32, p &C.atomic_t) i32 {
	unsafe { return C.vhp_add32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic_fetch_sub_relaxed']
pub fn atomic_fetch_sub_relaxed(value i32, p &C.atomic_t) i32 {
	unsafe { return C.vhp_sub32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic_fetch_and_relaxed']
pub fn atomic_fetch_and_relaxed(value i32, p &C.atomic_t) i32 {
	unsafe { return C.vhp_and32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic_fetch_or_relaxed']
pub fn atomic_fetch_or_relaxed(value i32, p &C.atomic_t) i32 {
	unsafe { return C.vhp_or32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic_fetch_xor_relaxed']
pub fn atomic_fetch_xor_relaxed(value i32, p &C.atomic_t) i32 {
	unsafe { return C.vhp_xor32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic_xchg_relaxed']
pub fn atomic_xchg_relaxed(p &C.atomic_t, value i32) i32 {
	unsafe { return C.vhp_exchange32(&p.counter, value, 0)
	 }
}

@[export: 'arch_atomic64_add']
pub fn atomic64_add(value C.vhp_s64, p &C.atomic64_t) {
	unsafe { C.vhp_add64(&p.counter, bits(value), 0) }
}

@[export: 'arch_atomic64_sub']
pub fn atomic64_sub(value C.vhp_s64, p &C.atomic64_t) {
	unsafe { C.vhp_sub64(&p.counter, bits(value), 0) }
}

@[export: 'arch_atomic64_and']
pub fn atomic64_and(value C.vhp_s64, p &C.atomic64_t) {
	unsafe { C.vhp_and64(&p.counter, bits(value), 0) }
}

@[export: 'arch_atomic64_or']
pub fn atomic64_or(value C.vhp_s64, p &C.atomic64_t) {
	unsafe { C.vhp_or64(&p.counter, bits(value), 0) }
}

@[export: 'arch_atomic64_xor']
pub fn atomic64_xor(value C.vhp_s64, p &C.atomic64_t) {
	unsafe { C.vhp_xor64(&p.counter, bits(value), 0) }
}

@[export: 'arch_atomic64_add_return_relaxed']
pub fn atomic64_add_return_relaxed(value C.vhp_s64, p &C.atomic64_t) C.vhp_s64 {
	unsafe { return native64(C.vhp_add_return64(&p.counter, bits(value), 0))
	 }
}

@[export: 'arch_atomic64_sub_return_relaxed']
pub fn atomic64_sub_return_relaxed(value C.vhp_s64, p &C.atomic64_t) C.vhp_s64 {
	unsafe { return native64(C.vhp_sub_return64(&p.counter, bits(value), 0))
	 }
}

@[export: 'arch_atomic64_fetch_add_relaxed']
pub fn atomic64_fetch_add_relaxed(value C.vhp_s64, p &C.atomic64_t) C.vhp_s64 {
	unsafe { return native64(C.vhp_add64(&p.counter, bits(value), 0))
	 }
}

@[export: 'arch_atomic64_fetch_sub_relaxed']
pub fn atomic64_fetch_sub_relaxed(value C.vhp_s64, p &C.atomic64_t) C.vhp_s64 {
	unsafe { return native64(C.vhp_sub64(&p.counter, bits(value), 0))
	 }
}

@[export: 'arch_atomic64_fetch_and_relaxed']
pub fn atomic64_fetch_and_relaxed(value C.vhp_s64, p &C.atomic64_t) C.vhp_s64 {
	unsafe { return native64(C.vhp_and64(&p.counter, bits(value), 0))
	 }
}

@[export: 'arch_atomic64_fetch_or_relaxed']
pub fn atomic64_fetch_or_relaxed(value C.vhp_s64, p &C.atomic64_t) C.vhp_s64 {
	unsafe { return native64(C.vhp_or64(&p.counter, bits(value), 0))
	 }
}

@[export: 'arch_atomic64_fetch_xor_relaxed']
pub fn atomic64_fetch_xor_relaxed(value C.vhp_s64, p &C.atomic64_t) C.vhp_s64 {
	unsafe { return native64(C.vhp_xor64(&p.counter, bits(value), 0))
	 }
}

@[export: 'arch_atomic64_xchg_relaxed']
pub fn atomic64_xchg_relaxed(p &C.atomic64_t, value C.vhp_s64) C.vhp_s64 {
	unsafe { return native64(C.vhp_exchange64(&p.counter, bits(value), 0))
	 }
}

// ABI adapters invoke this before evaluating the caller's lock expression.
@[export: 'vinix_local_irq_save']
pub fn irq_save() usize {
	return C.vinix_linuxkpi_irq_save()
}

@[export: 'vinix_local_irq_restore']
pub fn irq_restore(flags usize) {
	C.vinix_linuxkpi_irq_restore(flags)
}
