// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_unbind_range_guards_require_reservation_and_retained_fragment_ownership() {
	file := read(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	check_unbind_range_local(file)!
	for token in ['needed > ~u64(0) / sizeof(GpuMapping)', 'replacement.flags = .noslices', 'old.free()',
		'if !f.reserve_mapping_slots_locked(fragments) { return -12 }', 'mut index := f.mapping_index_locked(vm_id, addr)',
		'C.memmove(&f.mappings[index + 1], &f.mappings[index]', 'if !f.confirm_mapping_retirement_locked(index) { return -5 }',
		'f.mappings.delete_many(first, index - first)', 'first++',
		'gem.ref_obj(mapping.obj)', 'f.mappings[index].size = cut_end - cut_start', 'return f.unbind_range_locked(ctx.id, request.addr, request.range)',
		'return if f.has_mapping_overlap_locked(ctx.id, request.addr, request.range) { -16 } else { 0 }',
		'if mapping.vm_id == ctx.id && voidptr(mapping.obj) == voidptr(obj)', 'if busy {'] {
		if _ := check_unbind_range_local(file.replace(token, '')) { assert false, token }
	}
	if _ := check_unbind_range_local(file.replace('if !mapping.retiring {', 'if true {')) { assert false, 're-splitting pending retirement' }
	if _ := check_unbind_range_local(file.replace('gem.ref_obj(mapping.obj)', 'gem.unref(mapping.obj)')) { assert false, 'dropping surviving backing' }
	if _ := check_unbind_range_local(file.replace('if mapping.vm_id == vm_id && ranges_overlap', 'if !mapping.retiring && mapping.vm_id == vm_id && ranges_overlap')) {
		assert false, 'ignoring retained retirements'
	}
}
