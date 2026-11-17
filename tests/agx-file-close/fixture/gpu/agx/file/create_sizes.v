// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.bo
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

fn check_create_sizes() {
	gpu.set_running(true)
	mask := pgtable.uat_pgsz - 1
	maximum := ~u64(0) - mask
	mut cases := 0
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, vm_id: 1, identity: mmu.new_identity(), pgtable: unsafe { &pt } }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		for flags in [u32(0), ioctl.asahi_gem_writeback, ioctl.asahi_gem_vm_private,
			ioctl.asahi_gem_writeback | ioctl.asahi_gem_vm_private]! {
			vm_id := if flags & ioctl.asahi_gem_vm_private != 0 { u32(1) } else { u32(0) }
			for size in [u64(0), maximum + 1, ~u64(0)]! {
				mut request := ioctl.DrmAsahiGemCreate{ flags: flags, vm_id: vm_id, size: size, handle: 0xfeed }
				before := gem.creates()
				result := file.ioctl_gem_create(&request)
				expected := if size == 0 { -22 } else { -75 }
				assert result == expected, 'GEM size expected ${expected}, got ${result}'
				assert gem.creates() == before && gem.live() == 0
				assert request.size == size && request.handle == 0xfeed && !file.lock.is_held()
				cases++
			}
			for size in [u64(1), mask, pgtable.uat_pgsz, pgtable.uat_pgsz + 1, maximum - 1, maximum]! {
				assert bo.create_size_error(size) == 0
				mut request := ioctl.DrmAsahiGemCreate{ flags: flags, vm_id: vm_id, size: size, handle: 0xfeed }
				before := gem.creates()
				gem.fail_creates(true)
				assert file.ioctl_gem_create(&request) == -12
				gem.fail_creates(false)
				assert gem.creates() == before + 1 && gem.live() == 0
				assert request.size == size && request.handle == 0xfeed && !file.lock.is_held()
				cases++
				assert file.ioctl_gem_create(&request) == 0
				object := file.objects.table.remove(request.handle) or { panic('created size object') }
				assert object.size == (size + mask) & ~mask && object.references == 1
				assert object.vm_private_identity == if vm_id == 0 { u64(0) } else { vm.identity }
				assert object.pte_extra == if flags & ioctl.asahi_gem_writeback != 0 { u64(0) } else { u64(0x10) }
				assert request.size == size && request.handle != 0xfeed && !file.lock.is_held()
				gem.unref(object)
				assert gem.live() == 0
				cases++
			}
		}
		for size in [u64(0), maximum + 1, ~u64(0)]! {
			for missing in [u32(0), 2, ~u32(0)]! {
				mut request := ioctl.DrmAsahiGemCreate{ flags: ioctl.asahi_gem_vm_private, vm_id: missing, size: size, handle: 0xfeed }
				before := gem.creates()
				assert file.ioctl_gem_create(&request) == -2, 'private VM lookup must precede size validation'
				assert gem.creates() == before && gem.live() == 0 && request.handle == 0xfeed && request.size == size
				assert !file.lock.is_held()
				cases++
			}
			for bad_header in 0 .. 4 {
				mut request := ioctl.DrmAsahiGemCreate{ flags: ioctl.asahi_gem_vm_private, vm_id: 2, size: size, handle: 0xfeed }
				match bad_header {
					0 { request.extensions = 1 }
					1 { request.pad = 1 }
					2 { request.flags |= 4 }
					else { request.flags = 0 }
				}
				before := gem.creates()
				assert file.ioctl_gem_create(&request) == -22
				assert gem.creates() == before && gem.live() == 0 && request.handle == 0xfeed && request.size == size
				assert !file.lock.is_held()
				cases++
			}
		}
		assert !vm.destroyed && file.mappings.len == 0 && pt.maps == 0
		assert file.close() && vm.destroyed && gem.live() == 0
		unsafe { file.vms.free() }
	}
	println('AGX GEM sizes: ${cases} ioctl checks; zero EINVAL, rounding EOVERFLOW, maximum safe size, 16 KiB rounding, shared/private and writeback flags, header/VM precedence, allocator refusal, unchanged error outputs and complete object release passed')
}
