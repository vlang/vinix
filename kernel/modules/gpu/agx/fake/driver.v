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
import gpu.agx.bo as agxbo
import gpu.agx.command as agxcommand
import gpu.agx.compute as agxcompute
import gpu.agx.render as agxrender
import gpu.agx.submission as agxsubmission
import gpu.agx.vm as agxvm
import gpu.agx.workqueue
import klock
import sched
import usercopy
import aarch64.timer

const max_submission_syncs = agxsubmission.max_syncs
const max_submission_commands = agxsubmission.max_commands
const max_command_attachments = u32(16)

@[heap]
struct FakeG17File {
mut:
	dev           &drm.DrmDevice = unsafe { nil }
	vms           []&FakeG17Vm
	queues        []&workqueue.WorkQueue
	objects       agxbo.Table
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

// Lock order is global file map -> per-file -> fake VM. The global map lock is
// always released before close() takes the file lock, and no VM operation may
// call back into the file or common BO table. VM methods drop their lock before
// final GEM unrefs, so backend mapping teardown remains outside common BO code.

__global (
	fake_driver_state  FakeG17DriverState
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
	file.objects.release_all()
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
	return file.objects.get_ref(handle)
}

fn (mut file FakeG17File) import_object(object &gem.GemObject) ?u32 {
	if object == unsafe { nil } {
		return none
	}
	file.lock.acquire()
	handle := file.objects.import_object(object) or {
		file.lock.release()
		return none
	}
	file.lock.release()
	return handle
}

fn (mut file FakeG17File) authorize_mmap(handle u32) ?u64 {
	file.lock.acquire()
	defer { file.lock.release() }
	return file.objects.authorize_mmap(handle)
}

fn (mut file FakeG17File) mmap_page(page u64) voidptr {
	file.lock.acquire()
	defer { file.lock.release() }
	return file.objects.mmap_page(page)
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
		feat_compat: ioctl.asahi_feat_gettime | ioctl.asahi_feat_vinix_fake_g17
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
		C.printf(c'fake-g17: rejected VM request extensions=0x%llx pad=%u start=0x%llx end=0x%llx\n', request.extensions, request.pad, request.kernel_start, request.kernel_end)
		return -22
	}
	file.lock.acquire()
	id := next_unused_vm_id(&file) or {
		file.lock.release()
		return -24
	}
	vm := new_vm(id, request.kernel_start, request.kernel_end) or {
		C.printf(c'fake-g17: rejected VM range start=0x%llx end=0x%llx pad=%u\n', request.kernel_start, request.kernel_end, request.pad)
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
	file.objects.add_created(object)
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
	mut vm := file.find_vm(request.vm_id) or { return -22 }
	if !agxvm.valid_bind_request(request, vm.kernel_start, vm.kernel_end) {
		return -22
	}
	match request.op {
		ioctl.asahi_bind_op_bind {
			object := file.get_object_ref(request.handle) or { return -2 }
			flags := (if request.flags & ioctl.asahi_bind_read != 0 { vm_read } else { u32(0) }) | (if request.flags & ioctl.asahi_bind_write != 0 {
				vm_write
			} else {
				u32(0)
			})
			result := vm.bind(object, request.addr, request.range, request.offset, flags)
			gem.unref(object)
			return result
		}
		ioctl.asahi_bind_op_unbind {
			return vm.unbind(request.addr, request.range)
		}
		ioctl.asahi_bind_op_unbind_all {
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
	known_caps := ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_blit | ioctl.asahi_queue_cap_compute
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
	queue := workqueue.new_workqueue(id, request.vm_id, request.priority, request.queue_caps) or {
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

fn wait_staged_syncs(staged &agxsubmission.SyncArray) int {
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

fn mapped(mut vm FakeG17Vm, address u64, bytes u64, writable bool) bool {
	if address == 0 {
		return true
	}
	resolved := vm.resolve(address, if bytes == 0 { u64(1) } else { bytes }, writable) or { return false }
	resolved.release()
	return true
}

fn validate_attachments(mut vm FakeG17Vm,
	attachments [16]agxcommand.Attachment, count u32) int {
	if count > agxcommand.max_attachments {
		return -22
	}
	for index := u32(0); index < count; index++ {
		attachment := attachments[index]
		if attachment.order < 1 || attachment.order > 6
			|| attachment.address == 0 || attachment.size_bytes == 0
			|| !mapped(mut vm, attachment.address, attachment.size_bytes, false) {
			return -22
		}
	}
	return 0
}

fn validate_render_mappings(mut vm FakeG17Vm, command &agxrender.Command,
	resources []FakeG17ResourceReference) int {
	if command.encoder_ptr == 0 || !vm.contains_address(command.vertex_usc_base)
		|| !vm.contains_address(command.fragment_usc_base) {
		return -22
	}
	for resource in resources {
		if resource.provenance != u32(G17DescriptorProvenance.gpu_va)
			&& resource.provenance != u32(G17DescriptorProvenance.bo_resource) {
			return -22
		}
		if !mapped(mut vm, resource.address, resource.size, resource.access & fake_g17_vm_write != 0) {
			return -22
		}
	}
	return 0
}

fn validate_compute_mappings(mut vm FakeG17Vm,
	command &agxcompute.Command) int {
	if command.encoder_ptr == 0 || command.encoder_end <= command.encoder_ptr
		|| !mapped(mut vm, command.encoder_ptr, command.encoder_end - command.encoder_ptr, false)
		|| !vm.contains_address(command.usc_base)
		|| !mapped(mut vm, command.helper_arg, 8, false)
		|| !mapped(mut vm, command.sampler_array, if command.sampler_count == 0 {
			u64(1)
		} else {
			u64(command.sampler_count)
		}, false) {
		return -22
	}
	return validate_attachments(mut vm, command.attachments, command.attachment_count)
}

fn write_results(commands [2]agxsubmission.Command, count u32, object &gem.GemObject,
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
				C.memcpy(voidptr(object.virt_addr + descriptor.result_offset), voidptr(&result), sizeof(ioctl.DrmAsahiResultRender))
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
				C.memcpy(voidptr(object.virt_addr + descriptor.result_offset), voidptr(&result), sizeof(ioctl.DrmAsahiResultCompute))
			}
		}
	}
}

fn run_fake_render(mut queue workqueue.WorkQueue, mut vm FakeG17Vm,
	fence &syncobj.DmaFence, resources []FakeG17ResourceReference) FakeG17Verification {
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
		return FakeG17Verification{ error: fake_g17_invalid_argument }
	}
	unsafe { C.memset(command, 0, g17_command_bytes) }
	if !initialize_render_descriptor(descriptor, g17_descriptor_bytes) {
		unsafe {
			free(command)
			free(descriptor)
		}
		syncobj.signal_error(fence, -5)
		return FakeG17Verification{ error: fake_g17_invalid_argument }
	}
	mut inputs := FakeG17EncoderInputs{}
	mut writes := []FakeG17ExpectedWrite{len: int(fake_g17_max_writes)}
	encoding := encode_fake_g17_3d(command, g17_command_bytes, descriptor, g17_descriptor_bytes, vm.kernel_start, &inputs, mut writes)
	if !encoding.succeeded() {
		unsafe {
			writes.free()
			free(command)
			free(descriptor)
		}
		syncobj.signal_error(fence, -5)
		return FakeG17Verification{ error: encoding.error }
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
		resources: resources
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
	command_result, commands := agxsubmission.stage_commands(request.commands, request.command_count)
	if command_result != 0 {
		C.printf(c'fake-g17: submit rejected while staging commands error=%d count=%u\n', command_result, request.command_count)
		return command_result
	}
	input_result, input_syncs := agxsubmission.stage_sync_array(file.owner_key, request.in_syncs, request.in_sync_count, true)
	if input_result != 0 {
		C.printf(c'fake-g17: submit rejected while staging input syncs error=%d count=%u\n', input_result, request.in_sync_count)
		return input_result
	}
	output_result, output_syncs := agxsubmission.stage_sync_array(file.owner_key, request.out_syncs, request.out_sync_count, false)
	if output_result != 0 {
		C.printf(c'fake-g17: submit rejected while staging output syncs error=%d count=%u\n', output_result, request.out_sync_count)
		return output_result
	}
	dependency_result := wait_staged_syncs(&input_syncs)
	if dependency_result != 0 {
		C.printf(c'fake-g17: submit input dependency failed error=%d\n', dependency_result)
		return dependency_result
	}
	mut render_resources := []FakeG17ResourceReference{}
	for index := u32(0); index < request.command_count; index++ {
		if commands[index].descriptor.cmd_type == ioctl.asahi_cmd_render {
			render_resources = stage_render_resource_references(&commands[index].render)
			break
		}
	}
	defer {
		unsafe { render_resources.free() }
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
	mut render_index := -1
	for index := u32(0); index < request.command_count; index++ {
		descriptor := commands[index].descriptor
		if descriptor.cmd_type == ioctl.asahi_cmd_render {
			if queue.caps & ioctl.asahi_queue_cap_render == 0 {
				file.lock.release()
				return -22
			}
			render_index = int(index)
			mapping_result := validate_render_mappings(mut vm, &commands[index].render, render_resources)
			if mapping_result != 0 {
				file.lock.release()
				C.printf(c'fake-g17: render mappings rejected error=%d encoder=0x%llx vusc=0x%llx fusc=0x%llx va=%u fa=%u\n', mapping_result, commands[index].render.encoder_ptr, commands[index].render.vertex_usc_base, commands[index].render.fragment_usc_base, commands[index].render.vertex_attachment_count, commands[index].render.fragment_attachment_count)
				return mapping_result
			}
		} else {
			if queue.caps & ioctl.asahi_queue_cap_compute == 0 {
				file.lock.release()
				return -22
			}
			mapping_result := validate_compute_mappings(mut vm, &commands[index].compute)
			if mapping_result != 0 {
				file.lock.release()
				C.printf(c'fake-g17: compute mappings rejected error=%d encoder=0x%llx end=0x%llx\n', mapping_result, commands[index].compute.encoder_ptr, commands[index].compute.encoder_end)
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
			result_object = file.objects.find(request.result_handle) or { unsafe { nil } }
		}
		if result_object == unsafe { nil } || descriptor.result_offset > result_object.size
			|| descriptor.result_size > result_object.size - descriptor.result_offset {
			file.lock.release()
			return -22
		}
	}

	fence := syncobj.new_fence(file.owner_key, timer.get_ns())
	if !agxsubmission.install_output_syncs(&output_syncs, fence) {
		file.lock.release()
		return -22
	}
	started := timer.get_count()
	mut successful := true
	if render_index >= 0 {
		report := run_fake_render(mut queue, mut vm, fence, render_resources)
		successful = report.succeeded()
		if !successful {
			C.printf(c'fake-g17: verifier failed error=%u pass=%u entry=%u observed=%u expected=%u\n', report.error, report.pass, report.entry, report.observed_writes, report.expected_writes)
		} else {
			file.verified_jobs++
			if file.verified_jobs == 1 {
				render_command := commands[render_index].render
				C.printf(c'fake-g17: first Mesa render verified; id=%u size=%ux%u resources=%u actual writes=%u capacity=%u\n', render_command.fragment_command_id, render_command.framebuffer_width, render_command.framebuffer_height, u32(render_resources.len), report.expected_writes, fake_g17_max_writes)
			}
		}
	} else {
		successful = run_fake_compute(mut queue, fence)
	}
	ended := timer.get_count()
	write_results(commands, request.command_count, result_object, successful, started, ended)
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
	object := file.objects.remove(handle) or {
		file.lock.release()
		return -2
	}
	for mut vm in file.vms {
		vm.unbind_object(object)
	}
	file.lock.release()
	gem.unref(object)
	return 0
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
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_params, size: u32(sizeof(ioctl.DrmAsahiGetParams)), direction: drm.ioctl_write | drm.ioctl_read, handler: get_params_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_create, size: u32(sizeof(ioctl.DrmAsahiVmCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: vm_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_destroy, size: u32(sizeof(ioctl.DrmAsahiVmDestroy)), direction: drm.ioctl_write, handler: vm_destroy_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_create, size: u32(sizeof(ioctl.DrmAsahiGemCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: gem_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_mmap_offset, size: u32(sizeof(ioctl.DrmAsahiGemMmapOffset)), direction: drm.ioctl_write | drm.ioctl_read, handler: gem_mmap_offset_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind, size: u32(sizeof(ioctl.DrmAsahiGemBind)), direction: drm.ioctl_write, handler: gem_bind_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_create, size: u32(sizeof(ioctl.DrmAsahiQueueCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: queue_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_destroy, size: u32(sizeof(ioctl.DrmAsahiQueueDestroy)), direction: drm.ioctl_write, handler: queue_destroy_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_submit, size: u32(sizeof(ioctl.DrmAsahiSubmit)), direction: drm.ioctl_write, handler: submit_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_time, size: u32(sizeof(ioctl.DrmAsahiGetTime)), direction: drm.ioctl_write | drm.ioctl_read, handler: get_time_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind_object, size: u32(sizeof(ioctl.DrmAsahiGemBindObject)), direction: drm.ioctl_write | drm.ioctl_read, handler: unsupported_bind_object },
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
