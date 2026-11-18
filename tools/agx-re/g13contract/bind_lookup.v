// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_bind_vm_lookup_contract(local string, pure string, reference string) ! {
	shape := section(pure, 'pub fn valid_bind_shape(', 'pub fn valid_bind_request(', 'Native global bind validation')!
	require(shape.contains('return valid_bind_request(request, 0, 0)'), 'Shape validation excludes no private reservation')!
	bind := section(local, 'pub fn (mut f GpuFile) ioctl_gem_bind(', 'pub fn (f &GpuFile) ioctl_get_time(', 'Native bind VM lookup')!
	require_order(bind, ['if request.op == ioctl.asahi_bind_op_bind', 'if !agxvm.valid_bind_header(request) { return -22 }',
		'else if !agxvm.valid_bind_shape(request) { return -22 }', 'f.lock.acquire()', 'defer { f.lock.release() }', 'match request.op'],
		'Validate BIND header or complete unbind shape before serialized lookups')!
	local_bind := section(bind, 'ioctl.asahi_bind_op_bind {', 'ioctl.asahi_bind_op_unbind {', 'Native BO-first bind')!
	require_order(local_bind, ['obj := f.objects.get_ref(request.handle) or { return -2 }',
		'backing_bytes := agxvm.bind_backing_size(request)',
		'if request.offset > obj.size || backing_bytes > obj.size - request.offset', 'gem.unref(obj)', 'return -22',
		'if !agxvm.valid_bind_shape(request)', 'gem.unref(obj)', 'return -22',
		'ctx := f.find_vm(request.vm_id) or { gem.unref(obj); return -2 }',
		'ctx.pgtable == unsafe { nil }', '!agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end)',
		'obj.vm_private_identity', 'gem.unref(obj)', 'return -22', 'mut pt := unsafe { ctx.pgtable }'],
		'BO identity/range and global fields precede VM lookup; each rejection returns the temporary BO owner')!
	require(local_bind.count('f.find_vm(') == 1, 'BIND must not probe a VM before its BO')!
	header := section(pure, 'pub fn valid_bind_header(', 'pub fn valid_bind_shape(', 'Native pre-BO header')!
	require_order(header, ['request.extensions == 0', 'request.op == ioctl.asahi_bind_op_bind',
		'request.range != 0',
		'request.flags & ~(ioctl.asahi_bind_read | ioctl.asahi_bind_write | ioctl.asahi_bind_single_page) == 0',
		'(request.addr | request.range | request.offset) & page_mask == 0'], 'BIND header checks alignment and supported flag bits')!
	dispatch := section(reference, 'pub(crate) fn do_gem_bind_unbind(', 'pub(crate) fn do_gem_bind(', 'Packaged nonempty bind dispatch')!
	require_order(dispatch, ['if data.range == 0', 'return Err(EINVAL)',
		'Self::do_gem_bind(device, vm_id, data, file)'], 'Packaged zero-length BIND rejects before BO lookup')!
	require(!header.contains('valid_user_range(') && !header.contains('request.flags != 0'), 'Global ranges and nonzero permissions follow BO lookup')!
	for op in ['ioctl.asahi_bind_op_unbind {', 'ioctl.asahi_bind_op_unbind_all {'] {
		part := bind.all_after(op)
		require_order(part, ['ctx := f.find_vm(request.vm_id) or { return -2 }', 'ctx.pgtable == unsafe { nil }',
			'!agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end)'], 'Unbind keeps locked VM/private-window validation')!
	}
	remote := section(reference, 'pub(crate) fn do_gem_unbind(', 'pub(crate) fn unbind_gem_object(', 'Packaged unbind VM lookup')!
	require_order(remote, ['if data.offset != 0', 'return Err(EINVAL)', 'mmu::UAT_PGMSK',
		'.user_range.is_superset(range.clone())', 'return Err(EINVAL)', 'guard.get(vm_id).ok_or(ENOENT)?',
		'kernel_range.overlaps(range.clone())', 'return Err(EINVAL)'], 'Packaged global validation precedes VM lookup and private-hole validation')!
	remote_bind := section(reference, 'pub(crate) fn do_gem_bind(', 'pub(crate) fn do_gem_unbind(', 'Packaged bind VM lookup')!
	require_order(remote_bind, ['mmu::UAT_PGMSK', 'let bo = gem::Object::lookup_handle(file, data.handle)?',
		'data.addr.checked_add(data.range)', 'end_off as usize > bo.size()', '.user_range.is_superset(range.clone())',
		'Must specify read or write', 'guard.get(vm_id).ok_or(ENOENT)?', 'kernel_range.overlaps(range)'],
		'Packaged BIND validates its header, BO, global range and permissions before the VM/private reservation')!
}

fn check_modern_bind_staging_contract(local string, file string, uaccess string, kvec string, layout string) ! {
	bind := section(file, 'pub(crate) fn vm_bind(', 'fn vm_bind_g17(', 'Asahi G13 VM_BIND staging')!
	require_order(bind, ['if data.stride == 0 || data.pad != 0', 'return Err(EINVAL)',
		'if let Some(limit) = reg_data.gpu.bind_batch_limit()', 'data.userptr == 0',
		'return Self::vm_bind_g17(data, file)', 'let mut vec = KVec::new()',
		'.checked_mul(usize::try_from(data.num_binds)?)', 'reader.read_all(&mut vec, GFP_KERNEL)?',
		'reader.read_up_to(data.stride as usize)?', 'Self::do_gem_bind_unbind('],
		'Asahi legacy GPU VM_BIND copies the full batch before applying records')!
	read_all := section(uaccess, 'pub fn read_all<A: Allocator>(mut self', 'pub fn strcpy_into_buf', 'Asahi UserSliceReader')!
	require_order(read_all, ['buf.reserve(len, flags)?', 'self.read_raw('], 'Asahi reserves before validating the source pointer')!
	reserve := section(kvec, 'pub fn reserve(&mut self', 'A::realloc(', 'Asahi KVec reservation')!
	require(reserve.contains('ArrayLayout::new(new_cap).map_err(|_| AllocError)?')
		&& layout.contains('const ISIZE_MAX: usize = isize::MAX as usize;')
		&& layout.contains('match len.checked_mul(core::mem::size_of::<T>())')
		&& layout.contains('Some(size) if size <= ISIZE_MAX'), 'Asahi caps vector capacity at isize::MAX')!
	vinix := section(local, 'pub fn (mut f GpuFile) ioctl_modern_vm_bind(', 'fn modern_get_params_handler(', 'Vinix modern VM_BIND staging')!
	require_order(vinix, ['if data.stride == 0 || data.pad != 0 { return -22 }', 'if data.num_binds == 0 { return 0 }',
		'bytes := u64(data.stride) * u64(data.num_binds)',
		'if data.userptr == 0 || bytes - 1 > ~data.userptr {',
		'manager := gpu.get_global_manager() or { return -14 }',
		'if manager.hw_config.gpu_gen != .g13 { return -14 }',
		'if bytes > u64(max_i64) { return -12 }',
		'storage := memory.malloc_packed_fallible(bytes)', 'if storage == unsafe { nil } { return -12 }',
		'defer { memory.free(storage) }', 'if !usercopy.copy_from_user(storage, data.userptr, bytes) { return -14 }',
		'code := f.ioctl_gem_bind(unsafe { &old })'], 'Vinix allocates and copies the strided batch before any mapping mutation')!
	require(vinix.count('data.userptr') == 3, 'The full copy decides source pointer errors on G13')!
}
