// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import memory

fn C.__builtin_alloca(uint) voidptr

// Group unwrapped leaves by sequence, with ordered fences newest first.
// Independently completing fences group only with their exact duplicates.
fn merge_before(a &DmaFence, b &DmaFence) bool {
	if a.context != b.context { return a.context < b.context }
	a_instance := fence_sequence_instance(a)
	b_instance := fence_sequence_instance(b)
	return a_instance < b_instance || (a_instance == b_instance && a.seqno > b.seqno)
}

fn merge_sift(items &&DmaFence, root u32, count u32) {
	mut parent := root
	for u64(parent) * 2 + 1 < count {
		mut child := parent * 2 + 1
		unsafe {
			if child + 1 < count && merge_before(items[child], items[child + 1]) { child++ }
			if !merge_before(items[parent], items[child]) { return }
			tmp := items[parent]; items[parent] = items[child]; items[child] = tmp
		}
		parent = child
	}
}

fn merge_dedup(items &&DmaFence, count u32) u32 {
	mut root := count / 2
	for root > 0 { root--; merge_sift(items, root, count) }
	mut end := count
	for end > 1 {
		end--
		unsafe { tmp := items[0]; items[0] = items[end]; items[end] = tmp }
		merge_sift(items, 0, end)
	}
	mut unique := u32(1)
	for index := u32(1); index < count; index++ {
		unsafe { if !same_fence_sequence(items[index], items[unique - 1]) { items[unique] = items[index]; unique++ } }
	}
	return unique
}

fn merge_stub(timestamp u64) ?&DmaFence {
	mut fence := new_private_stub(timestamp) or { return none }
	fence.merge_reserved = true
	return fence
}

// The caller owns a new stub/array reservation until add_chain_point retains
// it. Existing single pending leaves are borrowed and never reclaimed here.
pub fn unwrap_merge(head &DmaFence) ?&DmaFence {
	return unwrap_merge_roots(head, unsafe { nil })
}

pub struct SyncFileMerge {
pub:
	fence &DmaFence = unsafe { nil }
	owned bool
}

// The caller holds both source descriptors while flattening their roots.
// The new descriptor owns any allocated result, including a completed stub.
pub fn merge_sync_file_fences(first &DmaFence, second &DmaFence) ?SyncFileMerge {
	fence := unwrap_merge_roots(first, second) or { return none }
	owned := fence.merge_reserved
	if owned { adopt_sync_file_snapshot(fence) }
	return SyncFileMerge{fence: fence, owned: owned}
}

fn unwrap_merge_roots(first &DmaFence, second &DmaFence) ?&DmaFence {
	heads := [first, second]!
	mut cursor := unsafe { &FenceUnwrap(C.__builtin_alloca(sizeof(FenceUnwrap))) }
	mut count := u32(0)
	mut timestamp := u64(0)
	mut single := &DmaFence(unsafe { nil })
	for head in heads {
		mut leaf := unwrap_first(head, cursor)
		for leaf != unsafe { nil } {
			if !is_signaled(leaf) {
				if count == u32(0x7fff_ffff) { return none }
				count++
				single = unsafe { leaf }
			} else {
				info := identity(leaf)
				if info.timestamp_ns > timestamp { timestamp = info.timestamp_ns }
			}
			leaf = unwrap_next(cursor)
		}
	}
	if count == 0 { return merge_stub(timestamp) }
	if count == 1 { return single }
	storage := memory.malloc_packed_fallible(u64(count) * sizeof(voidptr))
	if storage == unsafe { nil } { return none }
	items := unsafe { &&DmaFence(storage) }
	mut owned := true
	defer { if owned { memory.free(storage) } }
	count = 0
	for head in heads {
		mut leaf := unwrap_first(head, cursor)
		for leaf != unsafe { nil } {
			if !is_signaled(leaf) { unsafe { items[count] = leaf }; count++ }
			else {
				info := identity(leaf)
				if info.timestamp_ns > timestamp { timestamp = info.timestamp_ns }
			}
			leaf = unwrap_next(cursor)
		}
	}
	if count == 0 { return merge_stub(timestamp) }
	if count == 1 { return unsafe { items[0] } }
	count = merge_dedup(items, count)
	if count == 1 { return unsafe { items[0] } }
	result := new_merge_array(items, count) or { return none }
	owned = false
	return result
}
