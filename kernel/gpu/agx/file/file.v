@[has_globals]
module file

// Per-open DRM state for the Apple GPU. The public structures consumed here
// are the Mesa 25.0.5 unstable Asahi UAPI in drm.ioctl. G17 command submission
// stays fail-closed until its HAL300 work-command encoder is complete.

import drm
import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.bo as agxbo
import gpu.agx.params as agxparams
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.submission as agxsubmission
import gpu.agx.vm as agxvm
import gpu.agx.workqueue
import gpu.agx.gpu
import klock
import katomic
import proc
import usercopy
import aarch64.timer
import memory

const max_submission_commands = u32(64)
const max_submission_syncs = agxsubmission.max_syncs
const max_g13_submission_commands = agxsubmission.max_commands
const max_command_attachments = u32(16)

struct GpuMapping {
mut:
	vm_id    u32
	handle   u32
	addr     u64
	size     u64
	obj      &gem.GemObject = unsafe { nil }
	retiring bool // PTEs removed; backing retained until firmware invalidation completes
}

struct G17QueueOwnership {
	queue_id  u32
	resources &gpu.G17QueueResources = unsafe { nil }
}

struct G13QueueOwnership {
	queue_id  u32
	vm_id     u32
	resources &gpu.G13QueueResources = unsafe { nil }
}

struct TimestampObject {
	id   u32
	va   u64
	size u64
	obj  &gem.GemObject = unsafe { nil }
mut:
	references u64
	detached bool
}

struct G13SubmissionQueue {
	vm_id u32
	caps u32
	resources &gpu.G13QueueResources = unsafe { nil }
	retained bool
}

@[heap]
struct G13SubmitCompletion {
mut:
	file          &GpuFile = unsafe { nil }
	vm_id         u32
	result        &gem.GemObject = unsafe { nil }
	result_offset u64
	submission    &G13PendingSubmission = unsafe { nil }
	command_index u32
}

pub struct GpuFile {
pub mut:
	dev               &drm.DrmDevice = unsafe { nil }
	vms               []&mmu.UatContext
	detached_vms      [mmu.uat_num_contexts]bool // names removed; physical owners remain in vms
	queues            []&workqueue.WorkQueue
	mappings          []GpuMapping
	objects           agxbo.Table
	g17_queues        []G17QueueOwnership
	g13_queues        []G13QueueOwnership
	timestamp_objects []TimestampObject
	next_queue_id     u32
	next_timestamp_id u32
	owner_process_id  u32
	owner_key         u64
	inflight_by_vm    [mmu.uat_num_contexts]u64
	lock              klock.Lock
	closing_next      &GpuFile = unsafe { nil }
	closing_queued    bool
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
	if ff.close() {
		unsafe { free(voidptr(ff)) }
	} else { retire_closing_file(ff) }
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
	// find_vm() reads the VM list without the file lock, so it must never
	// move: sized for every context there is, as a file cannot have more VMs.
	// close() frees it.
	vms := []&mmu.UatContext{cap: mmu.uat_num_contexts} @[freed]
	mut f := &GpuFile{
		dev: unsafe { dev }
		next_queue_id: 1
		next_timestamp_id: 1
		owner_process_id: u32(current.process.pid)
		owner_key: owner_key
		vms: vms
	}
	// Nothing slices these, so growing one can free its old buffer.
	f.queues.flags |= .noslices
	f.mappings.flags |= .noslices
	f.g17_queues.flags |= .noslices
	f.g13_queues.flags |= .noslices
	f.timestamp_objects.flags |= .noslices
	return f
}

// Tear the file down. False when live jobs keep it, and with it the file
// itself, which completions still point at.
pub fn (mut f GpuFile) close() bool {
	f.lock.acquire()
	// Timestamp captures can precede the submission's VM pin. They keep the
	// file and its mapping owners alive even after namespace removal.
	for object in f.timestamp_objects {
		if object.references != 0 { f.lock.release(); return false }
	}
	for vm_id := u32(1); vm_id < mmu.uat_num_contexts; vm_id++ {
		if katomic.load(&f.inflight_by_vm[vm_id]) != 0 {
			// Completion callbacks still own this file. The worker retries its
			// close after their final reference is gone.
			f.lock.release()
			return false
		}
	}
	manager := gpu.get_global_manager() or { unsafe { nil } }
	if manager == unsafe { nil } && f.timestamp_objects.len != 0 {
		f.lock.release()
		return false
	}
	if manager != unsafe { nil } {
		mut gpu_manager := unsafe { manager }
		for ownership in f.g13_queues {
			if !gpu_manager.release_g13_queue_resources(ownership.resources) {
				// Failed invalidation retains backing in the manager. Keep the
				// VM and every userspace mapping alive until cleanup succeeds or
				// stopped firmware makes the retained queue safe to release.
				f.lock.release()
				return false
			}
		}
	}
	// Queue teardown alone does not invalidate userspace mappings. A failed
	// flush must keep their backing and VM alive for the next close retry.
	for index := f.mappings.len - 1; index >= 0; index-- {
		if !f.retire_mapping_locked(index) {
			f.lock.release()
			return false
		}
	}
	for mut q in f.queues { q.destroy() }
	unsafe { f.queues.free() }
	f.queues = []&workqueue.WorkQueue{}
	if manager != unsafe { nil } {
		mut gpu_manager := unsafe { manager }
		for ownership in f.g17_queues {
			gpu_manager.release_g17_queue_resources(ownership.resources)
		}
	}
	unsafe { f.g17_queues.free() }
	f.g17_queues = []G17QueueOwnership{}
	unsafe { f.g13_queues.free() }
	f.g13_queues = []G13QueueOwnership{}
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
	unsafe { f.timestamp_objects.free() }
	f.timestamp_objects = []TimestampObject{}

	mgr := uat_mgr
	if mgr != unsafe { nil } {
		mut m := unsafe { mgr }
		for vm in f.vms {
			m.destroy_context(vm)
		}
	}
	unsafe { f.vms.free() }
	f.vms = []&mmu.UatContext{}
	for mapping in f.mappings {
		gem.unref(mapping.obj)
	}
	unsafe { f.mappings.free() }
	f.mappings = []GpuMapping{}
	f.objects.release_all()
	f.lock.release()
	return true
}

fn (mut f GpuFile) get_object_ref(handle u32) ?&gem.GemObject {
	f.lock.acquire()
	defer { f.lock.release() }
	return f.objects.get_ref(handle)
}

fn (mut f GpuFile) import_object(obj &gem.GemObject) ?u32 {
	if obj == unsafe { nil } {
		return none
	}
	f.lock.acquire()
	handle := f.objects.import_object(obj) or {
		f.lock.release()
		return none
	}
	f.lock.release()
	return handle
}

fn (mut f GpuFile) authorize_mmap(handle u32) ?u64 {
	f.lock.acquire()
	defer { f.lock.release() }
	return f.objects.authorize_mmap(handle)
}

fn (mut f GpuFile) mmap_page(page u64) voidptr {
	f.lock.acquire()
	defer { f.lock.release() }
	return f.objects.mmap_page(page)
}

fn (mut f GpuFile) mmap_attributes(offset u64) u64 {
	f.lock.acquire()
	defer { f.lock.release() }
	return f.objects.mmap_attributes(offset)
}

fn (mut f GpuFile) valid_mmap_range(offset u64, length u64) bool {
	f.lock.acquire()
	defer { f.lock.release() }
	return f.objects.valid_mmap_range(offset, length)
}

// Caller holds file.lock and has excluded in-flight jobs from this VM. Once
// PTEs are removed, retries invalidate the same range without unmapping it
// again. The mapping's existing object reference is released only after the
// firmware acknowledges invalidation, or after firmware has stopped.
fn (mut f GpuFile) retire_mapping_locked(index int) bool {
	mapping := f.mappings[index]
	if mapping.vm_id >= mmu.uat_num_contexts
		|| katomic.load(&f.inflight_by_vm[mapping.vm_id]) != 0 { return false }
	ctx := f.find_owned_vm(mapping.vm_id) or { return false }
	if ctx.pgtable == unsafe { nil } { return false }
	if !mapping.retiring {
		mut pt := unsafe { ctx.pgtable }
		pt.unmap(mapping.addr, mapping.size)
		f.mappings[index].retiring = true
	}
	if !flush_firmware_mapping(ctx, mapping.addr, mapping.size, true) {
		return false
	}
	gem.unref(mapping.obj)
	f.mappings.delete(index)
	return true
}

// GEM_CLOSE drops every GPU-VA binding owned by the handle once the target VM
// is idle. A close racing an in-flight job leaves the binding retained; the
// next bind into that VM collects it after completion. CPU mmap authorization
// holds its own reference independently.
fn (mut f GpuFile) cleanup_closed_mappings_locked(vm_id u32) bool {
	if vm_id >= mmu.uat_num_contexts { return false }
	if katomic.load(&f.inflight_by_vm[vm_id]) != 0 {
		for mapping in f.mappings {
			if mapping.vm_id == vm_id && mapping.retiring { return false }
		}
		return true
	}
	mut success := true
	for index := f.mappings.len - 1; index >= 0; index-- {
		mapping := f.mappings[index]
		if mapping.vm_id != vm_id {
			continue
		}
		if !f.detached_vms[vm_id] && !mapping.retiring && f.objects.contains(mapping.obj) {
			continue
		}
		if !f.retire_mapping_locked(index) {
			success = false
		}
	}
	return success
}

fn (mut f GpuFile) close_object_handle(handle u32) int {
	f.lock.acquire()
	obj := f.objects.remove(handle) or {
		f.lock.release()
		return -2 // ENOENT
	}
	mut success := true
	for vm in f.vms {
		if !f.cleanup_closed_mappings_locked(vm.id) {
			success = false
		}
	}
	f.lock.release()
	gem.unref(obj)
	return if success { 0 } else { -5 }
}

// Reserve a complete replacement array before a range mutation takes any new
// BO references or changes PTEs. Records move; their existing owners do not.
fn (mut f GpuFile) reserve_mapping_slots_locked(extra int) bool {
	if extra < 0 { return false }
	needed := u64(f.mappings.len) + u64(extra)
	if needed <= u64(f.mappings.cap) { return true }
	if needed > 0x7fff_ffff || needed > ~u64(0) / sizeof(GpuMapping) { return false }
	// Fresh binds also use this path; keep growth amortized and fallible.
	mut capacity := needed
	if u64(f.mappings.cap) <= 0x3fff_ffff {
		doubled := u64(f.mappings.cap) * 2
		if doubled > capacity && doubled <= ~u64(0) / sizeof(GpuMapping) { capacity = doubled }
	}
	bytes := capacity * sizeof(GpuMapping)
	storage := memory.malloc_packed_fallible(bytes) @[freed]
	if storage == unsafe { nil } { return false }
	mut replacement := []GpuMapping{}
	unsafe {
		replacement.data = storage
		replacement.len = f.mappings.len
		replacement.cap = int(capacity)
		replacement.flags = .noslices
		if f.mappings.len != 0 { C.memcpy(storage, f.mappings.data, u64(f.mappings.len) * sizeof(GpuMapping)) }
	}
	mut old := unsafe { f.mappings }
	f.mappings = replacement
	unsafe { old.free() }
	return true
}

fn (f &GpuFile) mapping_survivor_count_locked(vm_id u32, addr u64, size u64) int {
	end := addr + size // The ioctl validated this full VA range before lookup.
	mut fragments := 0
	for mapping in f.mappings {
		if mapping.vm_id != vm_id || mapping.retiring
			|| !ranges_overlap(mapping.addr, mapping.size, addr, size) { continue }
		if mapping.addr < addr { fragments++ }
		if mapping.addr + mapping.size > end { fragments++ }
		// Disjoint mappings can straddle only the two ends of the request.
		if fragments > 2 { return -1 }
	}
	return fragments
}

// The file lock and idle-VM gate protect every fragment. The original owner
// becomes the removed interval's tombstone; each surviving piece owns one ref.
fn (mut f GpuFile) unbind_range_locked(vm_id u32, addr u64, size u64) int {
	end := addr + size
	fragments := f.mapping_survivor_count_locked(vm_id, addr, size)
	if fragments < 0 { return -22 }
	if !f.reserve_mapping_slots_locked(fragments) { return -12 }
	original_count := f.mappings.len
	mut flush_ok := true
	for i := original_count - 1; i >= 0; i-- {
		mapping := f.mappings[i]
		if mapping.vm_id != vm_id || !ranges_overlap(mapping.addr, mapping.size, addr, size) { continue }
		if !mapping.retiring {
			mapping_end := mapping.addr + mapping.size
			cut_start := if mapping.addr > addr { mapping.addr } else { addr }
			cut_end := if mapping_end < end { mapping_end } else { end }
			if mapping.addr < cut_start {
				gem.ref_obj(mapping.obj)
				f.mappings << GpuMapping{ vm_id: mapping.vm_id, handle: mapping.handle,
					addr: mapping.addr, size: cut_start - mapping.addr, obj: mapping.obj }
			}
			if cut_end < mapping_end {
				gem.ref_obj(mapping.obj)
				f.mappings << GpuMapping{ vm_id: mapping.vm_id, handle: mapping.handle,
					addr: cut_end, size: mapping_end - cut_end, obj: mapping.obj }
			}
			f.mappings[i].addr = cut_start
			f.mappings[i].size = cut_end - cut_start
		}
		// A prior tombstone retries its full recorded range, without unmapping
		// again or releasing backing before the invalidation completes.
		if !f.retire_mapping_locked(i) { flush_ok = false }
	}
	return if flush_ok { 0 } else { -5 }
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
		for ownership in f.g13_queues {
			if ownership.queue_id == candidate {
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
	if vm_id < mmu.uat_num_contexts && f.detached_vms[vm_id] { return none }
	return f.find_owned_vm(vm_id)
}

// Internal owners survive userspace namespace removal. Caller holds file.lock.
fn (f &GpuFile) find_owned_vm(vm_id u32) ?&mmu.UatContext {
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

// Firmware may retain both UAT translations and noncoherent cache lines after
// a mapping changes, so every bind and unbind has to invalidate them.
//
// Only G13's protocol is implemented. The full byte range is published in its
// handoff slot; FwCtlMsg only tells firmware which slot to process. Any other
// generation fails closed. Returning success without flushing would hand
// userspace a mapping the GPU may never observe, or keep a freed page live in
// a firmware translation.
fn flush_firmware_mapping(ctx &mmu.UatContext, addr u64, size u64, unmapped bool) bool {
	manager := gpu.get_global_manager() or { return false }
	if manager.hw_config.gpu_gen != .g13 {
		println('agx: no firmware mapping-flush protocol for this GPU generation')
		return false
	}
	mut gpu_manager := unsafe { manager }
	return gpu_manager.flush_g13_file_mapping(ctx.id, addr, size, unmapped)
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
		vm_kernel_min_size: agxvm.kernel_min_size
		max_syncs_per_submission: max_submission_syncs
		max_commands_per_submission: if cfg.gpu_gen == .g13 {
			max_g13_submission_commands
		} else {
			max_submission_commands
		}
		max_commands_in_flight: workqueue.max_job_slots
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
	request := unsafe { data }
	if request.extensions != 0 || request.param_group != 0 || request.pad != 0 {
		return -22 // EINVAL
	}
	manager := gpu.get_global_manager() or { return -19 }
	mut gpu_manager := unsafe { manager }
	if !gpu_manager.can_query_global_params() { return -19 }
	params := make_global_params(manager)
	return agxparams.copy_global(request, unsafe { &params })
}

pub fn (mut f GpuFile) ioctl_vm_create(data &ioctl.DrmAsahiVmCreate) int {
	mut request := unsafe { data }
	mgr := uat_mgr
	if mgr == unsafe { nil } {
		return -19
	}
	address_limit := u64(1) << mgr.ias
	if request.extensions != 0 || request.pad != 0
		|| !agxvm.valid_window(request.kernel_start, request.kernel_end)
		|| request.kernel_end > address_limit {
		return -22
	}
	mut m := unsafe { mgr }
	ctx := m.create_context(request.kernel_start, request.kernel_end) or { return -12 }
	m.bind_context(ctx)
	f.lock.acquire()
	f.detached_vms[ctx.id] = false
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
	if request.vm_id == 0 || request.vm_id >= mmu.uat_num_contexts { return -2 }
	f.lock.acquire()
	defer { f.lock.release() }
	vm := f.find_vm(request.vm_id) or { return -2 }
	if vm.id == 0 || vm.id >= mmu.uat_num_contexts { return -22 }
	// Match Asahi's namespace removal independently of retained queue/job
	// owners. Existing queues keep their VM; new VM-name lookups fail.
	f.detached_vms[vm.id] = true
	f.reap_detached_vms_locked()
	return 0
}

// Caller holds file.lock. User bindings retire only after accepted jobs are
// idle; failed invalidation keeps their object and context for a later retry.
// Queue owners (including failed-create quarantine) retain driver mappings.
fn (mut f GpuFile) reap_detached_vms_locked() {
	if uat_mgr == unsafe { nil } { return }
	for index := f.vms.len - 1; index >= 0; index-- {
		vm := f.vms[index]
		vm_id := vm.id
		if vm_id == 0 || vm_id >= mmu.uat_num_contexts || !f.detached_vms[vm_id] { continue }
		if katomic.load(&f.inflight_by_vm[vm_id]) != 0 { continue }
		if !f.cleanup_closed_mappings_locked(vm_id) { continue }
		mut retained := false
		for queue in f.queues {
			if queue.vm_id == vm_id { retained = true; break }
		}
		for ownership in f.g13_queues {
			if ownership.vm_id == vm_id { retained = true; break }
		}
		if retained { continue }
		mut manager := unsafe { uat_mgr }
		manager.destroy_context(vm)
		f.vms.delete(index)
		f.detached_vms[vm_id] = false
	}
}

pub fn (mut f GpuFile) ioctl_gem_create(data &ioctl.DrmAsahiGemCreate) int {
	mut request := unsafe { data }
	valid_flags := ioctl.asahi_gem_writeback | ioctl.asahi_gem_vm_private
	if request.extensions != 0 || request.pad != 0 || request.flags & ~valid_flags != 0 {
		return -22
	}
	f.lock.acquire()
	defer { f.lock.release() }
	mut private_identity := u64(0)
	if request.flags & ioctl.asahi_gem_vm_private != 0 {
		vm := f.find_vm(request.vm_id) or { return -2 }
		if vm.identity == 0 { return -22 }
		private_identity = vm.identity
	} else if request.vm_id != 0 {
		return -22
	}
	size_error := agxbo.create_size_error(request.size)
	if size_error != 0 { return size_error }
	obj := gem.create_aligned_with_cache(request.size, pgtable.uat_pgsz, private_identity,
		request.flags & ioctl.asahi_gem_writeback != 0) or { return -12 }
	f.objects.add_created(obj)
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
	if request.op == ioctl.asahi_bind_op_bind {
		if !agxvm.valid_bind_header(request) { return -22 }
	} else if !agxvm.valid_bind_shape(request) { return -22 }
	// Keep VM/page-table and handle lookup stable through mapping mutation.
	f.lock.acquire()
	defer { f.lock.release() }
	match request.op {
		ioctl.asahi_bind_op_bind {
			obj := f.objects.get_ref(request.handle) or { return -2 }
			backing_bytes := agxvm.bind_backing_size(request)
			if request.offset > obj.size || backing_bytes > obj.size - request.offset {
				gem.unref(obj)
				return -22
			}
			if !agxvm.valid_bind_shape(request) {
				gem.unref(obj)
				return -22
			}
			// The BO owner must be returned on every VM/private-window failure.
			ctx := f.find_vm(request.vm_id) or { gem.unref(obj); return -2 }
			if ctx.pgtable == unsafe { nil }
				|| !agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end) {
				gem.unref(obj)
				return -22
			}
			if obj.vm_private_identity != 0 && obj.vm_private_identity != ctx.identity {
				gem.unref(obj)
				return -22
			}
			mut pt := unsafe { ctx.pgtable }
			protection := if request.flags & ioctl.asahi_bind_read != 0 {
				if request.flags & ioctl.asahi_bind_write != 0 {
					pgtable.gpu_prot_gpu_shared_rw
				} else { pgtable.gpu_prot_gpu_shared_ro }
			} else {
				pgtable.gpu_prot_gpu_shared_wo
			}
			if !f.cleanup_closed_mappings_locked(request.vm_id) {
				gem.unref(obj)
				return -5
			}
			mut replacing := false
			for mapping in f.mappings {
				if mapping.vm_id == request.vm_id
					&& ranges_overlap(mapping.addr, mapping.size, request.addr, request.range) {
					replacing = true
					break
				}
			}
			if replacing && (request.vm_id >= mmu.uat_num_contexts
				|| katomic.load(&f.inflight_by_vm[request.vm_id]) != 0) {
				gem.unref(obj)
				return -16 // EBUSY: replacement must not remove pages used by jobs.
			}
			fragments := f.mapping_survivor_count_locked(request.vm_id, request.addr, request.range)
			if fragments < 0 { gem.unref(obj); return -22 }
			if !f.reserve_mapping_slots_locked(fragments + 1) {
				gem.unref(obj)
				return -12
			}
			if !pt.prepare_map_range(request.addr, request.range) {
				gem.unref(obj)
				return -12
			}
			if replacing {
				retired := f.unbind_range_locked(request.vm_id, request.addr, request.range)
				if retired != 0 { gem.unref(obj); return retired }
			}
			mapped := if request.flags & ioctl.asahi_bind_single_page != 0 {
				pt.map_repeated_page(request.addr, obj.phys_addr + request.offset, request.range, protection)
			} else { pt.map(request.addr, obj.phys_addr + request.offset, request.range, protection) }
			if !mapped {
				gem.unref(obj)
				return -12
			}
			f.mappings << GpuMapping{
				vm_id: request.vm_id
				handle: request.handle
				addr: request.addr
				size: request.range
				obj: obj
			}
			if !flush_firmware_mapping(ctx, request.addr, request.range, false) {
				// Firmware may have observed the new mapping before the flush
				// failed. Remove PTEs but retain backing until a retry is safe.
				pt.unmap(request.addr, request.range)
				f.mappings[f.mappings.len - 1].retiring = true
				return -5 // EIO
			}
			return 0
		}
		ioctl.asahi_bind_op_unbind {
			ctx := f.find_vm(request.vm_id) or { return -2 }
			if ctx.pgtable == unsafe { nil }
				|| !agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end) { return -22 }
			if request.vm_id >= mmu.uat_num_contexts
				|| katomic.load(&f.inflight_by_vm[request.vm_id]) != 0 {
				return -16 // EBUSY: firmware may still dereference this mapping
			}
			return f.unbind_range_locked(request.vm_id, request.addr, request.range)
		}
		ioctl.asahi_bind_op_unbind_all {
			ctx := f.find_vm(request.vm_id) or { return -2 }
			if ctx.pgtable == unsafe { nil }
				|| !agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end) { return -22 }
			obj := f.objects.get_ref(request.handle) or { return -2 }
			if request.vm_id >= mmu.uat_num_contexts
				|| katomic.load(&f.inflight_by_vm[request.vm_id]) != 0 {
				gem.unref(obj)
				return -16
			}
			mut flush_ok := true
			for i := f.mappings.len - 1; i >= 0; i-- {
				mapping := f.mappings[i]
				if mapping.vm_id == request.vm_id && voidptr(mapping.obj) == voidptr(obj) {
					if !f.retire_mapping_locked(i) {
						flush_ok = false
					}
				}
			}
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
	// Mesa 25.0.5 interprets this value in timer_frequency_hz units and
	// performs the nanosecond conversion itself. G13 firmware timestamps use
	// the same architectural counter, so returning nanoseconds here would
	// make CPU/GPU correlation roughly 41.7x too large on a 24 MHz M1.
	request.gpu_timestamp = timer.get_count()
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
				|| request.offset & pgtable.uat_pg_mask != 0
				|| request.range & pgtable.uat_pg_mask != 0
				|| request.range > ~request.offset {
				return -22
			}
			// object_handle is output-only. Empty ranges are a mapping error
			// after BO lookup; overflow is a request error before lookup.
			obj := f.get_object_ref(request.handle) or { return -2 }
			// Timestamp objects belong to the kernel VM, outside any private
			// userspace reservation domain.
			if obj.vm_private_identity != 0 { gem.unref(obj); return -22 }
			if request.range == 0 || request.offset > obj.size || request.range > obj.size - request.offset
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
				|| request.range != 0 {
				return -22
			}
			f.lock.acquire()
			mut found := TimestampObject{}
			mut found_index := -1
			for index, object in f.timestamp_objects {
				if object.id == request.object_handle && !object.detached {
					found = object
					found_index = index
					break
				}
			}
			if found_index < 0 {
				f.lock.release()
				return -2
			}
			if found.references != 0 {
				f.timestamp_objects[found_index].detached = true
				f.lock.release()
				return 0
			}
			// Keep the existing mapping owner installed if its manager is
			// unavailable. Missing names, including zero, still return ENOENT.
			manager := gpu.get_global_manager() or { f.lock.release(); return -19 }
			f.timestamp_objects.delete(found_index)
			f.lock.release()
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
	if request.extensions != 0 || request.flags != 0 || request.pad != 0 || request.priority > ioctl.asahi_priority_realtime
		|| request.queue_caps == 0 || request.queue_caps & ~known_caps != 0 {
		return -22
	}
	manager := gpu.get_global_manager() or { return -19 }
	// On G13, refuse unsupported HIGH and reserved REALTIME, as in Asahi.
	// Userspace numbering increases with priority; firmware bands decrease.
	if manager.hw_config.gpu_gen == .g13 && request.priority > ioctl.asahi_priority_medium { return -22 }
	firmware_priority := if manager.hw_config.gpu_gen == .g13 {
		ioctl.asahi_priority_realtime - request.priority
	} else { request.priority }
	f.lock.acquire()
	defer { f.lock.release() }
	// Keep the VM and its page table alive until the new queue is installed.
	vm := f.find_vm(request.vm_id) or { return -2 }
	id := f.allocate_queue_id_locked() or { return -24 } // EMFILE
	wq := workqueue.new_workqueue(id, request.vm_id, firmware_priority, request.queue_caps) or {
		return -12
	}
	mut g17_resources := &gpu.G17QueueResources(unsafe { nil })
	mut g13_resources := &gpu.G13QueueResources(unsafe { nil })
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
			unsafe { free(queue) }
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
		g13_resources = gpu_manager.create_g13_queue_resources(id, channel_mask, firmware_priority, vm) or {
			// Failed invalidation may leave a partially built queue borrowing
			// this VM. Adopt that graph before releasing the file lock.
			if retained := gpu_manager.retained_g13_queue_resources(id, vm) {
				f.g13_queues << G13QueueOwnership{ queue_id: id, vm_id: request.vm_id, resources: retained }
			}
			mut queue := unsafe { wq }
			queue.destroy()
			unsafe { free(queue) }
			return -12
		}
	}
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
			vm_id: request.vm_id
			resources: g13_resources
		}
	}
	request.queue_id = id
	return 0
}

// Caller holds file.lock. Captured ioctls and accepted submission nodes retain
// their own queue through staging, callbacks and final aggregate retirement.
// Unrelated work in the same VM does not postpone this queue's release.
fn (mut f GpuFile) reap_detached_g13_queues_locked() {
	manager := gpu.get_global_manager() or { return }
	mut gpu_manager := unsafe { manager }
	for i := f.queues.len - 1; i >= 0; i-- {
		mut q := unsafe { f.queues[i] }
		if !q.detached { continue }
		mut owner_index := -1
		for index, ownership in f.g13_queues {
			if ownership.queue_id == q.id { owner_index = index; break }
		}
		if owner_index < 0 { continue }
		ownership := f.g13_queues[owner_index]
		if ownership.resources.has_file_references() { continue }
		if !gpu_manager.release_g13_queue_resources(ownership.resources) { continue }
		q.destroy()
		f.queues.delete(i)
		f.g13_queues.delete(owner_index)
	}
}

// Failed construction may retain a GPU graph without installing a logical
// queue. Retry that graph independently of the file/VM name lifetime, while
// every published or captured queue keeps its original owner installed.
// Caller holds file.lock; physical release retains its manager/job guards.
fn (mut f GpuFile) reap_orphaned_g13_queues_locked() {
	manager := gpu.get_global_manager() or { return }
	mut gpu_manager := unsafe { manager }
	for index := f.g13_queues.len - 1; index >= 0; index-- {
		ownership := f.g13_queues[index]
		mut named := false
		for queue in f.queues {
			if queue.id == ownership.queue_id { named = true; break }
		}
		if named || ownership.resources.has_file_references() { continue }
		if !gpu_manager.release_g13_queue_resources(ownership.resources) { continue }
		f.g13_queues.delete(index)
	}
}

// The registry lock pins each open file against release_handle without a new
// reference or allocation. The worker calls this outside the manager lock;
// files already removed from the registry use the ordinary closing-file path.
fn reap_open_detached_g13_queues() {
	file_map_lock.acquire()
	for _, file in file_map {
		mut owned := unsafe { file }
		owned.lock.acquire()
		owned.reap_detached_g13_queues_locked()
		owned.reap_orphaned_g13_queues_locked()
		owned.reap_detached_timestamp_objects_locked()
		owned.reap_detached_vms_locked()
		owned.lock.release()
	}
	file_map_lock.release()
}

pub fn (mut f GpuFile) ioctl_queue_destroy(data &ioctl.DrmAsahiQueueDestroy) int {
	request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 {
		return -22
	}
	f.lock.acquire()
	for i, mut q in f.queues {
		if q.id == request.queue_id && !q.detached {
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
			if g13_resources != unsafe { nil } {
				// Namespace removal succeeds independently of live jobs or a
				// temporarily unavailable manager. Retained ownership is retried
				// by the worker, or by close after the Handle is released.
				q.detached = true
				f.reap_detached_g13_queues_locked()
				f.reap_detached_vms_locked()
				f.lock.release()
				return 0
			}
			manager := gpu.get_global_manager() or {
				f.lock.release()
				return -19
			}
			mut gpu_manager := unsafe { manager }
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
	return -2 // ENOENT: no queue in this open-file namespace.
}

fn discard_g13_completion(mut state G13SubmitCompletion) {
	submission := state.submission
	command_index := state.command_index
	if state.file != unsafe { nil } && state.vm_id < mmu.uat_num_contexts {
		katomic.dec(mut &state.file.inflight_by_vm[state.vm_id])
	}
	if state.result != unsafe { nil } {
		gem.unref(state.result)
		state.result = unsafe { nil }
	}
	unsafe {
		free(voidptr(state))
	}
	if submission != unsafe { nil } {
		// Only private callback retirement permits per-command capture release.
		// done is published earlier, while completion backing is still live.
		katomic.store(mut &submission.commands[command_index].callback_finished, true)
		// Last node access: zero permits the worker to free the submission.
		katomic.dec(mut &submission.callbacks_remaining)
	}
}

fn finish_g13_submit(mut state G13SubmitCompletion, successful bool, failure int) {
	mut result := if successful { 0 } else { failure }
	if state.submission != unsafe { nil } {
		override_error := katomic.load(&state.submission.failure)
		if override_error != 0 { result = int(override_error) }
		katomic.store(mut &state.submission.commands[state.command_index].error, i64(result))
		katomic.store(mut &state.submission.commands[state.command_index].done, true)
	}
	discard_g13_completion(mut state)
}

fn g13_render_completed(job &gpu.G13RenderJobResources, successful bool, data voidptr) {
	if data == unsafe { nil } {
		return
	}
	mut state := unsafe { &G13SubmitCompletion(data) }
	if state.result != unsafe { nil } {
		values := job.result_values()
		mut result := ioctl.DrmAsahiResultRender{}
		result.info = g13_result_info(&job.error, successful)
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
	finish_g13_submit(mut state, successful, job.error.fence_error())
}

fn g13_compute_completed(job &gpu.G13ComputeJobResources, successful bool, data voidptr) {
	if data == unsafe { nil } {
		return
	}
	mut state := unsafe { &G13SubmitCompletion(data) }
	if state.result != unsafe { nil } {
		values := job.timestamp_values()
		mut result := ioctl.DrmAsahiResultCompute{}
		result.info = g13_result_info(&job.error, successful)
		if successful {
			result.ts_start = values.start
			result.ts_end = values.end
		}
		unsafe {
			C.memcpy(voidptr(state.result.virt_addr + state.result_offset), voidptr(&result), sizeof(ioctl.DrmAsahiResultCompute))
		}
	}
	finish_g13_submit(mut state, successful, job.error.fence_error())
}

fn g13_result_info(failure &gpu.G13JobError, successful bool) ioctl.DrmAsahiResultInfo {
	return ioctl.DrmAsahiResultInfo{
		status: if successful { ioctl.asahi_status_complete } else if failure.status != 0 {
			failure.status
		} else { ioctl.asahi_status_unknown_error }
		fault_type: failure.fault_type
		unit: failure.unit
		sideband: failure.sideband
		level: failure.level
		is_read: failure.is_read
		extra: failure.extra
		address: failure.address
	}
}

// Caller holds the file lock. A failed setup is unwound by cancel_g13_pending
// before the node is freed, including callbacks already installed on prior jobs.
fn (mut f GpuFile) install_g13_batch_completion(mut pending G13PendingSubmission,
	index u32, command &agxsubmission.Command,
	result_object &gem.GemObject) int {
	mut manager := unsafe { pending.manager }
	mut entry := &pending.commands[index]
	is_compute := command.descriptor.cmd_type == ioctl.asahi_cmd_compute
	if command.descriptor.result_size != 0 { gem.ref_obj(result_object) }
	mut completion := &G13SubmitCompletion{
		file: unsafe { &f }
		vm_id: pending.vm_id
		result: if command.descriptor.result_size != 0 { unsafe { result_object } } else { unsafe { nil } }
		result_offset: command.descriptor.result_offset
		submission: unsafe { &pending }
		command_index: index
	} @[freed]
	katomic.inc(mut &pending.callbacks_remaining)
	katomic.inc(mut &f.inflight_by_vm[pending.vm_id])
	installed := if is_compute {
		manager.set_g13_compute_completion(entry.compute_job, g13_compute_completed, voidptr(completion))
	} else {
		manager.set_g13_render_completion(entry.render_job, g13_render_completed, voidptr(completion))
	}
	if !installed { discard_g13_completion(mut completion); return -5 }
	return 0
}

// Capture immutable queue state and an owned resource reference before user
// copies, as Asahi does with its initial Arc clone. Namespace removal can hide
// the name while this captured submission still uses the original queue.
fn (mut f GpuFile) capture_submission_queue(queue_id u32) ?G13SubmissionQueue {
	f.lock.acquire()
	defer { f.lock.release() }
	for queue in f.queues {
		if queue.id != queue_id || queue.detached { continue }
		for ownership in f.g13_queues {
			if ownership.queue_id == queue_id && ownership.resources != unsafe { nil }
				&& queue.vm_id != 0 && queue.vm_id < mmu.uat_num_contexts {
				mut resources := unsafe { ownership.resources }
				resources.retain_file_reference()
				return G13SubmissionQueue{vm_id: queue.vm_id, caps: queue.caps, resources: resources, retained: true}
			}
		}
		// Preserve backend/invalid-internal-state validation after staging for
		// non-G13 or malformed logical queues, without borrowing any resource.
		return G13SubmissionQueue{vm_id: queue.vm_id, caps: queue.caps}
	}
	return none
}

fn release_submission_queue(captured G13SubmissionQueue) {
	if !captured.retained { return }
	mut resources := unsafe { captured.resources }
	resources.release_file_reference()
}

// Copy userspace input without holding backend locks. Large batches use fallible
// owned heap storage rather than putting 64 command payloads on a kernel stack.
pub fn (mut f GpuFile) ioctl_submit(data &ioctl.DrmAsahiSubmit) int {
	request := unsafe { data }
	if request.extensions != 0 || request.flags != 0 || request.command_count == 0
		|| request.command_count > max_g13_submission_commands || request.commands == 0
		|| request.in_sync_count > max_submission_syncs || request.out_sync_count > max_submission_syncs
		|| (request.in_sync_count != 0 && request.in_syncs == 0)
		|| (request.out_sync_count != 0 && request.out_syncs == 0) { return -22 }
	captured := f.capture_submission_queue(request.queue_id) or { return -2 }
	mut transferred := false
	defer { if !transferred { release_submission_queue(captured) } }
	stage_bytes := u64(request.command_count) * sizeof(agxsubmission.Command)
	stage_storage := memory.malloc_packed_fallible(stage_bytes) @[freed]
	if stage_storage == unsafe { nil } { return -12 }
	defer { memory.free(stage_storage) }
	mut commands := []agxsubmission.Command{}
	unsafe {
		commands.data = stage_storage
		commands.len = int(request.command_count)
		commands.cap = int(request.command_count)
		commands.flags = .nogrow | .nofree
	}
	command_result := agxsubmission.stage_command_array(request.commands, request.command_count, mut commands)
	if command_result != 0 { return command_result }
	sync_result, input_syncs := agxsubmission.stage_sync_array(f.owner_key, request.in_syncs, request.in_sync_count, true)
	if sync_result != 0 { return sync_result }
	output_result, output_syncs := agxsubmission.stage_sync_array(f.owner_key, request.out_syncs, request.out_sync_count, false)
	if output_result != 0 { return output_result }
	code := f.submit_g13_staged(captured, commands, &input_syncs, &output_syncs, request.result_handle)
	transferred = code == 0
	return code
}

// Both copied input formats share preparation and pending ownership. The
// caller retains captured on failure; successful registration transfers it.
// Modern ioctl registration still requires a coordinated UAPI transition.
fn (mut f GpuFile) submit_g13_staged(captured G13SubmissionQueue,
	commands []agxsubmission.Command, input_syncs &agxsubmission.SyncArray,
	output_syncs &agxsubmission.SyncArray, result_handle u32) int {
	if commands.len == 0 || commands.len > int(max_g13_submission_commands) { return -22 }
	manager := gpu.get_global_manager() or { return -19 }
	mut state_manager := unsafe { manager }
	status := state_manager.g13_submission_status()
	if status != 0 { return status }
	// Captures acquire file.lock independently, before backend preparation.
	// This outer defer runs after the file-lock defer and pending cancellation.
	timestamp_code, captured_timestamps := f.new_g13_submission_timestamps(commands)
	if timestamp_code != 0 { return timestamp_code }
	timestamps := captured_timestamps
	mut timestamps_transferred := false
	defer { if !timestamps_transferred { f.release_g13_submission_timestamps(timestamps) } }
	f.lock.acquire()
	mut unqueued_fence := &syncobj.DmaFence(unsafe { nil })
	mut unqueued_failure := 0
	defer {
		f.lock.release()
		// Error cleanup may have exposed a prefix of the output sync array.
		// Deliver its notification after dropping file.lock and node backing.
		if unqueued_fence != unsafe { nil } { signal_g13_submission_fence(unqueued_fence, unqueued_failure) }
	}
	vm_id := captured.vm_id
	queue_caps := captured.caps
	if vm_id == 0 || vm_id >= mmu.uat_num_contexts { return -22 }
	vm := f.find_owned_vm(vm_id) or { return -22 }
	// Never publish work through an incompletely invalidated mapping. This
	// also retries mappings retained by an earlier GEM_CLOSE once VM pins end.
	if !f.cleanup_closed_mappings_locked(vm_id) { return -5 }
	if !captured.retained { return -22 }
	queue_resources := captured.resources
	mut result_object := &gem.GemObject(unsafe { nil })
	for command in commands {
		descriptor := command.descriptor
		if (descriptor.cmd_type == ioctl.asahi_cmd_compute && queue_caps & ioctl.asahi_queue_cap_compute == 0)
			|| (descriptor.cmd_type == ioctl.asahi_cmd_render && queue_caps & ioctl.asahi_queue_cap_render == 0) { return -22 }
		if descriptor.result_size != 0 {
			if result_handle == 0 { return -22 }
			if result_object == unsafe { nil } { result_object = f.objects.find(result_handle) or { unsafe { nil } } }
			if result_object == unsafe { nil } || descriptor.result_offset > result_object.size
				|| descriptor.result_size > result_object.size - descriptor.result_offset { return -22 }
		} else if descriptor.result_offset != 0 { return -22 }
	}
	storage := memory.malloc_packed_fallible(sizeof(G13PendingSubmission)) @[freed]
	if storage == unsafe { nil } { return -12 }
	mut pending := unsafe { &G13PendingSubmission(storage) }
	unsafe { *pending = G13PendingSubmission{
		file: &f
		vm_id: vm_id
		queue: queue_resources
		manager: manager
		dependencies: *input_syncs
		command_count: u32(commands.len)
		timestamps: timestamps
	} }
	if !resolve_g13_batch_dependencies(mut pending, commands) { memory.free(storage); return -22 }
	mut queued := false
	defer {
		if !queued {
			cancel_g13_pending(mut pending, -5)
			mut owner := unsafe { pending.manager }
			owner.release_g13_initial_events(mut pending.initial_events)
			assert katomic.load(&pending.callbacks_remaining) == 0
			unqueued_fence = pending.final_fence
			unqueued_failure = int(katomic.load(&pending.failure))
			memory.free(storage)
		}
	}
	mut gpu_manager := unsafe { manager }
	pending.initial_events = gpu_manager.capture_g13_initial_events(queue_resources, pending.initial_barriers) or { return -5 }
	for index := u32(0); index < pending.command_count; index++ {
		compute_ts := timestamps.addresses(index, 2)
		vertex_ts := timestamps.addresses(index, 0)
		fragment_ts := timestamps.addresses(index, 1)
		if commands[index].descriptor.cmd_type == ioctl.asahi_cmd_compute {
			pending.commands[index].compute_job = if timestamps.count == 0 {
				gpu_manager.prepare_g13_compute_job(queue_resources, vm, &commands[index].compute) or { return -12 }
			} else {
				gpu_manager.prepare_g13_compute_job_with_timestamps(queue_resources, vm,
					&commands[index].compute, compute_ts) or { return -12 }
			}
		} else {
			pending.commands[index].render_job = if timestamps.count == 0 {
				gpu_manager.prepare_g13_render_job(queue_resources, &commands[index].render) or { return -12 }
			} else {
				gpu_manager.prepare_g13_render_job_with_timestamps(queue_resources,
					&commands[index].render, vertex_ts, fragment_ts) or { return -12 }
			}
		}
	}
	if !install_g13_batch_barriers(mut pending) { return -5 }
	gpu_manager.release_g13_initial_events(mut pending.initial_events)
	pending.final_fence = syncobj.new_queue_fence(f.owner_key, timer.get_ns(), queue_resources.fence_context)
	for index := u32(0); index < pending.command_count; index++ {
		code := f.install_g13_batch_completion(mut pending, index, unsafe { &commands[index] }, result_object)
		if code != 0 { return code }
	}
	if !agxsubmission.install_output_syncs(output_syncs, pending.final_fence) { return -22 }
	katomic.inc(mut &f.inflight_by_vm[vm_id])
	if !register_g13_pending(mut gpu_manager, pending) {
		cancel_g13_pending(mut pending, -19)
		assert katomic.load(&pending.callbacks_remaining) == 0
		katomic.dec(mut &f.inflight_by_vm[vm_id])
		return -19
	}
	// Registration transferred the captured queue reference to the worker
	// node, which also owns the aggregate VM pin acquired above.
	timestamps_transferred = true
	queued = true
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

pub fn mmap_attributes_handle(_dev &drm.DrmDevice, handle voidptr, offset u64) u64 {
	f := lookup_file(handle) or { return 0 }
	mut file := unsafe { f }
	return file.mmap_attributes(offset)
}

pub fn retain_mmap_range_handle(_dev &drm.DrmDevice, handle voidptr, offset u64,
	length u64) bool {
	f := lookup_file(handle) or { return false }
	mut file := unsafe { f }
	return file.valid_mmap_range(offset, length)
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

pub fn gem_export_handler(dev &drm.DrmDevice, handle voidptr, object_handle u32) ?&gem.GemObject {
	mut file := get_or_create_file(handle, dev) or { return none }
	return file.get_object_ref(object_handle)
}

pub fn gem_import_handler(dev &drm.DrmDevice, handle voidptr, obj &gem.GemObject) ?u32 {
	mut file := get_or_create_file(handle, dev) or { return none }
	return file.import_object(obj)
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
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_params, size: u32(sizeof(ioctl.DrmAsahiGetParams)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_get_params_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_create, size: u32(sizeof(ioctl.DrmAsahiVmCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_vm_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_destroy, size: u32(sizeof(ioctl.DrmAsahiVmDestroy)), direction: drm.ioctl_write, handler: ioctl_vm_destroy_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_create, size: u32(sizeof(ioctl.DrmAsahiGemCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_gem_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_mmap_offset, size: u32(sizeof(ioctl.DrmAsahiGemMmapOffset)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_gem_mmap_offset_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind, size: u32(sizeof(ioctl.DrmAsahiGemBind)), direction: drm.ioctl_write, handler: ioctl_gem_bind_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_create, size: u32(sizeof(ioctl.DrmAsahiQueueCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_queue_create_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_destroy, size: u32(sizeof(ioctl.DrmAsahiQueueDestroy)), direction: drm.ioctl_write, handler: ioctl_queue_destroy_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_submit, size: u32(sizeof(ioctl.DrmAsahiSubmit)), direction: drm.ioctl_write, handler: ioctl_submit_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_time, size: u32(sizeof(ioctl.DrmAsahiGetTime)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_get_time_handler },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind_object, size: u32(sizeof(ioctl.DrmAsahiGemBindObject)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_gem_bind_object_handler },
	]
}
