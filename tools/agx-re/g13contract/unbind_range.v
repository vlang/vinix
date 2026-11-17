// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_unbind_range_local(file string) ! {
	reserve := section(file, 'fn (mut f GpuFile) reserve_mapping_slots_locked(', 'fn (f &GpuFile) mapping_survivor_count_locked(', 'Native split reservation')!
	require_order(reserve, ['needed := u64(f.mappings.len) + u64(extra)', 'needed <= u64(f.mappings.cap)',
		'needed > 0x7fff_ffff || needed > ~u64(0) / sizeof(GpuMapping)', 'mut capacity := needed',
		'if u64(f.mappings.cap) <= 0x3fff_ffff', 'doubled <= ~u64(0) / sizeof(GpuMapping)', 'bytes := capacity * sizeof(GpuMapping)',
		'memory.malloc_packed_fallible(bytes)', 'if storage == unsafe { nil } { return false }',
		'replacement.data = storage', 'replacement.len = f.mappings.len', 'replacement.cap = int(capacity)',
		'replacement.flags = .noslices', 'C.memcpy(storage, f.mappings.data',
		'mut old := unsafe { f.mappings }', 'f.mappings = replacement', 'old.free()'], 'Fallible complete array reservation and storage-only owner transfer')!
	require(!reserve.contains('gem.') && reserve.count('malloc_packed_fallible(') == 1, 'Reservation moves records without changing BO references')!
	count := section(file, 'fn (f &GpuFile) mapping_survivor_count_locked(', 'fn (mut f GpuFile) unbind_range_locked(', 'Native survivor count')!
	require_order(count, ['mapping.retiring', 'if mapping.addr < addr { fragments++ }',
		'if mapping.addr + mapping.size > end { fragments++ }', 'if fragments > 2 { return -1 }', 'return fragments'],
		'Disjoint mappings need at most two boundary survivors')!
	unmap := section(file, 'fn (mut f GpuFile) unbind_range_locked(', '// Reserve a nonzero per-open queue ID.', 'Native range removal')!
	require_order(unmap, ['fragments := f.mapping_survivor_count_locked(vm_id, addr, size)', 'if fragments < 0 { return -22 }',
		'if !f.reserve_mapping_slots_locked(fragments) { return -12 }', 'original_count := f.mappings.len',
		'for i := original_count - 1; i >= 0; i--', 'if !mapping.retiring',
		'cut_start :=', 'cut_end :=', 'if mapping.addr < cut_start', 'gem.ref_obj(mapping.obj)', 'f.mappings << GpuMapping{',
		'if cut_end < mapping_end', 'gem.ref_obj(mapping.obj)', 'f.mappings << GpuMapping{',
		'f.mappings[i].addr = cut_start', 'f.mappings[i].size = cut_end - cut_start',
		'if !f.retire_mapping_locked(i) { flush_ok = false }', 'return if flush_ok { 0 } else { -5 }'], 'Reserve transient fragments before clipped retirement; retry tombstones without resplitting')!
	require(unmap.count('gem.ref_obj(') == 2 && !unmap.contains('gem.unref(') && !unmap.contains('pt.map'), 'Survivors retain PTEs and own refs; retirement owns the only release')!
	ioctl := section(file.all_after('pub fn (mut f GpuFile) ioctl_gem_bind('), 'ioctl.asahi_bind_op_unbind {', 'ioctl.asahi_bind_op_unbind_all {', 'Native idle range dispatch')!
	require_order(ioctl, ['f.find_vm(request.vm_id)', 'agxvm.valid_bind_request(', 'katomic.load(&f.inflight_by_vm[ctx.id])', 'return -16',
		'return f.unbind_range_locked(ctx.id, request.addr, request.range)'], 'Range mutation follows VM/private validation and idle gate')!
}

fn check_unbind_range_reference(file string, mmu string) ! {
	unmap := section(file, 'pub(crate) fn do_gem_unbind(', 'pub(crate) fn unbind_gem_object(', 'Packaged range unbind')!
	require_order(unmap, ['data.addr.checked_add(data.range).ok_or(EINVAL)?', 'user_range.is_superset(range.clone())',
		'guard.get(vm_id).ok_or(ENOENT)?', 'kernel_range.overlaps(range.clone())',
		'vm.unmap_range(Some(device.as_ref().as_ref()), range.start, range.range())?'], 'Packaged validated range removal')!
	remap := section(mmu, '    fn sm_step_remap', '    /// Map', 'Packaged surviving GPUVA fragments')!
	require_order(remap, ['let orig_prot =', 'let unmap_start =', 'let unmap_end =',
		'let prev_gpuva = ctx.preallocated_gpuva()?', 'let next_gpuva = match ctx.preallocated_gpuva()',
		'self.page_table.unmap_pages(unmap_start..unmap_end)?', 'self.tlbi_range(', 'op.remap(', 'prot: Some(orig_prot)'],
		'Packaged split preallocation, hole-only PTE removal and original protection')!
}
