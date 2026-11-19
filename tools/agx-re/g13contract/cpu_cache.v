// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_cpu_cache_local(gem string, bo string, file string, driver string, ram string, cpu string, drm string, mmap string) ! {
	create := section(file, 'pub fn (mut f GpuFile) ioctl_gem_create(', 'pub fn (mut f GpuFile) ioctl_gem_mmap_offset(', 'Native CPU cache policy')!
	require_order(create, ['size_error := agxbo.create_size_error(request.size)',
		'gem.create_aligned_with_cache(request.size, pgtable.uat_pgsz, private_identity,',
		'request.flags & ioctl.asahi_gem_writeback != 0, f.objects.uses_local_handles(),', 'mmap_device: u64(f.dev))', 'f.objects.add_created(obj)'], 'Native WRITEBACK and registry selection before publication')!
	constructor := section(gem, 'pub fn create_aligned_with_cache(', '// Metadata for a host-owned resource.', 'GEM CPU cache constructor')!
	require(constructor.contains('create_object(size, alignment, false, identity, if writeback { u64(0) } else { memory.pte_uncached }, file_scoped, registration.mmap_device, true)'), 'WRITEBACK must select cacheable aliases; only AGX objects may scatter')!
	allocation := section(gem, 'fn create_object(', '// Destroy a GEM object:', 'GEM unpublished cache preparation')!
	require_order(allocation, ['memory.malloc_packed_fallible(sizeof(GemObject))', 'if storage == unsafe { nil } { return none }',
		'memory.pmm_alloc_aligned_fallible', 'if !external && phys == unsafe { nil }',
		'if room && scatter && alignment == page_size && pages > 1', 'page_list = alloc_scattered_pages(pages, pte_extra)',
		'if page_list == unsafe { nil }', 'memory.free(storage)',
		'if phys != unsafe { nil } && pte_extra & memory.pte_uncached != 0',
		'if !memory.set_ram_direct_map_uncached(u64(phys), aligned_size, true)', 'memory.pmm_free(phys, pages)',
		'memory.free(storage)', 'return none', 'gem_objects_lock.acquire()', 'if !file_scoped {', 'i < gem_max_handles',
		'if handle == 0 { publishable = false }', 'aligned_size > u64(-1) - next_mmap_offset', 'if !publishable {',
		'gem_objects_lock.release()', 'release_unpublished_backing(phys, page_list, pages, pte_extra)', 'memory.free(storage)', 'return none',
		'next_mmap_offset += aligned_size', '*obj = GemObject{', 'pte_extra:   pte_extra',
		'vm_private_identity: private_identity', 'file_scoped: file_scoped', 'if !file_scoped { gem_objects[handle] = obj }',
		'gem_objects_lock.release()'], 'Allocate and prepare backing before the registry lock; publish only globally named objects in the registry')!
	require(!allocation.all_before('gem_objects_lock.acquire()').contains('gem_objects['), 'Nothing touches the registry before its lock')!
	unpublished := section(gem, 'fn release_unpublished_backing(', 'pub fn destroy(', 'Unpublished backing release')!
	require_order(unpublished, ['free_scattered_pages(list, page_count, pte_extra)', 'return', 'if phys == unsafe { nil } { return }',
		'memory.set_ram_direct_map_uncached(u64(phys), page_count * page_size, false)', 'panic(', 'memory.pmm_free(phys, page_count)'],
		'Unpublished backing gets its cacheable policy back before PMM reuse')!
	destroy := section(gem, 'pub fn destroy(', '// Look up a GEM object', 'GEM final cache restoration')!
	require_order(destroy, ['if !obj.file_scoped && obj.handle < gem_max_handles', 'gem_objects_lock.acquire()', 'gem_objects[obj.handle] = unsafe { nil }', 'gem_objects_lock.release()',
		'if obj.pages != unsafe { nil }', 'free_scattered_pages(obj.pages, obj.size / page_size, obj.pte_extra)',
		'obj.phys_addr != 0 && !obj.external && obj.pte_extra & memory.pte_uncached != 0',
		'memory.set_ram_direct_map_uncached(obj.phys_addr, obj.size, false)',
		'panic(', 'memory.pmm_free(voidptr(obj.phys_addr), pages)'], 'Remove the namespace entry, restore before PMM reuse; keep external apertures outside ownership')!
	scattered := section(gem, 'fn alloc_scattered_pages(', '// Look up a GEM object', 'GEM scattered backing')!
	require_order(scattered, ['page := memory.pmm_alloc_fallible(1)', 'free_scattered_pages(list, index, pte_extra)', 'return none',
		'memory.set_ram_direct_map_uncached(u64(page), page_size, true)', 'memory.pmm_free(page, 1)', 'free_scattered_pages(list, index, pte_extra)',
		'unsafe { list[index] = u64(page) }', 'fn free_scattered_pages(',
		'memory.set_ram_direct_map_uncached(page, page_size, false)', 'panic(', 'memory.pmm_free(voidptr(page), 1)', 'memory.free(voidptr(list))'],
		'Scattered pages take the uncached policy before publication and get the cacheable one back before PMM reuse')!
	release := section(gem, 'pub fn unref(', '// Return (or lazily create)', 'GEM final reference release')!
	require_order(release, ['if !katomic.dec(mut rc)', 'destroy(obj)', 'if obj.external || obj.file_scoped { memory.free(voidptr(obj)) }'],
		'Only the final owner releases file-scoped metadata after backing')!
	range := section(bo, 'pub fn (table &Table) valid_mmap_range(', '// Remove a file handle', 'Homogeneous authorized mmap range')!
	require_order(range, ['if length == 0 || offset > ~u64(0) - length', 'table.mmap_objects',
		'offset >= base && offset - base < object.size', 'return length <= object.size - (offset - base)'], 'One authorized object per VMA')!
	attributes := section(bo, 'pub fn (table &Table) mmap_attributes(', '// A VMA records', 'Authorized mapping attributes')!
	require_order(attributes, ['table.mmap_objects', 'offset >= base && offset - base < object.size', 'return object.pte_extra'], 'Authorized object cache policy')!
	for name, fallback in {'mmap_attributes_handle': '0', 'retain_mmap_range_handle': 'false'} {
		callback := section(file, 'pub fn ' + name + '(', '\n}', 'Opaque mmap callback')!
		require(callback.contains('lookup_file(handle) or { return ' + fallback + ' }') && !callback.contains('&GpuFile(handle)'), 'Mmap callback must resolve opaque Handle: ' + name)!
	}
	admission := section(file, 'pub fn admit_mmap_range_handle(', 'pub fn release_mmap_range_handle(', 'New mmap admission')!
	require_order(admission, ['if dev == unsafe { nil } || !dev.is_registered() { return -19 }', 'lookup_file(handle) or {',
		'gem.file_mmap_offset_exists(u64(dev), offset, length)', 'file.admit_mmap_range(offset, length, shared)'], 'Check registration before resolving the file and offset')!
	require(driver.contains('mmap_attributes: agx_file.mmap_attributes_handle')
		&& driver.contains('mmap_admit: agx_file.admit_mmap_range_handle')
		&& driver.contains('mmap_retain: agx_file.retain_mmap_range_handle')
		&& driver.contains('mmap_release: agx_file.release_mmap_range_handle'), 'Register CPU cache policy, range admission and backing lifetime hooks')!
	node_admit := section(drm, 'fn (mut this DrmNode) admit_mapping_range(', 'fn (mut this DrmNode) mapping_can_grow(', 'DRM mapping admission')!
	require_order(node_admit, ['!this.dev.is_registered()', 'errno.set(errno.enodev)', 'return false',
		'this.dev.driver.mmap_admit(', 'return this.retain_mapping_range('], 'Registration gates both DRM mapping admission paths')!
	growth := section(drm, 'fn (mut this DrmNode) mapping_can_grow(', 'fn (mut this DrmNode) retain_mapping_range(', 'DRM mapping growth')!
	require_order(growth, ['this.dev.is_registered()', '!this.dev.driver.mmap_no_expand'], 'A DRM mapping can grow only while its device is registered and permits growth')!
	lifetime := section(drm, 'fn (mut this DrmNode) retain_mapping_range(', 'fn (mut this DrmNode) read(', 'DRM mapping lifetime')!
	require(!lifetime.contains('.is_registered()'), 'Existing mappings can retain and release backing after unregister')!
	prime := section(drm, 'fn (mut this GemPrimeResource) mapping_attributes(', 'fn (mut this GemPrimeResource) read(', 'PRIME CPU policy')!
	require(prime.contains('this.obj.pte_extra'), 'PRIME must retain the object policy')!
	require_order(mmap, ['handle_ref(range_handle)', 'if options.inherit_mapping_ref', 'resource.retain_mapping_range(',
		'resource.admit_mapping_range(', 'if !mapping_retained', 'resource.mapping_attributes(', 'pte_extra: extra_pte'], 'Pin Handle and validate complete VMA before recording attributes')!
	require_order(ram, ['if !vmm_initialised', 'cpu.read_ttbr1_el1() & kernel_pte_address_mask',
		'kernel_pagemap.l.acquire()', 'defer { kernel_pagemap.l.release() }',
		'kernel_pagemap.kernel_virt2pte(page + higher_half, false) or { return false }',
		'old & arm64_pte_valid', 'old & kernel_pte_address_mask != page', 'old & arm64_pte_ap_ro',
		'old & (u64(7) << 2) != expected_attr', 'cpu.clean_invalidate_data_cache_to_poc(',
		'else { cpu.dsb_sy() }', 'install_arm64_pte(mut entry, page + higher_half, new_pte, true)',
		'cpu.dsb_sy()', 'cpu.isb()', 'return true'], 'Complete leaf validation, clean, BBM and completion before reuse')!
	require(ram.count('kernel_virt2pte(page + higher_half, false)') == 2 && !ram.contains('kernel_virt2pte(page + higher_half, true)'), 'RAM retag must not allocate tables')!
	require(cpu.contains('mrs value, ctr_el0') && cpu.contains('dc civac, address'), 'Native cache maintenance instructions changed')!
	loop := cpu.all_after('pub fn clean_invalidate_data_cache_to_poc(')
	require_order(loop, ['if length == 0 { return }', 'address > ~u64(0) - length',
		'u64(4) << ((read_ctr_el0() >> 16) & 15)', 'dsb_sy()',
		'clean_invalidate_data_cache_line(current)', 'if end - current <= line { break }', 'current += line', 'dsb_sy()'], 'Cache-line geometry, full span and wrap-safe iteration')!
}

fn check_cpu_cache_reference(gem string) ! {
	create := section(gem, 'pub(crate) fn new_object(', '#[vtable]', 'Packaged user GEM CPU policy')!
	require_order(create, ['shmem::Object::<AsahiObject>::new(', 'map_wc: flags & uapi::drm_asahi_gem_flags_DRM_ASAHI_GEM_WRITEBACK == 0,'], 'Packaged WRITEBACK inverts the default write-combining policy')!
}
