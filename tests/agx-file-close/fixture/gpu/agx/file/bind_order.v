// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.gem
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import drm.ioctl

__global bind_order_cases = 0

fn check_bind_order_result(mut file GpuFile, request &ioctl.DrmAsahiGemBind, expected int, object &gem.GemObject, pt &pgtable.UatPgtable) {
	maps, unmaps, checks := pt.maps, pt.unmaps, gpu.mapping_checks()
	assert file.ioctl_gem_bind(request) == expected, 'BIND lookup order expected ${expected}'
	assert !file.lock.is_held() && object.references == 2 && file.mappings.len == 1
	assert pt.maps == maps && pt.unmaps == unmaps && gpu.mapping_checks() == checks
	bind_order_cases++
}

fn check_bind_order() {
	gpu.set_running(true)
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		file.mappings.flags |= .noslices
		object := gem.create(7); file.objects.table.add_created(object)
		assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
		for id in [u32(0), 1, 2, ~u32(0)]! {
			for handle in [u32(0), 8, ~u32(0)]! {
				for failure in 0 .. 6 {
					mut request := bind(handle, id, 0x8000)
					match failure {
						0 {}
						1 { request.flags = 0 }
						2 { request.addr = u64(1) << 39 }
						3 { request.addr = 0 }
						4 { request.range = ~u64(0) & ~u64(0x3fff) }
						else { request.addr = vm.kernel_start }
					}
					check_bind_order_result(mut file, &request, -2, object, &pt)
				}
				for failure in 0 .. 5 {
					mut request := bind(handle, id, 0x8000)
					match failure {
						0 { request.extensions = 1 }
						1 { request.flags = ~u32(0) }
						2 { request.addr++ }
						3 { request.range++ }
						else { request.offset++ }
					}
					check_bind_order_result(mut file, &request, -22, object, &pt)
				}
			}
			for failure in 0 .. 6 {
				mut request := bind(7, id, 0x8000)
				match failure {
					0 { request.offset = object.size }
					1 { request.range = ~u64(0) & ~u64(0x3fff) }
					2 { request.flags = 0 }
					3 { request.addr = u64(1) << 39 }
					4 { request.addr = 0 }
					else { request.offset = ~u64(0) & ~u64(0x3fff) }
				}
				check_bind_order_result(mut file, &request, -22, object, &pt)
			}
			request := bind(7, id, vm.kernel_start)
			check_bind_order_result(mut file, &request, if id == 1 { -22 } else { -2 }, object, &pt)
			if id != 1 {
				normal := bind(7, id, 0x8000)
				check_bind_order_result(mut file, &normal, -2, object, &pt)
			}
		}
		vm.pgtable = unsafe { nil }
		request := bind(7, 1, 0x8000)
		check_bind_order_result(mut file, &request, -22, object, &pt)
		vm.pgtable = unsafe { &pt }
		assert file.close() && vm.destroyed && gem.live() == 0
		unsafe { file.vms.free(); file.mappings.free() }
	}
	println('AGX BIND order: ${bind_order_cases} checks; alignment/flag header before BO, missing BO before ranges/permissions/VM, BO bounds/global fields before VM, exact temporary-ref cleanup, private-hole checks and unchanged PTE/state-check/mapping state passed')
}
