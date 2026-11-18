@[has_globals]
module file

// Per-open DRM state for the Apple GPU. The public structures consumed here
// include the Mesa 25.0.5 ABI in drm.ioctl and the modern ABI in drm.asahi.
// Each open file selects one dialect before using overlapping ioctl numbers.
// G17 command submission
// stays fail-closed until its HAL300 work-command encoder is complete.

import drm
import drm.gem
import drm.ioctl
import drm.asahi
import drm.syncobj
import errno
import gpu.agx.bo as agxbo
import gpu.agx.hw
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
	handle_closed bool // GEM_CLOSE selected this binding for retirement
	addr     u64
	size     u64
	obj      &gem.GemObject = unsafe { nil }
	retiring bool // PTEs removed; backing retained until the device-state check succeeds
}

struct G17QueueOwnership {
	queue_id  u32
	resources &gpu.G17QueueResources = unsafe { nil }
}

struct G13QueueOwnership {
mut:
	queue_id  u32 // zero when backing has no logical queue or name reservation
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
	usc_base u64
	resources &gpu.G13QueueResources = unsafe { nil }
	retained bool
}

@[heap]
struct G13SubmitCompletion {
mut:
	result        &gem.GemObject = unsafe { nil }
	result_offset u64
	submission    &G13PendingSubmission = unsafe { nil }
	command_index u32
}

pub struct GpuFile {
pub:
	registration_manager &gpu.GpuManager = unsafe { nil }
pub mut:
	dev               &drm.DrmDevice = unsafe { nil }
	vms               []&mmu.UatContext // visible names are in ascending order
	queues            []&workqueue.WorkQueue
	mappings          []GpuMapping
	objects           agxbo.Table
	g17_queues        []G17QueueOwnership
	g13_queues        []G13QueueOwnership
	timestamp_objects []TimestampObject // sorted by name, including detached records
	next_queue_id     u32
	owner_process_id  u32
	owner_key         u64
	ioctl_abi         u32 // zero until the first driver request selects a dialect
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
	defer { file_map_lock.release() }
	if key in file_map {
		f := file_map[key] or { return none }
		return f
	}

	f := new_gpu_file(dev, key) or { return none }
	file_map[key] = f
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
	if dev == unsafe { nil } || owner_key == 0 {
		return none
	}
	manager := unsafe { &gpu.GpuManager(dev.driver_data) }
	if manager == unsafe { nil } || manager.uat == unsafe { nil } {
		return none
	}
	current := proc.current_thread()
	if current == unsafe { nil } || current.process == unsafe { nil }
		|| current.process.pid <= 0 {
		return none
	}
	mut f := &GpuFile{
		dev: unsafe { dev }
		registration_manager: manager
		objects: agxbo.new_table(manager.hw_config.gpu_gen == .g13)
		next_queue_id: 1
		owner_process_id: u32(current.process.pid)
		owner_key: owner_key
	}
	// Nothing slices these, so growing one can free its old buffer.
	f.vms.flags |= .noslices
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
	// Closing has removed the file's names. An unrelated queue or VM can
	// still defer close, but has no use for an uncaptured timestamp.
	for object in f.timestamp_objects {
		release_timestamp_object(f.registration_manager, object)
	}
	unsafe { f.timestamp_objects.free() }
	f.timestamp_objects = []TimestampObject{}
	// Captures can precede the aggregate VM pin, including after shutdown has
	// already released backing. Keep their metadata owner until the last pin.
	for ownership in f.g13_queues {
		if ownership.resources.has_file_references() { f.lock.release(); return false }
	}
	for vm in f.vms {
		if katomic.load(&vm.inflight) != 0 {
			// Completion callbacks still own this file. The worker retries its
			// close after their final reference is gone.
			f.lock.release()
			return false
		}
	}
	mut manager := unsafe { f.registration_manager }
	mut uat := unsafe { f.file_uat() }
	if (manager == unsafe { nil } && (f.g13_queues.len != 0 || f.g17_queues.len != 0))
		|| (uat == unsafe { nil } && f.vms.len != 0) {
		f.lock.release()
		return false
	}
	if manager != unsafe { nil } {
		for ownership in f.g13_queues {
			if !manager.release_g13_queue_resources(ownership.resources) {
				// Failed invalidation retains backing in the manager. Keep the
				// VM and every userspace mapping alive until cleanup succeeds or
				// stopped firmware makes the retained queue safe to release.
				f.lock.release()
				return false
			}
		}
	}
	// Retire the userspace mappings before destroying the VM. A device-state
	// refusal leaves their backing and VM alive for the next close retry.
	for index := f.mappings.len - 1; index >= 0; index-- {
		if !f.retire_mapping_locked(index) {
			f.lock.release()
			return false
		}
	}
	for mut q in f.queues { q.destroy() }
	for index := f.queues.len - 1; index >= 0; index-- {
		queue := f.queues[index]
		f.queues.delete(index)
		workqueue.free_workqueue(queue)
	}
	unsafe { f.queues.free() }
	f.queues = []&workqueue.WorkQueue{}
	if manager != unsafe { nil } {
		for ownership in f.g17_queues {
			manager.release_g17_queue_resources(ownership.resources)
		}
	}
	unsafe { f.g17_queues.free() }
	f.g17_queues = []G17QueueOwnership{}
	for index := f.g13_queues.len - 1; index >= 0; index-- {
		ownership := f.g13_queues[index]
		f.g13_queues.delete(index)
		gpu.free_g13_queue_record(ownership.resources)
	}
	unsafe { f.g13_queues.free() }
	f.g13_queues = []G13QueueOwnership{}
	for vm in f.vms {
		uat.destroy_context(vm)
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

fn (mut f GpuFile) admit_mmap_range(offset u64, length u64) int {
	f.lock.acquire()
	defer { f.lock.release() }
	return f.objects.admit_mmap_range(offset, length)
}

fn (mut f GpuFile) retain_mmap_range(offset u64, length u64) bool {
	f.lock.acquire()
	defer { f.lock.release() }
	return f.objects.retain_mmap_range(offset, length)
}

fn (mut f GpuFile) release_mmap_range(offset u64) {
	f.lock.acquire()
	defer { f.lock.release() }
	f.objects.release_mmap_range(offset)
}

// Caller holds file.lock and has excluded in-flight jobs from this VM. Unmap
// completes GPU TLBI before dropping the mapping's object reference. A retry
// after a device-state refusal starts from the already-invalidated PTEs.
fn (mut f GpuFile) retire_mapping_locked(index int) bool {
	mapping := f.mappings[index]
	ctx := f.find_owned_vm(mapping.vm_id) or { return false }
	if katomic.load(&ctx.inflight) != 0 || ctx.pgtable == unsafe { nil } { return false }
	if !mapping.retiring {
		mut pt := unsafe { ctx.pgtable }
		pt.unmap(mapping.addr, mapping.size)
		f.mappings[index].retiring = true
	}
	if !f.finish_file_mapping(true) {
		return false
	}
	gem.unref(mapping.obj)
	f.mappings.delete(index)
	return true
}

// GEM_CLOSE drops the selected GPU-VA bindings once the target VM is idle.
// An import of the same BO can create new bindings while older ones await
// retirement. CPU mmap authorization holds its own reference independently.
fn (mut f GpuFile) cleanup_closed_mappings_locked(vm &mmu.UatContext) bool {
	vm_id := vm.id
	if katomic.load(&vm.inflight) != 0 {
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
		if !vm.detached && !mapping.retiring && !mapping.handle_closed {
			continue
		}
		if !f.retire_mapping_locked(index) {
			success = false
		}
	}
	if success {
		mut owned := unsafe { vm }
		owned.closed_mappings_pending = false
	}
	return success
}

fn (mut f GpuFile) close_object_handle(handle u32, pad u32) int {
	f.lock.acquire()
	manager := f.registration_manager
	modern := f.ioctl_abi != legacy_ioctl_abi && manager != unsafe { nil } && manager.hw_config.gpu_gen == .g13
	if !modern && pad != 0 {
		f.lock.release()
		return -22
	}
	obj := f.objects.remove(handle) or {
		f.lock.release()
		return if modern { -22 } else { -2 }
	}
	for mut mapping in f.mappings {
		if voidptr(mapping.obj) != voidptr(obj) { continue }
		mapping.handle_closed = true
		ctx := f.find_owned_vm(mapping.vm_id) or { continue }
		mut vm := unsafe { ctx }
		vm.closed_mappings_pending = true
	}
	mut success := true
	for vm in f.vms {
		if !f.cleanup_closed_mappings_locked(vm) {
			success = false
		}
	}
	f.lock.release()
	gem.unref(obj)
	// The modern close result describes handle removal. The VM worker owns
	// retries if an invalidation could not yet be acknowledged.
	return if success || modern { 0 } else { -5 }
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
	mut retired := true
	for i := original_count - 1; i >= 0; i-- {
		mapping := f.mappings[i]
		if mapping.vm_id != vm_id || !ranges_overlap(mapping.addr, mapping.size, addr, size) { continue }
		if !mapping.retiring {
			mapping_end := mapping.addr + mapping.size
			cut_start := if mapping.addr > addr { mapping.addr } else { addr }
			cut_end := if mapping_end < end { mapping_end } else { end }
			if mapping.addr < cut_start {
				gem.ref_obj(mapping.obj)
				f.mappings << GpuMapping{ vm_id: mapping.vm_id, handle_closed: mapping.handle_closed,
					addr: mapping.addr, size: cut_start - mapping.addr, obj: mapping.obj }
			}
			if cut_end < mapping_end {
				gem.ref_obj(mapping.obj)
				f.mappings << GpuMapping{ vm_id: mapping.vm_id, handle_closed: mapping.handle_closed,
					addr: cut_end, size: mapping_end - cut_end, obj: mapping.obj }
			}
			f.mappings[i].addr = cut_start
			f.mappings[i].size = cut_end - cut_start
		}
		// An earlier retirement has already unmapped its recorded range.
		if !f.retire_mapping_locked(i) { retired = false }
	}
	return if retired { 0 } else { -5 }
}

// Reserve a nonzero per-open queue ID. Modern G13 returns freed names to
// next_queue_id. Legacy G13 also checks ID reservations on retained backing.
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

// Return the lowest free visible name and its insertion index. Detached
// mappings keep their place in the array but own only their VA and backing.
fn (mut f GpuFile) allocate_timestamp_id_locked() (u32, int) {
	mut candidate := u32(1)
	for index, object in f.timestamp_objects {
		if object.id > candidate { return candidate, index }
		if object.id == candidate && !object.detached {
			if candidate == ~u32(0) { return 0, index }
			candidate++
		}
	}
	return candidate, f.timestamp_objects.len
}

// Captures keep scalar VAs, so all timestamp records can move under file.lock.
fn (mut f GpuFile) reserve_timestamp_entry_locked() bool {
	if f.timestamp_objects.len < f.timestamp_objects.cap { return true }
	if f.timestamp_objects.len == 0x7fff_ffff { return false }
	capacity := if f.timestamp_objects.cap == 0 { 8 } else if f.timestamp_objects.cap <= 0x3fff_ffff {
		f.timestamp_objects.cap * 2
	} else {
		0x7fff_ffff
	}
	storage := memory.malloc_packed_fallible(u64(capacity) * sizeof(TimestampObject)) @[freed]
	if storage == unsafe { nil } { return false }
	mut replacement := []TimestampObject{}
	unsafe {
		replacement.data = storage
		replacement.len = f.timestamp_objects.len
		replacement.cap = capacity
		replacement.flags = .noslices
		if f.timestamp_objects.len != 0 {
			C.memcpy(storage, f.timestamp_objects.data, u64(f.timestamp_objects.len) * sizeof(TimestampObject))
		}
		mut old := f.timestamp_objects
		f.timestamp_objects = replacement
		old.free()
	}
	return true
}

// Userspace names belong to the file. Callers hold file.lock.
fn (f &GpuFile) find_vm(vm_id u32) ?&mmu.UatContext {
	if vm_id == 0 { return none }
	for vm in f.vms {
		if vm.vm_id == vm_id && !vm.detached {
			return unsafe { vm }
		}
	}
	return none
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

// Retiring records still have an owner even after their PTEs are gone.
fn (f &GpuFile) has_mapping_overlap_locked(vm_id u32, addr u64, size u64) bool {
	for mapping in f.mappings {
		if mapping.vm_id == vm_id && ranges_overlap(mapping.addr, mapping.size, addr, size) {
			return true
		}
	}
	return false
}

// GPU-only GEM mappings are coherent. Page-table edits complete the
// translation invalidation for the published root before this state check.
fn (f &GpuFile) finish_file_mapping(unmapped bool) bool {
	mut gpu_manager := unsafe { f.registration_manager }
	if gpu_manager == unsafe { nil } { return false }
	return gpu_manager.finish_g13_file_mapping(unmapped)
}

fn (f &GpuFile) file_uat() &mmu.UatManager {
	manager := f.registration_manager
	if manager == unsafe { nil } { return unsafe { nil } }
	// G13 clears its resident slots before replacement. Other backends
	// still need the current UAT to own their firmware-visible slots.
	if manager.hw_config.gpu_gen != .g13 && voidptr(manager.uat) != voidptr(uat_mgr) {
		return unsafe { nil }
	}
	return manager.uat
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
	mut features := (u64(cfg.gpu_feat_compat) & ~ioctl.asahi_feat_soft_faults) | ioctl.asahi_feat_gettime
	if cfg.chip_id == 0x8103 && cfg.g13_fault_control == hw.g13_soft_fault_control {
		features |= ioctl.asahi_feat_soft_faults
	}
	mut params := ioctl.DrmAsahiParamsGlobal{
		unstable_uabi_version: ioctl.drm_asahi_unstable_uabi_version
		feat_compat: features
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
	manager := f.registration_manager
	if manager == unsafe { nil } { return -19 }
	mut gpu_manager := unsafe { manager }
	if !gpu_manager.can_query_global_params() { return -19 }
	params := make_global_params(manager)
	return agxparams.copy_global(request, unsafe { &params })
}

// V can move the pointer array without moving the VMs captured by jobs.
fn (mut f GpuFile) reserve_vm_entry_locked() bool {
	if f.vms.len < f.vms.cap { return true }
	if f.vms.len == 0x7fff_ffff { return false }
	capacity := if f.vms.cap == 0 { 8 } else if f.vms.cap <= 0x3fff_ffff {
		f.vms.cap * 2
	} else {
		0x7fff_ffff
	}
	storage := memory.malloc_packed_fallible(u64(capacity) * sizeof(&mmu.UatContext)) @[freed]
	if storage == unsafe { nil } { return false }
	mut replacement := []&mmu.UatContext{}
	unsafe {
		replacement.data = storage
		replacement.len = f.vms.len
		replacement.cap = capacity
		replacement.flags = .noslices
		if f.vms.len != 0 {
			C.memcpy(storage, f.vms.data, u64(f.vms.len) * sizeof(&mmu.UatContext))
		}
		mut old := f.vms
		f.vms = replacement
		old.free()
	}
	return true
}

pub fn (mut f GpuFile) ioctl_vm_create(data &ioctl.DrmAsahiVmCreate) int {
	mut request := unsafe { data }
	mgr := f.file_uat()
	if mgr == unsafe { nil } {
		return -19
	}
	address_limit := u64(1) << mgr.ias
	if request.extensions != 0 || request.pad != 0
		|| !agxvm.valid_window(request.kernel_start, request.kernel_end)
		|| request.kernel_end > address_limit {
		return -22
	}
	f.lock.acquire()
	defer { f.lock.release() }
	mut gpu_manager := unsafe { f.registration_manager }
	gpu_manager.lock.acquire()
	defer { gpu_manager.lock.release() }
	if gpu_manager.state == .stopped || gpu_manager.state == .error { return -19 }
	mut vm_id := u32(1)
	mut insert_at := f.vms.len
	for index, vm in f.vms {
		if vm.detached { continue }
		if vm.vm_id > vm_id { insert_at = index; break }
		if vm_id == ~u32(0) { return -12 }
		vm_id++
	}
	// A hidden owner may still use the public name's old internal key.
	mut owner_id := vm_id
	for f.find_owned_vm(owner_id) != none {
		owner_id = if owner_id == ~u32(0) { u32(1) } else { owner_id + 1 }
	}
	if !f.reserve_vm_entry_locked() { return -12 }
	mut m := unsafe { mgr }
	mut ctx := m.create_context(request.kernel_start, request.kernel_end) or { return -12 }
	ctx.id = owner_id
	ctx.vm_id = vm_id
	if m.handoff_abi != .v12_3 && m.bind_context(ctx) == 0 {
		m.destroy_context(ctx)
		return -12
	}
	f.vms << ctx
	for index := f.vms.len - 1; index > insert_at; index-- {
		f.vms[index] = f.vms[index - 1]
	}
	f.vms[insert_at] = ctx
	request.vm_id = vm_id
	return 0
}

pub fn (mut f GpuFile) ioctl_vm_destroy(data &ioctl.DrmAsahiVmDestroy) int {
	request := unsafe { data }
	if request.extensions != 0 || request.pad != 0 {
		return -22
	}
	if request.vm_id == 0 { return -2 }
	f.lock.acquire()
	defer { f.lock.release() }
	found := f.find_vm(request.vm_id) or { return -2 }
	mut vm := unsafe { found }
	// Match Asahi's namespace removal independently of retained queue/job
	// owners. Existing queues keep their VM; new VM-name lookups fail.
	vm.detached = true
	f.reap_detached_vms_locked()
	return 0
}

// Caller holds file.lock. Retry GEM_CLOSE mappings on idle visible VMs as well
// as bindings on detached VMs. Only detached VMs can lose their context, and
// queue owners (including failed-create quarantine) retain driver mappings.
fn (mut f GpuFile) reap_detached_vms_locked() {
	mut uat := unsafe { f.file_uat() }
	if uat == unsafe { nil } { return }
	for index := f.vms.len - 1; index >= 0; index-- {
		vm := f.vms[index]
		vm_id := vm.id
		if (!vm.detached && !vm.closed_mappings_pending) || katomic.load(&vm.inflight) != 0 { continue }
		if !f.cleanup_closed_mappings_locked(vm) { continue }
		if !vm.detached { continue }
		mut retained := false
		for queue in f.queues {
			if queue.vm_id == vm_id { retained = true; break }
		}
		for ownership in f.g13_queues {
			if ownership.vm_id == vm_id { retained = true; break }
		}
		if retained { continue }
		uat.destroy_context(vm)
		f.vms.delete(index)
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
	if !f.objects.reserve_handle_entry() { return -12 }
	obj := gem.create_aligned_with_cache(request.size, pgtable.uat_pgsz, private_identity,
		request.flags & ioctl.asahi_gem_writeback != 0, f.objects.uses_local_handles()) or { return -12 }
	request.handle = f.objects.add_created(obj)
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
			vm_slot := ctx.id
			if !f.cleanup_closed_mappings_locked(ctx) {
				gem.unref(obj)
				return -5
			}
			replacing := f.has_mapping_overlap_locked(vm_slot, request.addr, request.range)
			if replacing && katomic.load(&ctx.inflight) != 0 {
				gem.unref(obj)
				return -16 // EBUSY: replacement must not remove pages used by jobs.
			}
			fragments := f.mapping_survivor_count_locked(vm_slot, request.addr, request.range)
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
				retired := f.unbind_range_locked(vm_slot, request.addr, request.range)
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
				vm_id: vm_slot
				addr: request.addr
				size: request.range
				obj: obj
			}
			if !f.finish_file_mapping(false) {
				// Roll back the PTEs and retain backing until retirement can
				// confirm that the device is running or has stopped.
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
			if katomic.load(&ctx.inflight) != 0 {
				// A hole needs no PTE changes or owner retirement.
				return if f.has_mapping_overlap_locked(ctx.id, request.addr, request.range) { -16 } else { 0 }
			}
			return f.unbind_range_locked(ctx.id, request.addr, request.range)
		}
		ioctl.asahi_bind_op_unbind_all {
			ctx := f.find_vm(request.vm_id) or { return -2 }
			if ctx.pgtable == unsafe { nil }
				|| !agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end) { return -22 }
			obj := f.objects.get_ref(request.handle) or { return -2 }
			busy := katomic.load(&ctx.inflight) != 0
			mut retired := true
			for i := f.mappings.len - 1; i >= 0; i-- {
				mapping := f.mappings[i]
				if mapping.vm_id == ctx.id && voidptr(mapping.obj) == voidptr(obj) {
					if busy {
						gem.unref(obj)
						return -16
					}
					if !f.retire_mapping_locked(i) {
						retired = false
					}
				}
			}
			gem.unref(obj)
			return if retired { 0 } else { -5 }
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
			mut gpu_manager := unsafe { f.registration_manager }
			if gpu_manager == unsafe { nil } {
				gem.unref(obj)
				return -19
			}
			map_code, va := gpu_manager.map_g13_timestamp_buffer(obj.phys_addr + request.offset, request.range)
			if map_code != 0 {
				gem.unref(obj)
				return map_code
			}
			f.lock.acquire()
			id, slot := f.allocate_timestamp_id_locked()
			mut publish_code := if id == 0 { -16 } else if !f.reserve_timestamp_entry_locked() { -12 } else { 0 }
			if publish_code == 0 {
				// Storage is already reserved. Hold the shutdown lock through
				// publication, in the usual file-before-manager lock order.
				gpu_manager.lock.acquire()
				if gpu_manager.state == .stopped {
					publish_code = -19
				} else {
					object := TimestampObject{
						id: id
						va: va
						size: request.range
						obj: obj
					}
					f.timestamp_objects << object
					for index := f.timestamp_objects.len - 1; index > slot; index-- {
						f.timestamp_objects[index] = f.timestamp_objects[index - 1]
					}
					f.timestamp_objects[slot] = object
					request.object_handle = id
				}
				gpu_manager.lock.release()
			}
			f.lock.release()
			if publish_code != 0 {
				gpu_manager.unmap_g13_timestamp_buffer(va, request.range)
				gem.unref(obj)
			}
			return publish_code
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
			manager := f.registration_manager
			f.timestamp_objects.delete(found_index)
			f.lock.release()
			release_timestamp_object(manager, found)
			return 0
		}
		else {
			return -22
		}
	}
}

pub fn (mut f GpuFile) ioctl_queue_create(data &ioctl.DrmAsahiQueueCreate) int {
	return f.create_queue(data, 0, [u64(0), 0]!, false)
}

// Install immutable queue input before publishing its name under file.lock.
fn (mut f GpuFile) create_queue(data &ioctl.DrmAsahiQueueCreate, usc_base u64, render_scs_layout [2]u64, modern bool) int {
	mut request := unsafe { data }
	known_caps := ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_blit | ioctl.asahi_queue_cap_compute
	if request.extensions != 0 || request.flags != 0 || request.pad != 0 || request.priority > ioctl.asahi_priority_realtime
		|| request.queue_caps == 0 || request.queue_caps & ~known_caps != 0 {
		return -22
	}
	manager := f.registration_manager
	if manager == unsafe { nil } { return -19 }
	// Only G13's modern queue path is qualified here. Other backends retain
	// their previous refusal of nonzero modern render scratch layouts.
	if manager.hw_config.gpu_gen != .g13 && render_scs_layout != [u64(0), 0]! { return -22 }
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
	reuse_name := modern && manager.hw_config.gpu_gen == .g13
	retained_id := if reuse_name { u32(0) } else { id }
	mut published := false
	defer { if reuse_name && !published { f.next_queue_id = id } }
	wq := workqueue.new_workqueue(id, vm.id, firmware_priority, request.queue_caps) or {
		return -12
	}
	mut logical := unsafe { wq }
	logical.usc_base = usc_base
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
			workqueue.free_workqueue(queue)
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
		mut retained := &gpu.G13QueueResources(unsafe { nil })
		g13_resources = gpu_manager.create_g13_queue_resources(id, channel_mask, firmware_priority, vm, unsafe { &retained }) or {
			// Adopt the record even if shutdown already released its backing.
			if retained != unsafe { nil } {
				f.g13_queues << G13QueueOwnership{ queue_id: retained_id, vm_id: vm.id, resources: retained }
			}
			mut queue := unsafe { wq }
			queue.destroy()
			workqueue.free_workqueue(queue)
			return -12
		}
	}
	// Asahi reserves render scratch after constructing the queue. G13's
	// default implementation accepts only zero layouts, so constructor/VM
	// errors must win over this rejection. No logical name is published.
	if render_scs_layout != [u64(0), 0]! {
		mut gpu_manager := unsafe { manager }
		released := gpu_manager.release_g13_queue_resources(g13_resources)
		if !released {
			// Failed invalidation keeps the graph and VM alive through the
			// existing orphan-owner retry path, independently of this name.
			f.g13_queues << G13QueueOwnership{ queue_id: retained_id, vm_id: vm.id, resources: g13_resources }
		}
		logical.destroy()
		workqueue.free_workqueue(logical)
		if released { gpu.free_g13_queue_record(g13_resources) }
		return -22
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
			vm_id: vm.id
			resources: g13_resources
		}
	}
	request.queue_id = id
	published = true
	return 0
}

// Caller holds file.lock. Captured ioctls and accepted submission nodes retain
// their own queue through staging, callbacks and final aggregate retirement.
// Unrelated work in the same VM does not postpone this queue's release.
fn (mut f GpuFile) reap_detached_g13_queues_locked() {
	mut gpu_manager := unsafe { f.registration_manager }
	if gpu_manager == unsafe { nil } { return }
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
		workqueue.free_workqueue(q)
		gpu.free_g13_queue_record(ownership.resources)
	}
}

// Failed construction or modern queue destruction may leave backing without
// a logical queue. Retry that backing independently of the file/VM name.
// Caller holds file.lock; physical release retains its manager/job guards.
fn (mut f GpuFile) reap_orphaned_g13_queues_locked() {
	mut gpu_manager := unsafe { f.registration_manager }
	if gpu_manager == unsafe { nil } { return }
	for index := f.g13_queues.len - 1; index >= 0; index-- {
		ownership := f.g13_queues[index]
		mut named := false
		for queue in f.queues {
			if queue.id == ownership.queue_id { named = true; break }
		}
		if named || ownership.resources.has_file_references() { continue }
		if !gpu_manager.release_g13_queue_resources(ownership.resources) { continue }
		f.g13_queues.delete(index)
		gpu.free_g13_queue_record(ownership.resources)
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
		owned.reap_detached_vms_locked()
		owned.lock.release()
	}
	file_map_lock.release()
}

pub fn (mut f GpuFile) ioctl_queue_destroy(data &ioctl.DrmAsahiQueueDestroy) int {
	return f.destroy_queue(data, false)
}

fn (mut f GpuFile) destroy_queue(data &ioctl.DrmAsahiQueueDestroy, modern bool) int {
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
				if modern {
					// SUBMIT captures scalars and the physical owner under file.lock.
					// The name and logical record can go while that owner is pinned.
					q.destroy()
					record := unsafe { q }
					f.queues.delete(i)
					f.g13_queues[g13_index].queue_id = 0
					if f.next_queue_id == 0 || request.queue_id < f.next_queue_id {
						f.next_queue_id = request.queue_id
					}
					workqueue.free_workqueue(record)
					f.reap_orphaned_g13_queues_locked()
				} else {
					q.detached = true
					f.reap_detached_g13_queues_locked()
				}
				f.reap_detached_vms_locked()
				f.lock.release()
				return 0
			}
			mut gpu_manager := unsafe { f.registration_manager }
			if gpu_manager == unsafe { nil } {
				f.lock.release()
				return -19
			}
			if resources != unsafe { nil } {
				gpu_manager.release_g17_queue_resources(resources)
			}
			q.destroy()
			record := unsafe { q }
			f.queues.delete(i)
			if g17_index >= 0 {
				f.g17_queues.delete(g17_index)
			}
			if g13_index >= 0 {
				f.g13_queues.delete(g13_index)
			}
			workqueue.free_workqueue(record)
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
		katomic.dec(mut &submission.vm.inflight)
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

// Caller holds manager.lock. The aggregate callback retains state and the
// pending node until both stages finish; publish only, leaving file-lock work
// to the worker. No further timestamp access occurs after this stage's stamp.
fn g13_render_stage_completed(pipe u32, data voidptr) {
	if data == unsafe { nil } || pipe >= 2 { return }
	state := unsafe { &G13SubmitCompletion(data) }
	if state.submission == unsafe { nil } { return }
	katomic.store(mut &state.submission.commands[state.command_index].render_stage_finished[pipe], true)
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
fn install_g13_batch_completion(mut pending G13PendingSubmission,
	index u32, command &agxsubmission.Command,
	result_object &gem.GemObject) int {
	mut manager := unsafe { pending.manager }
	mut entry := &pending.commands[index]
	is_compute := command.descriptor.cmd_type == ioctl.asahi_cmd_compute
	if command.descriptor.result_size != 0 { gem.ref_obj(result_object) }
	mut completion := &G13SubmitCompletion{
		result: if command.descriptor.result_size != 0 { unsafe { result_object } } else { unsafe { nil } }
		result_offset: command.descriptor.result_offset
		submission: unsafe { &pending }
		command_index: index
	} @[freed]
	katomic.inc(mut &pending.callbacks_remaining)
	katomic.inc(mut &pending.vm.inflight)
	installed := if is_compute {
		manager.set_g13_compute_completion(entry.compute_job, g13_compute_completed, voidptr(completion))
	} else {
		manager.set_g13_render_completion(entry.render_job, g13_render_completed, g13_render_stage_completed, voidptr(completion))
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
			if ownership.queue_id == queue_id && ownership.resources != unsafe { nil } && queue.vm_id != 0 {
				mut resources := unsafe { ownership.resources }
				resources.retain_file_reference()
				return G13SubmissionQueue{vm_id: queue.vm_id, caps: queue.caps, usc_base: queue.usc_base, resources: resources, retained: true}
			}
		}
		// Preserve backend/invalid-internal-state validation after staging for
		// non-G13 or malformed logical queues, without borrowing any resource.
		return G13SubmissionQueue{vm_id: queue.vm_id, caps: queue.caps, usc_base: queue.usc_base}
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
	sync_result, input_syncs := agxsubmission.stage_g13_sync_array(f.owner_key, request.in_syncs, request.in_sync_count, true)
	if sync_result != 0 { return sync_result }
	output_result, output_syncs := agxsubmission.stage_g13_sync_array(f.owner_key, request.out_syncs, request.out_sync_count, false)
	if output_result != 0 { return output_result }
	defer { agxsubmission.release_sync_array(output_syncs) }
	code := f.submit_g13_staged(captured, commands, unsafe { &input_syncs }, unsafe { &output_syncs }, request.result_handle, 0)
	transferred = code == 0
	return code
}

// Both copied input formats share preparation and pending ownership. The
// caller retains captured on failure; successful registration transfers it.
fn (mut f GpuFile) submit_g13_staged(captured G13SubmissionQueue,
	commands []agxsubmission.Command, input_syncs &agxsubmission.SyncArray,
	output_syncs &agxsubmission.SyncArray, result_handle u32, attachment_initial_mask u32) int {
	if commands.len == 0 || commands.len > int(max_g13_submission_commands) { return -22 }
	manager := f.registration_manager
	if manager == unsafe { nil } { return -19 }
	mut gpu_manager := unsafe { manager }
	status := gpu_manager.g13_submission_status()
	if status != 0 { return status }
	dependency_code, pending_inputs := agxsubmission.copy_job_dependencies(input_syncs)
	if dependency_code != 0 { return dependency_code }
	mut dependencies_transferred := false
	defer { if !dependencies_transferred { agxsubmission.release_sync_array(pending_inputs) } }
	// Captures acquire file.lock independently, before backend preparation.
	// This outer defer runs after the file-lock defer and pending cancellation.
	timestamp_code, captured_timestamps := f.new_g13_submission_timestamps(commands, manager)
	if timestamp_code != 0 { return timestamp_code }
	timestamps := captured_timestamps
	mut timestamps_transferred := false
	defer { if !timestamps_transferred { f.release_g13_submission_timestamps(timestamps) } }
	f.lock.acquire()
	mut result_object := &gem.GemObject(unsafe { nil })
	defer {
		f.lock.release()
		if result_object != unsafe { nil } { gem.unref(result_object) }
	}
	vm_id := captured.vm_id
	queue_caps := captured.caps
	if vm_id == 0 { return -22 }
	mut queue_resources := unsafe { captured.resources }
	if captured.retained {
		for !queue_resources.submission_gate.try_enter() {
			generation := queue_resources.submission_gate.generation()
			f.lock.release()
			resumed := queue_resources.submission_gate.wait(generation)
			f.lock.acquire()
			if !resumed { return -int(errno.erestartsys) }
		}
	}
	defer {
		// Drop the gate under file.lock, before the queue reaper can reclaim
		// metadata whose captured reference was transferred to the worker.
		if captured.retained { queue_resources.submission_gate.leave() }
	}
	vm := f.find_owned_vm(vm_id) or { return -22 }
	// Finish retained mapping retirements before publishing work. This
	// also retries an earlier GEM_CLOSE once VM pins end.
	if !f.cleanup_closed_mappings_locked(vm) { return -5 }
	if !captured.retained { return -22 }
	mut initial_mask := attachment_initial_mask
	for command in commands {
		descriptor := command.descriptor
		if (descriptor.cmd_type == ioctl.asahi_cmd_compute && queue_caps & ioctl.asahi_queue_cap_compute == 0)
			|| (descriptor.cmd_type == ioctl.asahi_cmd_render && queue_caps & ioctl.asahi_queue_cap_render == 0) { return -22 }
		if descriptor.barriers[0] == 0 { initial_mask |= u32(1) }
		if descriptor.barriers[1] == 0 { initial_mask |= u32(2) }
		if descriptor.result_size != 0 {
			if result_handle == 0 { return -22 }
			if result_object == unsafe { nil } {
				result_object = f.objects.find(result_handle) or { return -22 }
				// The slot wait can overlap GEM_CLOSE and handle reuse.
				gem.ref_obj(result_object)
			}
			if descriptor.result_offset > result_object.size
				|| descriptor.result_size > result_object.size - descriptor.result_offset { return -22 }
		} else if descriptor.result_offset != 0 { return -22 }
	}
	// Use the caller's input count before reduction, as the Asahi queue does.
	early_operation := input_syncs.count != 0
	if early_operation {
		operation_status := gpu_manager.start_g13_submission_operation()
		if operation_status != 0 { return operation_status }
	}
	mut queued := false
	defer { if early_operation && !queued { gpu_manager.finish_g13_submission_operation() } }
	// Fix the prior event targets while this ioctl owns the queue gate.
	// The snapshot pins survive either admission wait.
	initial_events := gpu_manager.capture_g13_initial_events(queue_resources, initial_mask) or {
		capture_status := gpu_manager.g13_submission_status()
		return if capture_status != 0 { capture_status } else { -5 }
	}
	mut initial_events_released := false
	defer { if !initial_events_released { gpu_manager.release_g13_initial_events(initial_events) } }
	// An attachment record has no hardware queue on which to put a barrier.
	// Index zero is allowed only when its prior target was absent.
	for pipe, prior in initial_events.values {
		if prior.valid && attachment_initial_mask & (u32(1) << pipe) != 0 { return -22 }
	}
	slot := f.bind_g13_submission_vm_locked(mut gpu_manager, vm)
	if slot < 0 { return slot }
	mut uat := unsafe { gpu_manager.uat }
	defer { uat.release_g13_slot(vm, u32(slot)) }
	storage := memory.malloc_packed_fallible(sizeof(G13PendingSubmission)) @[freed]
	if storage == unsafe { nil } { return -12 }
	mut pending := unsafe { &G13PendingSubmission(storage) }
	unsafe { *pending = G13PendingSubmission{
		file: &f
		vm: vm
		queue: queue_resources
		manager: manager
		dependencies: pending_inputs
		operation_active: early_operation
		command_count: u32(commands.len)
		timestamps: timestamps
	} }
	if !resolve_g13_batch_dependencies(mut pending, commands) { memory.free(storage); return -22 }
	defer {
		if !queued {
			cancel_g13_pending(mut pending, -5)
			assert katomic.load(&pending.callbacks_remaining) == 0
			memory.free(storage)
		}
	}
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
	if !install_g13_batch_barriers(mut pending, initial_events) { return -5 }
	gpu_manager.release_g13_initial_events(initial_events)
	initial_events_released = true
	for index := u32(0); index < pending.command_count; index++ {
		code := install_g13_batch_completion(mut pending, index, unsafe { &commands[index] }, result_object)
		if code != 0 { return code }
	}
	katomic.inc(mut &pending.vm.inflight)
	fence := register_g13_pending(mut gpu_manager, pending) or {
		cancel_g13_pending(mut pending, -19)
		assert katomic.load(&pending.callbacks_remaining) == 0
		katomic.dec(mut &pending.vm.inflight)
		return -19
	}
	// Registration transferred the captured queue reference to the worker
	// node, which also owns the aggregate VM pin acquired above.
	timestamps_transferred = true
	dependencies_transferred = true
	queued = true
	// Both native ABIs stage referenced outputs and reserve every timeline
	// node before preparation. Publication consumes those reservations.
	installed := agxsubmission.install_output_syncs(output_syncs, fence)
	assert installed
	return 0
}

// Caller holds file.lock and a captured queue reference, which keeps the VM
// live across both waits. Return with file.lock held and transfer a slot lease
// on success. Jobs and queue teardown can retire while binders sleep.
fn (mut f GpuFile) bind_g13_submission_vm_locked(mut manager gpu.GpuManager,
	context &mmu.UatContext) int {
	mut uat := unsafe { manager.uat }
	if uat == unsafe { nil } { return -19 }
	mut vm := unsafe { context }
	for !vm.binding_gate.try_enter() {
		generation := vm.binding_gate.generation()
		f.lock.release()
		resumed := vm.binding_gate.wait(generation)
		f.lock.acquire()
		if !resumed { return -int(errno.erestartsys) }
		if !f.cleanup_closed_mappings_locked(vm) { return -5 }
	}
	defer { vm.binding_gate.leave() }
	for {
		generation := uat.g13_slot_generation()
		slot := manager.try_hold_g13_submission_slot(vm)
		if slot != 0 { return slot }
		f.lock.release()
		resumed := uat.wait_g13_slot(generation)
		f.lock.acquire()
		if !resumed { return -int(errno.erestartsys) }
		if !f.cleanup_closed_mappings_locked(vm) { return -5 }
	}
	return -19
}

fn dispatch(handle voidptr, dev &drm.DrmDevice) ?&GpuFile {
	return dispatch_abi(handle, dev, legacy_ioctl_abi)
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

pub fn close_gem_request(dev &drm.DrmDevice, handle voidptr, request &ioctl.DrmGemClose) int {
	f := lookup_file(handle) or {
		manager := unsafe { &gpu.GpuManager(dev.driver_data) }
		return if request.pad != 0 || (manager != unsafe { nil } && manager.hw_config.gpu_gen == .g13) {
			-22
		} else { -2 }
	}
	mut file := unsafe { f }
	return file.close_object_handle(request.handle, request.pad)
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
	return file.retain_mmap_range(offset, length)
}

pub fn admit_mmap_range_handle(_dev &drm.DrmDevice, handle voidptr, offset u64,
	length u64) int {
	f := lookup_file(handle) or { return -22 }
	mut file := unsafe { f }
	return file.admit_mmap_range(offset, length)
}

pub fn release_mmap_range_handle(_dev &drm.DrmDevice, handle voidptr, offset u64, _length u64) {
	f := lookup_file(handle) or { return }
	mut file := unsafe { f }
	file.release_mmap_range(offset)
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
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_params, size: u32(sizeof(ioctl.DrmAsahiGetParams)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_get_params_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_create, size: u32(sizeof(ioctl.DrmAsahiVmCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_vm_create_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_vm_destroy, size: u32(sizeof(ioctl.DrmAsahiVmDestroy)), direction: drm.ioctl_write, handler: ioctl_vm_destroy_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_create, size: u32(sizeof(ioctl.DrmAsahiGemCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_gem_create_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_mmap_offset, size: u32(sizeof(ioctl.DrmAsahiGemMmapOffset)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_gem_mmap_offset_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind, size: u32(sizeof(ioctl.DrmAsahiGemBind)), direction: drm.ioctl_write, handler: ioctl_gem_bind_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_create, size: u32(sizeof(ioctl.DrmAsahiQueueCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_queue_create_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_queue_destroy, size: u32(sizeof(ioctl.DrmAsahiQueueDestroy)), direction: drm.ioctl_write, handler: ioctl_queue_destroy_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_submit, size: u32(sizeof(ioctl.DrmAsahiSubmit)), direction: drm.ioctl_write, handler: ioctl_submit_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_get_time, size: u32(sizeof(ioctl.DrmAsahiGetTime)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_get_time_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: ioctl.drm_asahi_gem_bind_object, size: u32(sizeof(ioctl.DrmAsahiGemBindObject)), direction: drm.ioctl_write | drm.ioctl_read, handler: ioctl_gem_bind_object_handler, abi: legacy_ioctl_abi },
		drm.DrmIoctl{ cmd: asahi.get_params, size: u32(sizeof(asahi.GetParams)), direction: drm.ioctl_write, handler: modern_get_params_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.get_time, size: u32(sizeof(asahi.GetTime)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_get_time_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.vm_create, size: u32(sizeof(asahi.VmCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_vm_create_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.vm_destroy, size: u32(sizeof(asahi.VmDestroy)), direction: drm.ioctl_write, handler: modern_vm_destroy_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.vm_bind, size: u32(sizeof(asahi.VmBind)), direction: drm.ioctl_write, handler: modern_vm_bind_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.gem_create, size: u32(sizeof(asahi.GemCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_gem_create_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.gem_mmap_offset, size: u32(sizeof(asahi.GemMmapOffset)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_gem_mmap_offset_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.gem_bind_object, size: u32(sizeof(asahi.GemBindObject)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_gem_bind_object_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.queue_create, size: u32(sizeof(asahi.QueueCreate)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_queue_create_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.queue_destroy, size: u32(sizeof(asahi.QueueDestroy)), direction: drm.ioctl_write, handler: modern_queue_destroy_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.submit, size: u32(sizeof(asahi.Submit)), direction: drm.ioctl_write, handler: modern_submit_handler, abi: modern_ioctl_abi, extensible: true },
		drm.DrmIoctl{ cmd: asahi.gem_madvise, size: u32(sizeof(asahi.GemMadvise)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_gem_madvise_handler, abi: modern_ioctl_abi, extensible: true },
	]
}
