// SPDX-License-Identifier: GPL-2.0-or-later
// The native Thread owns this view and its lifetime; no task allocations.
@[translated]
module compatcore

#include "linuxkpi_task_v_primitives.h"

struct C.vkt_task_view {
mut:
	vinix_thread voidptr
	pid i32
	tgid i32
	flags u32
	state u32
	wait_lock u32
	comm [16]char
	initial_comm [16]char
	in_iowait u32
}
fn C.vinix_linuxkpi_task_dequeue(voidptr)
fn C.vinix_linuxkpi_task_enqueue(voidptr) bool
fn C.vinix_linuxkpi_task_is_dead(voidptr) bool
fn C.vinix_linuxkpi_task_park()
fn C.vinix_linuxkpi_task_signal_pending(voidptr, bool) bool
fn C.vinix_linuxkpi_iowait_block(voidptr)
fn C.vinix_linuxkpi_cond_resched() i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_irq_save() u64
fn C.vinix_linuxkpi_irq_flags() u64
fn C.vinix_linuxkpi_irq_restore(u64)
fn C.vinix_linuxkpi_spin_wait()
fn C.vkt_guest_enter()
fn C.vkt_guest_exit()
@[c: '__atomic_fetch_or']
fn C.vkt_or32(&u32, u32, i32) u32
@[c: '__atomic_fetch_and']
fn C.vkt_and32(&u32, u32, i32) u32
@[c: '__atomic_thread_fence']
fn C.vkt_fence(i32)

fn vkt_copy_comm(destination &char, name &char, length usize) {
	unsafe {
		count := if length < 15 { length } else { usize(15) }
		if count != 0 { C.memcpy(destination, name, count) }
		C.memset(destination + count, 0, 16 - count)
	}
}

@[export: 'vinix_linuxkpi_task_init']
pub fn task_init(storage voidptr, thread voidptr, pid i32, tgid i32, name &char, length usize) {
	unsafe {
		require(!is_null(storage) && !is_null(thread))
		mut task := &C.vkt_task_view(storage)
		task.vinix_thread = thread
		task.pid = pid
		task.tgid = tgid
		task.flags = 0
		task.state = 0
		task.in_iowait = 0
		C.vkp_spin_init(&task.wait_lock)
		vkt_copy_comm(&task.initial_comm[0], name, length)
		C.memcpy(&task.comm[0], &task.initial_comm[0], 16)
	}
}

@[export: 'vinix_linuxkpi_task_inherit']
pub fn task_inherit(storage voidptr, thread voidptr, pid i32, tgid i32, source voidptr) {
	unsafe { parent := &C.vkt_task_view(source)
		task_init(storage, thread, pid, tgid, &parent.comm[0], 16) }
}

@[export: 'vinix_linuxkpi_task_view']
pub fn task_view(storage voidptr, thread voidptr, pid i32, tgid i32, name &char, length usize, exiting bool) voidptr {
	unsafe {
		require(!is_null(storage) && !is_null(thread))
		mut task := &C.vkt_task_view(storage)
		require(task.vinix_thread == thread && task.pid == pid && task.tgid == tgid)
		if exiting { C.vkt_or32(&task.flags, 4, 0) }
		if length != 0 { vkt_copy_comm(&task.comm[0], name, length) }
		else { C.memcpy(&task.comm[0], &task.initial_comm[0], 16) }
		return storage
	}
}

@[export: 'vinix_linuxkpi_task_dead']
pub fn task_dead(storage voidptr) {
	unsafe {
		mut task := &C.vkt_task_view(storage)
		flags := C.vkp_spin_lock_irqsave(&task.wait_lock)
		C.vkt_or32(&task.flags, 4, 0)
		C.vkp_store32(&task.state, 128, 3)
		C.vkp_spin_unlock_irqrestore(&task.wait_lock, flags)
	}
}

@[export: 'vinix_linuxkpi_set_task_state']
pub fn set_task_state(state u32) {
	unsafe {
		require(state == 0 || state == 1 || state == 2 || state == 258 || state == 1026)
		mut task := &C.vkt_task_view(C.vkp_current())
		C.vkp_store32(&task.state, state, 5)
	}
}

fn vkt_signal_pending(state u32, task &C.vkt_task_view) bool {
	if (state & 257) == 0 { return false }
	return C.vinix_linuxkpi_task_signal_pending(task.vinix_thread, (state & 1) == 0)
}

@[export: 'schedule']
pub fn task_schedule() {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		mut task := &C.vkt_task_view(C.vkp_current())
		mut first := true
		for {
			flags := C.vkp_spin_lock_irqsave(&task.wait_lock)
			state := C.vkp_load32(&task.state, 0)
			require(state != 128)
			if state == 0 {
				C.vkp_spin_unlock_irqrestore(&task.wait_lock, flags)
				if first { C.vinix_linuxkpi_cond_resched() }
				return
			}
			C.vinix_linuxkpi_task_dequeue(task.vinix_thread)
			if vkt_signal_pending(state, task) {
				require(C.vinix_linuxkpi_task_enqueue(task.vinix_thread))
				C.vkp_store32(&task.state, 0, 0)
				C.vkp_spin_unlock_irqrestore(&task.wait_lock, flags)
				return
			}
			if task_in_iowait(task) { C.vinix_linuxkpi_iowait_block(task.vinix_thread) }
			C.vkp_spin_unlock_irqrestore(&task.wait_lock, flags)
			C.vinix_linuxkpi_task_park()
			first = false
		}
	}
}

@[export: 'wake_up_state']
pub fn task_wake_state(storage voidptr, state u32) i32 {
	unsafe {
		mut task := &C.vkt_task_view(storage)
		flags := C.vkp_spin_lock_irqsave(&task.wait_lock)
		C.vkt_fence(5)
		previous := C.vkp_load32(&task.state, 0)
		mut woke := i32(0)
		if (previous & state) != 0 && (previous & 3) != 0 && !C.vinix_linuxkpi_task_is_dead(task.vinix_thread) {
			C.vkp_store32(&task.state, 0, 0)
			if C.vinix_linuxkpi_task_enqueue(task.vinix_thread) { woke = 1 }
			else {
				require(C.vinix_linuxkpi_task_is_dead(task.vinix_thread))
				C.vkt_or32(&task.flags, 4, 0)
				C.vkp_store32(&task.state, 128, 3)
			}
		}
		C.vkp_spin_unlock_irqrestore(&task.wait_lock, flags)
		return woke
	}
}

@[export: 'wake_up_process']
pub fn task_wake_process(storage voidptr) i32 { return task_wake_state(storage, 3) }

@[export: 'vinix_linuxkpi_task_selftest']
pub fn task_selftest() i32 {
	unsafe {
		mut task := &C.vkt_task_view(C.vkp_current())
		pid := task.pid
		tgid := task.tgid
		if task.comm[0] == 0 || strnlen(&task.comm[0], 16) == 16 { return -5 }
		original_flags := C.vkt_or32(&task.flags, 0x40000000, 0)
		C.vkt_guest_enter()
		C.vinix_linuxkpi_preempt_disable()
		cpu := C.vinix_linuxkpi_cpu_id()
		mut result := i32(0)
		if C.vinix_linuxkpi_cpu_id() != cpu || C.vinix_linuxkpi_cpu_id() != cpu || C.vinix_linuxkpi_cond_resched() != 0 { result = -5 }
		C.vinix_linuxkpi_preempt_enable()
		flags := C.vinix_linuxkpi_irq_save()
		if C.vinix_linuxkpi_cond_resched() != 0 { result = -5 }
		C.vinix_linuxkpi_irq_restore(flags)
		if C.vinix_linuxkpi_cond_resched() != 1 || C.vkp_current() != voidptr(task) || task.pid != pid || task.tgid != tgid { result = -5 }
		if (C.vkp_load32(&task.flags, 0) & 0x40000001) != 0x40000001 { result = -5 }
		C.vkt_guest_exit()
		if (C.vkp_load32(&task.flags, 0) & 0x40000001) != 0x40000000 { result = -5 }
		if (original_flags & 1) != 0 { C.vkt_guest_enter() }
		C.vkt_and32(&task.flags, ~(u32(0x40000001) & ~original_flags), 0)
		return result
	}
}
