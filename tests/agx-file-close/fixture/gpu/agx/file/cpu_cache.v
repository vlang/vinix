module file

import drm.gem

fn check_cpu_mapping_policy() {
	for reversed in [false, true] {
		mut file := GpuFile{}
		mut first := gem.create_aligned_with_cache(0x10000, 0x4000, 0, reversed) or { panic('first GEM') }
		mut second := gem.create_aligned_with_cache(0x10000, 0x4000, 0, !reversed) or { panic('second GEM') }
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
