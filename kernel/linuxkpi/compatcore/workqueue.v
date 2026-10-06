// SPDX-License-Identifier: GPL-2.0-only
// Ordered, unbound and per-CPU queues retain the original pool/worker engine.
// Atomic queue/timer paths allocate nothing. Run/wait/cancel/flush records are
// stack values and all publication/removal is serialized by one raw lock.
@[translated]
module compatcore

#include "linuxkpi_workqueue_v_primitives.h"

@[aligned: 256]
struct WorkQueue {
mut:
	all C.vkw_list
	pending C.vkw_list
	delayed C.vkw_list
	sleepers C.vkw_list
	workers C.vkw_list
	manager &WqWorker
	pools &WqPool
	sequence u64
	generation u64
	drainers u32
	nr_pools u32
	max_active u32
	stop bool
	destroying bool
	ordered bool
	unbound bool
	highpri bool
	system bool
	name [32]char
}
@[aligned: 256]
struct WqPool {
mut:
	wq &WorkQueue
	cpu u32
	nr_workers u32
	nr_active u32
	nr_runnable u32
}
struct WqWorker {
mut:
	entry C.vkw_list
	wq &WorkQueue
	pool &WqPool
	task voidptr
	thread u64
	start_result i32
	ready C.vkw_completion
}
struct WorkBarrier {
mut:
	work C.vks_work
	target &C.vks_work
	sequence u64
	generation u64
	captured bool
	queue bool
}
struct WorkWait {
mut:
	entry C.vkw_list
	task voidptr
	done bool
}
struct WorkRun {
mut:
	entry C.vkw_list
	waiters C.vkw_list
	wq &WorkQueue
	pool &WqPool
	work &C.vks_work
	task voidptr
	sequence u64
	generation u64
	runnable bool
}
struct WorkCancel {
mut:
	entry C.vkw_list
	work &C.vks_work
}

@[c_extern]
__global C.system_wq voidptr
@[c_extern]
__global C.system_highpri_wq voidptr
@[c_extern]
__global C.system_unbound_wq voidptr
@[c_extern]
__global C.vkwq_running C.vkw_list
@[c_extern]
__global C.vkwq_canceling C.vkw_list
@[c_extern]
__global C.vkwq_all C.vkw_list
__global (
	vkwq_work_lock u32
	vkwq_bound_runnable [2][64]u32
)

fn C.vkwq_worker_callback() voidptr
fn C.vkwq_manager_callback() voidptr
fn C.vkwq_barrier_callback() voidptr
fn C.vkwq_delayed_callback() voidptr
fn C.vkwq_pthread_create(voidptr, voidptr, voidptr) i32
fn C.vkwq_pthread_join(u64) i32
fn C.vkwq_get_current() voidptr
fn C.vkwq_put_task(voidptr)
fn C.vkwq_task_state(voidptr) u32
fn C.vkwq_current_running() bool
fn C.vkwq_worker_enter()
fn C.vkwq_worker_leave()
fn C.vkwq_delayed_gate(voidptr)
fn C.vkwq_publish_gate(voidptr, u32)
fn C.vkwq_warn_queue_cpu(bool)
fn C.vkwq_warn_delayed_cpu(bool)
fn C.vkwq_warn_mod_cpu(bool)
fn C.vkwq_warn_limit()
fn C.vinix_linuxkpi_worker_set_nice(i32) i32
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_cond_resched() i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_irq_flags() u64
fn C.vinix_linuxkpi_spin_wait()
fn C.try_to_del_timer_sync(voidptr) i32
fn C.timer_delete_sync(voidptr) i32
fn C.mod_timer(voidptr, u64) i32

const work_no_pool = u64(0xfffffffe0)

fn wq_work_at(entry &C.vkw_list) &C.vks_work {
	unsafe { return &C.vks_work(usize(entry) - __offsetof(C.vks_work, entry)) }
}
fn wq_run_at(entry &C.vkw_list) &WorkRun {
	unsafe { return &WorkRun(usize(entry) - __offsetof(WorkRun, entry)) }
}
fn wq_wait_at(entry &C.vkw_list) &WorkWait {
	unsafe { return &WorkWait(usize(entry) - __offsetof(WorkWait, entry)) }
}
fn wq_worker_at(entry &C.vkw_list) &WqWorker {
	unsafe { return &WqWorker(usize(entry) - __offsetof(WqWorker, entry)) }
}
fn wq_queue_at(entry &C.vkw_list) &WorkQueue {
	unsafe { return &WorkQueue(usize(entry) - __offsetof(WorkQueue, all)) }
}
fn wq_barrier_at(work &C.vks_work) &WorkBarrier {
	unsafe { return &WorkBarrier(usize(work) - __offsetof(WorkBarrier, work)) }
}
fn wq_is_barrier(work &C.vks_work) bool {
	unsafe { return voidptr(work.func) == C.vkwq_barrier_callback() }
}
fn wq_priority(wq &WorkQueue) u32 { return if wq.highpri { u32(1) } else { u32(0) } }
fn wq_work_pending(work &C.vks_work) bool { unsafe { return (u64(C.vkw_load_owner(&work.data, 0)) & 1) != 0 } }
fn wq_running_locked(work &C.vks_work) &WorkRun {
	unsafe {
		for entry := C.vkwq_running.next; entry != &C.vkwq_running; entry = entry.next {
			run := wq_run_at(entry)
			if voidptr(run.work) == voidptr(work) { return run }
		}
		return nil
	}
}
fn wq_task_running_locked(task voidptr) &WorkRun {
	unsafe {
		for entry := C.vkwq_running.next; entry != &C.vkwq_running; entry = entry.next {
			run := wq_run_at(entry)
			if run.task == task { return run }
		}
		return nil
	}
}
fn wq_current_locked() &WorkRun { return wq_task_running_locked(C.vkp_current()) }
fn wq_canceling_locked(work &C.vks_work) bool {
	unsafe {
		for entry := C.vkwq_canceling.next; entry != &C.vkwq_canceling; entry = entry.next {
			cancel := &WorkCancel(usize(entry) - __offsetof(WorkCancel, entry))
			if voidptr(cancel.work) == voidptr(work) { return true }
		}
		return false
	}
}
fn wq_queued_pool_locked(work &C.vks_work) &WqPool {
	unsafe {
		data := u64(C.vkw_load_owner(&work.data, 0))
		return if (data & 6) == 4 { &WqPool(data & ~u64(255)) } else { &WqPool(nil) }
	}
}
fn wq_queued_locked(work &C.vks_work) &WorkQueue {
	unsafe { pool := wq_queued_pool_locked(work); return if !is_null(pool) { pool.wq } else { &WorkQueue(nil) } }
}
fn wq_delayed_pool_locked(work &C.vks_work) &WqPool {
	unsafe {
		data := u64(C.vkw_load_owner(&work.data, 0))
		return if (data & 6) == 6 { &WqPool(data & ~u64(255)) } else { &WqPool(nil) }
	}
}
fn wq_delayed_locked(work &C.vks_work) &WorkQueue {
	unsafe { pool := wq_delayed_pool_locked(work); return if !is_null(pool) { pool.wq } else { &WorkQueue(nil) } }
}
fn wq_mark_data_locked(pool &WqPool, work &C.vks_work, inactive bool) {
	unsafe {
		require((u64(pool) & 255) == 0)
		tag := if inactive { u64(2) } else { u64(0) }
		C.vkw_store_owner(&work.data, i64(u64(pool) | 5 | tag), 0)
	}
}
fn wq_mark_queued_locked(pool &WqPool, work &C.vks_work) { wq_mark_data_locked(pool, work, false) }
fn wq_cpu_request_valid(cpu i32) bool { return cpu == 256 || (cpu >= 0 && u32(cpu) < percpu_count()) }
fn wq_route_locked(cpu i32, wq &WorkQueue, work &C.vks_work) &WqPool {
	unsafe {
		if wq.unbound { return &wq.pools[0] }
		run := wq_running_locked(work)
		if !is_null(run) && voidptr(run.wq) == voidptr(wq) { return run.pool }
		selected := if cpu == 256 { C.vinix_linuxkpi_cpu_id() } else { u32(cpu) }
		require(selected < wq.nr_pools)
		return &wq.pools[selected]
	}
}
fn wq_wake_workers_locked(wq &WorkQueue) {
	unsafe {
		for entry := wq.workers.next; entry != &wq.workers; entry = entry.next {
			worker := wq_worker_at(entry)
			if is_null(wq_task_running_locked(worker.task)) { C.vkw_wake_task(worker.task) }
		}
		if !is_null(wq.manager) { C.vkw_wake_task(wq.manager.task) }
	}
}
fn wq_wake_bound_domain_locked(pool &WqPool) {
	unsafe {
		for entry := C.vkwq_all.next; entry != &C.vkwq_all; entry = entry.next {
			wq := wq_queue_at(entry)
			if !wq.unbound && wq.highpri == pool.wq.highpri { wq_wake_workers_locked(wq) }
		}
	}
}
fn wq_wake_sleepers_locked(wq &WorkQueue) {
	unsafe {
		for entry := wq.sleepers.next; entry != &wq.sleepers; entry = entry.next { C.vkw_wake_task(wq_wait_at(entry).task) }
	}
}
fn wq_detach_locked(work &C.vks_work) bool {
	unsafe {
		wq := wq_queued_locked(work)
		if is_null(wq) { return false }
		ww_list_del_init(&work.entry)
		C.vkw_store_owner(&work.data, i64(work_no_pool), 0)
		wq_capture_markers_locked(wq)
		wq_wake_workers_locked(wq)
		wq_wake_sleepers_locked(wq)
		return true
	}
}
fn wq_accepting_locked(wq &WorkQueue) bool {
	unsafe {
		require(!wq.stop)
		if wq.drainers == 0 && !wq.destroying { return true }
		run := wq_current_locked()
		return !is_null(run) && voidptr(run.wq) == voidptr(wq)
	}
}
@[export: 'queue_work_on']
pub fn queue_work_on(cpu i32, queue voidptr, record voidptr) bool {
	unsafe {
		wq := &WorkQueue(queue)
		work := &C.vks_work(record)
		require(!is_null(wq) && usize(work.func) != 0)
		valid := wq_cpu_request_valid(cpu)
		C.vkwq_warn_queue_cpu(!valid)
		if !valid { return false }
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		if wq_work_pending(work) || wq_canceling_locked(work) || !wq_accepting_locked(wq) {
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
			return false
		}
		wq_mark_queued_locked(wq_route_locked(cpu, wq, work), work)
		ww_list_add_tail(&work.entry, &wq.pending)
		wq_wake_workers_locked(wq)
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return true
	}
}
fn wq_promote_delayed_locked(dwork &C.vks_delayed_work) {
	unsafe {
		work := &dwork.work
		mut pool := wq_delayed_pool_locked(work)
		if is_null(pool) { return }
		wq := pool.wq
		ww_list_del_init(&work.entry)
		pool = wq_route_locked(dwork.cpu, wq, work)
		wq_mark_queued_locked(pool, work)
		ww_list_add_tail(&work.entry, &wq.pending)
		wq_wake_workers_locked(wq)
	}
}
@[export: 'delayed_work_timer_fn']
pub fn delayed_work_timer_fn(timer &C.timer_list) {
	unsafe {
		dwork := &C.vks_delayed_work(usize(timer) - __offsetof(C.vks_delayed_work, timer))
		C.vkwq_delayed_gate(timer)
		require((C.vinix_linuxkpi_irq_flags() & 512) == 0)
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		wq_promote_delayed_locked(dwork)
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		// The executable callback may now free dwork; never read it again.
	}
}
fn wq_arm_delayed_locked(cpu i32, wq &WorkQueue, dwork &C.vks_delayed_work, delay u64) {
	unsafe {
		require(voidptr(dwork.timer.function) == C.vkwq_delayed_callback() && dwork.timer.flags == 0x200000)
		selected := if cpu == 256 { C.vinix_linuxkpi_cpu_id() } else { u32(cpu) }
		pool_index := if wq.unbound { u32(0) } else { selected }
		pool := if delay != 0 { &wq.pools[pool_index] }
			else { wq_route_locked(cpu, wq, &dwork.work) }
		dwork.wq = wq
		dwork.cpu = if wq.unbound { cpu } else { i32(selected) }
		wq_mark_data_locked(pool, &dwork.work, delay != 0)
		if delay == 0 {
			ww_list_add_tail(&dwork.work.entry, &wq.pending)
			wq_wake_workers_locked(wq)
			return
		}
		ww_list_add_tail(&dwork.work.entry, &wq.delayed)
		require(C.mod_timer(&dwork.timer, C.vkp_jiffies() + delay) == 0)
	}
}
@[export: 'queue_delayed_work_on']
pub fn queue_delayed_work_on(cpu i32, queue voidptr, record voidptr, delay u64) bool {
	unsafe {
		wq := &WorkQueue(queue)
		dwork := &C.vks_delayed_work(record)
		require(!is_null(wq) && usize(dwork.work.func) != 0)
		valid := wq_cpu_request_valid(cpu)
		C.vkwq_warn_delayed_cpu(!valid)
		if !valid { return false }
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		accepted := !wq_work_pending(&dwork.work) && !wq_canceling_locked(&dwork.work) && wq_accepting_locked(wq)
		if accepted { wq_arm_delayed_locked(cpu, wq, dwork, delay) }
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return accepted
	}
}
fn wq_grab_delayed_locked(dwork &C.vks_delayed_work) i32 {
	unsafe {
		if wq_canceling_locked(&dwork.work) { return -2 }
		wq := wq_delayed_locked(&dwork.work)
		if is_null(wq) { return if wq_detach_locked(&dwork.work) { 1 } else { 0 } }
		result := C.try_to_del_timer_sync(&dwork.timer)
		if result < 0 { return -11 }
		require(result != 0)
		ww_list_del_init(&dwork.work.entry)
		C.vkw_store_owner(&dwork.work.data, i64(work_no_pool), 0)
		return 1
	}
}
fn wq_grab_delayed_retry_locked(dwork &C.vks_delayed_work, irq &u64) i32 {
	unsafe {
		for {
			result := wq_grab_delayed_locked(dwork)
			if result != -11 { return result }
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, *irq)
			C.vinix_linuxkpi_spin_wait()
			C.vinix_linuxkpi_cond_resched()
			*irq = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		}
	}
	return 0
}
@[export: 'mod_delayed_work_on']
pub fn mod_delayed_work_on(cpu i32, queue voidptr, record voidptr, delay u64) bool {
	unsafe {
		wq := &WorkQueue(queue)
		dwork := &C.vks_delayed_work(record)
		require(!is_null(wq) && usize(dwork.work.func) != 0)
		valid := wq_cpu_request_valid(cpu)
		C.vkwq_warn_mod_cpu(!valid)
		if !valid { return false }
		mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		mut pending := true
		if !wq_canceling_locked(&dwork.work) && wq_accepting_locked(wq) {
			grabbed := wq_grab_delayed_retry_locked(dwork, &flags)
			pending = grabbed != 0
			if grabbed >= 0 && !wq_canceling_locked(&dwork.work) && wq_accepting_locked(wq) {
				wq_arm_delayed_locked(cpu, wq, dwork, delay)
			}
		}
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return pending
	}
}
@[export: 'cancel_delayed_work']
pub fn cancel_delayed_work(record voidptr) bool {
	unsafe {
		mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		pending := wq_grab_delayed_retry_locked(&C.vks_delayed_work(record), &flags) > 0
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return pending
	}
}
fn wq_target_pending_before_locked(wq &WorkQueue, barrier &WorkBarrier) bool {
	unsafe {
		for entry := wq.pending.next; entry != &wq.pending; entry = entry.next {
			if entry == &barrier.work.entry { break }
			if voidptr(wq_work_at(entry)) == voidptr(barrier.target) { return true }
		}
		return false
	}
}
fn wq_capture_markers_locked(wq &WorkQueue) {
	unsafe {
		for entry := wq.pending.next; entry != &wq.pending; entry = entry.next {
			work := wq_work_at(entry)
			if !wq_is_barrier(work) { continue }
			barrier := wq_barrier_at(work)
			if !barrier.queue && !barrier.captured && !wq_target_pending_before_locked(wq, barrier) {
				barrier.sequence = wq.sequence
				barrier.captured = true
			}
		}
	}
}
fn wq_select_work_locked(pool &WqPool, generation &u64) &C.vks_work {
	unsafe {
		wq := pool.wq
		if pool.nr_active >= wq.max_active || (!wq.unbound && vkwq_bound_runnable[wq_priority(wq)][pool.cpu] != 0) { return nil }
		mut epoch := wq.generation
		for entry := wq.pending.next; entry != &wq.pending; entry = entry.next {
			work := wq_work_at(entry)
			if !wq_is_barrier(work) { continue }
			barrier := wq_barrier_at(work)
			if barrier.queue { epoch = barrier.generation; break }
		}
		for entry := wq.pending.next; entry != &wq.pending; entry = entry.next {
			work := wq_work_at(entry)
			if wq_is_barrier(work) {
				barrier := wq_barrier_at(work)
				if wq.ordered { return nil }
				if barrier.queue { epoch = barrier.generation + 1 }
				continue
			}
			if voidptr(wq_queued_pool_locked(work)) != voidptr(pool) { continue }
			if is_null(wq_running_locked(work)) {
				if !is_null(generation) { *generation = epoch }
				return work
			}
			if wq.ordered { return nil }
		}
		return nil
	}
}
fn wq_marker_ready_locked(wq &WorkQueue, barrier &WorkBarrier) bool {
	unsafe {
		if barrier.queue {
			if wq.pending.next != &barrier.work.entry { return false }
			for entry := C.vkwq_running.next; entry != &C.vkwq_running; entry = entry.next {
				run := wq_run_at(entry)
				if voidptr(run.wq) == voidptr(wq) && run.generation <= barrier.generation { return false }
			}
			return true
		}
		if !barrier.captured { return false }
		run := wq_running_locked(barrier.target)
		return is_null(run) || voidptr(run.wq) != voidptr(wq) || run.sequence > barrier.sequence
	}
}
fn wq_wait_marker_locked(wq &WorkQueue, barrier &WorkBarrier, irq &u64) {
	unsafe {
		mut wait := WorkWait{task: C.vkp_current()}
		ww_list_add_tail(&wait.entry, &wq.sleepers)
		for !wq_marker_ready_locked(wq, barrier) {
			C.vkw_current_state(2)
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, *irq)
			C.vkp_schedule()
			*irq = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		}
		ww_list_del_init(&wait.entry)
		require(wq_detach_locked(&barrier.work))
	}
}
fn wq_worker_enter(worker &WqWorker) bool {
	unsafe {
		C.vkwq_worker_enter()
		worker.task = C.vkwq_get_current()
		worker.start_result = C.vinix_linuxkpi_worker_set_nice(if worker.wq.highpri { -20 } else { 0 })
		if worker.start_result == 0 && !is_null(worker.pool) && !worker.wq.unbound {
			worker.start_result = C.vinix_linuxkpi_worker_bind(worker.pool.cpu)
		}
		complete(&worker.ready)
		return worker.start_result == 0
	}
}
@[export: 'vinix_linuxkpi_work_worker']
pub fn work_worker(argument voidptr) voidptr {
	unsafe {
		worker := &WqWorker(argument)
		wq := worker.wq
		if !wq_worker_enter(worker) { C.vkwq_worker_leave(); return nil }
		pool := worker.pool
		for {
			mut run := WorkRun{wq: wq, pool: pool, task: C.vkp_current()}
			wait_list_init(&run.waiters)
			mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
			mut generation := u64(0)
			mut work := wq_select_work_locked(pool, &generation)
			for is_null(work) && !wq.stop {
				C.vkw_current_state(2)
				C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
				C.vkp_schedule()
				flags = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
				work = wq_select_work_locked(pool, &generation)
			}
			if wq.stop { C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags); break }
			function := work.func
			run.generation = generation
			run.work = work
			wq.sequence++
			require(wq.sequence != 0)
			run.sequence = wq.sequence
			wq_detach_locked(work)
			pool.nr_active++
			if !wq.unbound {
				pool.nr_runnable++
				vkwq_bound_runnable[wq_priority(wq)][pool.cpu]++
				run.runnable = true
			}
			ww_list_add_tail(&run.entry, &C.vkwq_running)
			wq_wake_workers_locked(wq)
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
			function(&C.work_struct(work))
			require(C.vinix_linuxkpi_may_sleep() && C.vkwq_current_running())
			flags = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
			// The callback may have freed work. Only use retained run/wait records.
			mut entry := run.waiters.next
			for entry != &run.waiters {
				wait := wq_wait_at(entry)
				entry = entry.next
				ww_list_del_init(&wait.entry)
				wait.done = true
				C.vkw_wake_task(wait.task)
			}
			ww_list_del_init(&run.entry)
			require(pool.nr_active != 0)
			pool.nr_active--
			if !wq.unbound {
				require(run.runnable && pool.nr_runnable != 0 && vkwq_bound_runnable[wq_priority(wq)][pool.cpu] != 0)
				pool.nr_runnable--
				vkwq_bound_runnable[wq_priority(wq)][pool.cpu]--
			}
			wq_wake_sleepers_locked(wq)
			for queue_entry := C.vkwq_all.next; queue_entry != &C.vkwq_all; queue_entry = queue_entry.next {
				wq_wake_workers_locked(wq_queue_at(queue_entry))
			}
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		}
		C.vkwq_worker_leave()
		return nil
	}
}
@[export: 'vinix_linuxkpi_workqueue_task_sleep']
pub fn workqueue_task_sleep(task_view voidptr) {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		for entry := C.vkwq_running.next; entry != &C.vkwq_running; entry = entry.next {
			run := wq_run_at(entry)
			if run.task != task_view || run.wq.unbound || !run.runnable { continue }
			require(run.pool.nr_runnable != 0 && vkwq_bound_runnable[wq_priority(run.wq)][run.pool.cpu] != 0)
			run.runnable = false
			run.pool.nr_runnable--
			vkwq_bound_runnable[wq_priority(run.wq)][run.pool.cpu]--
			wq_wake_bound_domain_locked(run.pool)
			break
		}
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
	}
}
@[export: 'vinix_linuxkpi_workqueue_task_resume']
pub fn workqueue_task_resume(task_view voidptr) {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		for entry := C.vkwq_running.next; entry != &C.vkwq_running; entry = entry.next {
			run := wq_run_at(entry)
			if run.task != task_view || run.wq.unbound || run.runnable { continue }
			run.pool.nr_runnable++
			vkwq_bound_runnable[wq_priority(run.wq)][run.pool.cpu]++
			run.runnable = true
			break
		}
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
	}
}
fn wq_join_worker(worker &WqWorker) {
	unsafe {
		require(C.vkwq_pthread_join(worker.thread) == 0)
		for C.vkwq_task_state(worker.task) != 128 { C.vinix_linuxkpi_cond_resched() }
		C.vkwq_put_task(worker.task)
		C.kfree(worker)
	}
}
fn wq_start_worker(wq &WorkQueue, pool &WqPool, function voidptr) &WqWorker {
	unsafe {
		worker := &WqWorker(C.kzalloc(sizeof(WqWorker), 3264))
		if is_null(worker) { return nil }
		worker.wq = wq
		worker.pool = pool
		worker.ready.done = 0
		init_swait_queue_head(&worker.ready.@wait, nil, nil)
		if C.vkwq_pthread_create(&worker.thread, function, worker) != 0 { C.kfree(worker); return nil }
		wait_for_completion(&worker.ready)
		if worker.start_result != 0 { wq_join_worker(worker); return nil }
		return worker
	}
}
fn wq_pool_needing_worker_locked(wq &WorkQueue) &WqPool {
	unsafe {
		for cpu := u32(0); cpu < wq.nr_pools; cpu++ {
			pool := &wq.pools[cpu]
			if pool.nr_workers < wq.max_active && pool.nr_active >= pool.nr_workers
				&& !is_null(wq_select_work_locked(pool, nil)) { return pool }
		}
		return nil
	}
}
@[export: 'vinix_linuxkpi_pool_manager']
pub fn pool_manager(argument voidptr) voidptr {
	unsafe {
		manager := &WqWorker(argument)
		wq := manager.wq
		if !wq_worker_enter(manager) { C.vkwq_worker_leave(); return nil }
		for {
			mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
			mut pool := &WqPool(nil)
			for !wq.stop {
				pool = wq_pool_needing_worker_locked(wq)
				if !is_null(pool) { break }
				C.vkw_current_state(2)
				C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
				C.vkp_schedule()
				flags = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
			}
			stop := wq.stop
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
			if stop { break }
			worker := wq_start_worker(wq, pool, C.vkwq_worker_callback())
			if is_null(worker) { C.msleep(1); continue }
			C.vkwq_publish_gate(wq, pool.cpu)
			flags = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
			ww_list_add_tail(&worker.entry, &wq.workers)
			pool.nr_workers++
			wq_wake_workers_locked(wq)
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		}
		C.vkwq_worker_leave()
		return nil
	}
}
@[export: 'vinix_linuxkpi_workqueue_allocate']
pub fn workqueue_allocate(flags u32, requested i32) voidptr {
	unsafe {
		ordered := (flags & 131072) != 0
		unbound := (flags & 2) != 0
		nr_pools := if unbound { u32(1) } else { percpu_count() }
		if (flags & ~u32(2 | 16 | 131072 | 524288)) != 0
			|| (!unbound && (nr_pools == 0 || nr_pools > 64))
			|| (ordered && (!unbound || requested != 1)) || requested < 0
			|| (!ordered && (flags & 524288) != 0) { return nil }
		mut max_active := if requested == 0 { i32(256) } else { requested }
		if u32(max_active) > 512 { C.vkwq_warn_limit(); max_active = 512 }
		require(C.vinix_linuxkpi_may_sleep())
		// Preserve original private geometry and tagged-pool array stride.
		require(sizeof(WorkQueue) == 256 && sizeof(WqPool) == 256 && sizeof(WqWorker) == 88)
		wq := &WorkQueue(C.kzalloc(sizeof(WorkQueue), 3264))
		if is_null(wq) { return nil }
		wait_list_init(&wq.all)
		wait_list_init(&wq.pending)
		wait_list_init(&wq.delayed)
		wait_list_init(&wq.sleepers)
		wait_list_init(&wq.workers)
		wq.max_active = u32(max_active)
		wq.ordered = ordered
		wq.unbound = unbound
		wq.highpri = (flags & 16) != 0
		wq.nr_pools = nr_pools
		wq.pools = &WqPool(C.kzalloc(usize(nr_pools) * sizeof(WqPool), 3264))
		if is_null(wq.pools) { C.kfree(wq); return nil }
		for cpu := u32(0); cpu < nr_pools; cpu++ {
			wq.pools[cpu].wq = wq
			wq.pools[cpu].cpu = cpu
		}
		return wq
	}
}
@[export: 'vinix_linuxkpi_workqueue_name']
pub fn workqueue_name(storage voidptr) &char { unsafe { return &(&WorkQueue(storage)).name[0] } }
@[export: 'vinix_linuxkpi_workqueue_start']
pub fn workqueue_start(storage voidptr) voidptr {
	unsafe {
		wq := &WorkQueue(storage)
		worker := wq_start_worker(wq, &wq.pools[0], C.vkwq_worker_callback())
		if is_null(worker) { C.kfree(wq.pools); C.kfree(wq); return nil }
		ww_list_add_tail(&worker.entry, &wq.workers)
		wq.pools[0].nr_workers = 1
		if !wq.ordered && (!wq.unbound || wq.max_active > 1) {
			wq.manager = wq_start_worker(wq, nil, C.vkwq_manager_callback())
			if is_null(wq.manager) { destroy_workqueue(wq); return nil }
		}
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		ww_list_add_tail(&wq.all, &C.vkwq_all)
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return wq
	}
}
@[export: 'vinix_linuxkpi_workqueue_bootstrap']
pub fn workqueue_bootstrap() i32 {
	unsafe {
		if !is_null(C.system_unbound_wq) { require(!is_null(C.system_wq) && !is_null(C.system_highpri_wq)); return 0 }
		normal := &WorkQueue(C.alloc_workqueue(c'events', 0, 0))
		if is_null(normal) { return -12 }
		highpri := &WorkQueue(C.alloc_workqueue(c'events_highpri', 16, 0))
		if is_null(highpri) { destroy_workqueue(normal); return -12 }
		unbound := &WorkQueue(C.alloc_workqueue(c'events_unbound', 2, 0))
		if is_null(unbound) { destroy_workqueue(highpri); destroy_workqueue(normal); return -12 }
		normal.system = true
		highpri.system = true
		unbound.system = true
		C.system_wq = normal
		C.system_highpri_wq = highpri
		C.system_unbound_wq = unbound
		return 0
	}
}
@[export: 'vinix_linuxkpi_host_workqueue_stopped']
pub fn host_workqueue_stopped(storage voidptr) bool {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		stop := (&WorkQueue(storage)).stop
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return stop
	}
}
@[export: 'vinix_linuxkpi_workqueue_shutdown_for_test']
pub fn workqueue_shutdown_for_test() {
	unsafe {
		wq_system_retire := [C.system_wq, C.system_highpri_wq, C.system_unbound_wq]!
		C.system_wq = nil
		C.system_highpri_wq = nil
		C.system_unbound_wq = nil
		for i := 0; i < 3; i++ {
			if !is_null(wq_system_retire[i]) { (&WorkQueue(wq_system_retire[i])).system = false; destroy_workqueue(wq_system_retire[i]) }
		}
	}
}
fn wq_attach_running_locked(run &WorkRun, wait &WorkWait) {
	unsafe {
		C.memset(wait, 0, sizeof(WorkWait))
		wait.task = C.vkp_current()
		wait.done = is_null(run)
		wait_list_init(&wait.entry)
		if !is_null(run) { require(run.task != C.vkp_current()); ww_list_add_tail(&wait.entry, &run.waiters) }
	}
}
fn wq_wait_attached_locked(wait &WorkWait, irq &u64) {
	unsafe {
		for !wait.done {
			C.vkw_current_state(2)
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, *irq)
			C.vkp_schedule()
			*irq = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		}
		require(ww_list_empty(&wait.entry))
	}
}
fn wq_wait_running_locked(run &WorkRun, irq &u64) {
	unsafe {
		mut wait := WorkWait{}
		wq_attach_running_locked(run, &wait)
		wq_wait_attached_locked(&wait, irq)
	}
}
@[export: 'cancel_work']
pub fn cancel_work(storage voidptr) bool {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		pending := wq_detach_locked(&C.vks_work(storage))
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return pending
	}
}
fn wq_cancel_sync(work &C.vks_work, dwork &C.vks_delayed_work) bool {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		mut cancel := WorkCancel{work: work}
		mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		require(!is_null(dwork) || is_null(wq_delayed_locked(work)))
		pending := if !is_null(dwork) { wq_grab_delayed_retry_locked(dwork, &flags) > 0 } else { wq_detach_locked(work) }
		ww_list_add_tail(&cancel.entry, &C.vkwq_canceling)
		C.vkw_store_owner(&work.data, i64(work_no_pool | 1 | 16), 0)
		if !is_null(dwork) {
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
			C.timer_delete_sync(&dwork.timer)
			flags = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		}
		wq_wait_running_locked(wq_running_locked(work), &flags)
		ww_list_del_init(&cancel.entry)
		if !wq_canceling_locked(work) { C.vkw_store_owner(&work.data, i64(work_no_pool), 0) }
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return pending
	}
}
@[export: 'cancel_work_sync']
pub fn cancel_work_sync(storage voidptr) bool { unsafe { return wq_cancel_sync(&C.vks_work(storage), nil) } }
@[export: 'cancel_delayed_work_sync']
pub fn cancel_delayed_work_sync(storage voidptr) bool {
	unsafe { dwork := &C.vks_delayed_work(storage); return wq_cancel_sync(&dwork.work, dwork) }
}
@[export: 'vinix_linuxkpi_work_barrier']
pub fn work_barrier_callback(work &C.work_struct) { require(false) }
fn wq_init_barrier(barrier &WorkBarrier) {
	unsafe {
		C.vks_init_work(&barrier.work, C.vkwq_barrier_callback())
		barrier.captured = false
		barrier.queue = false
	}
}
fn wq_flush_work_common(work &C.vks_work, dwork &C.vks_delayed_work) bool {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		mut barrier := WorkBarrier{}
		wq_init_barrier(&barrier)
		mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		if !is_null(dwork) {
			for !is_null(wq_delayed_locked(work)) {
				result := C.try_to_del_timer_sync(&dwork.timer)
				if result >= 0 { require(result != 0); wq_promote_delayed_locked(dwork); break }
				C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
				C.vinix_linuxkpi_spin_wait()
				C.vinix_linuxkpi_cond_resched()
				flags = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
			}
		}
		wq := wq_queued_locked(work)
		if !is_null(wq) {
			caller := wq_current_locked()
			pool := wq_queued_pool_locked(work)
			require(is_null(caller) || voidptr(caller.wq) != voidptr(wq) || (!wq.ordered && (voidptr(caller.pool) != voidptr(pool) || wq.max_active != 1)))
			mut running := WorkWait{}
			wq_attach_running_locked(wq_running_locked(work), &running)
			barrier.target = work
			wq_mark_queued_locked(pool, &barrier.work)
			sync_list_add(&barrier.work.entry, &work.entry, work.entry.next)
			wq_wake_workers_locked(wq)
			wq_wait_marker_locked(wq, &barrier, &flags)
			wq_wait_attached_locked(&running, &flags)
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
			return true // destroy_work_on_stack is an upstream no-op in this config.
		}
		run := wq_running_locked(work)
		busy := !is_null(run)
		wq_wait_running_locked(run, &flags)
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return busy
	}
}
@[export: 'flush_work']
pub fn flush_work(storage voidptr) bool { unsafe { return wq_flush_work_common(&C.vks_work(storage), nil) } }
@[export: 'flush_delayed_work']
pub fn flush_delayed_work(storage voidptr) bool {
	unsafe { dwork := &C.vks_delayed_work(storage); return wq_flush_work_common(&dwork.work, dwork) }
}
@[export: '__flush_workqueue']
pub fn flush_workqueue(storage voidptr) {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		wq := &WorkQueue(storage)
		mut barrier := WorkBarrier{}
		wq_init_barrier(&barrier)
		barrier.queue = true
		mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		caller := wq_current_locked()
		require((is_null(caller) || voidptr(caller.wq) != voidptr(wq)) && !wq.stop)
		barrier.generation = wq.generation
		wq.generation++
		require(wq.generation != 0)
		wq_mark_queued_locked(&wq.pools[0], &barrier.work)
		ww_list_add_tail(&barrier.work.entry, &wq.pending)
		wq_wait_marker_locked(wq, &barrier, &flags)
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
	}
}
fn wq_active_locked(wq &WorkQueue) bool {
	unsafe {
		if !ww_list_empty(&wq.pending) { return true }
		for entry := C.vkwq_running.next; entry != &C.vkwq_running; entry = entry.next {
			if voidptr(wq_run_at(entry).wq) == voidptr(wq) { return true }
		}
		return false
	}
}
fn wq_drain_locked(wq &WorkQueue, irq &u64) {
	unsafe {
		caller := wq_current_locked()
		require(is_null(caller) || voidptr(caller.wq) != voidptr(wq))
		mut wait := WorkWait{task: C.vkp_current()}
		ww_list_add_tail(&wait.entry, &wq.sleepers)
		wq.drainers++
		for wq_active_locked(wq) {
			C.vkw_current_state(2)
			C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, *irq)
			C.vkp_schedule()
			*irq = C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		}
		wq.drainers--
		ww_list_del_init(&wait.entry)
	}
}
@[export: 'drain_workqueue']
pub fn drain_workqueue(storage voidptr) {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		wq_drain_locked(&WorkQueue(storage), &flags)
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
	}
}
@[export: 'destroy_workqueue']
pub fn destroy_workqueue(storage voidptr) {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		wq := &WorkQueue(storage)
		mut flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		require(!wq.destroying && !wq.system && ww_list_empty(&wq.delayed))
		wq.destroying = true
		wq_drain_locked(wq, &flags)
		require(ww_list_empty(&wq.delayed) && ww_list_empty(&wq.sleepers))
		wq.stop = true
		ww_list_del_init(&wq.all)
		wq_wake_workers_locked(wq)
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		// A manager can still publish a worker; join it before reading the list.
		if !is_null(wq.manager) { wq_join_worker(wq.manager) }
		mut entry := wq.workers.next
		for entry != &wq.workers {
			worker := wq_worker_at(entry)
			entry = entry.next
			ww_list_del_init(&worker.entry)
			wq_join_worker(worker)
		}
		C.kfree(wq.pools)
		C.kfree(wq)
	}
}
@[export: 'current_work']
pub fn current_work() voidptr {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		run := wq_current_locked()
		work := if !is_null(run) { voidptr(run.work) } else { voidptr(nil) }
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return work
	}
}
@[export: 'work_busy']
pub fn work_busy(storage voidptr) u32 {
	unsafe {
		work := &C.vks_work(storage)
		flags := C.vkp_spin_lock_irqsave(&vkwq_work_lock)
		mut busy := if wq_work_pending(work) { u32(1) } else { u32(0) }
		if !is_null(wq_running_locked(work)) { busy |= 2 }
		C.vkp_spin_unlock_irqrestore(&vkwq_work_lock, flags)
		return busy
	}
}
