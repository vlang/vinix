// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm
import drm.asahi
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.workqueue
import memory
import usercopy

__global scs_file &GpuFile = unsafe { nil }
__global scs_resource &gpu.G13QueueResources = unsafe { nil }
__global scs_failures int

fn scs_measure_step(mut file GpuFile, request &asahi.QueueCreate, retry bool) {
	if retry { gpu.watch_queue_release(watch_scs_release) }
	workqueue.heap_next_record(true)
	assert file.ioctl_modern_queue_create(request) == -22
	if retry {
		file.lock.acquire()
		file.reap_orphaned_g13_queues_locked()
		file.lock.release()
	}
	assert file.queues.len == 0 && file.g13_queues.len == 0
	assert workqueue.active() == 0 && gpu.active_queues() == 0
}

pub fn measure_scs_rejection() {
	$if macos {
		mut manager := mmu.UatManager{}
		mut registered := unsafe { gpu.registration_manager() }
		saved := registered.uat
		registered.uat = unsafe { &manager }
		uat_mgr = unsafe { &manager }
		defer {
			registered.uat = saved
			uat_mgr = unsafe { nil }
		}
		gpu.available(true)
		gpu.set_running(true)
		mut vm := mmu.UatContext{ id: 1, vm_id: 1 }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		file.queues.flags |= .noslices
		file.g13_queues.flags |= .noslices
		scs_file = unsafe { &file }
		scs_failures = 1
		request := asahi.QueueCreate{ vm_id: 1, render_scs_layout: [u64(1), 0]! }
		for retry in [false, true]! {
			for _ in 0 .. 20 {
				file.next_queue_id = 1
				scs_measure_step(mut file, unsafe { &request }, retry)
			}
			for batch in 0 .. 3 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 {
					file.next_queue_id = 1
					scs_measure_step(mut file, unsafe { &request }, retry)
				}
				after_blocks, after_bytes := live_record_heap()
				assert after_blocks == before_blocks && after_bytes == before_bytes
				println('scs-rejection retry=${retry} batch=${batch} operations=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
			}
		}
		assert file.close() && vm.destroyed
		scs_file = unsafe { nil }
		scs_resource = unsafe { nil }
	} $else {
		panic('malloc-zone retention measurement requires macOS')
	}
}

fn watch_scs_release(queue &gpu.G13QueueResources) {
	assert scs_file.lock.is_held() && scs_file.queues.len == 0
	mut resource := unsafe { queue }
	assert !resource.released && !resource.record_disposed
	scs_resource = resource
	resource.failures = scs_failures
	gpu.watch_queue_release(unsafe { nil })
}

pub fn run_modern_scs_checks() {
	gpu.available(true)
	gpu.set_running(true)
	driver := drm.DrmDriver{ ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle }
	device := drm.DrmDevice{ driver: unsafe { &driver } }
	mut cases := 0
	for _ in 0 .. 25 {
		for layout in [[u64(1), 0]!, [u64(0), ~u64(0)]!, [~u64(0), ~u64(0)]!] {
			for mode in 0 .. 10 {
				mut pt := pgtable.UatPgtable{}
				mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
				mut file := GpuFile{ vms: [unsafe { &vm }] }
				file.queues.flags |= .noslices
				file.g13_queues.flags |= .noslices
				file_map[0x5c5] = unsafe { &file }
				mut request := asahi.QueueCreate{
					vm_id:             if mode == 0 { u32(99) } else { 1 }
					priority:          if mode == 1 { u32(2) } else { 1 }
					flags:             if mode == 2 { u32(1) } else { 0 }
					queue_id:          73
					usc_exec_base:     0x120000000
					render_scs_layout: if mode == 9 { [u64(0), 0]! } else { layout }
				}
				if mode == 3 { workqueue.fail_next() }
				if mode == 4 { gpu.fail_queue() }
				if mode == 5 { gpu.quarantine_queue() }
				scs_file = unsafe { &file }
				scs_resource = unsafe { nil }
				scs_failures = if mode == 7 {
					2
				} else if mode == 8 {
					4
				} else {
					0
				}
				if mode in [6, 7, 8] { gpu.watch_queue_release(watch_scs_release) }
				workqueue.heap_next_record(true)
				host_before, gpu_before := workqueue.creation_attempts(), gpu.queue_creates()
				usercopy.configure(unsafe { u64(&request) }, sizeof(request), -1)
				code := drm.invoke(&device, 0x5c5, asahi.queue_create, sizeof(request), 3, unsafe { voidptr(&request) })
				workqueue.heap_next_record(false)
				gpu.watch_queue_release(unsafe { nil })
				expected := match mode {
					0 { -2 }
					3, 4, 5 { -12 }
					9 { 0 }
					else { -22 }
				}
				assert code == expected, 'queue construction must precede render SCS rejection'
				assert !file.lock.is_held() && file.ioctl_abi == modern_ioctl_abi
				assert workqueue.creation_attempts() == host_before + if mode >= 3 { 1 } else { 0 }
				assert gpu.queue_creates() == gpu_before + if mode >= 4 { 1 } else { 0 }
				if mode == 9 {
					assert request.queue_id == 1 && file.queues.len == 1
					assert file.queues[0].usc_base == request.usc_exec_base
					assert file.close() && vm.destroyed
				} else {
					assert request.queue_id == 73 && file.queues.len == 0
					assert file.capture_submission_queue(1) == none
					if mode >= 4 {
						assert C.__asan_address_is_poisoned(workqueue.last_record()) != 0, 'unpublished logical queue metadata must be freed'
					}
					if mode in [5, 7, 8] {
						assert file.g13_queues.len == 1, 'failed rollback must retain an orphan owner'
						mut resource := unsafe { file.g13_queues[0].resources }
						assert !resource.released && !resource.record_disposed && !vm.destroyed
						if mode != 5 {
							assert voidptr(resource) == voidptr(scs_resource) && resource.calls == 1
						}
						file.next_queue_id = 1
						assert (file.allocate_queue_id_locked() or { panic('retained ID') }) == 2
						if mode == 8 {
							for _ in 0 .. 3 {
								assert !file.close() && !vm.destroyed && !resource.record_disposed
							}
							assert file.close() && vm.destroyed && resource.record_disposed
						} else {
							assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{ vm_id: 1 }) == 0 && !vm.destroyed
							gpu.available(false)
							reap_open_detached_g13_queues()
							assert file.g13_queues.len == 1 && !vm.destroyed
							gpu.available(true)
							for _ in 0 .. 3 { reap_open_detached_g13_queues() }
							assert file.g13_queues.len == 0 && vm.destroyed && resource.record_disposed
							file.next_queue_id = 1
							assert (file.allocate_queue_id_locked() or { panic('reclaimed ID') }) == 1
							assert file.close()
						}
					} else {
						assert file.g13_queues.len == 0
						if mode == 6 {
							assert scs_resource.released && scs_resource.record_disposed
						}
						assert file.close() && vm.destroyed
					}
				}
				file_map.delete(0x5c5)
				scs_file = unsafe { nil }
				scs_resource = unsafe { nil }
				assert workqueue.active() == 0 && gpu.active_queues() == 0
				memory.assert_released()
				cases++
			}
		}
	}
	assert cases == 750
	println('AGX render SCS: 750 registered-node cases match header/priority/VM/constructor precedence, reject after construction without publishing a name, reclaim heap logical records, and retain failed graph/VM owners through worker or close retry')
}
