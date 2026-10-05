// SPDX-License-Identifier: GPL-2.0-only
// Wait queues adapted from Linux kernel/sched/wait.c:
// (C) 2004 Nadia Yvette Chambers, Oracle. Native direct handoff and stack
// lifetime serialization preserve the original LinuxKPI backend contracts.
@[translated]
module compatcore

#include "linuxkpi_wait_v_primitives.h"

struct C.vkw_swait_head {
mut:
	lock u32
	task_list C.vkw_list
}
struct C.vkw_swait {
mut:
	task voidptr
	task_list C.vkw_list
}
struct C.vkw_completion {
mut:
	done u32
	@wait C.vkw_swait_head
}
struct MutexWaiter {
mut:
	entry C.vkw_list
	task voidptr
}
type WaitWakeFn = fn (voidptr, u32, i32, voidptr) i32

fn C.vkw_wake_state(voidptr, u32) i32
fn C.vkw_irqs_disabled() bool
fn C.vkw_spin_lock_irq(voidptr)
fn C.vkw_spin_unlock_irq(voidptr)
fn C.vkw_atomic_add_unless(voidptr, i32, i32) bool
fn C.vkw_atomic_dec_and_test(voidptr) bool
fn C.vkw_autoremove_callback() voidptr

fn sync_list_add(node &C.vkw_list, prev &C.vkw_list, next &C.vkw_list) {
	unsafe {
		next.prev = node
		node.next = next
		node.prev = prev
		C.vkw_store_pointer(&voidptr(&prev.next), node, 0)
	}
}
fn sync_list_remove(node &C.vkw_list) {
	unsafe {
		node.next.prev = node.prev
		C.vkw_store_pointer(&voidptr(&node.prev.next), node.next, 0)
	}
}
fn sync_list_splice_init(source &C.vkw_list, destination &C.vkw_list) {
	unsafe {
		if ww_list_empty(source) { return }
		first := source.next
		last := source.prev
		first.prev = destination
		destination.next = first
		last.next = destination
		destination.prev = last
		wait_list_init(source)
	}
}
fn sync_wait_at(entry &C.vkw_list) &C.vkw_wait_entry {
	unsafe { return &C.vkw_wait_entry(usize(entry) - __offsetof(C.vkw_wait_entry, entry)) }
}
fn sync_mutex_waiter(entry &C.vkw_list) &MutexWaiter {
	unsafe { return &MutexWaiter(usize(entry) - __offsetof(MutexWaiter, entry)) }
}
fn sync_swait_at(entry &C.vkw_list) &C.vkw_swait {
	unsafe { return &C.vkw_swait(usize(entry) - __offsetof(C.vkw_swait, task_list)) }
}

@[export: '__mutex_init']
pub fn mutex_init(storage voidptr, name &char, key voidptr) {
	unsafe {
		mutex := &C.vkw_mutex(storage)
		C.vkw_store_owner(&mutex.owner, 0, 0)
		C.vkp_spin_init(&mutex.wait_lock)
		wait_list_init(&mutex.wait_list)
	}
}
@[export: 'mutex_is_locked']
pub fn mutex_is_locked(storage voidptr) bool {
	unsafe { return C.vkw_load_owner(&(&C.vkw_mutex(storage)).owner, 0) != 0 }
}
@[export: 'mutex_destroy']
pub fn mutex_destroy(storage voidptr) {
	unsafe {
		mutex := &C.vkw_mutex(storage)
		flags := C.vkp_spin_lock_irqsave(&mutex.wait_lock)
		require(!mutex_is_locked(mutex) && ww_list_empty(&mutex.wait_list))
		C.vkp_spin_unlock_irqrestore(&mutex.wait_lock, flags)
	}
}
fn mutex_acquire(mutex &C.vkw_mutex, state u32) i32 {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		task := C.vkp_current()
		mut wait := MutexWaiter{}
		wait.task = task
		mut flags := C.vkp_spin_lock_irqsave(&mutex.wait_lock)
		owner := C.vkw_load_owner(&mutex.owner, 0)
		require(owner != i64(task))
		if owner == 0 {
			require(ww_list_empty(&mutex.wait_list))
			C.vkw_store_owner(&mutex.owner, i64(task), 0)
			C.vkp_spin_unlock_irqrestore(&mutex.wait_lock, flags)
			return 0
		}
		ww_list_add_tail(&wait.entry, &mutex.wait_list)
		for {
			if C.vkw_load_owner(&mutex.owner, 0) == i64(task) {
				require(ww_list_empty(&wait.entry))
				C.vkw_current_state(0)
				C.vkp_spin_unlock_irqrestore(&mutex.wait_lock, flags)
				return 0
			}
			if C.vkw_signal_state(state, task) {
				ww_list_del_init(&wait.entry)
				C.vkw_current_state(0)
				C.vkp_spin_unlock_irqrestore(&mutex.wait_lock, flags)
				return -4
			}
			C.vkw_current_state(state)
			C.vkp_spin_unlock_irqrestore(&mutex.wait_lock, flags)
			C.vkp_schedule()
			flags = C.vkp_spin_lock_irqsave(&mutex.wait_lock)
		}
	}
	return 0
}
@[export: 'mutex_lock']
pub fn mutex_lock(storage voidptr) { unsafe { mutex_acquire(&C.vkw_mutex(storage), 2) } }
@[export: 'mutex_lock_io']
pub fn mutex_lock_io(storage voidptr) {
	token := io_schedule_prepare()
	mutex_lock(storage)
	io_schedule_finish(token)
}
@[export: 'mutex_lock_interruptible']
pub fn mutex_lock_interruptible(storage voidptr) i32 { unsafe { return mutex_acquire(&C.vkw_mutex(storage), 1) } }
@[export: 'mutex_lock_killable']
pub fn mutex_lock_killable(storage voidptr) i32 { unsafe { return mutex_acquire(&C.vkw_mutex(storage), 0x102) } }
@[export: 'mutex_trylock']
pub fn mutex_trylock(storage voidptr) i32 {
	unsafe {
		mutex := &C.vkw_mutex(storage)
		flags := C.vkp_spin_lock_irqsave(&mutex.wait_lock)
		acquired := C.vkw_load_owner(&mutex.owner, 0) == 0
		if acquired {
			require(ww_list_empty(&mutex.wait_list))
			C.vkw_store_owner(&mutex.owner, i64(C.vkp_current()), 0)
		}
		C.vkp_spin_unlock_irqrestore(&mutex.wait_lock, flags)
		return if acquired { 1 } else { 0 }
	}
}
@[export: 'mutex_unlock']
pub fn mutex_unlock(storage voidptr) {
	unsafe {
		mutex := &C.vkw_mutex(storage)
		flags := C.vkp_spin_lock_irqsave(&mutex.wait_lock)
		require(C.vkw_load_owner(&mutex.owner, 0) == i64(C.vkp_current()))
		if ww_list_empty(&mutex.wait_list) { C.vkw_store_owner(&mutex.owner, 0, 3) }
		else {
			wait := sync_mutex_waiter(mutex.wait_list.next)
			next := wait.task
			ww_list_del_init(&wait.entry)
			C.vkw_store_owner(&mutex.owner, i64(next), 3)
			C.vkw_wake_task(next)
		}
		C.vkp_spin_unlock_irqrestore(&mutex.wait_lock, flags)
	}
}
@[export: 'atomic_dec_and_mutex_lock']
pub fn atomic_dec_and_mutex_lock(count voidptr, storage voidptr) i32 {
	if C.vkw_atomic_add_unless(count, -1, 1) { return 0 }
	mutex_lock(storage)
	if C.vkw_atomic_dec_and_test(count) { return 1 }
	mutex_unlock(storage)
	return 0
}

@[export: '__init_waitqueue_head']
pub fn init_waitqueue_head(storage voidptr, name &char, key voidptr) {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		C.vkp_spin_init(&head.lock)
		wait_list_init(&head.head)
	}
}
fn sync_add_wait_queue(head &C.vkw_wait_queue, wait &C.vkw_wait_entry) {
	unsafe {
		mut position := &head.head
		for entry := head.head.next; entry != &head.head; entry = entry.next {
			if (sync_wait_at(entry).flags & 0x20) == 0 { break }
			position = entry
		}
		sync_list_add(&wait.entry, position, position.next)
	}
}
@[export: 'add_wait_queue']
pub fn add_wait_queue(storage voidptr, waiter voidptr) {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		wait.flags &= ~u32(1)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		sync_add_wait_queue(head, wait)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}
@[export: 'add_wait_queue_exclusive']
pub fn add_wait_queue_exclusive(storage voidptr, waiter voidptr) {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		wait.flags |= 1
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		ww_list_add_tail(&wait.entry, &head.head)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}
@[export: 'add_wait_queue_priority']
pub fn add_wait_queue_priority(storage voidptr, waiter voidptr) {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		wait.flags |= 0x21
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		sync_add_wait_queue(head, wait)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}
@[export: 'remove_wait_queue']
pub fn remove_wait_queue(storage voidptr, waiter voidptr) {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		ww_list_del_init(&wait.entry)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}
fn wake_queue_locked(head &C.vkw_wait_queue, mode u32, quota i32, key voidptr) i32 {
	unsafe {
		mut remaining := quota
		mut entry := head.head.next
		for entry != &head.head {
			wait := sync_wait_at(entry)
			entry = entry.next // The callback can remove its current entry.
			flags := wait.flags
			if (flags & 4) != 0 { continue }
			callback := WaitWakeFn(wait.func)
			result := callback(wait, mode, 0, key)
			if result < 0 { break }
			if result != 0 && (flags & 1) != 0 {
				remaining--
				if remaining == 0 { break }
			}
		}
		return quota - remaining
	}
}
@[export: '__wake_up']
pub fn wake_up(storage voidptr, mode u32, quota i32, key voidptr) i32 {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		result := wake_queue_locked(head, mode, quota, key)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
		return result
	}
}
@[export: '__wake_up_locked']
pub fn wake_up_locked(storage voidptr, mode u32, quota i32) {
	unsafe { wake_queue_locked(&C.vkw_wait_queue(storage), mode, quota, nil) }
}
@[export: '__wake_up_locked_key']
pub fn wake_up_locked_key(storage voidptr, mode u32, key voidptr) {
	unsafe { wake_queue_locked(&C.vkw_wait_queue(storage), mode, 1, key) }
}
@[export: 'default_wake_function']
pub fn default_wake_function(storage voidptr, mode u32, flags i32, key voidptr) i32 {
	unsafe {
		require(flags == 0)
		return C.vkw_wake_state((&C.vkw_wait_entry(storage)).@private, mode)
	}
}
@[export: 'autoremove_wake_function']
pub fn autoremove_wake_function(storage voidptr, mode u32, flags i32, key voidptr) i32 {
	unsafe {
		result := default_wake_function(storage, mode, flags, key)
		if result != 0 {
			entry := &(&C.vkw_wait_entry(storage)).entry
			sync_list_remove(entry)
			C.vkw_store_pointer(&voidptr(&entry.prev), entry, 0)
			C.vkw_store_pointer(&voidptr(&entry.next), entry, 3)
		}
		return result
	}
}
@[export: 'init_wait_entry']
pub fn init_wait_entry(storage voidptr, flags i32) {
	unsafe {
		wait := &C.vkw_wait_entry(storage)
		wait.flags = u32(flags)
		wait.@private = C.vkp_current()
		wait.func = C.vkw_autoremove_callback()
		wait_list_init(&wait.entry)
	}
}
@[export: 'prepare_to_wait']
pub fn prepare_to_wait(storage voidptr, waiter voidptr, state i32) {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		wait.flags &= ~u32(1)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		if ww_list_empty(&wait.entry) { sync_add_wait_queue(head, wait) }
		C.vkw_current_state(u32(state))
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}
@[export: 'prepare_to_wait_exclusive']
pub fn prepare_to_wait_exclusive(storage voidptr, waiter voidptr, state i32) bool {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		mut first := false
		wait.flags |= 1
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		if ww_list_empty(&wait.entry) {
			first = ww_list_empty(&head.head)
			ww_list_add_tail(&wait.entry, &head.head)
		}
		C.vkw_current_state(u32(state))
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
		return first
	}
}
@[export: 'prepare_to_wait_event']
pub fn prepare_to_wait_event(storage voidptr, waiter voidptr, state i32) i64 {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		mut result := i64(0)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		if C.vkw_signal_state(u32(state), C.vkp_current()) {
			ww_list_del_init(&wait.entry)
			C.vkw_current_state(0)
			result = -512
		} else {
			if ww_list_empty(&wait.entry) {
				if (wait.flags & 1) != 0 { ww_list_add_tail(&wait.entry, &head.head) }
				else { sync_add_wait_queue(head, wait) }
			}
			C.vkw_current_state(u32(state))
		}
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
		return result
	}
}
@[export: 'finish_wait']
pub fn finish_wait(storage voidptr, waiter voidptr) {
	unsafe {
		head := &C.vkw_wait_queue(storage)
		wait := &C.vkw_wait_entry(waiter)
		C.vkw_current_state(0)
		// Even autoremove must finish its locked producer callback first.
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		ww_list_del_init(&wait.entry)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}

@[export: '__init_swait_queue_head']
pub fn init_swait_queue_head(storage voidptr, name &char, key voidptr) {
	unsafe {
		head := &C.vkw_swait_head(storage)
		C.vkp_spin_init(&head.lock)
		wait_list_init(&head.task_list)
	}
}
@[export: 'swake_up_locked']
pub fn swake_up_locked(storage voidptr, flags i32) {
	unsafe {
		require(flags == 0)
		head := &C.vkw_swait_head(storage)
		if !ww_list_empty(&head.task_list) {
			wait := sync_swait_at(head.task_list.next)
			task := wait.task
			ww_list_del_init(&wait.task_list)
			C.vkw_wake_task(task)
		}
	}
}
@[export: 'swake_up_all_locked']
pub fn swake_up_all_locked(storage voidptr) {
	unsafe {
		head := &C.vkw_swait_head(storage)
		for !ww_list_empty(&head.task_list) { swake_up_locked(head, 0) }
	}
}
@[export: 'swake_up_one']
pub fn swake_up_one(storage voidptr) {
	unsafe {
		head := &C.vkw_swait_head(storage)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		swake_up_locked(head, 0)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}
@[export: 'swake_up_all']
pub fn swake_up_all(storage voidptr) {
	unsafe {
		require(!C.vkw_irqs_disabled())
		head := &C.vkw_swait_head(storage)
		mut pending := C.vkw_list{}
		wait_list_init(&pending)
		C.vkw_spin_lock_irq(&head.lock)
		sync_list_splice_init(&head.task_list, &pending)
		for !ww_list_empty(&pending) {
			wait := sync_swait_at(pending.next)
			task := wait.task
			ww_list_del_init(&wait.task_list)
			C.vkw_wake_task(task)
			// Waiters remove from pending under this same queue lock.
			C.vkw_spin_unlock_irq(&head.lock)
			C.vkw_spin_lock_irq(&head.lock)
		}
		C.vkw_spin_unlock_irq(&head.lock)
	}
}
@[export: '__prepare_to_swait']
pub fn prepare_to_swait(storage voidptr, waiter voidptr) {
	unsafe {
		head := &C.vkw_swait_head(storage)
		wait := &C.vkw_swait(waiter)
		wait.task = C.vkp_current()
		if ww_list_empty(&wait.task_list) { ww_list_add_tail(&wait.task_list, &head.task_list) }
	}
}
@[export: 'prepare_to_swait_exclusive']
pub fn prepare_to_swait_exclusive(storage voidptr, waiter voidptr, state i32) {
	unsafe {
		head := &C.vkw_swait_head(storage)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		prepare_to_swait(head, waiter)
		C.vkw_current_state(u32(state))
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}
@[export: 'prepare_to_swait_event']
pub fn prepare_to_swait_event(storage voidptr, waiter voidptr, state i32) i64 {
	unsafe {
		head := &C.vkw_swait_head(storage)
		wait := &C.vkw_swait(waiter)
		mut result := i64(0)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		if C.vkw_signal_state(u32(state), C.vkp_current()) {
			ww_list_del_init(&wait.task_list)
			C.vkw_current_state(0)
			result = -512
		} else {
			prepare_to_swait(head, wait)
			C.vkw_current_state(u32(state))
		}
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
		return result
	}
}
@[export: '__finish_swait']
pub fn finish_swait_locked(storage voidptr, waiter voidptr) {
	unsafe {
		C.vkw_current_state(0)
		ww_list_del_init(&(&C.vkw_swait(waiter)).task_list)
	}
}
@[export: 'finish_swait']
pub fn finish_swait(storage voidptr, waiter voidptr) {
	unsafe {
		head := &C.vkw_swait_head(storage)
		flags := C.vkp_spin_lock_irqsave(&head.lock)
		finish_swait_locked(head, waiter)
		C.vkp_spin_unlock_irqrestore(&head.lock, flags)
	}
}

@[export: 'complete']
pub fn complete(storage voidptr) {
	unsafe {
		completion := &C.vkw_completion(storage)
		flags := C.vkp_spin_lock_irqsave(&completion.@wait.lock)
		if completion.done != u32(-1) { completion.done++ }
		swake_up_locked(&completion.@wait, 0)
		C.vkp_spin_unlock_irqrestore(&completion.@wait.lock, flags)
	}
}
@[export: 'complete_all']
pub fn complete_all(storage voidptr) {
	unsafe {
		completion := &C.vkw_completion(storage)
		flags := C.vkp_spin_lock_irqsave(&completion.@wait.lock)
		completion.done = u32(-1)
		swake_up_all_locked(&completion.@wait)
		C.vkp_spin_unlock_irqrestore(&completion.@wait.lock, flags)
	}
}
fn completion_wait(completion &C.vkw_completion, duration i64, state u32) i64 {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		require(state == 2 || state == 1 || state == 0x102 || state == 0x402)
		mut wait := C.vkw_swait{}
		wait.task = C.vkp_current()
		wait_list_init(&wait.task_list)
		mut timeout := duration
		mut flags := C.vkp_spin_lock_irqsave(&completion.@wait.lock)
		for completion.done == 0 {
			if C.vkw_signal_state(state, C.vkp_current()) { timeout = -512; break }
			if timeout == 0 { break }
			prepare_to_swait(&completion.@wait, &wait)
			C.vkw_current_state(state)
			C.vkp_spin_unlock_irqrestore(&completion.@wait.lock, flags)
			timeout = C.vkp_schedule_timeout(timeout)
			flags = C.vkp_spin_lock_irqsave(&completion.@wait.lock)
			if timeout == 0 { break }
		}
		finish_swait_locked(&completion.@wait, &wait)
		if completion.done != 0 {
			if completion.done != u32(-1) { completion.done-- }
			if timeout == 0 { timeout = 1 }
		}
		C.vkp_spin_unlock_irqrestore(&completion.@wait.lock, flags)
		return timeout
	}
}
@[export: 'wait_for_completion_state']
pub fn wait_for_completion_state(storage voidptr, state u32) i32 {
	unsafe {
		result := completion_wait(&C.vkw_completion(storage), i64(0x7fffffffffffffff), state)
		return if result == -512 { i32(result) } else { 0 }
	}
}
@[export: 'wait_for_completion']
pub fn wait_for_completion(storage voidptr) { wait_for_completion_state(storage, 2) }
@[export: 'wait_for_completion_interruptible']
pub fn wait_for_completion_interruptible(storage voidptr) i32 { return wait_for_completion_state(storage, 1) }
@[export: 'wait_for_completion_killable']
pub fn wait_for_completion_killable(storage voidptr) i32 { return wait_for_completion_state(storage, 0x102) }
@[export: 'wait_for_completion_timeout']
pub fn wait_for_completion_timeout(storage voidptr, timeout u64) u64 {
	unsafe { return u64(completion_wait(&C.vkw_completion(storage), i64(timeout), 2)) }
}
@[export: 'wait_for_completion_interruptible_timeout']
pub fn wait_for_completion_interruptible_timeout(storage voidptr, timeout u64) i64 {
	unsafe { return completion_wait(&C.vkw_completion(storage), i64(timeout), 1) }
}
@[export: 'wait_for_completion_killable_timeout']
pub fn wait_for_completion_killable_timeout(storage voidptr, timeout u64) i64 {
	unsafe { return completion_wait(&C.vkw_completion(storage), i64(timeout), 0x102) }
}
@[export: 'try_wait_for_completion']
pub fn try_wait_for_completion(storage voidptr) bool {
	unsafe {
		completion := &C.vkw_completion(storage)
		flags := C.vkp_spin_lock_irqsave(&completion.@wait.lock)
		result := completion.done != 0
		if result && completion.done != u32(-1) { completion.done-- }
		C.vkp_spin_unlock_irqrestore(&completion.@wait.lock, flags)
		return result
	}
}
@[export: 'completion_done']
pub fn completion_done(storage voidptr) bool {
	unsafe {
		completion := &C.vkw_completion(storage)
		flags := C.vkp_spin_lock_irqsave(&completion.@wait.lock)
		result := completion.done != 0
		C.vkp_spin_unlock_irqrestore(&completion.@wait.lock, flags)
		return result
	}
}
