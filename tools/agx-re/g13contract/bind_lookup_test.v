// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_bind_lookup_guard_requires_shape_validation_and_locked_private_check() {
	repo := g13layout.repo_root()
	local := read(repo + '/kernel/gpu/agx/file/file.v')!
	pure := read(repo + '/kernel/gpu/agx/vm/vm.v')!
	reference := 'pub(crate) fn do_gem_bind( mmu::UAT_PGMSK; let bo = gem::Object::lookup_handle(file, data.handle)?;\n' +
		'data.addr.checked_add(data.range); end_off as usize > bo.size(); .user_range.is_superset(range.clone()); Must specify read or write;\n' +
		'guard.get(vm_id).ok_or(ENOENT)?; kernel_range.overlaps(range);\npub(crate) fn do_gem_unbind(\n' +
		'if data.offset != 0 { return Err(EINVAL) }; mmu::UAT_PGMSK; .user_range.is_superset(range.clone()); return Err(EINVAL);\n' +
		'guard.get(vm_id).ok_or(ENOENT)?; kernel_range.overlaps(range.clone()); return Err(EINVAL);\npub(crate) fn unbind_gem_object('
	check_bind_vm_lookup_contract(local, pure, reference)!
	for token in ['else if !agxvm.valid_bind_shape(request) { return -22 }',
		'if !agxvm.valid_bind_header(request) { return -22 }', 'ctx := f.find_vm(request.vm_id) or { gem.unref(obj); return -2 }',
		'if !agxvm.valid_bind_shape(request)', '!agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end)'] {
		if _ := check_bind_vm_lookup_contract(local.replace(token, ''), pure, reference) { assert false, token }
	}
	if _ := check_bind_vm_lookup_contract(local, pure.replace('request, 0, 0', 'request, 1, 2'), reference) { assert false }
	if _ := check_bind_vm_lookup_contract(local, pure, reference.replace('ENOENT', 'EINVAL')) { assert false }
	if _ := check_bind_vm_lookup_contract(local, pure.replace('request.flags & ~', 'request.flags != 0 && request.flags & ~'), reference) { assert false }
	lookup := 'obj := f.objects.get_ref(request.handle) or { return -2 }'
	early := local.replace(lookup, 'ctx := f.find_vm(request.vm_id) or { return -2 }\n' + lookup)
	if _ := check_bind_vm_lookup_contract(early, pure, reference) { assert false, 'early VM lookup accepted' }
}
