// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm
import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

fn check_detached_vms() {
	mut cases := 0
	for cycle in 0 .. 25 {
		for pins in [u64(0), 1, 3] {
			for failures in 0 .. 4 {
				for available in [false, true] {
					gpu.available(true)
					mut pt := pgtable.UatPgtable{}
					mut other_pt := pgtable.UatPgtable{}
					mut vm := mmu.UatContext{id: 1, vm_id: 1, identity: mmu.new_identity(), pgtable: &pt}
					mut other := mmu.UatContext{id: 2, vm_id: 2, pgtable: &other_pt}
					mut file := GpuFile{vms: [&vm, &other]}
					file.vms.flags |= .noslices
					file.mappings.flags |= .noslices
					file.queues.flags |= .noslices
					file.g13_queues.flags |= .noslices
					object := gem.create(7)
					file.objects.table.add_created(object)
					assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
					assert file.ioctl_gem_bind(bind(7, 2, 0x8000)) == 0
					mut create := queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_compute)
					assert file.ioctl_queue_create(&create) == 0
					logical := file.queues[0]
					mut resources := unsafe { file.g13_queues[0].resources }
					vm.queue = resources
					resources.failures = failures
					for _ in 0 .. int(pins) { resources.retain_file_reference() }
					vm.inflight = pins
					key := u64(0x5000_0000 + cycle)
					file_map[key] = unsafe { &file }
					gpu.fail_mapping_checks(failures)
					gpu.available(available)
					destroy := ioctl.DrmAsahiVmDestroy{vm_id: 1}
					assert file.ioctl_vm_destroy(&destroy) == 0
					assert file.ioctl_vm_destroy(&destroy) == -2
					assert vm.detached && !vm.destroyed && !other.destroyed
					if _ := file.find_vm(1) { panic('detached VM name visible') }
					owned := file.find_owned_vm(1) or { panic('lost physical VM owner') }
					assert voidptr(owned) == voidptr(&vm)
					if pins != 0 { assert pt.unmaps == 0 && object.references == 3 }
					// Existing queue capture remains usable without resurrecting
					// the VM name or changing aggregate job admission.
					captured := file.capture_submission_queue(create.queue_id) or { panic('queue capture') }
					assert captured.retained && voidptr(captured.resources) == voidptr(resources)
					assert vm.inflight == pins
					release_submission_queue(captured)
					gpu.available(true)
					assert file.ioctl_queue_create(&create) == -2
					mut private := create_request(1, ioctl.asahi_gem_vm_private)
					assert file.ioctl_gem_create(&private) == -2
					assert file.ioctl_gem_bind(bind(7, 1, 0xc000)) == -2
					assert file.ioctl_gem_bind(unbind(1, 0x4000)) == -2
					gpu.available(available)
					assert file.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: create.queue_id}) == 0
					if pins != 0 {
						reap_open_detached_g13_queues()
						assert !vm.destroyed && !resources.released && pt.unmaps == 0
					}
					for _ in 0 .. int(pins) { resources.release_file_reference() }
					vm.inflight = 0
					gpu.available(true)
					for _ in 0 .. failures + 4 { reap_open_detached_g13_queues() }
					assert vm.destroyed && resources.released && logical.destroyed
					assert pt.unmaps == 1 && !other.destroyed && other_pt.unmaps == 0
					assert object.references == 2 && file.mappings.len == 1
					assert file.vms.len == 1
					assert file.ioctl_vm_destroy(&destroy) == -2
					// A VM taking over the public name has a fresh identity.
					mut reused_pt := pgtable.UatPgtable{}
					mut reused := mmu.UatContext{id: 1, vm_id: 1, identity: mmu.new_identity(), pgtable: &reused_pt}
					file.vms << &reused
					assert reused.identity != vm.identity
					assert (file.find_vm(1) or { panic('reused VM hidden') }).identity == reused.identity
					file_map.delete(key)
					assert file.close() && other.destroyed && reused.destroyed
					assert gem.live() == 0 && gpu.active_queues() == 0
					unsafe { free(logical) }
					cases++
				}
			}
		}
	}
	// Namespace removal remains possible while the UAT manager is absent.
	mut idle := mmu.UatContext{id: 1, vm_id: 1}
	mut file := GpuFile{vms: [&idle]}
	saved := uat_mgr
	uat_mgr = unsafe { nil }
	assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 1}) == 0
	assert idle.detached && !idle.destroyed
	uat_mgr = saved
	file.lock.acquire(); file.reap_detached_vms_locked(); file.lock.release()
	assert idle.destroyed && file.close()
	// Handle close transfers a detached VM, queue and failed unmap to the
	// existing closing list. Retry must resolve its hidden physical owner.
	mut pt := pgtable.UatPgtable{}
	mut vm := mmu.UatContext{id: 1, vm_id: 1, pgtable: &pt}
	mut closing := &GpuFile{vms: [&vm]}
	object := gem.create(7)
	closing.objects.table.add_created(object)
	assert closing.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
	mut create := queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_compute)
	assert closing.ioctl_queue_create(&create) == 0
	logical := closing.queues[0]
	mut resources := unsafe { closing.g13_queues[0].resources }
	vm.queue = resources
	resources.retain_file_reference()
	vm.inflight = 1
	assert closing.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 1}) == 0
	file_map[99] = closing
	device := drm.DrmDevice{}
	release_handle(&device, voidptr(u64(99)))
	assert closing_count == 1 && !vm.destroyed && pt.unmaps == 0
	resources.release_file_reference()
	vm.inflight = 0
	gpu.fail_mapping_checks(1)
	reap_closed_files()
	assert closing_count == 1 && !vm.destroyed && object.references == 2
	reap_closed_files()
	assert closing_count == 0 && vm.destroyed && pt.unmaps == 1 && gem.live() == 0
	unsafe { free(logical) }
	println('G13 VM detach: ${cases} namespace/ownership cases, live queue captures, aggregate pins, mapping and queue invalidation retries, unavailable managers, sibling mappings, slot reuse and Handle-close transfer passed')
}
