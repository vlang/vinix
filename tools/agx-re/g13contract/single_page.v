// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_single_page_local(header string, pure string, file string, page_table string, fake string) ! {
	exact_line(header, 'pub const asahi_bind_single_page = u32(1) << 3', 'Native SINGLE_PAGE bit')!
	backing := section(pure, 'pub fn bind_backing_size(', 'pub fn valid_bind_request(', 'Native repeated backing size')!
	require(backing.contains('request.flags & ioctl.asahi_bind_single_page != 0 { page_size } else { request.range }'),
		'Repeated BIND must consume one full backing page')!
	require(pure.contains('request.flags & (ioctl.asahi_bind_read | ioctl.asahi_bind_write) != 0'), 'SINGLE_PAGE alone grants no access')!
	bind := section(file, 'pub fn (mut f GpuFile) ioctl_gem_bind(', 'pub fn (f &GpuFile) ioctl_get_time(', 'Native repeated mapping')!
	require_order(bind, ['backing_bytes := agxvm.bind_backing_size(request)', 'backing_bytes > obj.size - request.offset',
		'mapped := if request.flags & ioctl.asahi_bind_single_page != 0',
		'pt.map_repeated_page(request.addr, obj.phys_addr + request.offset, request.range, protection)',
		'else { pt.map(request.addr, obj.phys_addr + request.offset, request.range, protection) }',
		'if !mapped', 'gem.unref(obj)', 'return -12', 'f.insert_mapping_locked(mapping_index, GpuMapping{', 'size: request.range'],
		'Repeated/contiguous dispatch preserves virtual size and mapping ownership')!
	repeat := section(page_table, 'pub fn (mut pt UatPgtable) map_repeated_page(', '// Change only the access/cache attributes', 'Repeated PTE writer')!
	require_order(repeat, ['size - 1 > ~iova', 'pt.lock.acquire()', 'defer {', 'pt.invalidate_range_locked(iova, size)',
		'pt.lock.release()', 'pages := size / uat_pgsz', 'pt.map_page_locked(iova + i * uat_pgsz, phys, prot)',
		'for j := u64(0); j < i; j++ { pt.unmap_page_locked(iova + j * uat_pgsz) }', 'return false'],
		'Constant physical backing, rollback and one deferred range invalidation')!
	require(!repeat.contains('phys +') && !repeat.contains('malloc'), 'Repeated mapping must not advance backing or allocate temporary owners')!
	software := fake.all_after('fn (mut file FakeG17File) ioctl_gem_bind(')
	require_order(software, ['if !agxvm.valid_bind_request(', 'if request.flags & ioctl.asahi_bind_single_page != 0',
		'file.lock.release()', 'return -95', 'file.cleanup_closed_objects_locked()', 'file.objects.get_ref(request.handle)'],
		'Software backend rejects repeated mappings before effects')!
}

fn check_single_page_reference(header string, mmu string) ! {
	exact_line(header, 'DRM_ASAHI_BIND_SINGLE_PAGE = (1L << 3),', 'Packaged SINGLE_PAGE bit')!
	bind := section(mmu, 'pub(crate) fn bind_object<', '/// Spend the binding generation', 'Packaged repeated mapping')!
	require_order(bind, ['single_page: bool', 'let (flags, gem_range) = if single_page', 'GpuVaFlag::REPEAT',
		'UAT_PGSZ as u32', 'let req = OpMapRequest', 'range: size', 'gem_offset: offset', 'gem_range', 'flags', '.sm_map(req)'],
		'Packaged SINGLE_PAGE repeats one UAT page across the virtual range')!
}
