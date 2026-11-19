// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

// A BO backed by single pages maps one physically contiguous run at a time.
// When a later run fails, the runs already mapped are removed and the BIND
// publishes nothing.
fn check_scattered_bindings() {
	gpu.set_running(true)
	page := pgtable.uat_pgsz
	// Pages 0 and 1 are adjacent; pages 2 and 3 stand apart: three runs.
	mut list := [u64(0x800000), 0x804000, 0x900000, 0xa00000]!
	mut cases := 0
	for _ in 0 .. 100 {
		mut pt := pgtable.UatPgtable{watch_start: 0x4000}
		mut vm := mmu.UatContext{id: 1, vm_id: 1, pgtable: unsafe { &pt }}
		mut file := GpuFile{vms: [unsafe { &vm }]}
		file.mappings.flags |= .noslices
		mut object := gem.create(7)
		object.phys_addr = 0
		object.pages = unsafe { &list[0] }
		file.objects.table.add_created(object)

		mut request := bind(7, 1, 0x4000)
		request.range = 4 * page
		assert file.ioctl_gem_bind(&request) == 0
		assert pt.maps == 3 && object.references == 2 && file.mappings.len == 1
		for index in 0 .. 4 { assert pt.leaves[index] == list[index] }
		mut remove := unbind(1, 0x4000)
		remove.range = 4 * page
		assert file.ioctl_gem_bind(&remove) == 0 && object.references == 1
		cases += 2

		// SINGLE_PAGE repeats the one page the list holds at its offset.
		mut single := bind(7, 1, 0x4000)
		single.flags |= ioctl.asahi_bind_single_page
		single.offset = 2 * page
		single.range = 3 * page
		assert file.ioctl_gem_bind(&single) == 0 && pt.repeated && pt.last_phys == list[2]
		mut remove_single := unbind(1, 0x4000)
		remove_single.range = 3 * page
		assert file.ioctl_gem_bind(&remove_single) == 0 && object.references == 1
		cases++

		// The second run fails: the first run comes back out.
		pt.reject_map_after = 1
		maps := pt.maps
		unmaps := pt.unmaps
		assert file.ioctl_gem_bind(&request) == -12
		assert pt.maps == maps + 2 && pt.unmaps == unmaps + 1
		assert pt.last_unmap_addr == 0x4000 && pt.last_unmap_size == 2 * page
		assert file.mappings.len == 0 && object.references == 1
		for index in 0 .. 4 { assert pt.leaves[index] == 0 }
		pt.reject_map_after = -1
		cases++

		object.pages = unsafe { nil }
		assert file.close() && vm.destroyed && gem.live() == 0
		unsafe { file.vms.free(); file.mappings.free() }
	}
	// A timestamp range is mapped as one run. One crossing a gap between runs
	// is refused as out of memory before it reaches the GPU manager; one
	// inside a run maps.
	for _ in 0 .. 50 {
		mut file := GpuFile{registration_manager: gpu.registration_manager()}
		mut bo := gem.create(9900)
		bo.phys_addr = 0
		bo.pages = unsafe { &list[0] }
		file.objects.add_created(bo)
		maps := gpu.maps()
		mut across := timestamp_bind(bo.handle, 0, 0, 3 * page, ioctl.asahi_bind_object_usage_timestamps)
		assert file.ioctl_gem_bind_object(unsafe { &across }) == -12
		assert gpu.maps() == maps && bo.references == 1 && !file.lock.is_held()
		mut within := timestamp_bind(bo.handle, 0, 0, 2 * page, ioctl.asahi_bind_object_usage_timestamps)
		assert file.ioctl_gem_bind_object(unsafe { &within }) == 0 && gpu.maps() == maps + 1
		mut release := timestamp_unbind(within.object_handle)
		assert file.ioctl_gem_bind_object(unsafe { &release }) == 0
		bo.pages = unsafe { nil }
		assert file.close()
		cases += 2
	}
	println('AGX scattered BIND: ${cases} checks; three-run mapping, SINGLE_PAGE from the page list, rollback of a failed later run and one-run timestamp ranges passed')
}
