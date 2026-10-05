// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn notes_test_home(name string) string {
	base := os.real_path(os.temp_dir())
	pid := os.getpid().str()
	path := '${base}/vinix-notes-${name}-${pid}'
	unsafe {
		base.free()
		pid.free()
	}
	os.rmdir_all(path) or {}
	os.mkdir(path) or { panic(err) }
	return path
}

fn notes_test_edit(mut a NotesApp, title string, body string) {
	a.focus_field(1)
	a.key_input('\x01')
	a.paste_input(title)
	a.focus_field(2)
	a.key_input('\x01')
	a.paste_input(body)
}

fn test_notes_persistence_search_utf8_export_and_explicit_delete() {
	home := notes_test_home('persistence')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	assert !a.read_failed && a.count == 0
	a.new_note()
	notes_test_edit(mut a, '日本語 😀', 'First line\nРусский текст\t😀')
	assert a.save() && !a.dirty
	a.new_note()
	notes_test_edit(mut a, 'Second note', 'Body only match')
	assert a.save()
	a.focus_field(0)
	a.paste_input('Русский')
	assert a.matched == 1 && a.matches[0] == 0
	a.select_note(0)
	assert editor_bytes_text(a.body) == 'First line\nРусский текст\t😀'
	export_path := join_path(home, 'export.txt')
	defer { unsafe { export_path.free() } }
	assert notes_export(export_path, editor_bytes_text(a.title), editor_bytes_text(a.body)) == 'notes.export_saved'
	assert notes_export(export_path, 'replace', 'replace') == 'notes.export_exists'
	exported := os.read_file(export_path)!
	assert exported == '日本語 😀\n\nFirst line\nРусский текст\t😀'
	unsafe { exported.free() }
	a.close_app()
	mut b := new_notes_app(home)
	assert b.count == 2 && b.items[0].title == '日本語 😀'
	b.delete_note()
	assert b.delete_pending && b.count == 2
	b.handle('notes.cancel_delete')!
	assert !b.delete_pending && b.count == 2
	b.delete_note()
	b.delete_note()
	assert b.count == 1 && b.items[0].title == 'Second note'
	b.close_app()
	mut c := new_notes_app(home)
	assert c.count == 1 && c.next_id == 3
	c.close_app()
}

fn test_notes_conflict_preserves_drafts_and_blocks_switch_new_delete_refresh() {
	home := notes_test_home('conflict')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut first := new_notes_app(home)
	first.new_note()
	notes_test_edit(mut first, 'Original', 'one')
	assert first.save()
	first.new_note()
	notes_test_edit(mut first, 'Second', 'two')
	assert first.save()
	mut second := new_notes_app(home)
	notes_test_edit(mut second, 'Stale draft', 'keep me')
	first.select_note(0)
	notes_test_edit(mut first, 'Newer saved', 'latest')
	assert first.save()
	assert !second.save() && second.status == 'notes.conflict' && second.dirty
	second.select_note(1)
	assert second.selected == 0
	second.new_note()
	assert second.count == 2
	second.delete_note()
	assert second.count == 2 && !second.delete_pending
	second.reload()
	assert second.dirty && editor_bytes_text(second.body) == 'keep me'
	path := join_path(home, 'draft.txt')
	assert notes_export(path, editor_bytes_text(second.title), editor_bytes_text(second.body)) == 'notes.export_saved'
	unsafe { path.free() }
	second.close_app()
	first.close_app()
	mut check := new_notes_app(home)
	assert check.items[0].title == 'Newer saved' && check.items[0].body == 'latest'
	check.close_app()
}

fn test_notes_corrupt_empty_symlink_and_oversize_stores_are_preserved() {
	home := notes_test_home('corrupt')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := join_path(home, '.vinix-notes')
	defer { unsafe { path.free() } }
	for record in ['', 'VINIX-NOTES 1\n2\n1 3 0\nabc', 'VINIX-NOTES 1\n2\n1 1 0\na\n1 1 0\na\n',
		'VINIX-NOTES 1\n2\n1 1 0\n\xff\n']! {
		os.write_file(path, record)!
		mut a := new_notes_app(home)
		assert a.read_failed
		a.new_note()
		assert a.count == 0
		a.close_app()
		unchanged := os.read_file(path)!
		assert unchanged == record
		unsafe { unchanged.free() }
	}
	large := 'x'.repeat(notes_record_limit + 1)
	os.write_file(path, large)!
	unsafe { large.free() }
	mut big := new_notes_app(home)
	assert big.read_failed
	big.close_app()
	os.rm(path)!
	target := join_path(home, 'target')
	os.write_file(target, 'preserved')!
	os.symlink(target, path)!
	mut linked := new_notes_app(home)
	assert linked.read_failed
	linked.close_app()
	original := os.read_file(target)!
	assert original == 'preserved'
	unsafe {
		original.free()
		target.free()
	}
}

fn test_notes_new_empty_corrupt_store_and_lock_contention_cannot_be_overwritten() {
	home := notes_test_home('late-corrupt')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	a.new_note()
	path := join_path(home, '.vinix-notes')
	os.write_file(path, '')!
	assert !a.save() && a.dirty
	info := os.stat(path)!
	assert info.size == 0
	os.rm(path)!
	lock_fd := notes_lock(a.home_fd)
	assert lock_fd >= 0
	assert !a.save() && a.dirty
	desktop_close(lock_fd)
	assert a.save()
	a.close_app()
	unsafe { path.free() }
}

fn test_notes_input_bounds_cursor_split_utf8_paste_and_autosave() {
	home := notes_test_home('input')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	a.new_note()
	a.focus_field(1)
	a.key_input('\x01')
	a.paste_input('Title')
	a.focus_field(2)
	a.key_input('\xe6\x97')
	assert a.body.len == 0
	a.key_input('\xa5')
	assert editor_bytes_text(a.body) == '日'
	a.key_input('😀\x1b')
	assert editor_bytes_text(a.body) == '日😀'
	a.key_input('\x1b[D')
	a.key_input('X')
	assert editor_bytes_text(a.body) == '日X😀'
	a.key_input('\x7f')
	assert editor_bytes_text(a.body) == '日😀'
	a.key_input('\x1b[3~')
	assert editor_bytes_text(a.body) == '日'
	a.key_input('\x01')
	a.paste_input('\xffbad')
	assert editor_bytes_text(a.body) == '日'
	a.paste_input('safe\ntext')
	assert editor_bytes_text(a.body) == 'safe\ntext'
	long := 'z'.repeat(notes_body_limit)
	a.key_input('\x01')
	a.paste_input(long)
	a.key_input('q')
	assert a.body.len == notes_body_limit
	unsafe { long.free() }
	a.key_input('\x01')
	a.paste_input('Body')
	assert !a.poll_at(a.last_edit + notes_autosave_ms - 1)
	assert a.poll_at(a.last_edit + notes_autosave_ms) && !a.dirty
	assert !a.poll_at(~u64(0)) && a.next_poll_ms() == 2000
	a.focus_field(1)
	a.key_input('\x01\x7f')
	assert !a.save() && a.status == 'notes.title_required'
	a.reload()
	assert a.dirty
	a.paste_input('Saved title')
	assert a.save()
	begin_frame_elements()
	tree := a.build(ui2.rect(0, 0, 820, 576))!
	free_tree(tree)
	a.pointer_event(.down, .left, 0, 248, 101, 820, 576)
	assert a.cursor == 0 && a.focus == 2
	a.close_app()
}

fn test_notes_parser_rejects_overflow_trailing_fields_ids_and_preserves_existing_model() {
	home := notes_test_home('parser')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	a.new_note()
	notes_test_edit(mut a, 'Kept', 'original')
	assert a.save()
	for record in ['VINIX-NOTES 1\n18446744073709551616\n', 'VINIX-NOTES 1\n0\n',
		'VINIX-NOTES 1\n2\n0 1 0\na\n', 'VINIX-NOTES 1\n2\n2 1 0\na\n', 'VINIX-NOTES 1\n2\n1 1 0 extra\na\n',
		'VINIX-NOTES 1\n2\n1 1 0\na\nJUNK']! {
		assert !a.decode(record) && a.count == 1 && a.items[0].title == 'Kept'
	}
	a.close_app()
}

fn test_notes_symlink_home_is_anchored_but_lock_symlink_is_refused() {
	home := notes_test_home('home-link')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	alias := '${home}-alias'
	os.rm(alias) or {}
	os.symlink(home, alias)!
	mut a := new_notes_app(alias)
	a.new_note()
	assert a.save()
	a.handle('notes.export')!
	assert a.export_status == 'notes.export_saved'
	personal_export := '${home}/vinix-note.txt'
	assert os.exists(personal_export)
	unsafe { personal_export.free() }
	a.close_app()
	os.rm(alias)!
	unsafe { alias.free() }
	lock_fd := join_path(home, '.vinix-notes-lock')
	os.rm(lock_fd)!
	target := join_path(home, 'lock-target')
	os.write_file(target, 'untouched')!
	os.symlink(target, lock_fd)!
	mut b := new_notes_app(home)
	assert b.status == 'notes.read_failed'
	b.new_note()
	assert !b.save()
	b.close_app()
	original := os.read_file(target)!
	assert original == 'untouched'
	unsafe {
		lock_fd.free()
		target.free()
		original.free()
	}
}

fn test_notes_count_title_and_total_store_limits_preserve_saved_data() {
	home := notes_test_home('limits')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	for _ in 0 .. notes_limit { a.new_note() }
	assert a.count == notes_limit
	assert a.save()
	a.new_note()
	assert a.count == notes_limit && a.status == 'notes.limit'
	a.focus_field(1)
	a.key_input('\x01')
	long_title := 't'.repeat(notes_title_limit + 1)
	a.paste_input(long_title)
	unsafe { long_title.free() }
	assert editor_bytes_text(a.title) == tr('notes.untitled')
	assert a.status == 'notes.limit'
	snapshot := a.record.clone()
	long_body := 'b'.repeat(notes_body_limit)
	for index in 0 .. 64 {
		a.select_note(index)
		a.focus_field(2)
		a.key_input('\x01')
		a.paste_input(long_body)
		if index < 63 {
			assert a.save()
		}
	}
	assert !a.save() && a.dirty && a.status == 'notes.limit'
	assert a.count == notes_limit && a.body.len == notes_body_limit
	// The last rejected draft never replaced the preceding complete snapshot.
	mut other := new_notes_app(home)
	assert !other.read_failed && other.count == notes_limit
	assert other.items[62].body == long_body && other.items[63].body.len == 0
	assert snapshot.len < a.record.len
	other.close_app()
	a.close_app()
	unsafe {
		snapshot.free()
		long_body.free()
	}
}
