// SPDX-License-Identifier: GPL-2.0-only
// Independent native SRCU fixture. Failure line numbers retain the C reference.
@[translated]
module srcufixture

#include "linuxkpi_srcu_fixture_v_contract.h"

struct C.task_struct {
	__state      u32
	vinix_thread voidptr
}

struct C.srcu_struct {
	srcu_idx u32
	sda      &C.srcu_data
	srcu_sup &C.srcu_usage
}

struct C.srcu_usage {
	srcu_gp_seq        usize
	srcu_gp_seq_needed usize
}

struct C.srcu_data {
	srcu_lock_count   [2]C.atomic_long_t
	srcu_unlock_count [2]C.atomic_long_t
}

struct C.rcu_head {}

struct C.work_struct {}

struct C.workqueue_struct {}

struct C.completion {}

@[typedef]
struct C.atomic_long_t {}

@[typedef]
struct C.pthread_t {}

type SrcuWorker = fn (voidptr) voidptr
type SrcuCallback = fn (&C.rcu_head)
type SrcuWorkCallback = fn (&C.work_struct)

fn C.vinix_linuxkpi_fixture_srcu_worker(voidptr) voidptr
fn C.vinix_linuxkpi_fixture_srcu_barrier_waiter(voidptr) voidptr
fn C.vinix_linuxkpi_fixture_srcu_free_callback(&C.rcu_head)
fn C.vinix_linuxkpi_fixture_srcu_barrier_callback(&C.rcu_head)
fn C.vinix_linuxkpi_fixture_srcu_work_callback(&C.work_struct)
fn C.pthread_create(voidptr, voidptr, SrcuWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_test_worker_route(voidptr, u32) i32
fn C.vinix_linuxkpi_task_queued(voidptr) bool
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_spin_wait()
fn C.vinix_linuxkpi_test_alloc_oom(i32)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.completion_done(&C.completion) bool
fn C.cond_resched() i32
fn C.msleep(u32)
fn C.time_after_eq(usize, usize) bool
fn C.init_srcu_struct(&C.srcu_struct) i32
fn C.cleanup_srcu_struct(&C.srcu_struct)
fn C.srcu_read_lock(&C.srcu_struct) i32
fn C.srcu_read_unlock(&C.srcu_struct, i32)
fn C.synchronize_srcu(&C.srcu_struct)
fn C.synchronize_srcu_expedited(&C.srcu_struct)
fn C.srcu_barrier(&C.srcu_struct)
fn C.get_state_synchronize_srcu(&C.srcu_struct) usize
fn C.start_poll_synchronize_srcu(&C.srcu_struct) usize
fn C.poll_state_synchronize_srcu(&C.srcu_struct, usize) bool
fn C.call_srcu(&C.srcu_struct, &C.rcu_head, SrcuCallback)
fn C.per_cpu_ptr(&C.srcu_data, u32) &C.srcu_data
fn C.atomic_long_read(&C.atomic_long_t) isize
fn C.kzalloc(usize, u32) voidptr
fn C.kfree(voidptr)
fn C.alloc_workqueue(&char, u32, i32, ...) &C.workqueue_struct
fn C.destroy_workqueue(&C.workqueue_struct)
fn C.INIT_WORK_ONSTACK(&C.work_struct, SrcuWorkCallback)
fn C.current_work() &C.work_struct
fn C.queue_work_on(i32, &C.workqueue_struct, &C.work_struct) bool
fn C.__atomic_load_n(&u32, i32) u32

@[c: '__atomic_load_n']
fn C.srcu_load_bool(&bool, i32) bool

@[c: '__atomic_load_n']
fn C.srcu_load_i32(&i32, i32) i32

fn C.__atomic_store_n(&bool, bool, i32)

@[c: '__atomic_store_n']
fn C.srcu_store_i32(&i32, i32, i32)

fn C.__atomic_fetch_add(&u32, u32, i32) u32

@[c: 'READ_ONCE']
fn C.srcu_read_u32(u32) u32

@[c: 'READ_ONCE']
fn C.srcu_read_word(usize) usize

fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.jiffies usize

@[c_extern]
__global (
	C.TASK_DEAD            u32
	C.TASK_UNINTERRUPTIBLE u32
	C.EIO                  i32
	C.ENOMEM               i32
	C.GFP_KERNEL           u32
)

enum Operation {
	reader
	sync
	barrier
}

struct SrcuThread {
mut:
	ssp          &C.srcu_struct = unsafe { nil }
	task         &C.task_struct = unsafe { nil }
	thread       C.pthread_t
	entered      C.completion
	release_one  C.completion
	one_done     C.completion
	release      C.completion
	done         C.completion
	operation    Operation
	idx          [2]i32
	result       i32
	failure_line u32
	nested       bool
	initialized  bool
	started      bool
}

fn thread_failure(test &SrcuThread, line u32) {
	unsafe {
		if test.result == 0 { test.failure_line = line }
		test.result = -C.EIO
	}
}

@[export: 'vinix_linuxkpi_fixture_srcu_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut test := &SrcuThread(argument)
		test.task = C.get_task_struct(C.current)
		if test.operation == .reader {
			if C.vinix_linuxkpi_worker_bind(0) != 0 { thread_failure(test, 43) }
			test.idx[0] = C.srcu_read_lock(test.ssp)
			if test.nested { test.idx[1] = C.srcu_read_lock(test.ssp) }
			C.complete(&test.entered)
			C.cond_resched()
			C.msleep(1)
			if !C.vinix_linuxkpi_may_sleep() || C.vinix_linuxkpi_cpu_id() != 0 {
				thread_failure(test, 50)
			}
			target := if C.vinix_linuxkpi_percpu_count() > 1 { u32(1) } else { u32(0) }
			if C.vinix_linuxkpi_worker_bind(target) != 0 { thread_failure(test, 52) }
			if test.nested {
				C.wait_for_completion(&test.release_one)
				C.srcu_read_unlock(test.ssp, test.idx[1])
				C.complete(&test.one_done)
			}
			C.wait_for_completion(&test.release)
			C.cond_resched()
			C.msleep(1)
			if C.vinix_linuxkpi_cpu_id() != target { thread_failure(test, 61) }
			C.srcu_read_unlock(test.ssp, test.idx[0])
		} else {
			C.complete(&test.entered)
			if test.operation == .sync {
				C.synchronize_srcu(test.ssp)
			} else {
				C.srcu_barrier(test.ssp)
			}
		}
		C.complete(&test.done)
		C.pthread_exit(nil)
		return nil
	}
}

fn start(test &SrcuThread, ssp &C.srcu_struct, operation Operation, nested bool) i32 {
	unsafe {
		*test = SrcuThread{ ssp: ssp, operation: operation, nested: nested }
		C.init_completion(&test.entered)
		C.init_completion(&test.release_one)
		C.init_completion(&test.one_done)
		C.init_completion(&test.release)
		C.init_completion(&test.done)
		test.initialized = true
		if C.pthread_create(&test.thread, nil, C.vinix_linuxkpi_fixture_srcu_worker, test) != 0 {
			return -C.ENOMEM
		}
		test.started = true
		return 0
	}
}

fn join(test &SrcuThread) i32 {
	unsafe {
		if !test.started { return 0 }
		C.BUG_ON(C.pthread_join(test.thread, nil) != 0)
		for C.__atomic_load_n(&test.task.__state, 2) != C.TASK_DEAD { C.cond_resched() }
		if test.result != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test reader thread failed at line %u: operation=%u error=%d condition_line=%u idx=%d/%d\n', u32(94), u32(test.operation), test.result, test.failure_line, test.idx[0], test.idx[1])
		}
		C.put_task_struct(test.task)
		test.started = false
		return test.result
	}
}

fn flip(ssp &C.srcu_struct, old u32) i32 {
	unsafe {
		deadline := C.jiffies + 500
		for C.srcu_read_u32(ssp.srcu_idx) & 1 == old {
			if C.time_after_eq(C.jiffies, deadline) {
				C.kprintf(c'linuxkpi: SRCU self-test bank flip failed at line %u: old=%u idx=%u gp=%lu needed=%lu ticks=%lu\n', u32(107), old, C.srcu_read_u32(ssp.srcu_idx), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq_needed), C.jiffies)
				return -C.EIO
			}
			C.msleep(1)
		}
		return 0
	}
}

fn poll(ssp &C.srcu_struct, cookie usize) i32 {
	unsafe {
		deadline := C.jiffies + 500
		for !C.poll_state_synchronize_srcu(ssp, cookie) {
			if C.time_after_eq(C.jiffies, deadline) {
				C.kprintf(c'linuxkpi: SRCU self-test cookie poll failed at line %u: cookie=%lu idx=%u gp=%lu needed=%lu ticks=%lu\n', u32(123), cookie, C.srcu_read_u32(ssp.srcu_idx), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq_needed), C.jiffies)
				return -C.EIO
			}
			C.msleep(1)
		}
		return 0
	}
}

fn readers_body(ssp &C.srcu_struct, old &SrcuThread, late &SrcuThread,
	sync &SrcuThread, barrier &SrcuThread) i32 {
	unsafe {
		mut result := i32(0)
		if start(old, ssp, .reader, true) != 0 || C.wait_for_completion_timeout(&old.entered, 500) == 0 {
			C.kprintf(c'linuxkpi: SRCU self-test old reader entry failed at line %u: started=%u\n', u32(145), u32(old.started))
			return -C.EIO
		}
		bank := u32(old.idx[0])
		target := if C.vinix_linuxkpi_percpu_count() > 1 { u32(1) } else { u32(0) }
		source := C.per_cpu_ptr(ssp.sda, 0)
		destination := C.per_cpu_ptr(ssp.sda, target)
		if bank > 1 || old.idx[1] != i32(bank) || C.atomic_long_read(&source.srcu_lock_count[bank]) != 2 || C.atomic_long_read(&destination.srcu_unlock_count[bank]) != 0 {
			locks := if bank <= 1 {
				C.atomic_long_read(&source.srcu_lock_count[bank])
			} else {
				isize(-1)
			}
			unlocks := if bank <= 1 {
				C.atomic_long_read(&destination.srcu_unlock_count[bank])
			} else {
				isize(-1)
			}
			C.kprintf(c'linuxkpi: SRCU self-test nested reader counts failed at line %u: bank=%u nested=%d locks=%ld unlocks=%ld\n', u32(155), bank, old.idx[1], locks, unlocks)
			return -C.EIO
		}
		if start(barrier, ssp, .barrier, false) != 0 || C.wait_for_completion_timeout(&barrier.done, 500) == 0 {
			C.kprintf(c'linuxkpi: SRCU self-test empty callback barrier failed at line %u: started=%u done=%u\n', u32(164), u32(barrier.started), u32(C.completion_done(&barrier.done)))
			return -C.EIO
		}
		if join(barrier) != 0 { result = -C.EIO }
		if start(sync, ssp, .sync, false) != 0 || flip(ssp, bank) != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test first GP start failed at line %u: started=%u\n', u32(171), u32(sync.started))
			return -C.EIO
		}
		if start(late, ssp, .reader, false) != 0 || C.wait_for_completion_timeout(&late.entered, 500) == 0 {
			C.kprintf(c'linuxkpi: SRCU self-test late reader entry failed at line %u: started=%u\n', u32(176), u32(late.started))
			return -C.EIO
		}
		if late.idx[0] == i32(bank) || C.completion_done(&sync.done) {
			C.kprintf(c'linuxkpi: SRCU self-test late reader separation failed at line %u: old_bank=%u late_bank=%d sync_done=%u\n', u32(180), bank, late.idx[0], u32(C.completion_done(&sync.done)))
			result = -C.EIO
		}
		during := C.get_state_synchronize_srcu(ssp)
		C.complete(&old.release_one)
		if C.wait_for_completion_timeout(&old.one_done, 500) == 0 || C.completion_done(&sync.done) || C.atomic_long_read(&destination.srcu_unlock_count[bank]) != 1 {
			C.kprintf(c'linuxkpi: SRCU self-test one nested unlock failed at line %u: one_done=%u sync_done=%u unlocks=%ld\n', u32(188), u32(C.completion_done(&old.one_done)), u32(C.completion_done(&sync.done)), C.atomic_long_read(&destination.srcu_unlock_count[bank]))
			result = -C.EIO
		}
		C.complete(&old.release)
		if C.wait_for_completion_timeout(&sync.done, 500) == 0 {
			C.kprintf(c'linuxkpi: SRCU self-test first GP completion failed at line %u: gp=%lu needed=%lu\n', u32(195), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq_needed))
			return -C.EIO
		}
		if C.completion_done(&late.done) || C.poll_state_synchronize_srcu(ssp, during) {
			C.kprintf(c'linuxkpi: SRCU self-test first GP boundary failed at line %u: late_done=%u cookie=%lu gp=%lu\n', u32(200), u32(C.completion_done(&late.done)), during, C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq))
			result = -C.EIO
		}
		if join(old) != 0 { result = -C.EIO }
		if join(sync) != 0 { result = -C.EIO }
		if C.atomic_long_read(&source.srcu_lock_count[bank]) != 2 || C.atomic_long_read(&destination.srcu_unlock_count[bank]) != 2 {
			C.kprintf(c'linuxkpi: SRCU self-test migrated reader counts failed at line %u: locks=%ld unlocks=%ld\n', u32(208), C.atomic_long_read(&source.srcu_lock_count[bank]), C.atomic_long_read(&destination.srcu_unlock_count[bank]))
			result = -C.EIO
		}
		next := C.start_poll_synchronize_srcu(ssp)
		if flip(ssp, u32(late.idx[0])) != 0 || C.poll_state_synchronize_srcu(ssp, during) || C.poll_state_synchronize_srcu(ssp, next) {
			C.kprintf(c'linuxkpi: SRCU self-test second GP boundary failed at line %u: during=%lu next=%lu gp=%lu late_bank=%d\n', u32(218), during, next, C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq), late.idx[0])
			result = -C.EIO
		}
		C.complete(&late.release)
		if poll(ssp, during) != 0 || poll(ssp, next) != 0 { result = -C.EIO }
		return result
	}
}

fn readers() i32 {
	unsafe {
		mut ssp := C.srcu_struct{}
		mut old := SrcuThread{}
		mut late := SrcuThread{}
		mut sync := SrcuThread{}
		mut barrier := SrcuThread{}
		mut result := C.init_srcu_struct(&ssp)
		if result != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test reader domain init failed at line %u: error=%d\n', u32(140), result)
			return result
		}
		result = readers_body(&ssp, &old, &late, &sync, &barrier)
		// All failure paths open both nesting gates before joining any waiter.
		if old.initialized {
			C.complete_all(&old.release_one)
			C.complete_all(&old.release)
		}
		if late.initialized { C.complete_all(&late.release) }
		if join(&old) != 0 { result = -C.EIO }
		if join(&late) != 0 { result = -C.EIO }
		if join(&sync) != 0 { result = -C.EIO }
		if join(&barrier) != 0 { result = -C.EIO }
		C.srcu_barrier(&ssp)
		C.cleanup_srcu_struct(&ssp)
		return result
	}
}

struct Callbacks {
mut:
	count        u32
	failure_line u32
	result       i32
}

struct Callback {
mut:
	head  C.rcu_head
	test  &Callbacks = unsafe { nil }
	index u32
}

@[export: 'vinix_linuxkpi_fixture_srcu_free_callback']
pub fn free_callback(head &C.rcu_head) {
	unsafe {
		// head is the first member, preserving container_of's exact identity.
		callback := &Callback(head)
		mut test := callback.test
		index := callback.index
		if C.vinix_linuxkpi_may_sleep() || C.vinix_linuxkpi_preempt_count() == 0
			|| C.vinix_linuxkpi_irq_flags() & (usize(1) << 9) == 0
			|| C.__atomic_fetch_add(&test.count, 1, 4) != index {
			if test.result == 0 { test.failure_line = 259 }
			test.result = -C.EIO
		}
		C.kfree(callback)
	}
}

struct BarrierProbe {
mut:
	head                   C.rcu_head
	ssp                    &C.srcu_struct = unsafe { nil }
	task                   &C.task_struct = unsafe { nil }
	thread                 C.pthread_t
	ready                  C.completion
	cpu                    u32
	waiter_cpu             u32
	waiter_failure_line    u32
	callback_failure_line  u32
	task_state_at_failure  u32
	task_queued_at_failure bool
	entered                bool
	gp_done                bool
	barrier_started        bool
	barrier_done           bool
	callback_done          bool
	observed_park          bool
	result                 i32
	route_error            i32
}

fn barrier_waiter_body(test &BarrierProbe) {
	unsafe {
		deadline := C.jiffies + 500
		for !C.srcu_load_bool(&test.entered, 2) {
			if C.time_after_eq(C.jiffies, deadline) {
				test.waiter_failure_line = 286
				C.srcu_store_i32(&test.result, -C.EIO, 3)
				return
			}
			C.cond_resched()
		}
		if C.vinix_linuxkpi_worker_bind((test.cpu + 1) % C.vinix_linuxkpi_percpu_count()) != 0 {
			test.waiter_failure_line = 293
			C.srcu_store_i32(&test.result, -C.EIO, 3)
		}
		test.waiter_cpu = C.vinix_linuxkpi_cpu_id()
		cookie := C.start_poll_synchronize_srcu(test.ssp)
		if poll(test.ssp, cookie) != 0 {
			test.waiter_failure_line = 301
			C.srcu_store_i32(&test.result, -C.EIO, 3)
		} else {
			C.__atomic_store_n(&test.gp_done, true, 3)
		}
		C.__atomic_store_n(&test.barrier_started, true, 3)
		C.srcu_barrier(test.ssp)
	}
}

@[export: 'vinix_linuxkpi_fixture_srcu_barrier_waiter']
pub fn barrier_waiter(argument voidptr) voidptr {
	unsafe {
		mut test := &BarrierProbe(argument)
		test.task = C.get_task_struct(C.current)
		test.waiter_cpu = C.vinix_linuxkpi_cpu_id()
		C.complete(&test.ready)
		barrier_waiter_body(test)
		C.__atomic_store_n(&test.barrier_done, true, 3)
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_linuxkpi_fixture_srcu_barrier_callback']
pub fn barrier_callback(head &C.rcu_head) {
	unsafe {
		mut test := &BarrierProbe(head)
		test.cpu = C.vinix_linuxkpi_cpu_id()
		test.route_error = C.vinix_linuxkpi_test_worker_route(test.task.vinix_thread,
			(test.cpu + 1) % C.vinix_linuxkpi_percpu_count())
		if test.route_error != 0 {
			test.callback_failure_line = 324
			C.srcu_store_i32(&test.result, -C.EIO, 3)
		}
		C.__atomic_store_n(&test.entered, true, 3)
		if test.route_error != 0 {
			C.__atomic_store_n(&test.callback_done, true, 3)
			return
		}
		deadline := C.jiffies + 500
		for {
			if C.srcu_load_bool(&test.barrier_done, 2) || C.time_after_eq(C.jiffies, deadline) {
				test.callback_failure_line = 336
				test.task_state_at_failure = C.__atomic_load_n(&test.task.__state, 2)
				test.task_queued_at_failure = C.vinix_linuxkpi_task_queued(test.task.vinix_thread)
				C.srcu_store_i32(&test.result, -C.EIO, 3)
				break
			}
			if C.srcu_load_bool(&test.barrier_started, 2) && C.__atomic_load_n(&test.task.__state, 2) == C.TASK_UNINTERRUPTIBLE && !C.vinix_linuxkpi_task_queued(test.task.vinix_thread) {
				if !C.srcu_load_bool(&test.gp_done, 2) {
					test.callback_failure_line = 346
					C.srcu_store_i32(&test.result, -C.EIO, 3)
				}
				test.observed_park = true
				break
			}
			C.vinix_linuxkpi_spin_wait()
		}
		C.__atomic_store_n(&test.callback_done, true, 3)
	}
}

fn callbacks_body(ssp &C.srcu_struct, test &Callbacks, callbacks &&Callback,
	probe &BarrierProbe, submitted &u32, probe_started &bool, probe_submitted &bool) i32 {
	unsafe {
		mut result := i32(0)
		for i in 0 .. 16 {
			callbacks[i] = &Callback(C.kzalloc(sizeof(Callback), C.GFP_KERNEL))
			if callbacks[i] == nil {
				C.kprintf(c'linuxkpi: SRCU self-test callback allocation failed at line %u: index=%u\n', u32(373), u32(i))
				return -C.ENOMEM
			}
			callbacks[i].test = test
			callbacks[i].index = u32(i)
		}
		flags := C.vinix_linuxkpi_irq_save()
		for *submitted < 8 {
			C.call_srcu(ssp, &callbacks[*submitted].head, C.vinix_linuxkpi_fixture_srcu_free_callback)
			(*submitted)++
		}
		C.vinix_linuxkpi_irq_restore(flags)
		C.vinix_linuxkpi_preempt_disable()
		for *submitted < 16 {
			C.call_srcu(ssp, &callbacks[*submitted].head, C.vinix_linuxkpi_fixture_srcu_free_callback)
			(*submitted)++
		}
		C.vinix_linuxkpi_preempt_enable()
		C.srcu_barrier(ssp)
		if test.count != 16 || test.result != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test callback sequence failed at line %u: count=%u error=%d condition_line=%u\n', u32(390), test.count, test.result, test.failure_line)
			result = -C.EIO
		}
		if C.vinix_linuxkpi_percpu_count() > 1 {
			C.init_completion(&probe.ready)
			if C.pthread_create(&probe.thread, nil, C.vinix_linuxkpi_fixture_srcu_barrier_waiter, probe) != 0 {
				C.kprintf(c'linuxkpi: SRCU self-test barrier waiter creation failed at line %u: error=%d\n', u32(397), -C.ENOMEM)
				return -C.ENOMEM
			}
			*probe_started = true
			if C.wait_for_completion_timeout(&probe.ready, 500) == 0 {
				C.kprintf(c'linuxkpi: SRCU self-test barrier waiter entry failed at line %u: started=%u\n', u32(403), u32(*probe_started))
				return -C.EIO
			}
			C.call_srcu(ssp, &probe.head, C.vinix_linuxkpi_fixture_srcu_barrier_callback)
			*probe_submitted = true
		}
		return result
	}
}

fn callbacks() i32 {
	unsafe {
		mut ssp := C.srcu_struct{}
		mut test := Callbacks{}
		mut records := [16]&Callback{}
		mut probe := BarrierProbe{ ssp: &ssp }
		mut result := C.init_srcu_struct(&ssp)
		if result != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test callback domain init failed at line %u: error=%d\n', u32(365), result)
			return result
		}
		mut submitted := u32(0)
		mut probe_started := false
		mut probe_submitted := false
		result = callbacks_body(&ssp, &test, &records[0], &probe, &submitted, &probe_started, &probe_submitted)
		// Submitted objects remain owned by their self-free callbacks on failure.
		for i := submitted; i < 16; i++ { C.kfree(records[i]) }
		if probe_started {
			C.BUG_ON(C.pthread_join(probe.thread, nil) != 0)
			if probe_submitted {
				for !C.srcu_load_bool(&probe.callback_done, 2) { C.cond_resched() }
			}
			for C.__atomic_load_n(&probe.task.__state, 2) != C.TASK_DEAD { C.cond_resched() }
			C.put_task_struct(probe.task)
			if !probe.observed_park || C.srcu_load_i32(&probe.result, 2) != 0 {
				C.kprintf(c'linuxkpi: SRCU self-test callback barrier park failed at line %u: park=%u error=%d route_error=%d callback_line=%u waiter_line=%u callback_cpu=%u waiter_cpu=%u state=%u queued=%u entered=%u gp_done=%u started=%u done=%u callback_done=%u\n', u32(421), u32(probe.observed_park), C.srcu_load_i32(&probe.result, 2), probe.route_error, probe.callback_failure_line, probe.waiter_failure_line, probe.cpu, probe.waiter_cpu, probe.task_state_at_failure, u32(probe.task_queued_at_failure), u32(probe.entered), u32(probe.gp_done), u32(probe.barrier_started), u32(probe.barrier_done), u32(probe.callback_done))
				result = -C.EIO
			}
		}
		C.srcu_barrier(&ssp)
		C.cleanup_srcu_struct(&ssp)
		return result
	}
}

struct WorkTest {
mut:
	work   C.work_struct
	ssp    &C.srcu_struct = unsafe { nil }
	done   C.completion
	result i32
}

@[export: 'vinix_linuxkpi_fixture_srcu_work_callback']
pub fn work_callback(work &C.work_struct) {
	unsafe {
		mut test := &WorkTest(work)
		if !C.vinix_linuxkpi_may_sleep() || usize(C.current_work()) != usize(work) {
			test.result = -C.EIO
		}
		C.synchronize_srcu(test.ssp)
		C.synchronize_srcu_expedited(test.ssp)
		C.srcu_barrier(test.ssp)
		C.complete(&test.done)
	}
}

fn work_progress() i32 {
	unsafe {
		mut ssp := C.srcu_struct{}
		mut result := C.init_srcu_struct(&ssp)
		if result != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test work caller domain init failed at line %u: error=%d\n', u32(458), result)
			return result
		}
		queue := C.alloc_workqueue(c'vinix-srcu-caller', 0, 1)
		if queue == nil {
			C.kprintf(c'linuxkpi: SRCU self-test work caller queue allocation failed at line %u: error=%d\n', u32(463), -C.ENOMEM)
			C.cleanup_srcu_struct(&ssp)
			return -C.ENOMEM
		}
		mut test := WorkTest{ ssp: &ssp }
		C.INIT_WORK_ONSTACK(&test.work, C.vinix_linuxkpi_fixture_srcu_work_callback)
		C.init_completion(&test.done)
		C.BUG_ON(!C.queue_work_on(0, queue, &test.work))
		if C.wait_for_completion_timeout(&test.done, 500) == 0 {
			C.kprintf(c'linuxkpi: SRCU self-test work caller completion failed at line %u: gp=%lu needed=%lu\n', u32(471), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq), C.srcu_read_word(ssp.srcu_sup.srcu_gp_seq_needed))
			result = -C.EIO
		}
		C.destroy_workqueue(queue)
		if test.result != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test work caller context failed at line %u: error=%d\n', u32(478), test.result)
			result = -C.EIO
		}
		C.cleanup_srcu_struct(&ssp)
		return result
	}
}

@[export: 'vinix_linuxkpi_srcu_native_selftest']
pub fn selftest() i32 {
	unsafe {
		mut result := readers()
		if result != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test reader batch failed at line %u: error=%d\n', u32(488), result)
		}
		mut error := callbacks()
		if error != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test callback batch failed at line %u: error=%d\n', u32(491), error)
			result = -C.EIO
		}
		error = work_progress()
		if error != 0 {
			C.kprintf(c'linuxkpi: SRCU self-test work caller batch failed at line %u: error=%d\n', u32(496), error)
			result = -C.EIO
		}
		for repeat in 0 .. 20 {
			for stage in 0 .. 2 {
				mut ssp := C.srcu_struct{}
				C.vinix_linuxkpi_test_alloc_oom(i32(stage))
				constructor_error := C.init_srcu_struct(&ssp)
				C.vinix_linuxkpi_test_alloc_oom(-1)
				if constructor_error != -C.ENOMEM {
					C.kprintf(c'linuxkpi: SRCU self-test constructor fault failed at line %u: repeat=%u stage=%d error=%d\n', u32(508), u32(repeat), i32(stage), constructor_error)
					result = -C.EIO
				}
				if constructor_error != 0 && (ssp.sda != nil || ssp.srcu_sup != nil) {
					C.kprintf(c'linuxkpi: SRCU self-test constructor rollback failed at line %u: repeat=%u stage=%d sda_present=%u usage_present=%u\n', u32(513), u32(repeat), i32(stage), u32(ssp.sda != nil), u32(ssp.srcu_sup != nil))
					result = -C.EIO
				}
				if constructor_error == 0 { C.cleanup_srcu_struct(&ssp) }
			}
		}
		for repeat in 0 .. 8 {
			mut ssp := C.srcu_struct{}
			if C.init_srcu_struct(&ssp) != 0 {
				C.kprintf(c'linuxkpi: SRCU self-test domain reinitialization failed at line %u: repeat=%u\n', u32(524), u32(repeat))
				return -C.ENOMEM
			}
			index := C.srcu_read_lock(&ssp)
			C.msleep(1)
			C.srcu_read_unlock(&ssp, index)
			C.synchronize_srcu_expedited(&ssp)
			cookie := C.start_poll_synchronize_srcu(&ssp)
			if poll(&ssp, cookie) != 0 {
				C.kprintf(c'linuxkpi: SRCU self-test reinitialized domain poll failed at line %u: repeat=%u cookie=%lu\n', u32(533), u32(repeat), cookie)
				result = -C.EIO
			}
			C.srcu_barrier(&ssp)
			C.cleanup_srcu_struct(&ssp)
		}
		return result
	}
}
