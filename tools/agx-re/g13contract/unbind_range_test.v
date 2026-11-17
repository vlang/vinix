// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_unbind_range_guards_require_reservation_and_retained_fragment_ownership() {
	file := read(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	check_unbind_range_local(file)!
	for token in ['needed > ~u64(0) / sizeof(GpuMapping)', 'replacement.flags = .noslices', 'old.free()',
		'if !f.reserve_mapping_slots_locked(fragments) { return -12 }', 'original_count := f.mappings.len',
		'gem.ref_obj(mapping.obj)', 'f.mappings[i].size = cut_end - cut_start', 'return f.unbind_range_locked(ctx.id, request.addr, request.range)'] {
		if _ := check_unbind_range_local(file.replace(token, '')) { assert false, token }
	}
	if _ := check_unbind_range_local(file.replace('if !mapping.retiring {', 'if true {')) { assert false, 're-splitting pending retirement' }
	if _ := check_unbind_range_local(file.replace('gem.ref_obj(mapping.obj)', 'gem.unref(mapping.obj)')) { assert false, 'dropping surviving backing' }
}
