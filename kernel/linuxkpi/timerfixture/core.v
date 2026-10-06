// SPDX-License-Identifier: GPL-2.0-only
// Independent timer fixture; original context, rearm and shutdown checks.
@[translated]
module timerfixture

#include "linuxkpi_timer_fixture_v_contract.h"
struct C.task_struct {
	__state u32
}

struct C.timer_list {
	expires usize
}

struct C.completion {}

@[typedef]
struct C.pthread_t {}

type TimerCallback = fn (&C.timer_list)
type TimerWorker = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_timer_callback(&C.timer_list)
fn C.vinix_linuxkpi_fixture_timer_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, TimerWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.preempt_count() u32
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_may_sleep() bool
fn C.timer_pending(&C.timer_list) bool
fn C.time_before(usize, usize) bool
fn C.mod_timer(&C.timer_list, usize) i32
fn C.complete(&C.completion)
fn C.init_completion(&C.completion)
fn C.timer_setup_on_stack(&C.timer_list, TimerCallback, u32)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.timer_shutdown_sync(&C.timer_list) i32
fn C.destroy_timer_on_stack(&C.timer_list)
fn C.vinix_linuxkpi_timer_active() usize
fn C.__atomic_load_n(&u32, i32) u32
fn C.cond_resched() i32
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.jiffies usize

@[c_extern]
__global C.TASK_DEAD u32

@[c_extern]
__global C.TIMER_IRQSAFE u32

@[c_extern]
__global C.EIO i32

struct NativeTimerTest {
mut:
	timer            C.timer_list
	done             C.completion
	calls            u32
	result           i32
	callback_reasons u32
	bad_tick         usize
	bad_expires      usize
	bad_irq_flags    usize
	bad_depth        u32
	irq_safe         bool
}

struct TimerFailure {
mut:
	reasons          u32
	callback_reasons u32
	calls            u32
	depth            u32
	elapsed          usize
	tick             usize
	expires          usize
	irq_flags        usize
}

struct NativeTimerWorker {
mut:
	task     &C.task_struct = unsafe { nil }
	result   i32
	failures [12]TimerFailure
}

@[export: 'vinix_linuxkpi_fixture_timer_callback']
pub fn callback(timer &C.timer_list) {
	unsafe {
		mut test := &NativeTimerTest(&u8(timer) - __offsetof(NativeTimerTest, timer))
		mut reasons := u32(0)
		depth := C.preempt_count()
		flags := C.vinix_linuxkpi_irq_flags()
		now := C.jiffies
		if C.vinix_linuxkpi_may_sleep() { reasons |= 1 }
		if depth == 0 { reasons |= 2 }
		if C.timer_pending(timer) { reasons |= 4 }
		if ((flags & (usize(1) << 9)) != 0) == test.irq_safe { reasons |= 8 }
		if C.time_before(now, timer.expires) { reasons |= 16 }
		if reasons != 0 {
			test.result = -C.EIO
			test.callback_reasons |= reasons
			test.bad_tick = now
			test.bad_expires = timer.expires
			test.bad_irq_flags = flags
			test.bad_depth = depth
		}
		test.calls++
		if test.calls < 4 {
			C.mod_timer(timer, C.jiffies + 2)
		} else {
			C.complete(&test.done)
		}
	}
}

@[export: 'vinix_linuxkpi_fixture_timer_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut test_worker := &NativeTimerWorker(argument)
		test_worker.task = C.get_task_struct(C.current)
		for round in 0 .. 12 {
			mut test := NativeTimerTest{ irq_safe: (round & 1) != 0 }
			C.init_completion(&test.done)
			C.timer_setup_on_stack(&test.timer, C.vinix_linuxkpi_fixture_timer_callback,
				if test.irq_safe { C.TIMER_IRQSAFE } else { u32(0) })
			mut reasons := u32(0)
			started := C.jiffies
			C.mod_timer(&test.timer, C.jiffies + 2)
			if C.wait_for_completion_timeout(&test.done, 500) == 0 { reasons |= 1 }
			C.timer_shutdown_sync(&test.timer)
			elapsed := C.jiffies - started
			if test.calls != 4 { reasons |= 2 }
			if test.result != 0 { reasons |= 4 }
			if C.timer_pending(&test.timer) { reasons |= 8 }
			C.mod_timer(&test.timer, C.jiffies + 1)
			if C.timer_pending(&test.timer) { reasons |= 16 }
			C.destroy_timer_on_stack(&test.timer)
			if !C.vinix_linuxkpi_may_sleep() { reasons |= 32 }
			if reasons != 0 {
				test_worker.result = -C.EIO
				test_worker.failures[round] = TimerFailure{
					reasons:          reasons
					callback_reasons: test.callback_reasons
					calls:            test.calls
					elapsed:          elapsed
					depth:            test.bad_depth
					tick:             test.bad_tick
					expires:          test.bad_expires
					irq_flags:        test.bad_irq_flags
				}
			}
		}
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_linuxkpi_timer_native_selftest']
pub fn selftest() i32 {
	unsafe {
		mut workers := [4]NativeTimerWorker{}
		mut threads := [4]C.pthread_t{}
		mut result := i32(0)
		for i in 0 .. 4 {
			C.BUG_ON(C.pthread_create(&threads[i], nil, C.vinix_linuxkpi_fixture_timer_worker, &workers[i]) != 0)
		}
		for i in 0 .. 4 {
			C.BUG_ON(C.pthread_join(threads[i], nil) != 0)
			if workers[i].result != 0 { result = -C.EIO }
			for round in 0 .. 12 {
				failure := &workers[i].failures[round]
				if failure.reasons == 0 { continue }
				C.kprintf(c'linuxkpi: timer test worker=%u round=%u reasons=0x%x callback=0x%x calls=%u elapsed=%lu ticks depth=%u tick=%lu expires=%lu irq=0x%lx\n',
					u32(i), u32(round), failure.reasons, failure.callback_reasons, failure.calls,
					failure.elapsed, failure.depth, failure.tick, failure.expires, failure.irq_flags)
			}
			for C.__atomic_load_n(&workers[i].task.__state, 2) != C.TASK_DEAD { C.cond_resched() }
			C.put_task_struct(workers[i].task)
		}
		active := C.vinix_linuxkpi_timer_active()
		if active != 0 {
			C.kprintf(c'linuxkpi: timer test retained %zu active timers\n', active)
			result = -C.EIO
		}
		return result
	}
}
