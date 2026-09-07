// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module virtio_gpu

// Minimal VirtIO-GPU/VirGL DRM driver for QEMU's ARM `virt` machine.
//
// QEMU exposes the device through legacy VirtIO-MMIO so Vinix does not need
// ARM64 PCI ECAM just to use the virtual GPU. Commands are deliberately
// synchronous: this keeps GEM lifetime and CPU readback ordering exact while
// still executing every Gallium command on virglrenderer and the host GPU.
import aarch64.cpu
import aarch64.uart
import drm
import drm.gem
import drm.ioctl
import klock
import memory
import time
import usercopy

const reg_magic = u64(0x000)
const reg_version = u64(0x004)
const reg_device_id = u64(0x008)
const reg_host_features = u64(0x010)
const reg_guest_features = u64(0x020)
const reg_guest_page_size = u64(0x028)
const reg_queue_sel = u64(0x030)
const reg_queue_num_max = u64(0x034)
const reg_queue_num = u64(0x038)
const reg_queue_align = u64(0x03c)
const reg_queue_pfn = u64(0x040)
const reg_queue_notify = u64(0x050)
const reg_interrupt_status = u64(0x060)
const reg_interrupt_ack = u64(0x064)
const reg_status = u64(0x070)
const reg_config = u64(0x100)

const virtio_magic = u32(0x74726976)
const virtio_id_gpu = u32(16)
const virtio_gpu_f_virgl = u32(1) << 0

const status_acknowledge = u32(1)
const status_driver = u32(2)
const status_driver_ok = u32(4)
const status_failed = u32(128)

const descriptor_next = u16(1)
const descriptor_write = u16(2)

const mmio_base = u64(0x0a000000)
const mmio_slot_size = u64(0x200)
const mmio_slot_count = u64(32)
const queue_align = u64(4096)
const wanted_queue_size = u16(8)
const request_capacity = u64(1024 * 1024 + 4096)
const response_capacity = u64(128 * 1024)
const command_timeout_ns = u64(5_000_000_000)

const cmd_resource_unref = u32(0x0102)
const cmd_resource_attach_backing = u32(0x0106)
const cmd_get_capset_info = u32(0x0108)
const cmd_get_capset = u32(0x0109)
const cmd_ctx_create = u32(0x0200)
const cmd_ctx_destroy = u32(0x0201)
const cmd_ctx_attach_resource = u32(0x0202)
const cmd_ctx_detach_resource = u32(0x0203)
const cmd_resource_create_3d = u32(0x0204)
const cmd_transfer_to_host_3d = u32(0x0205)
const cmd_transfer_from_host_3d = u32(0x0206)
const cmd_submit_3d = u32(0x0207)

const resp_ok_nodata = u32(0x1100)
const resp_ok_capset_info = u32(0x1102)
const resp_ok_capset = u32(0x1103)
const resp_error_base = u32(0x1200)
const control_flag_fence = u32(1)

const max_capsets = 8
const max_files = 256
const max_resources = 4096

@[packed]
struct ControlHeader {
mut:
	type_    u32
	flags    u32
	fence_id u64
	ctx_id   u32
	ring_idx u8
	padding  [3]u8
}

@[packed]
struct ResourceCreate3d {
mut:
	hdr         ControlHeader
	resource_id u32
	target      u32
	format      u32
	bind        u32
	width       u32
	height      u32
	depth       u32
	array_size  u32
	last_level  u32
	nr_samples  u32
	flags       u32
	padding     u32
}

@[packed]
struct ResourceCommand {
mut:
	hdr         ControlHeader
	resource_id u32
	padding     u32
}

@[packed]
struct ResourceAttachBacking {
mut:
	hdr         ControlHeader
	resource_id u32
	nr_entries  u32
}

@[packed]
struct MemoryEntry {
mut:
	address u64
	length  u32
	padding u32
}

@[packed]
struct ContextCreate {
mut:
	hdr          ControlHeader
	name_length  u32
	context_init u32
	debug_name   [64]u8
}

@[packed]
struct ContextCommand {
mut:
	hdr ControlHeader
}

@[packed]
struct Transfer3d {
mut:
	hdr          ControlHeader
	box          ioctl.DrmVirtgpuBox
	offset       u64
	resource_id  u32
	level        u32
	stride       u32
	layer_stride u32
}

@[packed]
struct Submit3d {
mut:
	hdr     ControlHeader
	size    u32
	padding u32
}

@[packed]
struct GetCapsetInfo {
mut:
	hdr          ControlHeader
	capset_index u32
	padding      u32
}

@[packed]
struct CapsetInfoResponse {
mut:
	hdr         ControlHeader
	capset_id   u32
	max_version u32
	max_size    u32
	padding     u32
}

@[packed]
struct GetCapset {
mut:
	hdr            ControlHeader
	capset_id      u32
	capset_version u32
}

struct CapsetInfo {
mut:
	id          u32
	max_version u32
	max_size    u32
}

struct Transport {
mut:
	base           u64
	hhdm           u64
	queue_size     u16
	desc           u64
	avail          u64
	used           u64
	last_used      u16
	next_available u16
	request_phys   u64
	request_virt   u64
	response_phys  u64
	response_virt  u64
	next_fence     u64
	capset_count   u32
	capsets        [max_capsets]CapsetInfo
	capset_mask    u64
	ready          bool
	lock           klock.Lock
}

@[heap]
struct VirtioObject {
mut:
	gem_object  &gem.GemObject = unsafe { nil }
	resource_id u32
	references  u32
}

struct VirtioFile {
mut:
	context_id      u32
	context_created bool
	objects         []&VirtioObject
	mmap_objects    []&VirtioObject
	lock            klock.Lock
}

__global (
	virtgpu_transport Transport
	files_lock        klock.Lock
	files             = map[u64]&VirtioFile{}
	next_context_id   = u32(1)
	objects_lock      klock.Lock
	objects_by_handle [max_resources]&VirtioObject
	next_resource_id  = u32(1)
)

fn mmio_r32(address u64) u32 {
	value := unsafe { *&u32(address) }
	cpu.dmb_ish()
	return value
}

fn mmio_w32(address u64, value u32) {
	cpu.dmb_ish()
	unsafe {
		*&u32(address) = value
	}
}

fn align_up(value u64, alignment u64) u64 {
	return (value + alignment - 1) & ~(alignment - 1)
}

fn write_descriptor(index u16, address u64, length u32, flags u16, next u16) {
	descriptor := virtgpu_transport.desc + u64(index) * 16
	unsafe {
		*&u64(descriptor) = address
		*&u32(descriptor + 8) = length
		*&u16(descriptor + 12) = flags
		*&u16(descriptor + 14) = next
	}
}

// Submit one control command and wait until virglrenderer has acknowledged it.
// `payload` is either a kernel pointer or a checked userspace address and is
// appended to the command in the same device-readable descriptor.
fn submit(command voidptr, command_length u64, payload u64, payload_length u64,
	payload_is_user bool, response voidptr, response_length u64, fenced bool) (u32, u32) {
	if !virtgpu_transport.ready || command == unsafe { nil }
		|| command_length < sizeof(ControlHeader) || command_length > request_capacity
		|| payload_length > request_capacity - command_length || response_length > response_capacity {
		return 0, 0
	}

	virtgpu_transport.lock.acquire()
	defer {
		virtgpu_transport.lock.release()
	}

	unsafe {
		C.memcpy(voidptr(virtgpu_transport.request_virt), command, command_length)
		C.memset(voidptr(virtgpu_transport.response_virt), 0, response_capacity)
	}
	if payload_length != 0 {
		destination := voidptr(virtgpu_transport.request_virt + command_length)
		if payload_is_user {
			if !usercopy.copy_from_user(destination, payload, payload_length) {
				return 0, 0
			}
		} else {
			if payload == 0 {
				return 0, 0
			}
			unsafe { C.memcpy(destination, voidptr(payload), payload_length) }
		}
	}

	if fenced {
		virtgpu_transport.next_fence++
		if virtgpu_transport.next_fence == 0 {
			virtgpu_transport.next_fence++
		}
		unsafe {
			*&u32(virtgpu_transport.request_virt + 4) = control_flag_fence
			*&u64(virtgpu_transport.request_virt + 8) = virtgpu_transport.next_fence
		}
	}

	write_descriptor(0, virtgpu_transport.request_phys, u32(command_length + payload_length), descriptor_next, 1)
	write_descriptor(1, virtgpu_transport.response_phys, u32(response_capacity), descriptor_write, 0)

	position := u64(virtgpu_transport.next_available % virtgpu_transport.queue_size)
	unsafe {
		*&u16(virtgpu_transport.avail + 4 + position * 2) = 0
	}
	virtgpu_transport.next_available++
	cpu.dmb_ish()
	unsafe {
		*&u16(virtgpu_transport.avail + 2) = virtgpu_transport.next_available
	}
	mmio_w32(virtgpu_transport.base + reg_queue_notify, 0)

	deadline := time.monotonic_ns() + command_timeout_ns
	mut spins := u64(0)
	for {
		cpu.dmb_ish()
		used_index := unsafe { *&u16(virtgpu_transport.used + 2) }
		if used_index != virtgpu_transport.last_used {
			break
		}
		spins++
		if spins > 100_000_000 || time.monotonic_ns() >= deadline {
			C.printf(c'virtio-gpu: command 0x%x timed out\n', unsafe { *&u32(virtgpu_transport.request_virt) })
			return 0, 0
		}
	}

	entry_position := u64(virtgpu_transport.last_used % virtgpu_transport.queue_size)
	used_entry := virtgpu_transport.used + 4 + entry_position * 8
	used_length := unsafe { *&u32(used_entry + 4) }
	virtgpu_transport.last_used++
	cpu.dmb_ish()

	interrupts := mmio_r32(virtgpu_transport.base + reg_interrupt_status)
	if interrupts != 0 {
		mmio_w32(virtgpu_transport.base + reg_interrupt_ack, interrupts)
	}

	response_type := unsafe { *&u32(virtgpu_transport.response_virt) }
	if response_type >= resp_error_base {
		C.printf(c'virtio-gpu: host rejected command 0x%x with response 0x%x\n', unsafe { *&u32(virtgpu_transport.request_virt) }, response_type)
		return response_type, used_length
	}
	if response != unsafe { nil } && response_length != 0 {
		copy_length := if response_length < u64(used_length) {
			response_length
		} else {
			u64(used_length)
		}
		unsafe { C.memcpy(response, voidptr(virtgpu_transport.response_virt), copy_length) }
	}
	return response_type, used_length
}

fn header(type_ u32, context_id u32) ControlHeader {
	return ControlHeader{
		type_: type_
		ctx_id: context_id
	}
}

fn nodata(command voidptr, command_length u64, payload voidptr, payload_length u64,
	fenced bool) bool {
	response_type, _ := submit(command, command_length, u64(payload), payload_length, false, unsafe { nil }, 0, fenced)
	return response_type == resp_ok_nodata
}

fn get_file(handle voidptr) ?&VirtioFile {
	if handle == unsafe { nil } {
		return none
	}
	key := u64(handle)
	files_lock.acquire()
	if key in files {
		file := files[key] or {
			files_lock.release()
			return none
		}
		files_lock.release()
		return file
	}
	if files.len >= max_files {
		files_lock.release()
		return none
	}
	context_id := next_context_id
	next_context_id++
	if next_context_id == 0 {
		next_context_id = 1
	}
	mut file := &VirtioFile{
		context_id: context_id
	}
	files[key] = file
	files_lock.release()
	return file
}

fn ensure_context(mut file VirtioFile) bool {
	file.lock.acquire()
	defer {
		file.lock.release()
	}
	if file.context_created {
		return true
	}
	mut request := ContextCreate{
		hdr: header(cmd_ctx_create, file.context_id)
		name_length: 5
	}
	name := 'vinix'
	for i in 0 .. name.len {
		request.debug_name[i] = name[i]
	}
	if !nodata(voidptr(&request), sizeof(request), unsafe { nil }, 0, false) {
		return false
	}
	file.context_created = true
	return true
}

fn find_owned(mut file VirtioFile, handle u32) ?&VirtioObject {
	for object in file.objects {
		if object.gem_object != unsafe { nil } && object.gem_object.handle == handle {
			return object
		}
	}
	return none
}

fn allocate_resource_id() u32 {
	objects_lock.acquire()
	id := next_resource_id
	next_resource_id++
	if next_resource_id == 0 {
		next_resource_id = 1
	}
	objects_lock.release()
	return id
}

fn release_object(_object &VirtioObject) {
	mut object := unsafe { _object }
	if object == unsafe { nil } || object.gem_object == unsafe { nil } {
		return
	}
	mut last := false
	objects_lock.acquire()
	if object.references > 0 {
		object.references--
		last = object.references == 0
	}
	if last && object.gem_object.handle < max_resources
		&& objects_by_handle[object.gem_object.handle] == object {
		objects_by_handle[object.gem_object.handle] = unsafe { nil }
	}
	objects_lock.release()

	if last {
		mut request := ResourceCommand{
			hdr: header(cmd_resource_unref, 0)
			resource_id: object.resource_id
		}
		nodata(voidptr(&request), sizeof(request), unsafe { nil }, 0, false)
	}
	gem.unref(object.gem_object)
	if last {
		unsafe { free(voidptr(object)) }
	}
}

fn context_resource(command_type u32, context_id u32, resource_id u32) bool {
	mut request := ResourceCommand{
		hdr: header(command_type, context_id)
		resource_id: resource_id
	}
	return nodata(voidptr(&request), sizeof(request), unsafe { nil }, 0, false)
}

fn retain_object(_object &VirtioObject) {
	mut object := unsafe { _object }
	objects_lock.acquire()
	object.references++
	objects_lock.release()
	gem.ref_obj(object.gem_object)
}

fn remove_owned(mut file VirtioFile, handle u32) int {
	file.lock.acquire()
	for index, object in file.objects {
		if object.gem_object != unsafe { nil } && object.gem_object.handle == handle {
			file.objects.delete(index)
			file.lock.release()
			context_resource(cmd_ctx_detach_resource, file.context_id, object.resource_id)
			release_object(object)
			return 0
		}
	}
	file.lock.release()
	return -2
}

fn map_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut request := unsafe { &ioctl.DrmVirtgpuMap(data) }
	if request.pad != 0 {
		return -22
	}
	mut file := get_file(handle) or { return -9 }
	file.lock.acquire()
	object := find_owned(mut file, request.handle) or {
		file.lock.release()
		return -2
	}
	mut present := false
	for mapped in file.mmap_objects {
		if mapped == object {
			present = true
			break
		}
	}
	if !present {
		retain_object(object)
		file.mmap_objects << object
	}
	request.offset = gem.create_mmap_offset(object.gem_object)
	file.lock.release()
	return 0
}

fn getparam_handler(_dev &drm.DrmDevice, _handle voidptr, data voidptr) int {
	request := unsafe { &ioctl.DrmVirtgpuGetparam(data) }
	value := match request.param {
		ioctl.virtgpu_param_3d_features {
			u32(1)
		}
		ioctl.virtgpu_param_capset_query_fix {
			u32(1)
		}
		ioctl.virtgpu_param_supported_capset_ids {
			u32(virtgpu_transport.capset_mask)
		}
		ioctl.virtgpu_param_resource_blob, ioctl.virtgpu_param_host_visible, ioctl.virtgpu_param_cross_device, ioctl.virtgpu_param_context_init, ioctl.virtgpu_param_explicit_debug_name {
			u32(0)
		}
		else {
			return -22
		}
	}
	if request.value == 0 || !usercopy.copy_to_user(request.value, voidptr(&value), sizeof(u32)) {
		return -14
	}
	return 0
}

fn resource_create_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut request := unsafe { &ioctl.DrmVirtgpuResourceCreate(data) }
	if request.width == 0 || request.height == 0 || request.depth == 0 || request.array_size == 0
		|| request.size > 512 * 1024 * 1024 {
		return -22
	}
	mut file := get_file(handle) or { return -12 }
	if !ensure_context(mut file) {
		return -5
	}
	size := if request.size == 0 { u64(page_size) } else { u64(request.size) }
	object := gem.create(size) or { return -12 }
	resource_id := allocate_resource_id()
	mut create := ResourceCreate3d{
		hdr: header(cmd_resource_create_3d, 0)
		resource_id: resource_id
		target: request.target
		format: request.format
		bind: request.bind
		width: request.width
		height: request.height
		depth: request.depth
		array_size: request.array_size
		last_level: request.last_level
		nr_samples: request.nr_samples
		flags: request.flags
	}
	if !nodata(voidptr(&create), sizeof(create), unsafe { nil }, 0, true) {
		gem.unref(object)
		return -5
	}
	mut attach := ResourceAttachBacking{
		hdr: header(cmd_resource_attach_backing, 0)
		resource_id: resource_id
		nr_entries: 1
	}
	mut entry := MemoryEntry{
		address: object.phys_addr
		length: u32(object.size)
	}
	if object.size > u64(0xffff_ffff)
		|| !nodata(voidptr(&attach), sizeof(attach), voidptr(&entry), sizeof(entry), false) {
		mut unref := ResourceCommand{
			hdr: header(cmd_resource_unref, 0)
			resource_id: resource_id
		}
		nodata(voidptr(&unref), sizeof(unref), unsafe { nil }, 0, false)
		gem.unref(object)
		return -5
	}
	if !context_resource(cmd_ctx_attach_resource, file.context_id, resource_id) {
		mut unref := ResourceCommand{
			hdr: header(cmd_resource_unref, 0)
			resource_id: resource_id
		}
		nodata(voidptr(&unref), sizeof(unref), unsafe { nil }, 0, false)
		gem.unref(object)
		return -5
	}
	mut virtio_object := &VirtioObject{
		gem_object: object
		resource_id: resource_id
		references: 1
	}
	objects_lock.acquire()
	if object.handle >= max_resources || objects_by_handle[object.handle] != unsafe { nil } {
		objects_lock.release()
		context_resource(cmd_ctx_detach_resource, file.context_id, resource_id)
		release_object(virtio_object)
		return -12
	}
	objects_by_handle[object.handle] = virtio_object
	objects_lock.release()
	file.lock.acquire()
	file.objects << virtio_object
	file.lock.release()
	request.bo_handle = object.handle
	request.res_handle = resource_id
	return 0
}

fn resource_info_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut request := unsafe { &ioctl.DrmVirtgpuResourceInfo(data) }
	mut file := get_file(handle) or { return -9 }
	file.lock.acquire()
	object := find_owned(mut file, request.bo_handle) or {
		file.lock.release()
		return -2
	}
	request.res_handle = object.resource_id
	request.size = u32(object.gem_object.size)
	request.blob_mem = 0
	file.lock.release()
	return 0
}

fn transfer_handler(handle voidptr, data voidptr, to_host bool) int {
	request := unsafe { &ioctl.DrmVirtgpuTransfer(data) }
	if request.stride != 0 || request.layer_stride != 0 || request.box.w == 0 || request.box.h == 0
		|| request.box.d == 0 {
		return -22
	}
	mut file := get_file(handle) or { return -9 }
	if !ensure_context(mut file) {
		return -5
	}
	file.lock.acquire()
	object := find_owned(mut file, request.bo_handle) or {
		file.lock.release()
		return -2
	}
	resource_id := object.resource_id
	file.lock.release()
	mut command := Transfer3d{
		hdr: header(if to_host {
			cmd_transfer_to_host_3d
		} else {
			cmd_transfer_from_host_3d
		}, file.context_id)
		box: request.box
		offset: u64(request.offset)
		resource_id: resource_id
		level: request.level
		stride: request.stride
		layer_stride: request.layer_stride
	}
	return if nodata(voidptr(&command), sizeof(command), unsafe { nil }, 0, true) { 0 } else { -5 }
}

fn transfer_from_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	return transfer_handler(handle, data, false)
}

fn transfer_to_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	return transfer_handler(handle, data, true)
}

fn execbuffer_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut request := unsafe { &ioctl.DrmVirtgpuExecbuffer(data) }
	known_flags := ioctl.virtgpu_execbuf_fence_fd_in | ioctl.virtgpu_execbuf_fence_fd_out | ioctl.virtgpu_execbuf_ring_idx
	if request.flags & ~known_flags != 0 || request.flags != 0 || request.size == 0
		|| request.size > request_capacity - sizeof(Submit3d) || request.command == 0
		|| request.num_in_syncobjs != 0 || request.num_out_syncobjs != 0 {
		return -22
	}
	mut file := get_file(handle) or { return -9 }
	if !ensure_context(mut file) {
		return -5
	}
	if request.num_bo_handles > 4096 || (request.num_bo_handles != 0 && request.bo_handles == 0) {
		return -22
	}
	file.lock.acquire()
	for index := u32(0); index < request.num_bo_handles; index++ {
		bo_handle := usercopy.read_u32(request.bo_handles + u64(index) * 4) or {
			file.lock.release()
			return -14
		}
		find_owned(mut file, bo_handle) or {
			file.lock.release()
			return -2
		}
	}
	file.lock.release()
	mut command := Submit3d{
		hdr: header(cmd_submit_3d, file.context_id)
		size: request.size
	}
	response_type, _ := submit(voidptr(&command), sizeof(command), request.command, request.size, true, unsafe { nil }, 0, true)
	request.fence_fd = -1
	return if response_type == resp_ok_nodata { 0 } else { -5 }
}

fn wait_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	request := unsafe { &ioctl.DrmVirtgpuWait(data) }
	if request.flags & ~ioctl.virtgpu_wait_nowait != 0 {
		return -22
	}
	mut file := get_file(handle) or { return -9 }
	file.lock.acquire()
	find_owned(mut file, request.handle) or {
		file.lock.release()
		return -2
	}
	file.lock.release()
	// Every command is fenced and completed before its ioctl returns.
	return 0
}

fn get_caps_handler(_dev &drm.DrmDevice, _handle voidptr, data voidptr) int {
	request := unsafe { &ioctl.DrmVirtgpuGetCaps(data) }
	if request.size == 0 || request.size > response_capacity - sizeof(ControlHeader)
		|| request.addr == 0 || request.pad != 0 {
		return -22
	}
	mut found := false
	mut maximum := u32(0)
	for index := u32(0); index < virtgpu_transport.capset_count; index++ {
		info := virtgpu_transport.capsets[index]
		if info.id == request.cap_set_id && request.cap_set_ver <= info.max_version {
			found = true
			maximum = info.max_size
			break
		}
	}
	if !found {
		return -22
	}
	copy_size := if request.size < maximum { request.size } else { maximum }
	buffer_size := u64(copy_size) + sizeof(ControlHeader)
	buffer := memory.malloc(buffer_size)
	if buffer == unsafe { nil } {
		return -12
	}
	defer {
		memory.free(buffer)
	}
	mut command := GetCapset{
		hdr: header(cmd_get_capset, 0)
		capset_id: request.cap_set_id
		capset_version: request.cap_set_ver
	}
	response_type, used_length := submit(voidptr(&command), sizeof(command), 0, 0, false, buffer, buffer_size, false)
	if response_type != resp_ok_capset || used_length < sizeof(ControlHeader) + copy_size {
		return -5
	}
	if !usercopy.copy_to_user(request.addr, voidptr(u64(buffer) + sizeof(ControlHeader)), copy_size) {
		return -14
	}
	return 0
}

fn unsupported_handler(_dev &drm.DrmDevice, _handle voidptr, _data voidptr) int {
	return -22
}

fn close_handle(_dev &drm.DrmDevice, handle voidptr, object_handle u32) int {
	mut file := get_file(handle) or { return -9 }
	return remove_owned(mut file, object_handle)
}

fn export_object(_dev &drm.DrmDevice, handle voidptr, object_handle u32) ?&gem.GemObject {
	mut file := get_file(handle) or { return none }
	file.lock.acquire()
	object := find_owned(mut file, object_handle) or {
		file.lock.release()
		return none
	}
	retain_object(object)
	file.lock.release()
	return object.gem_object
}

fn release_exported_object(_dev &drm.DrmDevice, gem_object &gem.GemObject) {
	if gem_object == unsafe { nil } || gem_object.handle >= max_resources {
		return
	}
	objects_lock.acquire()
	object := objects_by_handle[gem_object.handle]
	objects_lock.release()
	if object != unsafe { nil } && object.gem_object == gem_object {
		release_object(object)
	}
}

fn import_object(_dev &drm.DrmDevice, handle voidptr, object &gem.GemObject) ?u32 {
	if object == unsafe { nil } || object.handle >= max_resources {
		return none
	}
	mut file := get_file(handle) or { return none }
	if !ensure_context(mut file) {
		return none
	}
	file.lock.acquire()
	if existing := find_owned(mut file, object.handle) {
		file.lock.release()
		return existing.gem_object.handle
	}
	objects_lock.acquire()
	mut virtio_object := objects_by_handle[object.handle]
	if virtio_object == unsafe { nil } {
		objects_lock.release()
		file.lock.release()
		return none
	}
	virtio_object.references++
	objects_lock.release()
	gem.ref_obj(object)
	if !context_resource(cmd_ctx_attach_resource, file.context_id, virtio_object.resource_id) {
		file.lock.release()
		release_object(virtio_object)
		return none
	}
	file.objects << virtio_object
	file.lock.release()
	return object.handle
}

fn mmap_object(_dev &drm.DrmDevice, handle voidptr, page u64, _flags int) voidptr {
	mut file := get_file(handle) or { return unsafe { nil } }
	file.lock.acquire()
	for object in file.mmap_objects {
		if physical := gem.get_object_mmap_page(object.gem_object, page) {
			file.lock.release()
			return physical
		}
	}
	file.lock.release()
	return unsafe { nil }
}

fn close_file(_dev &drm.DrmDevice, handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	key := u64(handle)
	files_lock.acquire()
	mut file := files[key] or {
		files_lock.release()
		return
	}
	files.delete(key)
	files_lock.release()

	file.lock.acquire()
	objects := file.objects.clone()
	mapped_objects := file.mmap_objects.clone()
	context_created := file.context_created
	context_id := file.context_id
	file.objects.clear()
	file.mmap_objects.clear()
	file.lock.release()
	for object in objects {
		if context_created {
			context_resource(cmd_ctx_detach_resource, context_id, object.resource_id)
		}
		release_object(object)
	}
	for object in mapped_objects {
		release_object(object)
	}
	if context_created {
		mut request := ContextCommand{
			hdr: header(cmd_ctx_destroy, context_id)
		}
		nodata(voidptr(&request), sizeof(request), unsafe { nil }, 0, false)
	}
	unsafe { free(voidptr(file)) }
}

fn query_capsets() bool {
	count := mmio_r32(virtgpu_transport.base + reg_config + 12)
	uart.puts(c'virtio-gpu: host reports ')
	uart.put_dec(count)
	uart.puts(c' capsets\n')
	virtgpu_transport.capset_count = if count < max_capsets { count } else { max_capsets }
	for index := u32(0); index < virtgpu_transport.capset_count; index++ {
		mut command := GetCapsetInfo{
			hdr: header(cmd_get_capset_info, 0)
			capset_index: index
		}
		mut response := CapsetInfoResponse{}
		response_type, used_length := submit(voidptr(&command), sizeof(command), 0, 0, false, voidptr(&response), sizeof(response), false)
		if response_type != resp_ok_capset_info || used_length < sizeof(response) {
			return false
		}
		virtgpu_transport.capsets[index] = CapsetInfo{
			id: response.capset_id
			max_version: response.max_version
			max_size: response.max_size
		}
		if response.capset_id < 64 {
			virtgpu_transport.capset_mask |= u64(1) << response.capset_id
		}
		uart.puts(c'virtio-gpu: capset ')
		uart.put_dec(response.capset_id)
		uart.puts(c' version ')
		uart.put_dec(response.max_version)
		uart.puts(c' size ')
		uart.put_dec(response.max_size)
		uart.puts(c'\n')
	}
	return (virtgpu_transport.capset_mask & (u64(1) << 1 | u64(1) << 2)) != 0
}

fn validate_layouts() bool {
	return sizeof(ControlHeader) == 24 && sizeof(ResourceCommand) == 32
		&& sizeof(ResourceAttachBacking) == 32 && sizeof(MemoryEntry) == 16
		&& sizeof(ResourceCreate3d) == 72 && sizeof(ContextCreate) == 96
		&& sizeof(ContextCommand) == 24 && sizeof(Transfer3d) == 72 && sizeof(Submit3d) == 32
		&& sizeof(GetCapsetInfo) == 32 && sizeof(CapsetInfoResponse) == 40
		&& sizeof(GetCapset) == 32 && sizeof(ioctl.DrmVirtgpuMap) == 16
		&& sizeof(ioctl.DrmVirtgpuExecbuffer) == 64 && sizeof(ioctl.DrmVirtgpuGetparam) == 16
		&& sizeof(ioctl.DrmVirtgpuResourceCreate) == 56
		&& sizeof(ioctl.DrmVirtgpuResourceInfo) == 16 && sizeof(ioctl.DrmVirtgpuTransfer) == 44
		&& sizeof(ioctl.DrmVirtgpuWait) == 8 && sizeof(ioctl.DrmVirtgpuGetCaps) == 24
		&& sizeof(ioctl.DrmVirtgpuResourceCreateBlob) == 48
		&& sizeof(ioctl.DrmVirtgpuContextInit) == 16
}

pub fn initialise(hhdm u64) bool {
	if !validate_layouts() {
		uart.puts(c'virtio-gpu: ABI layout validation failed\n')
		return false
	}
	for slot := u64(0); slot < mmio_slot_count; slot++ {
		base := hhdm + mmio_base + slot * mmio_slot_size
		if mmio_r32(base + reg_magic) != virtio_magic
			|| mmio_r32(base + reg_device_id) != virtio_id_gpu {
			continue
		}
		uart.puts(c'virtio-gpu: found MMIO device at slot ')
		uart.put_dec(slot)
		uart.puts(c'\n')
		if mmio_r32(base + reg_version) != 1 {
			uart.puts(c'virtio-gpu: modern MMIO transport is not supported yet\n')
			return false
		}

		mmio_w32(base + reg_status, 0)
		mmio_w32(base + reg_status, status_acknowledge)
		mmio_w32(base + reg_status, status_acknowledge | status_driver)
		offered := mmio_r32(base + reg_host_features)
		if offered & virtio_gpu_f_virgl == 0 {
			uart.puts(c'virtio-gpu: device has no VirGL feature\n')
			mmio_w32(base + reg_status, status_acknowledge | status_driver | status_failed)
			return false
		}
		mmio_w32(base + reg_guest_features, virtio_gpu_f_virgl)
		mmio_w32(base + reg_guest_page_size, 4096)

		mmio_w32(base + reg_queue_sel, 0)
		maximum := mmio_r32(base + reg_queue_num_max)
		if maximum < 2 {
			uart.puts(c'virtio-gpu: control queue is unavailable\n')
			return false
		}
		queue_size := if maximum < wanted_queue_size { u16(maximum) } else { wanted_queue_size }
		mmio_w32(base + reg_queue_num, queue_size)
		mmio_w32(base + reg_queue_align, u32(queue_align))
		avail_offset := u64(queue_size) * 16
		used_offset := align_up(avail_offset + 4 + 2 * u64(queue_size) + 2, queue_align)
		queue_bytes := used_offset + 4 + 8 * u64(queue_size) + 2
		queue_pages := (queue_bytes + page_size - 1) / page_size
		queue_phys := u64(memory.pmm_alloc(queue_pages))
		request_pages := (request_capacity + page_size - 1) / page_size
		response_pages := (response_capacity + page_size - 1) / page_size
		request_phys := u64(memory.pmm_alloc(request_pages))
		response_phys := u64(memory.pmm_alloc(response_pages))
		if queue_phys == 0 || request_phys == 0 || response_phys == 0 {
			uart.puts(c'virtio-gpu: queue allocation failed\n')
			return false
		}
		queue_virt := queue_phys + hhdm
		unsafe {
			C.memset(voidptr(queue_virt), 0, queue_pages * page_size)
			C.memset(voidptr(request_phys + hhdm), 0, request_pages * page_size)
			C.memset(voidptr(response_phys + hhdm), 0, response_pages * page_size)
		}
		virtgpu_transport = Transport{
			base: base
			hhdm: hhdm
			queue_size: queue_size
			desc: queue_virt
			avail: queue_virt + avail_offset
			used: queue_virt + used_offset
			request_phys: request_phys
			request_virt: request_phys + hhdm
			response_phys: response_phys
			response_virt: response_phys + hhdm
			next_fence: 1
			ready: true
		}
		mmio_w32(base + reg_queue_pfn, u32(queue_phys / page_size))
		mmio_w32(base + reg_status, status_acknowledge | status_driver | status_driver_ok)

		if !query_capsets() {
			uart.puts(c'virtio-gpu: no usable VirGL capset\n')
			virtgpu_transport.ready = false
			mmio_w32(base + reg_status, status_acknowledge | status_driver | status_failed)
			return false
		}

		mut driver := &drm.DrmDriver{
			name: 'virtio_gpu'
			desc: 'Vinix VirtIO-GPU VirGL'
			major: 0
			minor: 0
			patchlevel: 1
			features: drm.driver_gem | drm.driver_render | drm.driver_compute
			ioctls: [
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_map
					handler: map_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_execbuffer
					handler: execbuffer_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_getparam
					handler: getparam_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_resource_create
					handler: resource_create_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_resource_info
					handler: resource_info_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_transfer_from_host
					handler: transfer_from_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_transfer_to_host
					handler: transfer_to_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_wait
					handler: wait_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_get_caps
					handler: get_caps_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_resource_create_blob
					handler: unsupported_handler
				},
				drm.DrmIoctl{
					cmd: ioctl.drm_virtgpu_context_init
					handler: unsupported_handler
				},
			]
			file_close: close_file
			gem_close: close_handle
			gem_export: export_object
			gem_export_put: release_exported_object
			gem_import: import_object
			mmap: mmap_object
		}
		drm.register_driver(driver) or {
			virtgpu_transport.ready = false
			uart.puts(c'virtio-gpu: DRM registration failed\n')
			return false
		}
		uart.puts(c'virtio-gpu: VirGL render node ready\n')
		return true
	}
	uart.puts(c'virtio-gpu: no MMIO device found\n')
	return false
}
