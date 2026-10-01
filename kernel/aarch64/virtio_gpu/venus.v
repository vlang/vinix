// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module virtio_gpu

import drm
import drm.gem
import drm.ioctl
import drm.syncobj
import klock
import memory
import usercopy

const cmd_resource_create_blob = u32(0x010c)
const cmd_resource_map_blob = u32(0x0208)
const cmd_resource_unmap_blob = u32(0x0209)
const resp_ok_map_info = u32(0x1106)
const host_window_pages = 262144 // at most 4 GiB on ARM64's 16 KiB granule

@[packed]
struct ResourceCreateBlob {
mut:
	hdr         ControlHeader
	resource_id u32
	blob_mem    u32
	blob_flags  u32
	nr_entries  u32
	blob_id     u64
	size        u64
}

@[packed]
struct ResourceMapBlob {
mut:
	hdr         ControlHeader
	resource_id u32
	padding     u32
	offset      u64
}

@[packed]
struct ResourceMapResponse {
mut:
	hdr      ControlHeader
	map_info u32
	padding  u32
}

struct ContextParam {
	param u64
	value u64
}

__global (
	host_window_lock klock.Lock
	host_window_used [host_window_pages]bool
	completed_fence  = syncobj.DmaFence{ signaled: true }
)

fn reserve_host_span(size u64) ?u64 {
	pages := size / page_size
	limit := virtgpu_transport.hostmem_size / page_size
	if pages == 0 || limit > host_window_pages || pages > limit { return none }
	host_window_lock.acquire()
	defer { host_window_lock.release() }
	mut run := u64(0)
	for i := u64(0); i < limit; i++ {
		if host_window_used[i] { run = 0 } else { run++ }
		if run == pages {
			first := i + 1 - pages
			for j := first; j <= i; j++ { host_window_used[j] = true }
			return first * page_size
		}
	}
	return none
}

fn release_host_span(offset u64, size u64) {
	host_window_lock.acquire()
	for i := offset / page_size; i < (offset + size) / page_size; i++ {
		host_window_used[i] = false
	}
	host_window_lock.release()
}

fn context_init_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	request := unsafe { &ioctl.DrmVirtgpuContextInit(data) }
	if virtgpu_transport.features & 16 == 0 || request.pad != 0 || request.num_params == 0 || request.num_params > 3 {
		return -22
	}
	mut capset := u32(0)
	mut rings := u32(1)
	mut seen := u32(0)
	for i := u32(0); i < request.num_params; i++ {
		mut param := ContextParam{}
		if !usercopy.copy_from_user(voidptr(&param), request.ctx_set_params + u64(i) * sizeof(ContextParam), sizeof(ContextParam)) {
			return -14
		}
		if param.param < 1 || param.param > 3 || seen & (u32(1) << u32(param.param)) != 0 {
			return -22
		}
		seen |= u32(1) << u32(param.param)
		match param.param {
			1 {
				if param.value >= 64 || virtgpu_transport.capset_mask & (u64(1) << param.value) == 0 {
					return -22
				}
				capset = u32(param.value)
			}
			2 {
				if param.value == 0 || param.value > 64 { return -22 }
				rings = u32(param.value)
			}
			3 {
				if param.value != 0 { return -22 }
			}
			else { return -22 }
		}
	}
	mut file := get_file(handle) or { return -9 }
	file.lock.acquire()
	if file.context_created {
		file.lock.release()
		return -16
	}
	file.capset_id = capset
	file.num_rings = rings
	file.lock.release()
	return if ensure_context(mut file) { 0 } else { -5 }
}

fn resource_create_blob_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	mut request := unsafe { &ioctl.DrmVirtgpuResourceCreateBlob(data) }
	// Venus uses HOST3D blobs, including blob id 0 for its shared rings.
	if virtgpu_transport.features & 8 == 0 || request.blob_mem != 2 || request.blob_flags & ~u32(3) != 0
		|| request.size == 0 || request.size > u64(2) * 1024 * 1024 * 1024 || request.pad != 0 || request.cmd_size != 0 || request.cmd != 0 {
		return -22
	}
	mut file := get_file(handle) or { return -9 }
	if !ensure_context(mut file) { return -5 }
	mut object := gem.create_external(request.size) or { return -12 }
	resource_id := allocate_resource_id()
	mut offset := u64(0)
	mappable := request.blob_flags & 1 != 0
	if mappable {
		offset = reserve_host_span(object.size) or {
			gem.unref(object)
			return -12
		}
	}
	mut create := ResourceCreateBlob{
		hdr:         header(cmd_resource_create_blob, file.context_id)
		resource_id: resource_id
		blob_mem:    request.blob_mem
		blob_flags:  request.blob_flags
		blob_id:     request.blob_id
		size:        object.size
	}
	if !nodata(voidptr(&create), sizeof(create), unsafe { nil }, 0, false) {
		if mappable { release_host_span(offset, object.size) }
		gem.unref(object)
		return -5
	}
	mut wrapper := &VirtioObject{
		gem_object:    object
		resource_id:   resource_id
		references:    1
		blob_mem:      request.blob_mem
		host_reserved: mappable
		host_offset:   offset
	} @[freed]
	if mappable {
		mut mapping := ResourceMapBlob{
			hdr:         header(cmd_resource_map_blob, 0)
			resource_id: resource_id
			offset:      offset
		}
		mut response := ResourceMapResponse{}
		response_type, used := submit(voidptr(&mapping), sizeof(mapping), 0, 0, false, voidptr(&response), sizeof(response), false)
		if response_type != resp_ok_map_info || used < sizeof(response) {
			release_object(wrapper)
			return -5
		}
		wrapper.host_mapped = true
		cache := response.map_info & 0xf
		if cache > 3 {
			release_object(wrapper)
			return -22
		}
		// NONE/CACHED use Normal WB. UNCACHED/WC use Normal NC on ARM64,
		// identically in the kernel copy alias and every user mapping.
		object.pte_extra = if cache >= 2 { memory.pte_uncached } else { 0 }
		object.phys_addr = virtgpu_transport.hostmem_base + offset
		object.virt_addr = if cache >= 2 {
			memory.map_uncached(object.phys_addr, object.size)
		} else {
			memory.map_shared_memory(object.phys_addr, object.size)
		}
	}
	if !context_resource(cmd_ctx_attach_resource, file.context_id, resource_id) {
		release_object(wrapper)
		return -5
	}
	objects_lock.acquire()
	objects_by_handle[object.handle] = wrapper
	objects_lock.release()
	request.bo_handle = object.handle
	request.res_handle = resource_id
	file.lock.acquire()
	file.objects << wrapper
	file.owned[object.handle] = wrapper
	file.lock.release()
	return 0
}
