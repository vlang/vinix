// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_bind_replacement_guards_require_fallible_preparation_and_owner_cleanup() {
	repo := g13layout.repo_root()
	file := read(repo + '/kernel/gpu/agx/file/file.v')!
	page_table := read(repo + '/kernel/gpu/agx/pgtable/pgtable.v')!
	check_bind_replace_local(file, page_table)!
	for token in ['fragments + 1', 'if !pt.prepare_map_range(request.addr, request.range)',
		'if retired != 0 { gem.unref(obj); return retired }'] {
		if _ := check_bind_replace_local(file.replace(token, ''), page_table) { assert false, token }
	}
	overlap := 'replacing := f.has_mapping_overlap_locked(vm_slot, request.addr, request.range)\n'
	if _ := check_bind_replace_local(file.replace(overlap, overlap + '\t\t\tif replacing && katomic.load(&ctx.inflight) != 0 { gem.unref(obj); return -16 }\n'), page_table) {
		assert false, 'busy replacement refusal'
	}
	for token in ['size - 1 > ~iova', 'defer { pt.lock.release() }', 'pt.get_pte(address, allocate)',
		'if unsafe { first[index] } != 0 { return -16 }',
		'address += chunk', 'cpu.dsb_sy()', 'memory.pmm_alloc_aligned_fallible(',
		'if l1_entry == 0', 'if l2_entry == 0',
		'l1_entry & uat_pte_page == uat_pte_page', 'l2_entry & uat_pte_page == uat_pte_page'] {
		if _ := check_bind_replace_local(file, page_table.replace(token, '')) { assert false, token }
	}
	mmu := read(repo + '/kernel/gpu/agx/mmu/mmu.v')!
	check_fixed_map_local(page_table, mmu)!
	for token in ['if vacancy != 0 { return vacancy }', 'if prepared != 0 { return prepared }'] {
		if _ := check_fixed_map_local(page_table.replace(token, ''), mmu) { assert false, token }
	}
	if _ := check_fixed_map_local(page_table, mmu.replace('return pt.map_new_status(iova, phys, size, prot)', 'return if pt.map(iova, phys, size, prot) { 0 } else { -12 }')) {
		assert false, 'G13 bypasses fixed-map preparation'
	}
}

fn test_bind_replacement_reference_requires_table_preallocation_before_mapping() {
	source := 'pub(crate) fn bind_object< let mut resources = VmOpResources { preallocated_gpuvas: [] }; inner.page_table.alloc_pages(addr..(addr + size))?; let req = OpMapRequest {}; vm_exec.unique_gpuvm.sm_map(req)\n/// Spend the binding generation'
	check_bind_replace_reference(source)!
	if _ := check_bind_replace_reference(source.replace('inner.page_table.alloc_pages(addr..(addr + size))?', '')) { assert false }
}
