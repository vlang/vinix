// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

fn check_repeated_bindings() {
	gpu.set_running(true)
	mut cases := 0
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, pgtable: unsafe { &pt } }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		file.mappings.flags |= .noslices
		object := gem.create(7); file.objects.table.add_created(object)
		for index, permission in [ioctl.asahi_bind_read, ioctl.asahi_bind_write, ioctl.asahi_bind_read | ioctl.asahi_bind_write]! {
			for pages in [u64(1), 2, 17]! {
				for offset in [u64(0), object.size - pgtable.uat_pgsz]! {
					mut request := bind(7, 1, 0x4000)
					request.flags = permission | ioctl.asahi_bind_single_page
					request.range = pages * pgtable.uat_pgsz; request.offset = offset
					assert file.ioctl_gem_bind(&request) == 0, 'SINGLE_PAGE must accept one backing page for a larger VA range'
					assert object.references == 2 && file.mappings.len == 1
					assert file.mappings[0].size == request.range
					assert pt.repeated && pt.last_phys == object.phys_addr + offset && pt.last_size == request.range
					assert pt.last_protection == [pgtable.gpu_prot_gpu_shared_ro, pgtable.gpu_prot_gpu_shared_wo, pgtable.gpu_prot_gpu_shared_rw]![index]
					mut remove := unbind(1, request.addr); remove.range = request.range
					before := pt.unmaps
					file.inflight_by_vm[1] = 1
					assert file.ioctl_gem_bind(&remove) == -16 && object.references == 2 && pt.unmaps == before
					file.inflight_by_vm[1] = 0
					assert file.ioctl_gem_bind(&remove) == 0 && object.references == 1 && file.mappings.len == 0
					assert pt.last_unmap_size == request.range
					cases += 3
				}
			}
		}
		for failure in 0 .. 6 {
			mut request := bind(7, 1, 0x4000)
			request.flags |= ioctl.asahi_bind_single_page; request.range = 17 * pgtable.uat_pgsz
			match failure {
				0 { request.flags = ioctl.asahi_bind_single_page }
				1 { request.offset = object.size }
				2 { request.offset = 1 }
				3 { request.range = 0 }
				4 { request.addr = vm.kernel_start - pgtable.uat_pgsz; request.range = 2 * pgtable.uat_pgsz }
				else { request.vm_id = 0 }
			}
			before := pt.maps
			assert file.ioctl_gem_bind(&request) == if failure == 5 { -2 } else { -22 }
			assert object.references == 1 && file.mappings.len == 0 && pt.maps == before && !file.lock.is_held()
			cases++
		}
		mut request := bind(7, 1, 0x4000)
		request.flags |= ioctl.asahi_bind_single_page; request.range = 17 * pgtable.uat_pgsz
		pt.reject_map = true
		assert file.ioctl_gem_bind(&request) == -12 && object.references == 1 && file.mappings.len == 0; cases++
		pt.reject_map = false
		gpu.fail_flushes(1)
		assert file.ioctl_gem_bind(&request) == -5 && object.references == 2 && file.mappings[0].retiring; cases++
		assert pt.last_unmap_size == request.range
		gpu.fail_flushes(1)
		assert !file.cleanup_closed_mappings_locked(1) && object.references == 2; cases++
		assert file.cleanup_closed_mappings_locked(1) && object.references == 1 && file.mappings.len == 0; cases++
		assert file.close() && vm.destroyed && gem.live() == 0
		unsafe { file.vms.free(); file.mappings.free() }
	}
	println('AGX SINGLE_PAGE bindings: ${cases} checks; repeated first/last BO pages across larger VA ranges, RO/WO/RW, one mapping owner, busy pins, full-range removal, shape/bounds/private-hole refusal, failed map/flush ownership and retry passed')
}
