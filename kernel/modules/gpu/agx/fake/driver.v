// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module fake

// Mesa-facing fake G17 DRM device. This file intentionally imports only the
// common DRM/GEM/sync/workqueue layers and software helpers from this module.
// In particular, there is no native AGX manager, UAT, DART, PMP, RTKit, or
// MMIO dependency anywhere in the fake driver's import graph.

import drm
import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.workqueue
import klock
import sched
import usercopy
import aarch64.timer

const max_submission_syncs = u32(64)
const max_submission_commands = u32(2)
const max_command_attachments = u32(16)
const max_render_dimension = u32(16384)
const max_render_layers = u32(2048)

struct StagedSyncArray {
mut:
	count           u32
	objects         [64]&syncobj.SyncObj
	fences          [64]&syncobj.DmaFence
	timeline        [64]bool
	timeline_values [64]u64
}

struct StagedCommand {
mut:
	descriptor ioctl.DrmAsahiCommand
	render     ioctl.DrmAsahiCmdRender
	compute    ioctl.DrmAsahiCmdCompute
}

@[heap]
struct FakeG17File {
mut:
	dev           &drm.DrmDevice = unsafe { nil }
	vms           []&FakeG17Vm
	queues        []&workqueue.WorkQueue
	objects       []&gem.GemObject
	mmap_objects  []&gem.GemObject
	next_vm_id    u32
	next_queue_id u32
	owner_key     u64
	verified_jobs u64
	lock          klock.Lock
}

struct FakeG17DriverState {
mut:
	device      &drm.DrmDevice = unsafe { nil }
	initialized bool
}

__global (
	fake_driver_state FakeG17DriverState
	fake_file_map_lock klock.Lock
	fake_file_map      = map[u64]&FakeG17File{}
)

fn get_or_create_file(handle voidptr, dev &drm.DrmDevice) ?&FakeG17File {
	if handle == unsafe { nil } || dev == unsafe { nil } {
		return none
	}
	key := u64(handle)
	fake_file_map_lock.acquire()
	if key in fake_file_map {
		file := fake_file_map[key] or {
			fake_file_map_lock.release()
			return none
		}
		fake_file_map_lock.release()
		return file
	}
	mut file := &FakeG17File{
		dev: unsafe { dev }
		next_vm_id: 1
		next_queue_id: 1
		owner_key: key
	}
	fake_file_map[key] = file
	fake_file_map_lock.release()
	return file
}

fn lookup_file(handle voidptr) ?&FakeG17File {
	if handle == unsafe { nil } {
		return none
	}
	fake_file_map_lock.acquire()
	defer { fake_file_map_lock.release() }
	return fake_file_map[u64(handle)] or { return none }
}

fn (mut file FakeG17File) close() {
	file.lock.acquire()
	for mut queue in file.queues {
		queue.destroy()
	}
	file.queues.clear()
	for mut vm in file.vms {
		vm.destroy()
	}
	file.vms.clear()
	for object in file.mmap_objects {
		gem.unref(object)
	}
	file.mmap_objects.clear()
	for object in file.objects {
		gem.unref(object)
	}
	file.objects.clear()
	file.lock.release()
}

pub fn release_handle(_dev &drm.DrmDevice, handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	key := u64(handle)
	fake_file_map_lock.acquire()
	file := fake_file_map[key] or {
		fake_file_map_lock.release()
		return
	}
	fake_file_map.delete(key)
	fake_file_map_lock.release()
	mut owned := unsafe { file }
	owned.close()
}

fn (file &FakeG17File) find_vm(id u32) ?&FakeG17Vm {
	for vm in file.vms {
		if vm.id == id {
			return unsafe { vm }
		}
	}
	return none
}

fn (mut file FakeG17File) get_object_ref(handle u32) ?&gem.GemObject {
	file.lock.acquire()
	defer { file.lock.release() }
	for object in file.objects {
		if object.handle == handle {
			gem.ref_obj(object)
			return object
		}
	}
	return none
}

fn (mut file FakeG17File) import_object(object &gem.GemObject) ?u32 {
	if object == unsafe { nil } {
		return none
	}
	file.lock.acquire()
	for existing in file.objects {
		if voidptr(existing) == voidptr(object) {
			handle := existing.handle
			file.lock.release()
			return handle
		}
	}
	gem.ref_obj(object)
	file.objects << object
	handle := object.handle
	file.lock.release()
	return handle
}

fn (mut file FakeG17File) authorize_mmap(handle u32) ?u64 {
	file.lock.acquire()
	defer { file.lock.release() }
	mut found := &gem.GemObject(unsafe { nil })
	for object in file.objects {
		if object.handle == handle {
			found = object
			break
		}
	}
	if found == unsafe { nil } {
		return none
	}
	for object in file.mmap_objects {
		if voidptr(object) == voidptr(found) {
			return gem.create_mmap_offset(found)
		}
	}
	gem.ref_obj(found)
	file.mmap_objects << found
	return gem.create_mmap_offset(found)
}

fn (mut file FakeG17File) mmap_page(page u64) voidptr {
	file.lock.acquire()
	defer { file.lock.release() }
	for object in file.mmap_objects {
		if address := gem.get_object_mmap_page(object, page) {
			return address
		}
	}
	return unsafe { nil }
}

fn next_unused_vm_id(file &FakeG17File) ?u32 {
	mut candidate := file.next_vm_id
	if candidate == 0 {
		candidate = 1
	}
	start := candidate
	for {
		mut used := false
		for vm in file.vms {
			if vm.id == candidate {
				used = true
				break
			}
		}
		if !used {
			return candidate
		}
		candidate = if candidate == ~u32(0) { u32(1) } else { candidate + 1 }
		if candidate == start {
			return none
		}
	}
	return none
}

fn next_unused_queue_id(file &FakeG17File) ?u32 {
	mut candidate := file.next_queue_id
	if candidate == 0 {
		candidate = 1
	}
	start := candidate
	for {
		mut used := false
		for queue in file.queues {
			if queue.id == candidate {
				used = true
				break
			}
		}
		if !used {
			return candidate
		}
		candidate = if candidate == ~u32(0) { u32(1) } else { candidate + 1 }
		if candidate == start {
			return none
		}
	}
	return none
}

fn fake_global_params() ioctl.DrmAsahiParamsGlobal {
	mut params := ioctl.DrmAsahiParamsGlobal{
		unstable_uabi_version: ioctl.drm_asahi_unstable_uabi_version
		feat_compat: ioctl.asahi_feat_gettime
		gpu_generation: 17
		gpu_variant: u32(`C`)
		gpu_revision: 0x20
		chip_id: 0x6050
		num_dies: 1
		num_clusters_total: 4
		num_cores_per_cluster: 10
		num_frags_per_cluster: 10
		num_gps_per_cluster: 4
		num_cores_total_active: 40
		vm_page_size: u32(vm_page_size)
		vm_user_start: vm_user_start
		vm_user_end: vm_user_end
		vm_kernel_min_size: vm_kernel_min_size
		max_syncs_per_submission: max_submission_syncs
		max_commands_per_submission: max_submission_commands
		max_commands_in_flight: workqueue.max_job_slots
		max_attachments: max_command_attachments
		timer_frequency_hz: 24_000_000
		result_render_size: u32(sizeof(ioctl.DrmAsahiResultRender))
		result_compute_size: u32(sizeof(ioctl.DrmAsahiResultCompute))
		user_timestamp_frequency_hz: 24_000_000
	}
	for index := 0; index < 4; index++ {
		params.core_masks[index] = 0x3ff
	}
	return params
}

fn (file &FakeG17File) ioctl_get_params(data &ioctl.DrmAsahiGetParams) int {
	_ = file
	mut request := unsafe { data }
	if request.extensions != 0 || request.param_group != 0 || request.pad != 0 {
		return -22
	}
	params := fake_global_params()
	supported_size := u64(sizeof(ioctl.DrmAsahiParamsGlobal))
	copy_size := if request.size < supported_size { request.size } else { supported_size }
	if request.pointer == 0 || copy_size == 0 {
		request.size = supported_size
		return -14
	}
	if !usercopy.copy_to_user(request.pointer, voidptr(&params), copy_size) {
		request.size = supported_size
		return -14
	}
	request.size = supported_size
	return 0
}

fn (mut file FakeG17File) ioctl_vm_create(data &ioctl.DrmAsahiVmCreate) int {
	mut request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 {
		C.printf(c'fake-g17: rejected VM request extensions=0x%llx pad=%u start=0x%llx end=0x%llx\n',
			request.extensions, request.pad, request.kernel_start, request.kernel_end)
		return -22
	}
	file.lock.acquire()
	id := next_unused_vm_id(&file) or {
		file.lock.release()
		return -24
	}
	vm := new_vm(id, request.kernel_start, request.kernel_end) or {
		C.printf(c'fake-g17: rejected VM range start=0x%llx end=0x%llx pad=%u\n',
			request.kernel_start, request.kernel_end, request.pad)
		file.lock.release()
		return -22
	}
	file.vms << vm
	file.next_vm_id = if id == ~u32(0) { u32(1) } else { id + 1 }
	file.lock.release()
	request.vm_id = id
	return 0
}

fn (mut file FakeG17File) ioctl_vm_destroy(data &ioctl.DrmAsahiVmDestroy) int {
	request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 {
		return -22
	}
	file.lock.acquire()
	for queue in file.queues {
		if queue.vm_id == request.vm_id {
			file.lock.release()
			return -16
		}
	}
	for index, vm in file.vms {
		if vm.id == request.vm_id {
			mut target := unsafe { vm }
			if target.has_mappings() {
				file.lock.release()
				return -16
			}
			target.destroy()
			file.vms.delete(index)
			file.lock.release()
			return 0
		}
	}
	file.lock.release()
	return -22
}

fn (mut file FakeG17File) ioctl_gem_create(data &ioctl.DrmAsahiGemCreate) int {
	mut request := unsafe { data }
	valid_flags := ioctl.asahi_gem_writeback | ioctl.asahi_gem_vm_private
	if request.extensions != 0 || request.pad != 0 || request.flags & ~valid_flags != 0 {
		return -22
	}
	if request.flags & ioctl.asahi_gem_vm_private != 0 {
		file.find_vm(request.vm_id) or { return -22 }
	} else if request.vm_id != 0 {
		return -22
	}
	object := gem.create_aligned(request.size, vm_page_size) or { return -12 }
	file.lock.acquire()
	file.objects << object
	file.lock.release()
	request.size = object.size
	request.handle = object.handle
	return 0
}

fn (mut file FakeG17File) ioctl_gem_mmap_offset(data &ioctl.DrmAsahiGemMmapOffset) int {
	mut request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 {
		return -22
	}
	request.offset = file.authorize_mmap(request.handle) or { return -2 }
	return 0
}

fn (mut file FakeG17File) ioctl_gem_bind(data &ioctl.DrmAsahiGemBind) int {
	request := unsafe { data }
	if request.extensions != 0 {
		return -22
	}
	mut vm := file.find_vm(request.vm_id) or { return -22 }
	match request.op {
		ioctl.asahi_bind_op_bind {
			if request.flags == 0
				|| request.flags & ~(ioctl.asahi_bind_read | ioctl.asahi_bind_write) != 0 {
				return -22
			}
			object := file.get_object_ref(request.handle) or { return -2 }
			flags := (if request.flags & ioctl.asahi_bind_read != 0 { vm_read } else { u32(0) })
				| (if request.flags & ioctl.asahi_bind_write != 0 { vm_write } else { u32(0) })
			result := vm.bind(object, request.addr, request.range, request.offset, flags)
			gem.unref(object)
			return result
		}
		ioctl.asahi_bind_op_unbind {
			if request.handle != 0 || request.flags != 0 || request.offset != 0 {
				return -22
			}
			return vm.unbind(request.addr, request.range)
		}
		ioctl.asahi_bind_op_unbind_all {
			if request.handle == 0 || request.flags != 0 || request.offset != 0
				|| request.addr != 0 || request.range != 0 {
				return -22
			}
			object := file.get_object_ref(request.handle) or { return -2 }
			result := vm.unbind_object(object)
			gem.unref(object)
			return result
		}
		else {
			return -22
		}
	}
}

fn (mut file FakeG17File) ioctl_queue_create(data &ioctl.DrmAsahiQueueCreate) int {
	mut request := unsafe { data }
	known_caps := ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_blit
		| ioctl.asahi_queue_cap_compute
	if request.extensions != 0 || request.flags != 0 || request.pad != 0
		|| request.priority > 3 || request.queue_caps == 0
		|| request.queue_caps & ~known_caps != 0 {
		return -22
	}
	file.find_vm(request.vm_id) or { return -22 }
	file.lock.acquire()
	id := next_unused_queue_id(&file) or {
		file.lock.release()
		return -24
	}
	queue := workqueue.new_workqueue(id, request.vm_id, request.priority,
		request.queue_caps) or {
		file.lock.release()
		return -12
	}
	file.queues << queue
	file.next_queue_id = if id == ~u32(0) { u32(1) } else { id + 1 }
	file.lock.release()
	request.queue_id = id
	return 0
}

fn (mut file FakeG17File) ioctl_queue_destroy(data &ioctl.DrmAsahiQueueDestroy) int {
	request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 {
		return -22
	}
	file.lock.acquire()
	for index, mut queue in file.queues {
		if queue.id == request.queue_id {
			if !queue.is_empty() {
				file.lock.release()
				return -16
			}
			queue.destroy()
			file.queues.delete(index)
			file.lock.release()
			return 0
		}
	}
	file.lock.release()
	return -22
}

fn valid_render_command(command &ioctl.DrmAsahiCmdRender) bool {
	if command.extensions != 0 || command.flags & ~ioctl.asahi_render_supported_flags != 0
		|| command.fb_width == 0 || command.fb_width > max_render_dimension
		|| command.fb_height == 0 || command.fb_height > max_render_dimension
		|| command.layers == 0 || command.layers > max_render_layers {
		return false
	}
	if !((command.utile_width == 32 && command.utile_height == 32)
		|| (command.utile_width == 32 && command.utile_height == 16)
		|| (command.utile_width == 16 && command.utile_height == 16)) {
		return false
	}
	if command.samples != 1 && command.samples != 2 && command.samples != 4 {
		return false
	}
	return command.vertex_attachment_count <= max_command_attachments
		&& command.fragment_attachment_count <= max_command_attachments
		&& (command.vertex_attachment_count == 0 || command.vertex_attachments != 0)
		&& (command.fragment_attachment_count == 0 || command.fragment_attachments != 0)
}

fn valid_compute_command(command &ioctl.DrmAsahiCmdCompute) bool {
	return command.extensions == 0
		&& command.flags & ~ioctl.asahi_compute_no_preemption == 0 && command.pad == 0
		&& command.attachment_count <= max_command_attachments
		&& (command.attachment_count == 0 || command.attachments != 0)
}

fn stage_commands(pointer u64, count u32) (int, [2]StagedCommand) {
	mut staged := [2]StagedCommand{}
	if pointer == 0 || count == 0 || count > max_submission_commands {
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
		staged[index].descriptor = descriptor
		match descriptor.cmd_type {
			ioctl.asahi_cmd_render {
				if descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdRender)
					|| (descriptor.result_size != 0
						&& descriptor.result_size < sizeof(ioctl.DrmAsahiResultRender)) {
					return -22, staged
				}
				if !usercopy.copy_from_user(voidptr(&staged[index].render),
					descriptor.cmd_buffer, sizeof(ioctl.DrmAsahiCmdRender))
					|| !valid_render_command(&staged[index].render) {
					return -22, staged
				}
			}
			ioctl.asahi_cmd_compute {
				if (descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute)
					&& descriptor.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute) - u64(8))
					|| (descriptor.result_size != 0
						&& descriptor.result_size < sizeof(ioctl.DrmAsahiResultCompute)) {
					return -22, staged
				}
				if !usercopy.copy_from_user(voidptr(&staged[index].compute),
					descriptor.cmd_buffer, sizeof(ioctl.DrmAsahiCmdCompute))
					|| !valid_compute_command(&staged[index].compute) {
					return -22, staged
				}
			}
			else {
				return -95, staged
			}
		}
	}
	return 0, staged
}

fn stage_sync_array(owner u64, pointer u64, count u32,
	input bool) (int, StagedSyncArray) {
	mut staged := StagedSyncArray{
		count: count
	}
	if count == 0 {
		return 0, staged
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiSync)
	if pointer == 0 || bytes - 1 > ~pointer {
		return -14, staged
	}
	for index := u32(0); index < count; index++ {
		mut item := ioctl.DrmAsahiSync{}
		if !usercopy.copy_from_user(voidptr(&item), pointer + u64(index) * sizeof(ioctl.DrmAsahiSync), sizeof(ioctl.DrmAsahiSync)) {
			return -14, staged
		}
		if item.extensions != 0
			|| (item.sync_type != ioctl.asahi_sync_syncobj
				&& item.sync_type != ioctl.asahi_sync_timeline_syncobj)
			|| (item.sync_type == ioctl.asahi_sync_syncobj && item.timeline_value != 0)
			|| (item.sync_type == ioctl.asahi_sync_timeline_syncobj
				&& item.timeline_value == 0) {
			return -22, staged
		}
		object := syncobj.lookup(owner, item.handle) or { return -22, staged }
		staged.objects[index] = object
		staged.timeline[index] = item.sync_type == ioctl.asahi_sync_timeline_syncobj
		staged.timeline_values[index] = item.timeline_value
		if input {
			fence := if staged.timeline[index] {
				syncobj.get_timeline_fence(object, item.timeline_value) or {
					return -22, staged
				}
			} else {
				syncobj.get_fence(object) or { return -22, staged }
			}
			staged.fences[index] = fence
		}
	}
	return 0, staged
}

fn wait_staged_syncs(staged &StagedSyncArray) int {
	for index := u32(0); index < staged.count; index++ {
		fence := staged.fences[index]
		for !syncobj.is_signaled(fence) {
			syncobj.wait(fence, 1_000_000)
			sched.yield(false)
		}
		if syncobj.get_error(fence) != 0 {
			return -5
		}
	}
	return 0
}

fn install_output_syncs(staged &StagedSyncArray, fence &syncobj.DmaFence) bool {
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

fn mapped(mut vm FakeG17Vm, address u64, bytes u64, writable bool) bool {
	if address == 0 {
		return true
	}
	resolved := vm.resolve(address, if bytes == 0 { u64(1) } else { bytes },
		writable) or { return false }
	resolved.release()
	return true
}

fn validate_attachments(mut vm FakeG17Vm, pointer u64, count u32) int {
	if count == 0 {
		return 0
	}
	if pointer == 0 {
		return -22
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiAttachment)
	if bytes - 1 > ~pointer {
		return -14
	}
	for index := u32(0); index < count; index++ {
		mut attachment := ioctl.DrmAsahiAttachment{}
		if !usercopy.copy_from_user(voidptr(&attachment), pointer + u64(index) * sizeof(ioctl.DrmAsahiAttachment), sizeof(ioctl.DrmAsahiAttachment)) {
			return -14
		}
		if attachment.flags != 0 || attachment.order < 1 || attachment.order > 6
			|| attachment.pointer == 0 || attachment.size == 0
			|| !mapped(mut vm, attachment.pointer, attachment.size, false) {
			return -22
		}
	}
	return 0
}

fn validate_render_mappings(mut vm FakeG17Vm, command &ioctl.DrmAsahiCmdRender) int {
	if command.encoder_ptr == 0 || !mapped(mut vm, command.encoder_ptr, 4, false)
		|| !vm.contains_address(command.vertex_usc_base)
		|| !vm.contains_address(command.fragment_usc_base)
		|| !mapped(mut vm, command.vertex_helper_arg, 8, false)
		|| !mapped(mut vm, command.fragment_helper_arg, 8, false)
		|| !mapped(mut vm, command.depth_buffer_load, 8, false)
		|| !mapped(mut vm, command.depth_buffer_store, 8, true)
		|| !mapped(mut vm, command.depth_buffer_partial, 8, true)
		|| !mapped(mut vm, command.depth_meta_buffer_load, 8, false)
		|| !mapped(mut vm, command.depth_meta_buffer_store, 8, true)
		|| !mapped(mut vm, command.depth_meta_buffer_partial, 8, true)
		|| !mapped(mut vm, command.stencil_buffer_load, 8, false)
		|| !mapped(mut vm, command.stencil_buffer_store, 8, true)
		|| !mapped(mut vm, command.stencil_buffer_partial, 8, true)
		|| !mapped(mut vm, command.stencil_meta_buffer_load, 8, false)
		|| !mapped(mut vm, command.stencil_meta_buffer_store, 8, true)
		|| !mapped(mut vm, command.stencil_meta_buffer_partial, 8, true)
		|| !mapped(mut vm, command.scissor_array, 8, false)
		|| !mapped(mut vm, command.depth_bias_array, 8, false)
		|| !mapped(mut vm, command.visibility_result_buffer, 8, true)
		|| !mapped(mut vm, command.vertex_sampler_array,
			if command.vertex_sampler_count == 0 { u64(1) } else { u64(command.vertex_sampler_count) }, false)
		|| !mapped(mut vm, command.fragment_sampler_array,
			if command.fragment_sampler_count == 0 { u64(1) } else { u64(command.fragment_sampler_count) }, false) {
		return -22
	}
	result := validate_attachments(mut vm, command.vertex_attachments,
		command.vertex_attachment_count)
	if result != 0 {
		return result
	}
	return validate_attachments(mut vm, command.fragment_attachments,
		command.fragment_attachment_count)
}

fn validate_compute_mappings(mut vm FakeG17Vm,
	command &ioctl.DrmAsahiCmdCompute) int {
	if command.encoder_ptr == 0 || command.encoder_end <= command.encoder_ptr
		|| !mapped(mut vm, command.encoder_ptr, command.encoder_end - command.encoder_ptr,
			false)
		|| !vm.contains_address(command.usc_base)
		|| !mapped(mut vm, command.helper_arg, 8, false)
		|| !mapped(mut vm, command.sampler_array,
			if command.sampler_count == 0 { u64(1) } else { u64(command.sampler_count) }, false) {
		return -22
	}
	return validate_attachments(mut vm, command.attachments, command.attachment_count)
}

fn write_results(commands [2]StagedCommand, count u32, object &gem.GemObject,
	successful bool, started u64, ended u64) {
	if object == unsafe { nil } {
		return
	}
	for index := u32(0); index < count; index++ {
		descriptor := commands[index].descriptor
		if descriptor.result_size == 0 {
			continue
		}
		if descriptor.cmd_type == ioctl.asahi_cmd_render {
			mut result := ioctl.DrmAsahiResultRender{}
			result.info.status = if successful {
				ioctl.asahi_status_complete
			} else {
				ioctl.asahi_status_channel_error
			}
			result.vertex_ts_start = started
			result.vertex_ts_end = ended
			result.fragment_ts_start = started
			result.fragment_ts_end = ended
			unsafe {
				C.memcpy(voidptr(object.virt_addr + descriptor.result_offset),
					voidptr(&result), sizeof(ioctl.DrmAsahiResultRender))
			}
		} else {
			mut result := ioctl.DrmAsahiResultCompute{}
			result.info.status = if successful {
				ioctl.asahi_status_complete
			} else {
				ioctl.asahi_status_channel_error
			}
			result.ts_start = started
			result.ts_end = ended
			unsafe {
				C.memcpy(voidptr(object.virt_addr + descriptor.result_offset),
					voidptr(&result), sizeof(ioctl.DrmAsahiResultCompute))
			}
		}
	}
}

fn run_fake_render(mut queue workqueue.WorkQueue, mut vm FakeG17Vm,
	fence &syncobj.DmaFence) FakeG17Verification {
	command := unsafe { malloc(g17_command_bytes) }
	descriptor := unsafe { malloc(g17_descriptor_bytes) }
	if command == unsafe { nil } || descriptor == unsafe { nil } {
		if command != unsafe { nil } {
			unsafe { free(command) }
		}
		if descriptor != unsafe { nil } {
			unsafe { free(descriptor) }
		}
		syncobj.signal_error(fence, -12)
		return FakeG17Verification{error: fake_g17_invalid_argument}
	}
	unsafe { C.memset(command, 0, g17_command_bytes) }
	if !initialize_render_descriptor(descriptor, g17_descriptor_bytes) {
		unsafe {
			free(command)
			free(descriptor)
		}
		syncobj.signal_error(fence, -5)
		return FakeG17Verification{error: fake_g17_invalid_argument}
	}
	mut inputs := FakeG17EncoderInputs{}
	mut writes := []FakeG17ExpectedWrite{len: int(fake_g17_max_writes)}
	encoding := encode_fake_g17_3d(command, g17_command_bytes, descriptor,
		g17_descriptor_bytes, vm.kernel_start, &inputs, mut writes)
	if !encoding.succeeded() {
		unsafe {
			writes.free()
			free(command)
			free(descriptor)
		}
		syncobj.signal_error(fence, -5)
		return FakeG17Verification{error: encoding.error}
	}
	mut ranges := vm.address_ranges()
	mut item := workqueue.WorkItem{
		cmd_type: ioctl.asahi_cmd_render
		fence: unsafe { fence }
	}
	submission := FakeG17Submission{
		command: command
		command_bytes: g17_command_bytes
		descriptor: descriptor
		descriptor_bytes: g17_descriptor_bytes
		command_gpu_address: vm.kernel_start
		writes: unsafe { writes[..int(encoding.write_count)] }
		address_ranges: ranges
	}
	report := submit_fake_g17(mut queue, &item, &submission)
	unsafe {
		ranges.free()
		writes.free()
		free(command)
		free(descriptor)
	}
	return report
}

fn run_fake_compute(mut queue workqueue.WorkQueue, fence &syncobj.DmaFence) bool {
	mut item := workqueue.WorkItem{
		cmd_type: ioctl.asahi_cmd_compute
		fence: unsafe { fence }
	}
	slot := queue.submit(&item) or {
		syncobj.signal_error(fence, -16)
		return false
	}
	queue.complete(slot, workqueue.work_err_none)
	return true
}

fn (mut file FakeG17File) ioctl_submit(data &ioctl.DrmAsahiSubmit) int {
	request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 || request.command_count == 0
		|| request.command_count > max_submission_commands || request.commands == 0
		|| request.in_sync_count > max_submission_syncs
		|| request.out_sync_count > max_submission_syncs
		|| (request.in_sync_count != 0 && request.in_syncs == 0)
		|| (request.out_sync_count != 0 && request.out_syncs == 0) {
		return -22
	}
	command_result, commands := stage_commands(request.commands, request.command_count)
	if command_result != 0 {
		C.printf(c'fake-g17: submit rejected while staging commands error=%d count=%u\n',
			command_result, request.command_count)
		return command_result
	}
	input_result, input_syncs := stage_sync_array(file.owner_key, request.in_syncs,
		request.in_sync_count, true)
	if input_result != 0 {
		C.printf(c'fake-g17: submit rejected while staging input syncs error=%d count=%u\n',
			input_result, request.in_sync_count)
		return input_result
	}
	output_result, output_syncs := stage_sync_array(file.owner_key, request.out_syncs,
		request.out_sync_count, false)
	if output_result != 0 {
		C.printf(c'fake-g17: submit rejected while staging output syncs error=%d count=%u\n',
			output_result, request.out_sync_count)
		return output_result
	}
	dependency_result := wait_staged_syncs(&input_syncs)
	if dependency_result != 0 {
		C.printf(c'fake-g17: submit input dependency failed error=%d\n', dependency_result)
		return dependency_result
	}

	file.lock.acquire()
	mut queue := &workqueue.WorkQueue(unsafe { nil })
	for candidate in file.queues {
		if candidate.id == request.queue_id {
			unsafe { queue = candidate }
			break
		}
	}
	if queue == unsafe { nil } {
		file.lock.release()
		C.printf(c'fake-g17: submit rejected unknown queue=%u\n', request.queue_id)
		return -22
	}
	mut vm := file.find_vm(queue.vm_id) or {
		file.lock.release()
		return -22
	}
	mut has_render := false
	for index := u32(0); index < request.command_count; index++ {
		descriptor := commands[index].descriptor
		if descriptor.cmd_type == ioctl.asahi_cmd_render {
			if queue.caps & ioctl.asahi_queue_cap_render == 0 {
				file.lock.release()
				return -22
			}
			has_render = true
			mapping_result := validate_render_mappings(mut vm, &commands[index].render)
			if mapping_result != 0 {
				file.lock.release()
				C.printf(c'fake-g17: render mappings rejected error=%d encoder=0x%llx vusc=0x%llx fusc=0x%llx va=%u fa=%u\n',
					mapping_result, commands[index].render.encoder_ptr,
					commands[index].render.vertex_usc_base,
					commands[index].render.fragment_usc_base,
					commands[index].render.vertex_attachment_count,
					commands[index].render.fragment_attachment_count)
				return mapping_result
			}
		} else {
			if queue.caps & ioctl.asahi_queue_cap_compute == 0 {
				file.lock.release()
				return -22
			}
			mapping_result := validate_compute_mappings(mut vm,
				&commands[index].compute)
			if mapping_result != 0 {
				file.lock.release()
				C.printf(c'fake-g17: compute mappings rejected error=%d encoder=0x%llx end=0x%llx\n',
					mapping_result, commands[index].compute.encoder_ptr,
					commands[index].compute.encoder_end)
				return mapping_result
			}
		}
	}

	mut result_object := &gem.GemObject(unsafe { nil })
	for index := u32(0); index < request.command_count; index++ {
		descriptor := commands[index].descriptor
		if descriptor.result_size == 0 {
			if descriptor.result_offset != 0 {
				file.lock.release()
				return -22
			}
			continue
		}
		if request.result_handle == 0 {
			file.lock.release()
			return -22
		}
		if result_object == unsafe { nil } {
			for object in file.objects {
				if object.handle == request.result_handle {
					result_object = object
					break
				}
			}
		}
		if result_object == unsafe { nil } || descriptor.result_offset > result_object.size
			|| descriptor.result_size > result_object.size - descriptor.result_offset {
			file.lock.release()
			return -22
		}
	}

	fence := syncobj.new_fence(file.owner_key, timer.get_ns())
	if !install_output_syncs(&output_syncs, fence) {
		file.lock.release()
		return -22
	}
	started := timer.get_count()
	mut successful := true
	if has_render {
		report := run_fake_render(mut queue, mut vm, fence)
		successful = report.succeeded()
		if !successful {
			C.printf(c'fake-g17: verifier failed error=%u pass=%u entry=%u observed=%u expected=%u\n', report.error, report.pass, report.entry, report.observed_writes, report.expected_writes)
		} else {
			file.verified_jobs++
			if file.verified_jobs == 1 {
				C.printf(c'fake-g17: first Mesa render verified; actual writes=%u capacity=%u\n',
					report.expected_writes, fake_g17_max_writes)
			}
		}
	} else {
		successful = run_fake_compute(mut queue, fence)
	}
	ended := timer.get_count()
	write_results(commands, request.command_count, result_object, successful,
		started, ended)
	file.lock.release()
	return if successful { 0 } else { -5 }
}

fn (file &FakeG17File) ioctl_get_time(data &ioctl.DrmAsahiGetTime) int {
	_ = file
	mut request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 {
		return -22
	}
	request.gpu_timestamp = timer.get_count()
	return 0
}

fn (mut file FakeG17File) close_object_handle(handle u32) int {
	file.lock.acquire()
	for index, object in file.objects {
		if object.handle == handle {
			for mut vm in file.vms {
				vm.unbind_object(object)
			}
			file.objects.delete(index)
			file.lock.release()
			gem.unref(object)
			return 0
		}
	}
	file.lock.release()
	return -2
}

fn dispatch(handle voidptr, dev &drm.DrmDevice) ?&FakeG17File {
	return get_or_create_file(handle, dev)
}

fn get_params_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_get_params(unsafe { &ioctl.DrmAsahiGetParams(data) })
}

fn vm_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_vm_create(unsafe { &ioctl.DrmAsahiVmCreate(data) })
}

fn vm_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_vm_destroy(unsafe { &ioctl.DrmAsahiVmDestroy(data) })
}

fn gem_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_gem_create(unsafe { &ioctl.DrmAsahiGemCreate(data) })
}

fn gem_mmap_offset_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_gem_mmap_offset(unsafe { &ioctl.DrmAsahiGemMmapOffset(data) })
}

fn gem_bind_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_gem_bind(unsafe { &ioctl.DrmAsahiGemBind(data) })
}

fn queue_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_queue_create(unsafe { &ioctl.DrmAsahiQueueCreate(data) })
}

fn queue_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_queue_destroy(unsafe { &ioctl.DrmAsahiQueueDestroy(data) })
}

fn submit_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_submit(unsafe { &ioctl.DrmAsahiSubmit(data) })
}

fn get_time_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	file := dispatch(handle, dev) or { return -19 }
	return file.ioctl_get_time(unsafe { &ioctl.DrmAsahiGetTime(data) })
}

fn unsupported_bind_object(_dev &drm.DrmDevice, _handle voidptr,
	_data voidptr) int {
	return -95
}

pub fn close_gem_handle(_dev &drm.DrmDevice, handle voidptr,
	object_handle u32) int {
	mut file := lookup_file(handle) or { return -2 }
	return file.close_object_handle(object_handle)
}

pub fn mmap_handle(_dev &drm.DrmDevice, handle voidptr, page u64,
	_flags int) voidptr {
	mut file := lookup_file(handle) or { return unsafe { nil } }
	return file.mmap_page(page)
}

pub fn gem_export_handler(dev &drm.DrmDevice, handle voidptr,
	object_handle u32) ?&gem.GemObject {
	mut file := get_or_create_file(handle, dev) or { return none }
	return file.get_object_ref(object_handle)
}

pub fn gem_import_handler(dev &drm.DrmDevice, handle voidptr,
	object &gem.GemObject) ?u32 {
	mut file := get_or_create_file(handle, dev) or { return none }
	return file.import_object(object)
}

fn drm_ioctls() []drm.DrmIoctl {
	return [
		drm.DrmIoctl{cmd: ioctl.drm_asahi_get_params, size: u32(sizeof(ioctl.DrmAsahiGetParams)), direction: drm.ioctl_write | drm.ioctl_read, handler: get_params_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_vm_create, size: u32(sizeof(ioctl.DrmAsahiVmCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: vm_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_vm_destroy, size: u32(sizeof(ioctl.DrmAsahiVmDestroy)), direction: drm.ioctl_write, handler: vm_destroy_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_create, size: u32(sizeof(ioctl.DrmAsahiGemCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: gem_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_mmap_offset, size: u32(sizeof(ioctl.DrmAsahiGemMmapOffset)), direction: drm.ioctl_write | drm.ioctl_read, handler: gem_mmap_offset_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_bind, size: u32(sizeof(ioctl.DrmAsahiGemBind)), direction: drm.ioctl_write, handler: gem_bind_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_queue_create, size: u32(sizeof(ioctl.DrmAsahiQueueCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: queue_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_queue_destroy, size: u32(sizeof(ioctl.DrmAsahiQueueDestroy)), direction: drm.ioctl_write, handler: queue_destroy_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_submit, size: u32(sizeof(ioctl.DrmAsahiSubmit)), direction: drm.ioctl_write, handler: submit_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_get_time, size: u32(sizeof(ioctl.DrmAsahiGetTime)), direction: drm.ioctl_write | drm.ioctl_read, handler: get_time_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_bind_object, size: u32(sizeof(ioctl.DrmAsahiGemBindObject)), direction: drm.ioctl_write | drm.ioctl_read, handler: unsupported_bind_object},
	]
}

// Register a distinct render node. This function performs no hardware probe
// and is safe to call only when explicitly selected for VM testing.
pub fn initialise() bool {
	if fake_driver_state.initialized {
		return true
	}
	if !ioctl.validate_asahi_25_layouts() {
		println('fake-g17: Asahi UAPI layout validation failed')
		return false
	}
	mut driver := &drm.DrmDriver{
		name: 'asahi'
		desc: 'Vinix software-only fake G17 verifier'
		major: 1
		minor: 0
		patchlevel: 0
		features: drm.driver_gem | drm.driver_render | drm.driver_compute
		ioctls: drm_ioctls()
		file_close: release_handle
		gem_close: close_gem_handle
		gem_export: gem_export_handler
		gem_import: gem_import_handler
		mmap: mmap_handle
	}
	device := drm.register_driver(driver) or {
		println('fake-g17: DRM registration failed')
		return false
	}
	fake_driver_state.device = device
	fake_driver_state.initialized = true
	println('fake-g17: software-only G17C render node ready as renderD${128 + device.dev_id}')
	return true
}

pub fn shutdown() {
	if !fake_driver_state.initialized {
		return
	}
	if fake_driver_state.device != unsafe { nil } {
		drm.unregister_device(fake_driver_state.device)
		fake_driver_state.device = unsafe { nil }
	}
	fake_driver_state.initialized = false
}
