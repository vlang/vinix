@[has_globals]
module file

import drm
import drm.gem
import gpu.agx.bo
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.workqueue
import klock

struct G13QueueOwnership {
mut:
	queue_id u32
	vm_id u32
	resources &gpu.G13QueueResources
}

struct G17QueueOwnership {
	queue_id u32
	resources &gpu.G17QueueResources
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

struct Objects {
mut:
	table bo.Table
}

__global table_releases = 0
__global object_ref_lookups = 0

fn (mut objects Objects) release_all() { objects.table.release_all(); table_releases++ }
fn (objects &Objects) get_ref(handle u32) ?&gem.GemObject { object_ref_lookups++; return objects.table.get_ref(handle) }
fn (mut objects Objects) remove(handle u32) ?&gem.GemObject { return objects.table.remove(handle) }
fn (mut objects Objects) reserve_handle_entry() bool { return objects.table.reserve_handle_entry() }
fn (mut objects Objects) add_created(object &gem.GemObject) { objects.table.add_created(object) }
fn (objects &Objects) mmap_attributes(offset u64) u64 { return objects.table.mmap_attributes(offset) }
fn (objects &Objects) valid_mmap_range(offset u64, length u64) bool { return objects.table.valid_mmap_range(offset, length) }

struct GpuFile {
mut:
	lock              klock.Lock
	dev               &drm.DrmDevice = unsafe { nil }
	owner_key         u64
	queues            []&workqueue.WorkQueue
	g13_queues        []G13QueueOwnership
	g17_queues        []G17QueueOwnership
	timestamp_objects []TimestampObject
	registration_manager &gpu.GpuManager = gpu.registration_manager()
	vms               []&mmu.UatContext
	mappings          []GpuMapping
	objects           Objects
	next_queue_id u32 = 1
	owner_process_id u32 = 7
	ioctl_abi u32
	closing_next      &GpuFile = unsafe { nil }
	closing_queued    bool
}

__global file_map_lock klock.Lock
__global file_map = map[u64]&GpuFile{}
__global uat_mgr &mmu.UatManager = unsafe { nil }
__global stopping_file &GpuFile = unsafe { nil }
__global late_close_vm &mmu.UatContext = unsafe { nil }

fn stop_during_registration() {
	mut vm := unsafe { stopping_file.vms[0] }
	vm.inflight = 0
	for ownership in stopping_file.g13_queues {
		mut queue := unsafe { ownership.resources }
		queue.released = true
	}
}

fn close_during_reap(_ &gpu.G13QueueResources) {
	gpu.watch_queue_release(unsafe { nil })
	assert closing_reaper_active && closing_head == unsafe { nil }
	reap_closed_files()
	assert closing_reaper_requested
	release_handle(&drm.DrmDevice{}, voidptr(u64(4)))
	assert closing_count == 1
	late_close_vm.inflight = 0
}

fn check_late_stopped_close() {
	gpu.set_running(true)
	mut first_vm := mmu.UatContext{inflight: 1}
	mut second_vm := mmu.UatContext{inflight: 1}
	queue := gpu.G13QueueResources{}
	file_map[4] = &GpuFile{vms: [&second_vm]}
	file_map[5] = &GpuFile{
		vms: [&first_vm]
		g13_queues: [G13QueueOwnership{resources: &queue}]
	}
	release_handle(&drm.DrmDevice{}, voidptr(u64(5)))
	assert closing_count == 1
	gpu.set_running(false)
	first_vm.inflight = 0
	late_close_vm = unsafe { &second_vm }
	gpu.watch_queue_release(close_during_reap)
	reap_closed_files()
	assert first_vm.destroyed && second_vm.destroyed && closing_count == 0
	late_close_vm = unsafe { nil }
	gpu.set_running(true)
	println('AGX stopped close: a late close and overlapping reap drain both files')
}

pub fn run_checks() {
	mut vm_manager := mmu.UatManager{}
	uat_mgr = &vm_manager
	mut initial_manager := unsafe { gpu.registration_manager() }
	initial_manager.uat = &vm_manager
	mut queue_a := gpu.G13QueueResources{ failures: 1 }
	mut queue_b := gpu.G13QueueResources{ failures: 1 }
	mut pt := pgtable.UatPgtable{}
	mut vm_a := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &pt, queue: &queue_a }
	mut vm_b := mmu.UatContext{ id: 2, vm_id: 2, queue: &queue_b }
	mut logical := workqueue.WorkQueue{}
	mut mapped := gem.GemObject{}
	mut timestamp := gem.GemObject{}
	mut file := &GpuFile{
		queues:            [&logical]
		g13_queues:        [G13QueueOwnership{ resources: &queue_a },
			G13QueueOwnership{ resources: &queue_b }]
		vms:               [&vm_a, &vm_b]
		mappings:          [GpuMapping{ vm_id: 1, addr: 0x4000, size: 0x4000, obj: &mapped }]
		timestamp_objects: [TimestampObject{ va: 0x10000, size: 4096, obj: &timestamp }]
		registration_manager: gpu.registration_manager()
	}
	vm_a.inflight = 1
	key := u64(0x1234)
	file_map[key] = file
	device := drm.DrmDevice{}
	release_handle(&device, voidptr(key))
	assert key !in file_map && closing_count == 1
	assert queue_a.calls == 0 && !logical.destroyed && !vm_a.destroyed
	reap_closed_files()
	assert closing_count == 1 && queue_a.calls == 0
	vm_a.inflight = 0
	reap_closed_files()
	assert !queue_a.released && queue_b.calls == 0
	assert !vm_a.destroyed && !vm_b.destroyed && !logical.destroyed && table_releases == 0
	reap_closed_files()
	assert queue_a.released && !queue_b.released
	assert !vm_a.destroyed && !vm_b.destroyed && closing_count == 1
	reap_closed_files()
	// The file pointer is freed here; inspect separately owned fixtures only.
	assert vm_a.destroyed && vm_b.destroyed && logical.destroyed
	assert mapped.references == 0 && timestamp.references == 0 && gpu.unmaps() == 1
	assert table_releases == 1 && closing_count == 0 && closing_head == unsafe { nil } && closing_tail == unsafe { nil }
	reap_closed_files()
	assert table_releases == 1
	// Concurrent/reentrant polling is rejected without losing the file.
	mut one_vm := mmu.UatContext{ inflight: 1 }
	mut two_vm := mmu.UatContext{ inflight: 1 }
	mut one := &GpuFile{vms: [&one_vm]}
	mut two := &GpuFile{vms: [&two_vm]}
	file_map[1] = one
	file_map[2] = two
	release_handle(&device, voidptr(1))
	release_handle(&device, voidptr(2))
	assert closing_count == 2 && voidptr(closing_head) == voidptr(one) && voidptr(closing_tail) == voidptr(two)
	closing_reaper_active = true
	reap_closed_files()
	assert closing_count == 2
	closing_reaper_active = false
	reap_closed_files()
	assert closing_count == 2 && table_releases == 1, 'one pass must not spin on busy files'
	one_vm.inflight = 0
	reap_closed_files()
	assert closing_count == 1 && table_releases == 2 && voidptr(closing_head) == voidptr(two)
	two_vm.inflight = 0
	reap_closed_files()
	assert closing_count == 0
	assert closing_head == unsafe { nil } && closing_tail == unsafe { nil } && table_releases == 3
	// Deterministically finish shutdown between the initial failed close
	// and registration. No worker remains to drain an enqueue at this point.
	mut stopped_queue := gpu.G13QueueResources{}
	mut stopped_vm := mmu.UatContext{queue: &stopped_queue}
	mut stopped_file := &GpuFile{
		g13_queues: [G13QueueOwnership{resources: &stopped_queue}]
		vms: [&stopped_vm]
	}
	stopped_vm.inflight = 1
	file_map[3] = stopped_file
	stopping_file = stopped_file
	gpu.stop_on_next_retirement(stop_during_registration)
	release_handle(&device, voidptr(3))
	stopping_file = unsafe { nil }
	assert stopped_vm.destroyed && table_releases == 4 && closing_count == 0
	check_repeated_bindings()
	check_unbind_ranges()
	check_bind_replacements()
	check_global_params()
	check_global_params_device()
	check_timestamp_registration()
	check_timestamp_bindings()
	check_timestamp_captures()
	check_timestamp_publication_storage()
	check_timestamp_publication_stop()
	check_timestamp_owner_teardown()
	gpu.check_timestamp_serialization()
	check_zero_bind_ranges()
	check_create_sizes()
	check_bind_order()
	check_bind_vm_lookup()
	check_mapping_retirement()
	check_mapping_permissions()
	check_private_objects()
	check_identity_lookups()
	check_queue_priorities()
	check_cpu_mapping_policy()
	check_detached_queues()
	check_detached_vms()
	check_orphaned_queues()
	check_stopped_constructor_adoption()
	check_queue_record_reclamation()
	check_logical_queue_records()
	check_late_stopped_close()
	check_vm_registration_replacement()
	println('AGX file close: live jobs, failed/partial queue release, retained VMs, retry, final object teardown and intrusive retirement passed')
}
