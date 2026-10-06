// SPDX-License-Identifier: GPL-2.0-only
// Independent original ordered/delayed/unbound/bound workqueue fixture.
@[translated]
module workfixture

#include "linuxkpi_work_fixture_v_contract.h"
struct C.work_struct {}

struct C.timer_list {}

struct C.delayed_work {
	work  C.work_struct
	timer C.timer_list
}

struct C.workqueue_struct {}

struct C.completion {}

@[typedef]
struct C.atomic_t {}

type WorkCallback = fn (&C.work_struct)

fn C.vinix_linuxkpi_fixture_work_callback(&C.work_struct)
fn C.vinix_linuxkpi_fixture_delayed_callback(&C.work_struct)
fn C.vinix_linuxkpi_fixture_parallel_callback(&C.work_struct)
fn C.vinix_linuxkpi_fixture_bound_callback(&C.work_struct)
fn C.INIT_WORK_ONSTACK(&C.work_struct, WorkCallback)
fn C.INIT_DELAYED_WORK_ONSTACK(&C.delayed_work, WorkCallback)
fn C.to_delayed_work(&C.work_struct) &C.delayed_work
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.current_work() &C.work_struct
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_worker_nice() i32
fn C.vinix_linuxkpi_worker_timeslice() usize
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_test_park_preempt()
fn C.get_cpu() u32
fn C.put_cpu()
fn C.cond_resched() i32
fn C.msleep(u32)
fn C.kzalloc(usize, u32) voidptr
fn C.kfree(voidptr)
fn C.alloc_ordered_workqueue(&char, u32, ...) &C.workqueue_struct
fn C.alloc_workqueue(&char, u32, i32, ...) &C.workqueue_struct
fn C.destroy_workqueue(&C.workqueue_struct)
fn C.queue_work(&C.workqueue_struct, &C.work_struct) bool
fn C.queue_work_on(i32, &C.workqueue_struct, &C.work_struct) bool
fn C.schedule_work_on(i32, &C.work_struct) bool
fn C.queue_delayed_work(&C.workqueue_struct, &C.delayed_work, usize) bool
fn C.queue_delayed_work_on(i32, &C.workqueue_struct, &C.delayed_work, usize) bool
fn C.mod_delayed_work(&C.workqueue_struct, &C.delayed_work, usize) bool
fn C.mod_delayed_work_on(i32, &C.workqueue_struct, &C.delayed_work, usize) bool
fn C.cancel_work_sync(&C.work_struct) bool
fn C.cancel_delayed_work(&C.delayed_work) bool
fn C.cancel_delayed_work_sync(&C.delayed_work) bool
fn C.flush_work(&C.work_struct) bool
fn C.flush_delayed_work(&C.delayed_work) bool
fn C.flush_workqueue(&C.workqueue_struct)
fn C.drain_workqueue(&C.workqueue_struct)
fn C.work_busy(&C.work_struct) u32
fn C.timer_pending(&C.timer_list) bool
fn C.vinix_linuxkpi_timer_active() usize
fn C.time_before(usize, usize) bool
fn C.atomic_set(&C.atomic_t, i32)
fn C.atomic_read(&C.atomic_t) i32
fn C.atomic_inc_return(&C.atomic_t) i32
fn C.atomic_dec_return(&C.atomic_t) i32
fn C.__atomic_load_n(&bool, i32) bool
fn C.__atomic_store_n(&bool, bool, i32)
fn C.READ_ONCE(u32) u32
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.jiffies usize

@[c_extern]
__global (
	C.system_wq         &C.workqueue_struct
	C.system_unbound_wq &C.workqueue_struct
	C.system_highpri_wq &C.workqueue_struct
	C.WORK_CPU_UNBOUND  u32
	C.WORK_BUSY_PENDING u32
	C.WQ_UNBOUND        u32
	C.WQ_HIGHPRI        u32
	C.GFP_KERNEL        u32
	C.EIO               i32
	C.ENOMEM            i32
)

struct WorkTest {
mut:
	work      C.work_struct
	queue     &C.workqueue_struct = unsafe { nil }
	entered   C.completion
	gate      C.completion
	index     u32
	calls     u32
	limit     u32
	count     &u32 = unsafe { nil }
	order     &u32 = unsafe { nil }
	result    &i32 = unsafe { nil }
	hold      bool
	free_self bool
}

@[export: 'vinix_linuxkpi_fixture_work_callback']
pub fn work_callback(work &C.work_struct) {
	unsafe {
		mut test := &WorkTest(work)
		if !C.vinix_linuxkpi_may_sleep() || usize(C.current_work()) != usize(work) {
			*test.result = -C.EIO
		}
		if test.count != nil {
			index := *test.count
			(*test.count)++
			if test.order != nil { test.order[index] = test.index }
		}
		test.calls++
		if test.hold {
			C.complete(&test.entered)
			C.wait_for_completion(&test.gate)
		}
		C.msleep(1)
		if test.calls < test.limit && !C.queue_work(test.queue, work) { *test.result = -C.EIO }
		if test.free_self { C.kfree(test) }
	}
}

fn work_init(test &WorkTest, queue &C.workqueue_struct, result &i32) {
	unsafe {
		*test = WorkTest{ queue: queue, result: result }
		C.INIT_WORK_ONSTACK(&test.work, C.vinix_linuxkpi_fixture_work_callback)
		C.init_completion(&test.entered)
		C.init_completion(&test.gate)
	}
}

struct OrderedBatch {
mut:
	queues  [4]&C.workqueue_struct
	tests   [4][24]WorkTest
	chains  [4]WorkTest
	order   [4][24]u32
	count   [4]u32
	freed   [4]u32
	results [4]i32
}

fn ordered_body(batch &OrderedBatch) i32 {
	unsafe {
		for cpu in 0 .. 4 {
			batch.queues[cpu] = C.alloc_ordered_workqueue(c'vinix-test-%u', 0, u32(cpu))
			if batch.queues[cpu] == nil { return -C.ENOMEM }
		}
		for cpu in 0 .. 4 {
			for i in 0 .. 24 {
				work_init(&batch.tests[cpu][i], batch.queues[cpu], &batch.results[cpu])
				batch.tests[cpu][i].index = u32(i)
				batch.tests[cpu][i].order = &batch.order[cpu][0]
				batch.tests[cpu][i].count = &batch.count[cpu]
			}
			batch.tests[cpu][0].hold = true
			if !C.queue_work(batch.queues[cpu], &batch.tests[cpu][0].work) {
				batch.results[cpu] = -C.EIO
			}
			C.wait_for_completion(&batch.tests[cpu][0].entered)
			for i in 1 .. 24 {
				if !C.queue_work(batch.queues[cpu], &batch.tests[cpu][i].work) || C.queue_work(batch.queues[cpu], &batch.tests[cpu][i].work) {
					batch.results[cpu] = -C.EIO
				}
			}
			if !C.cancel_work_sync(&batch.tests[cpu][7].work) { batch.results[cpu] = -C.EIO }
			C.complete(&batch.tests[cpu][0].gate)
		}
		for cpu in 0 .. 4 {
			C.flush_workqueue(batch.queues[cpu])
			if batch.count[cpu] != 23 || batch.tests[cpu][7].calls != 0 {
				batch.results[cpu] = -C.EIO
			}
			for i := u32(0); i < batch.count[cpu]; i++ {
				if batch.order[cpu][i] != i + u32(i >= 7) { batch.results[cpu] = -C.EIO }
			}
			work_init(&batch.chains[cpu], batch.queues[cpu], &batch.results[cpu])
			batch.chains[cpu].limit = 8
			if !C.queue_work(batch.queues[cpu], &batch.chains[cpu].work) {
				batch.results[cpu] = -C.EIO
			}
		}
		for cpu in 0 .. 4 {
			C.drain_workqueue(batch.queues[cpu])
			if batch.chains[cpu].calls != 8 || C.work_busy(&batch.chains[cpu].work) != 0 {
				batch.results[cpu] = -C.EIO
			}
			for _ in 0 .. 16 {
				mut test := &WorkTest(C.kzalloc(sizeof(WorkTest), C.GFP_KERNEL))
				if test == nil {
					batch.results[cpu] = -C.ENOMEM
					break
				}
				work_init(test, batch.queues[cpu], &batch.results[cpu])
				test.free_self = true
				test.count = &batch.freed[cpu]
				if !C.queue_work(batch.queues[cpu], &test.work) {
					C.kfree(test)
					batch.results[cpu] = -C.EIO
				}
			}
			C.flush_workqueue(batch.queues[cpu])
			if batch.freed[cpu] != 16 { batch.results[cpu] = -C.EIO }
		}
		return 0
	}
}

@[export: 'vinix_linuxkpi_workqueue_native_selftest']
pub fn ordered_selftest() i32 {
	unsafe {
		mut batch := OrderedBatch{}
		mut result := ordered_body(&batch)
		for cpu in 0 .. 4 {
			if batch.queues[cpu] != nil { C.destroy_workqueue(batch.queues[cpu]) }
			if batch.results[cpu] != 0 { result = batch.results[cpu] }
		}
		return result
	}
}

struct DelayedFrees {
mut:
	count C.atomic_t
	done  C.completion
}

struct DelayedTest {
mut:
	work     C.delayed_work
	queue    &C.workqueue_struct = unsafe { nil }
	done     C.completion
	frees    &DelayedFrees = unsafe { nil }
	earliest usize
	calls    u32
	limit    u32
	result   &i32 = unsafe { nil }
}

@[export: 'vinix_linuxkpi_fixture_delayed_callback']
pub fn delayed_callback(work &C.work_struct) {
	unsafe {
		mut test := &DelayedTest(C.to_delayed_work(work))
		if !C.vinix_linuxkpi_may_sleep() || usize(C.current_work()) != usize(work) || C.time_before(C.jiffies, test.earliest) {
			*test.result = -C.EIO
		}
		test.calls++
		C.msleep(1)
		if test.frees != nil {
			frees := test.frees
			C.kfree(test)
			if C.atomic_inc_return(&frees.count) == 8 { C.complete(&frees.done) }
			return
		}
		if test.calls < test.limit {
			test.earliest = C.jiffies + 2
			if !C.queue_delayed_work(test.queue, &test.work, 2) { *test.result = -C.EIO }
		} else {
			C.complete(&test.done)
		}
	}
}

fn delayed_init(test &DelayedTest, queue &C.workqueue_struct, result &i32) {
	unsafe {
		*test = DelayedTest{ queue: queue, result: result, earliest: C.jiffies }
		C.INIT_DELAYED_WORK_ONSTACK(&test.work, C.vinix_linuxkpi_fixture_delayed_callback)
		C.init_completion(&test.done)
	}
}

struct DelayedBatch {
mut:
	queues    [4]&C.workqueue_struct
	tests     [4]DelayedTest
	heap      [4][8]&DelayedTest
	frees     [4]DelayedFrees
	results   [4]i32
	submitted bool
}

fn delayed_body(batch &DelayedBatch) i32 {
	unsafe {
		for i in 0 .. 4 {
			batch.queues[i] = C.alloc_ordered_workqueue(c'vinix-delayed-%u', 0, u32(i))
			if batch.queues[i] == nil { return -C.ENOMEM }
		}
		for i in 0 .. 4 {
			delayed_init(&batch.tests[i], batch.queues[i], &batch.results[i])
			batch.tests[i].limit = 4
			if !C.queue_delayed_work(batch.queues[i], &batch.tests[i].work, 1000) {
				batch.results[i] = -C.EIO
			}
			batch.tests[i].earliest = C.jiffies + 2
			if !C.mod_delayed_work(batch.queues[i], &batch.tests[i].work, 2) {
				batch.results[i] = -C.EIO
			}
		}
		for i in 0 .. 4 {
			if C.wait_for_completion_timeout(&batch.tests[i].done, 500) == 0 {
				batch.results[i] = -C.EIO
			}
			C.cancel_delayed_work_sync(&batch.tests[i].work)
			if batch.tests[i].calls != 4 || C.work_busy(&batch.tests[i].work.work) != 0 {
				batch.results[i] = -C.EIO
			}
			delayed_init(&batch.tests[i], batch.queues[i], &batch.results[i])
			if !C.queue_delayed_work(batch.queues[i], &batch.tests[i].work, 100000) || !C.flush_delayed_work(&batch.tests[i].work) {
				batch.results[i] = -C.EIO
			}
			if batch.tests[i].calls != 1 || C.timer_pending(&batch.tests[i].work.timer) {
				batch.results[i] = -C.EIO
			}
			C.cancel_delayed_work_sync(&batch.tests[i].work)
			delayed_init(&batch.tests[i], batch.queues[i], &batch.results[i])
			flags := C.vinix_linuxkpi_irq_save()
			if !C.queue_delayed_work(batch.queues[i], &batch.tests[i].work, 100000) || !C.mod_delayed_work(batch.queues[i], &batch.tests[i].work, 200000) || !C.cancel_delayed_work(&batch.tests[i].work) || C.vinix_linuxkpi_irq_flags() & (usize(1) << 9) != 0 {
				batch.results[i] = -C.EIO
			}
			C.vinix_linuxkpi_irq_restore(flags)
			if batch.tests[i].calls != 0 || C.work_busy(&batch.tests[i].work.work) != 0 {
				batch.results[i] = -C.EIO
			}
			if !C.queue_delayed_work(batch.queues[i], &batch.tests[i].work, 100000) || !C.cancel_delayed_work_sync(&batch.tests[i].work) {
				batch.results[i] = -C.EIO
			}
		}
		for i in 0 .. 4 {
			C.atomic_set(&batch.frees[i].count, 0)
			C.init_completion(&batch.frees[i].done)
			for j in 0 .. 8 {
				batch.heap[i][j] = &DelayedTest(C.kzalloc(sizeof(DelayedTest), C.GFP_KERNEL))
				if batch.heap[i][j] == nil { return -C.ENOMEM }
				delayed_init(batch.heap[i][j], batch.queues[i], &batch.results[i])
				batch.heap[i][j].frees = &batch.frees[i]
			}
		}
		batch.submitted = true
		for i in 0 .. 4 {
			for j in 0 .. 8 {
				batch.heap[i][j].earliest = C.jiffies + 2
				C.BUG_ON(!C.queue_delayed_work(batch.queues[i], &batch.heap[i][j].work, 2))
			}
		}
		for i in 0 .. 4 {
			if C.wait_for_completion_timeout(&batch.frees[i].done, 500) == 0 {
				batch.results[i] = -C.EIO
				C.wait_for_completion(&batch.frees[i].done)
			}
			C.flush_workqueue(batch.queues[i])
			if C.atomic_read(&batch.frees[i].count) != 8 { batch.results[i] = -C.EIO }
		}
		return 0
	}
}

@[export: 'vinix_linuxkpi_delayed_work_native_selftest']
pub fn delayed_selftest() i32 {
	unsafe {
		mut batch := DelayedBatch{}
		mut result := delayed_body(&batch)
		for i in 0 .. 4 {
			if !batch.submitted {
				for j in 0 .. 8 { C.kfree(batch.heap[i][j]) }
			}
			if batch.queues[i] != nil { C.destroy_workqueue(batch.queues[i]) }
			if batch.results[i] != 0 { result = batch.results[i] }
		}
		retire_by := C.jiffies + 500
		for C.vinix_linuxkpi_timer_active() != 0 && C.time_before(C.jiffies, retire_by) {
			C.msleep(1)
		}
		if C.vinix_linuxkpi_timer_active() != 0 { result = -C.EIO }
		return result
	}
}

struct ParallelTest {
mut:
	work            C.work_struct
	queue           &C.workqueue_struct = unsafe { nil }
	target          &ParallelTest       = unsafe { nil }
	entered         C.completion
	gate            C.completion
	done            C.completion
	frees           &DelayedFrees = unsafe { nil }
	active          C.atomic_t
	calls           u32
	limit           u32
	failure_reasons u32
	result          i32
	free_result     &i32 = unsafe { nil }
	free_reasons    &u32 = unsafe { nil }
	hold            bool
}

fn parallel_failure(test &ParallelTest, reason u32) {
	unsafe {
		test.failure_reasons |= reason
		test.result = -C.EIO
	}
}

fn parallel_report(stage &char, queue u32, item u32, ticks usize, test &ParallelTest,
	observed i32, expected i32, reasons u32) {
	unsafe {
		calls := if test != nil { test.calls } else { u32(0) }
		active := if test != nil { C.atomic_read(&test.active) } else { i32(0) }
		result := if test != nil { test.result } else { i32(0) }
		failure_reasons := if test != nil { test.failure_reasons } else { reasons }
		C.kprintf(c'linuxkpi: unbound test %s failed queue=%u item=%u ticks=%lu observed=%d expected=%d calls=%u active=%d callback_result=%d reasons=0x%x\n', stage, queue, item, ticks, observed, expected, calls, active, result, failure_reasons)
	}
}

@[export: 'vinix_linuxkpi_fixture_parallel_callback']
pub fn parallel_callback(work &C.work_struct) {
	unsafe {
		mut test := &ParallelTest(work)
		// Keep the original conditional active increment and failure order.
		if !C.vinix_linuxkpi_may_sleep() {
			parallel_failure(test, 1)
		} else if usize(C.current_work()) != usize(work) {
			parallel_failure(test, 2)
		} else if C.atomic_inc_return(&test.active) != 1 {
			parallel_failure(test, 4)
		}
		test.calls++
		if test.hold {
			C.complete(&test.entered)
			C.wait_for_completion(&test.gate)
		}
		C.msleep(1)
		if test.target != nil {
			if !C.queue_work(test.queue, &test.target.work) { parallel_failure(test, 8) }
			C.flush_work(&test.target.work)
			if test.target.calls != 1 || C.atomic_read(&test.target.active) != 0 {
				parallel_failure(test, 16)
			}
		}
		if test.calls < test.limit && !C.queue_work(test.queue, work) { parallel_failure(test, 32) }
		if C.atomic_dec_return(&test.active) != 0 { parallel_failure(test, 64) }
		if test.frees != nil {
			frees := test.frees
			*test.free_result = test.result
			*test.free_reasons = test.failure_reasons
			C.kfree(test)
			if C.atomic_inc_return(&frees.count) == 8 { C.complete(&frees.done) }
			return
		}
		if test.calls >= test.limit { C.complete(&test.done) }
	}
}

fn parallel_init(test &ParallelTest, queue &C.workqueue_struct) {
	unsafe {
		*test = ParallelTest{ queue: queue, limit: 1 }
		C.INIT_WORK_ONSTACK(&test.work, C.vinix_linuxkpi_fixture_parallel_callback)
		C.atomic_set(&test.active, 0)
		C.init_completion(&test.entered)
		C.init_completion(&test.gate)
		C.init_completion(&test.done)
	}
}

const parallel_limits = [u32(2), u32(4), u32(8)]!

struct ParallelBatch {
mut:
	queues         [3]&C.workqueue_struct
	held           [3][8]ParallelTest
	extra          [2]ParallelTest
	chains         [3][4]ParallelTest
	heap           [3][8]&ParallelTest
	frees          [3]DelayedFrees
	free_results   [3][8]i32
	free_reasons   [3][8]u32
	held_submitted bool
	heap_submitted bool
}

fn parallel_body(batch &ParallelBatch) i32 {
	unsafe {
		mut result := i32(0)
		batch.queues[0] = C.alloc_workqueue(c'vinix-parallel-2', C.WQ_UNBOUND, 2)
		batch.queues[1] = C.alloc_workqueue(c'vinix-parallel-4', C.WQ_UNBOUND, 4)
		batch.queues[2] = C.system_unbound_wq
		if batch.queues[0] == nil || batch.queues[1] == nil || batch.queues[2] == nil {
			parallel_report(c'queue allocation', 0, 0, 0, nil,
				i32(batch.queues[0] != nil) + i32(batch.queues[1] != nil) + i32(batch.queues[2] != nil), 3, 0)
			return -C.ENOMEM
		}
		for q in 0 .. 3 {
			for i := u32(0); i < parallel_limits[q]; i++ {
				parallel_init(&batch.held[q][i], batch.queues[q])
				batch.held[q][i].hold = true
			}
		}
		batch.held_submitted = true
		for q in 0 .. 3 {
			for i := u32(0); i < parallel_limits[q]; i++ {
				C.BUG_ON(!C.queue_work(batch.queues[q], &batch.held[q][i].work))
			}
		}
		for q in 0 .. 3 {
			for i := u32(0); i < parallel_limits[q]; i++ {
				started := C.jiffies
				if C.wait_for_completion_timeout(&batch.held[q][i].entered, 500) == 0 {
					parallel_report(c'held entry timeout', u32(q), i, C.jiffies - started, nil, 0, 1, 0)
					return -C.EIO
				}
			}
		}
		for q in 0 .. 2 {
			parallel_init(&batch.extra[q], batch.queues[q])
			C.BUG_ON(!C.queue_work(batch.queues[q], &batch.extra[q].work))
			C.msleep(2)
			busy := C.work_busy(&batch.extra[q].work)
			if busy != C.WORK_BUSY_PENDING {
				result = -C.EIO
				parallel_report(c'active-limit pending state', u32(q), 0, 0, nil, i32(busy), i32(C.WORK_BUSY_PENDING), 0)
			}
			C.complete(&batch.held[q][0].gate)
			C.flush_work(&batch.extra[q].work)
			if batch.extra[q].calls != 1 || batch.extra[q].result != 0 {
				result = -C.EIO
				parallel_report(c'deferred callback', u32(q), 0, 0, &batch.extra[q], i32(batch.extra[q].calls), 1, 0)
			}
		}
		for q in 0 .. 3 {
			for i := u32(0); i < parallel_limits[q]; i++ { C.complete(&batch.held[q][i].gate) }
			C.flush_workqueue(batch.queues[q])
			for i := u32(0); i < parallel_limits[q]; i++ {
				if batch.held[q][i].calls != 1 || batch.held[q][i].result != 0 {
					result = -C.EIO
					parallel_report(c'held callback', u32(q), i, 0, &batch.held[q][i], i32(batch.held[q][i].calls), 1, 0)
				}
			}
		}
		batch.held_submitted = false
		for q in 0 .. 3 {
			for i in 0 .. 4 {
				parallel_init(&batch.chains[q][i], batch.queues[q])
				batch.chains[q][i].limit = 4
				C.BUG_ON(!C.queue_work(batch.queues[q], &batch.chains[q][i].work))
			}
		}
		for q in 0 .. 3 {
			for i in 0 .. 4 {
				started := C.jiffies
				if C.wait_for_completion_timeout(&batch.chains[q][i].done, 500) == 0 {
					result = -C.EIO
					parallel_report(c'requeue timeout', u32(q), u32(i), C.jiffies - started, nil, 0, 1, 0)
				}
				C.cancel_work_sync(&batch.chains[q][i].work)
				if batch.chains[q][i].calls != 4 || batch.chains[q][i].result != 0 {
					result = -C.EIO
					parallel_report(c'requeue callback', u32(q), u32(i), C.jiffies - started, &batch.chains[q][i], i32(batch.chains[q][i].calls), 4, 0)
				}
			}
		}
		mut nested := ParallelTest{}
		mut target := ParallelTest{}
		parallel_init(&nested, batch.queues[0])
		parallel_init(&target, batch.queues[0])
		nested.target = &target
		C.BUG_ON(!C.queue_work(batch.queues[0], &nested.work))
		nested_started := C.jiffies
		if C.wait_for_completion_timeout(&nested.done, 500) == 0 {
			result = -C.EIO
			parallel_report(c'nested item-flush timeout', 0, 0, C.jiffies - nested_started, nil, 0, 1, 0)
		}
		C.cancel_work_sync(&nested.work)
		C.cancel_work_sync(&target.work)
		if nested.result != 0 || target.result != 0 || target.calls != 1 {
			result = -C.EIO
			if nested.result != 0 {
				parallel_report(c'nested caller', 0, 0, C.jiffies - nested_started, &nested, nested.result, 0, 0)
			}
			if target.result != 0 || target.calls != 1 {
				parallel_report(c'nested target', 0, 1, C.jiffies - nested_started, &target, i32(target.calls), 1, 0)
			}
		}
		for q in 0 .. 3 {
			C.atomic_set(&batch.frees[q].count, 0)
			C.init_completion(&batch.frees[q].done)
			for i in 0 .. 8 {
				batch.heap[q][i] = &ParallelTest(C.kzalloc(sizeof(ParallelTest), C.GFP_KERNEL))
				if batch.heap[q][i] == nil {
					parallel_report(c'self-free allocation', u32(q), u32(i), 0, nil, 0, 1, 0)
					return -C.ENOMEM
				}
				parallel_init(batch.heap[q][i], batch.queues[q])
				batch.heap[q][i].frees = &batch.frees[q]
				batch.heap[q][i].free_result = &batch.free_results[q][i]
				batch.heap[q][i].free_reasons = &batch.free_reasons[q][i]
			}
		}
		batch.heap_submitted = true
		for q in 0 .. 3 {
			for i in 0 .. 8 { C.BUG_ON(!C.queue_work(batch.queues[q], &batch.heap[q][i].work)) }
		}
		for q in 0 .. 3 {
			started := C.jiffies
			if C.wait_for_completion_timeout(&batch.frees[q].done, 500) == 0 {
				result = -C.EIO
				parallel_report(c'self-free timeout', u32(q), 0, C.jiffies - started, nil, C.atomic_read(&batch.frees[q].count), 8, 0)
				C.wait_for_completion(&batch.frees[q].done)
			}
			C.flush_workqueue(batch.queues[q])
			if C.atomic_read(&batch.frees[q].count) != 8 {
				result = -C.EIO
				parallel_report(c'self-free count', u32(q), 0, C.jiffies - started, nil, C.atomic_read(&batch.frees[q].count), 8, 0)
			}
			for i in 0 .. 8 {
				if batch.free_results[q][i] != 0 {
					result = -C.EIO
					parallel_report(c'self-free callback', u32(q), u32(i), C.jiffies - started, nil, batch.free_results[q][i], 0, batch.free_reasons[q][i])
				}
			}
		}
		return result
	}
}

@[export: 'vinix_linuxkpi_unbound_work_native_selftest']
pub fn parallel_selftest() i32 {
	unsafe {
		mut batch := ParallelBatch{}
		result := parallel_body(&batch)
		for q in 0 .. 3 {
			if batch.held_submitted {
				for i := u32(0); i < parallel_limits[q]; i++ { C.complete(&batch.held[q][i].gate) }
			}
			if !batch.heap_submitted {
				for i in 0 .. 8 { C.kfree(batch.heap[q][i]) }
			}
			if batch.queues[q] != nil {
				if q != 2 {
					C.destroy_workqueue(batch.queues[q])
				} else {
					C.drain_workqueue(batch.queues[q])
				}
			}
		}
		return result
	}
}

struct BoundTest {
mut:
	delayed         C.delayed_work
	queue           &C.workqueue_struct = unsafe { nil }
	requeue_queue   &C.workqueue_struct = unsafe { nil }
	dependency      &BoundTest          = unsafe { nil }
	entered         C.completion
	gate            C.completion
	done            C.completion
	frees           &DelayedFrees = unsafe { nil }
	free_result     &i32          = unsafe { nil }
	active          C.atomic_t
	expected_cpu    [2]u32
	calls           u32
	requeue_cpu     u32
	failure_reasons u32
	expected_nice   i32
	result          i32
	hold            bool
	spin            bool
	release_spin    bool
}

fn bound_failure(test &BoundTest, reason u32) {
	unsafe {
		test.failure_reasons |= reason
		test.result = -C.EIO
	}
}

@[export: 'vinix_linuxkpi_fixture_bound_callback']
pub fn bound_callback(work &C.work_struct) {
	unsafe {
		mut test := &BoundTest(C.to_delayed_work(work))
		call := test.calls
		test.calls++
		expected := test.expected_cpu[if call != 0 { 1 } else { 0 }]
		if C.atomic_inc_return(&test.active) != 1 { bound_failure(test, 1) }
		if !C.vinix_linuxkpi_may_sleep() { bound_failure(test, 2) }
		if usize(C.current_work()) != usize(work) { bound_failure(test, 4) }
		if expected != C.WORK_CPU_UNBOUND && C.vinix_linuxkpi_cpu_id() != expected {
			bound_failure(test, 8)
		}
		if C.vinix_linuxkpi_worker_nice() != test.expected_nice { bound_failure(test, 16) }
		if C.vinix_linuxkpi_worker_timeslice() != (if test.expected_nice == -20 {
			usize(10000)
		} else {
			usize(5000)
		}) {
			bound_failure(test, 32)
		}
		C.complete(&test.entered)
		for test.spin && !C.__atomic_load_n(&test.release_spin, 2) { C.cond_resched() }
		if test.hold { C.wait_for_completion(&test.gate) }
		if test.dependency != nil {
			if !C.queue_work_on(i32(expected), test.queue, &test.dependency.delayed.work) {
				bound_failure(test, 64)
			}
			C.vinix_linuxkpi_test_park_preempt()
			if C.wait_for_completion_timeout(&test.dependency.done, 500) == 0 {
				bound_failure(test, 128)
			}
		}
		C.cond_resched()
		C.msleep(1)
		if expected != C.WORK_CPU_UNBOUND && C.vinix_linuxkpi_cpu_id() != expected {
			bound_failure(test, 256)
		}
		if call == 0 && test.requeue_queue != nil && !C.queue_work_on(i32(test.requeue_cpu), test.requeue_queue, work) {
			bound_failure(test, 512)
		}
		if C.atomic_dec_return(&test.active) != 0 { bound_failure(test, 1024) }
		if test.frees != nil {
			frees := test.frees
			*test.free_result = test.result
			C.kfree(test)
			if C.atomic_inc_return(&frees.count) == 16 { C.complete(&frees.done) }
			return
		}
		if test.requeue_queue == nil || call != 0 { C.complete(&test.done) }
	}
}

fn bound_init(test &BoundTest, queue &C.workqueue_struct, cpu u32, highpri bool) {
	unsafe {
		*test = BoundTest{ queue: queue, expected_cpu: [cpu, cpu]!, expected_nice: if highpri {
			i32(-20)
		} else {
			i32(0)
		} }
		C.INIT_DELAYED_WORK_ONSTACK(&test.delayed, C.vinix_linuxkpi_fixture_bound_callback)
		C.init_completion(&test.entered)
		C.init_completion(&test.gate)
		C.init_completion(&test.done)
		C.atomic_set(&test.active, 0)
	}
}

fn bound_finish(test &BoundTest, stage &char) i32 {
	unsafe {
		started := C.jiffies
		mut result := if C.wait_for_completion_timeout(&test.done, 500) != 0 {
			i32(0)
		} else {
			-C.EIO
		}
		timed_out := result != 0
		C.cancel_delayed_work_sync(&test.delayed)
		if test.result != 0 || C.atomic_read(&test.active) != 0 { result = -C.EIO }
		if result != 0 {
			C.kprintf(c'linuxkpi: bound test %s failed: timeout=%u ticks=%lu calls=%u reasons=0x%x active=%d expected_cpu=%u/%u nice=%d\n', stage, u32(timed_out), C.jiffies - started, test.calls, test.failure_reasons, C.atomic_read(&test.active), test.expected_cpu[0], test.expected_cpu[1], test.expected_nice)
		}
		return result
	}
}

struct BoundBatch {
mut:
	cpus                u32
	queues              [4]&C.workqueue_struct
	tests               [4]BoundTest
	held                [4][2]BoundTest
	extra               [4]BoundTest
	spin                BoundTest
	blocked             BoundTest
	priority            BoundTest
	heap                [16]&BoundTest
	free_results        [16]i32
	frees               DelayedFrees
	held_initialized    bool
	heap_submitted      bool
	result              i32
	failed_stages       u32
	heap_watchdog_ticks usize
	heap_final_ticks    usize
	heap_watchdog_count i32
	heap_final_count    i32
}

fn bound_fail(batch &BoundBatch, stage u32) {
	unsafe {
		batch.result = -C.EIO
		batch.failed_stages |= u32(1) << stage
	}
}

fn bound_body(batch &BoundBatch) {
	unsafe {
		cpus := batch.cpus
		batch.queues[0] = C.alloc_workqueue(c'vinix-bound', 0, 2)
		batch.queues[1] = C.alloc_workqueue(c'vinix-bound-one', 0, 1)
		batch.queues[2] = C.alloc_workqueue(c'vinix-unbound-high', C.WQ_UNBOUND | C.WQ_HIGHPRI, 2)
		batch.queues[3] = C.alloc_workqueue(c'vinix-bound-high', C.WQ_HIGHPRI, 1)
		for q in 0 .. 4 {
			if batch.queues[q] == nil {
				batch.result = -C.ENOMEM
				batch.failed_stages |= 1
				return
			}
		}
		for cpu := u32(0); cpu < cpus; cpu++ {
			bound_init(&batch.tests[cpu], batch.queues[0], cpu, false)
			C.BUG_ON(!C.queue_work_on(i32(cpu), batch.queues[0], &batch.tests[cpu].delayed.work))
		}
		for cpu := u32(0); cpu < cpus; cpu++ {
			if bound_finish(&batch.tests[cpu], c'explicit routing') != 0 || batch.tests[cpu].calls != 1 {
				bound_fail(batch, 1)
			}
		}
		caller_cpu := C.get_cpu()
		bound_init(&batch.tests[0], batch.queues[0], caller_cpu, false)
		if !C.queue_work(batch.queues[0], &batch.tests[0].delayed.work) { bound_fail(batch, 2) }
		C.put_cpu()
		if bound_finish(&batch.tests[0], c'caller routing') != 0 { bound_fail(batch, 2) }
		bound_init(&batch.tests[0], batch.queues[2], C.WORK_CPU_UNBOUND, true)
		C.BUG_ON(!C.queue_work(batch.queues[2], &batch.tests[0].delayed.work))
		if bound_finish(&batch.tests[0], c'unbound high priority') != 0 { bound_fail(batch, 3) }
		bound_init(&batch.tests[0], batch.queues[0], cpus - 1, false)
		flags := C.vinix_linuxkpi_irq_save()
		if !C.queue_delayed_work_on(0, batch.queues[0], &batch.tests[0].delayed, 100000) || !C.mod_delayed_work_on(i32(cpus - 1), batch.queues[0], &batch.tests[0].delayed, 2) {
			bound_fail(batch, 4)
		}
		C.vinix_linuxkpi_irq_restore(flags)
		if bound_finish(&batch.tests[0], c'delayed routing') != 0 { bound_fail(batch, 4) }
		for migration in 0 .. 2 {
			bound_init(&batch.tests[0], batch.queues[0], 0, false)
			batch.tests[0].requeue_queue = batch.queues[migration]
			batch.tests[0].requeue_cpu = cpus - 1
			batch.tests[0].expected_cpu[1] = if migration != 0 { cpus - 1 } else { u32(0) }
			C.BUG_ON(!C.queue_work_on(0, batch.queues[0], &batch.tests[0].delayed.work))
			stage := if migration != 0 {
				&char(c'cross-owner requeue')
			} else {
				&char(c'same-owner requeue')
			}
			if bound_finish(&batch.tests[0], stage) != 0 || batch.tests[0].calls != 2 {
				bound_fail(batch, u32(5 + migration))
			}
		}
		bound_init(&batch.tests[0], batch.queues[0], 0, false)
		bound_init(&batch.tests[1], batch.queues[0], 0, false)
		batch.tests[0].dependency = &batch.tests[1]
		C.BUG_ON(!C.queue_work_on(0, batch.queues[0], &batch.tests[0].delayed.work))
		if bound_finish(&batch.tests[0], c'nested dependency') != 0 { bound_fail(batch, 7) }
		C.cancel_delayed_work_sync(&batch.tests[1].delayed)
		if batch.tests[1].calls != 1 || batch.tests[1].result != 0 { bound_fail(batch, 7) }
		for cpu := u32(0); cpu < cpus; cpu++ {
			for slot in 0 .. 2 {
				bound_init(&batch.held[cpu][slot], batch.queues[0], cpu, false)
				batch.held[cpu][slot].hold = true
			}
			bound_init(&batch.extra[cpu], batch.queues[0], cpu, false)
		}
		batch.held_initialized = true
		for cpu := u32(0); cpu < cpus; cpu++ {
			for slot in 0 .. 2 {
				C.BUG_ON(!C.queue_work_on(i32(cpu), batch.queues[0], &batch.held[cpu][slot].delayed.work))
				if C.wait_for_completion_timeout(&batch.held[cpu][slot].entered, 500) == 0 {
					bound_fail(batch, 8)
					return
				}
			}
			C.BUG_ON(!C.queue_work_on(i32(cpu), batch.queues[0], &batch.extra[cpu].delayed.work))
		}
		C.msleep(2)
		for cpu := u32(0); cpu < cpus; cpu++ {
			if C.READ_ONCE(batch.extra[cpu].calls) != 0 { bound_fail(batch, 8) }
			C.complete(&batch.held[cpu][0].gate)
			if bound_finish(&batch.extra[cpu], c'per-CPU deferred active') != 0 {
				bound_fail(batch, 8)
			}
			C.complete(&batch.held[cpu][1].gate)
			for slot in 0 .. 2 {
				if bound_finish(&batch.held[cpu][slot], c'per-CPU held active') != 0 {
					bound_fail(batch, 8)
				}
			}
		}
		batch.held_initialized = false
		bound_init(&batch.spin, batch.queues[0], 0, false)
		bound_init(&batch.blocked, batch.queues[1], 0, false)
		bound_init(&batch.priority, batch.queues[3], 0, true)
		batch.spin.spin = true
		batch.spin.hold = true
		C.BUG_ON(!C.queue_work_on(0, batch.queues[0], &batch.spin.delayed.work))
		if C.wait_for_completion_timeout(&batch.spin.entered, 500) == 0 { bound_fail(batch, 9) }
		C.BUG_ON(!C.queue_work_on(0, batch.queues[1], &batch.blocked.delayed.work))
		C.BUG_ON(!C.queue_work_on(0, batch.queues[3], &batch.priority.delayed.work))
		if bound_finish(&batch.priority, c'isolated priority domain') != 0 { bound_fail(batch, 9) }
		if C.READ_ONCE(batch.blocked.calls) != 0 { bound_fail(batch, 9) }
		C.__atomic_store_n(&batch.spin.release_spin, true, 3)
		if bound_finish(&batch.blocked, c'normal domain after sleep') != 0 { bound_fail(batch, 9) }
		C.complete(&batch.spin.gate)
		if bound_finish(&batch.spin, c'normal domain spinner') != 0 { bound_fail(batch, 9) }
		for cpu := u32(0); cpu < cpus; cpu++ {
			bound_init(&batch.tests[cpu], C.system_wq, cpu, false)
			C.BUG_ON(!C.schedule_work_on(i32(cpu), &batch.tests[cpu].delayed.work))
		}
		for cpu := u32(0); cpu < cpus; cpu++ {
			if bound_finish(&batch.tests[cpu], c'system default') != 0 { bound_fail(batch, 10) }
		}
		for cpu := u32(0); cpu < cpus; cpu++ {
			bound_init(&batch.tests[cpu], C.system_highpri_wq, cpu, true)
			C.BUG_ON(!C.queue_work_on(i32(cpu), C.system_highpri_wq, &batch.tests[cpu].delayed.work))
		}
		for cpu := u32(0); cpu < cpus; cpu++ {
			if bound_finish(&batch.tests[cpu], c'system high priority') != 0 {
				bound_fail(batch, 11)
			}
		}
		C.atomic_set(&batch.frees.count, 0)
		C.init_completion(&batch.frees.done)
		for i in 0 .. 16 {
			batch.heap[i] = &BoundTest(C.kzalloc(sizeof(BoundTest), C.GFP_KERNEL))
			if batch.heap[i] == nil {
				batch.result = -C.ENOMEM
				batch.failed_stages |= 4096
				return
			}
			bound_init(batch.heap[i], batch.queues[0], u32(i) % cpus, false)
			batch.heap[i].frees = &batch.frees
			batch.heap[i].free_result = &batch.free_results[i]
		}
		batch.heap_submitted = true
		for i in 0 .. 16 {
			C.BUG_ON(!C.queue_work_on(i32(u32(i) % cpus), batch.queues[0], &batch.heap[i].delayed.work))
		}
		heap_started := C.jiffies
		if C.wait_for_completion_timeout(&batch.frees.done, 500) == 0 {
			batch.heap_watchdog_ticks = C.jiffies - heap_started
			batch.heap_watchdog_count = C.atomic_read(&batch.frees.count)
			bound_fail(batch, 13)
			C.wait_for_completion(&batch.frees.done)
		}
		C.flush_workqueue(batch.queues[0])
		batch.heap_final_ticks = C.jiffies - heap_started
		batch.heap_final_count = C.atomic_read(&batch.frees.count)
		if batch.heap_final_count != 16 { bound_fail(batch, 13) }
		for i in 0 .. 16 { if batch.free_results[i] != 0 { bound_fail(batch, 14) } }
	}
}

@[export: 'vinix_linuxkpi_bound_work_native_selftest']
pub fn bound_selftest() i32 {
	unsafe {
		count := C.vinix_linuxkpi_percpu_count()
		mut batch := BoundBatch{ cpus: if count < 4 { count } else { u32(4) }, heap_watchdog_count: -1, heap_final_count: -1 }
		bound_body(&batch)
		if batch.held_initialized {
			for cpu := u32(0); cpu < batch.cpus; cpu++ {
				for slot in 0 .. 2 { C.complete(&batch.held[cpu][slot].gate) }
			}
		}
		if !batch.heap_submitted {
			for i in 0 .. 16 { C.kfree(batch.heap[i]) }
		}
		for q in 0 .. 4 { if batch.queues[q] != nil { C.destroy_workqueue(batch.queues[q]) } }
		if batch.result != 0 {
			C.kprintf(c'linuxkpi: bound native self-test failed stages=0x%x result=%d\n', batch.failed_stages, batch.result)
			if batch.failed_stages & 8192 != 0 {
				C.kprintf(c'linuxkpi: bound self-free completion watchdog_ticks=%lu watchdog_count=%d final_ticks=%lu final_count=%d expected=%u\n', batch.heap_watchdog_ticks, batch.heap_watchdog_count, batch.heap_final_ticks, batch.heap_final_count, u32(16))
			}
		}
		return batch.result
	}
}
