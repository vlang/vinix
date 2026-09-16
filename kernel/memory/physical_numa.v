// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Node-aware physical allocation.
//
// The bitmap in physical.v describes the whole machine as one pool, which is
// the right answer right up until the machine has two memory controllers. On a
// multi-socket board a load from the far socket's RAM costs noticeably more
// than one from the near socket's, so a page handed to a thread should come
// from the node that thread is running on whenever it can.
//
// Rather than split the bitmap, this file adds a classification of it: each
// node declares which physical page ranges it owns, and an allocation for a
// node scans only those. The single global bitmap and its lock are unchanged,
// so a machine with one node -- every uniprocessor and every single-socket
// desktop -- takes exactly the path it always did. `pmm_numa_active` gates
// every addition here and is only set once more than one node was found.
//
// The topology itself is discovered by the numa module, which calls the
// registration functions below once and then leaves them alone.
@[has_globals; manualfree]
module memory

import lib

pub const pmm_max_nodes = 16

// A node contributes one range per firmware memory-affinity entry. Two per
// node is the usual shape (a low hole and the rest); eight leaves room for a
// board that reports its RAM in pieces.
pub const pmm_max_node_ranges = pmm_max_nodes * 8

__global (
	// Only set once a real multi-node topology was published. Everything in
	// this file is a no-op until then, including the accounting hooks that
	// physical.v calls from its allocation and free paths.
	pmm_numa_active     = false
	pmm_numa_node_count = int(0)
	// Page-index ranges, [start, end), tagged with the node that owns them.
	// A flat table rather than a list per node: it is read far more often than
	// written, and the whole thing is a few hundred bytes.
	pmm_node_range_count = int(0)
	pmm_node_range_start [pmm_max_node_ranges]u64
	pmm_node_range_end   [pmm_max_node_ranges]u64
	pmm_node_range_node  [pmm_max_node_ranges]int
	// Where the last allocation for this node left off, so consecutive
	// allocations do not rescan the pages they just took.
	pmm_node_hint [pmm_max_nodes]u64
	// Usable pages the node owns, and how many of them are handed out.
	pmm_node_total [pmm_max_nodes]u64
	pmm_node_used  [pmm_max_nodes]u64
	// For each node, the nodes to try in increasing distance, itself first.
	// A node which has run out should reach for the nearest memory next, not
	// for whichever range the global scan happens to walk into.
	pmm_node_fallback     [pmm_max_nodes * pmm_max_nodes]int
	pmm_node_fallback_len [pmm_max_nodes]int
)

// How many pages the bitmap covers. The numa module needs this to describe a
// machine that declared no topology at all as one node holding everything.
pub fn pmm_page_count() u64 {
	return pmm_avl_page_count
}

// Declare that [base, base + length) belongs to `node`. Called once per
// firmware memory-affinity entry, before pmm_enable_numa(). Pages already
// handed out inside the range -- the bitmap and the refcount array live in one
// -- are counted as used straight away, so a per-node free figure is exact
// from the first time anybody asks for it.
pub fn pmm_register_node_range(node int, base u64, length u64) bool {
	if node < 0 || node >= pmm_max_nodes || length == 0 {
		return false
	}
	if pmm_node_range_count == pmm_max_node_ranges {
		return false
	}
	// Saturate rather than wrap: a node which claims "everything from zero"
	// passes a length that would overflow the sum.
	mut last := u64(-1)
	if length <= u64(-1) - base {
		last = base + length
	}
	mut start := lib.div_roundup(base, page_size)
	mut end := last / page_size
	if end > pmm_avl_page_count {
		end = pmm_avl_page_count
	}
	if start >= end {
		return false
	}

	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	index := pmm_node_range_count
	pmm_node_range_start[index] = start
	pmm_node_range_end[index] = end
	pmm_node_range_node[index] = node
	pmm_node_range_count++

	// Only pages the PMM can actually hand out are this node's to report. A
	// page whose bit is set but whose refcount is zero was never usable RAM:
	// pmm_init fills the bitmap with ones and only clears what the memory map
	// declared, so that combination is a hole, not memory in use.
	for page := start; page < end; page++ {
		if !lib.bittest(pmm_bitmap, page) {
			pmm_node_total[node]++
		} else if unsafe { (&u32(pmm_refcounts))[page] } != 0 {
			pmm_node_total[node]++
			pmm_node_used[node]++
		}
	}
	if pmm_node_hint[node] == 0 {
		pmm_node_hint[node] = start
	}
	return true
}

// Append `target` to the order `node` tries when it allocates. The numa module
// calls this in increasing distance, starting with the node itself.
pub fn pmm_add_node_fallback(node int, target int) bool {
	if node < 0 || node >= pmm_max_nodes || target < 0 || target >= pmm_max_nodes {
		return false
	}
	if pmm_node_fallback_len[node] >= pmm_max_nodes {
		return false
	}
	pmm_node_fallback[node * pmm_max_nodes + pmm_node_fallback_len[node]] = target
	pmm_node_fallback_len[node]++
	return true
}

// Start honouring node preferences. Until this is called the allocator behaves
// exactly as it did before the topology was read.
pub fn pmm_enable_numa(node_count int) {
	if node_count <= 1 || pmm_node_range_count == 0 {
		return
	}
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	pmm_numa_node_count = node_count
	pmm_numa_active = true
}

pub fn pmm_numa_enabled() bool {
	return pmm_numa_active
}

// Which node owns a physical page, or -1 when no node claimed it. Firmware
// need not describe every byte it reports as usable, and a page nobody claimed
// is still perfectly good memory.
pub fn pmm_node_of(phys u64) int {
	if !pmm_numa_active {
		return -1
	}
	return node_of_page(phys / page_size)
}

pub fn pmm_node_total_pages(node int) u64 {
	if node < 0 || node >= pmm_max_nodes {
		return 0
	}
	if !pmm_numa_active {
		return if node == 0 { pmm_total_pages } else { u64(0) }
	}
	return pmm_node_total[node]
}

pub fn pmm_node_free_pages(node int) u64 {
	if node < 0 || node >= pmm_max_nodes {
		return 0
	}
	if !pmm_numa_active {
		return if node == 0 { free_bytes() / page_size } else { u64(0) }
	}
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	if pmm_node_used[node] >= pmm_node_total[node] {
		return 0
	}
	return pmm_node_total[node] - pmm_node_used[node]
}

// ── Internals; every one of these runs with pmm_lock held ────────────────────

fn node_of_page(page u64) int {
	for i := 0; i < pmm_node_range_count; i++ {
		if page >= pmm_node_range_start[i] && page < pmm_node_range_end[i] {
			return pmm_node_range_node[i]
		}
	}
	return -1
}

// Charge a run of pages to whichever nodes own them. physical.v calls this
// from both allocation paths, so the per-node figures stay right even when the
// caller expressed no preference at all.
fn charge_node_pages(page u64, count u64) {
	if !pmm_numa_active {
		return
	}
	for i := page; i < page + count; i++ {
		node := node_of_page(i)
		if node >= 0 {
			pmm_node_used[node]++
		}
	}
}

fn discharge_node_page(page u64) {
	if !pmm_numa_active {
		return
	}
	node := node_of_page(page)
	if node >= 0 && pmm_node_used[node] > 0 {
		pmm_node_used[node]--
	}
}

// Scan the ranges of one node only. Resumes from the node's hint and wraps
// once within each range, which is what the global scan does across the bitmap.
fn alloc_within_node(count u64, node int) voidptr {
	for i := 0; i < pmm_node_range_count; i++ {
		if pmm_node_range_node[i] != node {
			continue
		}
		start := pmm_node_range_start[i]
		end := pmm_node_range_end[i]
		mut from := pmm_node_hint[node]
		if from < start || from >= end {
			from = start
		}
		mut ret := inner_alloc_range(count, from, end)
		if ret == 0 && from != start {
			ret = inner_alloc_range(count, start, from)
		}
		if ret != 0 {
			first := u64(ret) / page_size
			pmm_node_hint[node] = first + count
			pmm_node_used[node] += count
			return ret
		}
	}
	return 0
}

// Take `count` pages for `node`. With `strict` set the answer comes from that
// node or not at all, which is what mbind(2)'s MPOL_BIND promises; otherwise
// the nodes are tried in increasing distance.
fn try_alloc_on_node_nozero(count u64, node int, strict bool) voidptr {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	if !pmm_numa_active || node < 0 || node >= pmm_max_nodes {
		return unsafe { nil }
	}

	mut ret := alloc_within_node(count, node)
	if ret == 0 && !strict {
		for step := 0; step < pmm_node_fallback_len[node]; step++ {
			target := pmm_node_fallback[node * pmm_max_nodes + step]
			if target == node {
				continue
			}
			ret = alloc_within_node(count, target)
			if ret != 0 {
				break
			}
		}
	}
	if ret == 0 {
		return unsafe { nil }
	}
	free_pages -= count
	return ret
}

// ── The node-aware allocator proper ─────────────────────────────────────────

// Like pmm_alloc_nozero_fallible, but preferring `node`. Returns nil rather
// than panicking: every caller of these is serving a userspace request that
// can be told ENOMEM.
pub fn pmm_alloc_nozero_on_node(count u64, node int, strict bool) voidptr {
	if !pmm_numa_active || node < 0 {
		if strict {
			// The caller asked for memory from a node this machine does not
			// have. On a machine with no topology, node 0 is all of it.
			if node > 0 {
				return unsafe { nil }
			}
		}
		return pmm_alloc_nozero_fallible(count)
	}

	mut ret := try_alloc_on_node_nozero(count, node, strict)
	if ret == unsafe { nil } && !strict {
		ret = try_alloc_nozero(count)
	}
	if ret == unsafe { nil } {
		reclaim_pages(count)
		ret = try_alloc_on_node_nozero(count, node, strict)
		if ret == unsafe { nil } && !strict {
			ret = try_alloc_nozero(count)
		}
	}
	return ret
}

pub fn pmm_alloc_on_node(count u64, node int, strict bool) voidptr {
	ret := pmm_alloc_nozero_on_node(count, node, strict)
	if ret == unsafe { nil } {
		return unsafe { nil }
	}
	// Pages are always handed out zeroed, for the same reason as pmm_alloc.
	unsafe {
		mut ptr := &u64(u64(ret) + higher_half)
		for i := u64(0); i < (count * page_size) / 8; i++ {
			ptr[i] = 0
		}
	}
	return ret
}
