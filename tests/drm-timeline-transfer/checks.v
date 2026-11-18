// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import memory
import proc
import sched
import time
import usercopy

__global tt_merged [16]&syncobj.DmaFence
__global tt_count = 0
__global tt_complete &syncobj.DmaFence = unsafe { nil }
__global tt_complete_other &syncobj.DmaFence = unsafe { nil }

fn tt_track(fence &syncobj.DmaFence) {
	if syncobj.is_array_for_checks(fence) || syncobj.identity(fence).kind == .stub {
		assert tt_count < tt_merged.len
		tt_merged[tt_count] = unsafe { fence }; tt_count++
	}
}

fn tt_retire() {
	for index in 0 .. wait_fixture_fence_count { syncobj.signal(wait_fixture_fences[index]) }
	for index in 0 .. tt_count { syncobj.dispose_merged_for_checks(tt_merged[index]); tt_merged[index] = unsafe { nil } }
	tt_count = 0
	tt_complete = unsafe { nil }; tt_complete_other = unsafe { nil }
	bt_retire()
}

fn tt_retire_during_allocation() {
	syncobj.signal_error(tt_complete, -19)
	if tt_complete_other != unsafe { nil } { syncobj.signal_error(tt_complete_other, -5) }
}

fn check_independent_queue_transfer() {
	for sequence in [[u64(10), 11]!, [u64(10), 10]!, [u64(0xffff_ffff), 0]!]! {
		for reverse in [false, true]! {
			proc.reset()
			sched.reset(unsafe { nil })
			source := make_object(0)
			destination := make_object(0)
			context := syncobj.new_queue_context() or { panic('queue fence context') }
			first := remember_fence(syncobj.new_queue_fence(7, sequence[0], context))
			second := remember_fence(syncobj.new_queue_fence(7, sequence[1], context))
			tw_chain(source, first, 1)
			tw_chain(source, second, 2)
			tw_chain(source, first, 3)
			mut request := ioctl.DrmSyncobjTransfer{
				src_handle: source.handle
				dst_handle: destination.handle
				dst_point: 9
			}
			assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == 0
			head := remember_fence(current(destination))
			payload := syncobj.chain_contained(head)
			tt_track(payload)
			assert syncobj.array_count_for_checks(payload) == 2, 'timeline transfer must retain both independent fences once'
			assert !syncobj.is_signaled(head)
			syncobj.signal(if reverse { second } else { first })
			assert !syncobj.is_signaled(head)
			assert syncobj.query_timeline_point(destination, false) == 0
			syncobj.signal(if reverse { first } else { second })
			assert syncobj.is_signaled(head)
			assert syncobj.query_timeline_point(destination, false) == 9
			tt_retire()
		}
	}
	println('DRM timeline TRANSFER: independent same-queue fences survive merging with either notification order, equal or wrapping sequences, and exact duplicates.')
}

pub fn run_timeline_transfer_checks() {
	memory.reset(); memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	proc.reset(); sched.reset(unsafe { nil })
	syncobj.check_merge_array_protocol(); syncobj.check_large_merge_arrays(); assert memory.outstanding() == 0
	check_independent_queue_transfer()
	mut cases := 0
	for count in [1, 2, 3, 8]! { for duplicate in [false, true]! { for done in [false, true]! {
		proc.reset(); sched.reset(unsafe { nil })
		source := make_object(0); destination := make_object(0)
		mut leaves := unsafe { [8]&syncobj.DmaFence{} }
		for index in 0 .. count {
			leaves[index] = make_fence()
			unsafe { leaves[index].context = if duplicate { u64(3) } else { u64(count - index) }; leaves[index].seqno = u64(index + 1) }
			if done { time.advance(); syncobj.signal_error(leaves[index], -5) }
			tw_chain(source, leaves[index], u64(index + 1))
		}
		before := memory.outstanding()
		// Every allocation failure leaves destination empty and all private
		// merge storage gone, including a chain reservation after array/stub.
		allocations := if done { 2 } else if count == 1 { 1 } else if duplicate { 2 } else { 3 }
		for failure_index in 0 .. allocations {
			mut request := ioctl.DrmSyncobjTransfer{src_handle: source.handle, dst_handle: destination.handle, dst_point: 9}
			memory.fail_in(failure_index)
			assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == -12
			assert memory.outstanding() == before, 'unpublished merge owners must unwind'
			if _ := syncobj.get_fence(destination) { panic('failure published destination') }
			cases++
		}
		mut request := ioctl.DrmSyncobjTransfer{src_handle: source.handle, dst_handle: destination.handle, dst_point: 9}
		assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == 0
		head := remember_fence(current(destination)); payload := syncobj.chain_contained(head); tt_track(payload)
		assert syncobj.query_timeline_point(destination, true) == 9
		assert syncobj.array_count_for_checks(payload) == if done || duplicate { u32(1) } else { u32(count) }
		if done {
			assert syncobj.identity(payload).kind == .stub && syncobj.get_error(payload) == 0
			assert syncobj.snapshot(payload).timestamp_ns == syncobj.snapshot(leaves[count - 1]).timestamp_ns
		} else if duplicate { assert payload == leaves[count - 1], 'equal contexts keep greatest unsigned seqno' }
		else if count > 1 {
			for index in 0 .. count { assert syncobj.array_child_for_checks(payload, u32(index)).context == u64(index + 1) }
		}
		// Sync-file info unwraps the array rather than reporting a container.
		mut header := ioctl.SyncFileInfo{}
		mut details := [8]ioctl.SyncFenceInfo{}
		prepare_info(unsafe { &header }, unsafe { &details[0] }, u32(count))
		usercopy.allow_output(unsafe { u64(&details[0]) }, sizeof(details))
		assert sync_file_info_ioctl(head, unsafe { u64(&header) }, unsafe { nil }) == 0
		assert header.num_fences == syncobj.array_count_for_checks(payload)
		for index in 0 .. count {
			if !done { syncobj.signal_error(leaves[index], -19) }
			if !done && !duplicate && index + 1 < count { assert !syncobj.is_signaled(head) }
		}
		assert syncobj.is_signaled(head) && syncobj.get_error(head) == 0
		tt_retire(); cases++
	} } }
	// Retirement during the owned-table allocation can shrink the second pass
	// to one or zero pending leaves; ownership and latest timestamps still hold.
	for finish in 0 .. 2 {
		proc.reset(); sched.reset(unsafe { nil })
		source := make_object(0)
		a := make_fence(); b := make_fence()
		tw_chain(source, a, 1); tw_chain(source, b, 2)
		tt_complete = a; tt_complete_other = if finish == 1 { b } else { unsafe { nil } }
		memory.after_next_allocation(tt_retire_during_allocation)
		merged := syncobj.unwrap_merge(current(source)) or { panic('merge') }
		if finish == 0 { assert merged == b }
		else { assert syncobj.identity(merged).kind == .stub && syncobj.is_signaled(merged) }
		syncobj.release_merge_reservation(merged)
		if finish == 1 { syncobj.signal_error(b, -5) }
		tt_retire(); cases++
	}
	println('DRM timeline TRANSFER: ${cases} counted checks; flat arrays, context deduplication, pending-prefix completion, every merge/chain OOM, private-stub timestamps, sync-file flattening and between-pass retirement pass.')
}

pub fn run_timeline_transfer_trace() {
	memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	values := [[u64(1), 2, 3]!, [u64(3), 2, 1]!, [u64(0), ~u64(0), 1]!,
		[u64(1), u64(1) << 63, ~u64(0)]!, [~u64(0), u64(0), ~u64(1)]!, [~u64(0), ~u64(0), ~u64(0)]!]!
	for contexts in 0 .. 4 { for sequence in values { for mask in 0 .. 8 {
		for source_point in [u64(0), 1, 2, 3, ~u64(0)]! { for destination_point in [u64(0), 1, ~u64(0)]! { for predecessor in 0 .. 3 {
			memory.reset(); proc.reset(); sched.reset(unsafe { nil })
			source := make_object(0); destination := make_object(0)
			for index in 0 .. 3 {
				leaf := make_fence()
				unsafe { leaf.context = match contexts { 0 { u64(3 - index) } 1 { u64(1) } 2 { u64(index % 2) } else { ~u64(index) } }; leaf.seqno = sequence[index] }
				if mask & (1 << index) != 0 { syncobj.signal(leaf) }
				tw_chain(source, leaf, u64(index + 1))
			}
			if predecessor != 0 {
				leaf := make_fence()
				if predecessor == 2 { syncobj.signal(leaf) }
				tw_chain(destination, leaf, 10)
			}
			mut request := ioctl.DrmSyncobjTransfer{src_handle: source.handle, dst_handle: destination.handle, src_point: source_point, dst_point: destination_point}
			code := ioctl_syncobj_transfer(voidptr(11), unsafe { &request })
			head := syncobj.get_fence(destination) or { unsafe { nil } }
			payload := if destination_point != 0 && code == 0 { syncobj.chain_contained(remember_fence(head)) } else { head }
			if destination_point != 0 && code == 0 { tt_track(payload) }
			info := syncobj.identity(payload)
			kind := match info.kind { .stub { 1 } .fence_array { 2 } .chain { 3 } else { 0 } }
			println('${code} ${kind} ${int(syncobj.is_signaled(head))} ${syncobj.query_timeline_point(destination, true)}')
			if payload != unsafe { nil } {
				mut iterator := unsafe { &syncobj.FenceUnwrap(C.__builtin_alloca(sizeof(syncobj.FenceUnwrap))) }
				mut item := syncobj.unwrap_first(payload, iterator)
				for item != unsafe { nil } { println('${item.context} ${item.seqno}'); item = syncobj.unwrap_next(iterator) }
			}
			println('end')
			tt_retire()
		} } }
	} } }
}
pub fn measure_timeline_transfer() {
	$if macos {
		memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
		proc.reset(); sched.reset(unsafe { nil })
		source := make_object(0); destination := make_object(0)
		a := make_fence(); b := make_fence()
		unsafe { a.context = 1; b.context = 2 }
		tw_chain(source, a, 1); tw_chain(source, b, 2)
		for failure_index in 0 .. 3 { for batch in 0 .. 4 {
			before_blocks, before_bytes := live_record_heap()
			for _ in 0 .. 1000 {
				mut request := ioctl.DrmSyncobjTransfer{src_handle: source.handle, dst_handle: destination.handle, dst_point: 9}
				memory.fail_in(failure_index)
				assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == -12
			}
			after_blocks, after_bytes := live_record_heap()
			if batch != 0 {
				assert before_blocks == after_blocks && before_bytes == after_bytes
				println('timeline-transfer failure=${failure_index} batch=${batch} cycles=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
			}
		} }
		tt_retire()
	} $else { panic('malloc-zone measurement requires macOS') }
}
