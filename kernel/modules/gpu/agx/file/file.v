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
import proc
import usercopy

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

pub struct GpuFile {
pub mut:
	dev           &drm.DrmDevice = unsafe { nil }
	vms           []&mmu.UatContext
	queues        []&workqueue.WorkQueue
	mappings      []GpuMapping
	objects       []&gem.GemObject
	mmap_objects  []&gem.GemObject
	g17_queues    []G17QueueOwnership
	next_queue_id u32
	owner_process_id u32
	owner_key     u64
	lock          klock.Lock
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
		owner_process_id: u32(current.process.pid)
		owner_key: owner_key
	}
}

pub fn (mut f GpuFile) close() {
	f.lock.acquire()
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

fn (f &GpuFile) find_vm(vm_id u32) ?&mmu.UatContext {
	for vm in f.vms {
		if vm.id == vm_id {
			return unsafe { vm }
		}
	}
	return none
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
		unstable_uabi_version:       ioctl.drm_asahi_unstable_uabi_version
		feat_compat:                 u64(cfg.gpu_feat_compat)
		feat_incompat:               u64(cfg.gpu_feat_incompat)
		gpu_generation:              u32(cfg.gpu_gen)
		gpu_variant:                 asahi_variant(manager)
		gpu_revision:                asahi_revision(manager)
		chip_id:                     cfg.chip_id
		num_dies:                    cfg.max_dies
		num_clusters_total:          cfg.num_clusters
		num_cores_per_cluster:       cfg.num_cores_per_cluster
		num_frags_per_cluster:       if cfg.num_clusters == 0 { u32(0) } else { cfg.num_frags / cfg.num_clusters }
		num_gps_per_cluster:         if cfg.num_clusters == 0 { u32(0) } else { cfg.num_gps / cfg.num_clusters }
		num_cores_total_active:      cfg.gpu_core_count
		vm_page_size:                u32(pgtable.uat_pgsz)
		vm_user_start:               u64(0x100000000)
		vm_user_end:                 u64(1) << cfg.uat_ias
		vm_kernel_min_size:          u64(32) << 30
		max_syncs_per_submission:    max_submission_syncs
		max_commands_per_submission: max_submission_commands
		max_commands_in_flight:      workqueue.max_job_slots
		max_attachments:             max_command_attachments
		timer_frequency_hz:          u32(cfg.base_clock_hz)
		result_render_size:          u32(sizeof(ioctl.DrmAsahiResultRender))
		result_compute_size:         u32(sizeof(ioctl.DrmAsahiResultCompute))
		user_timestamp_frequency_hz: cfg.base_clock_hz
	}
	for i := u32(0); i < cfg.num_clusters && i < ioctl.drm_asahi_max_clusters; i++ {
		if i < cfg.core_mask_list.len {
			params.core_masks[i] = u64(cfg.core_mask_list[i])
		}
	}
	if cfg.perf_state_count > 0 {
		params.min_frequency_khz = cfg.perf_state_frequencies[0] / 1000
		params.max_frequency_khz = cfg.perf_state_frequencies[cfg.perf_state_count - 1] / 1000
	}
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
		|| request.kernel_start & pgtable.uat_pg_mask != 0
		|| request.kernel_end & pgtable.uat_pg_mask != 0 || request.kernel_end > address_limit {
		return -22
	}
	mut m := unsafe { mgr }
	ctx := m.create_context() or { return -12 }
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
		|| request.range > u64(-1) - request.addr {
		return -22
	}
	ctx := f.find_vm(request.vm_id) or { return -22 }
	if ctx.pgtable == unsafe { nil } {
		return -22
	}
	mut pt := unsafe { ctx.pgtable }

	match request.op {
		ioctl.asahi_bind_op_bind {
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
			if !pt.map(request.addr, obj.phys_addr + request.offset, request.range, protection) {
				gem.unref(obj)
				return -12
			}
			f.lock.acquire()
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
			pt.unmap(request.addr, request.range)
			f.lock.acquire()
			for i := f.mappings.len - 1; i >= 0; i-- {
				mapping := f.mappings[i]
				if mapping.vm_id == request.vm_id && mapping.addr == request.addr
					&& mapping.size == request.range {
					gem.unref(mapping.obj)
					f.mappings.delete(i)
				}
			}
			f.lock.release()
			return 0
		}
		ioctl.asahi_bind_op_unbind_all {
			if request.handle == 0 || request.flags != 0 || request.offset != 0 || request.addr != 0 {
				return -22
			}
			obj := f.get_object_ref(request.handle) or { return -2 }
			f.lock.acquire()
			for i := f.mappings.len - 1; i >= 0; i-- {
				mapping := f.mappings[i]
				if mapping.vm_id == request.vm_id && voidptr(mapping.obj) == voidptr(obj) {
					pt.unmap(mapping.addr, mapping.size)
					gem.unref(mapping.obj)
					f.mappings.delete(i)
				}
			}
			f.lock.release()
			gem.unref(obj)
			return 0
		}
		else {
			return -22
		}
	}
}

pub fn (mut f GpuFile) ioctl_queue_create(data &ioctl.DrmAsahiQueueCreate) int {
	mut request := unsafe { data }
	known_caps := ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_blit |
		ioctl.asahi_queue_cap_compute
	if request.extensions != 0 || request.flags != 0 || request.pad != 0 || request.priority > 3
		|| request.queue_caps == 0 || request.queue_caps & ~known_caps != 0 {
		return -22
	}
	f.find_vm(request.vm_id) or { return -22 }
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
		g17_resources = gpu_manager.create_g17_queue_resources(id, f.owner_process_id,
			channel_mask) or {
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
			q.destroy()
			f.queues.delete(i)
			mut resources := &gpu.G17QueueResources(unsafe { nil })
			for ownership_index, ownership in f.g17_queues {
				if ownership.queue_id == request.queue_id {
					resources = ownership.resources
					f.g17_queues.delete(ownership_index)
					break
				}
			}
			f.lock.release()
			if resources != unsafe { nil } {
				if manager := gpu.get_global_manager() {
					mut gpu_manager := unsafe { manager }
					gpu_manager.release_g17_queue_resources(resources)
				}
			}
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

// Copy every nested sync descriptor once while the submission is being
// staged. Timeline syncobjs are rejected because GET_CAP deliberately reports
// no timeline support; binary input syncobjs must already contain a fence.
fn validate_sync_array(owner u64, pointer u64, count u32, input bool) int {
	if count == 0 {
		return 0
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiSync)
	if pointer == 0 || bytes - 1 > ~pointer {
		return -14
	}
	for i := u32(0); i < count; i++ {
		mut item := ioctl.DrmAsahiSync{}
		if !usercopy.copy_from_user(voidptr(&item), pointer + u64(i) * sizeof(ioctl.DrmAsahiSync),
			sizeof(ioctl.DrmAsahiSync)) {
			return -14
		}
		if item.extensions != 0 || item.sync_type != ioctl.asahi_sync_syncobj
			|| item.timeline_value != 0 {
			return -22
		}
		obj := syncobj.lookup(owner, item.handle) or { return -22 }
		if input && obj.fence == unsafe { nil } {
			return -22
		}
	}
	return 0
}

// Validate attachment records before a future encoder is allowed to consume
// them. The firmware ABI stores sizes in 128-byte cache lines in a u32.
fn validate_attachment_array(pointer u64, count u32) int {
	if count == 0 {
		return 0
	}
	if count > max_command_attachments || pointer == 0 {
		return -22
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiAttachment)
	if bytes - 1 > ~pointer {
		return -14
	}
	for i := u32(0); i < count; i++ {
		mut attachment := ioctl.DrmAsahiAttachment{}
		if !usercopy.copy_from_user(voidptr(&attachment),
			pointer + u64(i) * sizeof(ioctl.DrmAsahiAttachment), sizeof(ioctl.DrmAsahiAttachment)) {
			return -14
		}
		if attachment.flags != 0 || attachment.order < 1 || attachment.order > 6 {
			return -22
		}
		cache_lines := (attachment.size >> 7) + if attachment.size & u64(127) != 0 {
			u64(1)
		} else {
			u64(0)
		}
		if cache_lines > u64(~u32(0)) {
			return -22
		}
	}
	return 0
}

fn (mut f GpuFile) get_queue_caps(queue_id u32) ?u32 {
	f.lock.acquire()
	defer { f.lock.release() }
	for q in f.queues {
		if q.id == queue_id {
			return q.caps
		}
	}
	return none
}

// Validate the Mesa envelope but do not reinterpret its command buffer as the
// obsolete v12.3 placeholder. G17/HAL300 work commands have a different,
// partially recovered layout; rejecting them is the only safe behavior until
// gpu.g17 has a complete encoder and completion path.
pub fn (mut f GpuFile) ioctl_submit(data &ioctl.DrmAsahiSubmit) int {
	request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 || request.command_count == 0
		|| request.command_count > max_submission_commands || request.commands == 0
		|| request.in_sync_count > max_submission_syncs || request.out_sync_count > max_submission_syncs
		|| (request.in_sync_count != 0 && request.in_syncs == 0)
		|| (request.out_sync_count != 0 && request.out_syncs == 0) {
		return -22
	}
	queue_caps := f.get_queue_caps(request.queue_id) or { return -22 }
	mut sync_result := validate_sync_array(f.owner_key, request.in_syncs, request.in_sync_count,
		true)
	if sync_result != 0 {
		return sync_result
	}
	sync_result = validate_sync_array(f.owner_key, request.out_syncs, request.out_sync_count,
		false)
	if sync_result != 0 {
		return sync_result
	}
	commands_bytes := u64(request.command_count) * sizeof(ioctl.DrmAsahiCommand)
	if commands_bytes - 1 > ~request.commands {
		return -14
	}
	mut prior_render_commands := u32(0)
	mut prior_compute_commands := u32(0)
	for i := u32(0); i < request.command_count; i++ {
		mut command := ioctl.DrmAsahiCommand{}
		if !usercopy.copy_from_user(voidptr(&command), request.commands + u64(i) * sizeof(ioctl.DrmAsahiCommand),
			sizeof(ioctl.DrmAsahiCommand)) {
			return -14
		}
		if command.extensions != 0 || command.flags != 0 || command.cmd_buffer == 0 {
			return -22
		}
		if (command.barriers[0] != ioctl.asahi_barrier_none
			&& command.barriers[0] > prior_render_commands)
			|| (command.barriers[1] != ioctl.asahi_barrier_none
			&& command.barriers[1] > prior_compute_commands) {
			return -22
		}
		match command.cmd_type {
			ioctl.asahi_cmd_render {
				if queue_caps & ioctl.asahi_queue_cap_render == 0
					|| command.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdRender)
					|| (command.result_size != 0
					&& command.result_size < sizeof(ioctl.DrmAsahiResultRender)) {
					return -22
				}
				mut render := ioctl.DrmAsahiCmdRender{}
				if !usercopy.copy_from_user(voidptr(&render), command.cmd_buffer,
					sizeof(ioctl.DrmAsahiCmdRender)) {
					return -14
				}
				if !valid_render_command(&render) {
					return -22
				}
				mut attachment_result := validate_attachment_array(render.vertex_attachments,
					render.vertex_attachment_count)
				if attachment_result != 0 {
					return attachment_result
				}
				attachment_result = validate_attachment_array(render.fragment_attachments,
					render.fragment_attachment_count)
				if attachment_result != 0 {
					return attachment_result
				}
				prior_render_commands++
			}
			ioctl.asahi_cmd_compute {
				if queue_caps & ioctl.asahi_queue_cap_compute == 0
					|| command.cmd_buffer_size != sizeof(ioctl.DrmAsahiCmdCompute)
					|| (command.result_size != 0
					&& command.result_size < sizeof(ioctl.DrmAsahiResultCompute)) {
					return -22
				}
				mut compute := ioctl.DrmAsahiCmdCompute{}
				if !usercopy.copy_from_user(voidptr(&compute), command.cmd_buffer,
					sizeof(ioctl.DrmAsahiCmdCompute)) {
					return -14
				}
				if !valid_compute_command(&compute) {
					return -22
				}
				attachment_result := validate_attachment_array(compute.attachments,
					compute.attachment_count)
				if attachment_result != 0 {
					return attachment_result
				}
				prior_compute_commands++
			}
			else { return -22 }
		}
		if command.result_size != 0 {
			if request.result_handle == 0 {
				return -22
			}
			result := f.get_object_ref(request.result_handle) or { return -2 }
			if command.result_offset > result.size
				|| command.result_size > result.size - command.result_offset {
				gem.unref(result)
				return -22
			}
			gem.unref(result)
		} else if command.result_offset != 0 {
			return -22
		}
	}
	return -95 // EOPNOTSUPP: native command encoding is not complete
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

pub fn drm_ioctls() []drm.DrmIoctl {
	return [
		drm.DrmIoctl{cmd: ioctl.drm_asahi_get_params, handler: ioctl_get_params_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_vm_create, handler: ioctl_vm_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_vm_destroy, handler: ioctl_vm_destroy_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_create, handler: ioctl_gem_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_mmap_offset, handler: ioctl_gem_mmap_offset_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_bind, handler: ioctl_gem_bind_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_queue_create, handler: ioctl_queue_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_queue_destroy, handler: ioctl_queue_destroy_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_submit, handler: ioctl_submit_handler},
	]
}
