// SPDX-License-Identifier: GPL-2.0-only
// Independent synchronization fixture with original wake-before-park checks.
@[translated]
module syncfixture

#include "linuxkpi_sync_fixture_v_contract.h"
struct C.task_struct {
	__state u32
}

struct C.list_head {
	next &C.list_head
	prev &C.list_head
}

@[typedef]
struct C.spinlock_t {}

@[typedef]
struct C.raw_spinlock_t {}

struct C.mutex {}

struct C.wait_queue_head {
	lock C.spinlock_t
	head C.list_head
}

@[typedef]
struct C.wait_queue_entry_t {}

struct C.swait_queue_head {
	lock      C.raw_spinlock_t
	task_list C.list_head
}

struct C.swait_queue {
	task      &C.task_struct
	task_list C.list_head
}

struct C.completion {
	done  u32
	@wait C.swait_queue_head
}

@[typedef]
struct C.pthread_t {}

type SyncWorker = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_sync_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, SyncWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.task_is_running(&C.task_struct) bool
fn C.vinix_linuxkpi_may_sleep() bool
fn C.mutex_init(&C.mutex)
fn C.mutex_trylock(&C.mutex) bool
fn C.mutex_is_locked(&C.mutex) bool
fn C.mutex_lock(&C.mutex)
fn C.mutex_unlock(&C.mutex)
fn C.mutex_destroy(&C.mutex)
fn C.init_waitqueue_head(&C.wait_queue_head)
fn C.init_wait_entry(&C.wait_queue_entry_t, i32)
fn C.prepare_to_wait(&C.wait_queue_head, &C.wait_queue_entry_t, i32)
fn C.waitqueue_active(&C.wait_queue_head) bool
fn C.wake_up(&C.wait_queue_head)
fn C.finish_wait(&C.wait_queue_head, &C.wait_queue_entry_t)
fn C.init_swait_queue_head(&C.swait_queue_head)
fn C.prepare_to_swait_exclusive(&C.swait_queue_head, &C.swait_queue, i32)
fn C.swake_up_one(&C.swait_queue_head)
fn C.finish_swait(&C.swait_queue_head, &C.swait_queue)
fn C.swait_active(&C.swait_queue_head) bool
fn C.init_completion(&C.completion)
fn C.try_wait_for_completion(&C.completion) bool
fn C.completion_done(&C.completion) bool
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.reinit_completion(&C.completion)
fn C.cond_resched() i32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.__atomic_load_n(&u32, i32) u32
fn C.wait_event(C.wait_queue_head, u32)
fn C.swait_event_exclusive(C.swait_queue_head, u32)
fn C.wake_up_all(&C.wait_queue_head)
fn C.swake_up_all(&C.swait_queue_head)
fn C.spin_lock_irqsave(&C.spinlock_t, usize)
fn C.spin_unlock_irqrestore(&C.spinlock_t, usize)
fn C.raw_spin_lock_irqsave(&C.raw_spinlock_t, usize)
fn C.raw_spin_unlock_irqrestore(&C.raw_spinlock_t, usize)
fn C.INIT_LIST_HEAD(&C.list_head)
fn C.BUG_ON(bool)

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.TASK_UNINTERRUPTIBLE i32

@[c_extern]
__global C.TASK_DEAD u32

@[c_extern]
__global C.UINT_MAX u32

@[c_extern]
__global C.EIO i32

@[export: 'vinix_linuxkpi_sync_selftest']
pub fn selftest() i32 {
	unsafe {
		mut guard := C.mutex{}
		C.mutex_init(&guard)
		if !C.mutex_trylock(&guard) || !C.mutex_is_locked(&guard) || C.mutex_trylock(&guard) {
			return -C.EIO
		}
		C.mutex_unlock(&guard)
		C.mutex_lock(&guard)
		C.mutex_unlock(&guard)
		C.mutex_destroy(&guard)
		mut queue := C.wait_queue_head{}
		C.init_waitqueue_head(&queue)
		mut waiter := C.wait_queue_entry_t{}
		C.init_wait_entry(&waiter, 0)
		C.prepare_to_wait(&queue, &waiter, C.TASK_UNINTERRUPTIBLE)
		if !C.waitqueue_active(&queue) { return -C.EIO }
		C.wake_up(&queue)
		C.finish_wait(&queue, &waiter)
		if C.waitqueue_active(&queue) || !C.task_is_running(C.current) { return -C.EIO }
		mut simple := C.swait_queue_head{}
		C.init_swait_queue_head(&simple)
		mut swaiter := C.swait_queue{ task: C.current }
		C.INIT_LIST_HEAD(&swaiter.task_list)
		C.prepare_to_swait_exclusive(&simple, &swaiter, C.TASK_UNINTERRUPTIBLE)
		C.swake_up_one(&simple)
		C.finish_swait(&simple, &swaiter)
		if C.swait_active(&simple) || !C.task_is_running(C.current) { return -C.EIO }
		mut completion := C.completion{}
		C.init_completion(&completion)
		if C.try_wait_for_completion(&completion) || C.completion_done(&completion) {
			return -C.EIO
		}
		C.complete(&completion)
		C.complete(&completion)
		C.wait_for_completion(&completion)
		if !C.try_wait_for_completion(&completion) || C.try_wait_for_completion(&completion) {
			return -C.EIO
		}
		C.complete_all(&completion)
		C.wait_for_completion(&completion)
		if !C.try_wait_for_completion(&completion) || completion.done != C.UINT_MAX {
			return -C.EIO
		}
		C.reinit_completion(&completion)
		return if C.completion_done(&completion) { -C.EIO } else { i32(0) }
	}
}

$if !linuxkpi_host_test ? {
struct NativeSyncTest {
mut:
	lock      C.mutex
	queue     C.wait_queue_head
	simple    C.swait_queue_head
	ready     C.completion
	stage     C.completion
	release   C.completion
	counter   u32
	go        u32
	simple_go u32
	payload   u32
}

struct NativeSyncWorker {
mut:
	test   &NativeSyncTest = unsafe { nil }
	task   &C.task_struct  = unsafe { nil }
	result i32
}

@[export: 'vinix_linuxkpi_fixture_sync_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut worker := &NativeSyncWorker(argument)
		mut test := worker.test
		worker.task = C.get_task_struct(C.current)
		for _ in 0 .. 32 {
			C.mutex_lock(&test.lock)
			previous := test.counter
			C.cond_resched()
			test.counter = previous + 1
			C.mutex_unlock(&test.lock)
		}
		C.complete(&test.ready)
		C.wait_event(test.queue, C.__atomic_load_n(&test.go, 2))
		if test.payload != 0x1234 { worker.result = -C.EIO }
		C.complete(&test.stage)
		C.swait_event_exclusive(test.simple, C.__atomic_load_n(&test.simple_go, 2))
		C.complete(&test.stage)
		C.wait_for_completion(&test.release)
		if !C.task_is_running(C.current) || !C.vinix_linuxkpi_may_sleep() { worker.result = -C.EIO }
		C.pthread_exit(nil)
		return nil
	}
}

fn queue_count(head &C.list_head) u32 {
	unsafe {
		mut count := u32(0)
		for entry := head.next; usize(entry) != usize(head); entry = entry.next { count++ }
		return count
	}
}

@[export: 'vinix_linuxkpi_sync_native_selftest']
pub fn native_selftest() i32 {
	unsafe {
		mut test := NativeSyncTest{}
		C.mutex_init(&test.lock)
		C.init_waitqueue_head(&test.queue)
		C.init_swait_queue_head(&test.simple)
		C.init_completion(&test.ready)
		C.init_completion(&test.stage)
		C.init_completion(&test.release)
		mut workers := [4]NativeSyncWorker{}
		mut threads := [4]C.pthread_t{}
		mut result := i32(0)
		for i in 0 .. 4 {
			workers[i] = NativeSyncWorker{ test: &test }
			C.BUG_ON(C.pthread_create(&threads[i], nil, C.vinix_linuxkpi_fixture_sync_worker, &workers[i]) != 0)
		}
		for _ in 0 .. 4 { C.wait_for_completion(&test.ready) }
		if test.counter != 4 * 32 { result = -C.EIO }
		for {
			mut flags := usize(0)
			C.spin_lock_irqsave(&test.queue.lock, flags)
			count := queue_count(&test.queue.head)
			C.spin_unlock_irqrestore(&test.queue.lock, flags)
			if count == 4 { break }
			C.cond_resched()
		}
		test.payload = 0x1234
		C.__atomic_store_n(&test.go, 1, 3)
		C.wake_up_all(&test.queue)
		for {
			mut flags := usize(0)
			C.raw_spin_lock_irqsave(&test.simple.lock, flags)
			count := queue_count(&test.simple.task_list)
			C.raw_spin_unlock_irqrestore(&test.simple.lock, flags)
			if count == 4 { break }
			C.cond_resched()
		}
		C.__atomic_store_n(&test.simple_go, 1, 3)
		C.swake_up_all(&test.simple)
		for _ in 0 .. 4 * 2 { C.wait_for_completion(&test.stage) }
		for {
			mut flags := usize(0)
			C.raw_spin_lock_irqsave(&test.release.@wait.lock, flags)
			count := queue_count(&test.release.@wait.task_list)
			C.raw_spin_unlock_irqrestore(&test.release.@wait.lock, flags)
			if count == 4 { break }
			C.cond_resched()
		}
		C.complete_all(&test.release)
		for i in 0 .. 4 {
			C.BUG_ON(C.pthread_join(threads[i], nil) != 0)
			if workers[i].result != 0 { result = -C.EIO }
			for C.__atomic_load_n(&workers[i].task.__state, 2) != C.TASK_DEAD { C.cond_resched() }
			C.put_task_struct(workers[i].task)
		}
		if C.waitqueue_active(&test.queue) || C.swait_active(&test.simple)
			|| C.swait_active(&test.ready.@wait) || C.swait_active(&test.stage.@wait)
			|| C.swait_active(&test.release.@wait) || test.stage.done != 0 || test.ready.done != 0 {
			result = -C.EIO
		}
		C.mutex_destroy(&test.lock)
		return result
	}
}

}
