// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

__global bind_lookup_cases = 0

fn check_bind_lookup(mut file GpuFile, request &ioctl.DrmAsahiGemBind, expected int, object &gem.GemObject, pt &pgtable.UatPgtable) {
	maps, unmaps, flushes := pt.maps, pt.unmaps, gpu.flushes()
	assert file.ioctl_gem_bind(request) == expected, 'bind VM lookup expected ${expected}'
	assert !file.lock.is_held() && object.references == 2 && file.mappings.len == 1
	assert pt.maps == maps && pt.unmaps == unmaps && gpu.flushes() == flushes
	bind_lookup_cases++
}

fn check_bind_vm_lookup() {
	gpu.set_running(true)
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
		mut neighbor_vm := mmu.UatContext{ id: 2, vm_id: 2 }
		mut neighbor := GpuFile{ vms: [unsafe { &neighbor_vm }] }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		file.mappings.flags |= .noslices
		object := gem.create(7); file.objects.table.add_created(object)
		assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
		for op in [ioctl.asahi_bind_op_bind, ioctl.asahi_bind_op_unbind, ioctl.asahi_bind_op_unbind_all]! {
			base := if op == ioctl.asahi_bind_op_bind { bind(7, 1, 0x8000) }
				else if op == ioctl.asahi_bind_op_unbind { unbind(1, 0x8000) }
				else { ioctl.DrmAsahiGemBind{ op: op, handle: 7, vm_id: 1 } }
			for id in [u32(0), 2, 64, ~u32(0)]! {
				mut request := base; request.vm_id = id
				check_bind_lookup(mut file, &request, -2, object, &pt)
				for invalid in 0 .. 8 {
					request = base; request.vm_id = id
					match invalid {
						0 { request.extensions = 1 }
						1 { request.op = ~u32(0) }
						2 { request.flags = ~u32(0) }
						3 { request.offset = 1 }
						4 { request.range = 1 }
						5 { request.addr = 1 }
						6 { request.range = ~u64(0) & ~u64(0x3fff) }
						else { request.addr = u64(1) << 39 }
					}
					check_bind_lookup(mut file, &request, -22, object, &pt)
				}
				if op != ioctl.asahi_bind_op_unbind_all {
					request = base; request.vm_id = id; request.addr = vm.kernel_start
					// A private hole can only be checked after finding its VM.
					check_bind_lookup(mut file, &request, -2, object, &pt)
				}
			}
			mut request := base
			if op != ioctl.asahi_bind_op_unbind_all {
				request.addr = vm.kernel_start
				check_bind_lookup(mut file, &request, -22, object, &pt)
			}
			request = base; vm.pgtable = unsafe { nil }
			check_bind_lookup(mut file, &request, -22, object, &pt)
			vm.pgtable = unsafe { &pt }
		}
		assert !neighbor_vm.destroyed && neighbor.vms.len == 1 && file.vms.len == 1
		assert file.close() && neighbor.close() && vm.destroyed && neighbor_vm.destroyed && gem.live() == 0
		unsafe { file.vms.free(); file.mappings.free(); neighbor.vms.free() }
	}
	println('AGX bind VM lookup: ${bind_lookup_cases} checks; ENOENT for missing/foreign-file VM names across BIND/UNBIND/UNBIND_ALL, malformed-request precedence, global versus private ranges, invalid present VM state, unchanged PTE/flush/reference counts and live neighbors passed')
}
