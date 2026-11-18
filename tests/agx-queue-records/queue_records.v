module file

import gpu.agx.gpu
import gpu.agx.mmu
import drm.ioctl
import gpu.agx.workqueue
import gpu.agx.pgtable
import drm.gem
#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

fn close_record_cycle(mut file GpuFile) {
	resource := &gpu.G13QueueResources{heap_record: true}
	file.g13_queues << G13QueueOwnership{queue_id: 1, resources: resource}
	assert file.close()
}
pub fn measure_queue_records() {
	gpu.available(true); gpu.set_running(true)
	C.printf(c'AGX-QUEUE-RECORDS controlled host close measurement\n')
	mut file := GpuFile{}
	for _ in 0 .. 1000 { close_record_cycle(mut file) }
	live_record_heap()
	for round in 0 .. 3 {
		a, b := live_record_heap()
		for _ in 0 .. 10000 { close_record_cycle(mut file) }
		c, d := live_record_heap()
		C.printf(c'AGX-QUEUE-RECORDS round=%d closes=10000 retained_blocks=%lld retained_bytes=%lld\n', round, i64(c) - i64(a), i64(d) - i64(b))
		assert c == a && d == b, 'final file ownership removal must not retain released queue records'
	}
}
fn check_queue_record_reclamation() {
	$if queue_records_sanitized ? {
	gpu.available(true); gpu.set_running(true)
	mut resource := &gpu.G13QueueResources{heap_record: true, failures: 1}
	mut file := GpuFile{g13_queues: [G13QueueOwnership{queue_id: 1, resources: resource}]}
	assert !file.close() && C.__asan_address_is_poisoned(resource) == 0
	assert file.close() && C.__asan_address_is_poisoned(resource) != 0, 'final file ownership removal must free released queue records'
	mut cases := 0
	for path in 0 .. 3 { for available in [false, true]! { for refs in [u64(0), 1, 3]! {
		for failures in 0 .. 3 { for stopped in [false, true]! { for count in [1, 3]! {
			gpu.set_running(!stopped)
			mut records := []&gpu.G13QueueResources{}; records.flags |= .noslices
			mut queues := [3]workqueue.WorkQueue{}
			mut vm := mmu.UatContext{id: 1}
			mut owned := GpuFile{vms: [&vm]}
			registered := owned.registration_manager
			if !available { owned.registration_manager = unsafe { nil } }
			owned.g13_queues.flags |= .noslices; owned.queues.flags |= .noslices
			for i in 0 .. count {
				mut record := &gpu.G13QueueResources{queue_id: u32(i + 1), heap_record: true, released: stopped, failures: failures}
				for _ in 0 .. int(refs) { record.retain_file_reference() }
				records << record
				owned.g13_queues << G13QueueOwnership{queue_id: u32(i + 1), vm_id: 1, resources: record}
				if path == 1 { queues[i] = workqueue.WorkQueue{id: u32(i + 1), vm_id: 1, detached: true}; owned.queues << unsafe { &queues[i] } }
			}
			if !available || refs != 0 {
				assert !record_owner_step(mut owned, path)
				assert owned.g13_queues.len == count && !vm.destroyed
				for record in records { assert C.__asan_address_is_poisoned(record) == 0, 'missing owner and captured references must retain all metadata' }
			}
			for mut record in records { for _ in 0 .. int(refs) { record.release_file_reference() } }
			owned.registration_manager = registered
			mut done := false
			for _ in 0 .. count * failures + 2 {
				if record_owner_step(mut owned, path) { done = true; break }
				if path == 0 { for record in records { assert C.__asan_address_is_poisoned(record) == 0, 'partial close must keep even already released records until retry succeeds' } }
			}
			assert done && owned.g13_queues.len == 0
			for record in records { assert C.__asan_address_is_poisoned(record) != 0, 'final file ownership removal must free released queue records' }
			if path == 1 { for i in 0 .. count { assert queues[i].destroyed } }
			assert owned.close()
			assert vm.destroyed
			unsafe { records.free() }; cases++
		} } }
	} } }
	check_record_mapping_retry()
	gpu.available(true); gpu.set_running(true)
	assert cases == 216
	println('AGX queue records: 216 close/detached/orphan capture/manager/failure/stopped cases reclaim heap metadata after final owner removal; mapping retries retain partial closes')
	}
}

fn record_owner_step(mut file GpuFile, path int) bool {
	if path == 0 { return file.close() }
	file.lock.acquire()
	if path == 1 { file.reap_detached_g13_queues_locked() } else { file.reap_orphaned_g13_queues_locked() }
	result := file.g13_queues.len == 0
	file.lock.release(); return result
}

fn check_record_mapping_retry() {
	$if queue_records_sanitized ? {
		gpu.available(true); gpu.set_running(true)
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{id: 1, pgtable: &pt}
		resource := &gpu.G13QueueResources{heap_record: true}
		mut object := gem.GemObject{}
		mut file := GpuFile{vms: [&vm], g13_queues: [G13QueueOwnership{queue_id: 1, resources: resource}],
			mappings: [GpuMapping{vm_id: 1, addr: 0x4000, size: 0x4000, obj: &object}]}
		gpu.fail_mapping_checks(1)
		assert !file.close() && resource.released && file.g13_queues.len == 1 && !vm.destroyed
		assert C.__asan_address_is_poisoned(resource) == 0, 'failed mapping cleanup must retain already released queue metadata'
		assert file.close() && vm.destroyed && C.__asan_address_is_poisoned(resource) != 0
	}
}
