// SPDX-License-Identifier: GPL-2.0-only
// Hashed queues and keyed stack waiters preserve the native LinuxKPI lifetime
// contract: finish_wait serializes with every callback before a frame returns.
@[translated]
module compatcore

#include "linuxkpi_wait_v_primitives.h"

struct C.vkw_list {
mut:
	next &C.vkw_list
	prev &C.vkw_list
}
struct C.vkw_wait_key {
mut:
	flags voidptr
	bit_nr i32
	timeout u64
}
struct C.vkw_wait_entry {
mut:
	flags u32
	@private voidptr
	func voidptr
	entry C.vkw_list
}
struct C.vkw_wait_queue {
mut:
	lock u32
	head C.vkw_list
}
struct C.vkw_wait_bit {
mut:
	key C.vkw_wait_key
	wq_entry C.vkw_wait_entry
}

fn C.vkw_wait_table() voidptr
fn C.vkw_wait_init(voidptr)
fn C.vkw_wait_prepare(voidptr, voidptr, u32)
fn C.vkw_wait_prepare_exclusive(voidptr, voidptr, u32)
fn C.vkw_wait_finish(voidptr, voidptr)
fn C.vkw_wait_active(voidptr) bool
fn C.vkw_wait_wake(voidptr, u32, i32, voidptr)
fn C.vkw_wait_autoremove(voidptr, u32, i32, voidptr) i32
fn C.vkw_test_bit(i32, voidptr) bool
fn C.vkw_test_bit_acquire(i32, voidptr) bool
fn C.vkw_test_and_set_bit(i32, voidptr) bool
fn C.vkw_bit_wake_callback() voidptr
fn C.vkw_var_wake_callback() voidptr

@[c: '__atomic_load_n']
fn C.vkw_load_pointer(&voidptr, i32) voidptr
@[c: '__atomic_store_n']
fn C.vkw_store_pointer(&voidptr, voidptr, i32)

__global vkw_bit_wait_ready u32

fn wait_list_init(head &C.vkw_list) {
	unsafe {
		C.vkw_store_pointer(&voidptr(&head.next), head, 0)
		C.vkw_store_pointer(&voidptr(&head.prev), head, 0)
	}
}

@[export: 'wait_bit_init']
pub fn wait_bit_init() {
	unsafe {
		if C.vkp_load32(&vkw_bit_wait_ready, 2) != 0 { return }
		table := &C.vkw_wait_queue(C.vkw_wait_table())
		for bucket := u32(0); bucket < 256; bucket++ {
			C.vkw_wait_init(&table[bucket])
		}
		C.vkp_store32(&vkw_bit_wait_ready, 1, 3)
	}
}

fn wait_bucket(key u64) voidptr {
	unsafe {
		require(C.vkp_load32(&vkw_bit_wait_ready, 2) != 0)
		table := &C.vkw_wait_queue(C.vkw_wait_table())
		return &table[(key * u64(0x61c8864680b583eb)) >> 56]
	}
}

@[export: 'bit_waitqueue']
pub fn bit_waitqueue(word voidptr, bit i32) voidptr {
	return wait_bucket((u64(word) << 6) | u64(i64(bit)))
}

@[export: '__var_waitqueue']
pub fn var_waitqueue(variable voidptr) voidptr {
	// The producer may already have retired this object; hash its address only.
	return wait_bucket(u64(variable))
}

fn bit_waiter(entry voidptr) &C.vkw_wait_bit {
	unsafe { return &C.vkw_wait_bit(usize(entry) - __offsetof(C.vkw_wait_bit, wq_entry)) }
}

@[export: 'wake_bit_function']
pub fn wake_bit_function(entry voidptr, mode u32, sync i32, argument voidptr) i32 {
	unsafe {
		key := &C.vkw_wait_key(argument)
		wait := bit_waiter(entry)
		if wait.key.flags != key.flags || wait.key.bit_nr != key.bit_nr
			|| C.vkw_test_bit(key.bit_nr, key.flags) { return 0 }
		return C.vkw_wait_autoremove(entry, mode, sync, key)
	}
}

@[export: 'vinix_linuxkpi_var_wake_function']
pub fn var_wake_function(entry voidptr, mode u32, sync i32, argument voidptr) i32 {
	unsafe {
		key := &C.vkw_wait_key(argument)
		wait := bit_waiter(entry)
		if wait.key.flags != key.flags || wait.key.bit_nr != key.bit_nr { return 0 }
		return C.vkw_wait_autoremove(entry, mode, sync, key)
	}
}

fn init_bit_wait_entry(wait &C.vkw_wait_bit, word voidptr, bit i32, flags u32, callback voidptr) {
	unsafe {
		C.memset(wait, 0, sizeof(C.vkw_wait_bit))
		wait.key.flags = word
		wait.key.bit_nr = bit
		wait.wq_entry.flags = flags
		wait.wq_entry.@private = C.vkp_current()
		wait.wq_entry.func = callback
		wait_list_init(&wait.wq_entry.entry)
	}
}

@[export: 'init_wait_var_entry']
pub fn init_wait_var_entry(storage voidptr, variable voidptr, flags i32) {
	unsafe { init_bit_wait_entry(&C.vkw_wait_bit(storage), variable, -1, u32(flags), C.vkw_var_wake_callback()) }
}

@[export: '__wait_on_bit']
pub fn wait_on_bit(queue voidptr, storage voidptr, action fn (voidptr, i32) i32, mode u32) i32 {
	unsafe {
		wait := &C.vkw_wait_bit(storage)
		mut result := i32(0)
		for {
			C.vkw_wait_prepare(queue, &wait.wq_entry, mode)
			if C.vkw_test_bit(wait.key.bit_nr, wait.key.flags) { result = action(&wait.key, i32(mode)) }
			if !C.vkw_test_bit_acquire(wait.key.bit_nr, wait.key.flags) || result != 0 { break }
		}
		C.vkw_wait_finish(queue, &wait.wq_entry)
		return result
	}
}

@[export: 'out_of_line_wait_on_bit']
pub fn out_of_line_wait_on_bit(word voidptr, bit i32, action fn (voidptr, i32) i32, mode u32) i32 {
	unsafe {
		queue := bit_waitqueue(word, bit)
		mut wait := C.vkw_wait_bit{}
		init_bit_wait_entry(&wait, word, bit, 0, C.vkw_bit_wake_callback())
		return wait_on_bit(queue, &wait, action, mode)
	}
}

@[export: 'out_of_line_wait_on_bit_timeout']
pub fn out_of_line_wait_on_bit_timeout(word voidptr, bit i32, action fn (voidptr, i32) i32, mode u32, timeout u64) i32 {
	unsafe {
		queue := bit_waitqueue(word, bit)
		mut wait := C.vkw_wait_bit{}
		init_bit_wait_entry(&wait, word, bit, 0, C.vkw_bit_wake_callback())
		// Spurious wakes never extend the absolute boundary captured here.
		wait.key.timeout = C.vkp_jiffies() + timeout
		return wait_on_bit(queue, &wait, action, mode)
	}
}

@[export: '__wait_on_bit_lock']
pub fn wait_on_bit_lock(queue voidptr, storage voidptr, action fn (voidptr, i32) i32, mode u32) i32 {
	unsafe {
		wait := &C.vkw_wait_bit(storage)
		mut result := i32(0)
		for {
			C.vkw_wait_prepare_exclusive(queue, &wait.wq_entry, mode)
			if C.vkw_test_bit(wait.key.bit_nr, wait.key.flags) {
				result = action(&wait.key, i32(mode))
				if result != 0 { C.vkw_wait_finish(queue, &wait.wq_entry) }
			}
			// Atomic acquisition wins a simultaneous signal or action error.
			if !C.vkw_test_and_set_bit(wait.key.bit_nr, wait.key.flags) {
				if result == 0 { C.vkw_wait_finish(queue, &wait.wq_entry) }
				return 0
			}
			if result != 0 { return result }
		}
	}
	return 0
}

@[export: 'out_of_line_wait_on_bit_lock']
pub fn out_of_line_wait_on_bit_lock(word voidptr, bit i32, action fn (voidptr, i32) i32, mode u32) i32 {
	unsafe {
		queue := bit_waitqueue(word, bit)
		mut wait := C.vkw_wait_bit{}
		init_bit_wait_entry(&wait, word, bit, 0, C.vkw_bit_wake_callback())
		return wait_on_bit_lock(queue, &wait, action, mode)
	}
}

@[export: '__wake_up_bit']
pub fn wake_up_bit_queue(queue voidptr, word voidptr, bit i32) {
	unsafe {
		mut key := C.vkw_wait_key{}
		key.flags = word
		key.bit_nr = bit
		if C.vkw_wait_active(queue) { C.vkw_wait_wake(queue, 3, 1, &key) }
	}
}

@[export: 'wake_up_bit']
pub fn wake_up_bit(word voidptr, bit i32) {
	// Ordinary entries also receive wakes while the bit remains set.
	wake_up_bit_queue(bit_waitqueue(word, bit), word, bit)
}

@[export: 'wake_up_var']
pub fn wake_up_var(variable voidptr) {
	wake_up_bit_queue(var_waitqueue(variable), variable, -1)
}

@[export: 'bit_wait']
pub fn bit_wait(key voidptr, mode i32) i32 {
	C.vkp_schedule()
	return if C.vkp_signal_pending(mode) { -4 } else { 0 }
}

@[export: 'bit_wait_timeout']
pub fn bit_wait_timeout(storage voidptr, mode i32) i32 {
	unsafe {
		key := &C.vkw_wait_key(storage)
		now := C.vkp_jiffies()
		if i64(now - key.timeout) >= 0 { return -11 }
		C.vkp_schedule_timeout(i64(key.timeout - now))
		return if C.vkp_signal_pending(mode) { -4 } else { 0 }
	}
}
