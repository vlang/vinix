// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm
import drm.asahi
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.params
import memory
import usercopy
import aarch64.timer

const legacy_ioctl_abi = u32(1)
const modern_ioctl_abi = u32(2)

fn (mut f GpuFile) select_ioctl_abi(abi u32) bool {
	f.lock.acquire()
	defer { f.lock.release() }
	if f.ioctl_abi != 0 && f.ioctl_abi != abi { return false }
	f.ioctl_abi = abi
	return true
}

fn dispatch_abi(handle voidptr, dev &drm.DrmDevice, abi u32) ?&GpuFile {
	f := get_or_create_file(handle, dev) or { return none }
	mut owned := unsafe { f }
	if !owned.select_ioctl_abi(abi) { return none }
	return f
}

// A fresh file accepts either canonical GET_PARAMS header. The first private
// request fixes its dialect; later colliding command numbers never cross it.
pub fn ioctl_abi_handle(_dev &drm.DrmDevice, handle voidptr) u32 {
	f := lookup_file(handle) or { return 0 }
	mut owned := unsafe { f }
	owned.lock.acquire()
	defer { owned.lock.release() }
	return owned.ioctl_abi
}

fn make_modern_global_params(manager &gpu.GpuManager) asahi.ParamsGlobal {
	legacy := make_global_params(manager)
	mut value := asahi.ParamsGlobal{
		features:                       legacy.feat_compat & u64(1) // only SOFT_FAULTS has the same meaning
		gpu_generation:                 legacy.gpu_generation
		gpu_variant:                    legacy.gpu_variant
		gpu_revision:                   legacy.gpu_revision
		chip_id:                        legacy.chip_id
		num_dies:                       legacy.num_dies
		num_clusters_total:             legacy.num_clusters_total
		num_cores_per_cluster:          legacy.num_cores_per_cluster
		max_frequency_khz:              legacy.max_frequency_khz
		vm_start:                       legacy.vm_user_start
		vm_end:                         legacy.vm_user_end
		vm_kernel_min_size:             legacy.vm_kernel_min_size
		max_commands_per_submission:    legacy.max_commands_per_submission
		max_attachments:                legacy.max_attachments
		command_timestamp_frequency_hz: 1_000_000_000
		usc_generation:                 2 // G13 shader ISA; predates numbered HAL generations
	}
	for index, mask in legacy.core_masks { value.core_masks[index] = mask }
	// The packaged G13 path has no device/client admission limits. Do not
	// advertise G17 status, scheduling or extension capabilities here.
	return value
}

pub fn (f &GpuFile) ioctl_modern_get_params(data &asahi.GetParams) int {
	if data.param_group != 0 || data.pad != 0 { return -22 }
	manager := gpu.get_global_manager() or { return -19 }
	if manager.hw_config.gpu_gen != .g13 { return -95 }
	mut owned := unsafe { manager }
	if !owned.can_query_global_params() { return -19 }
	value := make_modern_global_params(manager)
	size := if data.size < sizeof(value) { data.size } else { u64(sizeof(value)) }
	if size != 0 && !usercopy.copy_to_user(data.pointer, unsafe { voidptr(&value) }, size) {
		return -14
	}
	return 0
}

pub fn (f &GpuFile) ioctl_modern_get_time(data &asahi.GetTime) int {
	if data.flags != 0 { return -22 }
	manager := gpu.get_global_manager() or { return -19 }
	frequency := manager.hw_config.base_clock_hz
	if frequency == 0 { return -5 }
	mut request := unsafe { data }
	request.gpu_timestamp = params.timestamp_ns(timer.get_count(), frequency)
	return 0
}

pub fn (mut f GpuFile) ioctl_modern_vm_create(data &asahi.VmCreate) int {
	if data.flags != 0 { return -22 }
	mut old := ioctl.DrmAsahiVmCreate{ kernel_start: data.kernel_start, kernel_end: data.kernel_end, vm_id: data.vm_id }
	code := f.ioctl_vm_create(unsafe { &old })
	mut request := unsafe { data }
	request.vm_id = old.vm_id
	return code
}

pub fn (mut f GpuFile) ioctl_modern_vm_destroy(data &asahi.VmDestroy) int {
	old := ioctl.DrmAsahiVmDestroy{ vm_id: data.vm_id }
	return f.ioctl_vm_destroy(unsafe { &old })
}

pub fn (mut f GpuFile) ioctl_modern_gem_create(data &asahi.GemCreate) int {
	// The reference ignores GEM_CREATE.pad, unlike some other request pads.
	mut old := ioctl.DrmAsahiGemCreate{ size: data.size, flags: data.flags, vm_id: data.vm_id, handle: data.handle }
	code := f.ioctl_gem_create(unsafe { &old })
	mut request := unsafe { data }
	request.handle = old.handle
	return code
}

pub fn (mut f GpuFile) ioctl_modern_gem_mmap_offset(data &asahi.GemMmapOffset) int {
	mut old := ioctl.DrmAsahiGemMmapOffset{ handle: data.handle, flags: data.flags, offset: data.offset }
	code := f.ioctl_gem_mmap_offset(unsafe { &old })
	mut request := unsafe { data }
	request.offset = old.offset
	return code
}

pub fn (mut f GpuFile) ioctl_modern_gem_bind_object(data &asahi.GemBindObject) int {
	mut old := ioctl.DrmAsahiGemBindObject{
		op:            data.op
		flags:         data.flags
		handle:        data.handle
		vm_id:         data.vm_id
		offset:        data.offset
		range:         data.range
		object_handle: data.object_handle
		pad:           data.pad
	}
	code := f.ioctl_gem_bind_object(unsafe { &old })
	mut request := unsafe { data }
	request.object_handle = old.object_handle
	return code
}

pub fn (mut f GpuFile) ioctl_modern_queue_create(data &asahi.QueueCreate) int {
	if data.render_scs_layout != [u64(0), 0]! { return -22 }
	mut old := ioctl.DrmAsahiQueueCreate{
		flags:      data.flags
		vm_id:      data.vm_id
		priority:   data.priority
		queue_id:   data.queue_id
		queue_caps: ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_compute
	}
	code := f.create_queue(unsafe { &old }, data.usc_exec_base)
	mut request := unsafe { data }
	request.queue_id = old.queue_id
	return code
}

pub fn (mut f GpuFile) ioctl_modern_queue_destroy(data &asahi.QueueDestroy) int {
	old := ioctl.DrmAsahiQueueDestroy{ queue_id: data.queue_id }
	return f.ioctl_queue_destroy(unsafe { &old })
}

// Asahi snapshots the entire strided batch before any mapping mutation, then
// applies operations sequentially. A malformed later operation leaves its
// successful prefix installed; a userspace-copy fault installs nothing.
pub fn (mut f GpuFile) ioctl_modern_vm_bind(data &asahi.VmBind) int {
	if data.stride == 0 || data.pad != 0 { return -22 }
	if data.num_binds == 0 { return 0 }
	bytes := u64(data.stride) * u64(data.num_binds)
	if data.userptr == 0 || bytes - 1 > ~data.userptr { return -14 }
	storage := memory.malloc_packed_fallible(bytes) @[freed]
	if storage == unsafe { nil } { return -12 }
	defer { memory.free(storage) }
	if !usercopy.copy_from_user(storage, data.userptr, bytes) { return -14 }
	for index := u32(0); index < data.num_binds; index++ {
		mut op := asahi.GemBindOp{}
		size := if data.stride < sizeof(op) { u64(data.stride) } else { u64(sizeof(op)) }
		unsafe { C.memcpy(&op, voidptr(u64(storage) + u64(index) * data.stride), size) }
		// read_up_to zero extends short records and ignores long tails.
		unbind := op.flags & asahi.bind_unbind != 0
		if unbind && (op.flags != asahi.bind_unbind || op.handle != 0 || op.offset != 0) {
			return -22
		}
		if !unbind && op.flags & ~(asahi.bind_read | asahi.bind_write | asahi.bind_single_page) != 0 {
			return -22
		}
		old := ioctl.DrmAsahiGemBind{
			vm_id:  data.vm_id
			op:     if unbind { ioctl.asahi_bind_op_unbind } else { ioctl.asahi_bind_op_bind }
			flags:  if unbind {
				u32(0)
			} else {
				((op.flags & (asahi.bind_read | asahi.bind_write)) >> 1) | (op.flags & asahi.bind_single_page)
			}
			handle: op.handle
			offset: op.offset
			range:  op.range
			addr:   op.addr
		}
		code := f.ioctl_gem_bind(unsafe { &old })
		if code != 0 { return code }
	}
	return 0
}

fn modern_get_params_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_get_params(unsafe { &asahi.GetParams(data) })
}

fn modern_get_time_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_get_time(unsafe { &asahi.GetTime(data) })
}

fn modern_vm_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_vm_create(unsafe { &asahi.VmCreate(data) })
}

fn modern_vm_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_vm_destroy(unsafe { &asahi.VmDestroy(data) })
}

fn modern_gem_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_gem_create(unsafe { &asahi.GemCreate(data) })
}

fn modern_gem_mmap_offset_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_gem_mmap_offset(unsafe { &asahi.GemMmapOffset(data) })
}

fn modern_gem_bind_object_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_gem_bind_object(unsafe { &asahi.GemBindObject(data) })
}

fn modern_vm_bind_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_vm_bind(unsafe { &asahi.VmBind(data) })
}

fn modern_queue_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_queue_create(unsafe { &asahi.QueueCreate(data) })
}

fn modern_queue_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_queue_destroy(unsafe { &asahi.QueueDestroy(data) })
}

fn modern_submit_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut f := dispatch_abi(handle, dev, modern_ioctl_abi) or { return -19 }
	return f.ioctl_modern_submit(unsafe { &asahi.Submit(data) })
}
