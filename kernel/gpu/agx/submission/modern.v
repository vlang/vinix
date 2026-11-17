// SPDX-License-Identifier: GPL-2.0-or-later
module submission

import drm.asahi
import drm.ioctl
import drm.syncobj
import memory
import usercopy

struct PacketSyncArray {
mut:
	count           u32
	objects         [64]&syncobj.SyncObj
	fences          [64]&syncobj.DmaFence
	timeline        [64]bool
	timeline_values [64]u64
	items           &SyncItem = unsafe { nil }
}

fn packet_sync_snapshot(array PacketSyncArray) SyncArray {
	return SyncArray{
		count:           array.count
		objects:         array.objects
		fences:          array.fences
		timeline:        array.timeline
		timeline_values: array.timeline_values
		items:           array.items
	}
}

// Modern sync records are 16 bytes, without the legacy extensions word.
// Parse the combined input/output list in wire order before copying packets.
pub fn stage_packet_syncs(owner u64, pointer u64, in_count u32, out_count u32) (int, SyncArray, SyncArray) {
	mut inputs, mut outputs := PacketSyncArray{}, PacketSyncArray{}
	if in_count > ~u32(0) - out_count { return -75, SyncArray{}, SyncArray{} }
	count := u64(in_count) + out_count
	if count == 0 { return 0, SyncArray{}, SyncArray{} }
	bytes := count * sizeof(asahi.Sync)
	if pointer == 0 || bytes - 1 > ~pointer { return -14, SyncArray{}, SyncArray{} }
	mut complete := false
	defer {
		if !complete {
			if inputs.items != unsafe { nil } { memory.free(voidptr(inputs.items)) }
			if outputs.items != unsafe { nil } { memory.free(voidptr(outputs.items)) }
		}
	}
	if in_count > max_syncs {
		storage := memory.malloc_packed_fallible(u64(in_count) * sizeof(SyncItem)) @[freed]
		if storage == unsafe { nil } { return -12, SyncArray{}, SyncArray{} }
		inputs.items = unsafe { &SyncItem(storage) }
	}
	if out_count > max_syncs {
		storage := memory.malloc_packed_fallible(u64(out_count) * sizeof(SyncItem)) @[freed]
		if storage == unsafe { nil } { return -12, SyncArray{}, SyncArray{} }
		outputs.items = unsafe { &SyncItem(storage) }
	}
	for index := u64(0); index < count; index++ {
		mut item := asahi.Sync{}
		if !usercopy.copy_from_user(unsafe { voidptr(&item) }, pointer + index * sizeof(item), sizeof(item)) {
			return -14, SyncArray{}, SyncArray{}
		}
		if item.sync_type > ioctl.asahi_sync_timeline_syncobj
			|| (item.sync_type == ioctl.asahi_sync_syncobj && item.timeline_value != 0) {
			return -22, SyncArray{}, SyncArray{}
		}
		object := syncobj.lookup(owner, item.handle) or { return -2, SyncArray{}, SyncArray{} }
		timeline := item.sync_type == ioctl.asahi_sync_timeline_syncobj
		// Native timelines are still a noncumulative point map. Until that
		// migration lands, refuse zero-point outputs before publishing anything.
		if timeline && item.timeline_value == 0 && index >= in_count {
			return -95, SyncArray{}, SyncArray{}
		}
		if index < in_count {
			// dma_fence_chain_find_seqno(0) leaves the captured fence intact.
			// It waits on that snapshot even when the object is later replaced.
			fence := if timeline && item.timeline_value != 0 {
				syncobj.get_timeline_fence(object, item.timeline_value) or { return -22, SyncArray{}, SyncArray{} }
			} else {
				syncobj.get_fence(object) or { return -22, SyncArray{}, SyncArray{} }
			}
			if inputs.items != unsafe { nil } {
				unsafe { inputs.items[index] = SyncItem{object: object, fence: fence, timeline: timeline, timeline_value: item.timeline_value} }
			} else {
				inputs.objects[index] = object
				inputs.fences[index] = fence
				inputs.timeline[index] = timeline
				inputs.timeline_values[index] = item.timeline_value
			}
			inputs.count++
		} else {
			out := index - in_count
			if outputs.items != unsafe { nil } {
				unsafe { outputs.items[out] = SyncItem{object: object, timeline: timeline, timeline_value: item.timeline_value} }
			} else {
				outputs.objects[out] = object
				outputs.timeline[out] = timeline
				outputs.timeline_values[out] = item.timeline_value
			}
			outputs.count++
		}
	}
	complete = true
	return 0, packet_sync_snapshot(inputs), packet_sync_snapshot(outputs)
}
