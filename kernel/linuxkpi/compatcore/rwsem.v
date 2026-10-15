// SPDX-License-Identifier: GPL-2.0-only
// Linux 6.6.157 rwsem count/owner ABI and reader phases, with native sleeping
// handoff. Stack waiters remain serialized by the original wait_lock.
@[translated]
module compatcore

#include "linuxkpi_rwsem_v_primitives.h"

struct C.vrs_rwsem {
mut:
	count     i64
	owner     i64
	wait_lock u32
	wait_list C.vkw_list
}

struct RwsemWaiter {
mut:
	entry   C.vkw_list
	task    voidptr
	writer  bool
	granted bool
}

const vrs_writer = i64(1)
const vrs_waiters = i64(2)
const vrs_reader_bias = i64(256)
const vrs_reader_mask = ~i64(255)
const vrs_max_readers = u64(0x007fffffffffffff)

fn vrs_assert(ok bool, message &char) {
	if !ok { C.vinix_linuxkpi_bug(message, 0) }
}

fn vrs_storage(storage voidptr) &C.vrs_rwsem {
	vrs_assert(!is_null(storage) && (usize(storage) & 7) == 0, c'invalid rwsem storage')
	unsafe {
		return &C.vrs_rwsem(storage)
	}
}

fn vrs_current() voidptr {
	task := C.vkp_current()
	vrs_assert(!is_null(task) && (usize(task) & 3) == 0, c'rwsem requires a live aligned current task')
	return task
}

fn vrs_waiter(entry &C.vkw_list) &RwsemWaiter {
	unsafe {
		return &RwsemWaiter(usize(entry) - __offsetof(RwsemWaiter, entry))
	}
}

fn vrs_count_locked(sem &C.vrs_rwsem) i64 {
	unsafe {
		count := C.vkw_load_owner(&sem.count, 0)
		owner := C.vkw_load_owner(&sem.owner, 0)
		vrs_assert(count >= 0 && (count & 0xfc) == 0, c'invalid rwsem count flags')
		vrs_assert((count & vrs_writer) == 0 || (count & vrs_reader_mask) == 0,
			c'rwsem reader and writer overlap')
		vrs_assert(!is_null(sem.wait_list.next) && !is_null(sem.wait_list.prev), c'uninitialized rwsem list')
		vrs_assert(((count & vrs_waiters) != 0) == !ww_list_empty(&sem.wait_list),
			c'rwsem waiter flag differs from queue')
		if (count & vrs_writer) != 0 {
			vrs_assert(owner != 0 && (owner & 3) == 0, c'invalid rwsem writer owner')
		} else {
			vrs_assert(owner == 0 || (owner & 3) == 1, c'invalid rwsem reader hint')
			if (count & vrs_reader_mask) != 0 {
				vrs_assert((owner & 1) != 0, c'missing rwsem reader hint')
			}
		}
		return count
	}
}

// The active part has no waiters bit. Every queue mutation publishes its
// corresponding bit under wait_lock before any grant is made observable.
fn vrs_publish_locked(sem &C.vrs_rwsem, active i64) {
	unsafe {
		value := active | if ww_list_empty(&sem.wait_list) { i64(0) } else { vrs_waiters }
		C.vkw_store_owner(&sem.count, value, 3)
	}
}

fn vrs_set_reader(sem &C.vrs_rwsem, task voidptr) {
	unsafe { C.vkw_store_owner(&sem.owner, i64(task) | 1, 0) }
}

// Native handoff does not permit writers to steal a queued grant. Once the
// head is a reader, retain the original phase: up to256 readers anywhere in
// the queue, including readers beyond queued writers, acquire together.
fn vrs_wake_locked(sem &C.vrs_rwsem) {
	unsafe {
		if ww_list_empty(&sem.wait_list) { return }
		active := C.vkw_load_owner(&sem.count, 0) & ~vrs_waiters
		if (active & vrs_writer) != 0 { return }
		first := vrs_waiter(sem.wait_list.next)
		if first.writer {
			if active != 0 { return }
			task := first.task
			ww_list_del_init(&first.entry)
			C.vkw_store_owner(&sem.owner, i64(task), 0)
			vrs_publish_locked(sem, vrs_writer)
			first.granted = true
			C.vkw_wake_task(task)
			// The waiter may cease to exist after the final unlock. Neither
			// this record nor its task field is read after wake publication.
			return
		}
		mut number := u64(0)
		for entry := sem.wait_list.next; entry != &sem.wait_list; entry = entry.next {
			if !vrs_waiter(entry).writer {
				number++
				if number == 256 { break }
			}
		}
		vrs_assert(number > 0 && u64(active >> 8) <= vrs_max_readers - number,
			c'rwsem reader count overflow')
		mut grants := C.vkw_list{}
		wait_list_init(&grants)
		mut selected := u64(0)
		mut entry := sem.wait_list.next
		for selected < number {
			waiter := vrs_waiter(entry)
			entry = entry.next
			if waiter.writer { continue }
			ww_list_del_init(&waiter.entry)
			ww_list_add_tail(&waiter.entry, &grants)
			selected++
		}
		vrs_set_reader(sem, first.task)
		vrs_publish_locked(sem, active + i64(number) * vrs_reader_bias)
		// Publish the whole phase before any reader can be woken. Every
		// queued API still takes wait_lock before returning to its caller.
		for !ww_list_empty(&grants) {
			waiter := vrs_waiter(grants.next)
			task := waiter.task
			ww_list_del_init(&waiter.entry)
			waiter.granted = true
			C.vkw_wake_task(task)
		}
	}
}

@[export: 'vrs_init']
pub fn rwsem_init(storage voidptr) {
	unsafe {
		sem := vrs_storage(storage)
		// Fresh storage is not inspected. Live reinitialization is caller
		// misuse; no side allocation or hidden initialized-state registry.
		C.vkw_store_owner(&sem.count, 0, 0)
		C.vkw_store_owner(&sem.owner, 0, 0)
		C.vkp_spin_init(&sem.wait_lock)
		wait_list_init(&sem.wait_list)
	}
}

fn vrs_acquire(storage voidptr, state u32, writer bool) i32 {
	unsafe {
		vrs_assert(state == 2 || state == 258 || (!writer && state == 1), c'invalid rwsem wait state')
		sem := vrs_storage(storage)
		vrs_assert(C.vinix_linuxkpi_may_sleep(), c'rwsem blocking acquire requires sleepable task')
		task := vrs_current()
		mut waiter := RwsemWaiter{ task: task, writer: writer }
		mut flags := C.vkp_spin_lock_irqsave(&sem.wait_lock)
		count := vrs_count_locked(sem)
		vrs_assert((count & vrs_writer) == 0 || C.vkw_load_owner(&sem.owner, 0) != i64(task),
			c'rwsem recursive writer acquire')
		if ww_list_empty(&sem.wait_list) && (count & vrs_writer) == 0
			&& (!writer || count == 0) {
			if writer {
				C.vkw_store_owner(&sem.owner, i64(task), 0)
				vrs_publish_locked(sem, vrs_writer)
			} else {
				vrs_assert(u64(count >> 8) < vrs_max_readers, c'rwsem reader count overflow')
				vrs_set_reader(sem, task)
				vrs_publish_locked(sem, count + vrs_reader_bias)
			}
			C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
			return 0
		}
		ww_list_add_tail(&waiter.entry, &sem.wait_list)
		vrs_publish_locked(sem, count & ~vrs_waiters)
		for {
			if waiter.granted {
				vrs_assert(ww_list_empty(&waiter.entry), c'rwsem granted waiter still queued')
				C.vkw_current_state(0)
				C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
				return 0
			}
			if C.vkw_signal_state(state, task) {
				ww_list_del_init(&waiter.entry)
				vrs_publish_locked(sem, C.vkw_load_owner(&sem.count, 0) & ~vrs_waiters)
				vrs_wake_locked(sem)
				C.vkw_current_state(0)
				C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
				return -4
			}
			C.vkw_current_state(state)
			C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
			C.vkp_schedule()
			flags = C.vkp_spin_lock_irqsave(&sem.wait_lock)
		}
	}
	return 0
}

@[export: 'vrs_down_read']
pub fn rwsem_down_read(storage voidptr, state u32) i32 { return vrs_acquire(storage, state, false) }

@[export: 'vrs_down_write']
pub fn rwsem_down_write(storage voidptr, state u32) i32 { return vrs_acquire(storage, state, true) }

fn vrs_try(storage voidptr, writer bool) i32 {
	unsafe {
		sem := vrs_storage(storage)
		task := vrs_current()
		flags := C.vkp_spin_lock_irqsave(&sem.wait_lock)
		count := vrs_count_locked(sem)
		mut acquired := false
		if ww_list_empty(&sem.wait_list) && (count & vrs_writer) == 0 && (!writer || count == 0) {
			if writer {
				C.vkw_store_owner(&sem.owner, i64(task), 0)
				vrs_publish_locked(sem, vrs_writer)
			} else {
				vrs_assert(u64(count >> 8) < vrs_max_readers, c'rwsem reader count overflow')
				vrs_set_reader(sem, task)
				vrs_publish_locked(sem, count + vrs_reader_bias)
			}
			acquired = true
		}
		C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
		return if acquired { 1 } else { 0 }
	}
}

@[export: 'vrs_try_read']
pub fn rwsem_try_read(storage voidptr) i32 { return vrs_try(storage, false) }

@[export: 'vrs_try_write']
pub fn rwsem_try_write(storage voidptr) i32 { return vrs_try(storage, true) }

@[export: 'vrs_up_read']
pub fn rwsem_up_read(storage voidptr) {
	unsafe {
		sem := vrs_storage(storage)
		flags := C.vkp_spin_lock_irqsave(&sem.wait_lock)
		count := vrs_count_locked(sem)
		vrs_assert((count & vrs_writer) == 0 && (count & vrs_reader_mask) != 0, c'rwsem read unlock without reader')
		remaining := (count & ~vrs_waiters) - vrs_reader_bias
		vrs_publish_locked(sem, remaining)
		if remaining == 0 { vrs_wake_locked(sem) }
		C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
	}
}

@[export: 'vrs_up_write']
pub fn rwsem_up_write(storage voidptr) {
	unsafe {
		sem := vrs_storage(storage)
		task := vrs_current()
		flags := C.vkp_spin_lock_irqsave(&sem.wait_lock)
		count := vrs_count_locked(sem)
		vrs_assert((count & vrs_writer) != 0 && C.vkw_load_owner(&sem.owner, 0) == i64(task), c'rwsem write unlock by nonowner')
		C.vkw_store_owner(&sem.owner, 0, 0)
		vrs_publish_locked(sem, 0)
		vrs_wake_locked(sem)
		C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
	}
}

@[export: 'vrs_downgrade']
pub fn rwsem_downgrade(storage voidptr) {
	unsafe {
		sem := vrs_storage(storage)
		task := vrs_current()
		flags := C.vkp_spin_lock_irqsave(&sem.wait_lock)
		count := vrs_count_locked(sem)
		vrs_assert((count & vrs_writer) != 0 && C.vkw_load_owner(&sem.owner, 0) == i64(task), c'rwsem downgrade by nonowner')
		vrs_set_reader(sem, task)
		vrs_publish_locked(sem, vrs_reader_bias)
		vrs_wake_locked(sem)
		C.vkp_spin_unlock_irqrestore(&sem.wait_lock, flags)
	}
}
