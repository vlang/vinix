@[has_globals]
module file

import drm
import drm.gem
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.workqueue
import klock

struct G13QueueOwnership {
	resources &gpu.G13QueueResources
}

struct G17QueueOwnership {
	resources &gpu.G17QueueResources
}

struct GpuMapping {
	obj &gem.GemObject
}

struct TimestampObject {
	va   u64
	size u64
	obj  &gem.GemObject
}

struct Objects {}

__global table_releases = 0

fn (mut objects Objects) release_all() { table_releases++ }

struct GpuFile {
mut:
	lock              klock.Lock
	inflight_by_vm    [64]u64
	queues            []&workqueue.WorkQueue
	g13_queues        []G13QueueOwnership
	g17_queues        []G17QueueOwnership
	timestamp_objects []TimestampObject
	vms               []&mmu.UatContext
	mappings          []GpuMapping
	objects           Objects
	closing_next      &GpuFile = unsafe { nil }
	closing_queued    bool
}

__global file_map_lock klock.Lock
__global file_map = map[u64]&GpuFile{}
__global uat_mgr &mmu.UatManager = unsafe { nil }
__global stopping_file &GpuFile = unsafe { nil }

fn stop_during_registration() {
	stopping_file.inflight_by_vm[1] = 0
	for ownership in stopping_file.g13_queues {
		mut queue := unsafe { ownership.resources }
		queue.released = true
	}
}

pub fn run_checks() {
	mut vm_manager := mmu.UatManager{}
	uat_mgr = &vm_manager
	mut queue_a := gpu.G13QueueResources{ failures: 1 }
	mut queue_b := gpu.G13QueueResources{ failures: 1 }
	mut vm_a := mmu.UatContext{ queue: &queue_a }
	mut vm_b := mmu.UatContext{ queue: &queue_b }
	mut logical := workqueue.WorkQueue{}
	mut mapped := gem.GemObject{}
	mut timestamp := gem.GemObject{}
	mut file := &GpuFile{
		queues:            [&logical]
		g13_queues:        [G13QueueOwnership{ resources: &queue_a },
			G13QueueOwnership{ resources: &queue_b }]
		vms:               [&vm_a, &vm_b]
		mappings:          [GpuMapping{ obj: &mapped }]
		timestamp_objects: [TimestampObject{ va: 0x10000, size: 4096, obj: &timestamp }]
	}
	file.inflight_by_vm[1] = 1
	key := u64(0x1234)
	file_map[key] = file
	device := drm.DrmDevice{}
	release_handle(&device, voidptr(key))
	assert key !in file_map && closing_count == 1
	assert queue_a.calls == 0 && !logical.destroyed && !vm_a.destroyed
	reap_closed_files()
	assert closing_count == 1 && queue_a.calls == 0
	file.inflight_by_vm[1] = 0
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
	mut one := &GpuFile{}
	mut two := &GpuFile{}
	one.inflight_by_vm[1] = 1
	two.inflight_by_vm[1] = 1
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
	one.inflight_by_vm[1] = 0
	reap_closed_files()
	assert closing_count == 1 && table_releases == 2 && voidptr(closing_head) == voidptr(two)
	two.inflight_by_vm[1] = 0
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
	stopped_file.inflight_by_vm[1] = 1
	file_map[3] = stopped_file
	stopping_file = stopped_file
	gpu.stop_on_next_lookup(stop_during_registration)
	release_handle(&device, voidptr(3))
	stopping_file = unsafe { nil }
	assert stopped_vm.destroyed && table_releases == 4 && closing_count == 0
	println('AGX file close: live jobs, failed/partial queue release, retained VMs, retry, final object teardown and intrusive retirement passed')
}
