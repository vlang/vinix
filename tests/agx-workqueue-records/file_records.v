module file

import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.workqueue
import drm.ioctl

#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

fn check_logical_queue_records() {
	$if queue_records_sanitized ? {
	mut cases := 0
	for path in 0 .. 2 { for available in [false, true]! { for refs in [u64(0), 1, 3]! {
		for failures in 0 .. 2 { for count in [1, 3]! {
			gpu.available(available); gpu.set_running(true)
			mut resources := [3]gpu.G13QueueResources{}
			mut saved := unsafe { [3]&workqueue.WorkQueue{} }
			mut vm := mmu.UatContext{id: 1}
			mut file := GpuFile{vms: [&vm]}
			file.queues.flags |= .noslices; file.g13_queues.flags |= .noslices
			for i in 0 .. count {
				resources[i] = gpu.G13QueueResources{queue_id: u32(i + 1), failures: failures}
				for _ in 0 .. int(refs) { resources[i].retain_file_reference() }
				queue := &workqueue.WorkQueue{id: u32(i + 1), vm_id: 1, heap_record: true, detached: path == 1}
				saved[i] = queue; file.queues << queue
				file.g13_queues << G13QueueOwnership{queue_id: u32(i + 1), vm_id: 1, resources: unsafe { &resources[i] }}
			}
			if !available || refs != 0 {
				assert !record_owner_step(mut file, path)
				for i in 0 .. count { assert C.__asan_address_is_poisoned(saved[i]) == 0, 'logical metadata stays alive with captures or absent manager' }
			}
			for i in 0 .. count { for _ in 0 .. int(refs) { resources[i].release_file_reference() } }
			gpu.available(true)
			mut done := false
			for _ in 0 .. count * failures + 2 { if record_owner_step(mut file, path) { done = true; break } }
			assert done && file.queues.len == 0
			for i in 0 .. count { assert C.__asan_address_is_poisoned(saved[i]) != 0, 'native final queue owners must free logical metadata' }
			assert file.close() && vm.destroyed
			cases++
		} }
	} } }
	// G17/legacy ioctl destruction must snapshot the pointer before delete.
	for target in 0 .. 3 {
		mut file := GpuFile{}
		mut saved := unsafe { [3]&workqueue.WorkQueue{} }
		for i in 0 .. 3 {
			queue := &workqueue.WorkQueue{id: u32(i + 1), vm_id: 1, heap_record: true}
			saved[i] = queue; file.queues << queue
		}
		assert file.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: u32(target + 1)}) == 0
		for i in 0 .. 3 { assert (C.__asan_address_is_poisoned(saved[i]) != 0) == (i == target), 'native destroy must free its original pointer before row shifts' }
		assert file.close()
		cases++
	}
	// An aggregate submission pin retains even a logical-only file queue.
	queue := &workqueue.WorkQueue{id: 1, vm_id: 65, heap_record: true}
	mut vm := mmu.UatContext{id: 65, inflight: 1}
	mut pinned := GpuFile{queues: [queue], vms: [&vm]}
	assert !pinned.close() && C.__asan_address_is_poisoned(queue) == 0
	vm.inflight = 0
	assert pinned.close() && C.__asan_address_is_poisoned(queue) != 0
	assert cases == 51
	println('AGX logical queues: 51 native close/detached/shifted-owner cases and aggregate pin retention passed')
	}
}
