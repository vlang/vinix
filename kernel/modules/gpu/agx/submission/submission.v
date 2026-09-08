// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module submission

// Immutable Mesa submission input shared by native and fake AGX backends.
// All userspace command, payload, attachment, and sync descriptors are copied
// before a backend acquires its VM or queue locks.

import drm.ioctl
import drm.syncobj
import gpu.agx.compute as agxcompute
import gpu.agx.render as agxrender
import usercopy

pub const max_commands = u32(2)
pub const max_syncs = u32(64)

pub struct SyncArray {
pub:
	count           u32
	objects         [64]&syncobj.SyncObj
	fences          [64]&syncobj.DmaFence
	timeline        [64]bool
	timeline_values [64]u64
}

pub struct Command {
pub:
	descriptor ioctl.DrmAsahiCommand
	render     agxrender.Command
	compute    agxcompute.Command
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
		object := syncobj.lookup(owner, item.handle) or { return -22, SyncArray{} }
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
		count: count
		objects: objects
		fences: fences
		timeline: timeline
		timeline_values: timeline_values
	}
}

pub fn install_output_syncs(staged &SyncArray, fence &syncobj.DmaFence) bool {
	for index := u32(0); index < staged.count; index++ {
		object := staged.objects[index]
		if object == unsafe { nil } {
			return false
		}
		if staged.timeline[index] {
			if !syncobj.add_timeline_point(object, staged.timeline_values[index], fence) {
				return false
			}
		} else {
			syncobj.replace_fence(object, fence)
		}
	}
	return true
}

// Copy the complete command array once. The two-command form accepted by the
// current Asahi UAPI is an ordered compute-then-render pair.
pub fn stage_commands(pointer u64, count u32) (int, [2]Command) {
	mut staged := [2]Command{}
	if pointer == 0 || count == 0 || count > max_commands {
		return -22, staged
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiCommand)
	if bytes - 1 > ~pointer {
		return -14, staged
	}
	for index := u32(0); index < count; index++ {
		mut descriptor := ioctl.DrmAsahiCommand{}
		if !usercopy.copy_from_user(voidptr(&descriptor), pointer + u64(index) * sizeof(ioctl.DrmAsahiCommand), sizeof(ioctl.DrmAsahiCommand)) {
			return -14, staged
		}
		if descriptor.extensions != 0 || descriptor.flags != 0 || descriptor.cmd_buffer == 0 {
			return -22, staged
		}
		for barrier in descriptor.barriers {
			if barrier != ioctl.asahi_barrier_none && barrier > index {
				return -22, staged
			}
		}
		match descriptor.cmd_type {
			ioctl.asahi_cmd_render {
				if descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdRender)
					|| (descriptor.result_size != 0
						&& descriptor.result_size < sizeof(ioctl.DrmAsahiResultRender)) {
					return -22, staged
				}
				mut render := ioctl.DrmAsahiCmdRender{}
				if !usercopy.copy_from_user(voidptr(&render), descriptor.cmd_buffer, sizeof(ioctl.DrmAsahiCmdRender)) {
					return -14, staged
				}
				render_result, render_command := agxrender.stage_uapi(&render, descriptor.result_size != 0)
				if render_result != 0 {
					return render_result, staged
				}
				staged[index] = Command{
					descriptor: descriptor
					render: render_command
				}
			}
			ioctl.asahi_cmd_compute {
				// Mesa 25.0.5 reports sizeof - 8 for compatibility with 6.11.8,
				// while the userspace pointer still addresses the current struct.
				if (descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute)
					&& descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute) - u64(8))
					|| (descriptor.result_size != 0
						&& descriptor.result_size < sizeof(ioctl.DrmAsahiResultCompute)) {
					return -22, staged
				}
				mut compute := ioctl.DrmAsahiCmdCompute{}
				if !usercopy.copy_from_user(voidptr(&compute), descriptor.cmd_buffer, sizeof(ioctl.DrmAsahiCmdCompute)) {
					return -14, staged
				}
				compute_result, compute_command := agxcompute.stage_uapi(&compute, descriptor.result_size != 0)
				if compute_result != 0 {
					return compute_result, staged
				}
				staged[index] = Command{
					descriptor: descriptor
					compute: compute_command
				}
			}
			else {
				return -22, staged
			}
		}
	}
	if count == 2 && (staged[0].descriptor.cmd_type != ioctl.asahi_cmd_compute
		|| staged[1].descriptor.cmd_type != ioctl.asahi_cmd_render
		|| staged[1].descriptor.barriers[0] != ioctl.asahi_barrier_none
		|| staged[1].descriptor.barriers[1] != 1) {
		return -22, staged
	}
	return 0, staged
}
