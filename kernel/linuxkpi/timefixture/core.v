// SPDX-License-Identifier: GPL-2.0-only
// Independent time fixture retaining every original wait and retirement check.
@[translated]
module timefixture

#include "linuxkpi_time_fixture_v_contract.h"
struct C.task_struct {
	__state      u32
	vinix_thread voidptr
}

struct C.swait_queue_head {}

@[typedef]
struct C.wait_queue_head_t {}

struct C.completion {
	@wait C.swait_queue_head
}

@[typedef]
struct C.pthread_t {}

type TimeWorker = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_time_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, TimeWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.task_is_running(&C.task_struct) bool
fn C.cond_resched() i32
fn C.schedule_timeout_uninterruptible(isize) isize
fn C.schedule_timeout_killable(isize) isize
fn C.time_before(usize, usize) bool
fn C.init_waitqueue_head(&C.wait_queue_head_t)
fn C.wait_event_timeout(C.wait_queue_head_t, bool, usize) isize
fn C.waitqueue_active(&C.wait_queue_head_t) bool
fn C.init_swait_queue_head(&C.swait_queue_head)
fn C.swait_event_timeout_exclusive(C.swait_queue_head, bool, usize) isize
fn C.swait_active(&C.swait_queue_head) bool
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.wait_for_completion_interruptible_timeout(&C.completion, usize) isize
fn C.vinix_linuxkpi_test_task_signal(voidptr, u64)
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_clock_ns() u64
fn C.vinix_linuxkpi_test_task_time_waiters(&C.task_struct) usize
fn C.vinix_linuxkpi_test_thread_reap_ready(voidptr) bool
fn C.vinix_linuxkpi_test_reap_quiescent() bool
fn C.__atomic_load_n(&u32, i32) u32
fn C.BUG_ON(bool)
fn C.BUG()
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.jiffies usize

@[c_extern]
__global C.TASK_DEAD u32

@[c_extern]
__global C.EIO i32

@[c_extern]
__global C.ERESTARTSYS i32

struct TimeFailure {
mut:
	reasons     u32
	elapsed     usize
	timeout     isize
	queue       isize
	simple      isize
	completion  isize
	completed   isize
	interrupted isize
	killable    isize
}

struct NativeTimeWorker {
mut:
	task     &C.task_struct = unsafe { nil }
	result   i32
	failures [8]TimeFailure
}

@[export: 'vinix_linuxkpi_fixture_time_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut test_worker := &NativeTimeWorker(argument)
		test_worker.task = C.get_task_struct(C.current)
		for i in 0 .. 8 {
			mut failure := TimeFailure{}
			start := C.jiffies
			failure.timeout = C.schedule_timeout_uninterruptible(2)
			failure.elapsed = C.jiffies - start
			if failure.timeout != 0 { failure.reasons |= 1 }
			if C.time_before(C.jiffies, start + 2) { failure.reasons |= 2 }
			mut queue := C.wait_queue_head_t{}
			C.init_waitqueue_head(&queue)
			failure.queue = C.wait_event_timeout(queue, false, 1)
			if failure.queue != 0 || C.waitqueue_active(&queue) { failure.reasons |= 4 }
			mut simple := C.swait_queue_head{}
			C.init_swait_queue_head(&simple)
			failure.simple = C.swait_event_timeout_exclusive(simple, false, 1)
			if failure.simple != 0 || C.swait_active(&simple) { failure.reasons |= 8 }
			mut completion := C.completion{}
			C.init_completion(&completion)
			failure.completion = isize(C.wait_for_completion_timeout(&completion, 1))
			if failure.completion != 0 || C.swait_active(&completion.@wait) {
				failure.reasons |= 16
			}
			C.complete(&completion)
			failure.completed = isize(C.wait_for_completion_timeout(&completion, 0))
			if failure.completed != 1 { failure.reasons |= 32 }
			C.vinix_linuxkpi_test_task_signal(test_worker.task.vinix_thread, u64(1) << 14)
			failure.interrupted = C.wait_for_completion_interruptible_timeout(&completion, 5)
			if failure.interrupted != -C.ERESTARTSYS { failure.reasons |= 64 }
			failure.killable = C.schedule_timeout_killable(2)
			if failure.killable != 0 { failure.reasons |= 128 }
			C.vinix_linuxkpi_test_task_signal(test_worker.task.vinix_thread, 0)
			if !C.task_is_running(C.current) { failure.reasons |= 256 }
			if !C.vinix_linuxkpi_may_sleep() { failure.reasons |= 512 }
			if failure.reasons != 0 {
				test_worker.result = -C.EIO
				test_worker.failures[i] = failure
			}
		}
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_linuxkpi_time_native_selftest']
pub fn selftest() i32 {
	unsafe {
		mut workers := [4]NativeTimeWorker{}
		mut threads := [4]C.pthread_t{}
		mut result := i32(0)
		for i in 0 .. 4 {
			C.BUG_ON(C.pthread_create(&threads[i], nil, C.vinix_linuxkpi_fixture_time_worker, &workers[i]) != 0)
		}
		for i in 0 .. 4 { C.BUG_ON(C.pthread_join(threads[i], nil) != 0) }
		retirement_started := C.vinix_linuxkpi_clock_ns()
		for i in 0 .. 4 {
			if workers[i].result != 0 { result = -C.EIO }
			for round in 0 .. 8 {
				failure := &workers[i].failures[round]
				if failure.reasons == 0 { continue }
				C.kprintf(c'linuxkpi: time test worker=%u round=%u reasons=0x%x elapsed=%lu timeout=%ld queue=%ld simple=%ld completion=%ld completed=%ld interrupted=%ld killable=%ld\n',
					u32(i), u32(round), failure.reasons, failure.elapsed, failure.timeout,
					failure.queue, failure.simple, failure.completion, failure.completed,
					failure.interrupted, failure.killable)
			}
			for C.__atomic_load_n(&workers[i].task.__state, 2) != C.TASK_DEAD {
				if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 {
					C.kprintf(c'linuxkpi: time test worker=%u did not publish TASK_DEAD\n', u32(i))
					C.BUG()
				}
				C.cond_resched()
			}
			retained := C.vinix_linuxkpi_test_task_time_waiters(workers[i].task)
			if retained != 0 {
				C.kprintf(c'linuxkpi: time test worker=%u retained %zu timeout records after join\n', u32(i), retained)
				C.BUG()
			}
		}
		for i in 0 .. 4 {
			for !C.vinix_linuxkpi_test_thread_reap_ready(workers[i].task.vinix_thread) {
				if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 {
					C.kprintf(c'linuxkpi: time test worker=%u did not reach off-stack reaper\n', u32(i))
					C.BUG()
				}
				C.cond_resched()
			}
		}
		for i in 0 .. 4 { C.put_task_struct(workers[i].task) }
		for !C.vinix_linuxkpi_test_reap_quiescent() {
			if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 {
				C.kprintf(c'linuxkpi: time test deferred frees did not finish\n')
				C.BUG()
			}
			C.cond_resched()
		}
		return result
	}
}
