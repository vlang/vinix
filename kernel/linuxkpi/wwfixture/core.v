// SPDX-License-Identifier: GPL-2.0-only
// Independent wound/wait fixture preserving original ownership and retries.
@[translated]
module wwfixture

#include "linuxkpi_ww_fixture_v_contract.h"
struct C.task_struct {
	__state      u32
	vinix_thread voidptr
}

struct C.list_head {}

@[typedef]
struct C.atomic_long_t {}

@[typedef]
struct C.raw_spinlock_t {}

struct C.mutex {
	owner     C.atomic_long_t
	wait_lock C.raw_spinlock_t
	wait_list C.list_head
}

struct C.ww_class {
	stamp        C.atomic_long_t
	acquire_name &char
	mutex_name   &char
	is_wait_die  u32
}

struct C.ww_acquire_ctx {
	stamp    usize
	acquired u32
	wounded  u16
}

struct C.ww_mutex {
	base C.mutex
	ctx  &C.ww_acquire_ctx
}

struct C.completion {}

@[typedef]
struct C.pthread_t {}

type WwWorker = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_ww_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, WwWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.task_is_running(&C.task_struct) bool
fn C.vinix_linuxkpi_may_sleep() bool
fn C.cond_resched() i32
fn C.msleep(u32)
fn C.vinix_linuxkpi_task_queued(voidptr) bool
fn C.time_after_eq(usize, usize) bool
fn C.__atomic_load_n(&u32, i32) u32

@[c: '__atomic_load_n']
fn C.ww_load_short(&u16, i32) u16

fn C.READ_ONCE(&C.ww_acquire_ctx) &C.ww_acquire_ctx
fn C.atomic_long_set(&C.atomic_long_t, isize)
fn C.atomic_long_read(&C.atomic_long_t) isize
fn C.ww_mutex_init(&C.ww_mutex, &C.ww_class)
fn C.ww_mutex_destroy(&C.ww_mutex)
fn C.ww_mutex_is_locked(&C.ww_mutex) bool
fn C.ww_acquire_init(&C.ww_acquire_ctx, &C.ww_class)
fn C.ww_acquire_done(&C.ww_acquire_ctx)
fn C.ww_acquire_fini(&C.ww_acquire_ctx)
fn C.ww_mutex_lock(&C.ww_mutex, &C.ww_acquire_ctx) i32
fn C.ww_mutex_lock_interruptible(&C.ww_mutex, &C.ww_acquire_ctx) i32
fn C.ww_mutex_lock_slow(&C.ww_mutex, &C.ww_acquire_ctx)
fn C.ww_mutex_trylock(&C.ww_mutex, &C.ww_acquire_ctx) bool
fn C.ww_mutex_unlock(&C.ww_mutex)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.completion_done(&C.completion) bool
fn C.vinix_linuxkpi_test_task_signal(voidptr, u64)
fn C.raw_spin_lock_irqsave(&C.raw_spinlock_t, usize)
fn C.raw_spin_unlock_irqrestore(&C.raw_spinlock_t, usize)
fn C.list_empty(&C.list_head) bool
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.jiffies usize

@[c_extern]
__global C.TASK_DEAD u32

@[c_extern]
__global C.TASK_UNINTERRUPTIBLE u32

@[c_extern]
__global C.TASK_INTERRUPTIBLE u32

@[c_extern]
__global C.EIO i32

@[c_extern]
__global C.ENOMEM i32

@[c_extern]
__global C.EDEADLK i32

@[c_extern]
__global C.EALREADY i32

@[c_extern]
__global C.EINTR i32

enum Operation {
	inversion
	wounded
	first
	interrupt
	context_free
}

struct NativeWwTest {
mut:
	class       C.ww_class
	locks       [3]C.ww_mutex
	entered     C.completion
	go          C.completion
	backed_off  C.completion
	done        C.completion
	parent      &C.task_struct = unsafe { nil }
	task        &C.task_struct = unsafe { nil }
	worker_id   C.pthread_t
	operation   Operation
	stamp       usize
	lock_result i32
	result      i32
	started     bool
	use_context bool
}

fn parked(task &C.task_struct, state u32) i32 {
	unsafe {
		deadline := C.jiffies + 500
		for C.__atomic_load_n(&task.__state, 2) != state || C.vinix_linuxkpi_task_queued(task.vinix_thread) {
			if C.time_after_eq(C.jiffies, deadline) { return -C.EIO }
			C.msleep(1)
		}
		return 0
	}
}

@[export: 'vinix_linuxkpi_fixture_ww_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut ctx := C.ww_acquire_ctx{}
		mut test := &NativeWwTest(argument)
		mut held := [false, false, false]!
		test.task = C.get_task_struct(C.current)
		if test.use_context {
			C.ww_acquire_init(&ctx, &test.class)
			test.stamp = ctx.stamp
		}
		if test.operation == .inversion || test.operation == .wounded {
			if C.ww_mutex_lock(&test.locks[1], &ctx) != 0 {
				test.result = -C.EIO
			} else {
				held[1] = true
			}
		}
		C.complete(&test.entered)
		C.wait_for_completion(&test.go)
		if test.operation == .inversion {
			if parked(test.parent, C.TASK_UNINTERRUPTIBLE) != 0 { test.result = -C.EIO }
			test.lock_result = C.ww_mutex_lock(&test.locks[0], &ctx)
			if test.lock_result != -C.EDEADLK || ctx.acquired != 1 { test.result = -C.EIO }
			if test.lock_result == 0 { held[0] = true }
			if held[0] {
				C.ww_mutex_unlock(&test.locks[0])
				held[0] = false
			}
			if held[1] {
				C.ww_mutex_unlock(&test.locks[1])
				held[1] = false
			}
			C.complete(&test.backed_off)
			if test.lock_result == -C.EDEADLK {
				C.ww_mutex_lock_slow(&test.locks[0], &ctx)
				held[0] = true
				if ctx.stamp != test.stamp || ctx.acquired != 1 || ctx.wounded != 0 {
					test.result = -C.EIO
				}
				if C.ww_mutex_lock(&test.locks[1], &ctx) != 0 {
					test.result = -C.EIO
				} else {
					held[1] = true
				}
				if ctx.acquired != 2 || C.ww_mutex_lock(&test.locks[0], &ctx) != -C.EALREADY
					|| C.ww_mutex_trylock(&test.locks[0], &ctx) || ctx.acquired != 2 {
					test.result = -C.EIO
				}
			}
		} else if test.operation == .wounded {
			test.lock_result = C.ww_mutex_lock(&test.locks[2], &ctx)
			if test.lock_result != -C.EDEADLK || ctx.wounded == 0 || ctx.acquired != 1 {
				test.result = -C.EIO
			}
			if test.lock_result == 0 { held[2] = true }
			if held[2] {
				C.ww_mutex_unlock(&test.locks[2])
				held[2] = false
			}
			if held[1] {
				C.ww_mutex_unlock(&test.locks[1])
				held[1] = false
			}
			C.complete(&test.backed_off)
			if test.lock_result == -C.EDEADLK {
				C.ww_mutex_lock_slow(&test.locks[2], &ctx)
				held[2] = true
				if ctx.stamp != test.stamp || ctx.acquired != 1 || ctx.wounded != 0 {
					test.result = -C.EIO
				}
				if C.ww_mutex_lock(&test.locks[1], &ctx) != 0 {
					test.result = -C.EIO
				} else {
					held[1] = true
				}
				if ctx.acquired != 2 { test.result = -C.EIO }
			}
		} else {
			if test.operation == .interrupt {
				if test.use_context {
					test.lock_result = C.ww_mutex_lock_interruptible(&test.locks[0], &ctx)
				} else {
					test.lock_result = C.ww_mutex_lock_interruptible(&test.locks[0], nil)
				}
			} else if test.use_context {
				test.lock_result = C.ww_mutex_lock(&test.locks[0], &ctx)
			} else {
				test.lock_result = C.ww_mutex_lock(&test.locks[0], nil)
			}
			expected_context := if test.use_context { usize(&ctx) } else { usize(0) }
			if test.lock_result == 0 { held[0] = true }
			if test.operation == .interrupt {
				C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, 0)
				if test.lock_result != -C.EINTR || (test.use_context && ctx.acquired != 0) {
					test.result = -C.EIO
				}
			} else if test.lock_result != 0 || (test.use_context && ctx.acquired != 1)
				|| usize(C.READ_ONCE(test.locks[0].ctx)) != expected_context {
				test.result = -C.EIO
			}
		}
		for i in 0 .. 3 { if held[i] { C.ww_mutex_unlock(&test.locks[i]) } }
		if test.use_context {
			if ctx.acquired != 0 { test.result = -C.EIO }
			C.ww_acquire_fini(&ctx)
		}
		if !C.task_is_running(C.current) || !C.vinix_linuxkpi_may_sleep() { test.result = -C.EIO }
		C.complete(&test.done)
		C.pthread_exit(nil)
		return nil
	}
}

fn init_test(test &NativeWwTest, wait_die bool, operation Operation, use_context bool) {
	unsafe {
		*test = NativeWwTest{ operation: operation, use_context: use_context }
		test.class = C.ww_class{ acquire_name: c'native_ww_test_acquire', mutex_name: c'native_ww_test_mutex', is_wait_die: u32(wait_die) }
		for i in 0 .. 3 { C.ww_mutex_init(&test.locks[i], &test.class) }
		C.init_completion(&test.entered)
		C.init_completion(&test.go)
		C.init_completion(&test.backed_off)
		C.init_completion(&test.done)
		test.parent = C.get_task_struct(C.current)
	}
}

fn start(test &NativeWwTest) i32 {
	unsafe {
		if C.pthread_create(&test.worker_id, nil, C.vinix_linuxkpi_fixture_ww_worker, test) != 0 {
			return -C.ENOMEM
		}
		test.started = true
		return if C.wait_for_completion_timeout(&test.entered, 500) != 0 { i32(0) } else { -C.EIO }
	}
}

fn finish(test &NativeWwTest) i32 {
	unsafe {
		mut result := i32(0)
		if test.started {
			C.complete_all(&test.go)
			C.BUG_ON(C.pthread_join(test.worker_id, nil) != 0)
			result = test.result
			for C.__atomic_load_n(&test.task.__state, 2) != C.TASK_DEAD { C.cond_resched() }
			C.put_task_struct(test.task)
		}
		C.put_task_struct(test.parent)
		for i in 0 .. 3 {
			if C.ww_mutex_is_locked(&test.locks[i]) || C.READ_ONCE(test.locks[i].ctx) != nil
				|| !C.list_empty(&test.locks[i].base.wait_list) {
				result = -C.EIO
			}
			C.ww_mutex_destroy(&test.locks[i])
		}
		return result
	}
}

fn inversion_body(test &NativeWwTest, ctx &C.ww_acquire_ctx, held &bool, wait_die bool, stamp usize) i32 {
	unsafe {
		mut result := i32(0)
		if C.ww_mutex_lock(&test.locks[0], ctx) != 0 { return -C.EIO }
		held[0] = true
		if !wait_die {
			if C.ww_mutex_lock(&test.locks[2], ctx) != 0 { return -C.EIO }
			held[2] = true
		}
		if start(test) != 0 { return -C.EIO }
		if isize(test.stamp - stamp) <= 0 { result = -C.EIO }
		C.complete(&test.go)
		if !wait_die && parked(test.task, C.TASK_UNINTERRUPTIBLE) != 0 { result = -C.EIO }
		if C.ww_mutex_lock(&test.locks[1], ctx) != 0 { return -C.EIO }
		held[1] = true
		if C.wait_for_completion_timeout(&test.backed_off, 500) == 0 || test.lock_result != -C.EDEADLK
			|| ctx.stamp != stamp || ctx.acquired != (if wait_die { u32(2) } else { u32(3) }) {
			result = -C.EIO
		}
		C.ww_acquire_done(ctx)
		return result
	}
}

fn inversion(wait_die bool, wrap bool) i32 {
	unsafe {
		mut test := NativeWwTest{}
		mut ctx := C.ww_acquire_ctx{}
		mut held := [false, false, false]!
		init_test(&test, wait_die, if wait_die { Operation.inversion } else { Operation.wounded }, true)
		if wrap { C.atomic_long_set(&test.class.stamp, -2) }
		C.ww_acquire_init(&ctx, &test.class)
		mut result := inversion_body(&test, &ctx, &held[0], wait_die, ctx.stamp)
		if held[1] { C.ww_mutex_unlock(&test.locks[1]) }
		if held[0] { C.ww_mutex_unlock(&test.locks[0]) }
		if held[2] { C.ww_mutex_unlock(&test.locks[2]) }
		if ctx.acquired != 0 { result = -C.EIO }
		C.ww_acquire_fini(&ctx)
		if finish(&test) != 0 { result = -C.EIO }
		return result
	}
}

fn first_body(test &NativeWwTest, ctx &C.ww_acquire_ctx, held &bool, wait_die bool) i32 {
	unsafe {
		mut result := i32(0)
		if wait_die { C.ww_acquire_init(ctx, &test.class) }
		if start(test) != 0 {
			if !wait_die { C.ww_acquire_init(ctx, &test.class) }
			return -C.EIO
		}
		if !wait_die { C.ww_acquire_init(ctx, &test.class) }
		age := isize(test.stamp - ctx.stamp)
		age_bad := if wait_die { age <= 0 } else { age >= 0 }
		if age_bad { result = -C.EIO }
		if C.ww_mutex_lock(&test.locks[0], ctx) != 0 { return -C.EIO }
		*held = true
		C.complete(&test.go)
		if parked(test.task, C.TASK_UNINTERRUPTIBLE) != 0 || C.completion_done(&test.done)
			|| C.ww_load_short(&ctx.wounded, 2) != 0 {
			result = -C.EIO
		}
		return result
	}
}

fn first(wait_die bool) i32 {
	unsafe {
		mut test := NativeWwTest{}
		mut ctx := C.ww_acquire_ctx{}
		mut held := false
		init_test(&test, wait_die, .first, true)
		mut result := first_body(&test, &ctx, &held, wait_die)
		if held { C.ww_mutex_unlock(&test.locks[0]) }
		if ctx.acquired != 0 { result = -C.EIO }
		C.ww_acquire_fini(&ctx)
		if finish(&test) != 0 { result = -C.EIO }
		return result
	}
}

fn single_body(test &NativeWwTest, held &bool, interruptible bool) i32 {
	unsafe {
		mut result := i32(0)
		if C.ww_mutex_lock(&test.locks[0], nil) != 0 { return -C.EIO }
		*held = true
		if start(test) != 0 { return -C.EIO }
		C.complete(&test.go)
		state := if interruptible { C.TASK_INTERRUPTIBLE } else { C.TASK_UNINTERRUPTIBLE }
		if parked(test.task, state) != 0 || C.completion_done(&test.done) { result = -C.EIO }
		if interruptible {
			C.vinix_linuxkpi_test_task_signal(test.task.vinix_thread, u64(1) << 14)
			if C.wait_for_completion_timeout(&test.done, 500) == 0 || test.lock_result != -C.EINTR {
				result = -C.EIO
			}
			mut flags := usize(0)
			C.raw_spin_lock_irqsave(&test.locks[0].base.wait_lock, flags)
			if !C.list_empty(&test.locks[0].base.wait_list) || C.atomic_long_read(&test.locks[0].base.owner) != isize(usize(C.current)) {
				result = -C.EIO
			}
			C.raw_spin_unlock_irqrestore(&test.locks[0].base.wait_lock, flags)
		}
		return result
	}
}

fn single(interruptible bool, use_context bool) i32 {
	unsafe {
		mut test := NativeWwTest{}
		mut held := false
		init_test(&test, true, if interruptible {
			Operation.interrupt
		} else {
			Operation.context_free
		}, use_context)
		mut result := single_body(&test, &held, interruptible)
		if held { C.ww_mutex_unlock(&test.locks[0]) }
		if finish(&test) != 0 { result = -C.EIO }
		return result
	}
}

fn repeated() i32 {
	unsafe {
		mut class := C.ww_class{ acquire_name: c'native_ww_repeated_acquire', mutex_name: c'native_ww_repeated_mutex', is_wait_die: 1 }
		mut a := C.ww_mutex{}
		mut b := C.ww_mutex{}
		mut result := i32(0)
		C.ww_mutex_init(&a, &class)
		C.ww_mutex_init(&b, &class)
		for _ in 0 .. 256 {
			mut ctx := C.ww_acquire_ctx{}
			C.ww_acquire_init(&ctx, &class)
			if C.ww_mutex_lock(&a, &ctx) != 0 {
				result = -C.EIO
				C.ww_acquire_fini(&ctx)
				break
			}
			if ctx.acquired != 1 || C.ww_mutex_lock(&a, &ctx) != -C.EALREADY || C.ww_mutex_trylock(&a, &ctx) || ctx.acquired != 1 {
				result = -C.EIO
			}
			if !C.ww_mutex_trylock(&b, &ctx) {
				result = -C.EIO
			} else {
				if ctx.acquired != 2 || usize(a.ctx) != usize(&ctx) || usize(b.ctx) != usize(&ctx) {
					result = -C.EIO
				}
				C.ww_acquire_done(&ctx)
				C.ww_mutex_unlock(&b)
			}
			C.ww_mutex_unlock(&a)
			if ctx.acquired != 0 { result = -C.EIO }
			C.ww_acquire_fini(&ctx)
			if C.ww_mutex_lock(&a, nil) != 0 {
				result = -C.EIO
			} else {
				if a.ctx != nil || C.ww_mutex_trylock(&a, nil) { result = -C.EIO }
				C.ww_mutex_unlock(&a)
			}
			if !C.vinix_linuxkpi_may_sleep() { result = -C.EIO }
		}
		C.ww_mutex_destroy(&a)
		C.ww_mutex_destroy(&b)
		return result
	}
}

@[export: 'vinix_linuxkpi_ww_mutex_native_selftest']
pub fn selftest() i32 {
	mut result := i32(0)
	if repeated() != 0 {
		C.kprintf(c'linuxkpi: WW repeated/context counts failed\n')
		result = -C.EIO
	}
	if inversion(true, false) != 0 {
		C.kprintf(c'linuxkpi: Wait-Die inversion failed\n')
		result = -C.EIO
	}
	if inversion(true, true) != 0 {
		C.kprintf(c'linuxkpi: Wait-Die wrapped stamp failed\n')
		result = -C.EIO
	}
	if inversion(false, false) != 0 {
		C.kprintf(c'linuxkpi: Wound-Wait cross-lock wake failed\n')
		result = -C.EIO
	}
	if first(true) != 0 {
		C.kprintf(c'linuxkpi: Wait-Die first-lock exemption failed\n')
		result = -C.EIO
	}
	if first(false) != 0 {
		C.kprintf(c'linuxkpi: Wound-Wait first-lock exemption failed\n')
		result = -C.EIO
	}
	if single(true, true) != 0 {
		C.kprintf(c'linuxkpi: WW context signal abort failed\n')
		result = -C.EIO
	}
	if single(true, false) != 0 {
		C.kprintf(c'linuxkpi: WW context-free signal abort failed\n')
		result = -C.EIO
	}
	if single(false, false) != 0 {
		C.kprintf(c'linuxkpi: WW context-free handoff failed\n')
		result = -C.EIO
	}
	return result
}
