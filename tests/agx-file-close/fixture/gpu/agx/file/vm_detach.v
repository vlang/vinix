// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm
import drm.asahi
import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

fn check_vm_registration_replacement() {
	gpu.set_running(true)
	mut original := unsafe { gpu.registration_manager() }
	mut original_uat := unsafe { original.uat }
	saved_uat := uat_mgr
	original_destroys := original_uat.vm_destroys
	original_releases := original.queue_release_calls
	mut original_pt := pgtable.UatPgtable{}
	mut original_vm := mmu.UatContext{pgtable: &original_pt}
	original_uat.next_context = unsafe { &original_vm }
	mut old_file := GpuFile{registration_manager: original}
	mut create_vm := ioctl.DrmAsahiVmCreate{kernel_start: 0x100000000, kernel_end: 0x120000000}
	assert old_file.ioctl_vm_create(&create_vm) == 0 && create_vm.vm_id == 1
	old_file.objects.table.add_created(gem.create(7))
	assert old_file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
	mut create_queue := queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_compute)
	assert old_file.ioctl_queue_create(&create_queue) == 0
	logical := old_file.queues[0]

	gpu.set_running(false)
	gpu.replace_manager(true)
	mut replacement := unsafe { gpu.registration_manager() }
	replacement.state = .running
	replacement_releases := replacement.queue_release_calls
	mut replacement_vm := mmu.UatContext{}
	mut replacement_uat := mmu.UatManager{handoff_abi: .v12_3, next_context: &replacement_vm}
	replacement.uat = unsafe { &replacement_uat }
	uat_mgr = unsafe { &replacement_uat }
	mut new_file := GpuFile{registration_manager: replacement}
	mut request := asahi.VmCreate{vm_id: 77, kernel_start: create_vm.kernel_start, kernel_end: create_vm.kernel_end}
	assert old_file.ioctl_modern_vm_create(&request) == -19 && request.vm_id == 77
	assert voidptr(replacement_uat.next_context) == voidptr(&replacement_vm) && old_file.vms.len == 1
	assert new_file.ioctl_modern_vm_create(&request) == 0 && request.vm_id == 1
	assert new_file.ioctl_get_params(&ioctl.DrmAsahiGetParams{}) == 0
	assert old_file.ioctl_get_params(&ioctl.DrmAsahiGetParams{}) == -19
	assert old_file.close()
	assert original_uat.vm_destroys == original_destroys + 1 && original.queue_release_calls == original_releases + 1,
		'old close must release its queue and VM through the original registration'
	assert original_vm.destroyed && original_pt.unmaps == 1 && !replacement_vm.destroyed
	assert replacement_uat.vm_destroys == 0 && replacement.queue_release_calls == replacement_releases
	assert new_file.close() && replacement_vm.destroyed && replacement_uat.vm_destroys == 1
	unsafe { free(logical) }
	replacement.uat = unsafe { nil }
	uat_mgr = saved_uat
	gpu.replace_manager(false)
	gpu.set_running(true)
	println('G13 registration replacement: stale creation refused and old queue, mapping and VM retired through their original owners')
}

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
	// Namespace removal and retirement still work without a global UAT.
	mut idle := mmu.UatContext{id: 1, vm_id: 1}
	mut file := GpuFile{vms: [&idle]}
	saved := uat_mgr
	uat_mgr = unsafe { nil }
	assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 1}) == 0
	assert idle.detached && idle.destroyed && file.vms.len == 0
	uat_mgr = saved
	assert file.close()
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
