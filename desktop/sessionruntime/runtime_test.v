// SPDX-License-Identifier: MIT
module sessionruntime

import os

fn test_numeric_defaults_keep_users_separate_and_preserve_explicit_paths() {
	assert directory_for(0, '', false) == '/run/vinix-session.0'
	assert directory_for(1000, '', false) == '/run/user/1000/vinix-session.1000'
	assert directory_for(1001, '', false) == '/run/user/1001/vinix-session.1001'
	assert directory_for(1000, '/tmp/development', true) == '/tmp/development/vinix-session.1000'
	assert directory_for(0, '/tmp/development', true) == '/tmp/development/vinix-session.0'
}

fn test_runtime_parents_refuse_missing_insecure_foreign_and_replaced_directories() {
	base := '${os.temp_dir()}/vinix-runtime-parents-${os.getpid()}'
	uid := u32(C.getuid())
	users := base + '/user'
	parent := users + '/' + uid.str()
	defer {
		os.rmdir_all(base) or {}
		unsafe { base.free() users.free() parent.free() }
	}
	assert !ordinary_parents(base, uid, uid)
	os.mkdir_all(parent, mode: 0o700)!
	assert ordinary_parents(base, uid, uid)
	assert !ordinary_parents(base, uid + 1, uid)
	assert !ordinary_parents(base, uid, uid + 1)
	for path in [base, users, parent] {
		os.chmod(path, 0o777)!
		assert !ordinary_parents(base, uid, uid)
		os.chmod(path, 0o700)!
		assert ordinary_parents(base, uid, uid)
	}
	// The user parent may be readable by nobody else, even without write bits.
	os.chmod(parent, 0o755)!
	assert !ordinary_parents(base, uid, uid)
	os.chmod(parent, 0o700)!
	// Replacing either the privileged or user-owned component by a symlink
	// must fail even when its target has otherwise acceptable owner and mode.
	for path in [parent, users, base] {
		moved := path + '-real'
		os.mv(path, moved)!
		os.symlink(moved, path)!
		assert !ordinary_parents(base, uid, uid)
		os.rm(path)!
		os.mv(moved, path)!
		unsafe { moved.free() }
		assert ordinary_parents(base, uid, uid)
	}
	os.rmdir(parent)!
	os.write_file(parent, 'replacement')!
	assert !ordinary_parents(base, uid, uid)
}

fn test_private_leaf_rejects_replacement_without_changing_generic_directory_policy() {
	base := '${os.temp_dir()}/vinix-runtime-leaf-${os.getpid()}'
	path := base + '/service-logs'
	os.mkdir(base, mode: 0o700)!
	defer {
		os.rmdir_all(base) or {}
		unsafe { base.free() path.free() }
	}
	assert private_directory(path)
	os.chmod(path, 0o755)!
	assert !private_directory(path)
	os.chmod(path, 0o700)!
	os.rmdir(path)!
	os.symlink(base, path)!
	assert !private_directory(path)
	os.rm(path)!
	os.write_file(path, 'replacement')!
	assert !private_directory(path)
}
