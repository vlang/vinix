// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_cpu_cache_guards_require_complete_alias_and_teardown_contract() {
	repo := g13layout.repo_root()
	gem := read(repo + '/kernel/drm/gem/gem.v')!
	bo := read(repo + '/kernel/gpu/agx/bo/bo.v')!
	file := read(repo + '/kernel/gpu/agx/file/file.v')!
	driver := read(repo + '/kernel/gpu/agx/driver/driver.v')!
	ram := read(repo + '/kernel/memory/ram_cache_arm64.v')!
	cpu := read(repo + '/kernel/aarch64/cpu/data_cache.v')!
	drm := read(repo + '/kernel/drm/drm.v')!
	mmap := read(repo + '/kernel/memory/mmap/mmap.v')!
	check_cpu_cache_local(gem, bo, file, driver, ram, cpu, drm, mmap)!
	for source, token in {'gem': 'memory.set_ram_direct_map_uncached(obj.phys_addr, obj.size, false)',
		'bo': 'return length <= object.size - (offset - base)', 'file': 'request.flags & ioctl.asahi_gem_writeback != 0, f.objects.uses_local_handles(),',
		'driver': 'mmap_retain: agx_file.retain_mmap_range_handle', 'ram': 'cpu.read_ttbr1_el1() & kernel_pte_address_mask',
		'cpu': 'if end - current <= line { break }'} {
		if _ := check_cpu_cache_local(if source == 'gem' { gem.replace(token, '') } else { gem },
			if source == 'bo' { bo.replace(token, '') } else { bo }, if source == 'file' { file.replace(token, '') } else { file },
			if source == 'driver' { driver.replace(token, '') } else { driver }, if source == 'ram' { ram.replace(token, '') } else { ram },
			if source == 'cpu' { cpu.replace(token, '') } else { cpu }, drm, mmap) { assert false, source }
	}
	if _ := check_cpu_cache_local(gem, bo, file.replace('lookup_file(handle) or { return 0 }', 'unsafe { &GpuFile(handle) }'), driver, ram, cpu, drm, mmap) { assert false }
	if _ := check_cpu_cache_local(gem.replace('gem_objects[obj.handle] = unsafe { nil }', ''), bo, file, driver, ram, cpu, drm, mmap) { assert false }
	if _ := check_cpu_cache_local(gem.replace('memory.free(storage)', ''), bo, file, driver, ram, cpu, drm, mmap) { assert false }
}

fn test_cpu_cache_reference_requires_inverse_writeback_flag() {
	source := 'pub(crate) fn new_object( shmem::Object::<AsahiObject>::new( map_wc: flags & uapi::drm_asahi_gem_flags_DRM_ASAHI_GEM_WRITEBACK == 0, #[vtable]'
	check_cpu_cache_reference(source)!
	if _ := check_cpu_cache_reference(source.replace('== 0', '!= 0')) { assert false }
}

fn test_g13_remap_growth_checks_the_retained_resource_before_building_destination() {
	repo := g13layout.repo_root()
	linux := read(repo + '/kernel/memory/mmap/linux.v')!
	remap := section(linux, 'mut source_resource := global.resource', 'destination := mmap_with_credit(', 'mremap growth')!
	require_order(remap, ['source_handle_ref(source_handle)', 'resource.retain_resource(mut retained)',
		'pagemap.l.release()', 'if new_length > old_length', '!resource.mapping_can_grow(mut source_resource)',
		'return errno.err, errno.efault', 'if new_length <= old_length', 'destination_flags |= map_fixed'],
		'Check growth against the retained resource before constructing the destination')!
	driver := read(repo + '/kernel/gpu/agx/driver/driver.v')!
	assert driver.contains('mmap_no_expand: cfg.gpu_gen == .g13')
	mknod := read(repo + '/kernel/fs/mknod.v')!
	forwarding := section(mknod, 'fn (mut this MknodDeviceResource) mapping_can_grow(',
		'fn (mut this MknodDeviceResource) retain_mapping_range(', 'A device node forwards its backing policy')!
	assert forwarding.contains('return resource.mapping_can_grow(mut backing)')
}
