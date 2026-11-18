module g13contract

import g13layout
import os

fn test_private_domains_reject_reused_contexts_and_ownership_drift() {
	repo := g13layout.repo_root()
	file := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
	bo := os.read_file(repo + '/kernel/gpu/agx/bo/bo.v')!
	mmu := os.read_file(repo + '/kernel/gpu/agx/mmu/mmu.v')!
	gem := os.read_file(repo + '/kernel/drm/gem/gem.v')!
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	identity := os.read_file(repo + '/kernel/gpu/agx/vm/identity.v')!
	check_private_bo_local(file, bo, mmu, gem, drm, identity)!
	for broken in [file.replace('private_identity = vm.identity', 'private_identity = u64(vm.id)'),
		file.replace('obj.vm_private_identity != ctx.identity', 'obj.vm_private_identity != u64(ctx.id)'),
		file.replace('if obj.vm_private_identity != 0 { gem.unref(obj); return -22 }', ''),
		file.replace('defer { f.lock.release() }', 'f.lock.release()')] {
		if _ := check_private_bo_local(broken, bo, mmu, gem, drm, identity) { assert false }
	}
	for broken in [gem.replace('vm_private_identity: private_identity', 'vm_private_identity: 0'),
		gem.replace('pub:\n\tvm_private_identity', 'pub mut:\n\tvm_private_identity'),
		gem.replace('create_object(size, alignment, false, identity, 0, false)', 'create_object(size, alignment, false, 0, 0, false)')] {
		if _ := check_private_bo_local(file, bo, mmu, broken, drm, identity) { assert false }
	}
	if _ := check_private_bo_local(file, bo.replace('object.vm_private_identity != 0', 'false'),
		mmu, gem, drm, identity) { assert false }
	for broken in [drm.replace('if obj.vm_private_identity != 0', 'if false'),
		drm.replace('else { gem.unref(obj) }', 'else {}'),
		drm.replace('dev.driver.gem_export_put(dev, obj)', 'skip_put()')] {
		if _ := check_private_bo_local(file, bo, mmu, gem, broken, identity) { assert false }
	}
	for broken in [mmu.replace('identity := allocate_context_identity()', 'identity := u64(i)'),
		mmu + '\ncontext_identities = agxvm.IdentityPool{}'] {
		if _ := check_private_bo_local(file, bo, broken, gem, drm, identity) { assert false }
	}
	if _ := check_private_bo_local(file, bo, mmu, gem, drm,
		identity.replace('pool.next = if identity == ~u64(0) { u64(0) } else { identity + 1 }',
			'pool.next = identity + 1')) { assert false }
}

fn test_private_reference_requires_reservation_parent_and_nonexportable_policy() {
	reference := 'pub(crate) fn validate_vm_binding(\n' +
		'DRM_ASAHI_GEM_VM_PRIVATE != 0 && vm.is_extobj(gem) { return Err(EINVAL); }\n' +
		'unsafe impl Send for AsahiObject\npub(crate) fn new_object(\n' +
		'DRM_ASAHI_GEM_VM_PRIVATE != 0) != parent_object.is_some()\n' +
		'parent_resv_obj: parent_object, exportable: parent_object.is_none()\n' +
		'#[vtable]\n    fn export(\nif !obj.exportable { return Err(EINVAL); }\n' +
		'obj.prime_export(flags)\nimpl AsahiObject {'
	check_private_bo_reference(reference)!
	for token in ['DRM_ASAHI_GEM_VM_PRIVATE != 0 && vm.is_extobj(gem)',
		'parent_resv_obj: parent_object', 'exportable: parent_object.is_none()', 'if !obj.exportable'] {
		if _ := check_private_bo_reference(reference.replace(token, '')) { assert false, token }
	}
}
