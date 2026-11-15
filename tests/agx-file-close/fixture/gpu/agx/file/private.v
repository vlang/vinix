// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.bo
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import klock

fn create_request(vm_id u32, flags u32) ioctl.DrmAsahiGemCreate {
	return ioctl.DrmAsahiGemCreate{ vm_id: vm_id, flags: flags, size: 0x4000 }
}

fn check_private_objects() {
	gpu.set_running(true)
	mut first_pt := pgtable.UatPgtable{}
	mut second_pt := pgtable.UatPgtable{}
	mut first := mmu.UatContext{ id: 1, identity: mmu.new_identity(), pgtable: &first_pt }
	mut second := mmu.UatContext{ id: 2, identity: mmu.new_identity(), pgtable: &second_pt }
	assert first.identity != 0 && first.identity != second.identity
	mut file := GpuFile{ vms: [&first, &second] }
	file.mappings.flags |= .noslices
	file.timestamp_objects.flags |= .noslices
	mut private_request := create_request(1, ioctl.asahi_gem_vm_private | ioctl.asahi_gem_writeback)
	assert file.ioctl_gem_create(&private_request) == 0
	private := file.objects.table.find(private_request.handle) or { panic('private object') }
	assert private.vm_private_identity == first.identity && private.references == 1
	assert file.ioctl_gem_bind(bind(private.handle, 1, 0x4000)) == 0
	assert private.references == 2 && first_pt.maps == 1
	assert file.ioctl_gem_bind(bind(private.handle, 2, 0x4000)) == -22
	assert second_pt.maps == 0 && private.references == 2
	assert file.ioctl_gem_bind(unbind(1, 0x4000)) == 0 && private.references == 1
	mut imported := bo.Table{}
	if _ := imported.import_object(private) { panic('private import accepted') }
	if _ := file.objects.table.import_object(private) { panic('private reimport accepted') }
	assert private.references == 1
	imported.release_all()
	timestamp := ioctl.DrmAsahiGemBindObject{
		op: ioctl.asahi_bind_object_op_bind
		flags: ioctl.asahi_bind_object_usage_timestamps
		handle: private.handle
		range: 0x4000
	}
	before := gpu.maps()
	assert file.ioctl_gem_bind_object(&timestamp) == -22
	assert private.references == 1 && gpu.maps() == before && file.timestamp_objects.len == 0
	// CPU access through this file is allowed; it holds its own reference.
	file.objects.table.authorize_mmap(private.handle) or { panic('private CPU mmap') }
	assert private.references == 2

	// Destroy the hardware context while its unmapped private BO remains.
	// Reusing the same userspace/context number cannot inherit its domain.
	destroy := ioctl.DrmAsahiVmDestroy{ vm_id: 1 }
	assert file.ioctl_vm_destroy(&destroy) == 0 && first.destroyed
	mut reused_pt := pgtable.UatPgtable{}
	mut reused := mmu.UatContext{ id: 1, identity: mmu.new_identity(), pgtable: &reused_pt }
	assert reused.identity != first.identity && reused.identity != second.identity
	file.vms << &reused
	assert file.ioctl_gem_bind(bind(private.handle, 1, 0x4000)) == -22
	assert reused_pt.maps == 0 && private.references == 2
	mut shared_request := create_request(0, 0)
	assert file.ioctl_gem_create(&shared_request) == 0
	shareable := file.objects.table.find(shared_request.handle) or { panic('shared object') }
	assert shareable.vm_private_identity == 0
	assert file.ioctl_gem_bind(bind(shareable.handle, 1, 0x4000)) == 0
	assert file.ioctl_gem_bind(bind(shareable.handle, 2, 0x4000)) == 0
	assert shareable.references == 3
	mut shared_import := bo.Table{}
	assert (shared_import.import_object(shareable) or { panic('shared import') }) == shareable.handle
	assert shareable.references == 4
	shared_import.release_all()
	assert shareable.references == 3
	// Shareable timestamp buffers remain available in the kernel VM.
	mut shared_timestamp := ioctl.DrmAsahiGemBindObject{
		op: ioctl.asahi_bind_object_op_bind
		flags: ioctl.asahi_bind_object_usage_timestamps
		handle: shareable.handle
		range: 0x4000
	}
	assert file.ioctl_gem_bind_object(&shared_timestamp) == 0
	assert shared_timestamp.object_handle != 0 && shareable.references == 4
	gem.fail_creates(true)
	mut failed_private := create_request(1, ioctl.asahi_gem_vm_private)
	objects_before := gem.live()
	assert file.ioctl_gem_create(&failed_private) == -12
	assert failed_private.handle == 0 && gem.live() == objects_before
	gem.fail_creates(false)
	assert file.close() && gem.live() == 0
	assert reused.destroyed && second.destroyed

	mut empty_scope := mmu.UatContext{ id: 1 }
	mut invalid := GpuFile{ vms: [&empty_scope] }
	mut request := create_request(1, ioctl.asahi_gem_vm_private)
	assert invalid.ioctl_gem_create(&request) == -22 && request.handle == 0 && gem.live() == 0
	request = create_request(2, ioctl.asahi_gem_vm_private)
	assert invalid.ioctl_gem_create(&request) == -2 && request.handle == 0 && gem.live() == 0
	request = create_request(1, 0)
	assert invalid.ioctl_gem_create(&request) == -22 && gem.live() == 0
	request = create_request(0, 4)
	assert invalid.ioctl_gem_create(&request) == -22 && gem.live() == 0
	gem.fail_creates(true)
	request = create_request(0, 0)
	assert invalid.ioctl_gem_create(&request) == -12 && gem.live() == 0
	gem.fail_creates(false)
	// VM destruction wins before private-create takes its mutation lock.
	mut race_pt := pgtable.UatPgtable{}
	mut race_vm := mmu.UatContext{ id: 1, identity: mmu.new_identity(), pgtable: &race_pt }
	mut raced := GpuFile{ vms: [&race_vm] }
	destroying_vm_file = &raced
	klock.before_once(unsafe { &raced.lock }, destroy_before_bind)
	request = create_request(1, ioctl.asahi_gem_vm_private)
	assert raced.ioctl_gem_create(&request) == -2
	assert race_vm.destroyed && request.handle == 0 && gem.live() == 0
	if _ := raced.objects.table.find(request.handle) { panic('creation raced VM destruction') }
	destroying_vm_file = unsafe { nil }
	assert raced.close()
	unsafe { invalid.vms.free() }
	println('AGX VM-private objects: owning VM bind, foreign/reused-ID rejection, non-exportable import/timestamp policy, CPU authorization, shared operation, invalid flags/OOM and create/destroy lock race passed')
}
