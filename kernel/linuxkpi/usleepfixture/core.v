// SPDX-License-Identifier: GPL-2.0-only
// Independent native sleep fixture: unchanged minimums, wakeups and retirement.
@[translated]
module usleepfixture

#include "linuxkpi_usleep_fixture_v_contract.h"

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.vkus_ull {}
fn C.memcpy(voidptr, voidptr, usize) voidptr
struct C.completion {}
struct C.task_struct {
	vinix_thread voidptr
	__state u32
	in_iowait u32
}
type SleepWorker = fn (voidptr) voidptr
fn C.vinix_linuxkpi_fixture_usleep_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, SleepWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.completion_done(&C.completion) bool
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_clock_ns() u64
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_test_alloc_oom(i32)
fn C.vinix_linuxkpi_test_worker_oom(i32)
fn C.vinix_linuxkpi_test_task_signal(voidptr, u64)
fn C.vinix_linuxkpi_test_task_time_waiters(&C.task_struct) usize
fn C.vinix_linuxkpi_test_thread_reap_ready(voidptr) bool
fn C.vinix_linuxkpi_test_reap_quiescent() bool
fn C.vinix_linuxkpi_task_queued(voidptr) bool
fn C.task_is_running(&C.task_struct) bool
fn C.wake_up_process(&C.task_struct) i32
fn C.usleep_range(usize, usize)
fn C.usleep_idle_range(usize, usize)
fn C.usleep_range_state(usize, usize, u32)
fn C.msleep(u32)
fn C.cond_resched() i32
fn C.time_after_eq(usize, usize) bool
fn C.__atomic_load(voidptr, voidptr, i32)
fn C.__atomic_store(voidptr, voidptr, i32)
fn C.__atomic_load_n(&u32, i32) u32
fn C.BUG_ON(bool)
fn C.BUG()
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.current &C.task_struct
@[c_extern]
__global C.jiffies usize
@[c_extern]
__global (
	C.TASK_RUNNING u32
	C.TASK_UNINTERRUPTIBLE u32
	C.TASK_IDLE u32
	C.TASK_INTERRUPTIBLE u32
	C.TASK_KILLABLE u32
	C.TASK_DEAD u32
	C.EIO i32
	C.ENOMEM i32
	C.EAGAIN i32
)

const long_us = usize(50000)
const long_ns = u64(50000000)

struct NativeSleepWorker {
mut:
	task &C.task_struct = unsafe { nil }
	thread C.pthread_t
	entered C.completion
	go C.completion
	series_done C.completion
	long_go C.completion
	long_started C.completion
	long_done C.completion
	release C.completion
	done C.completion
	long_start u64
	long_elapsed u64
	failed_elapsed u64
	failed_min usize
	cpu u32
	state u32
	kind u32
	failed_case u32
	reasons u32
	early_wakes u32
	signal_sent u32
	signal_reparked u32
	initialized bool
	started bool
	cancel bool
}

fn cancelled(test &NativeSleepWorker) bool {
	mut value := false
	unsafe { C.__atomic_load(&test.cancel, &value, 2) }
	return value
}

fn retained_task(test &NativeSleepWorker) &C.task_struct {
	mut task := unsafe { &C.task_struct(nil) }
	unsafe { C.__atomic_load(&test.task, &task, 2) }
	return task
}

fn unsigned_long_long(value u64) C.vkus_ull {
	mut native := C.vkus_ull{}
	unsafe { C.memcpy(&native, &value, sizeof(u64)) }
	return native
}

fn sleep_call(test &NativeSleepWorker, minimum usize, maximum usize) {
	if test.kind == 0 { C.usleep_range(minimum, maximum) }
	else if test.kind == 1 { C.usleep_idle_range(minimum, maximum) }
	else { C.usleep_range_state(minimum, maximum, test.state) }
}

fn check(test &NativeSleepWorker, index u32, minimum usize, elapsed u64, flags usize, depth u32) {
	unsafe {
		mut reasons := u32(0)
		if elapsed < u64(minimum) * 1000 { reasons |= 1 }
		if !C.task_is_running(C.current) { reasons |= 2 }
		if !C.vinix_linuxkpi_may_sleep() || C.vinix_linuxkpi_irq_flags() != flags ||
			C.vinix_linuxkpi_preempt_count() != depth { reasons |= 4 }
		if C.vinix_linuxkpi_cpu_id() != test.cpu { reasons |= 8 }
		if C.current.in_iowait != 0 { reasons |= 16 }
		if reasons != 0 && test.reasons == 0 {
			test.failed_case = index
			test.failed_min = minimum
			test.failed_elapsed = elapsed
		}
		test.reasons |= reasons
	}
}

// Return to the common original out path when cancellation is observed.
fn series(test &NativeSleepWorker) bool {
	unsafe {
		ranges := [usize(0), usize(0), usize(0), usize(500), usize(1), usize(1),
			usize(100), usize(250), usize(400), usize(500), usize(1000), usize(2000),
			usize(3000), usize(4000)]!
		C.vinix_linuxkpi_test_alloc_oom(0)
		for round in 0 .. 4 {
			for i in 0 .. 7 {
				if cancelled(test) { return false }
				flags := C.vinix_linuxkpi_irq_flags()
				depth := C.vinix_linuxkpi_preempt_count()
				before := C.vinix_linuxkpi_clock_ns()
				sleep_call(test, ranges[i * 2], ranges[i * 2 + 1])
				check(test, u32(round * 7 + i), ranges[i * 2], C.vinix_linuxkpi_clock_ns() - before, flags, depth)
			}
		}
		if test.kind == 0 {
			flags := C.vinix_linuxkpi_irq_flags()
			depth := C.vinix_linuxkpi_preempt_count()
			before := C.vinix_linuxkpi_clock_ns()
			C.usleep_range_state(1000, 2000, u32(C.TASK_RUNNING))
			check(test, 28, 1000, C.vinix_linuxkpi_clock_ns() - before, flags, depth)
		}
		C.vinix_linuxkpi_test_alloc_oom(-1)
		C.complete(&test.series_done)
		C.wait_for_completion(&test.long_go)
		if cancelled(test) { return false }
		flags := C.vinix_linuxkpi_irq_flags()
		depth := C.vinix_linuxkpi_preempt_count()
		test.long_start = C.vinix_linuxkpi_clock_ns()
		C.complete(&test.long_started)
		C.vinix_linuxkpi_test_alloc_oom(0)
		sleep_call(test, long_us, long_us + 1000)
		test.long_elapsed = C.vinix_linuxkpi_clock_ns() - test.long_start
		C.vinix_linuxkpi_test_alloc_oom(-1)
		check(test, 29, long_us, test.long_elapsed, flags, depth)
		C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, 0)
		C.complete(&test.long_done)
		C.wait_for_completion(&test.release)
		return true
	}
}

@[export: 'vinix_linuxkpi_fixture_usleep_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut test := &NativeSleepWorker(argument)
		task := C.get_task_struct(C.current)
		C.__atomic_store(&test.task, &task, 3)
		if C.vinix_linuxkpi_worker_bind(test.cpu) != 0 { test.reasons |= 32 }
		C.complete(&test.entered)
		C.wait_for_completion(&test.go)
		if !cancelled(test) { series(test) }
		C.vinix_linuxkpi_test_alloc_oom(-1)
		C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, 0)
		if !C.task_is_running(C.current) || !C.vinix_linuxkpi_may_sleep() { test.reasons |= 64 }
		C.complete(&test.done)
		C.pthread_exit(nil)
		return nil
	}
}

fn release(test &NativeSleepWorker) {
	unsafe {
		if !test.initialized { return }
		cancel := true
		C.__atomic_store(&test.cancel, &cancel, 3)
		C.complete_all(&test.go)
		C.complete_all(&test.long_go)
		C.complete_all(&test.release)
		task := retained_task(test)
		if test.started && task != nil {
			C.vinix_linuxkpi_test_task_signal(task.vinix_thread, 0)
			C.wake_up_process(task)
		}
	}
}

fn retire(tests &NativeSleepWorker, count u32) i32 {
	unsafe {
		mut result := i32(0)
		for i := u32(0); i < count; i++ { release(&tests[i]) }
		for i := u32(0); i < count; i++ {
			if !tests[i].started { continue }
			if C.wait_for_completion_timeout(&tests[i].done, 500) == 0 {
				C.kprintf(c'linuxkpi: usleep worker=%u did not finish before cleanup watchdog\n', i)
				C.BUG()
			}
			C.BUG_ON(C.pthread_join(tests[i].thread, nil) != 0)
		}
		retirement_started := C.vinix_linuxkpi_clock_ns()
		for i := u32(0); i < count; i++ {
			if !tests[i].started { continue }
			task := retained_task(&tests[i])
			C.BUG_ON(task == nil)
			if tests[i].reasons != 0 {
				C.kprintf(c'linuxkpi: usleep worker=%u reasons=0x%x case=%u min=%lu elapsed_ns=%llu\n',
					i, tests[i].reasons, tests[i].failed_case, tests[i].failed_min, unsigned_long_long(tests[i].failed_elapsed))
				result = -C.EIO
			}
			for C.__atomic_load_n(&task.__state, 2) != C.TASK_DEAD {
				if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 {
					C.kprintf(c'linuxkpi: usleep worker=%u did not publish TASK_DEAD\n', i)
					C.BUG()
				}
				C.cond_resched()
			}
			retained := C.vinix_linuxkpi_test_task_time_waiters(task)
			if retained != 0 {
				C.kprintf(c'linuxkpi: usleep worker=%u retained %zu deadline records\n', i, retained)
				C.BUG()
			}
		}
		for i := u32(0); i < count; i++ {
			if !tests[i].started { continue }
			for !C.vinix_linuxkpi_test_thread_reap_ready(tests[i].task.vinix_thread) {
				if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 {
					C.kprintf(c'linuxkpi: usleep worker=%u did not reach off-stack reaper\n', i)
					C.BUG()
				}
				C.cond_resched()
			}
		}
		for i := u32(0); i < count; i++ {
			if !tests[i].started { continue }
			C.put_task_struct(tests[i].task)
			tests[i].started = false
		}
		for !C.vinix_linuxkpi_test_reap_quiescent() {
			if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 {
				C.kprintf(c'linuxkpi: usleep deferred frees did not finish\n')
				C.BUG()
			}
			C.cond_resched()
		}
		return result
	}
}

fn wakes(tests &NativeSleepWorker, count u32) i32 {
	unsafe {
		watchdog := C.jiffies + 500
		for {
			mut finished := true
			for i := u32(0); i < count; i++ {
				mut test := &tests[i]
				if C.completion_done(&test.long_done) { continue }
				finished = false
				task := test.task
				if C.__atomic_load_n(&task.__state, 2) != test.state ||
					C.vinix_linuxkpi_task_queued(task.vinix_thread) ||
					C.vinix_linuxkpi_test_task_time_waiters(task) == 0 { continue }
				before := C.vinix_linuxkpi_clock_ns()
				early := before - test.long_start < long_ns
				if i < 2 && early && test.signal_sent == 0 {
					test.signal_sent = 1
					C.vinix_linuxkpi_test_task_signal(task.vinix_thread, u64(1) << 14)
					continue
				}
				if early && test.signal_sent != 0 { test.signal_reparked = 1 }
				accepted := C.wake_up_process(task)
				if accepted != 0 && C.vinix_linuxkpi_clock_ns() - test.long_start < long_ns { test.early_wakes++ }
			}
			if finished { break }
			if C.time_after_eq(C.jiffies, watchdog) {
				C.kprintf(c'linuxkpi: usleep did not finish under continuing wakeups\n')
				return -C.EIO
			}
			C.msleep(1)
		}
		mut early_wakes := u32(0)
		mut signal_reparks := u32(0)
		for i := u32(0); i < count; i++ {
			early_wakes += tests[i].early_wakes
			signal_reparks += tests[i].signal_reparked
			if tests[i].long_elapsed < long_ns { return -C.EIO }
		}
		if early_wakes == 0 || signal_reparks == 0 {
			C.kprintf(c'linuxkpi: usleep early-wake proof not observed wakes=%u signal_reparks=%u\n', early_wakes, signal_reparks)
			return -C.EIO
		}
		return 0
	}
}

fn start_and_run(tests &NativeSleepWorker, fail_after u32, oom_stage u32) i32 {
	unsafe {
		states := [u32(C.TASK_UNINTERRUPTIBLE), u32(C.TASK_IDLE), u32(C.TASK_INTERRUPTIBLE), u32(C.TASK_KILLABLE)]!
		C.BUG_ON(oom_stage != 0 && (oom_stage > 4 || fail_after >= 4))
		for i := u32(0); i < 4; i++ {
			mut test := &tests[i]
			test.cpu = i
			test.kind = i
			test.state = states[i]
			C.init_completion(&test.entered)
			C.init_completion(&test.go)
			C.init_completion(&test.series_done)
			C.init_completion(&test.long_go)
			C.init_completion(&test.long_started)
			C.init_completion(&test.long_done)
			C.init_completion(&test.release)
			C.init_completion(&test.done)
			test.initialized = true
			if oom_stage != 0 && i == fail_after { C.vinix_linuxkpi_test_worker_oom(i32(oom_stage)) }
			error := C.pthread_create(&test.thread, nil, C.vinix_linuxkpi_fixture_usleep_worker, test)
			C.vinix_linuxkpi_test_worker_oom(0)
			if error == 0 { test.started = true }
			if oom_stage != 0 && i == fail_after {
				return if error != C.EAGAIN || test.started { -C.EIO } else { i32(0) }
			}
			if error != 0 { return -C.ENOMEM }
			if C.wait_for_completion_timeout(&test.entered, 500) == 0 { return -C.EIO }
		}
		for i in 0 .. 4 { C.complete(&tests[i].go) }
		for i in 0 .. 4 { if C.wait_for_completion_timeout(&tests[i].series_done, 500) == 0 { return -C.EIO } }
		for i in 0 .. 4 { C.complete(&tests[i].long_go) }
		for i in 0 .. 4 { if C.wait_for_completion_timeout(&tests[i].long_started, 500) == 0 { return -C.EIO } }
		return wakes(tests, 4)
	}
}

fn group(fail_after u32, oom_stage u32) i32 {
	unsafe {
		mut tests := [4]NativeSleepWorker{}
		mut result := start_and_run(&tests[0], fail_after, oom_stage)
		if retire(&tests[0], 4) != 0 { result = -C.EIO }
		return result
	}
}

@[export: 'vinix_linuxkpi_usleep_native_selftest']
pub fn selftest() i32 {
	unsafe {
		if C.vinix_linuxkpi_percpu_count() < 4 { return -C.EIO }
		mut result := i32(0)
		for stage in 1 .. 5 {
			for before in 0 .. 4 {
				if group(u32(before), u32(stage)) != 0 {
					C.kprintf(c'linuxkpi: usleep constructor rollback stage=%u after=%u failed\n', u32(stage), u32(before))
					result = -C.EIO
				}
			}
		}
		if group(0, 0) != 0 { result = -C.EIO }
		return result
	}
}
