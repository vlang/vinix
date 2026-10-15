// SPDX-License-Identifier: MIT
// Native reservation algorithms over original intrusive tagged-list storage.
@[translated]
module compatcore

#include "linuxkpi_dma_resv_v_primitives.h"

struct C.vdr_obj {
mut:
	owner  i64
	fences &C.vdr_list
}

struct C.vdr_list {
mut:
	num_fences u32
	max_fences u32
	table      &voidptr
}

struct C.vdr_iter {
mut:
	obj          voidptr
	usage        u32
	fence        voidptr
	fence_usage  u32
	position     u32
	fences       &C.vdr_list
	num_fences   u32
	is_restarted bool
}

fn C.vdr_load_ptr(voidptr) voidptr
fn C.vdr_store_ptr(voidptr, voidptr, i32)
fn C.vdr_load32(&u32) u32
fn C.vdr_store32(&u32, u32)
fn C.vdr_publish_fence()
fn C.vdr_lock_init(voidptr)
fn C.vdr_lock_fini(voidptr)
fn C.vdr_get(voidptr) voidptr
fn C.vdr_put(voidptr)
fn C.vdr_get_rcu(voidptr) voidptr
fn C.vdr_later_or_same(voidptr, voidptr) bool
fn C.vdr_container(voidptr) bool
fn C.vdr_read_lock()
fn C.vdr_read_unlock()
fn C.kmalloc_size_roundup(usize) usize
fn C.krealloc_array(voidptr, usize, usize, u32) voidptr

fn resv_object(storage voidptr) &C.vdr_obj {
	require(!is_null(storage) && usize(storage) % 8 == 0)
	return unsafe { &C.vdr_obj(storage) }
}

fn resv_usage_valid(usage u32) { require(usage <= 3) }

fn resv_writer(storage voidptr) &C.vdr_obj {
	obj := resv_object(storage)
	task := C.vkp_current()
	unsafe { require(!is_null(task) && C.vkw_load_owner(&obj.owner, 2) == i64(task)) }
	return obj
}

fn resv_cursor(storage voidptr) &C.vdr_iter {
	require(!is_null(storage) && usize(storage) % 8 == 0)
	unsafe {
		cursor := &C.vdr_iter(storage)
		resv_object(cursor.obj)
		resv_usage_valid(cursor.usage)
		return cursor
	}
}

fn resv_list(obj &C.vdr_obj) &C.vdr_list {
	return unsafe { &C.vdr_list(C.vdr_load_ptr(&obj.fences)) }
}

fn resv_entry(list &C.vdr_list, index u32) usize {
	return unsafe { usize(C.vdr_load_ptr(&list.table[index])) }
}

fn resv_set(list &C.vdr_list, index u32, fence voidptr, usage u32) {
	unsafe { C.vdr_store_ptr(&list.table[index], voidptr(usize(fence) | usize(usage)), 0) }
}

fn resv_alloc(capacity u32) &C.vdr_list {
	if usize(capacity) > (usize(-1) - sizeof(C.vdr_list)) / sizeof(voidptr) {
		return unsafe { nil }
	}
	size := C.kmalloc_size_roundup(sizeof(C.vdr_list) + usize(capacity) * sizeof(voidptr))
	unsafe {
		list := &C.vdr_list(C.kmalloc(size, 3264))
		if is_null(list) { return nil }
		list.max_fences = u32((size - sizeof(C.vdr_list)) / sizeof(voidptr))
		return list
	}
}

fn resv_free(list &C.vdr_list) {
	unsafe {
		if is_null(list) { return }
		for i := u32(0); i < list.num_fences; i++ {
			C.vdr_put(voidptr(resv_entry(list, i) & ~usize(3)))
		}
		C.vkr_kvfree_call_rcu(list, list)
	}
}

fn resv_begin(cursor &C.vdr_iter, obj voidptr, usage u32) {
	unsafe {
		cursor.obj = obj
		cursor.usage = usage
		cursor.fence = nil
	}
}

fn resv_end(cursor &C.vdr_iter) {
	unsafe { C.vdr_put(cursor.fence) }
}

@[export: 'vdr_init']
pub fn dma_resv_init(storage voidptr) {
	obj := resv_object(storage)
	C.vdr_lock_init(obj)
	unsafe { C.vdr_store_ptr(&obj.fences, nil, 0) }
}

@[export: 'vdr_fini']
pub fn dma_resv_fini(storage voidptr) {
	obj := resv_object(storage)
	unsafe {
		require(C.vkw_load_owner(&obj.owner, 2) == 0)
		resv_free(resv_list(obj))
		C.vdr_lock_fini(obj)
	}
}

@[export: 'vdr_reserve']
pub fn dma_resv_reserve(storage voidptr, additional u32) i32 {
	unsafe {
		obj := resv_writer(storage)
		old := resv_list(obj)
		mut capacity := u32(4)
		if !is_null(old) && old.max_fences != 0 {
			count := C.vdr_load32(&old.num_fences)
			if additional > u32(-1) - count { return -12 }
			needed := count + additional
			if needed <= old.max_fences { return 0 }
			if old.max_fences > u32(-1) / 2 { return -12 }
			capacity = old.max_fences * 2
			if needed > capacity { capacity = needed }
		} else {
			for capacity < additional {
				if capacity > u32(-1) / 2 { return -12 }
				capacity *= 2
			}
		}
		fresh := resv_alloc(capacity)
		if is_null(fresh) { return -12 }
		mut active := u32(0)
		mut retired := capacity
		count := if is_null(old) { u32(0) } else { C.vdr_load32(&old.num_fences) }
		for i := u32(0); i < count; i++ {
			tag := resv_entry(old, i)
			fence := voidptr(tag & ~usize(3))
			if fence_is_signaled(&C.vdf_fence(fence), false) {
				retired--
				resv_set(fresh, retired, fence, 0)
			} else {
				resv_set(fresh, active, fence, u32(tag & 3))
				active++
			}
		}
		fresh.num_fences = active
		C.vdr_store_ptr(&obj.fences, fresh, 3)
		if is_null(old) { return 0 }
		for i := retired; i < capacity; i++ { C.vdr_put(voidptr(resv_entry(fresh, i))) }
		C.vkr_kvfree_call_rcu(old, old)
		return 0
	}
}

@[export: 'vdr_add']
pub fn dma_resv_add(storage voidptr, fence voidptr, usage u32) {
	unsafe {
		resv_usage_valid(usage)
		obj := resv_writer(storage)
		require(!is_null(fence) && usize(fence) % 8 == 0)
		list := resv_list(obj)
		require(!is_null(list))
		count := C.vdr_load32(&list.num_fences)
		require(count <= list.max_fences)
		if C.vdr_container(fence) { C.vkp_warn(c'dma_resv_add_fence container', 0) }
		for i := u32(0); i < count; i++ {
			tag := resv_entry(list, i)
			old := voidptr(tag & ~usize(3))
			if ((&C.vdf_fence(old)).context == (&C.vdf_fence(fence)).context && u32(tag & 3) >= usage && C.vdr_later_or_same(fence, old))
				|| fence_is_signaled(&C.vdf_fence(old), false) {
				C.vdr_get(fence)
				resv_set(list, i, fence, usage)
				C.vdr_put(old)
				return
			}
		}
		require(count < list.max_fences)
		C.vdr_get(fence)
		resv_set(list, count, fence, usage)
		C.vdr_publish_fence()
		C.vdr_store32(&list.num_fences, count + 1)
	}
}

@[export: 'vdr_replace']
pub fn dma_resv_replace(storage voidptr, context u64, replacement voidptr, usage u32) {
	unsafe {
		resv_usage_valid(usage)
		obj := resv_writer(storage)
		require(!is_null(replacement) && usize(replacement) % 8 == 0)
		list := resv_list(obj)
		if is_null(list) { return }
		for i := u32(0); i < C.vdr_load32(&list.num_fences); i++ {
			old := voidptr(resv_entry(list, i) & ~usize(3))
			if (&C.vdf_fence(old)).context != context { continue }
			resv_set(list, i, C.vdr_get(replacement), usage)
			C.vdr_put(old)
		}
	}
}

fn resv_restart(cursor &C.vdr_iter) {
	unsafe {
		cursor.position = 0
		cursor.num_fences = 0
		cursor.fences = resv_list(resv_object(cursor.obj))
		if !is_null(cursor.fences) {
			cursor.num_fences = C.vdr_load32(&cursor.fences.num_fences)
		} else {
			// A restart to NULL must drop the previous cursor owner, otherwise
			// original walk's early return repeats that old fence forever.
			C.vdr_put(cursor.fence)
			cursor.fence = nil
		}
		cursor.is_restarted = true
	}
}

fn resv_walk_unlocked(cursor &C.vdr_iter) {
	unsafe {
		// Separate read sections can span a grace period and allocator reuse.
		// The same address can then name a new list with fewer active entries.
		// Within this read section a live list's count only grows.
		if !is_null(cursor.fences) && C.vdr_load32(&cursor.fences.num_fences) < cursor.num_fences {
			resv_restart(cursor)
		}
		if is_null(cursor.fences) { return }
		for {
			C.vdr_put(cursor.fence)
			cursor.fence = nil
			if cursor.position >= cursor.num_fences { return }
			tag := resv_entry(cursor.fences, cursor.position)
			cursor.position++
			cursor.fence_usage = u32(tag & 3)
			cursor.fence = C.vdr_get_rcu(voidptr(tag & ~usize(3)))
			if is_null(cursor.fence) {
				resv_restart(cursor)
				continue
			}
			if !fence_is_signaled(&C.vdf_fence(cursor.fence), false) && cursor.usage >= cursor.fence_usage {
				return
			}
		}
	}
}

@[export: 'vdr_iter_first_unlocked']
pub fn dma_resv_iter_first_unlocked(storage voidptr) voidptr {
	unsafe {
		cursor := resv_cursor(storage)
		C.vdr_read_lock()
		for {
			resv_restart(cursor)
			resv_walk_unlocked(cursor)
			if usize(resv_list(resv_object(cursor.obj))) == usize(cursor.fences) { break }
		}
		C.vdr_read_unlock()
		return cursor.fence
	}
}

@[export: 'vdr_iter_next_unlocked']
pub fn dma_resv_iter_next_unlocked(storage voidptr) voidptr {
	unsafe {
		cursor := resv_cursor(storage)
		C.vdr_read_lock()
		cursor.is_restarted = false
		mut restart := usize(resv_list(resv_object(cursor.obj))) != usize(cursor.fences)
		for {
			if restart { resv_restart(cursor) }
			resv_walk_unlocked(cursor)
			restart = true
			if usize(resv_list(resv_object(cursor.obj))) == usize(cursor.fences) { break }
		}
		C.vdr_read_unlock()
		return cursor.fence
	}
}

@[export: 'vdr_iter_first']
pub fn dma_resv_iter_first(storage voidptr) voidptr {
	unsafe {
		cursor := resv_cursor(storage)
		obj := resv_writer(cursor.obj)
		cursor.position = 0
		cursor.fences = resv_list(obj)
		fence := dma_resv_iter_next(cursor)
		cursor.is_restarted = true
		return fence
	}
}

@[export: 'vdr_iter_next']
pub fn dma_resv_iter_next(storage voidptr) voidptr {
	unsafe {
		cursor := resv_cursor(storage)
		resv_writer(cursor.obj)
		cursor.is_restarted = false
		for {
			if is_null(cursor.fences) || cursor.position >= C.vdr_load32(&cursor.fences.num_fences) {
				return nil
			}
			tag := resv_entry(cursor.fences, cursor.position)
			cursor.position++
			cursor.fence_usage = u32(tag & 3)
			if cursor.fence_usage <= cursor.usage { return voidptr(tag & ~usize(3)) }
		}
	}
}

@[export: 'vdr_copy']
pub fn dma_resv_copy(dst_storage voidptr, src_storage voidptr) i32 {
	mut cursor := C.vdr_iter{}
	iterator := unsafe { &cursor }
	unsafe {
		dst := resv_writer(dst_storage)
		resv_object(src_storage)
		resv_begin(iterator, src_storage, 3)
		mut list := &C.vdr_list(nil)
		mut fence := dma_resv_iter_first_unlocked(iterator)
		for !is_null(fence) {
			if cursor.is_restarted {
				resv_free(list)
				list = resv_alloc(cursor.num_fences)
				if is_null(list) {
					resv_end(iterator)
					return -12
				}
				list.num_fences = 0
			}
			C.vdr_get(fence)
			resv_set(list, list.num_fences, fence, cursor.fence_usage)
			list.num_fences++
			fence = dma_resv_iter_next_unlocked(iterator)
		}
		resv_end(iterator)
		old := resv_list(dst)
		C.vdr_store_ptr(&dst.fences, list, 3)
		resv_free(old)
		return 0
	}
}

@[export: 'vdr_get_fences']
pub fn dma_resv_get_fences(storage voidptr, usage u32, count &u32, output &voidptr) i32 {
	mut cursor := C.vdr_iter{}
	iterator := unsafe { &cursor }
	unsafe {
		resv_object(storage)
		resv_usage_valid(usage)
		require(!is_null(count) && usize(count) % 4 == 0 && !is_null(output) && usize(output) % 8 == 0)
		*count = 0
		*output = nil
		resv_begin(iterator, storage, usage)
		mut fence := dma_resv_iter_first_unlocked(iterator)
		for !is_null(fence) {
			if cursor.is_restarted {
				mut fresh := voidptr(nil)
				if cursor.num_fences != u32(-1) && usize(cursor.num_fences + 1) <= usize(-1) / sizeof(voidptr) {
					for *count != 0 {
						(*count)--
						C.vdr_put((&voidptr(*output))[*count])
					}
					fresh = C.krealloc_array(*output, usize(cursor.num_fences + 1), sizeof(voidptr), 3264)
				}
				if is_null(fresh) {
					for *count != 0 {
						(*count)--
						C.vdr_put((&voidptr(*output))[*count])
					}
					C.kfree(*output)
					*output = nil
					resv_end(iterator)
					return -12
				}
				*output = fresh
			}
			(&voidptr(*output))[*count] = C.vdr_get(fence)
			(*count)++
			fence = dma_resv_iter_next_unlocked(iterator)
		}
		resv_end(iterator)
		return 0
	}
}

@[export: 'vdr_get_singleton']
pub fn dma_resv_get_singleton(storage voidptr, usage u32, output &voidptr) i32 {
	unsafe {
		resv_object(storage)
		resv_usage_valid(usage)
		require(!is_null(output) && usize(output) % 8 == 0)
		mut count := u32(0)
		mut vector := voidptr(nil)
		result := dma_resv_get_fences(storage, usage, &count, &vector)
		if result != 0 { return result }
		if count == 0 {
			*output = nil
			return 0
		}
		if count == 1 {
			*output = (&voidptr(vector))[0]
			C.kfree(vector)
			return 0
		}
		mut aggregate := voidptr(nil)
		if count <= 0x7fffffff {
			aggregate = dma_fence_array_create(i32(count), vector, dma_fence_context_alloc(1), 1, false)
		}
		if is_null(aggregate) {
			for count != 0 {
				count--
				C.vdr_put((&voidptr(vector))[count])
			}
			C.kfree(vector)
			return -12
		}
		*output = aggregate
		return 0
	}
}

@[export: 'vdr_wait']
pub fn dma_resv_wait(storage voidptr, usage u32, intr bool, timeout u64) i64 {
	mut cursor := C.vdr_iter{}
	iterator := unsafe { &cursor }
	unsafe {
		resv_object(storage)
		resv_usage_valid(usage)
		mut remaining := timeout
		mut result := if timeout == 0 { i64(1) } else { i64(timeout) }
		resv_begin(iterator, storage, usage)
		mut fence := dma_resv_iter_first_unlocked(iterator)
		for !is_null(fence) {
			result = dma_fence_wait_timeout(fence, intr, i64(remaining))
			if result <= 0 { break }
			if remaining != 0 { remaining = u64(result) }
			fence = dma_resv_iter_next_unlocked(iterator)
		}
		resv_end(iterator)
		return result
	}
}

@[export: 'vdr_deadline']
pub fn dma_resv_deadline(storage voidptr, usage u32, deadline i64) {
	mut cursor := C.vdr_iter{}
	iterator := unsafe { &cursor }
	unsafe {
		resv_object(storage)
		resv_usage_valid(usage)
		resv_begin(iterator, storage, usage)
		mut fence := dma_resv_iter_first_unlocked(iterator)
		for !is_null(fence) {
			dma_fence_set_deadline(fence, deadline)
			fence = dma_resv_iter_next_unlocked(iterator)
		}
		resv_end(iterator)
	}
}

@[export: 'vdr_test_signaled']
pub fn dma_resv_test_signaled(storage voidptr, usage u32) bool {
	mut cursor := C.vdr_iter{}
	iterator := unsafe { &cursor }
	unsafe {
		resv_object(storage)
		resv_usage_valid(usage)
		resv_begin(iterator, storage, usage)
		mut signaled := false
		if is_null(dma_resv_iter_first_unlocked(iterator)) { signaled = true }
		resv_end(iterator)
		return signaled
	}
}
