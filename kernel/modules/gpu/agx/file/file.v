@[has_globals]
module file

// Per-open DRM state for the Apple GPU. The public structures consumed here
// are the Mesa 25.0.5 unstable Asahi UAPI in drm.ioctl. G17 command submission
// stays fail-closed until its HAL300 work-command encoder is complete.

import drm
import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.workqueue
import gpu.agx.gpu
import klock
import katomic
import proc
import sched
import usercopy
import aarch64.timer

const max_submission_commands = u32(64)
const max_submission_syncs = u32(64)
const max_command_attachments = u32(16)
const max_render_dimension = u32(16384)
const max_render_layers = u32(2048)

struct GpuMapping {
mut:
	vm_id  u32
	handle u32
	addr   u64
	size   u64
	obj    &gem.GemObject = unsafe { nil }
}

struct G17QueueOwnership {
	queue_id  u32
	resources &gpu.G17QueueResources = unsafe { nil }
}

struct G13QueueOwnership {
	queue_id  u32
	resources &gpu.G13QueueResources = unsafe { nil }
}

struct TimestampObject {
	id   u32
	va   u64
	size u64
	obj  &gem.GemObject = unsafe { nil }
}

struct StagedSyncArray {
mut:
	count           u32
	objects         [64]&syncobj.SyncObj
	fences          [64]&syncobj.DmaFence
	timeline        [64]bool
	timeline_values [64]u64
}

@[heap]
struct G13SubmitCompletion {
mut:
	file          &GpuFile = unsafe { nil }
	vm_id         u32
	fence         &syncobj.DmaFence = unsafe { nil }
	result        &gem.GemObject = unsafe { nil }
	result_offset u64
}

pub struct GpuFile {
pub mut:
	dev               &drm.DrmDevice = unsafe { nil }
	vms               []&mmu.UatContext
	queues            []&workqueue.WorkQueue
	mappings          []GpuMapping
	objects           []&gem.GemObject
	mmap_objects      []&gem.GemObject
	g17_queues        []G17QueueOwnership
	g13_queues        []G13QueueOwnership
	timestamp_objects []TimestampObject
	next_queue_id     u32
	next_timestamp_id u32
	owner_process_id  u32
	owner_key         u64
	inflight_by_vm    [mmu.uat_num_contexts]u64
	lock              klock.Lock
}

__global (
	file_map_lock klock.Lock
	file_map      = map[u64]&GpuFile{}
)

fn get_or_create_file(handle voidptr, dev &drm.DrmDevice) ?&GpuFile {
	if handle == unsafe { nil } {
		return none
	}
	key := u64(handle)

	file_map_lock.acquire()
	if key in file_map {
		f := file_map[key] or {
			file_map_lock.release()
			return none
		}
		file_map_lock.release()
		return f
	}
	file_map_lock.release()

	f := new_gpu_file(dev, key) or { return none }
	file_map_lock.acquire()
	file_map[key] = f
	file_map_lock.release()
	return f
}

pub fn release_handle(_dev &drm.DrmDevice, handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	key := u64(handle)
	file_map_lock.acquire()
	f := file_map[key] or {
		file_map_lock.release()
		return
	}
	file_map.delete(key)
	file_map_lock.release()

	mut ff := unsafe { f }
	ff.close()
}

pub fn new_gpu_file(dev &drm.DrmDevice, owner_key u64) ?&GpuFile {
	if dev == unsafe { nil } || uat_mgr == unsafe { nil } || owner_key == 0 {
		return none
	}
	current := proc.current_thread()
	if current == unsafe { nil } || current.process == unsafe { nil }
		|| current.process.pid <= 0 {
		return none
	}
	return &GpuFile{
		dev: unsafe { dev }
		next_queue_id: 1
		next_timestamp_id: 1
		owner_process_id: u32(current.process.pid)
		owner_key: owner_key
	}
}

pub fn (mut f GpuFile) close() {
	f.lock.acquire()
	for vm_id := u32(1); vm_id < mmu.uat_num_contexts; vm_id++ {
		if katomic.load(&f.inflight_by_vm[vm_id]) != 0 {
			// No G13 kill protocol is implemented yet. Retaining the complete
			// file graph is safer than tearing live UAT mappings out from under
			// firmware. A normal Mesa close waits its output fence first.
			C.printf(c'agx: retaining closing DRM file with live VM %u jobs\n', vm_id)
			f.lock.release()
			return
		}
	}
	for mut q in f.queues {
		q.destroy()
	}
	f.queues.clear()
	manager := gpu.get_global_manager() or { unsafe { nil } }
	if manager != unsafe { nil } {
		mut gpu_manager := unsafe { manager }
		for ownership in f.g17_queues {
			gpu_manager.release_g17_queue_resources(ownership.resources)
		}
	}
	f.g17_queues.clear()
	if manager != unsafe { nil } {
		mut gpu_manager := unsafe { manager }
		for ownership in f.g13_queues {
			gpu_manager.release_g13_queue_resources(ownership.resources)
		}
	}
	f.g13_queues.clear()
	if manager != unsafe { nil } {
		mut gpu_manager := unsafe { manager }
		for object in f.timestamp_objects {
			gpu_manager.unmap_g13_timestamp_buffer(object.va, object.size)
			gem.unref(object.obj)
		}
	} else {
		for object in f.timestamp_objects {
			gem.unref(object.obj)
		}
	}
	f.timestamp_objects.clear()

	mgr := uat_mgr
	if mgr != unsafe { nil } {
		mut m := unsafe { mgr }
		for vm in f.vms {
			m.destroy_context(vm)
		}
	}
	f.vms.clear()
	for mapping in f.mappings {
		gem.unref(mapping.obj)
	}
	f.mappings.clear()
	for obj in f.mmap_objects {
		gem.unref(obj)
	}
	f.mmap_objects.clear()
	for obj in f.objects {
		gem.unref(obj)
	}
	f.objects.clear()
	f.lock.release()
}

fn (mut f GpuFile) get_object_ref(handle u32) ?&gem.GemObject {
	f.lock.acquire()
	defer { f.lock.release() }
	for obj in f.objects {
		if obj.handle == handle {
			gem.ref_obj(obj)
			return obj
		}
	}
	return none
}

fn (mut f GpuFile) authorize_mmap(handle u32) ?u64 {
	f.lock.acquire()
	defer { f.lock.release() }
	mut found := &gem.GemObject(unsafe { nil })
	for obj in f.objects {
		if obj.handle == handle {
			found = obj
			break
		}
	}
	if voidptr(found) == unsafe { nil } {
		return none
	}
	for obj in f.mmap_objects {
		if voidptr(obj) == voidptr(found) {
			return gem.create_mmap_offset(found)
		}
	}
	gem.ref_obj(found)
	f.mmap_objects << found
	return gem.create_mmap_offset(found)
}

fn (mut f GpuFile) mmap_page(page u64) voidptr {
	f.lock.acquire()
	defer { f.lock.release() }
	for obj in f.mmap_objects {
		if phys := gem.get_object_mmap_page(obj, page) {
			return phys
		}
	}
	return unsafe { nil }
}

fn (mut f GpuFile) close_object_handle(handle u32) int {
	f.lock.acquire()
	for i, obj in f.objects {
		if obj.handle == handle {
			f.objects.delete(i)
			f.lock.release()
			gem.unref(obj)
			return 0
		}
	}
	f.lock.release()
	return -2 // ENOENT
}

// Reserve a nonzero per-open queue ID. Failed queue construction may leave a
// hole, so wraparound also checks live IDs instead of assuming monotonic IDs
// can never be exhausted.
fn (mut f GpuFile) allocate_queue_id_locked() ?u32 {
	mut candidate := f.next_queue_id
	if candidate == 0 {
		candidate = 1
	}
	start := candidate
	for {
		mut used := false
		for queue in f.queues {
			if queue.id == candidate {
				used = true
				break
			}
		}
		if !used {
			f.next_queue_id = if candidate == ~u32(0) { u32(1) } else { candidate + 1 }
			return candidate
		}
		candidate = if candidate == ~u32(0) { u32(1) } else { candidate + 1 }
		if candidate == start {
			return none
		}
	}
	return none
}

fn (mut f GpuFile) allocate_timestamp_id_locked() ?u32 {
	mut candidate := f.next_timestamp_id
	if candidate == 0 {
		candidate = 1
	}
	start := candidate
	for {
		mut used := false
		for object in f.timestamp_objects {
			if object.id == candidate {
				used = true
				break
			}
		}
		if !used {
			f.next_timestamp_id = if candidate == ~u32(0) { u32(1) } else { candidate + 1 }
			return candidate
		}
		candidate = if candidate == ~u32(0) { u32(1) } else { candidate + 1 }
		if candidate == start {
			return none
		}
	}
	return none
}

fn (f &GpuFile) find_vm(vm_id u32) ?&mmu.UatContext {
	for vm in f.vms {
		if vm.id == vm_id {
			return unsafe { vm }
		}
	}
	return none
}

fn ranges_overlap(first_addr u64, first_size u64, second_addr u64, second_size u64) bool {
	return first_addr < second_addr + second_size && second_addr < first_addr + first_size
}

// G13 firmware may retain both UAT translations and noncoherent cache lines.
// Break large mappings into the 16-bit page counts accepted by FwCtlMsg.
fn flush_g13_mapping(ctx &mmu.UatContext, addr u64, size u64) bool {
	manager := gpu.get_global_manager() or { return false }
	if manager.hw_config.gpu_gen != .g13 {
		return true
	}
	mut gpu_manager := unsafe { manager }
	max_flush_size := u64(0xffff) * pgtable.uat_pgsz
	mut current := addr
	mut remaining := size
	for remaining != 0 {
		chunk := if remaining > max_flush_size { max_flush_size } else { remaining }
		if !gpu_manager.flush_g13_uat_range(ctx.id, current, chunk) {
			return false
		}
		current += chunk
		remaining -= chunk
	}
	return true
}

fn asahi_variant(config &gpu.GpuManager) u32 {
	return match config.hw_config.gpu_variant {
		.s { u32(`S`) }
		.c { u32(`C`) }
		.d { u32(`D`) }
		.g { u32(`G`) }
	}
}

fn asahi_revision(config &gpu.GpuManager) u32 {
	return match config.hw_config.gpu_rev {
		.a0 { u32(0x00) }
		.a1 { u32(0x01) }
		.b0 { u32(0x10) }
		.b1 { u32(0x11) }
		.c0 { u32(0x20) }
		.c1 { u32(0x21) }
		.unknown { u32(0xffffffff) }
	}
}

fn make_global_params(manager &gpu.GpuManager) ioctl.DrmAsahiParamsGlobal {
	cfg := &manager.hw_config
	mut params := ioctl.DrmAsahiParamsGlobal{
		unstable_uabi_version: ioctl.drm_asahi_unstable_uabi_version
		feat_compat: u64(cfg.gpu_feat_compat) | ioctl.asahi_feat_gettime
		feat_incompat: u64(cfg.gpu_feat_incompat)
		gpu_generation: u32(cfg.gpu_gen)
		gpu_variant: asahi_variant(manager)
		gpu_revision: asahi_revision(manager)
		chip_id: cfg.chip_id
		num_dies: cfg.max_dies
		num_clusters_total: cfg.num_clusters
		num_cores_per_cluster: cfg.num_cores_per_cluster
		num_frags_per_cluster: if cfg.num_clusters == 0 {
			u32(0)
		} else {
			cfg.num_frags / cfg.num_clusters
		}
		num_gps_per_cluster: if cfg.num_clusters == 0 {
			u32(0)
		} else {
			cfg.num_gps / cfg.num_clusters
		}
		num_cores_total_active: cfg.gpu_core_count
		vm_page_size: u32(pgtable.uat_pgsz)
		vm_user_start: mmu.uat_user_va_start
		vm_user_end: mmu.uat_unknown_page
		vm_kernel_min_size: u64(0x20000000)
		max_syncs_per_submission: max_submission_syncs
		max_commands_per_submission: if cfg.gpu_gen == .g13 {
			u32(1)
		} else {
			max_submission_commands
		}
		max_commands_in_flight: if cfg.gpu_gen == .g13 {
			u32(1)
		} else {
			workqueue.max_job_slots
		}
		max_attachments: max_command_attachments
		timer_frequency_hz: u32(cfg.base_clock_hz)
		result_render_size: u32(sizeof(ioctl.DrmAsahiResultRender))
		result_compute_size: u32(sizeof(ioctl.DrmAsahiResultCompute))
		user_timestamp_frequency_hz: cfg.base_clock_hz
	}
	for i := u32(0); i < cfg.num_clusters && i < ioctl.drm_asahi_max_clusters; i++ {
		if i < cfg.core_mask_list.len {
			params.core_masks[i] = u64(cfg.core_mask_list[i])
		}
	}
	if cfg.perf_state_count > 0 {
		params.min_frequency_khz = cfg.perf_state_frequencies[cfg.perf_state_base] / 1000
		params.max_frequency_khz = cfg.perf_state_frequencies[cfg.perf_state_count - 1] / 1000
		params.max_power_mw = cfg.max_power_mw
	}
	params.firmware_version = cfg.firmware_version
	return params
}

pub fn (f &GpuFile) ioctl_get_params(data &ioctl.DrmAsahiGetParams) int {
	mut request := unsafe { data }
	if request.extensions != 0 || request.param_group != 0 || request.pad != 0 {
		return -22 // EINVAL
	}
	manager := gpu.get_global_manager() or { return -19 }
	params := make_global_params(manager)
	supported_size := u64(sizeof(ioctl.DrmAsahiParamsGlobal))
	copy_size := if request.size < supported_size { request.size } else { supported_size }
	if request.pointer == 0 || copy_size == 0 {
		request.size = supported_size
		return -14 // EFAULT
	}
	if !usercopy.copy_to_user(request.pointer, voidptr(&params), copy_size) {
		request.size = supported_size
		return -14
	}
	request.size = supported_size
	return 0
}

pub fn (mut f GpuFile) ioctl_vm_create(data &ioctl.DrmAsahiVmCreate) int {
	mut request := unsafe { data }
	mgr := uat_mgr
	if mgr == unsafe { nil } {
		return -19
	}
	address_limit := u64(1) << mgr.ias
	if request.extensions != 0 || request.pad != 0 || request.kernel_start >= request.kernel_end
		|| request.kernel_start < mmu.uat_user_va_start
		|| request.kernel_start & pgtable.uat_pg_mask != 0
		|| request.kernel_end & pgtable.uat_pg_mask != 0
		|| request.kernel_end > mmu.uat_unknown_page
		|| request.kernel_end - request.kernel_start < 0x20000000
		|| request.kernel_end > address_limit {
		return -22
	}
	mut m := unsafe { mgr }
	ctx := m.create_context(request.kernel_start, request.kernel_end) or { return -12 }
	m.bind_context(ctx)
	f.lock.acquire()
	f.vms << ctx
	f.lock.release()
	request.vm_id = ctx.id
	return 0
}

pub fn (mut f GpuFile) ioctl_vm_destroy(data &ioctl.DrmAsahiVmDestroy) int {
	request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 {
		return -22
	}
	f.lock.acquire()
	defer { f.lock.release() }
	for q in f.queues {
		if q.vm_id == request.vm_id {
			return -16 // EBUSY
		}
	}
	for mapping in f.mappings {
		if mapping.vm_id == request.vm_id {
			return -16
		}
	}
	for i, vm in f.vms {
		if vm.id == request.vm_id {
			mut manager := unsafe { uat_mgr }
			manager.destroy_context(vm)
			f.vms.delete(i)
			return 0
		}
	}
	return -22
}

pub fn (mut f GpuFile) ioctl_gem_create(data &ioctl.DrmAsahiGemCreate) int {
	mut request := unsafe { data }
	valid_flags := ioctl.asahi_gem_writeback | ioctl.asahi_gem_vm_private
	if request.extensions != 0 || request.pad != 0 || request.flags & ~valid_flags != 0 {
		return -22
	}
	if request.flags & ioctl.asahi_gem_vm_private != 0 {
		f.find_vm(request.vm_id) or { return -22 }
	} else if request.vm_id != 0 {
		return -22
	}
	obj := gem.create_aligned(request.size, pgtable.uat_pgsz) or { return -12 }
	f.lock.acquire()
	f.objects << obj
	f.lock.release()
	request.handle = obj.handle
	return 0
}

pub fn (mut f GpuFile) ioctl_gem_mmap_offset(data &ioctl.DrmAsahiGemMmapOffset) int {
	mut request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 {
		return -22
	}
	request.offset = f.authorize_mmap(request.handle) or { return -2 }
	return 0
}

pub fn (mut f GpuFile) ioctl_gem_bind(data &ioctl.DrmAsahiGemBind) int {
	request := unsafe { data }
	if request.extensions != 0 || request.flags & ~(ioctl.asahi_bind_read | ioctl.asahi_bind_write) != 0
		|| request.addr & pgtable.uat_pg_mask != 0 || request.range == 0
		|| request.range & pgtable.uat_pg_mask != 0
		|| request.range > u64(-1) - request.addr
		|| request.addr < mmu.uat_user_va_start
		|| request.addr >= mmu.uat_unknown_page
		|| request.range > mmu.uat_unknown_page - request.addr {
		return -22
	}
	ctx := f.find_vm(request.vm_id) or { return -22 }
	if ctx.pgtable == unsafe { nil } {
		return -22
	}
	mut pt := unsafe { ctx.pgtable }
	end := request.addr + request.range
	if request.addr < ctx.kernel_end && end > ctx.kernel_start {
		return -22
	}

	match request.op {
		ioctl.asahi_bind_op_bind {
			if request.flags == 0 {
				return -22
			}
			obj := f.get_object_ref(request.handle) or { return -2 }
			if request.offset & pgtable.uat_pg_mask != 0 || request.offset > obj.size
				|| request.range > obj.size - request.offset {
				gem.unref(obj)
				return -22
			}
			protection := if request.flags & ioctl.asahi_bind_write != 0 {
				pgtable.gpu_prot_gpu_shared_rw
			} else {
				pgtable.gpu_prot_gpu_shared_ro
			}
			f.lock.acquire()
			for mapping in f.mappings {
				if mapping.vm_id == request.vm_id
					&& ranges_overlap(mapping.addr, mapping.size, request.addr, request.range) {
					f.lock.release()
					gem.unref(obj)
					return -16 // EBUSY
				}
			}
			if !pt.map(request.addr, obj.phys_addr + request.offset, request.range, protection) {
				f.lock.release()
				gem.unref(obj)
				return -12
			}
			if !flush_g13_mapping(ctx, request.addr, request.range) {
				pt.unmap(request.addr, request.range)
				f.lock.release()
				gem.unref(obj)
				return -5 // EIO
			}
			f.mappings << GpuMapping{
				vm_id: request.vm_id
				handle: request.handle
				addr: request.addr
				size: request.range
				obj: obj
			}
			f.lock.release()
			return 0
		}
		ioctl.asahi_bind_op_unbind {
			if request.handle != 0 || request.flags != 0 || request.offset != 0 {
				return -22
			}
			f.lock.acquire()
			if request.vm_id >= mmu.uat_num_contexts
				|| katomic.load(&f.inflight_by_vm[request.vm_id]) != 0 {
				f.lock.release()
				return -16 // EBUSY: firmware may still dereference this mapping
			}
			for i, mapping in f.mappings {
				if mapping.vm_id == request.vm_id && mapping.addr == request.addr
					&& mapping.size == request.range {
					pt.unmap(request.addr, request.range)
					flush_ok := flush_g13_mapping(ctx, request.addr, request.range)
					gem.unref(mapping.obj)
					f.mappings.delete(i)
					f.lock.release()
					return if flush_ok { 0 } else { -5 }
				}
			}
			f.lock.release()
			return -22
		}
		ioctl.asahi_bind_op_unbind_all {
			if request.handle == 0 || request.flags != 0 || request.offset != 0 || request.addr != 0 {
				return -22
			}
			obj := f.get_object_ref(request.handle) or { return -2 }
			f.lock.acquire()
			if request.vm_id >= mmu.uat_num_contexts
				|| katomic.load(&f.inflight_by_vm[request.vm_id]) != 0 {
				f.lock.release()
				gem.unref(obj)
				return -16
			}
			mut flush_ok := true
			for i := f.mappings.len - 1; i >= 0; i-- {
				mapping := f.mappings[i]
				if mapping.vm_id == request.vm_id && voidptr(mapping.obj) == voidptr(obj) {
					pt.unmap(mapping.addr, mapping.size)
					if !flush_g13_mapping(ctx, mapping.addr, mapping.size) {
						flush_ok = false
					}
					gem.unref(mapping.obj)
					f.mappings.delete(i)
				}
			}
			f.lock.release()
			gem.unref(obj)
			return if flush_ok { 0 } else { -5 }
		}
		else {
			return -22
		}
	}
}

pub fn (f &GpuFile) ioctl_get_time(data &ioctl.DrmAsahiGetTime) int {
	mut request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 {
		return -22
	}
	request.gpu_timestamp = timer.get_ns()
	return 0
}

pub fn (mut f GpuFile) ioctl_gem_bind_object(data &ioctl.DrmAsahiGemBindObject) int {
	mut request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 || request.vm_id != 0 {
		return -22
	}
	match request.op {
		ioctl.asahi_bind_object_op_bind {
			if request.flags != ioctl.asahi_bind_object_usage_timestamps
				|| request.object_handle != 0 || request.range == 0
				|| request.offset & pgtable.uat_pg_mask != 0
				|| request.range & pgtable.uat_pg_mask != 0 {
				return -22
			}
			obj := f.get_object_ref(request.handle) or { return -2 }
			if request.offset > obj.size || request.range > obj.size - request.offset
				|| obj.phys_addr > u64(-1) - request.offset {
				gem.unref(obj)
				return -22
			}
			manager := gpu.get_global_manager() or {
				gem.unref(obj)
				return -19
			}
			mut gpu_manager := unsafe { manager }
			va := gpu_manager.map_g13_timestamp_buffer(obj.phys_addr + request.offset, request.range) or {
				gem.unref(obj)
				return -12
			}
			f.lock.acquire()
			id := f.allocate_timestamp_id_locked() or {
				f.lock.release()
				gpu_manager.unmap_g13_timestamp_buffer(va, request.range)
				gem.unref(obj)
				return -24
			}
			f.timestamp_objects << TimestampObject{
				id: id
				va: va
				size: request.range
				obj: obj
			}
			f.lock.release()
			request.object_handle = id
			return 0
		}
		ioctl.asahi_bind_object_op_unbind {
			if request.flags != 0 || request.handle != 0 || request.offset != 0
				|| request.range != 0 || request.object_handle == 0 {
				return -22
			}
			manager := gpu.get_global_manager() or { return -19 }
			f.lock.acquire()
			mut found := TimestampObject{}
			mut present := false
			for index, object in f.timestamp_objects {
				if object.id == request.object_handle {
					found = object
					f.timestamp_objects.delete(index)
					present = true
					break
				}
			}
			f.lock.release()
			if !present {
				return -2
			}
			mut gpu_manager := unsafe { manager }
			gpu_manager.unmap_g13_timestamp_buffer(found.va, found.size)
			gem.unref(found.obj)
			return 0
		}
		else {
			return -22
		}
	}
}

pub fn (mut f GpuFile) ioctl_queue_create(data &ioctl.DrmAsahiQueueCreate) int {
	mut request := unsafe { data }
	known_caps := ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_blit | ioctl.asahi_queue_cap_compute
	if request.extensions != 0 || request.flags != 0 || request.pad != 0 || request.priority > 3
		|| request.queue_caps == 0 || request.queue_caps & ~known_caps != 0 {
		return -22
	}
	vm := f.find_vm(request.vm_id) or { return -22 }
	f.lock.acquire()
	id := f.allocate_queue_id_locked() or {
		f.lock.release()
		return -24 // EMFILE
	}
	f.lock.release()
	wq := workqueue.new_workqueue(id, request.vm_id, request.priority, request.queue_caps) or {
		return -12
	}
	mut g17_resources := &gpu.G17QueueResources(unsafe { nil })
	mut g13_resources := &gpu.G13QueueResources(unsafe { nil })
	manager := gpu.get_global_manager() or {
		mut queue := unsafe { wq }
		queue.destroy()
		return -19
	}
	if manager.hw_config.gpu_gen == .g17 {
		mut channel_mask := u32(0)
		if request.queue_caps & ioctl.asahi_queue_cap_render != 0 {
			channel_mask |= gpu.g17_queue_channel_ta
		}
		if request.queue_caps & (ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_blit) != 0 {
			channel_mask |= gpu.g17_queue_channel_3d
		}
		if request.queue_caps & ioctl.asahi_queue_cap_compute != 0 {
			channel_mask |= gpu.g17_queue_channel_cl
		}
		mut gpu_manager := unsafe { manager }
		g17_resources = gpu_manager.create_g17_queue_resources(id, f.owner_process_id, channel_mask, request.priority) or {
			mut queue := unsafe { wq }
			queue.destroy()
			return -12
		}
	} else if manager.hw_config.gpu_gen == .g13 {
		mut channel_mask := u32(0)
		if request.queue_caps & ioctl.asahi_queue_cap_render != 0 {
			channel_mask |= gpu.g13_queue_channel_vertex
		}
		if request.queue_caps & (ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_blit) != 0 {
			channel_mask |= gpu.g13_queue_channel_fragment
		}
		if request.queue_caps & ioctl.asahi_queue_cap_compute != 0 {
			channel_mask |= gpu.g13_queue_channel_compute
		}
		mut gpu_manager := unsafe { manager }
		g13_resources = gpu_manager.create_g13_queue_resources(id, channel_mask, request.priority, vm) or {
			mut queue := unsafe { wq }
			queue.destroy()
			return -12
		}
	}
	f.lock.acquire()
	f.queues << wq
	if g17_resources != unsafe { nil } {
		f.g17_queues << G17QueueOwnership{
			queue_id: id
			resources: g17_resources
		}
	}
	if g13_resources != unsafe { nil } {
		f.g13_queues << G13QueueOwnership{
			queue_id: id
			resources: g13_resources
		}
	}
	f.lock.release()
	request.queue_id = id
	return 0
}

pub fn (mut f GpuFile) ioctl_queue_destroy(data &ioctl.DrmAsahiQueueDestroy) int {
	request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 {
		return -22
	}
	f.lock.acquire()
	for i, mut q in f.queues {
		if q.id == request.queue_id {
			mut resources := &gpu.G17QueueResources(unsafe { nil })
			mut g13_resources := &gpu.G13QueueResources(unsafe { nil })
			mut g17_index := -1
			mut g13_index := -1
			for ownership_index, ownership in f.g17_queues {
				if ownership.queue_id == request.queue_id {
					resources = ownership.resources
					g17_index = ownership_index
					break
				}
			}
			for ownership_index, ownership in f.g13_queues {
				if ownership.queue_id == request.queue_id {
					g13_resources = ownership.resources
					g13_index = ownership_index
					break
				}
			}
			manager := gpu.get_global_manager() or {
				f.lock.release()
				return -19
			}
			mut gpu_manager := unsafe { manager }
			// A G13 queue cannot disappear while a retained firmware job still
			// references its rings, notifier, TVB, or VM context.
			if g13_resources != unsafe { nil }
				&& !gpu_manager.release_g13_queue_resources(g13_resources) {
				f.lock.release()
				return -16 // EBUSY (or quarantined after a failed UAT flush)
			}
			if resources != unsafe { nil } {
				gpu_manager.release_g17_queue_resources(resources)
			}
			q.destroy()
			f.queues.delete(i)
			if g17_index >= 0 {
				f.g17_queues.delete(g17_index)
			}
			if g13_index >= 0 {
				f.g13_queues.delete(g13_index)
			}
			f.lock.release()
			return 0
		}
	}
	f.lock.release()
	return -22
}

// Validate the fixed render payload fields consumed by Mesa 25.0.5. These are
// the same limits enforced by the matching downstream Asahi UAPI. Extensions
// remain disabled until Vinix can copy and walk their userspace linked list
// without faulting in the kernel.
fn valid_render_command(command &ioctl.DrmAsahiCmdRender) bool {
	if command.extensions != 0 || command.flags & ~ioctl.asahi_render_supported_flags != 0 {
		return false
	}
	if command.fb_width == 0 || command.fb_width > max_render_dimension
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
	if command.vertex_attachment_count > max_command_attachments
		|| command.fragment_attachment_count > max_command_attachments
		|| (command.vertex_attachment_count != 0 && command.vertex_attachments == 0)
		|| (command.fragment_attachment_count != 0 && command.fragment_attachments == 0) {
		return false
	}
	return true
}

fn valid_compute_command(command &ioctl.DrmAsahiCmdCompute) bool {
	if command.extensions != 0 || command.flags & ~ioctl.asahi_compute_no_preemption != 0
		|| command.pad != 0 || command.attachment_count > max_command_attachments
		|| (command.attachment_count != 0 && command.attachments == 0) {
		return false
	}
	return true
}

// Copy every nested sync descriptor exactly once while the submission is
// staged and retain stable object/fence pointers. The Asahi UAPI uses timeline
// points for its cross-context flush sync even though generic DRM timeline
// ioctls are not exposed by Vinix yet.
fn stage_sync_array(owner u64, pointer u64, count u32, input bool) (int, StagedSyncArray) {
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
	for i := u32(0); i < count; i++ {
		mut item := ioctl.DrmAsahiSync{}
		if !usercopy.copy_from_user(voidptr(&item), pointer + u64(i) * sizeof(ioctl.DrmAsahiSync), sizeof(ioctl.DrmAsahiSync)) {
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
		obj := syncobj.lookup(owner, item.handle) or { return -22, staged }
		staged.objects[i] = obj
		staged.timeline[i] = item.sync_type == ioctl.asahi_sync_timeline_syncobj
		staged.timeline_values[i] = item.timeline_value
		if input {
			fence := if staged.timeline[i] {
				syncobj.get_timeline_fence(obj, item.timeline_value) or {
					return -22, staged
				}
			} else {
				syncobj.get_fence(obj) or { return -22, staged }
			}
			staged.fences[i] = fence
		}
	}
	return 0, staged
}

// Copy attachment records once and translate byte sizes into the firmware's
// 128-byte cache-line unit.
fn stage_attachment_array(pointer u64, count u32) (int, [16]gpu.G13ComputeAttachment) {
	mut staged := [16]gpu.G13ComputeAttachment{}
	if count == 0 {
		return 0, staged
	}
	if count > max_command_attachments || pointer == 0 {
		return -22, staged
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiAttachment)
	if bytes - 1 > ~pointer {
		return -14, staged
	}
	for i := u32(0); i < count; i++ {
		mut attachment := ioctl.DrmAsahiAttachment{}
		if !usercopy.copy_from_user(voidptr(&attachment), pointer + u64(i) * sizeof(ioctl.DrmAsahiAttachment), sizeof(ioctl.DrmAsahiAttachment)) {
			return -14, staged
		}
		if attachment.flags != 0 || attachment.order < 1 || attachment.order > 6 {
			return -22, staged
		}
		cache_lines := (attachment.size >> 7) + if attachment.size & u64(127) != 0 {
			u64(1)
		} else {
			u64(0)
		}
		if cache_lines > u64(~u32(0)) {
			return -22, staged
		}
		staged[i] = gpu.G13ComputeAttachment{
			address: attachment.pointer
			size: u32(cache_lines)
			order: u16(attachment.order)
		}
	}
	return 0, staged
}

fn wait_staged_syncs(staged &StagedSyncArray) int {
	for i := u32(0); i < staged.count; i++ {
		fence := staged.fences[i]
		if fence == unsafe { nil } {
			return -22
		}
		for !syncobj.is_signaled(fence) {
			manager := gpu.get_global_manager() or { return -19 }
			if manager.state != .running {
				return -19
			}
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
	for i := u32(0); i < staged.count; i++ {
		obj := staged.objects[i]
		if obj == unsafe { nil } {
			return false
		}
		if staged.timeline[i] {
			if !syncobj.add_timeline_point(obj, staged.timeline_values[i], fence) {
				return false
			}
		} else {
			syncobj.replace_fence(obj, fence)
		}
	}
	return true
}

fn make_g13_render_command(command &ioctl.DrmAsahiCmdRender,
	vertex_attachments [16]gpu.G13ComputeAttachment,
	fragment_attachments [16]gpu.G13ComputeAttachment, has_result bool) gpu.G13RenderCommand {
	return gpu.G13RenderCommand{
		flags: command.flags
		encoder_ptr: command.encoder_ptr
		vertex_usc_base: command.vertex_usc_base
		fragment_usc_base: command.fragment_usc_base
		vertex_helper_program: command.vertex_helper_program
		fragment_helper_program: command.fragment_helper_program
		vertex_helper_cfg: command.vertex_helper_cfg
		fragment_helper_cfg: command.fragment_helper_cfg
		vertex_helper_arg: command.vertex_helper_arg
		fragment_helper_arg: command.fragment_helper_arg
		depth_buffer_load: command.depth_buffer_load
		depth_buffer_load_stride: command.depth_buffer_load_stride
		depth_buffer_store: command.depth_buffer_store
		depth_buffer_store_stride: command.depth_buffer_store_stride
		depth_buffer_partial: command.depth_buffer_partial
		depth_buffer_partial_stride: command.depth_buffer_partial_stride
		depth_meta_buffer_load: command.depth_meta_buffer_load
		depth_meta_buffer_load_stride: command.depth_meta_buffer_load_stride
		depth_meta_buffer_store: command.depth_meta_buffer_store
		depth_meta_buffer_store_stride: command.depth_meta_buffer_store_stride
		depth_meta_buffer_partial: command.depth_meta_buffer_partial
		depth_meta_buffer_partial_stride: command.depth_meta_buffer_partial_stride
		stencil_buffer_load: command.stencil_buffer_load
		stencil_buffer_load_stride: command.stencil_buffer_load_stride
		stencil_buffer_store: command.stencil_buffer_store
		stencil_buffer_store_stride: command.stencil_buffer_store_stride
		stencil_buffer_partial: command.stencil_buffer_partial
		stencil_buffer_partial_stride: command.stencil_buffer_partial_stride
		stencil_meta_buffer_load: command.stencil_meta_buffer_load
		stencil_meta_buffer_load_stride: command.stencil_meta_buffer_load_stride
		stencil_meta_buffer_store: command.stencil_meta_buffer_store
		stencil_meta_buffer_store_stride: command.stencil_meta_buffer_store_stride
		stencil_meta_buffer_partial: command.stencil_meta_buffer_partial
		stencil_meta_buffer_partial_stride: command.stencil_meta_buffer_partial_stride
		scissor_array: command.scissor_array
		depth_bias_array: command.depth_bias_array
		visibility_result_buffer: command.visibility_result_buffer
		vertex_sampler_array: command.vertex_sampler_array
		vertex_sampler_count: command.vertex_sampler_count
		vertex_sampler_max: command.vertex_sampler_max
		fragment_sampler_array: command.fragment_sampler_array
		fragment_sampler_count: command.fragment_sampler_count
		fragment_sampler_max: command.fragment_sampler_max
		zls_control: command.zls_ctrl
		ppp_multisamplectl: command.ppp_multisamplectl
		ppp_control: command.ppp_ctrl
		framebuffer_width: command.fb_width
		framebuffer_height: command.fb_height
		utile_width: command.utile_width
		utile_height: command.utile_height
		samples: command.samples
		layers: command.layers
		encoder_id: command.encoder_id
		vertex_command_id: command.cmd_ta_id
		fragment_command_id: command.cmd_3d_id
		sample_size: command.sample_size
		tib_blocks: command.tib_blocks
		iogpu_unk_214: command.iogpu_unk_214
		merge_upper_x: command.merge_upper_x
		merge_upper_y: command.merge_upper_y
		load_pipeline: command.load_pipeline
		load_pipeline_bind: command.load_pipeline_bind
		store_pipeline: command.store_pipeline
		store_pipeline_bind: command.store_pipeline_bind
		partial_reload_pipeline: command.partial_reload_pipeline
		partial_reload_pipeline_bind: command.partial_reload_pipeline_bind
		partial_store_pipeline: command.partial_store_pipeline
		partial_store_pipeline_bind: command.partial_store_pipeline_bind
		depth_dimensions: command.depth_dimensions
		isp_bgobjdepth: command.isp_bgobjdepth
		isp_bgobjvals: command.isp_bgobjvals
		vertex_attachment_count: command.vertex_attachment_count
		fragment_attachment_count: command.fragment_attachment_count
		vertex_attachments: vertex_attachments
		fragment_attachments: fragment_attachments
		has_result: has_result
		flush_stamps: true
	}
}

fn make_g13_compute_command(command &ioctl.DrmAsahiCmdCompute,
	attachments [16]gpu.G13ComputeAttachment, has_result bool) gpu.G13ComputeCommand {
	return gpu.G13ComputeCommand{
		flags: command.flags
		encoder_ptr: command.encoder_ptr
		encoder_end: command.encoder_end
		usc_base: command.usc_base
		helper_program: command.helper_program
		helper_cfg: command.helper_cfg
		helper_arg: command.helper_arg
		encoder_id: command.encoder_id
		cmd_id: command.cmd_id
		sampler_array: command.sampler_array
		sampler_count: command.sampler_count
		sampler_max: command.sampler_max
		iogpu_unk_40: command.iogpu_unk_40
		unk_mask: command.unk_mask
		attachment_count: command.attachment_count
		attachments: attachments
		has_result: has_result
		flush_stamps: true
	}
}

fn finish_g13_submit(mut state G13SubmitCompletion, successful bool) {
	if state.file != unsafe { nil } && state.vm_id < mmu.uat_num_contexts {
		katomic.dec(mut &state.file.inflight_by_vm[state.vm_id])
	}
	if state.result != unsafe { nil } {
		gem.unref(state.result)
		state.result = unsafe { nil }
	}
	if successful {
		syncobj.signal(state.fence)
	} else {
		syncobj.signal_error(state.fence, -5)
	}
	unsafe {
		free(voidptr(state))
	}
}

fn g13_render_completed(job &gpu.G13RenderJobResources, successful bool, data voidptr) {
	if data == unsafe { nil } {
		return
	}
	mut state := unsafe { &G13SubmitCompletion(data) }
	if state.result != unsafe { nil } {
		values := job.result_values()
		mut result := ioctl.DrmAsahiResultRender{}
		result.info.status = if successful {
			ioctl.asahi_status_complete
		} else {
			ioctl.asahi_status_unknown_error
		}
		if successful {
			result.vertex_ts_start = values.vertex_start
			result.vertex_ts_end = values.vertex_end
			result.fragment_ts_start = values.fragment_start
			result.fragment_ts_end = values.fragment_end
			result.tvb_size_bytes = values.tvb_size_bytes
			result.tvb_usage_bytes = values.tvb_usage_bytes
			result.num_tvb_overflows = values.num_tvb_overflows
			if values.overflowed {
				result.flags |= ioctl.asahi_result_render_tvb_overflowed
			}
		}
		unsafe {
			C.memcpy(voidptr(state.result.virt_addr + state.result_offset), voidptr(&result), sizeof(ioctl.DrmAsahiResultRender))
		}
	}
	finish_g13_submit(mut state, successful)
}

fn g13_compute_completed(job &gpu.G13ComputeJobResources, successful bool, data voidptr) {
	if data == unsafe { nil } {
		return
	}
	mut state := unsafe { &G13SubmitCompletion(data) }
	if state.result != unsafe { nil } {
		values := job.timestamp_values()
		mut result := ioctl.DrmAsahiResultCompute{}
		result.info.status = if successful {
			ioctl.asahi_status_complete
		} else {
			ioctl.asahi_status_unknown_error
		}
		if successful {
			result.ts_start = values.start
			result.ts_end = values.end
		}
		unsafe {
			C.memcpy(voidptr(state.result.virt_addr + state.result_offset), voidptr(&result), sizeof(ioctl.DrmAsahiResultCompute))
		}
	}
	finish_g13_submit(mut state, successful)
}

// Submit one byte-exact v12.3 G13 command. Per-queue serialization preserves
// implicit subqueue ordering while native multi-command barriers remain
// unimplemented. G17/HAL300 payloads continue to fail closed.
pub fn (mut f GpuFile) ioctl_submit(data &ioctl.DrmAsahiSubmit) int {
	request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 || request.command_count != 1
		|| request.commands == 0
		|| request.in_sync_count > max_submission_syncs || request.out_sync_count > max_submission_syncs
		|| (request.in_sync_count != 0 && request.in_syncs == 0)
		|| (request.out_sync_count != 0 && request.out_syncs == 0) {
		return -22
	}
	sync_result, input_syncs := stage_sync_array(f.owner_key, request.in_syncs, request.in_sync_count, true)
	if sync_result != 0 {
		return sync_result
	}
	output_result, output_syncs := stage_sync_array(f.owner_key, request.out_syncs, request.out_sync_count, false)
	if output_result != 0 {
		return output_result
	}
	if sizeof(ioctl.DrmAsahiCommand) - 1 > ~request.commands {
		return -14
	}
	mut command := ioctl.DrmAsahiCommand{}
	if !usercopy.copy_from_user(voidptr(&command), request.commands, sizeof(ioctl.DrmAsahiCommand)) {
		return -14
	}
	if command.extensions != 0 || command.flags != 0 || command.cmd_buffer == 0
		|| (command.barriers[0] != ioctl.asahi_barrier_none && command.barriers[0] != 0)
		|| (command.barriers[1] != ioctl.asahi_barrier_none && command.barriers[1] != 0) {
		return -22
	}

	mut render_command := gpu.G13RenderCommand{}
	mut compute_command := gpu.G13ComputeCommand{}
	match command.cmd_type {
		ioctl.asahi_cmd_render {
			if command.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdRender)
				|| (command.result_size != 0
					&& command.result_size < sizeof(ioctl.DrmAsahiResultRender)) {
				return -22
			}
			mut render := ioctl.DrmAsahiCmdRender{}
			if !usercopy.copy_from_user(voidptr(&render), command.cmd_buffer, sizeof(ioctl.DrmAsahiCmdRender)) {
				return -14
			}
			if !valid_render_command(&render) {
				return -22
			}
			vertex_result, vertex_attachments := stage_attachment_array(render.vertex_attachments, render.vertex_attachment_count)
			if vertex_result != 0 {
				return vertex_result
			}
			fragment_result, fragment_attachments := stage_attachment_array(render.fragment_attachments, render.fragment_attachment_count)
			if fragment_result != 0 {
				return fragment_result
			}
			render_command = make_g13_render_command(&render, vertex_attachments, fragment_attachments, command.result_size != 0)
		}
		ioctl.asahi_cmd_compute {
			// Mesa 25.0.5 deliberately reports sizeof - 8 for compatibility
			// with 6.11.8 kernels, while still passing the full current struct.
			if (command.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute)
				&& command.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute) - u64(8))
				|| (command.result_size != 0
					&& command.result_size < sizeof(ioctl.DrmAsahiResultCompute)) {
				return -22
			}
			mut compute := ioctl.DrmAsahiCmdCompute{}
			if !usercopy.copy_from_user(voidptr(&compute), command.cmd_buffer, sizeof(ioctl.DrmAsahiCmdCompute)) {
				return -14
			}
			if !valid_compute_command(&compute) {
				return -22
			}
			attachment_result, attachments := stage_attachment_array(compute.attachments, compute.attachment_count)
			if attachment_result != 0 {
				return attachment_result
			}
			compute_command = make_g13_compute_command(&compute, attachments, command.result_size != 0)
		}
		else {
			return -22
		}
	}

	dependency_result := wait_staged_syncs(&input_syncs)
	if dependency_result != 0 {
		return dependency_result
	}
	manager := gpu.get_global_manager() or { return -19 }
	if manager.hw_config.gpu_gen != .g13 || manager.state != .running {
		return -95
	}
	mut gpu_manager := unsafe { manager }

	// Pin the file's queue, VM, mapping list, and result handle until the job
	// has been handed to the manager and its in-flight count is visible.
	f.lock.acquire()
	defer {
		f.lock.release()
	}
	mut queue_caps := u32(0)
	mut vm_id := u32(0)
	mut queue_found := false
	for queue in f.queues {
		if queue.id == request.queue_id {
			queue_caps = queue.caps
			vm_id = queue.vm_id
			queue_found = true
			break
		}
	}
	if !queue_found || vm_id == 0 || vm_id >= mmu.uat_num_contexts {
		return -22
	}
	mut queue_resources := &gpu.G13QueueResources(unsafe { nil })
	for ownership in f.g13_queues {
		if ownership.queue_id == request.queue_id {
			queue_resources = ownership.resources
			break
		}
	}
	if queue_resources == unsafe { nil }
		|| (command.cmd_type == ioctl.asahi_cmd_render
			&& queue_caps & ioctl.asahi_queue_cap_render == 0)
		|| (command.cmd_type == ioctl.asahi_cmd_compute
			&& queue_caps & ioctl.asahi_queue_cap_compute == 0) {
		return -22
	}
	vm := f.find_vm(vm_id) or { return -22 }

	for gpu_manager.g13_queue_busy(queue_resources) {
		if gpu_manager.state != .running {
			return -19
		}
		sched.yield(false)
	}

	mut result_object := &gem.GemObject(unsafe { nil })
	if command.result_size != 0 {
		if request.result_handle == 0 {
			return -22
		}
		for object in f.objects {
			if object.handle == request.result_handle {
				result_object = object
				break
			}
		}
		if result_object == unsafe { nil } || command.result_offset > result_object.size
			|| command.result_size > result_object.size - command.result_offset {
			return -22
		}
		gem.ref_obj(result_object)
	} else if command.result_offset != 0 {
		return -22
	}

	mut render_job := &gpu.G13RenderJobResources(unsafe { nil })
	mut compute_job := &gpu.G13ComputeJobResources(unsafe { nil })
	if command.cmd_type == ioctl.asahi_cmd_render {
		render_job = gpu_manager.prepare_g13_render_job(queue_resources, &render_command) or {
			if result_object != unsafe { nil } {
				gem.unref(result_object)
			}
			return -12
		}
	} else {
		compute_job = gpu_manager.prepare_g13_compute_job(queue_resources, vm, &compute_command) or {
			if result_object != unsafe { nil } {
				gem.unref(result_object)
			}
			return -12
		}
	}

	fence := syncobj.new_fence(f.owner_key, timer.get_ns())
	mut completion := &G13SubmitCompletion{
		file: unsafe { &f }
		vm_id: vm_id
		fence: fence
		result: result_object
		result_offset: command.result_offset
	}
	katomic.inc(mut &f.inflight_by_vm[vm_id])
	callback_set := if command.cmd_type == ioctl.asahi_cmd_render {
		gpu_manager.set_g13_render_completion(render_job, g13_render_completed, voidptr(completion))
	} else {
		gpu_manager.set_g13_compute_completion(compute_job, g13_compute_completed, voidptr(completion))
	}
	if !callback_set {
		katomic.dec(mut &f.inflight_by_vm[vm_id])
		if result_object != unsafe { nil } {
			gem.unref(result_object)
		}
		unsafe {
			free(voidptr(completion))
		}
		if render_job != unsafe { nil } {
			gpu_manager.release_g13_render_job(render_job)
		}
		if compute_job != unsafe { nil } {
			gpu_manager.release_g13_compute_job(compute_job)
		}
		return -5
	}
	if !install_output_syncs(&output_syncs, fence) {
		if render_job != unsafe { nil } {
			gpu_manager.release_g13_render_job(render_job)
		} else {
			gpu_manager.release_g13_compute_job(compute_job)
		}
		return -22
	}
	if command.cmd_type == ioctl.asahi_cmd_render {
		if !gpu_manager.submit_g13_render_job(render_job) {
			gpu_manager.release_g13_render_job(render_job)
			return -16
		}
	} else if !gpu_manager.submit_g13_compute_job(compute_job) {
		gpu_manager.release_g13_compute_job(compute_job)
		return -16
	}
	return 0
}

fn dispatch(handle voidptr, dev &drm.DrmDevice) ?&GpuFile {
	return get_or_create_file(handle, dev)
}

fn lookup_file(handle voidptr) ?&GpuFile {
	if handle == unsafe { nil } {
		return none
	}
	file_map_lock.acquire()
	defer { file_map_lock.release() }
	f := file_map[u64(handle)] or { return none }
	return f
}

pub fn close_gem_handle(_dev &drm.DrmDevice, handle voidptr, object_handle u32) int {
	f := lookup_file(handle) or { return -2 }
	mut file := unsafe { f }
	return file.close_object_handle(object_handle)
}

pub fn mmap_handle(_dev &drm.DrmDevice, handle voidptr, page u64, _flags int) voidptr {
	f := lookup_file(handle) or { return unsafe { nil } }
	mut file := unsafe { f }
	return file.mmap_page(page)
}

fn ioctl_get_params_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_get_params(unsafe { &ioctl.DrmAsahiGetParams(data) })
}

fn ioctl_vm_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_vm_create(unsafe { &ioctl.DrmAsahiVmCreate(data) })
}

fn ioctl_vm_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_vm_destroy(unsafe { &ioctl.DrmAsahiVmDestroy(data) })
}

fn ioctl_gem_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_gem_create(unsafe { &ioctl.DrmAsahiGemCreate(data) })
}

fn ioctl_gem_mmap_offset_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_gem_mmap_offset(unsafe { &ioctl.DrmAsahiGemMmapOffset(data) })
}

fn ioctl_gem_bind_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_gem_bind(unsafe { &ioctl.DrmAsahiGemBind(data) })
}

fn ioctl_queue_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_queue_create(unsafe { &ioctl.DrmAsahiQueueCreate(data) })
}

fn ioctl_queue_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_queue_destroy(unsafe { &ioctl.DrmAsahiQueueDestroy(data) })
}

fn ioctl_submit_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_submit(unsafe { &ioctl.DrmAsahiSubmit(data) })
}

fn ioctl_get_time_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_get_time(unsafe { &ioctl.DrmAsahiGetTime(data) })
}

fn ioctl_gem_bind_object_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut file := unsafe { f }
	return file.ioctl_gem_bind_object(unsafe { &ioctl.DrmAsahiGemBindObject(data) })
}

pub fn drm_ioctls() []drm.DrmIoctl {
	return [
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_params, handler: ioctl_get_params_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_create, handler: ioctl_vm_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_destroy, handler: ioctl_vm_destroy_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_create, handler: ioctl_gem_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_mmap_offset, handler: ioctl_gem_mmap_offset_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind, handler: ioctl_gem_bind_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_create, handler: ioctl_queue_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_destroy, handler: ioctl_queue_destroy_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_submit, handler: ioctl_submit_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_time, handler: ioctl_get_time_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind_object, handler: ioctl_gem_bind_object_handler },
	]
}
