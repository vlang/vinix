// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module submission

// Immutable Mesa submission input shared by native and fake AGX backends.
// All userspace command, payload, attachment, and sync descriptors are copied
// before a backend acquires its VM or queue locks.

import drm.asahi
import drm.ioctl
import drm.syncobj
import gpu.agx.compute as agxcompute
import gpu.agx.render as agxrender
import usercopy

pub const max_commands = u32(64)
pub const max_legacy_commands = u32(2)
pub const max_syncs = u32(64)

pub struct SyncItem {
pub:
	object &syncobj.SyncObj = unsafe { nil }
	fence &syncobj.DmaFence = unsafe { nil }
	timeline bool
	timeline_value u64
	chain &syncobj.DmaFence = unsafe { nil } // modern output's reserved chain node
}

pub struct SyncArray {
pub:
	count           u32
	objects         [64]&syncobj.SyncObj
	fences          [64]&syncobj.DmaFence
	timeline        [64]bool
	timeline_values [64]u64
	chains          [64]&syncobj.DmaFence
	items           &SyncItem = unsafe { nil } // owned storage for modern lists beyond the inline bound
}

pub fn (array &SyncArray) item(index u32) SyncItem {
	assert index < array.count
	if array.items != unsafe { nil } { return unsafe { array.items[index] } }
	return SyncItem{object: array.objects[index], fence: array.fences[index],
		timeline: array.timeline[index], timeline_value: array.timeline_values[index], chain: array.chains[index]}
}

pub struct Command {
pub:
	descriptor ioctl.DrmAsahiCommand
	render     agxrender.Command
	compute    agxcompute.Command
	timestamps [3]asahi.Timestamps // vertex, fragment, compute; zero for legacy input
}

// Snapshot sync descriptors and retain the stable sync-object and input-fence
// pointers needed by backend-specific wait and completion paths.
pub fn stage_sync_array(owner u64, pointer u64, count u32, input bool) (int, SyncArray) {
	mut objects := unsafe { [64]&syncobj.SyncObj{} }
	mut fences := unsafe { [64]&syncobj.DmaFence{} }
	mut timeline := [64]bool{}
	mut timeline_values := [64]u64{}
	if count > max_syncs {
		return -22, SyncArray{}
	}
	if count == 0 {
		return 0, SyncArray{}
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiSync)
	if pointer == 0 || bytes - 1 > ~pointer {
		return -14, SyncArray{}
	}
	for index := u32(0); index < count; index++ {
		mut item := ioctl.DrmAsahiSync{}
		if !usercopy.copy_from_user(voidptr(&item), pointer + u64(index) * sizeof(ioctl.DrmAsahiSync), sizeof(ioctl.DrmAsahiSync)) {
			return -14, SyncArray{}
		}
		if item.extensions != 0
			|| (item.sync_type != ioctl.asahi_sync_syncobj
				&& item.sync_type != ioctl.asahi_sync_timeline_syncobj)
			|| (item.sync_type == ioctl.asahi_sync_syncobj && item.timeline_value != 0)
			|| (item.sync_type == ioctl.asahi_sync_timeline_syncobj
				&& item.timeline_value == 0) {
			return -22, SyncArray{}
		}
		// Asahi's SyncObj::lookup_handle returns ENOENT. A found object with
		// no usable input fence remains EINVAL below.
		object := syncobj.lookup(owner, item.handle) or { return -2, SyncArray{} }
		objects[index] = object
		timeline[index] = item.sync_type == ioctl.asahi_sync_timeline_syncobj
		timeline_values[index] = item.timeline_value
		if input {
			fence := if timeline[index] {
				syncobj.get_timeline_fence(object, item.timeline_value) or {
					return -22, SyncArray{}
				}
			} else {
				syncobj.get_fence(object) or { return -22, SyncArray{} }
			}
			fences[index] = fence
		}
	}
	return 0, SyncArray{
		count:           count
		objects:         objects
		fences:          fences
		timeline:        timeline
		timeline_values: timeline_values
	}
}

pub fn install_output_syncs(staged &SyncArray, fence &syncobj.DmaFence) bool {
	for index := u32(0); index < staged.count; index++ {
		item := staged.item(index)
		object := item.object
		if object == unsafe { nil } {
			return false
		}
		if item.timeline {
			if item.chain != unsafe { nil } {
				if !syncobj.add_chain_point(object, item.chain, fence, item.timeline_value) { return false }
			} else if !syncobj.add_timeline_point(object, item.timeline_value, fence) {
				return false
			}
		} else {
			syncobj.replace_fence(object, fence)
		}
	}
	return true
}

// Snapshot one descriptor and its nested payload before taking backend locks.
pub fn stage_command(pointer u64, index u32) (int, Command) {
	if pointer == 0 || index >= max_commands { return -22, Command{} }
	bytes := u64(index + 1) * sizeof(ioctl.DrmAsahiCommand)
	if bytes - 1 > ~pointer { return -14, Command{} }
	mut descriptor := ioctl.DrmAsahiCommand{}
	if !usercopy.copy_from_user(voidptr(&descriptor), pointer + u64(index) * sizeof(ioctl.DrmAsahiCommand), sizeof(ioctl.DrmAsahiCommand)) {
		return -14, Command{}
	}
	if descriptor.extensions != 0 || descriptor.flags != 0 || descriptor.cmd_buffer == 0 {
		return -22, Command{}
	}
	for barrier in descriptor.barriers {
		if barrier != ioctl.asahi_barrier_none && barrier > index { return -22, Command{} }
	}
	match descriptor.cmd_type {
		ioctl.asahi_cmd_render {
			if descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdRender)
				|| (descriptor.result_size != 0 && descriptor.result_size < sizeof(ioctl.DrmAsahiResultRender)) {
				return -22, Command{}
			}
			mut input := ioctl.DrmAsahiCmdRender{}
			if !usercopy.copy_from_user(voidptr(&input), descriptor.cmd_buffer, sizeof(input)) {
				return -14, Command{}
			}
			code, command := agxrender.stage_uapi(&input, descriptor.result_size != 0)
			return code, Command{ descriptor: descriptor, render: command }
		}
		ioctl.asahi_cmd_compute {
			// Mesa 25.0.5 reports sizeof - 8 but points to the current struct.
			if (descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute)
				&& descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute) - u64(8))
				|| (descriptor.result_size != 0 && descriptor.result_size < sizeof(ioctl.DrmAsahiResultCompute)) {
				return -22, Command{}
			}
			mut input := ioctl.DrmAsahiCmdCompute{}
			if !usercopy.copy_from_user(voidptr(&input), descriptor.cmd_buffer, sizeof(input)) {
				return -14, Command{}
			}
			code, command := agxcompute.stage_uapi(&input, descriptor.result_size != 0)
			return code, Command{ descriptor: descriptor, compute: command }
		}
		else { return -22, Command{} }
	}
}

// The caller supplies owned, correctly sized kernel storage. No allocation
// occurs here. Barrier indices name PREVIOUS commands of their own subqueue,
// including index zero for the initial no-command event, as in Asahi's parser.
pub fn stage_command_array(pointer u64, count u32, mut staged []Command) int {
	if count == 0 || count > max_commands || staged.len != int(count) { return -22 }
	mut counts := [2]u32{}
	for index := u32(0); index < count; index++ {
		code, command := stage_command(pointer, index)
		if code != 0 { return code }
		for pipe in 0 .. 2 {
			barrier := command.descriptor.barriers[pipe]
			if barrier != ioctl.asahi_barrier_none && barrier > counts[pipe] { return -22 }
		}
		staged[index] = command
		pipe := if command.descriptor.cmd_type == ioctl.asahi_cmd_render { 0 } else { 1 }
		counts[pipe]++
	}
	return 0
}

// The fake backend retains its previous two-command contract while native
// G13 uses the general bounded array above.
pub fn stage_commands(pointer u64, count u32) (int, [2]Command) {
	mut staged := [2]Command{}
	if count == 0 || count > max_legacy_commands { return -22, staged }
	for index := u32(0); index < count; index++ {
		code, command := stage_command(pointer, index)
		if code != 0 { return code, staged }
		staged[index] = command
	}
	if count == 2 && (staged[0].descriptor.cmd_type != ioctl.asahi_cmd_compute
		|| staged[1].descriptor.cmd_type != ioctl.asahi_cmd_render
		|| staged[1].descriptor.barriers[0] != ioctl.asahi_barrier_none
		|| staged[1].descriptor.barriers[1] != 1) {
		return -22, staged
	}
	return 0, staged
}
