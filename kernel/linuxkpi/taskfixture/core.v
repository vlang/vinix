// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native task fixture, retaining the original seventy-worker test.
@[translated]
module taskfixture

#include "linuxkpi_task_fixture_v_contract.h"

struct C.task_struct {
	__state      u32
	flags        u32
	vinix_thread voidptr
}

@[typedef]
struct C.pthread_t {}

type TaskWorker = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_task_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, TaskWorker, voidptr) i32
fn C.pthread_detach(C.pthread_t) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.task_is_running(&C.task_struct) bool
fn C.vtime_account_guest_enter()
fn C.set_current_state(u32)
fn C.schedule()
fn C.cond_resched() i32
fn C.wake_up_state(&C.task_struct, u32) i32
fn C.wake_up_process(&C.task_struct) i32
fn C.vinix_linuxkpi_task_queued(voidptr) bool
fn C.vinix_linuxkpi_task_is_dead(voidptr) bool
fn C.vinix_linuxkpi_test_task_signal(voidptr, u64)
fn C.__atomic_fetch_or(&u32, u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.__atomic_load_n(&u32, i32) u32
fn C.BUG_ON(bool)

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.PF_VCPU u32

@[c_extern]
__global C.PF_EXITING u32

@[c_extern]
__global C.TASK_RUNNING u32

@[c_extern]
__global C.TASK_UNINTERRUPTIBLE u32

@[c_extern]
__global C.TASK_INTERRUPTIBLE u32

@[c_extern]
__global C.TASK_DEAD u32

@[c_extern]
__global C.EIO i32

struct NativeWaitTest {
mut:
	task   &C.task_struct = unsafe { nil }
	phase  u32
	early  bool
	result i32
}

@[export: 'vinix_linuxkpi_fixture_task_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut test := &NativeWaitTest(argument)
		task := C.get_task_struct(C.current)
		task_test_flags := C.PF_VCPU | u32(0x40000000)
		C.__atomic_fetch_or(&task.flags, task_test_flags & ~C.PF_VCPU, 0)
		C.vtime_account_guest_enter()
		test.task = task
		C.set_current_state(C.TASK_UNINTERRUPTIBLE)
		C.__atomic_store_n(&test.phase, 1, 3)
		if test.early {
			for C.__atomic_load_n(&test.phase, 2) < 2 { C.cond_resched() }
		}
		C.schedule()
		test.result = if C.task_is_running(task) && usize(C.current) == usize(task)
			&& (C.__atomic_load_n(&task.flags, 0) & task_test_flags) == task_test_flags {
			i32(0)
		} else {
			-C.EIO
		}
		C.__atomic_store_n(&test.phase, 3, 3)
		C.pthread_exit(voidptr(usize(0x1234)))
		return nil
	}
}

@[export: 'vinix_linuxkpi_task_native_selftest']
pub fn selftest() i32 {
	unsafe {
		mut held := [70]&C.task_struct{}
		mut result := i32(0)
		for i in 0 .. 70 {
			mut test := NativeWaitTest{ early: (i & 1) != 0 }
			mut worker_id := C.pthread_t{}
			C.BUG_ON(C.pthread_create(&worker_id, nil, C.vinix_linuxkpi_fixture_task_worker, &test) != 0)
			for C.__atomic_load_n(&test.phase, 2) < 1 { C.cond_resched() }
			held[i] = test.task
			if C.wake_up_state(held[i], C.TASK_INTERRUPTIBLE) != 0 { result = -C.EIO }
			if !test.early {
				for C.vinix_linuxkpi_task_queued(held[i].vinix_thread) { C.cond_resched() }
				C.vinix_linuxkpi_test_task_signal(held[i].vinix_thread, u64(1) << 14)
				for C.vinix_linuxkpi_task_queued(held[i].vinix_thread) { C.cond_resched() }
				if C.__atomic_load_n(&held[i].__state, 0) != C.TASK_UNINTERRUPTIBLE {
					result = -C.EIO
				}
				C.vinix_linuxkpi_test_task_signal(held[i].vinix_thread, 0)
			}
			if C.wake_up_process(held[i]) != 1 { result = -C.EIO }
			if test.early { C.__atomic_store_n(&test.phase, 2, 3) }
			if i % 3 == 0 {
				C.BUG_ON(C.pthread_detach(worker_id) != 0)
				for C.__atomic_load_n(&test.phase, 2) < 3 { C.cond_resched() }
			} else {
				mut value := voidptr(nil)
				C.BUG_ON(C.pthread_join(worker_id, &value) != 0)
				if usize(value) != usize(0x1234) { result = -C.EIO }
			}
			if test.result != 0 { result = -C.EIO }
			for !C.vinix_linuxkpi_task_is_dead(held[i].vinix_thread) { C.cond_resched() }
			if C.wake_up_process(held[i]) != 0 { result = -C.EIO }
		}
		task_test_flags := C.PF_VCPU | u32(0x40000000)
		for i in 0 .. 70 {
			for C.__atomic_load_n(&held[i].__state, 2) != C.TASK_DEAD { C.cond_resched() }
			expected := task_test_flags | C.PF_EXITING
			if (C.__atomic_load_n(&held[i].flags, 0) & expected) != expected { result = -C.EIO }
			if usize(C.get_task_struct(held[i])) != usize(held[i]) { result = -C.EIO }
			C.put_task_struct(held[i])
			C.put_task_struct(held[i])
		}
		return result
	}
}
