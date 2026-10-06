// SPDX-License-Identifier: GPL-2.0-or-later
// Native SRCU keeps Linux's small-domain reader banks, encoded grace-period
// sequence, callback FIFO and embedded work on one permanent unbound queue.
@[translated]
module compatcore

#include "linuxkpi_srcu_v_primitives.h"

struct C.vks_rcu_head {
mut:
	next &C.vks_rcu_head
	func fn (&C.callback_head)
}
struct C.vks_cblist {
mut:
	head &C.vks_rcu_head
	tails [4]&&C.vks_rcu_head
	gp_seq [4]u64
	len i64
	seglen [4]i64
	flags u8
}
struct C.vks_work {
mut:
	data i64
	entry C.vkw_list
	func fn (&C.work_struct)
}
struct C.vks_delayed_work {
mut:
	work C.vks_work
	timer C.vks_timer
	wq voidptr
	cpu i32
}
struct C.vks_timer {
mut:
	next voidptr
	pprev voidptr
	expires u64
	function fn (&C.timer_list)
	flags u32
}
struct C.vks_srcu_data {
mut:
	srcu_lock_count [2]i64
	srcu_unlock_count [2]i64
	lock u32
	srcu_cblist C.vks_cblist
	srcu_gp_seq_needed u64
	srcu_gp_seq_needed_exp u64
	srcu_cblist_invoking bool
	work C.vks_work
	mynode voidptr
	grpmask u64
	cpu i32
	ssp voidptr
}
struct C.vks_srcu_usage {
mut:
	node voidptr
	level [3]voidptr
	srcu_size_state i32
	srcu_cb_mutex C.vkw_mutex
	lock u32
	srcu_gp_mutex C.vkw_mutex
	srcu_gp_seq u64
	srcu_gp_seq_needed u64
	srcu_gp_seq_needed_exp u64
	sda_is_static bool
	srcu_barrier_seq u64
	srcu_barrier_mutex C.vkw_mutex
	srcu_barrier_completion C.vkw_completion
	srcu_barrier_cpu_cnt i32
	work C.vks_delayed_work
	srcu_ssp voidptr
}
struct C.vks_srcu {
mut:
	srcu_idx u32
	sda voidptr
	srcu_sup voidptr
}
fn C.vks_init_work(voidptr, voidptr)
fn C.vks_init_delayed_work(voidptr, voidptr)
fn C.vks_gp_callback() voidptr
fn C.vks_cblist_callback() voidptr
fn C.vks_unbound_ready() bool
fn C.vks_preempt_disable()
fn C.vks_preempt_enable()
fn C.vks_preempt_count() u32
fn C.vks_cpu_id() u32
fn C.vks_data_alignment() usize
fn C.alloc_workqueue(&char, u32, i32, ...voidptr) voidptr
fn C.vks_queue_work(voidptr, voidptr) bool
fn C.vks_queue_delayed_work(voidptr, voidptr, u64) bool
fn C.cancel_delayed_work_sync(voidptr) bool
fn C.flush_work(voidptr) bool
fn C.cancel_work_sync(voidptr) bool
fn C.destroy_workqueue(voidptr)
fn C.msleep(u32)
@[c: '__atomic_thread_fence']
fn C.vks_fence(i32)
@[c: '__atomic_fetch_add']
fn C.vks_add_reader(&i64, i64, i32) i64
@[c: '__atomic_add_fetch']
fn C.vks_add_index(&u32, u32, i32) u32
@[c: '__atomic_store_n']
fn C.vks_store64(&u64, u64, i32)

__global vks_srcu_workqueue voidptr

fn srcu_sequence_done(observed u64, target u64) bool { return i64(observed - target) >= 0 }
fn srcu_sequence_snapshot(sequence u64) u64 { return (sequence + 7) & ~u64(3) }
fn srcu_sequence_request(storage voidptr, target u64) {
	unsafe {
		needed := &u64(storage)
		if !srcu_sequence_done(*needed, target) { *needed = target }
	}
}
fn srcu_callback_data(ssp &C.vks_srcu) &C.vks_srcu_data {
	unsafe { return &C.vks_srcu_data(percpu_ptr(ssp.sda, 0)) }
}
fn srcu_init_callback_list(list &C.vks_cblist) {
	unsafe {
		list.head = nil
		for segment := 0; segment < 4; segment++ {
			list.tails[segment] = &list.head
			list.gp_seq[segment] = 0
			list.seglen[segment] = 0
		}
		list.len = 0
		list.flags = 0
	}
}
fn srcu_initialize_usage(ssp &C.vks_srcu, sup &C.vks_srcu_usage, data voidptr, is_static bool) {
	unsafe {
		// Static reader counters and srcu_idx may already contain live readers.
		sup.node = nil
		for level := 0; level < 3; level++ { sup.level[level] = nil }
		sup.srcu_size_state = 0
		mutex_init(&sup.srcu_cb_mutex, nil, nil)
		mutex_init(&sup.srcu_gp_mutex, nil, nil)
		mutex_init(&sup.srcu_barrier_mutex, nil, nil)
		sup.srcu_barrier_completion.done = 0
		init_swait_queue_head(&sup.srcu_barrier_completion.@wait, nil, nil)
		C.vkp_store_signed(&sup.srcu_barrier_cpu_cnt, 0, 0)
		sup.srcu_gp_seq = 0
		sup.srcu_gp_seq_needed_exp = 0
		sup.srcu_barrier_seq = 0
		sup.sda_is_static = is_static
		sup.srcu_ssp = ssp
		C.vks_init_delayed_work(&sup.work, C.vks_gp_callback())
		for cpu := u32(0); cpu < percpu_count(); cpu++ {
			sdp := &C.vks_srcu_data(percpu_ptr(data, cpu))
			C.vkp_spin_init(&sdp.lock)
			srcu_init_callback_list(&sdp.srcu_cblist)
			sdp.srcu_cblist_invoking = false
			sdp.srcu_gp_seq_needed = 0
			sdp.srcu_gp_seq_needed_exp = 0
			C.vks_init_work(&sdp.work, C.vks_cblist_callback())
			sdp.mynode = nil
			sdp.grpmask = 0
			sdp.cpu = i32(cpu)
			sdp.ssp = ssp
		}
		// Replace the original -1 lazy-init sentinel only after publication.
		C.vks_store64(&sup.srcu_gp_seq_needed, 0, 3)
	}
}
fn srcu_initialized_usage(ssp &C.vks_srcu) &C.vks_srcu_usage {
	unsafe {
		sup := &C.vks_srcu_usage(C.vkw_load_pointer(&ssp.srcu_sup, 2))
		require(!is_null(sup) && !is_null(ssp.sda))
		if C.vkp_load64(&sup.srcu_gp_seq_needed, 2) != u64(-1) { return sup }
		flags := C.vkp_spin_lock_irqsave(&sup.lock)
		if sup.srcu_gp_seq_needed == u64(-1) { srcu_initialize_usage(ssp, sup, ssp.sda, true) }
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
		return sup
	}
}
fn srcu_bootstrap_limit(active_limit u32) i32 {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		require(C.vks_unbound_ready() && percpu_count() != 0)
		if !is_null(C.vkw_load_pointer(&vks_srcu_workqueue, 2)) { return 0 }
		queue := C.alloc_workqueue(c'linuxkpi-srcu', 2, i32(active_limit))
		if is_null(queue) { return -12 }
		C.vkw_store_pointer(&vks_srcu_workqueue, queue, 3)
		return 0
	}
}
@[export: 'vinix_linuxkpi_srcu_bootstrap']
pub fn srcu_bootstrap() i32 { return srcu_bootstrap_limit(0) }
@[export: 'srcu_init']
pub fn srcu_init() { require(srcu_bootstrap() == 0) }
@[export: 'init_srcu_struct']
pub fn init_srcu_struct(storage voidptr) i32 {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep() && !is_null(storage))
		ssp := &C.vks_srcu(storage)
		ssp.srcu_idx = 0
		ssp.sda = nil
		ssp.srcu_sup = nil
		sup := &C.vks_srcu_usage(C.kzalloc(sizeof(C.vks_srcu_usage), 3264))
		if is_null(sup) { return -12 }
		data := alloc_percpu_gfp(sizeof(C.vks_srcu_data), C.vks_data_alignment(), 3264)
		if is_null(data) { C.kfree(sup); return -12 }
		C.vkp_spin_init(&sup.lock)
		srcu_initialize_usage(ssp, sup, data, false)
		C.vkw_store_pointer(&ssp.sda, data, 3)
		C.vkw_store_pointer(&ssp.srcu_sup, sup, 3)
		return 0
	}
}
@[export: '__srcu_read_lock']
pub fn srcu_read_lock(storage voidptr) i32 {
	unsafe {
		ssp := &C.vks_srcu(storage)
		require(!is_null(ssp) && !is_null(ssp.sda))
		C.vks_preempt_disable()
		index := C.vkp_load32(&ssp.srcu_idx, 0) & 1
		sdp := &C.vks_srcu_data(percpu_ptr(ssp.sda, C.vks_cpu_id()))
		C.vks_add_reader(&sdp.srcu_lock_count[index], 1, 0)
		C.vks_fence(5)
		C.vks_preempt_enable()
		return i32(index)
	}
}
@[export: '__srcu_read_unlock']
pub fn srcu_read_unlock(storage voidptr, index i32) {
	unsafe {
		ssp := &C.vks_srcu(storage)
		require(!is_null(ssp) && !is_null(ssp.sda) && (index & ~i32(1)) == 0)
		C.vks_fence(5)
		C.vks_preempt_disable()
		sdp := &C.vks_srcu_data(percpu_ptr(ssp.sda, C.vks_cpu_id()))
		C.vks_add_reader(&sdp.srcu_unlock_count[index], 1, 0)
		C.vks_preempt_enable()
	}
}
fn srcu_readers_done(ssp &C.vks_srcu, index u32) bool {
	unsafe {
		mut unlocks := u64(0)
		mut locks := u64(0)
		for cpu := u32(0); cpu < percpu_count(); cpu++ {
			sdp := &C.vks_srcu_data(percpu_ptr(ssp.sda, cpu))
			unlocks += u64(C.vkw_load_owner(&sdp.srcu_unlock_count[index], 0))
		}
		C.vks_fence(5)
		for cpu := u32(0); cpu < percpu_count(); cpu++ {
			sdp := &C.vks_srcu_data(percpu_ptr(ssp.sda, cpu))
			locks += u64(C.vkw_load_owner(&sdp.srcu_lock_count[index], 0))
		}
		return locks == unlocks
	}
}
fn srcu_updater_queue() voidptr {
	unsafe { queue := C.vkw_load_pointer(&vks_srcu_workqueue, 2); require(!is_null(queue)); return queue }
}
fn srcu_kick_updater(sup &C.vks_srcu_usage) { unsafe { C.vks_queue_delayed_work(srcu_updater_queue(), &sup.work, 0) } }
@[export: 'call_srcu']
pub fn call_srcu(storage voidptr, record voidptr, function fn (&C.callback_head)) {
	unsafe {
		head := &C.vks_rcu_head(record)
		require(!is_null(head) && usize(function) != 0)
		ssp := &C.vks_srcu(storage)
		sup := srcu_initialized_usage(ssp)
		C.vks_fence(5)
		flags := C.vkp_spin_lock_irqsave(&sup.lock)
		sdp := srcu_callback_data(ssp)
		list := &sdp.srcu_cblist
		require(list.len != i64(0x7fffffffffffffff))
		head.next = nil
		head.func = function
		*list.tails[3] = head
		list.tails[3] = &head.next
		list.len++
		sdp.srcu_gp_seq_needed++
		srcu_sequence_request(&sup.srcu_gp_seq_needed, srcu_sequence_snapshot(sup.srcu_gp_seq))
		srcu_kick_updater(sup)
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
	}
}
@[export: 'vinix_linuxkpi_srcu_gp_work']
pub fn srcu_gp_work(work &C.work_struct) {
	unsafe {
		sup := &C.vks_srcu_usage(usize(work) - __offsetof(C.vks_srcu_usage, work))
		ssp := &C.vks_srcu(sup.srcu_ssp)
		sdp := srcu_callback_data(ssp)
		mut flags := C.vkp_spin_lock_irqsave(&sup.lock)
		mut sequence := sup.srcu_gp_seq
		if (sequence & 3) == 0 {
			if srcu_sequence_done(sequence, sup.srcu_gp_seq_needed) {
				C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
				return
			}
			sdp.srcu_cblist.gp_seq[1] = sdp.srcu_gp_seq_needed
			sequence++
			C.vks_store64(&sup.srcu_gp_seq, sequence, 3)
		}
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
		mut index := C.vkp_load32(&ssp.srcu_idx, 0) & 1
		if (sequence & 3) == 1 {
			if !srcu_readers_done(ssp, index ^ 1) { C.vks_queue_delayed_work(srcu_updater_queue(), &sup.work, 1); return }
			C.vks_fence(5)
			C.vks_add_index(&ssp.srcu_idx, 1, 0)
			C.vks_fence(5)
			flags = C.vkp_spin_lock_irqsave(&sup.lock)
			sequence++
			C.vks_store64(&sup.srcu_gp_seq, sequence, 3)
			C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
			index ^= 1
		}
		require((sequence & 3) == 2)
		if !srcu_readers_done(ssp, index ^ 1) { C.vks_queue_delayed_work(srcu_updater_queue(), &sup.work, 1); return }
		C.vks_fence(5)
		flags = C.vkp_spin_lock_irqsave(&sup.lock)
		completed := (sequence & ~u64(3)) + 4
		C.vks_store64(&sup.srcu_gp_seq, completed, 3)
		srcu_sequence_request(&sdp.srcu_gp_seq_needed_exp, sdp.srcu_cblist.gp_seq[1])
		if !srcu_sequence_done(sup.srcu_barrier_seq, sdp.srcu_gp_seq_needed_exp) { C.vks_queue_work(srcu_updater_queue(), &sdp.work) }
		if !srcu_sequence_done(completed, sup.srcu_gp_seq_needed) { srcu_kick_updater(sup) }
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
	}
}
@[export: 'vinix_linuxkpi_srcu_callback_work']
pub fn srcu_callback_work(work &C.work_struct) {
	unsafe {
		sdp := &C.vks_srcu_data(usize(work) - __offsetof(C.vks_srcu_data, work))
		sup := &C.vks_srcu_usage((&C.vks_srcu(sdp.ssp)).srcu_sup)
		mut flags := C.vkp_spin_lock_irqsave(&sup.lock)
		target := sdp.srcu_gp_seq_needed_exp
		sdp.srcu_cblist_invoking = true
		for !srcu_sequence_done(sup.srcu_barrier_seq, target) {
			list := &sdp.srcu_cblist
			head := list.head
			require(!is_null(head) && list.len != 0)
			list.head = head.next
			if is_null(list.head) { list.tails[3] = &list.head }
			function := head.func
			head.next = nil
			C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
			require(C.vinix_linuxkpi_may_sleep())
			C.vks_preempt_disable()
			function(&C.callback_head(head)) // Callback may free or requeue head; never read it again.
			require(C.vks_preempt_count() == 1 && !C.vkw_irqs_disabled())
			C.vks_preempt_enable()
			flags = C.vkp_spin_lock_irqsave(&sup.lock)
			require(list.len != 0)
			list.len--
			sup.srcu_barrier_seq++
			if C.vkp_load_signed(&sup.srcu_barrier_cpu_cnt, 0) != 0 { complete(&sup.srcu_barrier_completion) }
		}
		sdp.srcu_cblist_invoking = false
		if !srcu_sequence_done(sup.srcu_barrier_seq, sdp.srcu_gp_seq_needed_exp) { C.vks_queue_work(srcu_updater_queue(), &sdp.work) }
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
	}
}
@[export: 'get_state_synchronize_srcu']
pub fn get_state_synchronize_srcu(storage voidptr) u64 {
	unsafe {
		sup := srcu_initialized_usage(&C.vks_srcu(storage))
		C.vks_fence(5)
		cookie := srcu_sequence_snapshot(C.vkp_load64(&sup.srcu_gp_seq, 2))
		C.vks_fence(5)
		return cookie
	}
}
@[export: 'start_poll_synchronize_srcu']
pub fn start_poll_synchronize_srcu(storage voidptr) u64 {
	unsafe {
		sup := srcu_initialized_usage(&C.vks_srcu(storage))
		C.vks_fence(5)
		flags := C.vkp_spin_lock_irqsave(&sup.lock)
		cookie := srcu_sequence_snapshot(sup.srcu_gp_seq)
		srcu_sequence_request(&sup.srcu_gp_seq_needed, cookie)
		srcu_kick_updater(sup)
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
		return cookie
	}
}
@[export: 'poll_state_synchronize_srcu']
pub fn poll_state_synchronize_srcu(storage voidptr, cookie u64) bool {
	unsafe {
		sup := srcu_initialized_usage(&C.vks_srcu(storage))
		if !srcu_sequence_done(C.vkp_load64(&sup.srcu_gp_seq, 2), cookie) { return false }
		C.vks_fence(5)
		return true
	}
}
fn srcu_synchronize_domain(ssp &C.vks_srcu, expedited bool) {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		sup := srcu_initialized_usage(ssp)
		C.vks_fence(5)
		flags := C.vkp_spin_lock_irqsave(&sup.lock)
		cookie := srcu_sequence_snapshot(sup.srcu_gp_seq)
		srcu_sequence_request(&sup.srcu_gp_seq_needed, cookie)
		if expedited { srcu_sequence_request(&sup.srcu_gp_seq_needed_exp, cookie) }
		srcu_kick_updater(sup)
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
		for !poll_state_synchronize_srcu(ssp, cookie) { C.msleep(1) }
		C.vks_fence(5)
	}
}
@[export: 'synchronize_srcu']
pub fn synchronize_srcu(storage voidptr) { unsafe { srcu_synchronize_domain(&C.vks_srcu(storage), false) } }
@[export: 'synchronize_srcu_expedited']
pub fn synchronize_srcu_expedited(storage voidptr) { unsafe { srcu_synchronize_domain(&C.vks_srcu(storage), true) } }
@[export: 'srcu_barrier']
pub fn srcu_barrier(storage voidptr) {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		ssp := &C.vks_srcu(storage)
		sup := srcu_initialized_usage(ssp)
		C.vks_fence(5)
		mut flags := C.vkp_spin_lock_irqsave(&sup.lock)
		target := srcu_callback_data(ssp).srcu_gp_seq_needed
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
		mutex_lock(&sup.srcu_barrier_mutex)
		flags = C.vkp_spin_lock_irqsave(&sup.lock)
		for !srcu_sequence_done(sup.srcu_barrier_seq, target) {
			sup.srcu_barrier_completion.done = 0
			C.vkp_store_signed(&sup.srcu_barrier_cpu_cnt, 1, 0)
			C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
			wait_for_completion(&sup.srcu_barrier_completion)
			flags = C.vkp_spin_lock_irqsave(&sup.lock)
			C.vkp_store_signed(&sup.srcu_barrier_cpu_cnt, 0, 0)
		}
		C.vkp_spin_unlock_irqrestore(&sup.lock, flags)
		mutex_unlock(&sup.srcu_barrier_mutex)
		C.vks_fence(5)
	}
}
fn srcu_quiesce_domain(ssp &C.vks_srcu, sup &C.vks_srcu_usage) {
	unsafe {
		require(srcu_readers_done(ssp, 0) && srcu_readers_done(ssp, 1))
		synchronize_srcu(ssp)
		srcu_barrier(ssp)
		C.cancel_delayed_work_sync(&sup.work)
		sdp := srcu_callback_data(ssp)
		C.flush_work(&sdp.work)
		C.cancel_work_sync(&sdp.work)
		require(srcu_readers_done(ssp, 0) && srcu_readers_done(ssp, 1))
		require(sdp.srcu_cblist.len == 0 && is_null(sdp.srcu_cblist.head)
			&& !sdp.srcu_cblist_invoking && (sup.srcu_gp_seq & 3) == 0
			&& srcu_sequence_done(sup.srcu_gp_seq, sup.srcu_gp_seq_needed))
	}
}
@[export: 'cleanup_srcu_struct']
pub fn cleanup_srcu_struct(storage voidptr) {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep() && !is_null(storage))
		ssp := &C.vks_srcu(storage)
		if is_null(ssp.srcu_sup) { require(is_null(ssp.sda)); return }
		sup := srcu_initialized_usage(ssp)
		require(!sup.sda_is_static)
		srcu_quiesce_domain(ssp, sup)
		data := ssp.sda
		ssp.sda = nil
		ssp.srcu_sup = nil
		free_percpu(data)
		C.kfree(sup)
	}
}
@[export: 'vinix_linuxkpi_srcu_bootstrap_limit_for_test']
pub fn srcu_bootstrap_limit_for_test(active_limit u32) i32 {
	require(active_limit >= 2 && active_limit <= 512)
	return srcu_bootstrap_limit(active_limit)
}
@[export: 'vinix_linuxkpi_srcu_queue_for_test']
pub fn srcu_queue_for_test() voidptr { return srcu_updater_queue() }
@[export: 'vinix_linuxkpi_srcu_shutdown_for_test']
pub fn srcu_shutdown_for_test() {
	unsafe {
		queue := C.vkw_load_pointer(&vks_srcu_workqueue, 2)
		if is_null(queue) { return }
		C.destroy_workqueue(queue)
		C.vkw_store_pointer(&vks_srcu_workqueue, nil, 3)
	}
}
@[export: 'vinix_linuxkpi_srcu_static_quiesce_for_test']
pub fn srcu_static_quiesce_for_test(storage voidptr) {
	unsafe {
		ssp := &C.vks_srcu(storage)
		sup := srcu_initialized_usage(ssp)
		require(sup.sda_is_static)
		srcu_quiesce_domain(ssp, sup)
	}
}
