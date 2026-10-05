// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import ui2

fn C.mkfifo(path &char, mode u32) int

fn backup_test_home(name string) string {
	base := os.real_path(os.temp_dir())
	defer { unsafe { base.free() } }
	path := os.join_path(base, 'vinix-backup-${os.getpid()}-${name}')
	os.mkdir(path) or { panic(err) }
	return path
}

fn backup_test_finish(mut app BackupApp) {
	for _ in 0 .. 10000 { if !app.poll() { return } }
	assert false
}

fn test_backup_copies_real_tree_versions_and_restores_to_new_folder() {
	home := backup_test_home('roundtrip')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	restore := backup_join(home, 'restored')
	sub := backup_join(source, '日本語')
	file := backup_join(sub, 'note.txt')
	empty := backup_join(source, 'empty')
	defer { unsafe { source.free() store.free() restore.free() sub.free() file.free() empty.free() } }
	os.mkdir(source)! os.mkdir(store)! os.mkdir(sub)!
	os.write_file(file, 'hello 😀\n')! os.write_file(empty, '')!
	mut app := new_backup_app(source, store, restore)
	defer { app.close_app() }
	app.start_backup()
	assert app.active, app.status
	backup_test_finish(mut app)
	assert app.status == 'backup.complete'
	assert app.files == 2
	assert app.bytes == 11
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 1
	assert app.version_ids[0] == 'backup.version.0'
	app.start_restore()
	backup_test_finish(mut app)
	assert app.status == 'backup.restored'
	restored_file := backup_join(restore, '日本語/note.txt')
	data := os.read_file(restored_file)!
	assert data == 'hello 😀\n'
	unsafe { restored_file.free() data.free() }
	app.start_restore()
	assert app.status == 'backup.exists'
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 760, 560))!
	free_tree(tree)
}

fn test_backup_path_validation_and_nonoverlapping_boundaries() {
	for path in ['', '/', 'relative', '/one/', '/one//two', '/one/./two', '/one/../two', '/one\nname', '/one\x00x']! { assert !backup_valid_path(path) }
	for path in ['/one', '/one/two', '/日本語/😀']! { assert backup_valid_path(path) }
	assert backup_overlaps('/one', '/one/two')
	assert backup_overlaps('/one/two', '/one')
	assert backup_overlaps('/one', '/one')
	assert !backup_overlaps('/one', '/onetwo')
}

fn test_backup_cancel_keeps_partial_destination_without_completed_version() {
	home := backup_test_home('cancel')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	file := backup_join(source, 'large')
	defer { unsafe { source.free() store.free() file.free() } }
	os.mkdir(source)! os.mkdir(store)!
	data := 'x'.repeat(backup_chunk_bytes * 4)
	os.write_file(file, data)!
	unsafe { data.free() }
	mut app := new_backup_app(source, store, '')
	defer { app.close_app() }
	app.start_backup()
	for _ in 0 .. 10 { assert app.poll()
		if app.bytes > 0 { break } }
	assert app.bytes == backup_chunk_bytes
	assert app.active
	app.handle('backup.cancel')!
	assert !app.active
	assert app.status == 'backup.cancelled'
	assert os.is_dir(app.output_path)
	marker := backup_join(app.output_path, 'complete')
	defer { unsafe { marker.free() } }
	assert !os.exists(marker)
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 0
	assert app.status == 'backup.no_versions'
}

fn test_backup_rejects_source_links_special_files_and_intermediate_links() {
	home := backup_test_home('links')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	file := backup_join(home, 'outside')
	link := backup_join(source, 'link')
	alias := backup_join(home, 'alias')
	defer { unsafe { source.free() store.free() file.free() link.free() alias.free() } }
	os.mkdir(source)! os.mkdir(store)!
	os.write_file(file, 'never follow this')!
	os.symlink(file, link)!
	os.symlink(source, alias)!
	mut app := new_backup_app(source, store, '')
	defer { app.close_app() }
	app.start_backup()
	backup_test_finish(mut app)
	assert app.status == 'backup.special'
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 0
	assert backup_open_directory(alias) == -1
	os.rm(link)!
	assert C.mkfifo(&char(link.str), 0o600) == 0
	app.start_backup()
	backup_test_finish(mut app)
	assert app.status == 'backup.special'
}

fn test_backup_conflicts_and_overlap_do_not_modify_existing_data() {
	home := backup_test_home('conflicts')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	nested := backup_join(source, 'backup')
	file := backup_join(source, 'important')
	defer { unsafe { source.free() store.free() nested.free() file.free() } }
	os.mkdir(source)! os.mkdir(store)! os.mkdir(nested)!
	os.write_file(file, 'preserved')!
	mut app := new_backup_app(source, nested, source)
	defer { app.close_app() }
	app.start_backup()
	assert app.status == 'backup.overlap'
	app.focus_field(1)
	app.key_input('\x01')
	app.paste_input(store)
	app.start_backup()
	backup_test_finish(mut app)
	assert app.status == 'backup.complete'
	app.refresh_versions()
	backup_test_finish(mut app)
	app.start_restore()
	assert app.status == 'backup.overlap'
	app.focus_field(2)
	app.key_input('\x01')
	app.paste_input(file)
	app.start_restore()
	assert app.status == 'backup.overlap'
	app.focus_field(2)
	app.key_input('\x01')
	app.paste_input(home)
	app.start_restore()
	assert app.status == 'backup.overlap'
	data := os.read_file(file)!
	assert data == 'preserved'
	unsafe { data.free() }
}

fn test_backup_changed_source_never_publishes_completed_marker() {
	home := backup_test_home('change')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	file := backup_join(source, 'changing')
	defer { unsafe { source.free() store.free() file.free() } }
	os.mkdir(source)! os.mkdir(store)!
	os.write_file(file, 'first')!
	mut app := new_backup_app(source, store, '')
	defer { app.close_app() }
	app.start_backup()
	for _ in 0 .. 10 { app.poll() if app.input_fd >= 0 { break } }
	assert app.input_fd >= 0
	os.write_file(file, 'a longer changed value')!
	backup_test_finish(mut app)
	assert app.status == 'backup.changed'
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 0
}

fn backup_test_element(tree ui2.Element, id string) ?ui2.Element {
	if tree.id == id { return tree }
	for child in tree.children { if found := backup_test_element(child, id) { return found } }
	return none
}

fn test_backup_shortened_paths_native_fields_and_clickable_versions() {
	home := backup_test_home('short-fields')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 's')
	store := backup_join(home, 'b')
	restore := backup_join(home, 'r')
	long_source := backup_join(home, 'source-with-longer-name')
	long_store := backup_join(home, 'backup-with-longer-name')
	long_restore := backup_join(home, 'restore-with-longer-name')
	defer { unsafe { source.free() store.free() restore.free() long_source.free() long_store.free() long_restore.free() } }
	os.mkdir(source)! os.mkdir(store)!
	mut app := new_backup_app(long_source, long_store, long_restore)
	defer { app.close_app() }
	for field, value in [source, store, restore]! {
		app.focus_field(field)
		app.key_input('\x01')
		app.paste_input(value)
	}
	assert unsafe { (&u8(app.source_input.data))[app.source_input.len] } != 0
	app.start_backup()
	backup_test_finish(mut app)
	assert app.status == 'backup.complete'
	app.refresh_versions()
	backup_test_finish(mut app)
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 760, 560))!
	version := backup_test_element(tree, 'backup.version.0') or { panic('Missing version button') }
	assert version.kind == .button
	mut desktop := Desktop{targets: []HitTarget{cap: 1}}
	desktop.record_target(&version, 14, 266, 700, 26)
	assert desktop.targets.len == 1
	assert desktop.targets[0].action_id == 'backup.version.0'
	desktop.clear_hit_targets()
	unsafe { desktop.targets.free() }
	free_tree(tree)
	app.start_restore()
	backup_test_finish(mut app)
	assert app.status == 'backup.restored'
	assert os.is_dir(restore)
	assert !os.exists(long_restore)
}

fn test_backup_rejects_same_size_edits_and_directory_mutation() {
	home := backup_test_home('same-size')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	file := backup_join(source, 'a')
	new_file := backup_join(source, 'new')
	defer { unsafe { source.free() store.free() file.free() new_file.free() } }
	os.mkdir(source)! os.mkdir(store)!
	os.write_file(file, 'first')!
	mut app := new_backup_app(source, store, '')
	defer { app.close_app() }
	app.start_backup()
	for _ in 0 .. 10 { app.poll() if app.input_fd >= 0 { break } }
	assert app.input_fd >= 0
	os.write_file(file, 'other')!
	backup_test_finish(mut app)
	assert app.status == 'backup.changed'
	app.start_backup()
	os.write_file(new_file, 'directory changed')!
	backup_test_finish(mut app)
	assert app.status == 'backup.changed'
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 0
}

fn test_backup_scan_ignores_missing_invalid_records_and_bounds_versions() {
	home := backup_test_home('version-limit')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_backup_app('', home, '')
	defer { app.close_app() }
	for index in 0 .. 130 {
		number := index.str()
		name := 'snapshot-${number}'
		path := backup_join(home, name)
		marker := backup_join(path, 'complete')
		manifest := backup_join(path, 'manifest.txt')
		os.mkdir(path)!
		os.write_file(marker, backup_marker)!
		os.write_file(manifest, 'VINIX BACKUP 1\n')!
		unsafe { number.free() name.free() path.free() marker.free() manifest.free() }
	}
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 128
	assert app.version_ids.len == 128
	assert app.version_limit
	app.focus_field(1)
	app.key_input('\x01')
	app.paste_input('/some/other/store')
	app.start_restore()
	assert app.status == 'backup.select_version' || app.status == 'backup.invalid_path'
}

fn test_backup_depth_limit_and_incomplete_records_stay_out_of_versions() {
	home := backup_test_home('depth')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	defer { unsafe { source.free() store.free() } }
	os.mkdir(source)! os.mkdir(store)!
	mut path := source.clone()
	for _ in 0 .. backup_depth_limit {
		next := backup_join(path, 'd')
		unsafe { path.free() }
		path = next
		os.mkdir(path)!
	}
	unsafe { path.free() }
	mut app := new_backup_app(source, store, '')
	defer { app.close_app() }
	app.start_backup()
	backup_test_finish(mut app)
	assert app.status == 'backup.limit'
	// A marker alone and a bad manifest cannot be called completed versions.
	fake := backup_join(store, 'snapshot-fake')
	marker := backup_join(fake, 'complete')
	manifest := backup_join(fake, 'manifest.txt')
	defer { unsafe { fake.free() marker.free() manifest.free() } }
	os.mkdir(fake)!
	os.write_file(marker, backup_marker)!
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 0
	os.write_file(manifest, 'incorrect header')!
	app.refresh_versions()
	backup_test_finish(mut app)
	assert app.versions.len == 0
}
