// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_create_size_guards_reject_wrong_errno_boundary_and_allocation_order() {
	repo := g13layout.repo_root()
	objects := read(repo + '/kernel/gpu/agx/bo/bo.v')!
	file := read(repo + '/kernel/gpu/agx/file/file.v')!
	fake := read(repo + '/kernel/gpu/agx/fake/driver.v')!
	check_create_size_local(objects, file, fake)!
	for token in ['return -22', 'return -75', 'size > ~u64(0) - agxvm.page_mask'] {
		if _ := check_create_size_local(objects.replace(token, ''), file, fake) { assert false, token }
	}
	for token in ['size_error := agxbo.create_size_error(request.size)', 'if size_error != 0 { return size_error }'] {
		if _ := check_create_size_local(objects, file.replace(token, ''), fake) { assert false, token }
		if _ := check_create_size_local(objects, file, fake.replace(token, '')) { assert false, token }
	}
	check := 'size_error := agxbo.create_size_error(request.size)'
	early := file.replace(check, '').replace('mut private_identity := u64(0)', check + '\n\tmut private_identity := u64(0)')
	if _ := check_create_size_local(objects, early, fake) { assert false, 'size check moved before VM lookup' }
}

fn test_create_size_reference_requires_zero_error_and_overflow_checked_rounding() {
	objects := 'pub(crate) fn checked_object_size( if size == 0 { return Err(EINVAL) }; size.checked_add(mmu::UAT_PGMSK).map(|rounded| rounded & !mmu::UAT_PGMSK).ok_or(EOVERFLOW) }\nfn new_kernel_object_mapped('
	file := 'pub(crate) fn gem_create( DRM_ASAHI_GEM_VM_PRIVATE; return Err(EINVAL); vms.get(data.vm_id.try_into()?).ok_or(ENOENT)?; let size = gem::checked_object_size(data.size.try_into()?)?; gem::new_object(; data.handle = handle;\n/// IOCTL: gem_mmap_offset:'
	check_create_size_reference(objects, file)!
	for token in ['return Err(EINVAL)', 'size.checked_add(mmu::UAT_PGMSK)', '.ok_or(EOVERFLOW)'] {
		if _ := check_create_size_reference(objects.replace(token, ''), file) { assert false, token }
	}
}
