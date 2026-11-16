// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_params_copy_guards_require_input_bound_single_copy_and_no_size_writeback() {
	repo := g13layout.repo_root()
	native := read(repo + '/kernel/gpu/agx/file/file.v')!
	fake := read(repo + '/kernel/gpu/agx/fake/driver.v')!
	helper := read(repo + '/kernel/gpu/agx/params/params.v')!
	check_params_copy_local(native, fake, helper)!
	for token in ['request.size < supported', 'usercopy.copy_to_user(request.pointer, voidptr(value), bytes)', 'return -14'] {
		if _ := check_params_copy_local(native, fake, helper.replace(token, '')) { assert false, token }
	}
	if _ := check_params_copy_local(native, fake, helper.replace('return 0', 'request.size = supported\nreturn 0')) { assert false }
	for source in [native, fake] {
		assert source.contains('return agxparams.copy_global(request, unsafe { &params })')
	}
	if _ := check_params_copy_local(native.replace('return agxparams.copy_global(request, unsafe { &params })', 'return 0'), fake, helper) { assert false }
	if _ := check_params_copy_local(native, fake.replace('return agxparams.copy_global(request, unsafe { &params })', 'return 0'), helper) { assert false }
}
