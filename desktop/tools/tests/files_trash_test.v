// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn trash_test_home(suffix string) string {
	base := os.real_path(os.temp_dir())
	pid := C.getpid().str()
	path := '${base}/vinix-trash-${pid}-${suffix}'
	unsafe {
		base.free()
		pid.free()
	}
	os.rmdir_all(path) or {}
	os.mkdir(path) or { panic(err) }
	return path
}

fn trash_test_action(tree ui2.Element, action string) bool {
	if tree.id == action { return true }
	for child in tree.children { if trash_test_action(child, action) { return true } }
	return false
}

fn trash_test_select(mut trash FilesTrash, relative string) {
	for index, entry in trash.entries {
		if entry.path == relative {
			trash.selected = index
			return
		}
	}
	assert false, relative
}

fn test_trash_move_reload_unicode_and_restore_original_contents() {
	home := trash_test_home('reload')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := '${home}/Café 日本語 😀.txt'
	defer { unsafe { path.free() } }
	os.write_file(path, 'original contents')!
	mut trash := files_trash_new(home)
	assert trash.move(path)
	assert trash.status == 'files.trash.moved'
	assert !os.exists(path) && trash.entries.len == 1
	assert trash.entries[0].path == 'Café 日本語 😀.txt'
	trash.close()
	mut reopened := files_trash_new(home)
	reopened.reload()
	assert !reopened.damaged && reopened.entries.len == 1
	reopened.action(reopened.entries[0].action)
	reopened.action('files.trash.restore')
	assert reopened.status == 'files.trash.restored' && reopened.entries.len == 0
	assert os.read_file(path)! == 'original contents'
	reopened.close()
}

fn test_trash_restore_never_overwrites_files_directories_or_links() {
	home := trash_test_home('conflict')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := '${home}/item'
	defer { unsafe { path.free() } }
	os.write_file(path, 'original')!
	mut trash := files_trash_new(home)
	defer { trash.close() }
	assert trash.move(path)
	trash.selected = 0
	os.write_file(path, 'replacement')!
	trash.restore()
	assert trash.status == 'files.trash.conflict' && trash.entries.len == 1
	assert os.read_file(path)! == 'replacement'
	os.rm(path)!
	os.mkdir(path)!
	trash.restore()
	assert trash.status == 'files.trash.conflict' && os.is_dir(path)
	os.rmdir(path)!
	os.symlink('/never-created-vinix-trash-target', path)!
	trash.restore()
	assert trash.status == 'files.trash.conflict' && os.is_link(path)
	os.rm(path)!
	trash.restore()
	assert trash.status == 'files.trash.restored' && os.read_file(path)! == 'original'
}

fn test_trash_protected_paths_parent_links_and_registered_home_alias() {
	home := trash_test_home('unsafe')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	alias := '${home}-alias'
	defer {
		os.rm(alias) or {}
		unsafe { alias.free() }
	}
	os.symlink(home, alias)!
	mut trash := files_trash_new(alias)
	defer { trash.close() }
	assert trash.home == home && trash.home_fd >= 0
	assert !trash.move('/') && trash.status == 'files.trash.unsafe'
	assert !trash.move(home) && !trash.move(alias)
	assert !trash.move('/etc/passwd')
	assert !trash.move('${home}/.vinix-trash')
	assert !trash.move('${home}/.vinix-notes')
	assert !trash.move('${home}/../file')
	assert !trash.move('${home}/double//file')
	outside := trash_test_home('outside')
	defer {
		os.rmdir_all(outside) or {}
		unsafe { outside.free() }
	}
	os.write_file('${outside}/keep', 'untouched')!
	os.symlink(outside, '${home}/parent-link')!
	assert !trash.move('${home}/parent-link/keep') && trash.status == 'files.trash.unsafe'
	assert os.read_file('${outside}/keep')! == 'untouched'
	os.write_file('${alias}/normal', 'via alias')!
	assert trash.move('${alias}/normal')
	trash.selected = 0
	trash.restore()
	assert os.read_file('${home}/normal')! == 'via alias'
}

fn test_trash_leaf_links_preserve_targets_and_empty_requires_confirmation() {
	home := trash_test_home('links')
	outside := trash_test_home('links-outside')
	defer {
		os.rmdir_all(home) or {}
		os.rmdir_all(outside) or {}
		unsafe {
			home.free()
			outside.free()
		}
	}
	path := '${home}/link'
	defer { unsafe { path.free() } }
	os.write_file('${outside}/target', 'keep target')!
	os.symlink('${outside}/target', path)!
	mut trash := files_trash_new(home)
	defer { trash.close() }
	assert trash.move(path)
	trash.empty_confirmed()
	assert trash.entries.len == 1
	trash.action('files.trash.empty')
	trash.action('files.trash.cancel')
	trash.action('files.trash.confirm')
	assert trash.entries.len == 1
	trash.action('files.trash.empty')
	trash.action('files.trash.confirm')
	assert trash.status == 'files.trash.emptied' && trash.entries.len == 0
	assert os.read_file('${outside}/target')! == 'keep target'
}

fn test_trash_nonempty_folders_prevent_all_emptying_and_remain_restorable() {
	home := trash_test_home('folders')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	os.mkdir('${home}/folder')!
	os.write_file('${home}/folder/child', 'child')!
	os.write_file('${home}/file', 'ordinary')!
	os.mkdir('${home}/empty')!
	mut trash := files_trash_new(home)
	defer { trash.close() }
	assert trash.move('${home}/file')
	assert trash.move('${home}/folder')
	assert trash.move('${home}/empty')
	trash.action('files.trash.empty')
	trash.action('files.trash.confirm')
	assert trash.status == 'files.trash.nonempty' && trash.entries.len == 3
	trash_test_select(mut trash, 'folder')
	trash.restore()
	assert trash.status == 'files.trash.restored'
	assert os.read_file('${home}/folder/child')! == 'child'
	trash.action('files.trash.empty')
	trash.action('files.trash.confirm')
	assert trash.status == 'files.trash.emptied' && trash.entries.len == 0
}

fn test_trash_missing_parent_symlink_parent_and_changed_metadata_refuse_restore() {
	home := trash_test_home('changed')
	outside := trash_test_home('changed-outside')
	defer {
		os.rmdir_all(home) or {}
		os.rmdir_all(outside) or {}
		unsafe {
			home.free()
			outside.free()
		}
	}
	os.mkdir('${home}/parent')!
	os.write_file('${home}/parent/file', 'preserve')!
	mut trash := files_trash_new(home)
	defer { trash.close() }
	assert trash.move('${home}/parent/file')
	trash.selected = 0
	os.rmdir('${home}/parent')!
	trash.restore()
	assert trash.status == 'files.trash.parent_missing' && trash.entries.len == 1
	os.symlink(outside, '${home}/parent')!
	trash.restore()
	assert trash.status == 'files.trash.parent_missing' && !os.exists('${outside}/file')
	os.rm('${home}/parent')!
	os.mkdir('${home}/parent')!
	bucket := trash.entries[0].bucket.clone()
	defer { unsafe { bucket.free() } }
	os.write_file('${home}/.vinix-trash/${bucket}/info', 'corrupt')!
	trash.restore()
	assert trash.status == 'files.trash.changed' && !os.exists('${home}/parent/file')
	trash.reload()
	assert trash.damaged && trash.status == 'files.trash.damaged'
	trash.action('files.trash.empty')
	trash.action('files.trash.confirm')
	assert trash.status == 'files.trash.damaged'
	assert os.read_file('${home}/.vinix-trash/${bucket}/item')! == 'preserve'
	os.write_file('${home}/another', 'untouched')!
	assert !trash.move('${home}/another') && os.exists('${home}/another')
}

fn test_trash_store_links_unknown_entries_and_lock_refuse_without_source_changes() {
	home := trash_test_home('store')
	outside := trash_test_home('store-outside')
	defer {
		os.rmdir_all(home) or {}
		os.rmdir_all(outside) or {}
		unsafe {
			home.free()
			outside.free()
		}
	}
	os.write_file('${home}/source', 'keep')!
	os.symlink(outside, '${home}/.vinix-trash')!
	mut unsafe_store := files_trash_new(home)
	assert !unsafe_store.move('${home}/source') && unsafe_store.status == 'files.trash.unavailable'
	assert os.exists('${home}/source')
	unsafe_store.close()
	os.rm('${home}/.vinix-trash')!
	mut trash := files_trash_new(home)
	defer { trash.close() }
	trash.reload()
	lock_fd := files_trash_lock(trash.store_fd)
	assert lock_fd >= 0
	assert !trash.move('${home}/source') && trash.status == 'files.trash.busy'
	desktop_close(lock_fd)
	os.write_file('${home}/.vinix-trash/unknown', 'keep unknown')!
	assert !trash.move('${home}/source') && trash.status == 'files.trash.damaged'
	assert os.read_file('${home}/source')! == 'keep'
	trash.action('files.trash.empty')
	trash.action('files.trash.confirm')
	assert os.read_file('${home}/.vinix-trash/unknown')! == 'keep unknown'
}

fn test_trash_parser_bounds_and_paged_view_keep_last_item_reachable() {
	assert !files_trash_relative_valid('a/../b')
	assert !files_trash_relative_valid('a/./b')
	assert !files_trash_relative_valid('bad\nname')
	assert !files_trash_relative_valid('\xff')
	assert files_trash_relative_valid('日本語/😀')
	for record in ['bad', 'VINIX TRASH 1\n', 'VINIX TRASH 1\n1\t2\t33188\n',
		'VINIX TRASH 1\n1\t2\t33188\n../unsafe\n', 'VINIX TRASH 1\n18446744073709551616\t2\t33188\nfile\n',
		'VINIX TRASH 1\n1\t2\t33188\nfile\nextra\n'] {
		if mut parsed := files_trash_parse(record) {
			unsafe { parsed.path.free() }
			assert false
		}
	}
	home := trash_test_home('paging')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut trash := files_trash_new(home)
	defer { trash.close() }
	for index in 0 .. 8 {
		path := '${home}/file-${index}'
		os.write_file(path, 'contents')!
		assert trash.move(path)
		unsafe { path.free() }
	}
	begin_frame_elements()
	first := trash.build(ui2.rect(0, 0, 700, 376))
	assert trash_test_action(first, 'files.trash.restore') && trash_test_action(first, 'files.trash.empty')
	assert trash_test_action(first, trash.entries[0].action)
	free_tree(first)
	for _ in 0 .. 100 { trash.key('\x1b[6~') }
	begin_frame_elements()
	last := trash.build(ui2.rect(0, 0, 700, 376))
	assert trash_test_action(last, trash.entries[7].action)
	free_tree(last)
	trash.key('\x1b[5~')
	assert trash.page >= 0
	trash.action('files.trash.empty')
	trash.key('\x1b')
	assert !trash.confirming
}

fn test_trash_empty_confirmation_refuses_new_arrivals_and_replaced_store() {
	home := trash_test_home('arrival')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	os.write_file('${home}/first', 'first')!
	os.write_file('${home}/second', 'second')!
	mut first := files_trash_new(home)
	mut second := files_trash_new(home)
	defer {
		first.close()
		second.close()
	}
	assert first.move('${home}/first')
	first.action('files.trash.empty')
	assert second.move('${home}/second')
	first.action('files.trash.confirm')
	assert first.status == 'files.trash.changed' && first.entries.len == 2
	assert !first.confirming
	os.mv('${home}/.vinix-trash', '${home}/old-trash')!
	os.mkdir('${home}/.vinix-trash')!
	first.selected = 0
	first.restore()
	assert first.status == 'files.trash.unavailable' && !os.exists('${home}/first')
	first.action('files.trash.empty')
	first.action('files.trash.confirm')
	assert first.status == 'files.trash.unavailable'
}

fn test_trash_files_handler_moves_instead_of_deleting_and_exposes_trash_actions() {
	home := trash_test_home('adapter')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := '${home}/document'
	defer { unsafe { path.free() } }
	os.write_file(path, 'reversible')!
	mut app := FilesContextApp{}
	app.trash = files_trash_new(home)
	app.files.browser.read(home.clone())
	app.set_context_path(path)
	app.handle(file_context_delete)!
	assert !os.exists(path) && app.trash.entries.len == 1
	assert app.trash.status == 'files.trash.moved' && app.context_path.len == 0
	begin_frame_elements()
	files := app.build(ui2.rect(0, 0, 700, 400))!
	assert trash_test_action(files, 'files.trash.open')
	free_tree(files)
	app.handle('files.trash.open')!
	assert app.trash_open
	app.handle(app.trash.entries[0].action)!
	app.handle('files.trash.restore')!
	assert os.read_file(path)! == 'reversible'
	app.handle('files.trash.back')!
	assert !app.trash_open
	app.close_app()
	app.files.browser.free_entries()
	unsafe {
		app.files.browser.path.free()
		app.files.browser.error.free()
		app.files.browser.error_path.free()
	}
}

fn test_trash_reopened_windows_find_free_bucket_after_many_existing_names() {
	home := trash_test_home('collisions')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut first := files_trash_new(home)
	for index in 0 .. 34 {
		path := '${home}/file-${index}'
		os.write_file(path, 'keep')!
		assert first.move(path)
		unsafe { path.free() }
	}
	first.close()
	mut reopened := files_trash_new(home)
	defer { reopened.close() }
	os.write_file('${home}/next', 'new')!
	assert reopened.move('${home}/next') && reopened.entries.len == 35
	assert !reopened.damaged
}

fn test_trash_cross_filesystem_rename_refuses_and_keeps_source_when_available() {
	$if linux {
		if !os.is_dir('/dev/shm') { return }
		home := trash_test_home('cross-device')
		defer {
			os.rmdir_all(home) or {}
			unsafe { home.free() }
		}
		mut trash := files_trash_new(home)
		defer { trash.close() }
		trash.reload()
		other := C.open(c'/dev/shm', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		if other < 0 { return }
		defer { desktop_close(other) }
		mut source_info := C.stat{}
		mut home_info := C.stat{}
		if unsafe { C.fstat(other, &source_info) } != 0 || unsafe { C.fstat(trash.home_fd, &home_info) } != 0
			|| source_info.st_dev == home_info.st_dev {
			return
		}
		pid := C.getpid().str()
		leaf := 'vinix-trash-exdev-${pid}'
		unsafe { pid.free() }
		defer {
			C.unlinkat(other, &char(leaf.str), 0)
			unsafe { leaf.free() }
		}
		fd := C.openat(other, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
		assert fd >= 0
		assert desktop_write_all(fd, c'unchanged', 9)
		desktop_close(fd)
		assert unsafe { C.fstatat(other, &char(leaf.str), &source_info, C.AT_SYMLINK_NOFOLLOW) } == 0
		assert trash.move_locked(other, leaf, leaf, source_info, other) == 'files.trash.cross_device'
		assert unsafe { C.fstatat(other, &char(leaf.str), &source_info, C.AT_SYMLINK_NOFOLLOW) } == 0
		trash.reload()
		assert !trash.damaged && trash.entries.len == 0
	}
}
