// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_private_bo_local(file string, bo string, mmu string, gem string, drm string, identity string) ! {
	create := section(file, 'pub fn (mut f GpuFile) ioctl_gem_create(',
		'pub fn (mut f GpuFile) ioctl_gem_mmap_offset(', 'Vinix private BO creation')!
	require_order(create, ['f.lock.acquire()', 'defer { f.lock.release() }',
		'vm := f.find_vm(request.vm_id)', 'if vm.identity == 0', 'private_identity = vm.identity',
		'gem.create_aligned_with_cache(request.size, pgtable.uat_pgsz, private_identity,',
		'f.objects.add_created(obj)'], 'Vinix private BO creation')!
	require(create.count('f.lock.acquire()') == 1 && create.count('f.lock.release()') == 1,
		'Private BO VM lookup must remain locked through publication')!
	bind := section(file, 'pub fn (mut f GpuFile) ioctl_gem_bind(',
		'pub fn (f &GpuFile) ioctl_get_time(', 'Vinix private VM binding')!
	require_order(bind, ['f.lock.acquire()', 'f.objects.get_ref(request.handle)',
		'if obj.vm_private_identity != 0 && obj.vm_private_identity != ctx.identity',
		'gem.unref(obj)', 'return -22', 'pt.map('], 'Vinix private VM binding')!
	timestamps := section(file, 'pub fn (mut f GpuFile) ioctl_gem_bind_object(',
		'pub fn (mut f GpuFile) ioctl_queue_create(', 'Vinix private timestamp refusal')!
	require_order(timestamps, ['obj := f.get_object_ref(request.handle)',
		'if obj.vm_private_identity != 0 { gem.unref(obj); return -22 }',
		'gpu_manager.map_g13_timestamp_buffer'], 'Vinix private timestamp refusal')!
	importer := section(bo, 'pub fn (mut table Table) import_object(',
		'pub fn (mut table Table) authorize_mmap(', 'Vinix private import refusal')!
	require_order(importer, ['object.vm_private_identity != 0', 'return none', 'gem.ref_obj(object)'],
		'Vinix private import refusal')!
	constructor := section(gem, 'pub fn create_aligned_private(',
		'// Metadata for a host-owned resource.', 'Vinix private GEM constructor')!
	require_order(constructor, ['if identity == 0', 'return none',
		'create_object(size, alignment, false, identity, 0, false, 0)'], 'Vinix private GEM constructor')!
	require_order(gem, ['pub:\n\tvm_private_identity u64', 'fn create_object(',
		'vm_private_identity: private_identity', 'if !file_scoped { gem_objects[handle] = obj }'], 'Vinix immutable GEM domain publication')!
	prime := section(drm, 'fn ioctl_prime_handle_to_fd(', 'fn ioctl_prime_fd_to_handle(', 'Vinix private PRIME refusal')!
	require_order(prime, ['file.reserve_fd(', 'defer { file.cancel_fd_reservation(',
		'dev.driver.gem_export(dev, handle, request.handle)', 'if obj.vm_private_identity != 0',
		'put_prime_object(dev, obj)', 'return -22', 'create_prime_fd(dev, obj, request.flags,'], 'Vinix private PRIME refusal')!
	put := section(drm, 'fn put_prime_object(', 'fn create_prime_fd(', 'Vinix PRIME reference release')!
	require_order(put, ['dev.driver.gem_export_put(dev, obj)', 'gem.unref(obj)'], 'Vinix PRIME reference release')!
	require_order(identity, ['if pool.next == 0', 'return none', 'identity := pool.next',
		'pool.next = if identity == ~u64(0) { u64(0) } else { identity + 1 }', 'return identity'],
		'Vinix non-reused VM identity')!
	require(mmu.count('context_identities =') == 1, 'VM identities must have one kernel-lifetime initialization')!
	require_order(mmu, ['__global context_identity_lock', '__global context_identities = agxvm.IdentityPool{}',
		'fn allocate_context_identity()', 'context_identity_lock.acquire()',
		'defer { context_identity_lock.release() }', 'context_identities.allocate()',
		'pub fn (mut mgr UatManager) create_context(', 'identity := allocate_context_identity()',
		'mut ctx := &UatContext{', 'identity: identity', 'return ctx'], 'Vinix context incarnation')!
}

fn check_private_bo_reference(reference string) ! {
	validate := section(reference, 'pub(crate) fn validate_vm_binding(',
		'unsafe impl Send for AsahiObject', 'Asahi VM-private reservation validation')!
	require_order(validate, ['DRM_ASAHI_GEM_VM_PRIVATE != 0 && vm.is_extobj(gem)', 'return Err(EINVAL)'],
		'Asahi VM-private reservation validation')!
	create := section(reference, 'pub(crate) fn new_object(', '#[vtable]', 'Asahi private GEM creation')!
	require_order(create, ['DRM_ASAHI_GEM_VM_PRIVATE != 0) != parent_object.is_some()',
		'parent_resv_obj: parent_object', 'exportable: parent_object.is_none()'], 'Asahi private GEM creation')!
	export := section(reference, '    fn export(', 'impl AsahiObject {', 'Asahi private GEM export')!
	require_order(export, ['if !obj.exportable', 'return Err(EINVAL)', 'obj.prime_export(flags)'],
		'Asahi private GEM export')!
}
