// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

fn check_zero_bind_ranges() {
	gpu.set_running(true); gpu.available(true)
	mut cases := 0
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		file.mappings.flags |= .noslices
		object := gem.create(7); file.objects.table.add_created(object)
		assert file.ioctl_gem_bind(bind(7, 1, 0x4000)) == 0
		maps, unmaps, checks, lookups := pt.maps, pt.unmaps, gpu.mapping_checks(), object_ref_lookups
		for id in [u32(0), 1, 2, 64, ~u32(0)]! {
			for handle in [u32(0), 7, 8, ~u32(0)]! {
				for flags in [u32(0), ioctl.asahi_bind_read, ioctl.asahi_bind_write,
					ioctl.asahi_bind_read | ioctl.asahi_bind_write,
					ioctl.asahi_bind_read | ioctl.asahi_bind_single_page, ~u32(0)]! {
					for address in [u64(0), 0x4000, 0x8000, vm.kernel_start, u64(1) << 39, ~u64(0)]! {
						for offset in [u64(0), 0x4000, 1]! {
							request := ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_bind,
								flags: flags, handle: handle, vm_id: id, addr: address, offset: offset }
							before := request
							result := file.ioctl_gem_bind(unsafe { &request })
							assert result == -22, 'empty BIND must return EINVAL before BO/VM lookup'
							assert request == before && !file.lock.is_held()
							assert object_ref_lookups == lookups && object.references == 2
							assert file.mappings.len == 1 && file.mappings[0].addr == 0x4000 && !file.mappings[0].retiring
							assert pt.maps == maps && pt.unmaps == unmaps && gpu.mapping_checks() == checks
							cases++
						}
					}
				}
			}
		}
		// Empty UNBIND already fails. Legacy UNBIND_ALL deliberately carries
		// no VA range, so its zero encoding must still remove the live mapping.
		zero_unbind := ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_unbind, vm_id: 1, addr: 0x4000 }
		assert file.ioctl_gem_bind(&zero_unbind) == -22 && object_ref_lookups == lookups; cases++
		all := ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_unbind_all, vm_id: 1, handle: 7 }
		assert file.ioctl_gem_bind(&all) == 0 && file.mappings.len == 0 && object.references == 1; cases++
		mut positive := bind(7, 1, 0x8000); positive.flags |= ioctl.asahi_bind_single_page
		assert file.ioctl_gem_bind(&positive) == 0 && object.references == 2 && file.mappings.len == 1; cases++
		assert file.close() && vm.destroyed && gem.live() == 0
	}
	println('AGX zero-length BIND: ${cases} ioctl checks; EINVAL before BO lookup across existing/missing handles and VMs, flags/addresses/offsets, unchanged request/PTE/flush/owner state, empty UNBIND refusal and nonempty/SINGLE_PAGE/zero-encoded UNBIND_ALL controls passed')
}
