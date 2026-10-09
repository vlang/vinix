// SPDX-License-Identifier: GPL-2.0-or-later
// A real IPI interrupts a held bound callback during an observed drain.
@[translated]
module workirqfixture

#include "linuxkpi_work_irq_fixture_v_contract.h"

struct C.work_struct {}
struct C.workqueue_struct {}
struct C.completion {}
struct C.task_struct {
	__state u32
	vinix_thread voidptr
}
@[typedef]
struct C.pthread_t {}
type WorkFn = fn (&C.work_struct)
type ThreadFn = fn (voidptr) voidptr
type IpiFn = fn (voidptr)
fn C.vinix_linuxkpi_workirq_anchor(&C.work_struct)
fn C.vinix_linuxkpi_workirq_rejected(&C.work_struct)
fn C.vinix_linuxkpi_workirq_chain(&C.work_struct)
fn C.vinix_linuxkpi_workirq_probe(voidptr)
fn C.vinix_linuxkpi_workirq_controller(voidptr) voidptr
fn C.vinix_linuxkpi_workirq_drainer(voidptr) voidptr
fn C.INIT_WORK_ONSTACK(&C.work_struct, WorkFn)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.alloc_workqueue(&char, u32, i32, ...) &C.workqueue_struct
fn C.destroy_workqueue(&C.workqueue_struct)
fn C.drain_workqueue(&C.workqueue_struct)
fn C.queue_work_on(i32, &C.workqueue_struct, &C.work_struct) bool
fn C.current_work() &C.work_struct
fn C.work_busy(&C.work_struct) u32
fn C.vinix_linuxkpi_workqueue_draining_for_test(voidptr) bool
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_maskable_irq_depth() u32
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_spin_wait()
fn C.vinix_linuxkpi_clock_ns() u64
fn C.vinix_linuxkpi_test_thread_reap_ready(voidptr) bool
fn C.vinix_linuxkpi_test_reap_quiescent() bool
fn C.smp_call_function_single(i32, IpiFn, voidptr, i32) i32
fn C.pthread_create(voidptr, voidptr, ThreadFn, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct)
fn C.put_task_struct(&C.task_struct)
fn C.cond_resched() i32
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.__atomic_fetch_or(&u32, u32, i32) u32
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32
@[c_extern]
__global C.current &C.task_struct
@[c_extern]
__global C.TASK_DEAD u32

const deadline_ns = u64(30000000000)

struct WorkIrqCase {
mut:
	anchor C.work_struct
	rejected C.work_struct
	chain C.work_struct
	queue &C.workqueue_struct = unsafe { nil }
	anchor_ready C.completion
	drain_ready C.completion
	drain_task &C.task_struct = unsafe { nil }
	drain_thread C.pthread_t
	drain_started bool
	release u32
	irq_done u32
	post_iret u32
	chain_go u32
	chain_accepted u32
	rejected_calls u32
	chain_calls u32
	failures u32
}

struct WorkIrqController {
mut:
	task &C.task_struct = unsafe { nil }
	thread C.pthread_t
	result i32
}

fn fail(test &WorkIrqCase, bit u32) {
	unsafe { C.__atomic_fetch_or(&test.failures, bit, 0) }
}

@[export: 'vinix_linuxkpi_workirq_probe']
pub fn probe(argument voidptr) {
	unsafe {
		mut test := &WorkIrqCase(argument)
		if C.vinix_linuxkpi_cpu_id() != 1 || C.vinix_linuxkpi_maskable_irq_depth() == 0
			|| (C.vinix_linuxkpi_irq_flags() & 512) != 0 || C.vinix_linuxkpi_preempt_count() == 0 {
			fail(test, 1)
		}
		if usize(C.current_work()) != 0 { fail(test, 2) }
		if !C.vinix_linuxkpi_workqueue_draining_for_test(test.queue) { fail(test, 4) }
		if C.work_busy(&test.rejected) != 0 { fail(test, 8) }
		if C.queue_work_on(1, test.queue, &test.rejected) { fail(test, 16) }
		if C.work_busy(&test.rejected) != 0 { fail(test, 32) }
		// Last borrowed-ledger use in the IRQ callback. The anchored task later
		// publishes a separate acknowledgement after the handler has IRETed.
		C.__atomic_store_n(&test.irq_done, 1, 3)
	}
}

@[export: 'vinix_linuxkpi_workirq_anchor']
pub fn anchor(work &C.work_struct) {
	unsafe {
		mut test := &WorkIrqCase(work)
		C.vinix_linuxkpi_preempt_disable()
		if C.vinix_linuxkpi_cpu_id() != 1 || C.vinix_linuxkpi_maskable_irq_depth() != 0
			|| usize(C.current_work()) != usize(work) { fail(test, 64) }
		flags := C.vinix_linuxkpi_irq_save()
		if usize(C.current_work()) != usize(work) { fail(test, 128) }
		C.vinix_linuxkpi_irq_restore(flags)
		C.complete(&test.anchor_ready)
		started := C.vinix_linuxkpi_clock_ns()
		for C.__atomic_load_n(&test.release, 2) == 0 {
			if C.__atomic_load_n(&test.irq_done, 2) != 0 && C.__atomic_load_n(&test.post_iret, 2) == 0 {
				if C.vinix_linuxkpi_maskable_irq_depth() != 0 || usize(C.current_work()) != usize(work) {
					fail(test, 256)
				}
				C.__atomic_store_n(&test.post_iret, 1, 3)
			}
			if C.__atomic_load_n(&test.chain_go, 2) != 0 && C.__atomic_load_n(&test.chain_accepted, 2) == 0 {
				chain_flags := C.vinix_linuxkpi_irq_save()
				if !C.vinix_linuxkpi_workqueue_draining_for_test(test.queue)
					|| usize(C.current_work()) != usize(work) { fail(test, 512) }
				if !C.queue_work_on(1, test.queue, &test.chain) { fail(test, 1024) }
				C.vinix_linuxkpi_irq_restore(chain_flags)
				C.__atomic_store_n(&test.chain_accepted, 1, 3)
			}
			if C.vinix_linuxkpi_clock_ns() - started >= deadline_ns {
				fail(test, 2048)
				break
			}
			C.vinix_linuxkpi_spin_wait()
		}
		C.vinix_linuxkpi_preempt_enable()
	}
}

@[export: 'vinix_linuxkpi_workirq_rejected']
pub fn rejected(work &C.work_struct) {
	unsafe {
		test := &WorkIrqCase(usize(work) - __offsetof(WorkIrqCase, rejected))
		C.__atomic_fetch_or(&test.rejected_calls, 1, 0)
	}
}

@[export: 'vinix_linuxkpi_workirq_chain']
pub fn chain(work &C.work_struct) {
	unsafe {
		test := &WorkIrqCase(usize(work) - __offsetof(WorkIrqCase, chain))
		if C.vinix_linuxkpi_cpu_id() != 1 || C.vinix_linuxkpi_maskable_irq_depth() != 0
			|| usize(C.current_work()) != usize(work) { fail(test, 4096) }
		C.__atomic_fetch_or(&test.chain_calls, 1, 0)
	}
}

@[export: 'vinix_linuxkpi_workirq_drainer']
pub fn drainer(argument voidptr) voidptr {
	unsafe {
		mut test := &WorkIrqCase(argument)
		test.drain_task = C.current
		C.get_task_struct(test.drain_task)
		C.complete(&test.drain_ready)
		C.drain_workqueue(test.queue)
		C.pthread_exit(nil)
		return nil
	}
}

fn expired(started u64) bool { return C.vinix_linuxkpi_clock_ns() - started >= deadline_ns }

fn retire(task &C.task_struct) {
	unsafe {
		C.BUG_ON(task == nil)
		started := C.vinix_linuxkpi_clock_ns()
		for C.__atomic_load_n(&task.__state, 2) != C.TASK_DEAD
			|| !C.vinix_linuxkpi_test_thread_reap_ready(task.vinix_thread) {
			C.BUG_ON(expired(started))
			C.cond_resched()
		}
		C.put_task_struct(task)
	}
}

fn quiescent() {
	started := C.vinix_linuxkpi_clock_ns()
	for !C.vinix_linuxkpi_test_reap_quiescent() {
		C.BUG_ON(expired(started))
		C.cond_resched()
	}
}

fn exercise(test &WorkIrqCase) i32 {
	unsafe {
		test.queue = C.alloc_workqueue(c'linuxkpi-irq-identity', 0, 1)
		if test.queue == nil { return -12 }
		C.INIT_WORK_ONSTACK(&test.anchor, C.vinix_linuxkpi_workirq_anchor)
		C.INIT_WORK_ONSTACK(&test.rejected, C.vinix_linuxkpi_workirq_rejected)
		C.INIT_WORK_ONSTACK(&test.chain, C.vinix_linuxkpi_workirq_chain)
		C.init_completion(&test.anchor_ready)
		C.init_completion(&test.drain_ready)
		if !C.queue_work_on(1, test.queue, &test.anchor) { return -5 }
		if C.wait_for_completion_timeout(&test.anchor_ready, 10000) == 0 { return -5 }
		if C.pthread_create(&test.drain_thread, nil, C.vinix_linuxkpi_workirq_drainer, test) != 0 { return -12 }
		test.drain_started = true
		if C.wait_for_completion_timeout(&test.drain_ready, 10000) == 0 { return -5 }
		started := C.vinix_linuxkpi_clock_ns()
		for !C.vinix_linuxkpi_workqueue_draining_for_test(test.queue) {
			if expired(started) { return -5 }
			C.cond_resched()
		}
		if C.smp_call_function_single(1, C.vinix_linuxkpi_workirq_probe, test, 1) != 0 { return -5 }
		for C.__atomic_load_n(&test.post_iret, 2) == 0 {
			if expired(started) { return -5 }
			C.cond_resched()
		}
		C.__atomic_store_n(&test.chain_go, 1, 3)
		for C.__atomic_load_n(&test.chain_accepted, 2) == 0 {
			if expired(started) { return -5 }
			C.cond_resched()
		}
		return 0
	}
}

@[export: 'vinix_linuxkpi_workirq_controller']
pub fn controller(argument voidptr) voidptr {
	unsafe {
		mut control := &WorkIrqController(argument)
		control.task = C.current
		C.get_task_struct(control.task)
		if C.vinix_linuxkpi_worker_bind(0) != 0 {
			control.result = -5
			C.pthread_exit(nil)
			return nil
		}
		mut test := WorkIrqCase{}
		control.result = exercise(&test)
		// Every error path releases the held callback and joins the only actor
		// borrowing this stack. Destruction retires all accepted work and workers.
		C.__atomic_store_n(&test.release, 1, 3)
		if test.drain_started {
			C.BUG_ON(C.pthread_join(test.drain_thread, nil) != 0)
			retire(test.drain_task)
		}
		if test.queue != nil { C.destroy_workqueue(test.queue) }
		if control.result == 0 && (test.failures != 0 || test.rejected_calls != 0 || test.chain_calls != 1) {
			C.kprintf(c'linuxkpi: work IRQ identity failure bits=0x%x rejected=%u chain=%u\n',
				test.failures, test.rejected_calls, test.chain_calls)
			control.result = -5
		}
		quiescent()
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_linuxkpi_workirq_native_selftest']
pub fn selftest() i32 {
	unsafe {
		if C.vinix_linuxkpi_percpu_count() < 2 { return -22 }
		mut control := WorkIrqController{}
		if C.pthread_create(&control.thread, nil, C.vinix_linuxkpi_workirq_controller, &control) != 0 { return -12 }
		C.BUG_ON(C.pthread_join(control.thread, nil) != 0)
		retire(control.task)
		quiescent()
		return control.result
	}
}
