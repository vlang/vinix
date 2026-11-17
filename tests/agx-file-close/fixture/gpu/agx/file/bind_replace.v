// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import memory

fn check_bind_replacements() {
	gpu.set_running(true)
	mut cases := 0
	for _ in 0 .. 100 {
		for old_repeat in [false, true]! {
			for new_repeat in [false, true]! {
				for mode, flags in [ioctl.asahi_bind_read, ioctl.asahi_bind_write, ioctl.asahi_bind_read | ioctl.asahi_bind_write]! {
					for cut in [[u64(2), 4]!, [u64(0), 6]!, [u64(5), 10]!, [u64(1), 17]!,
						[u64(0), 20]!, [u64(4), 14]!, [u64(8), 12]!]! {
						mut pt := pgtable.UatPgtable{ watch_start: 0x4000 }
						mut neighbor := pgtable.UatPgtable{ watch_start: 0x4000 }
						mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
						mut other := mmu.UatContext{ id: 2, vm_id: 2, pgtable: unsafe { &neighbor } }
						mut file := GpuFile{ vms: [unsafe { &vm }, unsafe { &other }] }
						mut first := gem.create(7); first.size = 32 * pgtable.uat_pgsz
						mut second := gem.create(8); second.size = first.size; second.phys_addr = 0x800000
						mut target := gem.create(9); target.size = first.size; target.phys_addr = 0xc00000
						file.objects.table.add_created(first); file.objects.table.add_created(second); file.objects.table.add_created(target)
						for index, span in [[u64(0), 6]!, [u64(8), 12]!, [u64(14), 18]!]! {
							mut request := bind(if index == 1 { u32(8) } else { u32(7) }, 1, (span[0] + 1) * pgtable.uat_pgsz)
							request.range = (span[1] - span[0]) * pgtable.uat_pgsz
							request.flags = [ioctl.asahi_bind_read, ioctl.asahi_bind_write, ioctl.asahi_bind_read | ioctl.asahi_bind_write]![index]
							request.offset = if old_repeat { 31 * pgtable.uat_pgsz } else { u64(index + 1) * pgtable.uat_pgsz }
							if old_repeat { request.flags |= ioctl.asahi_bind_single_page }
							assert file.ioctl_gem_bind(&request) == 0
						}
						assert file.ioctl_gem_bind(bind(8, 2, 0x4000)) == 0
						old_leaves := pt.leaves; old_protection := pt.protections
						mut request := bind(9, 1, (cut[0] + 1) * pgtable.uat_pgsz)
						request.range = (cut[1] - cut[0]) * pgtable.uat_pgsz
						request.offset = if new_repeat { 31 * pgtable.uat_pgsz } else { pgtable.uat_pgsz }
						request.flags = flags | if new_repeat { ioctl.asahi_bind_single_page } else { u32(0) }
						before_alloc := memory.calls(); before_flush := gpu.flushes(); before_prepare := pt.prepares
						file.inflight_by_vm[1] = 1
						assert file.ioctl_gem_bind(&request) == -16
						assert first.references == 3 && second.references == 3 && target.references == 1
						assert pt.leaves == old_leaves && pt.protections == old_protection
						assert memory.calls() == before_alloc && gpu.flushes() == before_flush && pt.prepares == before_prepare
						file.inflight_by_vm[1] = 0; cases++
						for _ in 0 .. 2 {
							assert file.ioctl_gem_bind(&request) == 0, 'BIND must replace idle overlapping mappings'
							for index in 0 .. 32 {
								inside := u64(index) >= cut[0] && u64(index) < cut[1]
								physical := target.phys_addr + request.offset + if new_repeat { u64(0) } else { (u64(index) - cut[0]) * pgtable.uat_pgsz }
								assert pt.leaves[index] == if inside { physical } else { old_leaves[index] }
								assert pt.protections[index] == if inside { [pgtable.gpu_prot_gpu_shared_ro, pgtable.gpu_prot_gpu_shared_wo, pgtable.gpu_prot_gpu_shared_rw]![mode] } else { old_protection[index] }
							}
							mut first_refs := 1; mut second_refs := 1; mut target_refs := 1
							for mapping in file.mappings {
								assert !mapping.retiring
								if voidptr(mapping.obj) == voidptr(first) { first_refs++ }
								else if voidptr(mapping.obj) == voidptr(second) { second_refs++ }
								else { target_refs++ }
							}
							assert first.references == first_refs && second.references == second_refs && target.references == target_refs && target_refs == 2
							assert neighbor.maps == 1 && neighbor.unmaps == 0 && neighbor.leaves[0] == second.phys_addr
							cases++
						}
						assert file.close() && vm.destroyed && other.destroyed && gem.live() == 0
						memory.assert_released()
					}
				}
			}
		}
	}
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{ watch_start: 0x4000 }
		mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		mut old := gem.create(7); old.size = 16 * pgtable.uat_pgsz
		mut target := gem.create(9); target.size = old.size; target.phys_addr = 0xc00000
		file.objects.table.add_created(old); file.objects.table.add_created(target)
		mut original := bind(7, 1, 0x4000); original.range = 8 * pgtable.uat_pgsz
		assert file.ioctl_gem_bind(&original) == 0
		mut request := bind(9, 1, 3 * pgtable.uat_pgsz); request.range = 3 * pgtable.uat_pgsz
		leaves := pt.leaves
		unsafe { file.mappings.cap = file.mappings.len }
		memory.fail_allocations(true)
		prepare := pt.prepares
		assert file.ioctl_gem_bind(&request) == -12
		memory.fail_allocations(false)
		assert old.references == 2 && target.references == 1 && pt.leaves == leaves && pt.unmaps == 0 && pt.prepares == prepare
		assert file.mappings.len == 1 && file.mappings[0].size == original.range; cases++
		pt.reject_prepare = true
		assert file.ioctl_gem_bind(&request) == -12
		pt.reject_prepare = false
		assert old.references == 2 && target.references == 1 && pt.leaves == leaves && pt.unmaps == 0 && pt.maps == 1
		assert file.mappings.len == 1 && file.mappings[0].size == original.range; cases++
		gpu.fail_flushes(1)
		assert file.ioctl_gem_bind(&request) == -5
		assert old.references == 4 && target.references == 1 && file.mappings.len == 3 && pt.maps == 1 && pt.unmaps == 1; cases++
		gpu.fail_flushes(1)
		before_prepare := pt.prepares
		assert file.ioctl_gem_bind(&request) == -5
		assert old.references == 4 && target.references == 1 && pt.unmaps == 1 && pt.maps == 1 && pt.prepares == before_prepare; cases++
		assert file.ioctl_gem_bind(&request) == 0
		assert old.references == 3 && target.references == 2 && file.mappings.len == 3; cases++
		request.handle = 7
		gpu.fail_flush_after(1)
		assert file.ioctl_gem_bind(&request) == -5
		assert old.references == 4 && target.references == 1 && file.mappings.len == 3 && file.mappings[file.mappings.len - 1].retiring; cases++
		gpu.fail_flushes(1)
		assert !file.close() && !vm.destroyed && old.references == 4
		assert file.close() && vm.destroyed && gem.live() == 0
		memory.assert_released()

		mut fresh_pt := pgtable.UatPgtable{ watch_start: 0x4000 }
		mut fresh_vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &fresh_pt } }
		mut fresh := GpuFile{ vms: [unsafe { &fresh_vm }] }
		fresh_object := gem.create(7); fresh.objects.table.add_created(fresh_object)
		memory.fail_allocations(true)
		assert fresh.ioctl_gem_bind(bind(7, 1, 0x4000)) == -12
		memory.fail_allocations(false)
		assert fresh_object.references == 1 && fresh.mappings.len == 0 && fresh_pt.maps == 0 && fresh_pt.prepares == 0; cases++
		fresh_pt.reject_prepare = true
		assert fresh.ioctl_gem_bind(bind(7, 1, 0x4000)) == -12
		fresh_pt.reject_prepare = false
		assert fresh_object.references == 1 && fresh.mappings.len == 0 && fresh_pt.maps == 0; cases++
		fresh.inflight_by_vm[1] = 1
		assert fresh.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0 && fresh_object.references == 2
		fresh.inflight_by_vm[1] = 0; cases++
		assert fresh.close() && gem.live() == 0
		memory.assert_released()
	}
	println('AGX BIND replacement: ${cases} ioctl checks; idle exact/partial/multi-BO replacement, holes, protected contiguous/repeated survivors, same-BO replacement, foreign VMs, busy gate, metadata/table OOM before mutation, old/new flush failures, retained retry/close and freed reservations passed')
}
