// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import memory

fn range_request(first u64, end u64) ioctl.DrmAsahiGemBind {
	mut request := unbind(1, (first + 1) * pgtable.uat_pgsz)
	request.range = (end - first) * pgtable.uat_pgsz
	return request
}

fn check_unbind_ranges() {
	gpu.set_running(true)
	mut cases := 0
	for _ in 0 .. 200 {
		for repeated in [false, true]! {
			for cut in [[u64(0), 1]!, [u64(5), 6]!, [u64(2), 4]!, [u64(5), 10]!,
				[u64(1), 17]!, [u64(0), 20]!, [u64(6), 8]!, [u64(19), 20]!, [u64(0), 6]!]! {
				mut pt := pgtable.UatPgtable{ watch_start: 0x4000 }
				mut neighbor := pgtable.UatPgtable{ watch_start: 0x4000 }
				mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
				mut other := mmu.UatContext{ id: 2, vm_id: 2, pgtable: unsafe { &neighbor } }
				mut file := GpuFile{ vms: [unsafe { &vm }, unsafe { &other }] }
				file.mappings.flags |= .noslices
				mut first := gem.create(7); first.size = 32 * pgtable.uat_pgsz
				mut second := gem.create(8); second.size = 32 * pgtable.uat_pgsz; second.phys_addr = 0x800000
				file.objects.table.add_created(first); file.objects.table.add_created(second)
				for index, span in [[u64(0), 6]!, [u64(8), 12]!, [u64(14), 18]!]! {
					mut request := bind(if index == 1 { u32(8) } else { u32(7) }, 1, (span[0] + 1) * pgtable.uat_pgsz)
					request.range = (span[1] - span[0]) * pgtable.uat_pgsz
					request.offset = if repeated { 31 * pgtable.uat_pgsz } else { u64(index + 1) * pgtable.uat_pgsz }
					if repeated { request.flags |= ioctl.asahi_bind_single_page }
					assert file.ioctl_gem_bind(&request) == 0
				}
				assert file.ioctl_gem_bind(bind(8, 2, 7 * pgtable.uat_pgsz)) == 0
				original := pt.leaves
				request := range_request(cut[0], cut[1])
				before_alloc := memory.calls(); before_check := gpu.mapping_checks()
				mut occupied := false
				for index in int(cut[0]) .. int(cut[1]) {
					if original[index] != 0 { occupied = true; break }
				}
				vm.inflight = 1
				assert file.ioctl_gem_bind(&request) == if occupied { -16 } else { 0 }
				assert first.references == 3 && second.references == 3 && pt.unmaps == 0
				assert memory.calls() == before_alloc && gpu.mapping_checks() == before_check && pt.leaves == original
				vm.inflight = 0; cases++
				if repeated && cut[0] == 1 && cut[1] == 17 {
					gpu.fail_mapping_checks(1)
					assert file.ioctl_gem_bind(&request) == -5
					assert first.references == 4 && second.references == 2
					assert pt.unmaps == 3, 'failed range retirement must continue other overlaps'
					cases++
				}
				assert file.ioctl_gem_bind(&request) == 0, 'range UNBIND must accept holes and surviving fragments'
				cases++
				for index in 0 .. 32 {
					expected := if u64(index) >= cut[0] && u64(index) < cut[1] { u64(0) } else { original[index] }
					assert pt.leaves[index] == expected
				}
				mut first_refs := 1; mut second_refs := 1
				for mapping in file.mappings {
					assert !mapping.retiring && mapping.size != 0
					if voidptr(mapping.obj) == voidptr(first) { first_refs++ } else { second_refs++ }
					if mapping.vm_id == 1 { assert !ranges_overlap(mapping.addr, mapping.size, request.addr, request.range) }
				}
				assert first.references == first_refs && second.references == second_refs
				assert neighbor.maps == 1 && neighbor.unmaps == 0 && neighbor.leaves[6] == second.phys_addr
				before_unmaps := pt.unmaps; after_alloc := memory.calls(); after_checks := gpu.mapping_checks()
				vm.inflight = 1
				assert file.ioctl_gem_bind(&request) == 0
				assert pt.unmaps == before_unmaps && memory.calls() == after_alloc && gpu.mapping_checks() == after_checks
				assert first.references == first_refs && second.references == second_refs && pt.maps == 3
				vm.inflight = 0
				cases++
				assert file.close() && vm.destroyed && other.destroyed && gem.live() == 0
				memory.assert_released()
			}

			// A middle cut needs two transient survivor owners while a failed
			// state check retains the original. OOM must precede every visible effect.
			mut pt := pgtable.UatPgtable{ watch_start: 0x4000 }
			mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
			mut file := GpuFile{ vms: [unsafe { &vm }] }
			file.mappings.flags |= .noslices
			mut object := gem.create(7); object.size = 16 * pgtable.uat_pgsz
			file.objects.table.add_created(object)
			mut original := bind(7, 1, 0x4000); original.range = 8 * pgtable.uat_pgsz
			if repeated { original.flags |= ioctl.asahi_bind_single_page }
			assert file.ioctl_gem_bind(&original) == 0
			file.lock.acquire()
			assert !file.reserve_mapping_slots_locked(-1)
			assert !file.reserve_mapping_slots_locked(0x7fff_ffff)
			file.lock.release()
			unsafe { file.mappings.cap = file.mappings.len }
			data := file.mappings.data; leaves := pt.leaves
			request := range_request(2, 5)
			memory.fail_allocations(true)
			before := memory.calls(); checks := gpu.mapping_checks()
			assert file.ioctl_gem_bind(&request) == -12
			memory.fail_allocations(false)
			assert memory.calls() == before + 1 && file.mappings.data == data && file.mappings.len == 1
			assert object.references == 2 && pt.unmaps == 0 && pt.leaves == leaves && gpu.mapping_checks() == checks
			assert !file.lock.is_held(); cases++
			gpu.fail_mapping_checks(1)
			assert file.ioctl_gem_bind(&request) == -5
			assert object.references == 4 && file.mappings.len == 3 && file.mappings.cap >= 3
			assert file.mappings[0].retiring && file.mappings[0].addr == request.addr && file.mappings[0].size == request.range
			assert pt.unmaps == 1 && pt.last_unmap_addr == request.addr && pt.last_unmap_size == request.range
			cases++
			inner := range_request(3, 4)
			gpu.fail_mapping_checks(1)
			assert file.ioctl_gem_bind(&inner) == -5 && object.references == 4 && pt.unmaps == 1
			assert pt.last_unmap_size == request.range; cases++
			vm.inflight = 1
			assert file.ioctl_gem_bind(&inner) == -16 && object.references == 4 && pt.unmaps == 1
			all := ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_unbind_all, vm_id: 1, handle: 7 }
			assert file.ioctl_gem_bind(&all) == -16 && object.references == 4 && pt.unmaps == 1
			vm.inflight = 0; cases += 2
			assert file.ioctl_gem_bind(&inner) == 0 && object.references == 3 && file.mappings.len == 2 && pt.unmaps == 1
			cases++
			for index in 0 .. 8 {
				assert pt.leaves[index] == if index >= 2 && index < 5 { u64(0) } else { leaves[index] }
			}
			assert file.ioctl_gem_bind(&inner) == 0; cases++
			mut replacement := bind(7, 1, inner.addr)
			replacement.offset = 8 * pgtable.uat_pgsz
			assert file.ioctl_gem_bind(&replacement) == 0 && object.references == 4; cases++
			if repeated {
				assert file.ioctl_gem_bind(&all) == 0 && object.references == 1 && file.mappings.len == 0; cases++
			} else {
				assert file.close_object_handle(7) == 0 && file.mappings.len == 0 && gem.live() == 0; cases++
			}
			mut closing_object := gem.create(9); closing_object.size = 16 * pgtable.uat_pgsz
			file.objects.table.add_created(closing_object)
			mut closing_bind := bind(9, 1, 0x4000); closing_bind.range = 8 * pgtable.uat_pgsz
			assert file.ioctl_gem_bind(&closing_bind) == 0
			unsafe { file.mappings.cap = file.mappings.len }
			gpu.fail_mapping_checks(1)
			assert file.ioctl_gem_bind(&request) == -5 && closing_object.references == 4
			gpu.fail_mapping_checks(1)
			assert !file.close() && !vm.destroyed && closing_object.references == 4
			assert file.close() && vm.destroyed && gem.live() == 0
			cases++
			memory.assert_released()
		}
	}
	println('AGX range UNBIND: ${cases} ioctl checks; holes, multiple BOs, head/tail/middle survivors, contiguous/repeated leaves, busy gates, mutation-free reservation OOM, retained split tombstones and full-range retries, replacement, UNBIND_ALL/GEM_CLOSE and freed array reservations passed')
	check_busy_unbind_all()
}

fn check_busy_unbind_all() {
	mut pt := pgtable.UatPgtable{ watch_start: 0x4000 }
	mut neighbor := pgtable.UatPgtable{ watch_start: 0x4000 }
	mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
	mut other := mmu.UatContext{ id: 2, vm_id: 2, pgtable: unsafe { &neighbor } }
	mut file := GpuFile{ vms: [unsafe { &vm }, unsafe { &other }] }
	first := gem.create(7)
	second := gem.create(8)
	file.objects.table.add_created(first)
	file.objects.table.add_created(second)
	assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
	assert file.ioctl_gem_bind(bind(8, 2, 0x4000)) == 0
	before_alloc := memory.calls()
	before_checks := gpu.mapping_checks()
	vm.inflight = 1
	mut request := ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_unbind_all, vm_id: 1, handle: 8 }
	assert file.ioctl_gem_bind(&request) == 0, 'UNBIND_ALL must ignore bindings in another VM'
	request.handle = 7
	assert file.ioctl_gem_bind(&request) == -16
	request.handle = 99
	assert file.ioctl_gem_bind(&request) == -2
	assert file.mappings.len == 2 && first.references == 2 && second.references == 2
	assert pt.unmaps == 0 && neighbor.unmaps == 0 && memory.calls() == before_alloc && gpu.mapping_checks() == before_checks
	vm.inflight = 0
	assert file.close() && vm.destroyed && other.destroyed && gem.live() == 0
	memory.assert_released()
	println('AGX legacy UNBIND_ALL: busy VM accepts an unmatched handle, protects mapped backing and rejects a missing handle')
}
