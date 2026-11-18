module file

import drm
import drm.gem
import gpu.agx.bo
import memory
import memory.mmap

fn check_cpu_mapping_policy() {
	for reversed in [false, true] {
		mut file := GpuFile{}
		mut first := gem.create_aligned_with_cache(0x10000, 0x4000, 0, reversed, false) or { panic('first GEM') }
		mut second := gem.create_aligned_with_cache(0x10000, 0x4000, 0, !reversed, false) or { panic('second GEM') }
		file.objects.add_created(first)
		file.objects.add_created(second)
		first_offset := u64(first.handle) * 0x10000
		second_offset := u64(second.handle) * 0x10000
		assert second_offset == first_offset + first.size
		// These are opaque open-handle keys, deliberately unrelated to &file.
		handle := voidptr(u64(0x1234_5000) + if reversed { u64(0x4000) } else { u64(0) })
		file_map[u64(handle)] = unsafe { &file }
		assert mmap_attributes_handle(unsafe { nil }, handle, first_offset) == 0
		assert !retain_mmap_range_handle(unsafe { nil }, handle, first_offset, first.size)
		_ = file.objects.table.authorize_mmap(first.handle) or { panic('first authorization') }
		_ = file.objects.table.authorize_mmap(second.handle) or { panic('second authorization') }
		for object in [first, second] {
			offset := gem.create_mmap_offset(object)
			assert mmap_attributes_handle(unsafe { nil }, handle, offset) == object.pte_extra
			assert mmap_attributes_handle(unsafe { nil }, handle, offset + object.size - 1) == object.pte_extra
			assert retain_mmap_range_handle(unsafe { nil }, handle, offset, object.size)
			assert retain_mmap_range_handle(unsafe { nil }, handle, offset + 0x4000, object.size - 0x4000)
			assert !retain_mmap_range_handle(unsafe { nil }, handle, offset, 0)
			assert !retain_mmap_range_handle(unsafe { nil }, handle, offset + object.size - 1, 2)
		}
		assert !retain_mmap_range_handle(unsafe { nil }, handle, first_offset, first.size + second.size)
		assert !retain_mmap_range_handle(unsafe { nil }, handle, ~u64(0), 2)
		assert mmap_attributes_handle(unsafe { nil }, voidptr(u64(0x9999)), first_offset) == 0
		assert !retain_mmap_range_handle(unsafe { nil }, voidptr(u64(0x9999)), first_offset, first.size)
		assert mmap_attributes_handle(unsafe { nil }, unsafe { nil }, first_offset) == 0
		assert !retain_mmap_range_handle(unsafe { nil }, unsafe { nil }, first_offset, first.size)
		// GEM_CLOSE drops the handle reference while mmap authorization retains it.
		removed := file.objects.remove(first.handle) or { panic('first close') }
		gem.unref(removed)
		assert first.references == 1 && mmap_attributes_handle(unsafe { nil }, handle, first_offset) == first.pte_extra
		assert retain_mmap_range_handle(unsafe { nil }, handle, first_offset, first.size)
		file_map.delete(u64(handle))
		file.objects.release_all()
		assert gem.live() == 0 && !file.lock.is_held()
	}
	println('AGX CPU mmap policy: opaque handle lookup, WRITEBACK selection, authorized whole-BO bounds, adjacent opposite policies, rejected crossings/overflow and GEM_CLOSE retention passed')
}

fn check_cpu_mmap_revocation() {
	driver := drm.DrmDriver{gem_close_request: close_gem_request, mmap_admit: admit_mmap_range_handle,
		mmap_retain: retain_mmap_range_handle, mmap_release: release_mmap_range_handle}
	mut device := drm.DrmDevice{driver: unsafe { &driver }}
	other_device := drm.DrmDevice{driver: unsafe { &driver }}
	key := u64(0x4c30)
	handle := voidptr(key)
	for _ in 0 .. 64 {
		mut file := GpuFile{dev: unsafe { &device }, objects: Objects{table: bo.new_table(true)}}
		file_map[key] = unsafe { &file }
		object := gem.create_aligned_with_cache(0x10000, 0x4000, 0, false, true,
			mmap_device: unsafe { u64(&device) }) or { panic('GEM backing') }
		name := file.objects.add_created(object)
		offset := file.authorize_mmap(name) or { panic('GEM mmap offset') }
		assert name == 1 && object.references == 1
		foreign := voidptr(key + 1)
		assert drm.admit_mapping(&device, foreign, offset, 0x4000, mmap.map_shared) == -13
		assert drm.admit_mapping(&device, foreign, offset, 0x4000, mmap.map_private) == -13
		assert drm.admit_mapping(&other_device, foreign, offset, 0x4000, mmap.map_shared) == -22
		assert drm.admit_mapping(&device, foreign, offset, 0x14000, mmap.map_shared) == -22
		assert drm.admit_mapping(&device, handle, offset + 0x4000, 0x4000, mmap.map_shared) == -22
		assert drm.admit_mapping(&device, handle, offset, 0x14000, mmap.map_shared) == -22
		assert !drm.retain_mapping(&device, handle, offset, 0x4000)
		memory.fail_allocations(true)
		assert drm.admit_mapping(&device, handle, offset, 0x8000, mmap.map_private) == -22
		assert drm.admit_mapping(&device, handle, offset, 0x8000, mmap.map_shared) == -12
		memory.fail_allocations(false)
		assert object.references == 1 && memory.outstanding() == 0
		assert drm.admit_mapping(&device, handle, offset, 0x8000, mmap.map_shared) == 0
		assert drm.admit_mapping(&device, handle, offset, 0x4000, mmap.map_private) == -22
		assert drm.admit_mapping(&device, handle, offset, 0x4000, mmap.map_shared) == 0
		device.registered = false
		assert drm.admit_mapping(&device, handle, offset, 0x4000, mmap.map_private) == -19
		device.registered = true
		assert object.references == 2
		gem.ref_obj(object) // An export can outlive the handle and all VMAs.
		assert close_wire_gem(&device, key, name, 0) == 0
		assert file.authorize_mmap(name) == none
		assert drm.admit_mapping(&device, handle, offset, 0x4000, mmap.map_shared) == -13
		assert drm.retain_mapping(&device, handle, offset, 0x8000)
		assert drm.retain_mapping(&device, handle, offset + 0x4000, 0x4000)
		assert !drm.retain_mapping(&device, handle, offset + 0xc000, 0x8000)
		assert mmap_handle(&device, handle, offset / 0x4000 + 1, 0) == voidptr(object.phys_addr + 0x4000)
		assert mmap_attributes_handle(&device, handle, offset) == object.pte_extra
		for index in 0 .. 2 {
			drm.release_mapping(&device, handle, offset + u64(index) * 0x4000, 0x4000)
			drm.release_mapping(&device, handle, offset, 0x8000)
		}
		assert object.references == 1 && !drm.retain_mapping(&device, handle, offset, 0x4000)
		assert drm.admit_mapping(&device, handle, offset, 0x4000, mmap.map_shared) == -13
		assert mmap_handle(&device, handle, offset / 0x4000, 0) == unsafe { nil }
		assert (gem_import_handler(&device, handle, object) or { panic('GEM reimport') }) == name
		assert drm.admit_mapping(&device, handle, offset, 0x4000, mmap.map_shared) == 0
		gem.unref(object)
		assert close_wire_gem(&device, key, name, 0) == 0 && gem.live() == 1
		drm.release_mapping(&device, handle, offset, 0x4000)
		assert gem.live() == 0 && drm.admit_mapping(&device, handle, offset, 0x4000, mmap.map_shared) == -22
		file_map.delete(key)
		assert file.close()
		memory.assert_released()
	}
	println('G13 CPU mmap: 64 lifetimes cover private mapping refusal, errno precedence, admission OOM, revocation, retained pins, reimport and final VMA release')
}
