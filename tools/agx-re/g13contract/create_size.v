// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_create_size_local(objects string, file string, fake string) ! {
	helper := section(objects, 'pub fn create_size_error(', 'pub struct Table {', 'GEM size error helper')!
	require_order(helper, ['if size == 0 { return -22 }', 'if size > ~u64(0) - agxvm.page_mask { return -75 }', 'return 0'],
		'Zero size is EINVAL; 16 KiB rounding overflow is EOVERFLOW')!
	require(!helper.contains('malloc') && !helper.contains('gem.'), 'Size rejection precedes backing/metadata allocation')!
	reserve := section(objects, 'pub fn (mut table Table) reserve_handle_entry()', '// Transfer the creator', 'GEM handle table storage')!
	require_order(reserve, ['return reserve_entry(mut table.objects)', 'if entries.len < entries.cap { return true }',
		'memory.malloc_packed_fallible(u64(capacity) * sizeof(T)) @[freed]',
		'if storage == unsafe { nil } { return false }', 'C.memcpy(storage, entries.data',
		'entries = replacement', 'old.free()'], 'Reserve and copy before replacing the owned handle table')!
	create := section(file, 'pub fn (mut f GpuFile) ioctl_gem_create(', 'pub fn (mut f GpuFile) ioctl_gem_mmap_offset(', 'Native checked GEM size')!
	require_order(create, ['request.flags & ~valid_flags != 0', 'f.lock.acquire()', 'defer { f.lock.release() }',
		'f.find_vm(request.vm_id) or { return -2 }', 'private_identity = vm.identity', '} else if request.vm_id != 0',
		'size_error := agxbo.create_size_error(request.size)', 'if size_error != 0 { return size_error }',
		'if !f.objects.reserve_handle_entry() { return -12 }',
		'gem.create_aligned_with_cache(request.size, pgtable.uat_pgsz, private_identity,',
		'request.flags & ioctl.asahi_gem_writeback != 0, f.objects.uses_local_handles())', 'request.handle = f.objects.add_created(obj)'],
		'Header and private VM lookup precede checked size, constructors and publication')!
	software := section(fake, 'fn (mut file FakeG17File) ioctl_gem_create(', 'fn (mut file FakeG17File) ioctl_gem_mmap_offset(', 'Fake checked GEM size')!
	require_order(software, ['file.lock.acquire()', 'defer { file.lock.release() }', 'file.find_vm(request.vm_id)', '} else if request.vm_id != 0',
		'size_error := agxbo.create_size_error(request.size)', 'if size_error != 0 { return size_error }',
		'if !file.objects.reserve_handle_entry() { return -12 }',
		'gem.create_aligned(request.size, vm_page_size)', 'file.objects.add_created(object)'],
		'Software backend shares size errors before allocation')!
}

fn check_create_size_reference(objects string, file string) ! {
	helper := section(objects, 'pub(crate) fn checked_object_size(', 'fn new_kernel_object_mapped(', 'Packaged checked GEM size')!
	require_order(helper, ['if size == 0', 'return Err(EINVAL)', 'size.checked_add(mmu::UAT_PGMSK)',
		'.map(|rounded| rounded & !mmu::UAT_PGMSK)', '.ok_or(EOVERFLOW)'], 'Packaged size errors and checked rounding')!
	create := section(file, 'pub(crate) fn gem_create(', '/// IOCTL: gem_mmap_offset:', 'Packaged checked GEM create')!
	require_order(create, ['DRM_ASAHI_GEM_VM_PRIVATE', 'return Err(EINVAL)', 'vms.get(data.vm_id.try_into()?).ok_or(ENOENT)?',
		'let size = gem::checked_object_size(data.size.try_into()?)?', 'gem::new_object(', 'data.handle = handle'],
		'Packaged private VM lookup precedes size and object construction')!
}
