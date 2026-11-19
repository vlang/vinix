// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import klock
import memory

__global destroying_vm_file &GpuFile = unsafe { nil }

fn destroy_before_bind() {
	request := ioctl.DrmAsahiVmDestroy{ vm_id: 1 }
	assert destroying_vm_file.ioctl_vm_destroy(&request) == 0
}

fn bind(handle u32, vm_id u32, address u64) ioctl.DrmAsahiGemBind {
	return ioctl.DrmAsahiGemBind{
		op: ioctl.asahi_bind_op_bind
		flags: ioctl.asahi_bind_read | ioctl.asahi_bind_write
		handle: handle
		vm_id: vm_id
		addr: address
		range: 0x4000
	}
}

fn unbind(vm_id u32, address u64) ioctl.DrmAsahiGemBind {
	return ioctl.DrmAsahiGemBind{
		op: ioctl.asahi_bind_op_unbind
		vm_id: vm_id
		addr: address
		range: 0x4000
	}
}

fn check_mapping_retirement() {
	gpu.set_running(true)
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &pt }
		mut file := GpuFile{ vms: [&vm] }
		file.mappings.flags |= .noslices
		object := gem.create(7)
		file.objects.table.add_created(object)
		// A refusal before publication has no mapping or reference to retire.
		pt.reject_map = true
		assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == -12
		assert object.references == 1 && file.mappings.len == 0 && pt.unmaps == 0
		pt.reject_map = false
		assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
		assert object.references == 2 && file.mappings.len == 1
		gpu.fail_mapping_checks(3)
		for _ in 0 .. 3 {
			assert file.ioctl_gem_bind(unbind(1, 0x4000)) == -5
			assert object.references == 2 && file.mappings.len == 1
			assert file.mappings[0].retiring && pt.unmaps == 1
		}
		assert file.ioctl_gem_bind(unbind(1, 0x4000)) == 0
		assert object.references == 1 && file.mappings.len == 0 && pt.unmaps == 1
		assert file.ioctl_gem_bind(unbind(1, 0x4000)) == 0
		assert file.close() && vm.destroyed && gem.live() == 0

		// A failed BIND keeps the just-published object's reference, too.
		mut failed_pt := pgtable.UatPgtable{}
		mut failed_vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &failed_pt }
		mut failed := GpuFile{ vms: [&failed_vm], ioctl_abi: legacy_ioctl_abi }
		failed.mappings.flags |= .noslices
		failed_object := gem.create(7)
		failed.objects.table.add_created(failed_object)
		gpu.fail_mapping_checks(1)
		assert failed.ioctl_gem_bind(bind(7, 1, 0x4000)) == -5
		assert failed_object.references == 2 && failed.mappings[0].retiring
		assert failed_pt.unmaps == 1
		gpu.fail_mapping_checks(2)
		assert failed.close_object_handle(7, 0) == -5
		assert failed_object.references == 1 && !failed_vm.destroyed
		assert !failed.close() && !failed_vm.destroyed
		assert failed_object.references == 1 && failed_pt.unmaps == 1
		assert failed.close() && failed_vm.destroyed && gem.live() == 0

		// Jobs in flight do not hold user bindings, as on Asahi's G13 path:
		// UNBIND and GEM_CLOSE remove the PTEs and invalidate them before the
		// mapping drops its reference. A failed acknowledgement keeps the
		// record and its reference, and the retry runs while the VM is busy.
		mut busy_pt := pgtable.UatPgtable{}
		mut busy_vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &busy_pt }
		mut busy := GpuFile{ vms: [&busy_vm], ioctl_abi: legacy_ioctl_abi }
		busy.mappings.flags |= .noslices
		busy_object := gem.create(7)
		busy.objects.table.add_created(busy_object)
		assert busy.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
		assert busy.ioctl_gem_bind(bind(7, 1, 0x8000)) == 0
		assert busy_object.references == 3
		busy_vm.inflight = 1
		assert busy.ioctl_gem_bind(unbind(1, 0x4000)) == 0
		assert busy_object.references == 2 && busy_pt.unmaps == 1 && busy.mappings.len == 1
		gpu.fail_mapping_checks(1)
		assert busy.close_object_handle(7, 0) == -5
		assert busy.mappings[0].retiring && busy_object.references == 1 && busy_pt.unmaps == 2
		assert !busy.close() && !busy_vm.destroyed
		before := gpu.mapping_checks()
		assert busy.cleanup_closed_mappings_locked(&busy_vm) && gpu.mapping_checks() == before + 1
		assert busy.mappings.len == 0 && busy_pt.unmaps == 2 && gem.live() == 0
		assert !busy.close() && !busy_vm.destroyed
		busy_vm.inflight = 0
		assert busy.close()
	}

	mut first_pt := pgtable.UatPgtable{}
	mut second_pt := pgtable.UatPgtable{}
	mut first_vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &first_pt }
	mut second_vm := mmu.UatContext{ id: 2, vm_id: 2, pgtable: &second_pt }
	mut file := GpuFile{ vms: [&first_vm, &second_vm] }
	file.mappings.flags |= .noslices
	object := gem.create(7)
	file.objects.table.add_created(object)
	assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
	assert file.ioctl_gem_bind(bind(7, 1, 0x8000)) == 0
	assert file.ioctl_gem_bind(bind(7, 2, 0x4000)) == 0
	assert object.references == 4
	all := ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_unbind_all, handle: 7, vm_id: 1 }
	gpu.fail_mapping_checks(1)
	assert file.ioctl_gem_bind(&all) == -5
	assert object.references == 3 && file.mappings.len == 2
	assert first_pt.unmaps == 2 && second_pt.unmaps == 0
	assert file.ioctl_gem_bind(&all) == 0
	assert object.references == 2 && file.mappings.len == 1
	assert file.mappings[0].vm_id == 2

	// Failed retries refuse overlapping replacement. A later successful
	// retirement frees the old reservation and permits a new mapping.
	gpu.fail_mapping_checks(1)
	assert file.ioctl_gem_bind(unbind(2, 0x4000)) == -5
	gpu.fail_mapping_checks(1)
	assert file.ioctl_gem_bind(bind(7, 2, 0x4000)) == -5
	assert object.references == 2 && second_pt.maps == 1
	assert file.ioctl_gem_bind(bind(7, 2, 0x4000)) == 0
	assert object.references == 2 && second_pt.maps == 2
	gpu.fail_mapping_checks(1)
	assert file.ioctl_gem_bind(unbind(2, 0x4000)) == -5
	before := gpu.mapping_checks()
	gpu.set_running(false)
	// Stopped firmware permits final release after taking the manager lock.
	gpu.fail_mapping_checks(100)
	assert file.close() && gpu.mapping_checks() == before && gem.live() == 0
	assert first_vm.destroyed && second_vm.destroyed
	gpu.fail_mapping_checks(0)
	assert file.find_owned_vm(64) == none
	// VM destruction wins before the mutation lock. BIND must re-resolve
	// the VM inside that lock, before borrowing the page table or GEM.
	gpu.set_running(true)
	mut race_pt := pgtable.UatPgtable{}
	mut race_vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &race_pt }
	mut raced := GpuFile{ vms: [&race_vm] }
	race_object := gem.create(7)
	raced.objects.table.add_created(race_object)
	destroying_vm_file = &raced
	klock.before_once(unsafe { &raced.lock }, destroy_before_bind)
	assert raced.ioctl_gem_bind(bind(7, 1, 0x4000)) == -2
	assert race_pt.destroyed && race_pt.maps == 0 && raced.mappings.len == 0
	assert race_object.references == 1 && raced.close() && gem.live() == 0
	destroying_vm_file = unsafe { nil }

	for is_bind in [false, true]! {
		gpu.set_running(true)
		mut stop_pt := pgtable.UatPgtable{}
		mut stop_vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &stop_pt }
		mut stopping := GpuFile{ vms: [&stop_vm] }
		stop_object := gem.create(7)
		stopping.objects.table.add_created(stop_object)
		if !is_bind {
			assert stopping.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
			gpu.fail_mapping_checks(1)
			assert stopping.ioctl_gem_bind(unbind(1, 0x4000)) == -5
		}
		before_stops := gpu.stop_count()
		gpu.stop_during_mapping_lock()
		if is_bind {
			assert stopping.ioctl_gem_bind(bind(7, 1, 0x4000)) == -5
			assert stop_object.references == 2 && stopping.mappings[0].retiring
		}
		assert stopping.close()
		assert gpu.stop_count() == before_stops + 1 && gem.live() == 0
		assert stop_pt.unmaps == 1 && stop_vm.destroyed
	}
	println('AGX mapping retirement: 200 bind/unbind/GEM-close/retry cycles, failed bind ownership, busy VM admission, partial UNBIND_ALL, replacement, stopped cleanup, exact-lock shutdown races and VM destruction before BIND passed')
	check_reimported_mapping_retirement()
	check_worker_mapping_retirement()
	check_eviction_before_file_mapping_check()
	check_file_mapping_state()
}

fn check_reimported_mapping_retirement() {
	gpu.set_running(true)
	for split in [false, true]! {
		mut pt := pgtable.UatPgtable{watch_start: 0x4000}
		mut vm := mmu.UatContext{id: 1, vm_id: 1, pgtable: &pt}
		mut file := GpuFile{vms: [&vm], ioctl_abi: legacy_ioctl_abi}
		object := gem.create(7)
		file.objects.table.add_created(object)
		// An export keeps the BO alive across its handle's close.
		gem.ref_obj(object)
		mut original := bind(7, 1, 0x4000)
		original.range = 0xc000
		assert file.ioctl_gem_bind(&original) == 0
		if split {
			assert file.ioctl_gem_bind(unbind(1, 0x8000)) == 0
			assert file.mappings.len == 2 && object.references == 4 && pt.leaves[1] == 0
		}
		old_records := file.mappings.len
		before_close := pt.unmaps

		// The close removes the old bindings' PTEs while a job holds the VM.
		// One failed acknowledgement leaves a record retiring with its reference.
		vm.inflight = 1
		gpu.fail_mapping_checks(1)
		assert file.close_object_handle(7, 0) == -5
		assert pt.leaves[0] == 0 && pt.leaves[1] == 0 && pt.leaves[2] == 0
		assert pt.unmaps == before_close + old_records
		assert file.mappings.len == 1 && file.mappings[0].retiring && object.references == 2
		file.lock.acquire()
		imported := file.objects.table.import_object(object) or { panic('restore handle') }
		file.lock.release()
		assert object.references == 3

		// A bind through the reimported handle completes the old retirement
		// without unmapping it again, and installs the new binding.
		assert file.ioctl_gem_bind(bind(imported, 1, 0x10000)) == 0
		assert pt.unmaps == before_close + old_records && pt.leaves[3] == object.phys_addr
		assert pt.leaves[0] == 0 && pt.leaves[1] == 0 && pt.leaves[2] == 0,
			'reimport must not restore bindings selected by the old close'
		assert file.mappings.len == 1 && !file.mappings[0].retiring && object.references == 3
		vm.inflight = 0
		assert file.close() && object.references == 1
		gem.unref(object)
		assert gem.live() == 0
		memory.assert_released()
	}
	println('AGX GEM reimport: a busy close retires old bindings and split fragments at once; a reimport neither cancels nor repeats a pending retirement')
}

fn check_worker_mapping_retirement() {
	gpu.set_running(true)
	mut first_pt := pgtable.UatPgtable{watch_start: 0x4000}
	mut second_pt := pgtable.UatPgtable{watch_start: 0x4000}
	mut first := mmu.UatContext{id: 1, vm_id: 1, pgtable: &first_pt}
	mut second := mmu.UatContext{id: 2, vm_id: 2, pgtable: &second_pt}
	mut file := GpuFile{vms: [&first, &second]}
	file_map[0x4c05] = unsafe { &file }
	closed := gem.create(7)
	neighbor_bo := gem.create(8)
	file.objects.table.add_created(closed)
	file.objects.table.add_created(neighbor_bo)
	assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
	assert file.ioctl_gem_bind(bind(7, 2, 0x4000)) == 0
	assert file.ioctl_gem_bind(bind(8, 1, 0x8000)) == 0

	// Jobs in flight do not hold user bindings (Asahi G13): the close removes
	// both VMs' PTEs at once. The first VM's acknowledgement fails once, and
	// the worker retries it while that VM is still busy, without a second
	// PTE removal.
	first.inflight = 2
	second.inflight = 1
	gpu.fail_mapping_checks(1)
	assert file.close_object_handle(7, 0) == 0
	assert first.closed_mappings_pending && !second.closed_mappings_pending
	assert first_pt.unmaps == 1 && second_pt.unmaps == 1 && closed.references == 1
	reap_open_detached_g13_queues()
	assert !first.closed_mappings_pending && first_pt.unmaps == 1 && second_pt.unmaps == 1 && gem.live() == 1
	assert first_pt.leaves[1] == neighbor_bo.phys_addr && neighbor_bo.references == 2 && file.mappings.len == 1
	assert first.inflight == 2 && second.inflight == 1
	assert !first.destroyed && !second.destroyed && file.find_vm(1) != none && file.find_vm(2) != none
	first.inflight = 0
	second.inflight = 0
	file_map.delete(0x4c05)
	assert file.close() && gem.live() == 0
	memory.assert_released()
	println('AGX GEM close worker: busy VMs release old mappings at once, device-state refusal retries once without a second PTE removal, and live mappings and VM names remain available')
}

__global evicting_pt &pgtable.UatPgtable = unsafe { nil }

fn evict_before_file_mapping_check() {
	assert evicting_pt.unmaps == 1 && evicting_pt.tlb_bound
	evicting_pt.tlb_bound = false
}

fn check_eviction_before_file_mapping_check() {
	gpu.set_running(true)
	mut pt := pgtable.UatPgtable{tlb_asid: 7}
	mut vm := mmu.UatContext{id: 1, vm_id: 1, pgtable: &pt}
	mut file := GpuFile{vms: [&vm]}
	file.objects.table.add_created(gem.create(7))
	assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
	checks := gpu.mapping_checks()
	evicting_pt = unsafe { &pt }
	gpu.before_file_mapping_lock(evict_before_file_mapping_check)
	assert file.ioctl_gem_bind(unbind(1, 0x4000)) == 0
	assert !pt.tlb_bound && gpu.mapping_checks() == checks + 1 && file.mappings.len == 0
	evicting_pt = unsafe { nil }
	assert file.close() && gem.live() == 0
	memory.assert_released()
	println('AGX file mapping: resident bind and eviction after unmap complete without FwCtl')
}

fn check_file_mapping_state() {
	mut manager := unsafe { gpu.get_global_manager() or { panic('GPU manager') } }
	file := GpuFile{ registration_manager: manager }
	for generation in [gpu.Generation.g13, .g17]! {
		manager.hw_config.gpu_gen = generation
		for state in [gpu.State.idle, .starting, .running, .error, .stopped]! {
			manager.state = state
			assert file.finish_file_mapping(false) == (generation == .g13 && state == .running)
			assert file.finish_file_mapping(true) == (generation == .g13 && state in [.running, .stopped]!)
			assert !gpu.query_lock_held()
		}
	}
	manager.hw_config.gpu_gen = .g13
	manager.state = .running
	println('AGX file mapping: device loss, stopped cleanup and unsupported G17 state gates passed')
}

fn check_mapping_permissions() {
	gpu.set_running(true)
	gpu.fail_mapping_checks(0)
	mut pt := pgtable.UatPgtable{}
	mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: &pt }
	mut file := GpuFile{ vms: [&vm] }
	file.mappings.flags |= .noslices
	object := gem.create(7)
	file.objects.table.add_created(object)
	flags := [ioctl.asahi_bind_read, ioctl.asahi_bind_write,
		ioctl.asahi_bind_read | ioctl.asahi_bind_write]!
	protection := [pgtable.gpu_prot_gpu_shared_ro, pgtable.gpu_prot_gpu_shared_wo,
		pgtable.gpu_prot_gpu_shared_rw]!
	for index, mode in flags {
		mut request := bind(7, 1, 0x4000)
		request.flags = mode
		assert file.ioctl_gem_bind(&request) == 0
		assert pt.last_protection == protection[index]
		assert object.references == 2 && file.mappings.len == 1
		assert file.ioctl_gem_bind(unbind(1, 0x4000)) == 0
		assert object.references == 1 && file.mappings.len == 0
	}
	for mode in [u32(0), 4, 5, 6, 7, 0x80000000, 0xffffffff]! {
		mut request := bind(7, 1, 0x4000)
		request.flags = mode
		before := pt.maps
		assert file.ioctl_gem_bind(&request) == -22
		assert pt.maps == before && object.references == 1 && file.mappings.len == 0
	}
	assert file.close() && gem.live() == 0
	println('AGX mapping permissions: real ioctl preserves distinct read-only, write-only and read/write selectors; empty/unknown permissions reject before mapping')
}
