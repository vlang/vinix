// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn backup_heap_home(name string) string {
	base := os.real_path(os.temp_dir())
	defer { unsafe { base.free() } }
	path := os.join_path(base, 'vinix-backup-heap-${os.getpid()}-${name}')
	os.mkdir(path) or { panic(err) }
	return path
}

fn backup_heap_finish(mut app BackupApp) {
	for _ in 0 .. 10000 { if !app.poll() { return } }
	assert false
}

fn test_backup_owned_initial_buffers_utf8_fields_and_frames_are_released() {
	mut desktop := Desktop{}
	mut native := open_backup_app(mut desktop)!
	begin_frame_elements()
	free_tree(native.build(ui2.rect(0, 0, 760, 560))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		native.handle('backup.store')!
		if mut native is KeyboardApp {
			mut keyboard := KeyboardApp(native)
			keyboard.key_input('\x01')
		}
		if mut native is PastingApp {
			mut paster := PastingApp(native)
			paster.paste_input('/home/日本語/backup')
		}
		if mut native is BackupApp {
			assert editor_bytes_text(native.store_input) == '/home/日本語/backup'
			assert native.store_input.element_size == 1
			assert native.restore_input.element_size == 1
			assert native.source_input.element_size == 1
		}
		begin_frame_elements()
		free_tree(native.build(ui2.rect(0, 0, 760, 560))!)
	}
	if mut native is BackupApp { native.close_app() }
	assert C.vinix_heap_end() == 0
}

fn test_backup_completed_cancelled_jobs_and_version_rows_release_owned_heap() {
	home := backup_heap_home('jobs')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	sub := backup_join(source, 'folder')
	file := backup_join(sub, 'a')
	defer { unsafe { source.free() store.free() sub.free() file.free() } }
	os.mkdir(source)! os.mkdir(store)! os.mkdir(sub)!
	os.write_file(file, 'real contents 😀')!
	mut app := new_backup_app(source, store, '')
	app.start_backup()
	backup_heap_finish(mut app)
	app.refresh_versions()
	backup_heap_finish(mut app)
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 760, 800))!)
	C.vinix_heap_begin()
	for _ in 0 .. 20 {
		app.start_backup()
		backup_heap_finish(mut app)
		assert app.status == 'backup.complete'
		app.refresh_versions()
		backup_heap_finish(mut app)
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 760, 800))!)
		app.start_backup()
		app.poll()
		app.handle('backup.cancel')!
		assert app.status == 'backup.cancelled'
	}
	app.close_app()
	app.close_app()
	live := C.vinix_heap_end()
	assert live == 0, 'Backup jobs retained ${live} bytes'
}

fn test_backup_restore_complete_cancel_and_close_release_owned_buffers() {
	home := backup_heap_home('restores')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	source := backup_join(home, 'source')
	store := backup_join(home, 'store')
	file := backup_join(source, 'a')
	defer { unsafe { source.free() store.free() file.free() } }
	os.mkdir(source)! os.mkdir(store)!
	os.write_file(file, 'restore contents')!
	mut app := new_backup_app(source, store, '')
	app.start_backup()
	backup_heap_finish(mut app)
	app.refresh_versions()
	backup_heap_finish(mut app)
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 760, 560))!)
	C.vinix_heap_begin()
	for index in 0 .. 20 {
		number := index.str()
		name := 'restored-${number}'
		path := backup_join(home, name)
		app.focus_field(2)
		app.key_input('\x01')
		app.paste_input(path)
		unsafe { number.free() name.free() path.free() }
		app.start_restore()
		assert app.active
		if index % 2 == 0 {
			backup_heap_finish(mut app)
			assert app.status == 'backup.restored'
		} else {
			app.poll()
			app.handle('backup.cancel')!
			assert app.status == 'backup.cancelled'
		}
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 760, 560))!)
	}
	app.close_app()
	live := C.vinix_heap_end()
	assert live == 0, 'Backup restores retained ${live} bytes'
}
