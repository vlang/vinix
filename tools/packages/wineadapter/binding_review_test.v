// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

fn binding_snapshot(path string, mut files map[string]string) ! {
	if os.is_link(path) { files[path] = 'link:' + os.readlink(path)!; return }
	if os.is_dir(path) {
		files[path] = 'directory'
		for name in os.ls(path)! { binding_snapshot(path + '/' + name, mut files)! }
	} else { files[path] = 'file:' + os.read_file(path)! }
}

fn binding_refused(data string, builtins string, store string, message string) ! {
	mut before := map[string]string{}
	binding_snapshot(data, mut before)!
	mut review := review_prefix_bindings(data, builtins, store) or {
		assert err.msg().contains(message), err.msg()
		cli := os.getenv('VINIX_WINE_PREFIX_REVIEW')
		if cli != '' {
			mut child := os.new_process(cli)
			defer { child.close() }
			child.set_args([store, data, builtins])
			child.set_redirect_stdio_merged()
			child.run()
			output := child.stdout_slurp()
			child.wait()
			assert child.code == 1 && output.contains(message), output
		}
		mut after := map[string]string{}
		binding_snapshot(data, mut after)!
		assert before == after
		return
	}
	review.close()
	assert false, 'unsafe binding review accepted'
}

fn test_builtin_generation_paths_are_canonical() {
	for value in ['0', '01', '-1', '+1', '1e2', '18446744073709551616'] {
		if _, _ := builtin_generation('/store', '/store/generations/' + value + '/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows') {
			assert false, 'invalid generation accepted'
		}
	}
	generation, runtime := builtin_generation('/store', '/store/generations/18446744073709551615/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows')!
	assert generation == u64(18446744073709551615)
	assert runtime == 'org.vinix.wine'
}

fn test_binding_review_is_read_only_and_refuses_foreign_or_mixed_links() {
	root := os.real_path(os.temp_dir()) + '/wine-binding-review-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	old := store + '/generations/1/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows'
	new := store + '/generations/2/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(new)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	os.chown(data, int(C.geteuid()), os.getegid())!
	for name in ['kernel32.dll', 'ntdll.dll'] { os.write_file(old + '/' + name, 'old')!; os.write_file(new + '/' + name, 'new')! }
	mut prefix := prepare_prefix(data, old)!
	prefix.close()
	mut before := map[string]string{}
	binding_snapshot(data, mut before)!
	mut review := review_prefix_bindings(data, new, store)!
	assert review.generation == 2 && review.prior_generation == 1
	assert review.runtime_id == 'org.vinix.wine' && review.bindings.len == 2
	assert review.bindings[0].observed == old + '/kernel32.dll'
	assert review.bindings[0].replacement == new + '/kernel32.dll'
	assert review.bindings[0].operation == .replace
	review.close(); review.close()
	cli := os.getenv('VINIX_WINE_PREFIX_REVIEW')
	if cli != '' {
		mut child := os.new_process(cli)
		defer { child.close() }
		child.set_args([store, data, new])
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait()
		assert child.code == 0, output
		assert output.contains('read-only structural review') && output.contains('org.vinix.wine')
	}
	mut after := map[string]string{}
	binding_snapshot(data, mut after)!
	assert before == after
	system := data + '/wine/drive_c/windows/system32'
	// Inventory shrinkage must not hide a stale packaged DLL, even when its
	// old generation has already been collected. User-owned additions survive.
	os.write_file(system + '/personal.dll', 'private contents')!
	os.symlink('/private/user-library.dll', system + '/personal-link.dll')!
	mut personal := review_prefix_bindings(data, new, store)!
	assert personal.bindings.len == 2
	personal.close()
	for target in [old + '/retired.dll', new + '/retired.dll', store + '/generations/invalid/apps/foreign/retired.dll'] {
		os.symlink(target, system + '/retired.dll')!
		binding_refused(data, new, store, 'absent from the selected builtin inventory')!
		assert os.readlink(system + '/retired.dll')! == target
		os.rm(system + '/retired.dll')!
	}
	assert os.read_file(system + '/personal.dll')! == 'private contents'
	assert os.readlink(system + '/personal-link.dll')! == '/private/user-library.dll'
	for name in ['kernel32.dll', 'ntdll.dll'] {
		os.rm(system + '/' + name)!; os.symlink(new + '/' + name, system + '/' + name)!
	}
	mut current := review_prefix_bindings(data, new, store)!
	assert current.prior_generation == 0 && current.bindings.len == 2
	assert current.bindings[0].operation == .keep && current.bindings[1].operation == .keep
	current.close()
	// An upgrade may add a DLL. Distinguish absent entries from user files or
	// directories; keep review read-only even when a link would be created.
	os.write_file(new + '/new.dll', 'new builtin')!
	mut additions_before := map[string]string{}
	binding_snapshot(data, mut additions_before)!
	mut additions := review_prefix_bindings(data, new, store)!
	assert additions.prior_generation == 0 && additions.bindings.len == 3
	assert additions.bindings[1].name == 'new.dll'
	assert additions.bindings[1].operation == .create && additions.bindings[1].observed == ''
	assert additions.bindings[1].replacement == new + '/new.dll'
	additions.close(); additions.close()
	if cli != '' {
		mut child := os.new_process(cli)
		defer { child.close() }
		child.set_args([store, data, new])
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait()
		assert child.code == 0, output
		assert output.contains('"operation":"create"') && output.contains('"observed":""'), output
	}
	mut additions_after := map[string]string{}
	binding_snapshot(data, mut additions_after)!
	assert additions_before == additions_after
	assert !os.exists(system + '/new.dll')
	os.rm(system + '/kernel32.dll')!
	os.symlink(old + '/kernel32.dll', system + '/kernel32.dll')!
	mut mixed := review_prefix_bindings(data, new, store)!
	assert mixed.prior_generation == 1 && mixed.bindings.len == 3
	assert mixed.bindings[0].operation == .replace
	assert mixed.bindings[1].operation == .create
	assert mixed.bindings[2].operation == .keep
	mixed.close()
	os.rm(system + '/kernel32.dll')!
	os.symlink(new + '/kernel32.dll', system + '/kernel32.dll')!
	os.write_file(system + '/new.dll', 'personal file')!
	binding_refused(data, new, store, 'symlinks')!
	os.rm(system + '/new.dll')!
	os.mkdir(system + '/new.dll')!
	binding_refused(data, new, store, 'symlinks')!
	os.rmdir(system + '/new.dll')!
	os.symlink('/missing/personal-new.dll', system + '/new.dll')!
	binding_refused(data, new, store, 'basename')!
	os.rm(system + '/new.dll')!
	os.rm(new + '/new.dll')!
	for name in ['kernel32.dll', 'ntdll.dll'] {
		os.rm(system + '/' + name)!; os.symlink(old + '/' + name, system + '/' + name)!
	}
	os.rm(new + '/kernel32.dll')!; os.symlink(old + '/kernel32.dll', new + '/kernel32.dll')!
	binding_refused(data, new, store, 'linked or unavailable')!
	assert os.readlink(new + '/kernel32.dll')! == old + '/kernel32.dll'
	os.rm(new + '/kernel32.dll')!; os.write_file(new + '/kernel32.dll', 'new')!
	os.write_file(new + '/unexpected.txt', 'invalid inventory')!
	binding_refused(data, new, store, 'name is invalid')!
	os.rm(new + '/unexpected.txt')!
	for target in ['/outside/kernel32.dll', store + '/generations/1/apps/foreign/root/usr/lib/wine/x86_64-windows/kernel32.dll', old + '/wrong.dll'] {
		os.rm(system + '/kernel32.dll')!; os.symlink(target, system + '/kernel32.dll')!
		binding_refused(data, new, store, if target.starts_with('/outside') { 'outside' } else if target.ends_with('wrong.dll') { 'basename' } else { 'different runtime' })!
	}
	os.rm(system + '/kernel32.dll')!; os.symlink(old + '/kernel32.dll', system + '/kernel32.dll')!
	os.rm(system + '/ntdll.dll')!; os.symlink(store + '/generations/3/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows/ntdll.dll', system + '/ntdll.dll')!
	binding_refused(data, new, store, 'multiple prior')!
	os.rm(system + '/ntdll.dll')!; os.write_file(system + '/ntdll.dll', 'personal file')!
	binding_refused(data, new, store, 'symlinks')!
	os.mv(data + '/wine/drive_c/windows', data + '/wine/drive_c/original-windows')!
	os.symlink('original-windows', data + '/wine/drive_c/windows')!
	binding_refused(data, new, store, 'directory components')!
	os.mkdir(root + '/empty-data')!; os.chmod(root + '/empty-data', 0o700)!
	os.chown(root + '/empty-data', int(C.geteuid()), os.getegid())!
	binding_refused(root + '/empty-data', new, store, 'directory components')!
	assert !os.exists(root + '/empty-data/wine')
}
