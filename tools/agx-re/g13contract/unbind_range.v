// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_unbind_range_local(file string) ! {
	lookup := section(file, 'fn (f &GpuFile) mapping_index_locked(', 'fn (mut f GpuFile) insert_mapping_locked(', 'Native mapping lookup')!
	require_order(lookup, ['for low < high', 'mapping := f.mappings[middle]',
		'mapping.vm_id < vm_id || (mapping.vm_id == vm_id && mapping.addr < addr)',
		'low = middle + 1', 'high = middle', 'return low'], 'Locate mappings in VM and VA order')!
	insert := section(file, 'fn (mut f GpuFile) insert_mapping_locked(', 'fn (mut f GpuFile) reserve_mapping_slots_locked(', 'Native mapping insertion')!
	require_order(insert, ['f.mappings << mapping', 'if index < last',
		'C.memmove(&f.mappings[index + 1], &f.mappings[index]', 'f.mappings[index] = mapping'],
		'Insert in order and move existing owners with their records')!
	require(!insert.contains('gem.') && !insert.contains('malloc'), 'Existing mapping owners move without new references or allocations')!
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
		'if !f.reserve_mapping_slots_locked(fragments) { return -12 }', 'mut index := f.mapping_index_locked(vm_id, addr)',
		'previous.vm_id == vm_id && previous.addr + previous.size > addr', 'index--',
		'mut first := index', 'defer {', 'for retired in first .. index', 'gem.unref(f.mappings[retired].obj)',
		'f.mappings.delete_many(first, index - first)',
		'for index < f.mappings.len', 'if mapping.vm_id != vm_id || mapping.addr >= end { break }', 'if !mapping.retiring',
		'cut_start :=', 'cut_end :=', 'f.mappings[index].addr = cut_start', 'f.mappings[index].size = cut_end - cut_start',
		'if mapping.addr < cut_start', 'gem.ref_obj(mapping.obj)', 'f.insert_mapping_locked(index, GpuMapping{', 'first++', 'index++',
		'if cut_end < mapping_end', 'gem.ref_obj(mapping.obj)', 'f.insert_mapping_locked(index + 1, GpuMapping{',
		'if !f.confirm_mapping_retirement_locked(index) { return -5 }', 'index++', 'return 0'],
		'Reserve fragments, retire in VA order and stop before editing subsequent ranges on failure')!
	require(unmap.count('gem.ref_obj(') == 2 && unmap.count('gem.unref(') == 1 && !unmap.contains('pt.map'),
		'Survivors retain their PTEs and owners, and only the successful prefix releases its references')!
	overlap := section(file, 'fn ranges_overlap(', '// GPU-only GEM mappings', 'Native mapping overlap')!
	require_order(overlap, ['return first_addr < second_addr + second_size && second_addr < first_addr + first_size',
		'fn (f &GpuFile) has_mapping_overlap_locked(', 'for mapping in f.mappings',
		'if mapping.vm_id == vm_id && ranges_overlap(mapping.addr, mapping.size, addr, size)', 'return true', 'return false'],
		'Half-open overlap test uses internal VM identity')!
	require(!overlap.contains('mapping.retiring'), 'Overlap test includes retained retirements')!
	dispatch := file.all_after('pub fn (mut f GpuFile) ioctl_gem_bind(')
	range := section(dispatch, 'ioctl.asahi_bind_op_unbind {', 'ioctl.asahi_bind_op_unbind_all {', 'Native range dispatch')!
	require_order(range, ['f.find_vm(request.vm_id)', 'agxvm.valid_bind_request(',
		'return f.unbind_range_locked(ctx.id, request.addr, request.range)'], 'Range unbind runs while jobs run, as on Asahi G13')!
	require(!range.contains('inflight'), 'Range unbind does not wait for jobs')!
	all := section(dispatch, 'ioctl.asahi_bind_op_unbind_all {', 'pub fn (f &GpuFile) ioctl_get_time(', 'Native legacy unbind-all dispatch')!
	require_order(all, ['f.find_vm(request.vm_id)', 'agxvm.valid_bind_request(', 'obj := f.objects.get_ref(request.handle)',
		'for i := f.mappings.len - 1; i >= 0; i--',
		'if mapping.vm_id == ctx.id && voidptr(mapping.obj) == voidptr(obj)',
		'if !f.retire_mapping_locked(i)', 'gem.unref(obj)', 'return if retired { 0 } else { -5 }'],
		'Legacy unbind-all retires only matching records and returns the temporary GEM reference')!
	require(!all.contains('inflight'), 'Legacy unbind-all does not wait for jobs')!
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
