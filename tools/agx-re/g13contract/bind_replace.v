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
		'pt.lock.acquire()', 'defer { pt.lock.release() }', 'table_span := u64(1) << uat_middle_shift',
		'mut address := iova', 'mut bytes_left := size', 'pt.get_pte(address, true) or { return false }',
		'chunk := table_span - (address & (table_span - 1))', 'if bytes_left <= chunk { return true }',
		'bytes_left -= chunk', 'address += chunk'], 'Prepare each touched leaf table under lock without adding a wrapping end address')!
	for token in ['map_page', 'unmap_page', 'invalidate_', '*pte'] { require(!prepare.contains(token), 'Preparation must preserve leaves: ' + token)! }
	allocator := section(page_table, 'pub fn alloc_table_page(', '// Free a 16 KiB page table page.', 'Fallible table allocation')!
	require(allocator.contains('memory.pmm_alloc_aligned_fallible(') && !allocator.contains('memory.pmm_alloc_aligned('),
		'Table OOM must return through the fallible walker rather than panic')!
	walk := section(page_table, 'pub fn (pt &UatPgtable) get_pte(', '// Map a single', 'Native table walk')!
	require_order(walk, ['if l1_entry == 0', 'l2_table := alloc_table_page() or { return none }', 'l2_phys = u64(l2_table)',
		'cpu.dsb_sy()', 'l1_virt[l1_idx] = l2_phys | uat_pte_valid | uat_pte_table',
		'} else if l1_entry & uat_pte_page == uat_pte_page {', 'l2_phys = l1_entry & pt.oas_mask & ~uat_pg_mask',
		'} else {\n\t\treturn none\n\t}', 'l2_entry := unsafe', 'if l2_entry == 0',
		'l3_table := alloc_table_page() or { return none }', 'l3_phys = u64(l3_table)',
		'cpu.dsb_sy()', 'l2_virt[l2_idx] = l3_phys | uat_pte_valid | uat_pte_table',
		'} else if l2_entry & uat_pte_page == uat_pte_page {', 'l3_phys = l2_entry & pt.oas_mask & ~uat_pg_mask',
		'} else {\n\t\treturn none\n\t}', 'l3_virt := unsafe'],
		'Publish children after initialization in empty entries and follow only table descriptors')!
}

fn check_table_preparation_reference(page_table string, mem string) ! {
	walk := section(page_table, 'fn walk_inner<F>(', 'fn free_table(', 'Packaged page-table walk')!
	require_order(walk, ['if upte_val == 0 && alloc', 'let pt_page = Page::alloc_page(GFP_KERNEL | __GFP_ZERO)?',
		'crate::mem::sync();', 'upte.store(upte_val, Ordering::Relaxed);',
		'if upte_val & PTE_TYPE_BITS == PTE_TYPE_LEAF_TABLE', 'Ok(Some(upte_val & oas_mask',
		'Unexpected Table PTE value', 'Ok(None)', 'if pt_addr[level].is_none()',
		'let count = (((end - iova) >> UAT_PGBIT) as usize).min(max_count)',
		'let block = 1 << (UAT_PGBIT + UAT_LVBIT);', 'iova = align(iova + 1, block);'],
		'Asahi synchronizes each zeroed child and walks one span per leaf table')!
	require_order(page_table, ['pub(crate) fn alloc_pages(', 'self.with_pages(iova_range, true, false, |_, _| Ok(()))'],
		'Asahi BIND preallocates intermediate tables without editing leaves')!
	require_order(mem, ['pub(crate) fn sync()', 'asm!("dsb sy")'], 'Asahi child-table publication uses a full-system barrier')!
}

fn check_bind_replace_reference(mmu string) ! {
	bind := section(mmu, 'pub(crate) fn bind_object<', '/// Spend the binding generation', 'Packaged BIND preparation')!
	require_order(bind, ['let mut resources = VmOpResources', 'preallocated_gpuvas:',
		'inner.page_table.alloc_pages(addr..(addr + size))?', 'let req = OpMapRequest', 'vm_exec.unique_gpuvm.sm_map(req)'],
		'Packaged BIND preallocates GPUVA nodes and tables before GPUVM replacement')!
}
