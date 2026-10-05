// SPDX-License-Identifier: GPL-2.0-only
// Stamp ordering and Wait-Die/Wound-Wait follow the pinned Linux algorithms.
// Copyright (C) 2013 Canonical Ltd.; Copyright (C) 2018 VMware Inc.
// Native waiters stay on their task's stack and are detached under wait_lock.
@[translated]
module compatcore

#include "linuxkpi_wait_v_primitives.h"

struct C.vkw_mutex {
mut:
	owner i64
	wait_lock u32
	wait_list C.vkw_list
}
struct C.vkw_ww_mutex {
mut:
	base C.vkw_mutex
	ctx voidptr
}
struct C.vkw_ww_ctx {
mut:
	task voidptr
	stamp u64
	acquired u32
	wounded u16
	is_wait_die u16
}
struct WwWaiter {
mut:
	entry C.vkw_list
	task voidptr
	ctx voidptr
}

@[c: '__atomic_load_n']
fn C.vkw_load_short(&u16, i32) u16
@[c: '__atomic_store_n']
fn C.vkw_store_short(&u16, u16, i32)
@[c: '__atomic_load_n']
fn C.vkw_load_owner(&i64, i32) i64
@[c: '__atomic_store_n']
fn C.vkw_store_owner(&i64, i64, i32)
@[c: '__atomic_fetch_add']
fn C.vkw_add_count(&u32, u32, i32) u32
@[c: '__atomic_fetch_sub']
fn C.vkw_sub_count(&u32, u32, i32) u32
fn C.vkw_signal_state(u32, voidptr) bool
fn C.vkw_current_state(u32)
fn C.vkw_wake_task(voidptr) i32

fn ww_list_empty(head &C.vkw_list) bool {
	unsafe { return C.vkw_load_pointer(&voidptr(&head.next), 0) == head }
}
fn ww_list_add_tail(node &C.vkw_list, head &C.vkw_list) {
	unsafe {
		node.prev = head.prev
		node.next = head
		C.vkw_store_pointer(&voidptr(&head.prev.next), node, 0)
		head.prev = node
	}
}
fn ww_list_del_init(node &C.vkw_list) {
	unsafe {
		node.next.prev = node.prev
		C.vkw_store_pointer(&voidptr(&node.prev.next), node.next, 0)
		wait_list_init(node)
	}
}
fn ww_context_acquired(ctx &C.vkw_ww_ctx) u32 {
	unsafe { return C.vkp_load32(&ctx.acquired, 2) }
}
fn ww_context_younger(a &C.vkw_ww_ctx, b &C.vkw_ww_ctx) bool {
	// Live stamps must remain within half the unsigned sequence space.
	unsafe { return i64(a.stamp - b.stamp) > 0 }
}
fn ww_owner_context(ww_lock &C.vkw_ww_mutex) &C.vkw_ww_ctx {
	unsafe { return &C.vkw_ww_ctx(C.vkw_load_pointer(&ww_lock.ctx, 2)) }
}
fn ww_prepare_context(ctx &C.vkw_ww_ctx) {
	unsafe {
		if is_null(ctx) { return }
		require(ctx.task == C.vkp_current() && ctx.is_wait_die <= 1)
		if ww_context_acquired(ctx) == 0 { C.vkw_store_short(&ctx.wounded, 0, 3) }
	}
}
fn ww_acquire_context(ww_lock &C.vkw_ww_mutex, ctx &C.vkw_ww_ctx) {
	unsafe {
		require(is_null(ww_owner_context(ww_lock)))
		if !is_null(ctx) { require(C.vkw_add_count(&ctx.acquired, 1, 4) != u32(-1)) }
		C.vkw_store_pointer(&ww_lock.ctx, ctx, 3)
	}
}
fn ww_release_context(ww_lock &C.vkw_ww_mutex) {
	unsafe {
		ctx := ww_owner_context(ww_lock)
		if !is_null(ctx) {
			require(ctx.task == C.vkp_current())
			require(C.vkw_sub_count(&ctx.acquired, 1, 4) != 0)
		}
		C.vkw_store_pointer(&ww_lock.ctx, nil, 3)
	}
}
fn ww_waiter_at(entry &C.vkw_list) &WwWaiter {
	unsafe { return &WwWaiter(usize(entry) - __offsetof(WwWaiter, entry)) }
}
fn ww_die_waiter(waiter &WwWaiter, older &C.vkw_ww_ctx) bool {
	unsafe {
		if older.is_wait_die == 0 { return false }
		ctx := &C.vkw_ww_ctx(waiter.ctx)
		if ww_context_acquired(ctx) != 0 && ww_context_younger(ctx, older) {
			C.vkw_wake_task(waiter.task)
		}
		return true
	}
}
fn ww_wound_owner(ww_lock &C.vkw_ww_mutex, requester &C.vkw_ww_ctx, holder &C.vkw_ww_ctx) bool {
	unsafe {
		if is_null(holder) || ww_context_acquired(requester) == 0
			|| !ww_context_younger(holder, requester) { return false }
		owner := voidptr(C.vkw_load_owner(&ww_lock.base.owner, 0))
		require(!is_null(owner) && holder.task == owner)
		// Separate mutex wait locks can expose this context concurrently.
		C.vkw_store_short(&holder.wounded, 1, 3)
		if owner != C.vkp_current() { C.vkw_wake_task(owner) }
		return true
	}
}
fn ww_check_waiters(ww_lock &C.vkw_ww_mutex, holder &C.vkw_ww_ctx) {
	unsafe {
		if is_null(holder) { return }
		for entry := ww_lock.base.wait_list.next; entry != &ww_lock.base.wait_list; entry = entry.next {
			waiter := ww_waiter_at(entry)
			if is_null(waiter.ctx) { continue }
			if ww_die_waiter(waiter, holder) || ww_wound_owner(ww_lock, &C.vkw_ww_ctx(waiter.ctx), holder) { break }
		}
	}
}
fn ww_add_waiter(ww_lock &C.vkw_ww_mutex, waiter &WwWaiter) i32 {
	unsafe {
		ctx := &C.vkw_ww_ctx(waiter.ctx)
		if is_null(ctx) { ww_list_add_tail(&waiter.entry, &ww_lock.base.wait_list); return 0 }
		mut position := &ww_lock.base.wait_list
		for entry := ww_lock.base.wait_list.prev; entry != &ww_lock.base.wait_list; entry = entry.prev {
			existing := ww_waiter_at(entry)
			if is_null(existing.ctx) { continue }
			if ww_context_younger(ctx, &C.vkw_ww_ctx(existing.ctx)) {
				if ctx.is_wait_die != 0 && ww_context_acquired(ctx) != 0 { return -35 }
				break
			}
			position = entry
			ww_die_waiter(existing, ctx)
		}
		ww_list_add_tail(&waiter.entry, position)
		if ctx.is_wait_die == 0 { ww_wound_owner(ww_lock, ctx, ww_owner_context(ww_lock)) }
		return 0
	}
}
fn ww_must_back_off(ww_lock &C.vkw_ww_mutex, waiter &WwWaiter) bool {
	unsafe {
		ctx := &C.vkw_ww_ctx(waiter.ctx)
		if is_null(ctx) || ww_context_acquired(ctx) == 0 { return false }
		if ctx.is_wait_die == 0 { return C.vkw_load_short(&ctx.wounded, 2) != 0 }
		holder := ww_owner_context(ww_lock)
		if !is_null(holder) && ww_context_younger(ctx, holder) { return true }
		for entry := waiter.entry.prev; entry != &ww_lock.base.wait_list; entry = entry.prev {
			if !is_null(ww_waiter_at(entry).ctx) { return true }
		}
		return false
	}
}
fn ww_acquire_mutex(ww_lock &C.vkw_ww_mutex, ctx &C.vkw_ww_ctx, state u32) i32 {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		task := C.vkp_current()
		mut waiter := WwWaiter{}
		waiter.task = task
		waiter.ctx = ctx
		wait_list_init(&waiter.entry)
		mut flags := C.vkp_spin_lock_irqsave(&ww_lock.base.wait_lock)
		if !is_null(ctx) && ww_owner_context(ww_lock) == ctx {
			require(ctx.task == task && C.vkw_load_owner(&ww_lock.base.owner, 0) == i64(task))
			C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
			return -114
		}
		ww_prepare_context(ctx)
		owner := C.vkw_load_owner(&ww_lock.base.owner, 0)
		require(owner != i64(task))
		if owner == 0 {
			require(ww_list_empty(&ww_lock.base.wait_list))
			ww_acquire_context(ww_lock, ctx)
			C.vkw_store_owner(&ww_lock.base.owner, i64(task), 3)
			ww_check_waiters(ww_lock, ctx)
			C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
			return 0
		}
		mut result := ww_add_waiter(ww_lock, &waiter)
		if result != 0 {
			require(ww_list_empty(&waiter.entry))
			C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
			return result
		}
		for {
			// Direct handoff publishes context/count before detaching the record.
			if C.vkw_load_owner(&ww_lock.base.owner, 0) == i64(task) {
				require(ww_list_empty(&waiter.entry) && ww_owner_context(ww_lock) == ctx)
				C.vkw_current_state(0)
				C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
				return 0
			}
			result = if C.vkw_signal_state(state, task) { i32(-4) }
				else if ww_must_back_off(ww_lock, &waiter) { i32(-35) } else { i32(0) }
			if result != 0 {
				ww_list_del_init(&waiter.entry)
				C.vkw_current_state(0)
				C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
				return result
			}
			C.vkw_current_state(state)
			C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
			C.vkp_schedule()
			flags = C.vkp_spin_lock_irqsave(&ww_lock.base.wait_lock)
		}
	}
	return 0
}

@[export: 'ww_mutex_lock']
pub fn ww_mutex_lock(storage voidptr, context voidptr) i32 {
	unsafe { return ww_acquire_mutex(&C.vkw_ww_mutex(storage), &C.vkw_ww_ctx(context), 2) }
}
@[export: 'ww_mutex_lock_interruptible']
pub fn ww_mutex_lock_interruptible(storage voidptr, context voidptr) i32 {
	unsafe { return ww_acquire_mutex(&C.vkw_ww_mutex(storage), &C.vkw_ww_ctx(context), 1) }
}
@[export: 'ww_mutex_trylock']
pub fn ww_mutex_trylock(storage voidptr, context voidptr) i32 {
	unsafe {
		ww_lock := &C.vkw_ww_mutex(storage)
		ctx := &C.vkw_ww_ctx(context)
		flags := C.vkp_spin_lock_irqsave(&ww_lock.base.wait_lock)
		ww_prepare_context(ctx)
		acquired := C.vkw_load_owner(&ww_lock.base.owner, 0) == 0
		if acquired {
			require(ww_list_empty(&ww_lock.base.wait_list))
			ww_acquire_context(ww_lock, ctx)
			C.vkw_store_owner(&ww_lock.base.owner, i64(C.vkp_current()), 3)
			ww_check_waiters(ww_lock, ctx)
		}
		C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
		return if acquired { 1 } else { 0 }
	}
}
@[export: 'ww_mutex_unlock']
pub fn ww_mutex_unlock(storage voidptr) {
	unsafe {
		ww_lock := &C.vkw_ww_mutex(storage)
		flags := C.vkp_spin_lock_irqsave(&ww_lock.base.wait_lock)
		require(C.vkw_load_owner(&ww_lock.base.owner, 0) == i64(C.vkp_current()))
		ww_release_context(ww_lock)
		if ww_list_empty(&ww_lock.base.wait_list) { C.vkw_store_owner(&ww_lock.base.owner, 0, 3) }
		else {
			waiter := ww_waiter_at(ww_lock.base.wait_list.next)
			next := waiter.task
			ctx := &C.vkw_ww_ctx(waiter.ctx)
			ww_list_del_init(&waiter.entry)
			ww_acquire_context(ww_lock, ctx)
			C.vkw_store_owner(&ww_lock.base.owner, i64(next), 3)
			ww_check_waiters(ww_lock, ctx)
			// Do not read the detached stack record after publication/wakeup.
			C.vkw_wake_task(next)
		}
		C.vkp_spin_unlock_irqrestore(&ww_lock.base.wait_lock, flags)
	}
}
