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
	chains          [64]&syncobj.DmaFence
	items           &SyncItem = unsafe { nil }
	owns_objects    bool
}

fn packet_sync_snapshot(array PacketSyncArray) SyncArray {
	return SyncArray{
		count:           array.count
		objects:         array.objects
		fences:          array.fences
		timeline:        array.timeline
		timeline_values: array.timeline_values
		chains:          array.chains
		items:           array.items
		owns_objects:    array.owns_objects
	}
}

// Modern sync records are 16 bytes, without the legacy extensions word.
// Parse the combined input/output list in wire order before copying packets.
pub fn stage_packet_syncs(owner u64, pointer u64, in_count u32, out_count u32) (int, SyncArray, SyncArray) {
	mut inputs, mut outputs := PacketSyncArray{}, PacketSyncArray{owns_objects: true}
	if in_count > ~u32(0) - out_count { return -75, SyncArray{}, SyncArray{} }
	count := u64(in_count) + out_count
	if count == 0 { return 0, SyncArray{}, SyncArray{} }
	bytes := count * sizeof(asahi.Sync)
	if pointer == 0 || bytes - 1 > ~pointer { return -14, SyncArray{}, SyncArray{} }
	mut complete := false
	defer {
		if !complete {
			release_sync_array(packet_sync_snapshot(inputs))
			release_sync_array(packet_sync_snapshot(outputs))
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
		timeline := item.sync_type == ioctl.asahi_sync_timeline_syncobj
		if index < in_count {
			object := syncobj.lookup(owner, item.handle) or { return -2, SyncArray{}, SyncArray{} }
			// dma_fence_chain_find_seqno(0) leaves the captured fence intact.
			// It waits on that snapshot even when the object is later replaced.
			fence := if timeline {
				syncobj.get_chain_fence(object, item.timeline_value) or { return -22, SyncArray{}, SyncArray{} }
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
			object := syncobj.lookup_referenced(owner, item.handle) or { return -2, SyncArray{}, SyncArray{} }
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
	// Match Asahi's parse_array: validate and snapshot every wire record
	// before reserving output chain nodes. Nothing is published on failure.
	for index := u32(0); index < outputs.count; index++ {
		timeline := if outputs.items != unsafe { nil } { unsafe { outputs.items[index].timeline } } else { outputs.timeline[index] }
		if !timeline { continue }
		chain := syncobj.reserve_chain() or { return -12, SyncArray{}, SyncArray{} }
		if outputs.items != unsafe { nil } {
			item := unsafe { outputs.items[index] }
			unsafe { outputs.items[index] = SyncItem{object: item.object, timeline: true,
				timeline_value: item.timeline_value, chain: chain} }
		} else { outputs.chains[index] = chain }
	}
	complete = true
	return 0, packet_sync_snapshot(inputs), packet_sync_snapshot(outputs)
}
