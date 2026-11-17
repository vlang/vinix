module main

import os
import gpu
import gpu.agx.alloc

// Model immediate cancellation as a single specifically selected chronological
// removal, independently of production's direct VA-ordered table deletion.
fn (mut model HeapRangeModel) cancel_unpublished(address u64) {
	for index, record in model.records {
		if record.va != address || !record.in_use { continue }
		model.records[index].in_use = false
		model.pending.insert(0, address)
		model.collect_count(1)
		return
	}
}
fn check_cancellation_model() {
	mut cases := 0
	for offset in [u64(0), 1, alloc.gpu_page_size - 1]! { for policy in 0 .. 3 {
		for shape in 0 .. 2 { for reverse in [false, true]! {
			for releases in 0 .. 16 { for cancellations in 0 .. 16 {
				start := alloc.g13_private_start + offset
				end := start + 64 * alloc.gpu_page_size
				mut heap := if policy == 0 { alloc.new_heap_with_explicit_gc('cancel', start, end) }
					else { alloc.new_heap_with_garbage('cancel', start, end, policy == 1) }
				mut model := new_range_model(start, end); model.keep_garbage = policy != 2
				mut addresses := [4]u64{}; mut records := unsafe { [4]&alloc.Allocation{} }
				for i in 0 .. 4 {
					alignment := if shape == 1 && i % 2 == 0 { 4 * alloc.gpu_page_size } else { alloc.gpu_page_size }
					addresses[i] = reserve_checked(mut heap, mut model, u64(i + 1), alignment)
					records[i] = record_at(heap, addresses[i])
				}
				for i in 0 .. 4 { if releases & (1 << i) != 0 { heap.release(addresses[i]); model.release(addresses[i]) } }
				for turn in 0 .. 4 {
					i := if reverse { 3 - turn } else { turn }
					if cancellations & (1 << i) != 0 {
						heap.cancel_unpublished(addresses[i]); model.cancel_unpublished(addresses[i])
						heap.cancel_unpublished(addresses[i])
					}
					check_model_hole_orders(heap, model)
				}
				heap.cancel_unpublished(0)
				assert heap.top == model.top() && heap.allocations.len == model.records.len
				for i in 0 .. 4 {
					released := releases & (1 << i) != 0
					retired := (released && policy == 2) || (!released && cancellations & (1 << i) != 0)
					assert (C.__asan_address_is_poisoned(records[i]) != 0) == retired, 'cancellation must retire only its live unpublished owner'
					if !retired { assert record_at(heap, addresses[i]) == records[i] }
				}
				for i in 0 .. 2 { reserve_checked(mut heap, mut model, u64(i + 1), alloc.gpu_page_size) }
				for record in model.records { heap.release(record.va) }
				heap.gc(); assert heap.allocations.len == 0 && heap.top == start
				unsafe { heap.allocations.free(); model.records.free(); model.pending.free(); model.holes.free() }
				cases++
			} }
		} }
	} }
	assert cases == 9216
	println('AGX cancellation: 9216 independent history/FIFO cases preserve pending owners, hole ranks, padding and live pointers')
}
fn measure_cancellation() {
	mut heap := alloc.new_heap_with_explicit_gc('cancel-measure', alloc.g13_private_start, alloc.g13_private_start + 16 * alloc.gpu_page_size)
	pending_address := heap.alloc(1, 0) or { panic('pending') }; heap.release(pending_address)
	pin := heap.alloc(1, 0) or { panic('pin') }
	for _ in 0 .. 1000 { va := heap.alloc(1, 0) or { panic('warmup') }; heap.cancel_unpublished(va) }
	for round in 0 .. 3 {
		before_blocks, before_bytes := live_heap()
		for _ in 0 .. 10000 { va := heap.alloc(1, 0) or { panic('measured reservation') }; heap.cancel_unpublished(va) }
		after_blocks, after_bytes := live_heap()
		blocks := i64(after_blocks) - i64(before_blocks); bytes := i64(after_bytes) - i64(before_bytes)
		C.printf(c'AGX-CANCEL round=%lld operations=10000 retained_blocks=%lld retained_bytes=%lld\n', round, blocks, bytes)
		assert blocks == 0 && bytes == 0, 'unpublished reservation churn must retain no metadata'
		assert heap.allocations.len == 2 && heap.garbage_count == 1 && heap.garbage_bytes == alloc.gpu_page_size
	}
	heap.release(pin); heap.gc(); unsafe { heap.allocations.free() }
}
fn main() {
	$if agx_cancel_measure ? { measure_cancellation() } $else {
	selected := if os.args.len == 2 { os.args[1] } else { '' }
	if selected != 'rollback' { check_cancellation_model() }
	if selected != 'model' { gpu.check_rollback() }
	}
}
