// SPDX-License-Identifier: GPL-2.0-only
// Independent native I/O fixture retaining the original observations and deadlines.
@[translated]
module iofixture

#include "linuxkpi_io_fixture_v_contract.h"

@[typedef]
struct C.raw_spinlock_t {}

@[typedef]
struct C.atomic_long_t {}

@[typedef]
struct C.pthread_t {}

struct C.task_struct {
	vinix_thread voidptr
	__state u32
	vinix_wait_lock C.raw_spinlock_t
	in_iowait u32
}

struct C.list_head {
	next &C.list_head
	prev &C.list_head
}

struct C.mutex {
	owner C.atomic_long_t
	wait_lock C.raw_spinlock_t
	wait_list C.list_head
}

struct C.completion {}

struct C.wait_bit_key {
mut:
	flags &usize
	bit_nr i32
	timeout usize
}

type IoWorker = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_io_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, IoWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.completion_done(&C.completion) bool
fn C.io_schedule_prepare() i32
fn C.io_schedule_finish(i32)
fn C.io_schedule()
fn C.io_schedule_timeout(isize) isize
fn C.schedule()
fn C.set_current_state(u32)
fn C.__set_current_state(u32)
fn C.task_is_running(&C.task_struct) bool
fn C.cond_resched() i32
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.raw_spin_lock_irqsave(&C.raw_spinlock_t, usize)
fn C.raw_spin_unlock_irqrestore(&C.raw_spinlock_t, usize)
fn C.vinix_linuxkpi_task_dequeue(voidptr)
fn C.vinix_linuxkpi_task_queued(voidptr) bool
fn C.vinix_linuxkpi_iowait_block(voidptr)
fn C.vinix_linuxkpi_test_task_signal(voidptr, u64)
fn C.vinix_linuxkpi_test_worker_route(voidptr, u32) i32
fn C.vinix_linuxkpi_test_worker_oom(i32)
fn C.vinix_linuxkpi_test_park_preempt()
fn C.nr_iowait_cpu(u32) u32
fn C.nr_iowait() u32
fn C.wake_up_process(&C.task_struct) i32
fn C.time_after_eq(usize, usize) bool
fn C.msleep(u32)
fn C.mutex_init(&C.mutex)
fn C.mutex_destroy(&C.mutex)
fn C.mutex_lock(&C.mutex)
fn C.mutex_lock_io(&C.mutex)
fn C.mutex_lock_io_nested(&C.mutex, i32)
fn C.mutex_unlock(&C.mutex)
fn C.mutex_is_locked(&C.mutex) bool
fn C.atomic_long_read(&C.atomic_long_t) isize
fn C.wait_on_bit_io(&usize, i32, u32) i32
fn C.wait_on_bit_lock_io(&usize, i32, u32) i32
fn C.bit_wait_io_timeout(&C.wait_bit_key, i32) i32
fn C.test_bit(i32, &usize) bool
fn C.clear_and_wake_up_bit(i32, &usize)
fn C.bit_waitqueue(&usize, i32) voidptr
fn C.waitqueue_active(voidptr) bool
fn C.__atomic_load(voidptr, voidptr, i32)
fn C.__atomic_store(voidptr, voidptr, i32)
fn C.__atomic_load_n(&u32, i32) u32
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.jiffies usize

@[c_extern]
__global (
	C.TASK_RUNNING u32
	C.TASK_INTERRUPTIBLE u32
	C.TASK_UNINTERRUPTIBLE u32
	C.TASK_DEAD u32
	C.MAX_SCHEDULE_TIMEOUT isize
	C.EIO i32
	C.ENOMEM i32
	C.EINTR i32
	C.EAGAIN i32
)

enum Operation {
	sleep
	timeout
	bit
	bit_lock
	preempt
	ordinary
	exit_counted
	mutex
	mutex_ordinary
}

struct IoThread {
mut:
	task &C.task_struct = unsafe { nil }
	thread C.pthread_t
	entered C.completion
	go C.completion
	acquired C.completion
	release C.completion
	done C.completion
	word &usize = unsafe { nil }
	mutex &C.mutex = unsafe { nil }
	baseline &u32 = unsafe { nil }
	timeout isize
	remaining isize
	cpu u32
	resumed_cpu u32
	state u32
	operation Operation
	value i32
	result i32
	initialized bool
	started bool
	nested bool
	cancel bool
}

fn cancelled(test &IoThread) bool {
	unsafe {
		mut value := false
		C.__atomic_load(&test.cancel, &value, 2)
		return value
	}
}

// Callback registration names the exported C wrapper, preserving native identity.
@[export: 'vinix_linuxkpi_fixture_io_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut test := &IoThread(argument)
		mut task := C.get_task_struct(C.current)
		C.__atomic_store(&test.task, &task, 3)
		mut outer := i32(-1)
		if C.vinix_linuxkpi_worker_bind(test.cpu) != 0 || C.current.in_iowait != 0 {
			test.result = -C.EIO
		}
		C.complete(&test.entered)
		C.wait_for_completion(&test.go)
		if !cancelled(test) {
			if test.nested {
				outer = C.io_schedule_prepare()
				inner := C.io_schedule_prepare()
				if outer != 0 || inner != 1 || C.current.in_iowait == 0 { test.result = -C.EIO }
				C.io_schedule_finish(inner)
				if C.current.in_iowait == 0 { test.result = -C.EIO }
			}
			if test.operation == .exit_counted {
				// Keep IRQs disabled through the actual dead dequeue and pthread exit.
				token := C.io_schedule_prepare()
				C.vinix_linuxkpi_irq_save()
				mut wait_flags := usize(0)
				C.raw_spin_lock_irqsave(&test.task.vinix_wait_lock, wait_flags)
				C.set_current_state(C.TASK_UNINTERRUPTIBLE)
				C.vinix_linuxkpi_task_dequeue(test.task.vinix_thread)
				C.vinix_linuxkpi_iowait_block(test.task.vinix_thread)
				C.raw_spin_unlock_irqrestore(&test.task.vinix_wait_lock, wait_flags)
				if token != 0 || C.nr_iowait_cpu(test.cpu) != test.baseline[test.cpu] + 1 {
					test.result = -C.EIO
				}
				C.complete(&test.done)
				C.pthread_exit(nil)
				return nil
			}
			if test.operation == .mutex || test.operation == .mutex_ordinary {
				if test.operation == .mutex { C.mutex_lock_io_nested(test.mutex, 1) }
				else { C.mutex_lock(test.mutex) }
				if (C.current.in_iowait != 0) != test.nested ||
					C.atomic_long_read(&test.mutex.owner) != isize(C.current) { test.result = -C.EIO }
				if outer >= 0 { C.io_schedule_finish(outer); outer = -1 }
				test.resumed_cpu = C.vinix_linuxkpi_cpu_id()
				C.complete(&test.acquired)
				C.wait_for_completion(&test.release)
				C.mutex_unlock(test.mutex)
			} else if test.operation == .bit {
				test.value = C.wait_on_bit_io(test.word, 0, test.state)
			} else if test.operation == .bit_lock {
				test.value = C.wait_on_bit_lock_io(test.word, 0, test.state)
				if test.value == 0 {
					if !C.test_bit(0, test.word) || C.current.in_iowait != 0 { test.result = -C.EIO }
					C.complete(&test.acquired)
					C.wait_for_completion(&test.release)
					C.clear_and_wake_up_bit(0, test.word)
				}
			} else {
				C.set_current_state(test.state)
				// Cancellation publication pairs with the state-store barrier.
				if cancelled(test) { C.__set_current_state(C.TASK_RUNNING) }
				else {
					if test.operation == .preempt { C.vinix_linuxkpi_test_park_preempt() }
					if test.operation == .timeout { test.remaining = C.io_schedule_timeout(test.timeout) }
					else if test.operation == .ordinary { C.schedule() }
					else { C.io_schedule() }
				}
			}
			test.resumed_cpu = C.vinix_linuxkpi_cpu_id()
		}
		if outer >= 0 {
			if C.current.in_iowait == 0 { test.result = -C.EIO }
			C.io_schedule_finish(outer)
		}
		C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, 0)
		if C.current.in_iowait != 0 || !C.task_is_running(C.current) || !C.vinix_linuxkpi_may_sleep() {
			test.result = -C.EIO
		}
		C.complete(&test.done)
		C.pthread_exit(nil)
		return nil
	}
}

fn start(test &IoThread, operation Operation, cpu u32, state u32, timeout isize,
	word &usize, baseline &u32, nested bool) i32 {
	unsafe {
		*test = IoThread{ operation: operation, cpu: cpu, state: state, timeout: timeout,
			word: word, baseline: baseline, nested: nested }
		C.init_completion(&test.entered)
		C.init_completion(&test.go)
		C.init_completion(&test.acquired)
		C.init_completion(&test.release)
		C.init_completion(&test.done)
		test.initialized = true
		if C.pthread_create(&test.thread, nil, C.vinix_linuxkpi_fixture_io_worker, test) != 0 {
			return -C.ENOMEM
		}
		test.started = true
		return if C.wait_for_completion_timeout(&test.entered, 500) != 0 { i32(0) } else { -C.EIO }
	}
}

fn parked(test &IoThread) i32 {
	unsafe {
		deadline := C.jiffies + 500
		for {
			if C.completion_done(&test.done) { return -C.EIO }
			if C.__atomic_load_n(&test.task.__state, 2) == test.state &&
				!C.vinix_linuxkpi_task_queued(test.task.vinix_thread) { return 0 }
			if C.time_after_eq(C.jiffies, deadline) { return -C.EIO }
			C.msleep(1)
		}
	}
}

fn join(test &IoThread) i32 {
	unsafe {
		if !test.started { return 0 }
		C.BUG_ON(C.pthread_join(test.thread, nil) != 0)
		for C.__atomic_load_n(&test.task.__state, 2) != C.TASK_DEAD { C.cond_resched() }
		result := test.result
		C.put_task_struct(test.task)
		test.started = false
		return result
	}
}

fn counts(baseline &u32, cpu0 u32, cpu1 u32) i32 {
	unsafe {
		deadline := C.jiffies + 500
		count := C.vinix_linuxkpi_percpu_count()
		for {
			mut total := u32(0)
			mut matches := true
			for cpu := u32(0); cpu < count; cpu++ {
				expected := baseline[cpu] + if cpu == 0 { cpu0 } else if cpu == 1 { cpu1 } else { u32(0) }
				total += expected
				if C.nr_iowait_cpu(cpu) != expected { matches = false }
			}
			if matches && C.nr_iowait() == total { return 0 }
			if C.time_after_eq(C.jiffies, deadline) { return -C.EIO }
			C.msleep(1)
		}
	}
}

fn release(test &IoThread) {
	unsafe {
		if !test.initialized { return }
		mut cancel := true
		C.__atomic_store(&test.cancel, &cancel, 3)
		C.complete_all(&test.go)
		C.complete_all(&test.release)
		mut task := &C.task_struct(nil)
		C.__atomic_load(&test.task, &task, 2)
		if test.started && task != nil && test.operation != .exit_counted { C.wake_up_process(task) }
	}
}

fn pool_counts(baseline &u32) i32 {
	unsafe {
		mut tests := [3]IoThread{}
		mut result := i32(0)
		for i in 0 .. 3 {
			cpu := if i == 2 { u32(1) } else { u32(0) }
			if start(&tests[i], if i == 1 { Operation.preempt } else { Operation.sleep }, cpu,
				C.TASK_UNINTERRUPTIBLE, 0, nil, baseline, i == 0) != 0 { result = -C.EIO; break }
			C.complete(&tests[i].go)
			if parked(&tests[i]) != 0 { result = -C.EIO; break }
		}
		if result == 0 && counts(baseline, 2, 1) != 0 { result = -C.EIO }
		if result == 0 {
			C.vinix_linuxkpi_test_task_signal(tests[1].task.vinix_thread, u64(1) << 14)
			if parked(&tests[1]) != 0 || counts(baseline, 2, 1) != 0 { result = -C.EIO }
			// Keep proceeding here after that observation fails, as the original did.
			if C.vinix_linuxkpi_test_worker_route(tests[0].task.vinix_thread, 1) != 0 { result = -C.EIO }
			C.wake_up_process(tests[0].task)
			C.wake_up_process(tests[0].task)
			if C.wait_for_completion_timeout(&tests[0].done, 500) == 0 || tests[0].resumed_cpu != 1 ||
				counts(baseline, 1, 1) != 0 { result = -C.EIO }
		}
		for i in 0 .. 3 { release(&tests[i]) }
		for i in 0 .. 3 { if join(&tests[i]) != 0 { result = -C.EIO } }
		if counts(baseline, 0, 0) != 0 { result = -C.EIO }
		return result
	}
}

fn timeout(baseline &u32, expire bool, interrupt bool) i32 {
	unsafe {
		mut test := IoThread{}
		state := if interrupt { C.TASK_INTERRUPTIBLE } else { C.TASK_UNINTERRUPTIBLE }
		mut result := start(&test, .timeout, 0, state, 200, nil, baseline, true)
		if result == 0 {
			C.complete(&test.go)
			if parked(&test) != 0 || counts(baseline, 1, 0) != 0 { result = -C.EIO }
			else {
				if interrupt { C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, u64(1) << 14) }
				else if !expire { C.wake_up_process(test.task) }
				if C.wait_for_completion_timeout(&test.done, 500) == 0 ||
					(if expire { test.remaining != 0 } else { test.remaining <= 0 || test.remaining > 200 }) {
					result = -C.EIO
				}
			}
		}
		release(&test)
		if join(&test) != 0 || counts(baseline, 0, 0) != 0 { result = -C.EIO }
		return result
	}
}

fn bits(baseline &u32, want_lock bool, interrupt bool) i32 {
	unsafe {
		mut word := usize(1)
		mut tests := [2]IoThread{}
		nr := if want_lock && !interrupt { 2 } else { 1 }
		mut result := i32(0)
		for i in 0 .. nr {
			if start(&tests[i], if want_lock { Operation.bit_lock } else { Operation.bit }, 0,
				if interrupt { C.TASK_INTERRUPTIBLE } else { C.TASK_UNINTERRUPTIBLE },
				0, &word, baseline, false) != 0 { result = -C.EIO; break }
			C.complete(&tests[i].go)
			if parked(&tests[i]) != 0 { result = -C.EIO; break }
		}
		if result == 0 && counts(baseline, u32(nr), 0) != 0 { result = -C.EIO }
		if result == 0 {
			if interrupt {
				C.vinix_linuxkpi_test_task_signal(tests[0].task.vinix_thread, u64(1) << 14)
				if C.wait_for_completion_timeout(&tests[0].done, 500) == 0 || tests[0].value != -C.EINTR ||
					!C.test_bit(0, &word) { result = -C.EIO }
			} else {
				C.clear_and_wake_up_bit(0, &word)
				if want_lock {
					if C.wait_for_completion_timeout(&tests[0].acquired, 500) == 0 ||
						C.completion_done(&tests[1].acquired) || counts(baseline, 1, 0) != 0 { result = -C.EIO }
					else {
						C.complete(&tests[0].release)
						if C.wait_for_completion_timeout(&tests[1].acquired, 500) == 0 || counts(baseline, 0, 0) != 0 {
							result = -C.EIO
						}
					}
				} else if C.wait_for_completion_timeout(&tests[0].done, 500) == 0 { result = -C.EIO }
			}
		}
		for i in 0 .. nr { release(&tests[i]) }
		C.clear_and_wake_up_bit(0, &word)
		for i in 0 .. nr { if join(&tests[i]) != 0 { result = -C.EIO } }
		if C.waitqueue_active(C.bit_waitqueue(&word, 0)) || counts(baseline, 0, 0) != 0 { result = -C.EIO }
		return result
	}
}

fn fast_paths(baseline &u32) i32 {
	unsafe {
		task := C.current
		mut mutex := C.mutex{}
		C.mutex_init(&mutex)
		mut result := i32(0)
		for _ in 0 .. 128 {
			C.mutex_lock_io(&mutex)
			if task.in_iowait != 0 || C.atomic_long_read(&mutex.owner) != isize(task) ||
				counts(baseline, 0, 0) != 0 { result = -C.EIO }
			C.mutex_unlock(&mutex)
			outer := C.io_schedule_prepare()
			inner := C.io_schedule_prepare()
			if outer != 0 || inner != 1 || task.in_iowait == 0 { result = -C.EIO }
			C.io_schedule_finish(inner)
			if task.in_iowait == 0 || counts(baseline, 0, 0) != 0 { result = -C.EIO }
			C.mutex_lock_io_nested(&mutex, 1)
			if task.in_iowait == 0 || C.atomic_long_read(&mutex.owner) != isize(task) ||
				counts(baseline, 0, 0) != 0 { result = -C.EIO }
			C.mutex_unlock(&mutex)
			C.io_schedule()
			if C.io_schedule_timeout(C.MAX_SCHEDULE_TIMEOUT) != C.MAX_SCHEDULE_TIMEOUT ||
				C.io_schedule_timeout(0) != 0 || task.in_iowait == 0 { result = -C.EIO }
			C.io_schedule_finish(outer)
			C.set_current_state(C.TASK_INTERRUPTIBLE)
			C.vinix_linuxkpi_test_task_signal(task.vinix_thread, u64(1) << 14)
			remaining := C.io_schedule_timeout(10)
			if remaining < 0 || remaining > 10 || task.in_iowait != 0 || !C.task_is_running(task) { result = -C.EIO }
			C.vinix_linuxkpi_test_task_signal(task.vinix_thread, 0)
			token := C.io_schedule_prepare()
			flags := C.vinix_linuxkpi_irq_save()
			mut wait_flags := usize(0)
			C.raw_spin_lock_irqsave(&task.vinix_wait_lock, wait_flags)
			C.set_current_state(C.TASK_UNINTERRUPTIBLE)
			C.vinix_linuxkpi_task_dequeue(task.vinix_thread)
			C.raw_spin_unlock_irqrestore(&task.vinix_wait_lock, wait_flags)
			if C.wake_up_process(task) == 0 { result = -C.EIO }
			C.raw_spin_lock_irqsave(&task.vinix_wait_lock, wait_flags)
			C.vinix_linuxkpi_iowait_block(task.vinix_thread)
			C.raw_spin_unlock_irqrestore(&task.vinix_wait_lock, wait_flags)
			C.io_schedule_finish(token)
			C.vinix_linuxkpi_irq_restore(flags)
			if !C.task_is_running(task) || task.in_iowait != 0 || counts(baseline, 0, 0) != 0 { result = -C.EIO }
			mut word := usize(1)
			mut key := C.wait_bit_key{ flags: &word, bit_nr: 0, timeout: C.jiffies }
			if C.bit_wait_io_timeout(&key, i32(C.TASK_UNINTERRUPTIBLE)) != -C.EAGAIN || task.in_iowait != 0 {
				result = -C.EIO
			}
		}
		C.mutex_destroy(&mutex)
		return result
	}
}

fn mutex_waiters(mutex &C.mutex, expected u32) i32 {
	unsafe {
		deadline := C.jiffies + 500
		for {
			mut flags := usize(0)
			mut count := u32(0)
			C.raw_spin_lock_irqsave(&mutex.wait_lock, flags)
			mut entry := mutex.wait_list.next
			for usize(entry) != usize(&mutex.wait_list) { count++; entry = entry.next }
			C.raw_spin_unlock_irqrestore(&mutex.wait_lock, flags)
			if count == expected { return 0 }
			if C.time_after_eq(C.jiffies, deadline) { return -C.EIO }
			C.msleep(1)
		}
	}
}

fn mutex_handoffs(baseline &u32, fail_after u32, oom_stage u32) i32 {
	unsafe {
		mut tests := [3]IoThread{}
		mut mutex := C.mutex{}
		C.mutex_init(&mutex)
		C.mutex_lock(&mutex)
		mut held := true
		mut result := i32(0)
		mut constructed := true
		C.BUG_ON(oom_stage != 0 && (oom_stage > 4 || fail_after >= 3))
		for i in 0 .. 3 {
			if oom_stage != 0 && u32(i) == fail_after { C.vinix_linuxkpi_test_worker_oom(i32(oom_stage)) }
			started := start(&tests[i], if i == 1 { Operation.mutex_ordinary } else { Operation.mutex },
				if i != 0 { u32(1) } else { u32(0) }, C.TASK_UNINTERRUPTIBLE, 0, nil, baseline, i == 0)
			C.vinix_linuxkpi_test_worker_oom(0)
			if oom_stage != 0 && u32(i) == fail_after {
				if started != -C.ENOMEM || tests[i].started || counts(baseline, if i != 0 { u32(1) } else { u32(0) }, 0) != 0 {
					result = -C.EIO
				}
				constructed = false
				break
			}
			if started != 0 { result = -C.EIO; constructed = false; break }
			tests[i].mutex = &mutex
			C.complete(&tests[i].go)
			if mutex_waiters(&mutex, u32(i + 1)) != 0 || parked(&tests[i]) != 0 {
				result = -C.EIO; constructed = false; break
			}
		}
		if constructed {
			if counts(baseline, 1, 1) != 0 { result = -C.EIO }
			else {
				C.vinix_linuxkpi_test_task_signal(tests[2].task.vinix_thread, u64(1) << 14)
				if parked(&tests[2]) != 0 || mutex_waiters(&mutex, 3) != 0 || counts(baseline, 1, 1) != 0 { result = -C.EIO }
				else {
					if C.vinix_linuxkpi_test_worker_route(tests[0].task.vinix_thread, 1) != 0 {
						result = -C.EIO
					} else {
						C.mutex_unlock(&mutex)
						held = false
						for i in 0 .. 3 {
							if C.wait_for_completion_timeout(&tests[i].acquired, 500) == 0 ||
								C.atomic_long_read(&mutex.owner) != isize(tests[i].task) ||
								(i == 0 && tests[i].resumed_cpu != 1) ||
								(i + 1 < 3 && C.completion_done(&tests[i + 1].acquired)) ||
								counts(baseline, 0, if i < 2 { u32(1) } else { u32(0) }) != 0 {
								result = -C.EIO; break
							}
							C.complete(&tests[i].release)
						}
					}
				}
			}
		}
		// Release all initialized gates before joining, including partial OOM construction.
		for i in 0 .. 3 { release(&tests[i]) }
		if held { C.mutex_unlock(&mutex) }
		for i in 0 .. 3 { if join(&tests[i]) != 0 { result = -C.EIO } }
		if mutex_waiters(&mutex, 0) != 0 || C.mutex_is_locked(&mutex) || counts(baseline, 0, 0) != 0 { result = -C.EIO }
		C.mutex_destroy(&mutex)
		return result
	}
}

fn ordinary_and_exit(baseline &u32, exiting bool) i32 {
	unsafe {
		mut test := IoThread{}
		mut result := start(&test, if exiting { Operation.exit_counted } else { Operation.ordinary },
			0, C.TASK_UNINTERRUPTIBLE, 0, nil, baseline, false)
		if result == 0 {
			C.complete(&test.go)
			if exiting {
				if C.wait_for_completion_timeout(&test.done, 500) == 0 { result = -C.EIO }
			} else if parked(&test) != 0 || counts(baseline, 0, 0) != 0 { result = -C.EIO }
		}
		release(&test)
		if join(&test) != 0 || counts(baseline, 0, 0) != 0 { result = -C.EIO }
		return result
	}
}

@[export: 'vinix_linuxkpi_io_native_selftest']
pub fn selftest() i32 {
	unsafe {
		count := C.vinix_linuxkpi_percpu_count()
		mut baseline := [256]u32{}
		mut result := i32(0)
		if count < 2 || count > 256 { return -C.EIO }
		for cpu := u32(0); cpu < count; cpu++ { baseline[cpu] = C.nr_iowait_cpu(cpu) }
		if fast_paths(&baseline[0]) != 0 {
			C.kprintf(c'linuxkpi: I/O fast/nested/early-wake checks failed\n'); result = -C.EIO
		}
		if pool_counts(&baseline[0]) != 0 {
			C.kprintf(c'linuxkpi: I/O blocked CPU/migration/preempt checks failed\n'); result = -C.EIO
		}
		for stage in 1 .. 5 {
			for before in 0 .. 3 {
				if mutex_handoffs(&baseline[0], u32(before), u32(stage)) != 0 {
					C.kprintf(c'linuxkpi: I/O mutex constructor rollback stage=%u after=%u failed\n', u32(stage), u32(before))
					result = -C.EIO
				}
			}
		}
		if mutex_handoffs(&baseline[0], 0, 0) != 0 {
			C.kprintf(c'linuxkpi: I/O mutex FIFO/migration/intent checks failed\n'); result = -C.EIO
		}
		for kind in 0 .. 3 {
			if timeout(&baseline[0], kind == 0, kind == 2) != 0 {
				C.kprintf(c'linuxkpi: I/O timeout/early/signal checks failed\n'); result = -C.EIO
			}
		}
		for want_lock in 0 .. 2 {
			for interrupt in 0 .. 2 {
				if bits(&baseline[0], want_lock != 0, interrupt != 0) != 0 {
					C.kprintf(c'linuxkpi: I/O bit/lock/cancel checks failed\n'); result = -C.EIO
				}
			}
		}
		if ordinary_and_exit(&baseline[0], false) != 0 || ordinary_and_exit(&baseline[0], true) != 0 {
			C.kprintf(c'linuxkpi: I/O ordinary-sleep/dead-dequeue checks failed\n'); result = -C.EIO
		}
		if counts(&baseline[0], 0, 0) != 0 || C.current.in_iowait != 0 ||
			!C.task_is_running(C.current) || !C.vinix_linuxkpi_may_sleep() { result = -C.EIO }
		return result
	}
}
