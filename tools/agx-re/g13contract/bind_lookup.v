// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_bind_vm_lookup_contract(local string, pure string, reference string) ! {
	shape := section(pure, 'pub fn valid_bind_shape(', 'pub fn valid_bind_request(', 'Native global bind validation')!
	require(shape.contains('return valid_bind_request(request, 0, 0)'), 'Shape validation excludes no private reservation')!
	bind := section(local, 'pub fn (mut f GpuFile) ioctl_gem_bind(', 'pub fn (f &GpuFile) ioctl_get_time(', 'Native bind VM lookup')!
	require_order(bind, ['if !agxvm.valid_bind_shape(request) { return -22 }', 'f.lock.acquire()',
		'defer { f.lock.release() }', 'ctx := f.find_vm(request.vm_id) or { return -2 }',
		'ctx.pgtable == unsafe { nil }', '!agxvm.valid_bind_request(request, ctx.kernel_start, ctx.kernel_end)',
		'return -22', 'mut pt := unsafe { ctx.pgtable }', 'match request.op'],
		'Validate global fields, return ENOENT for absent VM, then validate the private reservation under lock')!
	remote := section(reference, 'pub(crate) fn do_gem_unbind(', 'pub(crate) fn unbind_gem_object(', 'Packaged unbind VM lookup')!
	require_order(remote, ['if data.offset != 0', 'return Err(EINVAL)', 'mmu::UAT_PGMSK',
		'.user_range.is_superset(range.clone())', 'return Err(EINVAL)', 'guard.get(vm_id).ok_or(ENOENT)?',
		'kernel_range.overlaps(range.clone())', 'return Err(EINVAL)'], 'Packaged global validation precedes VM lookup and private-hole validation')!
	remote_bind := section(reference, 'pub(crate) fn do_gem_bind(', 'pub(crate) fn do_gem_unbind(', 'Packaged bind VM lookup')!
	require(remote_bind.contains('guard.get(vm_id).ok_or(ENOENT)?'), 'Packaged bind returns ENOENT for an absent VM')!
}
