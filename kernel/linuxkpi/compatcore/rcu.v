// SPDX-License-Identifier: GPL-2.0-or-later
// Scoped nonpreemptible ordinary RCU: immutable boot CPUs report actual native
// outer-IRQ returns. Private GP/callback pthreads consume no workqueue slots.
@[translated]
module compatcore

#include "linuxkpi_rcu_v_primitives.h"

struct C.vkr_rcu_head {
mut:
	next &C.vkr_rcu_head
	func fn (&C.callback_head)
}
struct RcuWorker {
mut:
	task voidptr
	thread u64
	stop u32
	ready C.vkw_completion
}
fn C.vkr_rcu_worker_function(bool) voidptr
fn C.vkr_rcu_pthread_create(voidptr, voidptr, voidptr) i32
fn C.vkr_rcu_pthread_join(u64) i32
fn C.vkr_rcu_worker_enter()
fn C.vkr_rcu_thread_exit()
fn C.vkr_rcu_get_current() voidptr
fn C.vkr_rcu_put_task(voidptr)
fn C.vkr_rcu_task_retired(voidptr) bool
fn C.vkr_rcu_load32(&u32, i32) u32
fn C.vkr_rcu_store32(&u32, u32, i32)
fn C.vkr_rcu_load64(&u64, i32) u64
fn C.vkr_rcu_store64(&u64, u64, i32)
fn C.vkr_rcu_fence(i32)
fn C.vkm_cpu_masks_ready() bool
fn C.vkm_cpu_ids() u32
fn C.vkm_online_count() u32
fn C.vks_smp_ready() bool
fn C.vinix_linuxkpi_smp_boot_context() bool
fn C.vinix_linuxkpi_smp_task_present() bool
fn C.vinix_linuxkpi_rcu_force_quiescence()
fn C.vinix_linuxkpi_maskable_irq_depth() u32
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vkr_page_allocation_size(voidptr) usize
fn C.vkr_kvfree(voidptr)

__global (
	vkr_rcu_published u32
	vkr_rcu_cpu_count u32
	vkr_rcu_guard u32
	vkr_rcu_request u64
	vkr_rcu_acknowledged [256]u64
	vkr_rcu_sequence u64
	vkr_rcu_needed u64
	vkr_rcu_enqueued u64
	vkr_rcu_completed u64
	vkr_rcu_pending_head &C.vkr_rcu_head
	vkr_rcu_pending_tail &C.vkr_rcu_head
	vkr_rcu_pending_count u64
	vkr_rcu_ready_head &C.vkr_rcu_head
	vkr_rcu_ready_tail &C.vkr_rcu_head
	vkr_rcu_ready_count u64
	vkr_rcu_gp_owner &RcuWorker
	vkr_rcu_callback_owner &RcuWorker
)

fn rcu_sequence_done(observed u64, target u64) bool { return i64(observed - target) >= 0 }
// Original rcu_seq_done_exact(): a public cookie may outlive the half-range
// guard band used by internal grace-period and callback ordinal accounting.
fn rcu_sequence_exact_done(observed u64, cookie u64) bool {
	return i64(observed - cookie) >= 0 || i64(observed - (cookie - 7)) < 0
}
fn rcu_sequence_snapshot(sequence u64) u64 { return (sequence + 7) & ~u64(3) }
fn rcu_request_locked(target u64) {
	unsafe { if !rcu_sequence_done(vkr_rcu_needed, target) { vkr_rcu_needed = target } }
}
fn rcu_sleepable_context() bool {
	return C.vinix_linuxkpi_may_sleep() && C.vinix_linuxkpi_smp_task_present()
		&& C.vinix_linuxkpi_maskable_irq_depth() == 0 && C.vinix_linuxkpi_preempt_count() == 0
		&& (C.vinix_linuxkpi_irq_flags() & 512) != 0
}
@[export: 'vkr_rcu_ready']
pub fn rcu_domain_ready() bool { return unsafe { C.vkr_rcu_load32(&vkr_rcu_published, 2) != 0 } }

// Only the root's actual native saved-context gate may call this. It is not a
// reader API or a guess based on another CPU's task/idle state.
@[export: 'vkr_rcu_quiescent']
pub fn rcu_quiescent(cpu u32) {
	unsafe {
		if !rcu_domain_ready() { return }
		require(cpu < vkr_rcu_cpu_count)
		target := C.vkr_rcu_load64(&vkr_rcu_request, 2)
		C.vkr_rcu_fence(5)
		C.vkr_rcu_store64(&vkr_rcu_acknowledged[cpu], target, 3)
	}
}
fn rcu_worker_stopping(worker &RcuWorker) bool { unsafe { return C.vkr_rcu_load32(&worker.stop, 2) != 0 } }
fn rcu_enter_worker(worker &RcuWorker) {
	unsafe {
		C.vkr_rcu_worker_enter()
		worker.task = C.vkr_rcu_get_current()
		require(!is_null(worker.task))
		complete(&worker.ready)
	}
}
fn rcu_join_worker(worker &RcuWorker) {
	unsafe {
		require(C.vkr_rcu_pthread_join(worker.thread) == 0)
		for !C.vkr_rcu_task_retired(worker.task) { C.vinix_linuxkpi_cond_resched() }
		C.vkr_rcu_put_task(worker.task)
		C.kfree(worker)
	}
}
fn rcu_stop_worker(worker &RcuWorker) {
	unsafe { C.vkr_rcu_store32(&worker.stop, 1, 3) }
	rcu_join_worker(worker)
}
fn rcu_start_worker(callback bool) &RcuWorker {
	unsafe {
		worker := &RcuWorker(C.kzalloc(sizeof(RcuWorker), 3264))
		if is_null(worker) { return nil }
		init_swait_queue_head(&worker.ready.@wait, nil, nil)
		if C.vkr_rcu_pthread_create(&worker.thread, C.vkr_rcu_worker_function(callback), worker) != 0 {
			C.kfree(worker)
			return nil
		}
		wait_for_completion(&worker.ready)
		return worker
	}
}
@[export: 'vkr_rcu_bootstrap']
pub fn rcu_bootstrap(count u32) i32 {
	if count == 0 || count > 256 || !C.vkm_cpu_masks_ready() || !C.vks_smp_ready()
		|| count != C.vkm_cpu_ids() || count != C.vkm_online_count() { return -22 }
	if rcu_domain_ready() { return -114 }
	if !C.vinix_linuxkpi_smp_boot_context() { return -1 }
	gp := rcu_start_worker(false)
	if is_null(gp) { return -12 }
	callback := rcu_start_worker(true)
	if is_null(callback) { rcu_stop_worker(gp); return -12 }
	unsafe {
		C.vkp_spin_init(&vkr_rcu_guard)
		vkr_rcu_cpu_count = count
		vkr_rcu_request = 0
		vkr_rcu_sequence = 0
		vkr_rcu_needed = 0
		vkr_rcu_enqueued = 0
		vkr_rcu_completed = 0
		vkr_rcu_pending_head = nil
		vkr_rcu_pending_tail = nil
		vkr_rcu_pending_count = 0
		vkr_rcu_ready_head = nil
		vkr_rcu_ready_tail = nil
		vkr_rcu_ready_count = 0
		for cpu := 0; cpu < 256; cpu++ { vkr_rcu_acknowledged[cpu] = 0 }
		vkr_rcu_gp_owner = gp
		vkr_rcu_callback_owner = callback
		C.vkr_rcu_store32(&vkr_rcu_published, 1, 3)
	}
	return 0
}

// The low 4096 values are private embedded-free offsets. Store the raw bits
// without constructing or reading an invalid function-pointer value. The
// typed original head and its layout stay unchanged.
fn rcu_enqueue(storage voidptr, bits usize) {
	unsafe {
		require(rcu_domain_ready() && !is_null(storage)
			&& usize(storage) % sizeof(voidptr) == 0)
		head := &C.vkr_rcu_head(storage)
		C.vkr_rcu_fence(5)
		flags := C.vkp_spin_lock_irqsave(&vkr_rcu_guard)
		head.next = nil
		C.memcpy(&head.func, &bits, sizeof(usize))
		if is_null(vkr_rcu_pending_tail) { vkr_rcu_pending_head = head }
		else { vkr_rcu_pending_tail.next = head }
		vkr_rcu_pending_tail = head
		require(vkr_rcu_pending_count != u64(-1))
		vkr_rcu_pending_count++
		vkr_rcu_enqueued++
		rcu_request_locked(rcu_sequence_snapshot(vkr_rcu_sequence))
		C.vkp_spin_unlock_irqrestore(&vkr_rcu_guard, flags)
		// The node may already be executing or freed; never inspect it again.
	}
}
@[export: 'vkr_rcu_call']
pub fn rcu_call(storage voidptr, callback fn (&C.callback_head)) {
	unsafe {
		mut bits := usize(0)
		C.memcpy(&bits, &callback, sizeof(usize))
		require(bits >= 4096)
		rcu_enqueue(storage, bits)
	}
}
@[export: 'vkr_kvfree_call_rcu']
pub fn rcu_kvfree(storage voidptr, base voidptr) {
	require(rcu_domain_ready())
	if is_null(storage) {
		// Original TREE_RCU permits an allocation-free synchronous fallback
		// for a headless submission. It must be an ordinary sleepable task,
		// and must start a real future GP before releasing the owned pages.
		require(rcu_sleepable_context())
		if usize(base) > 16 { C.vkr_page_allocation_size(base) }
		rcu_synchronize(false)
		C.vkr_kvfree(base)
		return
	}
	address := usize(storage)
	owner := usize(base)
	require(address % sizeof(voidptr) == 0 && owner > 16 && address >= owner)
	offset := address - owner
	require(offset < 4096)
	span := C.vkr_page_allocation_size(base)
	require(span <= usize(-1) - owner && span >= sizeof(C.vkr_rcu_head)
		&& offset <= span - sizeof(C.vkr_rcu_head))
	// Every ownership/range check precedes publication and head mutation.
	// The enqueue path borrows only the existing intrusive record.
	rcu_enqueue(storage, offset)
}
@[export: 'vkr_rcu_get_state']
pub fn rcu_get_state() u64 {
	unsafe {
		require(rcu_domain_ready())
		C.vkr_rcu_fence(5)
		cookie := rcu_sequence_snapshot(C.vkr_rcu_load64(&vkr_rcu_sequence, 2))
		C.vkr_rcu_fence(5)
		return cookie
	}
}
@[export: 'vkr_rcu_start_poll']
pub fn rcu_start_poll() u64 {
	unsafe {
		require(rcu_domain_ready() && (C.vinix_linuxkpi_irq_flags() & 512) != 0)
		C.vkr_rcu_fence(5)
		flags := C.vkp_spin_lock_irqsave(&vkr_rcu_guard)
		cookie := rcu_sequence_snapshot(vkr_rcu_sequence)
		rcu_request_locked(cookie)
		C.vkp_spin_unlock_irqrestore(&vkr_rcu_guard, flags)
		C.vkr_rcu_fence(5)
		return cookie
	}
}
@[export: 'vkr_rcu_poll']
pub fn rcu_poll(cookie u64) bool {
	unsafe {
		require(rcu_domain_ready())
		if !rcu_sequence_exact_done(C.vkr_rcu_load64(&vkr_rcu_sequence, 2), cookie) { return false }
		C.vkr_rcu_fence(5)
		return true
	}
}
@[export: 'vkr_rcu_cond']
pub fn rcu_cond(cookie u64) {
	require(rcu_sleepable_context())
	if !rcu_poll(cookie) { rcu_synchronize(false) }
	C.vkr_rcu_fence(5)
}
@[export: 'vkr_rcu_synchronize']
pub fn rcu_synchronize(_expedited bool) {
	require(rcu_sleepable_context())
	cookie := rcu_start_poll()
	for !rcu_poll(cookie) { C.msleep(1) }
	C.vkr_rcu_fence(5)
}
@[export: 'vkr_rcu_barrier']
pub fn rcu_callbacks_barrier() {
	unsafe {
		require(rcu_domain_ready() && rcu_sleepable_context())
		C.vkr_rcu_fence(5)
		flags := C.vkp_spin_lock_irqsave(&vkr_rcu_guard)
		target := vkr_rcu_enqueued
		C.vkp_spin_unlock_irqrestore(&vkr_rcu_guard, flags)
		for !rcu_sequence_done(C.vkr_rcu_load64(&vkr_rcu_completed, 2), target) { C.msleep(1) }
		C.vkr_rcu_fence(5)
	}
}

fn rcu_all_cpus_acknowledged(target u64) bool {
	unsafe {
		for cpu := u32(0); cpu < vkr_rcu_cpu_count; cpu++ {
			if !rcu_sequence_done(C.vkr_rcu_load64(&vkr_rcu_acknowledged[cpu], 2), target) { return false }
		}
		return true
	}
}
@[export: 'vkr_rcu_gp_worker']
pub fn rcu_gp_worker(argument voidptr) voidptr {
	unsafe {
		worker := &RcuWorker(argument)
		rcu_enter_worker(worker)
		mut active := false
		mut target := u64(0)
		mut batch := &C.vkr_rcu_head(nil)
		mut tail := &C.vkr_rcu_head(nil)
		mut count := u64(0)
		for !rcu_worker_stopping(worker) {
			if !rcu_domain_ready() { C.msleep(1); continue }
			flags := C.vkp_spin_lock_irqsave(&vkr_rcu_guard)
			if !active && !rcu_sequence_done(vkr_rcu_sequence, vkr_rcu_needed) {
				batch = vkr_rcu_pending_head
				tail = vkr_rcu_pending_tail
				count = vkr_rcu_pending_count
				vkr_rcu_pending_head = nil
				vkr_rcu_pending_tail = nil
				vkr_rcu_pending_count = 0
				started := vkr_rcu_sequence + 1
				target = (started | 3) + 1
				C.vkr_rcu_store64(&vkr_rcu_sequence, started, 3)
				C.vkr_rcu_fence(5)
				C.vkr_rcu_store64(&vkr_rcu_request, target, 3)
				active = true
			}
			if active && rcu_all_cpus_acknowledged(target) {
				C.vkr_rcu_fence(5)
				C.vkr_rcu_store64(&vkr_rcu_sequence, target, 3)
				if !is_null(batch) {
					if is_null(vkr_rcu_ready_tail) { vkr_rcu_ready_head = batch }
					else { vkr_rcu_ready_tail.next = batch }
					vkr_rcu_ready_tail = tail
					require(count <= u64(-1) - vkr_rcu_ready_count)
					vkr_rcu_ready_count += count
				}
				batch = nil
				tail = nil
				count = 0
				active = false
			}
			C.vkp_spin_unlock_irqrestore(&vkr_rcu_guard, flags)
			// Requests may have interrupted an old pinned/IRQ scope. Keep asking
			// for a real return; neither IPI arrival nor a fixed delay is a QS.
			if active { C.vinix_linuxkpi_rcu_force_quiescence() }
			C.msleep(1)
		}
		require(!active && is_null(batch))
		C.vkr_rcu_thread_exit()
		return nil
	}
}
@[export: 'vkr_rcu_callback_worker']
pub fn rcu_callback_worker(argument voidptr) voidptr {
	unsafe {
		worker := &RcuWorker(argument)
		rcu_enter_worker(worker)
		for !rcu_worker_stopping(worker) {
			if !rcu_domain_ready() { C.msleep(1); continue }
			flags := C.vkp_spin_lock_irqsave(&vkr_rcu_guard)
			mut head := vkr_rcu_ready_head
			count := vkr_rcu_ready_count
			vkr_rcu_ready_head = nil
			vkr_rcu_ready_tail = nil
			vkr_rcu_ready_count = 0
			C.vkp_spin_unlock_irqrestore(&vkr_rcu_guard, flags)
			for index := u64(0); index < count; index++ {
				require(!is_null(head))
				next := head.next
				mut bits := usize(0)
				C.memcpy(&bits, &head.func, sizeof(usize))
				head.next = nil
				require(rcu_sleepable_context())
				C.vinix_linuxkpi_preempt_disable()
				C.vkr_rcu_fence(5)
				if bits < 4096 {
					C.memset(&head.func, 0, sizeof(voidptr))
					C.vkr_kvfree(voidptr(usize(head) - bits))
				} else {
					// Only the real-function branch reads the typed field.
					callback := head.func
					C.memset(&head.func, 0, sizeof(voidptr))
					callback(&C.callback_head(head))
				}
				// Callback may requeue or free its object. Only pointer values and
				// separate ordinal accounting remain live after invocation.
				require(C.vinix_linuxkpi_maskable_irq_depth() == 0
					&& C.vinix_linuxkpi_preempt_count() == 1
					&& (C.vinix_linuxkpi_irq_flags() & 512) != 0)
				C.vinix_linuxkpi_preempt_enable()
				retired_flags := C.vkp_spin_lock_irqsave(&vkr_rcu_guard)
				C.vkr_rcu_store64(&vkr_rcu_completed, vkr_rcu_completed + 1, 3)
				C.vkp_spin_unlock_irqrestore(&vkr_rcu_guard, retired_flags)
				head = next
			}
			require(is_null(head))
			C.msleep(1)
		}
		C.vkr_rcu_thread_exit()
		return nil
	}
}

$if linuxkpi_host_test ? {
	// Isolated fixture ownership only: producers stop before this call. Static
	// acknowledgement storage remains valid even as readiness is withdrawn.
	// Join every fixture QS actor after this call and before any new bootstrap;
	// a paused old actor must never publish into a reused test-domain epoch.
	@[export: 'vkr_rcu_shutdown_for_test']
	pub fn rcu_shutdown_for_test() {
		unsafe {
			require(rcu_domain_ready() && rcu_sleepable_context())
			rcu_callbacks_barrier()
			rcu_synchronize(false)
			flags := C.vkp_spin_lock_irqsave(&vkr_rcu_guard)
			require(is_null(vkr_rcu_pending_head) && is_null(vkr_rcu_ready_head)
				&& vkr_rcu_enqueued == vkr_rcu_completed
				&& rcu_sequence_done(vkr_rcu_sequence, vkr_rcu_needed))
			gp := vkr_rcu_gp_owner
			callback := vkr_rcu_callback_owner
			C.vkr_rcu_store32(&vkr_rcu_published, 0, 3)
			C.vkr_rcu_store32(&gp.stop, 1, 3)
			C.vkr_rcu_store32(&callback.stop, 1, 3)
			C.vkp_spin_unlock_irqrestore(&vkr_rcu_guard, flags)
			rcu_join_worker(gp)
			rcu_join_worker(callback)
			vkr_rcu_gp_owner = nil
			vkr_rcu_callback_owner = nil
		}
	}
}
