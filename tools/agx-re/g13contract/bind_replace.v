// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_bind_replace_local(file string, page_table string) ! {
	bind := section(file, 'pub fn (mut f GpuFile) ioctl_gem_bind(', 'ioctl.asahi_bind_op_unbind {', 'Native BIND replacement')!
	require_order(bind, ['vm_slot := ctx.id', 'if !f.cleanup_closed_mappings_locked(ctx)',
		'replacing := f.has_mapping_overlap_locked(vm_slot, request.addr, request.range)', 'if replacing && katomic.load(&ctx.inflight)',
		'gem.unref(obj)', 'return -16',
		'fragments := f.mapping_survivor_count_locked(vm_slot, request.addr, request.range)',
		'if fragments < 0 { gem.unref(obj); return -22 }', 'if !f.reserve_mapping_slots_locked(fragments + 1)',
		'gem.unref(obj)', 'return -12', 'if !pt.prepare_map_range(request.addr, request.range)',
		'gem.unref(obj)', 'return -12', 'if replacing {',
		'retired := f.unbind_range_locked(vm_slot, request.addr, request.range)',
		'if retired != 0 { gem.unref(obj); return retired }', 'mapped := if', 'if !mapped',
		'gem.unref(obj)', 'return -12', 'f.mappings << GpuMapping{', 'vm_id: vm_slot', 'obj: obj',
		'if !finish_file_mapping(false)',
		'f.mappings[f.mappings.len - 1].retiring = true'],
		'Prepare transient survivor/new metadata and all tables before old retirement; return temporary new owner on failure')!
	prepare := section(page_table, 'pub fn (mut pt UatPgtable) prepare_map_range(', '// Map a contiguous range', 'Native table preparation')!
	require_order(prepare, ['size == 0 || (iova | size) & uat_pg_mask != 0 || size - 1 > ~iova',
		'pt.lock.acquire()', 'defer { pt.lock.release() }', 'offset < size', 'offset += uat_pgsz',
		'pt.get_pte(iova + offset, true) or { return false }', 'return true'], 'Locked complete-page preparation without rounded-size overflow')!
	for token in ['map_page', 'unmap_page', 'invalidate_', '*pte'] { require(!prepare.contains(token), 'Preparation must preserve leaves: ' + token)! }
	allocator := section(page_table, 'pub fn alloc_table_page(', '// Free a 16 KiB page table page.', 'Fallible table allocation')!
	require(allocator.contains('memory.pmm_alloc_aligned_fallible(') && !allocator.contains('memory.pmm_alloc_aligned('),
		'Table OOM must return through the fallible walker rather than panic')!
}

fn check_bind_replace_reference(mmu string) ! {
	bind := section(mmu, 'pub(crate) fn bind_object<', '/// Spend the binding generation', 'Packaged BIND preparation')!
	require_order(bind, ['let mut resources = VmOpResources', 'preallocated_gpuvas:',
		'inner.page_table.alloc_pages(addr..(addr + size))?', 'let req = OpMapRequest', 'vm_exec.unique_gpuvm.sm_map(req)'],
		'Packaged BIND preallocates GPUVA nodes and tables before GPUVM replacement')!
}
