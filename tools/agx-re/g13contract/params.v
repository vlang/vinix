// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_params_copy_local(native string, fake string, helper string) ! {
	for source, marker in {native: 'pub fn (f &GpuFile) ioctl_get_params(', fake: 'fn (file &FakeG17File) ioctl_get_params('} {
		query := section(source, marker, 'ioctl_vm_create(', 'Native/fake global parameter query')!
		require_order(query, ['request := unsafe { data }', 'request.extensions != 0 || request.param_group != 0 || request.pad != 0',
			'return -22', 'params :=', 'return agxparams.copy_global(request, unsafe { &params })'],
			'Parameter queries validate the header before a single shared bounded copy')!
		require(!query.contains('request.size =') && !query.contains('supported_size') && !query.contains('request.pointer == 0'),
			'Queries must keep size input-only and allow zero/null bounded copies')!
	}
	query := section(native, 'pub fn (f &GpuFile) ioctl_get_params(', 'pub fn (mut f GpuFile) ioctl_vm_create(', 'Native global lookup')!
	require_order(query, ['return -22', 'manager := f.registration_manager', 'if manager == unsafe { nil } { return -19 }', 'params := make_global_params(manager)', 'agxparams.copy_global('],
		'Invalid headers precede device lookup; missing device precedes copying')!
	require_order(helper, ['pub fn copy_global(', 'supported := u64(sizeof(ioctl.DrmAsahiParamsGlobal))',
		'bytes := if request.size < supported { request.size } else { supported }',
		'if !usercopy.copy_to_user(request.pointer, voidptr(value), bytes) { return -14 }', 'return 0'],
		'Exactly one checked copy of min(input size, supported size), with ordinary partial-fault behavior')!
	require(helper.count('usercopy.copy_to_user(') == 1 && !helper.contains('request.size =') && !helper.contains('malloc'),
		'Global parameter copy must not rewrite headers or allocate temporary storage')!
}

fn check_params_copy_reference(file string, header string) ! {
	query := section(file, 'pub(crate) fn get_params(', '/// Query only file-owned VM state;', 'Packaged global query')!
	require_order(query, ['if data.param_group != 0 || data.pad != 0', 'return Err(EINVAL)', 'gpu.get_params(&mut params)?',
		'let size = core::mem::size_of::<uapi::drm_asahi_params_global>().min(data.size.try_into()?)',
		'UserSlice::new(UserPtr::from_addr(data.pointer as usize), size)', 'params_writer.write_slice(', 'fetch_max(data.size,'],
		'Packaged query copies a bounded prefix and retains input size')!
	require(!query.contains('data.size ='), 'Packaged size is an input buffer bound')!
	require(header.contains('@size: Size of the user buffer.') && header.contains('not write past the length specified here'),
		'Packaged UAPI documents the input size bound')!
}
