// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxkpi

import event
import katomic
import lib
import memory
import proc
import sched
import x86.cpu
import x86.hpet as resv_clock

#include "linuxkpi_resv_fixture_v_primitives.h"

struct C.vinix_resv_fixture {}
struct C.vinix_resv_iter_fixture {}
fn C.vinix_linuxkpi_resv_fixture_bytes(u32) u32
fn C.vinix_linuxkpi_resv_fixture_init(voidptr)
fn C.vinix_linuxkpi_resv_fixture_fini(voidptr)
fn C.vinix_linuxkpi_resv_fixture_lock(voidptr, u32) i32
fn C.vinix_linuxkpi_resv_fixture_unlock(voidptr)
fn C.vinix_linuxkpi_resv_fixture_locked(voidptr) bool
fn C.vinix_linuxkpi_resv_fixture_reserve(voidptr, u32) i32
fn C.vinix_linuxkpi_resv_fixture_add(voidptr, voidptr, u32)
fn C.vinix_linuxkpi_resv_fixture_replace(voidptr, u64, voidptr, u32)
fn C.vinix_linuxkpi_resv_fixture_copy(voidptr, voidptr) i32
fn C.vinix_linuxkpi_resv_fixture_begin(voidptr, voidptr, u32)
fn C.vinix_linuxkpi_resv_fixture_step(voidptr, u32) voidptr
fn C.vinix_linuxkpi_resv_fixture_end(voidptr)
fn C.vinix_linuxkpi_resv_fixture_cursor(voidptr, u32) u32
fn C.vinix_linuxkpi_resv_fixture_list(voidptr) voidptr
fn C.vinix_linuxkpi_resv_fixture_list_value(voidptr, u32, u32) u64
fn C.vinix_linuxkpi_resv_fixture_get(voidptr, u32, &u32, &voidptr) i32
fn C.vinix_linuxkpi_resv_fixture_singleton(voidptr, u32, &voidptr) i32
fn C.vinix_linuxkpi_resv_fixture_wait(voidptr, u32, bool, u64) i64
fn C.vinix_linuxkpi_resv_fixture_deadline(voidptr, u32, i64)
fn C.vinix_linuxkpi_resv_fixture_signaled(voidptr, u32) bool
fn C.vinix_linuxkpi_resv_fixture_roundup(usize) usize
fn C.vinix_linuxkpi_resv_fixture_realloc(voidptr, usize, usize) voidptr

// Every output slot, cursor and cross-task borrow is boot-lifetime storage.
// Reinitialization follows actor retirement, reference puts and an RCU barrier.
struct ResvTestLedger {
mut:
	objects [3]C.vinix_resv_fixture
	cursor C.vinix_resv_iter_fixture
	cursor_live bool
	leaves [8]voidptr
	count u32
	vector voidptr
	vector_count u32
	output voidptr
	ready [3]bool
	commands [3]u32
	started [3]bool
	done [3]bool
	owners [3]voidptr
	quit bool
	results [3]i64
	usage u32
	intr bool
	timeout u64
	reader_held bool
	reader_release bool
	reader_list voidptr
	reader_entries [2]u64
	reader_fences [2]voidptr
	reader_check bool
	failures u32
}
__global resv_test_ledger ResvTestLedger

fn resv_fail(bit u32) {
	for {
		old := katomic.load(&resv_test_ledger.failures)
		if katomic.cas(mut &resv_test_ledger.failures, old, old | bit) { return }
	}
}
fn resv_wait(flag &bool) bool {
	start := resv_clock.nanoseconds()
	for !katomic.load(flag) {
		if resv_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return katomic.load(&resv_test_ledger.failures) == 0
}
fn resv_actor(argument voidptr) {
	index := u32(usize(argument))
	if worker_bind(index + 1) != 0 || !dma_fence_test_task(index + 1) { resv_fail(1) }
	katomic.store(mut &resv_test_ledger.ready[index], true)
	for !katomic.load(&resv_test_ledger.quit) {
		command := katomic.load(&resv_test_ledger.commands[index])
		if command == 0 { sched.reschedule(); continue }
		katomic.store(mut &resv_test_ledger.started[index], true)
		obj := unsafe { &resv_test_ledger.objects[0] }
		if command == 1 || command == 2 {
			ret := C.vinix_linuxkpi_resv_fixture_lock(obj, command - 1)
			resv_test_ledger.results[index] = ret
			if ret == 0 { C.vinix_linuxkpi_resv_fixture_unlock(obj) }
		} else if command == 3 {
			resv_test_ledger.results[index] = C.vinix_linuxkpi_resv_fixture_wait(obj,
				resv_test_ledger.usage, resv_test_ledger.intr, resv_test_ledger.timeout)
		} else if command == 4 {
			C.vinix_linuxkpi_rcu_fixture_read_lock()
			resv_test_ledger.reader_list = C.vinix_linuxkpi_resv_fixture_list(obj)
			for i in 0 .. 2 {
				resv_test_ledger.reader_entries[i] = C.vinix_linuxkpi_resv_fixture_list_value(resv_test_ledger.reader_list, 2, u32(i))
			}
			katomic.store(mut &resv_test_ledger.reader_held, true)
			start := resv_clock.nanoseconds()
			for !katomic.load(&resv_test_ledger.reader_release) {
				if resv_clock.nanoseconds() - start >= dmafence_test_timeout_ns {
					lib.kpanic(unsafe { nil }, c'linuxkpi: reservation RCU reader deadline')
				}
				spin_wait()
			}
			if resv_test_ledger.reader_check {
				if C.vinix_linuxkpi_resv_fixture_list_value(resv_test_ledger.reader_list, 0, 0) != 2 { resv_fail(4) }
				for i in 0 .. 2 {
					if C.vinix_linuxkpi_resv_fixture_list_value(resv_test_ledger.reader_list, 2, u32(i)) != resv_test_ledger.reader_entries[i]
						|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.reader_fences[i]) != 0 { resv_fail(8) }
				}
			}
			C.vinix_linuxkpi_rcu_fixture_read_unlock()
		} else { C.vinix_linuxkpi_rcu_fixture_barrier() }
		if !dma_fence_test_task(index + 1) { resv_fail(2) }
		katomic.store(mut &resv_test_ledger.commands[index], u32(0))
		katomic.store(mut &resv_test_ledger.done[index], true)
	}
	event.pthread_exit(unsafe { nil })
}
fn resv_start(index u32, command u32) {
	resv_test_ledger.results[index] = -9999
	katomic.store(mut &resv_test_ledger.started[index], false)
	katomic.store(mut &resv_test_ledger.done[index], false)
	katomic.store(mut &resv_test_ledger.commands[index], command)
}
fn resv_finish(index u32) {
	if !resv_wait(&resv_test_ledger.done[index]) {
		lib.kpanic(unsafe { nil }, c'linuxkpi: reservation actor cleanup deadline')
	}
}
fn resv_parked(index u32, expected u32) bool {
	owner := unsafe { &proc.Thread(resv_test_ledger.owners[index]) }
	start := resv_clock.nanoseconds()
	for !(katomic.load(&resv_test_ledger.started[index])
		&& C.vinix_linuxkpi_dmafence_fixture_task_state(unsafe { &owner.linuxkpi_task[0] }) == expected
		&& !katomic.load(&owner.is_in_queue) && katomic.load(&owner.running_on) == u64(-1)
		&& !katomic.load(&owner.is_in_queue)) {
		if katomic.load(&resv_test_ledger.done[index]) || resv_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	return true
}
fn resv_prepare() {
	for i in 0 .. 3 { C.vinix_linuxkpi_resv_fixture_init(unsafe { &resv_test_ledger.objects[i] }) }
}
fn resv_vector_put() {
	unsafe {
		for i in 0 .. resv_test_ledger.vector_count { C.vinix_linuxkpi_dmafence_fixture_put((&voidptr(resv_test_ledger.vector))[i]) }
	}
	C.kfree(resv_test_ledger.vector)
	resv_test_ledger.vector = unsafe { nil }
	resv_test_ledger.vector_count = 0
}
fn resv_clear() {
	if resv_test_ledger.cursor_live {
		C.vinix_linuxkpi_resv_fixture_end(unsafe { &resv_test_ledger.cursor })
		resv_test_ledger.cursor_live = false
	}
	for i in 0 .. resv_test_ledger.count {
		if resv_test_ledger.leaves[i] != unsafe { nil } { C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[i], 0, 0) }
	}
	resv_vector_put()
	if resv_test_ledger.output != unsafe { nil } && C.vinix_linuxkpi_fct_kind(resv_test_ledger.output) != 0 {
		start := resv_clock.nanoseconds()
		for C.vinix_linuxkpi_fct_refs(resv_test_ledger.output) != 1 {
			if resv_clock.nanoseconds() - start >= dmafence_test_timeout_ns { lib.kpanic(unsafe { nil }, c'linuxkpi: reservation singleton callbacks deadline') }
			sched.reschedule()
		}
	}
	C.vinix_linuxkpi_dmafence_fixture_put(resv_test_ledger.output)
	resv_test_ledger.output = unsafe { nil }
	for i in 0 .. 3 { C.vinix_linuxkpi_resv_fixture_fini(unsafe { &resv_test_ledger.objects[i] }) }
	for i in 0 .. resv_test_ledger.count {
		C.vinix_linuxkpi_dmafence_fixture_put(resv_test_ledger.leaves[i])
		resv_test_ledger.leaves[i] = unsafe { nil }
	}
	resv_test_ledger.count = 0
	C.vinix_linuxkpi_rcu_fixture_barrier()
}
fn resv_leaf(kind u32, context u64, seqno u64) bool {
	leaf := dma_fence_test_new(kind, 0, context, seqno)
	if leaf == unsafe { nil } { return false }
	resv_test_ledger.leaves[resv_test_ledger.count] = leaf
	resv_test_ledger.count++
	return true
}
fn resv_allocators() bool {
	// A fixed array stays local; no borrowed array or slice is published.
	sizes := [usize(0), 1, 16, 17, 64, 128, usize(-1)]!
	for i in 0 .. 7 { if C.vinix_linuxkpi_resv_fixture_roundup(sizes[i]) != sizes[i] { return false } }
	mut owner := C.kmalloc(17, 3264)
	if owner == unsafe { nil } { return false }
	defer { C.kfree(owner) }
	unsafe { for i in 0 .. 17 { (&u8(owner))[i] = u8(i + 0x40) } }
	test_alloc_oom(0)
	failed := C.vinix_linuxkpi_resv_fixture_realloc(owner, 128, 1)
	test_alloc_oom(-1)
	if failed != unsafe { nil } { owner = failed; return false }
	unsafe { for i in 0 .. 17 { if (&u8(owner))[i] != u8(i + 0x40) { return false } } }
	test_alloc_oom(1)
	overflow := C.vinix_linuxkpi_resv_fixture_realloc(owner, usize(-1), 2)
	gate := proc.current_thread().linuxkpi_alloc_fail_after
	test_alloc_oom(-1)
	if overflow != unsafe { nil } || gate != 1 { return false }
	grown := C.vinix_linuxkpi_resv_fixture_realloc(owner, 128, 1)
	if grown == unsafe { nil } { return false }
	different := grown != owner
	owner = grown
	if !different { return false }
	unsafe {
		for i in 0 .. 17 { if (&u8(owner))[i] != u8(i + 0x40) { return false } }
		for i in 17 .. 128 { (&u8(owner))[i] = u8(i) }
	}
	shrunk := C.vinix_linuxkpi_resv_fixture_realloc(owner, 64, 1)
	if shrunk == unsafe { nil } { return false }
	changed := shrunk != owner
	owner = shrunk
	if !changed { return false }
	unsafe { for i in 0 .. 64 { if (&u8(owner))[i] != if i < 17 { u8(i + 0x40) } else { u8(i) } { return false } } }
	return true
}
fn resv_writer_locking() bool {
	resv_prepare()
	defer { resv_clear() }
	obj := unsafe { &resv_test_ledger.objects[0] }
	mut held := false
	mut active := false
	defer {
		if held { C.vinix_linuxkpi_resv_fixture_unlock(obj) }
		if active { resv_finish(0) }
		test_task_signal(resv_test_ledger.owners[0], 0)
	}
	if C.vinix_linuxkpi_resv_fixture_locked(obj) || C.vinix_linuxkpi_resv_fixture_lock(obj, 2) != 0 { return false }
	held = true
	if !C.vinix_linuxkpi_resv_fixture_locked(obj) || C.vinix_linuxkpi_resv_fixture_lock(obj, 2) != -16 { return false }
	resv_start(0, 1)
	active = true
	if !resv_parked(0, 2) { return false }
	C.vinix_linuxkpi_resv_fixture_unlock(obj)
	held = false
	resv_finish(0)
	active = false
	if resv_test_ledger.results[0] != 0 || C.vinix_linuxkpi_resv_fixture_lock(obj, 0) != 0 { return false }
	held = true
	resv_start(0, 2)
	active = true
	if !resv_parked(0, 1) { return false }
	test_task_signal(resv_test_ledger.owners[0], u64(1) << 14)
	resv_finish(0)
	active = false
	test_task_signal(resv_test_ledger.owners[0], 0)
	return resv_test_ledger.results[0] == -4 && C.vinix_linuxkpi_resv_fixture_locked(obj)
}
fn resv_usage_growth() bool {
	resv_prepare()
	defer { resv_clear() }
	obj := unsafe { &resv_test_ledger.objects[0] }
	iter := unsafe { &resv_test_ledger.cursor }
	context := C.vinix_linuxkpi_dmafence_fixture_context(8)
	for i in 0 .. 4 { if !resv_leaf(0, context + u64(i), 1) { return false } }
	if !resv_leaf(0, context + 4, 2) || !resv_leaf(0, context + 2, 2)
		|| !resv_leaf(0, context + 2, 1) || !resv_leaf(0, context + 7, 1) { return false }
	if C.vinix_linuxkpi_resv_fixture_lock(obj, 0) != 0 { return false }
	defer { C.vinix_linuxkpi_resv_fixture_unlock(obj) }
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, 8) != 0 { return false }
	for i in 0 .. 4 { C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[i], u32(i)) }
	list := C.vinix_linuxkpi_resv_fixture_list(obj)
	for i in 0 .. 4 {
		if C.vinix_linuxkpi_resv_fixture_list_value(list, 2, u32(i)) != (u64(usize(resv_test_ledger.leaves[i])) | u64(i))
			|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[i]) != 2 { return false }
	}
	C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[0], 0, 0)
	C.vinix_linuxkpi_resv_fixture_begin(iter, obj, 1)
	// The locked iterator borrows even signaled fences and takes no references.
	if C.vinix_linuxkpi_resv_fixture_step(iter, 0) != resv_test_ledger.leaves[0]
		|| C.vinix_linuxkpi_resv_fixture_cursor(iter, 1) != 1
		|| C.vinix_linuxkpi_resv_fixture_step(iter, 1) != resv_test_ledger.leaves[1]
		|| C.vinix_linuxkpi_resv_fixture_cursor(iter, 0) != 1
		|| C.vinix_linuxkpi_resv_fixture_step(iter, 1) != unsafe { nil } { return false }
	C.vinix_linuxkpi_resv_fixture_begin(iter, obj, 1)
	resv_test_ledger.cursor_live = true
	if C.vinix_linuxkpi_resv_fixture_step(iter, 2) != resv_test_ledger.leaves[1]
		|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[1]) != 3
		|| C.vinix_linuxkpi_resv_fixture_step(iter, 3) != unsafe { nil }
		|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[1]) != 2 { return false }
	C.vinix_linuxkpi_resv_fixture_end(iter)
	resv_test_ledger.cursor_live = false
	C.vinix_linuxkpi_resv_fixture_replace(obj, context + 1, resv_test_ledger.leaves[4], 0)
	if C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[1]) != 1 || C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[4]) != 2 { return false }
	// Signaled slot reuse precedes the same-context promotion at its later slot.
	C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[7], 2)
	C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[5], 1)
	C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[6], 3)
	if C.vinix_linuxkpi_resv_fixture_list_value(list, 0, 0) != 5
		|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[2]) != 1
		|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[5]) != 2 { return false }
	C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[3], 0, 0)
	capacity := u32(C.vinix_linuxkpi_resv_fixture_list_value(list, 1, 0))
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, capacity + 1) != 0 { return false }
	new_list := C.vinix_linuxkpi_resv_fixture_list(obj)
	return new_list != list && C.vinix_linuxkpi_resv_fixture_list_value(new_list, 0, 0) == 4
		&& C.vinix_linuxkpi_resv_fixture_list_value(new_list, 1, 0) >= u64(capacity + 6)
		&& C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[3]) == 1
}
fn resv_collection_oom() bool {
	resv_prepare()
	defer { resv_clear() }
	src := unsafe { &resv_test_ledger.objects[0] }
	dst := unsafe { &resv_test_ledger.objects[1] }
	if C.vinix_linuxkpi_resv_fixture_get(src, 3, unsafe { &resv_test_ledger.vector_count }, unsafe { &resv_test_ledger.vector }) != 0
		|| resv_test_ledger.vector_count != 0 || resv_test_ledger.vector != unsafe { nil }
		|| C.vinix_linuxkpi_resv_fixture_singleton(src, 3, unsafe { &resv_test_ledger.output }) != 0
		|| resv_test_ledger.output != unsafe { nil } { return false }
	context := C.vinix_linuxkpi_dmafence_fixture_context(3)
	for i in 0 .. 3 { if !resv_leaf(0, context + u64(i), 1) { return false } }
	if C.vinix_linuxkpi_resv_fixture_lock(src, 0) != 0 { return false }
	defer { C.vinix_linuxkpi_resv_fixture_unlock(src) }
	if C.vinix_linuxkpi_resv_fixture_lock(dst, 0) != 0 { return false }
	defer { C.vinix_linuxkpi_resv_fixture_unlock(dst) }
	test_alloc_oom(0)
	missing := C.vinix_linuxkpi_resv_fixture_reserve(src, 3)
	test_alloc_oom(-1)
	if missing != -12 || C.vinix_linuxkpi_resv_fixture_list(src) != unsafe { nil }
		|| C.vinix_linuxkpi_resv_fixture_reserve(src, 3) != 0 { return false }
	for i in 0 .. 3 { C.vinix_linuxkpi_resv_fixture_add(src, resv_test_ledger.leaves[i], u32(i)) }
	old := C.vinix_linuxkpi_resv_fixture_list(src)
	test_alloc_oom(1)
	overflow := C.vinix_linuxkpi_resv_fixture_reserve(src, u32(-1))
	gate := proc.current_thread().linuxkpi_alloc_fail_after
	test_alloc_oom(-1)
	if overflow != -12 || gate != 1 || C.vinix_linuxkpi_resv_fixture_list(src) != old { return false }
	test_alloc_oom(0)
	failed := C.vinix_linuxkpi_resv_fixture_get(src, 3, unsafe { &resv_test_ledger.vector_count }, unsafe { &resv_test_ledger.vector })
	test_alloc_oom(-1)
	if failed != -12 || resv_test_ledger.vector_count != 0 || resv_test_ledger.vector != unsafe { nil } { return false }
	// First the result vector succeeds, then array-owner allocation fails.
	test_alloc_oom(1)
	single_failed := C.vinix_linuxkpi_resv_fixture_singleton(src, 3, unsafe { &resv_test_ledger.output })
	test_alloc_oom(-1)
	if single_failed != -12 || resv_test_ledger.output != unsafe { nil } { return false }
	for i in 0 .. 3 { if C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[i]) != 2 { return false } }
	if C.vinix_linuxkpi_resv_fixture_reserve(dst, 1) != 0 { return false }
	C.vinix_linuxkpi_resv_fixture_add(dst, resv_test_ledger.leaves[2], 3)
	dst_old := C.vinix_linuxkpi_resv_fixture_list(dst)
	test_alloc_oom(0)
	copy_failed := C.vinix_linuxkpi_resv_fixture_copy(dst, src)
	test_alloc_oom(-1)
	if copy_failed != -12 || C.vinix_linuxkpi_resv_fixture_list(dst) != dst_old
		|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[0]) != 2 { return false }
	C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[0], 0, 0)
	if C.vinix_linuxkpi_resv_fixture_copy(dst, src) != 0
		|| C.vinix_linuxkpi_resv_fixture_list_value(C.vinix_linuxkpi_resv_fixture_list(dst), 0, 0) != 2
		|| C.vinix_linuxkpi_resv_fixture_get(dst, 3, unsafe { &resv_test_ledger.vector_count }, unsafe { &resv_test_ledger.vector }) != 0
		|| resv_test_ledger.vector_count != 2 { return false }
	unsafe {
		if (&voidptr(resv_test_ledger.vector))[0] != resv_test_ledger.leaves[1]
			|| (&voidptr(resv_test_ledger.vector))[1] != resv_test_ledger.leaves[2] { return false }
	}
	resv_vector_put()
	if C.vinix_linuxkpi_resv_fixture_singleton(dst, 1, unsafe { &resv_test_ledger.output }) != 0
		|| resv_test_ledger.output != resv_test_ledger.leaves[1] { return false }
	C.vinix_linuxkpi_dmafence_fixture_put(resv_test_ledger.output)
	resv_test_ledger.output = unsafe { nil }
	if C.vinix_linuxkpi_resv_fixture_singleton(dst, 3, unsafe { &resv_test_ledger.output }) != 0
		|| resv_test_ledger.output == unsafe { nil } || C.vinix_linuxkpi_fct_kind(resv_test_ledger.output) != 1 { return false }
	return true
}
fn resv_restart_empty() bool {
	resv_prepare()
	defer { resv_clear() }
	obj := unsafe { &resv_test_ledger.objects[0] }
	empty := unsafe { &resv_test_ledger.objects[2] }
	iter := unsafe { &resv_test_ledger.cursor }
	if !resv_leaf(0, C.vinix_linuxkpi_dmafence_fixture_context(1), 1)
		|| C.vinix_linuxkpi_resv_fixture_lock(obj, 0) != 0 { return false }
	defer { C.vinix_linuxkpi_resv_fixture_unlock(obj) }
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, 1) != 0 { return false }
	C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[0], 1)
	C.vinix_linuxkpi_resv_fixture_begin(iter, obj, 3)
	resv_test_ledger.cursor_live = true
	if C.vinix_linuxkpi_resv_fixture_step(iter, 2) != resv_test_ledger.leaves[0] { return false }
	old := C.vinix_linuxkpi_resv_fixture_list(obj)
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, u32(C.vinix_linuxkpi_resv_fixture_list_value(old, 1, 0)) + 1) != 0
		|| C.vinix_linuxkpi_resv_fixture_step(iter, 3) != resv_test_ledger.leaves[0]
		|| C.vinix_linuxkpi_resv_fixture_cursor(iter, 1) != 1
		|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[0]) != 3 { return false }
	if C.vinix_linuxkpi_resv_fixture_copy(obj, empty) != 0
		|| C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[0]) != 2 { return false }
	// Native correction: a NULL-list restart drops and clears the old cursor.
	return C.vinix_linuxkpi_resv_fixture_step(iter, 3) == unsafe { nil }
		&& C.vinix_linuxkpi_resv_fixture_step(iter, 3) == unsafe { nil }
		&& C.vinix_linuxkpi_fct_refs(resv_test_ledger.leaves[0]) == 1
}
fn resv_waits_deadlines() bool {
	resv_prepare()
	defer { resv_clear() }
	obj := unsafe { &resv_test_ledger.objects[0] }
	mut active := false
	defer {
		for i in 0 .. resv_test_ledger.count { C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[i], 0, 0) }
		if active { resv_finish(0) }
		test_task_signal(resv_test_ledger.owners[0], 0)
	}
	if C.vinix_linuxkpi_resv_fixture_wait(obj, 3, false, 0) != 1
		|| C.vinix_linuxkpi_resv_fixture_wait(obj, 3, false, 7) != 7
		|| !C.vinix_linuxkpi_resv_fixture_signaled(obj, 3) { return false }
	context := C.vinix_linuxkpi_dmafence_fixture_context(2)
	if !resv_leaf(1, context, 1) || !resv_leaf(1, context + 1, 1)
		|| C.vinix_linuxkpi_resv_fixture_lock(obj, 0) != 0 { return false }
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, 2) != 0 { C.vinix_linuxkpi_resv_fixture_unlock(obj); return false }
	C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[0], 0)
	C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[1], 2)
	C.vinix_linuxkpi_resv_fixture_unlock(obj)
	C.vinix_linuxkpi_resv_fixture_deadline(obj, 0, 123456789)
	if dmafence_test_ledger.deadline != 123456789 || C.vinix_linuxkpi_resv_fixture_signaled(obj, 3)
		|| C.vinix_linuxkpi_resv_fixture_wait(obj, 0, false, 0) != 0 { return false }
	resv_test_ledger.usage = 3
	resv_test_ledger.intr = false
	resv_test_ledger.timeout = 4
	resv_start(0, 3)
	active = true
	resv_finish(0)
	active = false
	if resv_test_ledger.results[0] != 0 { return false }
	resv_test_ledger.intr = true
	resv_test_ledger.timeout = u64(dmafence_test_infinite)
	resv_start(0, 3)
	active = true
	if !resv_parked(0, 1) { return false }
	test_task_signal(resv_test_ledger.owners[0], u64(1) << 14)
	resv_finish(0)
	active = false
	test_task_signal(resv_test_ledger.owners[0], 0)
	if resv_test_ledger.results[0] != -512 { return false }
	resv_test_ledger.intr = false
	resv_test_ledger.timeout = 1000
	resv_start(0, 3)
	active = true
	if !resv_parked(0, 2) { return false }
	C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[0], 0, 0)
	start := resv_clock.nanoseconds()
	for C.vinix_linuxkpi_dmafence_fixture_callbacks(resv_test_ledger.leaves[1]) != 1 {
		if resv_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[1], 0, 0)
	resv_finish(0)
	active = false
	return resv_test_ledger.results[0] > 0 && resv_test_ledger.results[0] <= 1000
		&& C.vinix_linuxkpi_resv_fixture_signaled(obj, 3) && C.vinix_linuxkpi_resv_fixture_wait(obj, 3, false, 0) == 1
}
fn resv_deferred() bool {
	resv_prepare()
	defer { resv_clear() }
	obj := unsafe { &resv_test_ledger.objects[0] }
	empty := unsafe { &resv_test_ledger.objects[2] }
	mut reader := false
	mut barrier := false
	mut locked := false
	defer {
		if locked { C.vinix_linuxkpi_resv_fixture_unlock(obj) }
		katomic.store(mut &resv_test_ledger.reader_release, true)
		if reader { resv_finish(2) }
		if barrier { resv_finish(1) }
	}
	context := C.vinix_linuxkpi_dmafence_fixture_context(2)
	if !resv_leaf(0, context, 1) || !resv_leaf(0, context + 1, 1)
		|| C.vinix_linuxkpi_resv_fixture_lock(obj, 0) != 0 { return false }
	locked = true
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, 2) != 0 { return false }
	for i in 0 .. 2 {
		C.vinix_linuxkpi_resv_fixture_add(obj, resv_test_ledger.leaves[i], u32(i))
		resv_test_ledger.reader_fences[i] = resv_test_ledger.leaves[i]
	}
	katomic.store(mut &resv_test_ledger.reader_held, false)
	katomic.store(mut &resv_test_ledger.reader_release, false)
	resv_test_ledger.reader_check = false
	resv_start(2, 4)
	reader = true
	if !resv_wait(&resv_test_ledger.reader_held) { return false }
	old := resv_test_ledger.reader_list
	C.vinix_linuxkpi_dmafence_fixture_signal(resv_test_ledger.leaves[0], 0, 0)
	if C.vinix_linuxkpi_resv_fixture_reserve(obj, u32(C.vinix_linuxkpi_resv_fixture_list_value(old, 1, 0)) + 1) != 0
		|| C.vinix_linuxkpi_resv_fixture_list(obj) == old
		|| C.vinix_linuxkpi_resv_fixture_copy(obj, empty) != 0 { return false }
	C.vinix_linuxkpi_resv_fixture_unlock(obj)
	locked = false
	for i in 0 .. 2 {
		C.vinix_linuxkpi_dmafence_fixture_put(resv_test_ledger.leaves[i])
		resv_test_ledger.leaves[i] = unsafe { nil }
	}
	resv_test_ledger.reader_check = true
	force := C.vinix_linuxkpi_rcu_test_force_count()
	held := memory.free_bytes()
	resv_start(1, 5)
	barrier = true
	start := resv_clock.nanoseconds()
	for C.vinix_linuxkpi_rcu_test_force_count() == force {
		if resv_clock.nanoseconds() - start >= dmafence_test_timeout_ns { return false }
		sched.reschedule()
	}
	if katomic.load(&resv_test_ledger.done[1]) || memory.free_bytes() != held { return false }
	katomic.store(mut &resv_test_ledger.reader_release, true)
	return resv_wait(&resv_test_ledger.done[2]) && resv_wait(&resv_test_ledger.done[1])
}
fn resv_lifecycle() bool {
	ints := cpu.interrupt_toggle(false)
	mut controller := proc.current_thread()
	affinity := katomic.load(&controller.affinity_mask)
	numa := katomic.load(&controller.numa_node)
	gate := controller.linuxkpi_alloc_fail_after
	cpu.interrupt_toggle(ints)
	mut owners := unsafe { [3]&proc.Thread{} }
	mut created := 0
	defer {
		katomic.store(mut &resv_test_ledger.reader_release, true)
		katomic.store(mut &resv_test_ledger.quit, true)
		for i in 0 .. created { irq_test_join(owners[i]) }
		C.vinix_linuxkpi_rcu_fixture_barrier()
		selftest_free_baseline()
		restore := cpu.interrupt_toggle(false)
		controller.linuxkpi_alloc_fail_after = gate
		katomic.store(mut &controller.numa_node, numa)
		katomic.store(mut &controller.affinity_mask, affinity)
		cpu.interrupt_toggle(restore)
	}
	if !ints || worker_bind(0) != 0 { return false }
	resv_test_ledger = ResvTestLedger{}
	for i in 0 .. 3 {
		mut actor := sched.try_new_kernel_thread(voidptr(resv_actor), voidptr(i)) or { return false }
		proc.pin_thread(actor)
		proc.pin_thread(actor)
		actor.pthread_joinable = 1
		if !sched.enqueue_thread(actor, false) {
			proc.unpin_thread(actor)
			proc.unpin_thread(actor)
			sched.discard_unstarted_thread(actor)
			return false
		}
		owners[i] = actor
		resv_test_ledger.owners[i] = actor
		created++
	}
	for i in 0 .. 3 { if !resv_wait(&resv_test_ledger.ready[i]) { return false } }
	if !resv_allocators() { C.kprintf(c'linuxkpi: DMA reservation allocator case failed\n'); return false }
	if !resv_writer_locking() { C.kprintf(c'linuxkpi: DMA reservation writer case failed\n'); return false }
	if !resv_usage_growth() { C.kprintf(c'linuxkpi: DMA reservation usage/growth case failed\n'); return false }
	if !resv_collection_oom() { C.kprintf(c'linuxkpi: DMA reservation collection/OOM case failed\n'); return false }
	if !resv_restart_empty() { C.kprintf(c'linuxkpi: DMA reservation empty restart case failed\n'); return false }
	if !resv_waits_deadlines() { C.kprintf(c'linuxkpi: DMA reservation wait/deadline case failed\n'); return false }
	if !resv_deferred() { C.kprintf(c'linuxkpi: DMA reservation deferred case failed\n'); return false }
	return true
}
fn dma_resv_native_selftest() bool {
	if cpu_locals.len < 4 || cpu_locals.len > 64 || C.vinix_linuxkpi_resv_fixture_bytes(0) != 48
		|| C.vinix_linuxkpi_resv_fixture_bytes(1) != 48 || C.vinix_linuxkpi_resv_fixture_bytes(2) != 32
		|| C.vinix_linuxkpi_resv_fixture_bytes(3) != 24 { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !resv_lifecycle() { return false }
		C.kprintf(c'linuxkpi: DMA reservation lifecycle warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !resv_lifecycle() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			equal = false
			C.kprintf(c'linuxkpi: DMA reservation heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n',
				i, before.sizes[i], after.sizes[i], before.live[i], after.live[i])
		}
	}
	C.kprintf(c'linuxkpi: DMA reservation fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%d\n', free_before, free_after, int(equal))
	return free_before == free_after && equal && katomic.load(&resv_test_ledger.failures) == 0
}
