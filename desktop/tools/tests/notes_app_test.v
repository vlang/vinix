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

fn test_notes_widening_and_tall_resize_preserve_visible_text_and_caret() {
	home := notes_test_home('resize')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	a.new_note()
	text := '日'.repeat(5000)
	defer { unsafe { text.free() } }
	a.focus_field(2)
	a.paste_input(text)
	begin_frame_elements()
	narrow := a.build(ui2.rect(0, 0, 500, 300))!
	free_tree(narrow)
	a.body_scroll = a.wrap_count - a.text_rows
	previous_scroll := a.body_scroll
	begin_frame_elements()
	wide := a.build(ui2.rect(0, 0, 1200, 600))!
	assert a.body_scroll < previous_scroll && a.body_scroll > 0
	assert a.cursor_row() >= a.body_scroll && a.cursor_row() < a.body_scroll + a.text_rows
	mut text_visible := false
	mut caret_visible := false
	for panel in wide.children {
		if panel.id != 'notes.body' { continue }
		for child in panel.children {
			if child.text.len > 0 { text_visible = true }
			if child.frame.width == 1 && child.frame.height == 17 { caret_visible = true }
		}
	}
	assert text_visible && caret_visible
	free_tree(wide)
	begin_frame_elements()
	tall := a.build(ui2.rect(0, 0, 1200, 1400))!
	assert a.wrap_count < a.text_rows && a.body_scroll == 0
	free_tree(tall)
	a.pointer_event(.scroll, .no_button, -100, 300, 120, 1200, 1400)
	assert a.body_scroll == 0
	begin_frame_elements()
	shallow := a.build(ui2.rect(0, 0, 1200, 242))!
	assert a.text_rows == 1 && a.body_scroll < a.wrap_count
	free_tree(shallow)
	a.close_app()
}

fn test_notes_normal_close_saves_or_preserves_an_invalid_draft_until_explicit_discard() {
	home := notes_test_home('close-invalid')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	a.new_note()
	notes_test_edit(mut a, 'Saved title', 'saved body')
	assert a.prepare_close() && !a.dirty
	a.focus_field(1)
	a.key_input('\x01\x7f')
	assert !a.prepare_close() && a.dirty && a.close_requested
	assert a.status == 'notes.title_required'
	assert !a.prepare_close() && !a.discard_allowed
	a.handle('notes.confirm_discard')!
	assert !a.discard_allowed
	a.handle('notes.discard')!
	assert a.discard_pending && !a.discard_allowed
	// Pressing X again cancels confirmation; it never chooses discard.
	assert !a.prepare_close() && !a.discard_pending && !a.discard_allowed
	a.handle('notes.keep_editing')!
	assert !a.close_requested && a.dirty
	a.paste_input('Repaired title')
	assert a.prepare_close() && !a.dirty
	a.focus_field(1)
	a.key_input('\x01\x7f')
	assert !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	assert a.discard_allowed && a.dirty && a.prepare_close()
	assert !a.poll_at(a.last_edit + notes_autosave_ms) && a.next_poll_ms() == 2000
	a.close_app()
	mut check := new_notes_app(home)
	assert check.items[0].title == 'Repaired title' && check.items[0].body == 'saved body'
	check.close_app()
}

fn test_notes_conflicting_close_export_retry_and_new_edits_revoke_discard_permission() {
	home := notes_test_home('close-conflict')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	a.new_note()
	notes_test_edit(mut a, 'Original', 'first')
	assert a.save()
	mut newer := new_notes_app(home)
	notes_test_edit(mut newer, 'Newer', 'stored')
	assert newer.save()
	notes_test_edit(mut a, 'Draft', 'unsaved 😀')
	assert !a.prepare_close() && a.status == 'notes.conflict'
	a.handle('notes.export')!
	assert a.export_status == 'notes.export_saved'
	assert !a.prepare_close() && a.dirty
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	assert a.prepare_close()
	a.focus_field(0)
	a.key_input('D')
	assert !a.discard_allowed && a.status == 'notes.unsaved' && !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.focus_field(3)
	a.paste_input('draft-export.txt')
	assert !a.discard_allowed && a.status == 'notes.unsaved' && !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.focus_field(2)
	a.key_input('X')
	assert !a.discard_allowed && !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.key_input('\x7f')
	assert !a.discard_allowed && !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.key_input('\x01')
	a.paste_input('Replaced draft')
	assert !a.discard_allowed && !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.handle('notes.save')!
	assert !a.discard_allowed && !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.handle('notes.keep_editing')!
	assert a.status == 'notes.unsaved'
	assert !a.discard_allowed && !a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.close_app()
	newer.close_app()
	mut check := new_notes_app(home)
	assert check.items[0].title == 'Newer' && check.items[0].body == 'stored'
	check.close_app()
}

fn test_notes_history_restores_atomic_utf8_pastes_title_body_cursor_and_focus() {
	home := notes_test_home('history-fields')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	assert !a.can_undo() && !a.can_redo()
	a.paste_input('日本語 title')
	assert a.history_count == 1
	a.focus_field(2)
	a.paste_input('日😀\nРусский')
	assert a.history_count == 2
	a.key_input('\x1b[H')
	previous_cursor := a.cursor
	a.key_input('X')
	assert a.history_count == 3
	a.key_input('\x1a')
	assert editor_bytes_text(a.body) == '日😀\nРусский'
	assert a.cursor == previous_cursor && a.focus == 2 && a.can_redo()
	a.key_input('\x1a')
	assert a.body.len == 0 && a.focus == 2 && a.cursor == 0
	a.handle('notes.undo')!
	assert editor_bytes_text(a.title) == tr('notes.untitled') && a.focus == 1 && a.select_all
	assert !a.can_undo() && a.can_redo()
	a.handle('notes.redo')!
	assert editor_bytes_text(a.title) == '日本語 title' && a.focus == 2
	a.key_input('\x19\x19')
	assert editor_bytes_text(a.body) == '日😀\nXРусский' && !a.can_redo()
	a.close_app()
}

fn test_notes_history_has_32_shared_slots_and_real_edits_alone_invalidate_redo() {
	home := notes_test_home('history-bound')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	a.focus_field(2)
	for _ in 0 .. 40 { a.key_input('日') }
	assert a.history_count == notes_history_limit && a.history_position == notes_history_limit
	for _ in 0 .. notes_history_limit { a.restore_history(false) }
	assert a.body.len == 8 * 3 && !a.can_undo() && a.can_redo()
	for _ in 0 .. notes_history_limit { a.restore_history(true) }
	assert a.body.len == 40 * 3 && a.can_undo() && !a.can_redo()
	a.restore_history(false)
	position := a.history_position
	a.paste_input('')
	a.key_input('\x1b[F')
	a.key_input('\x1b[3~') // Navigation and deleting past the end leave history intact.
	a.paste_input('\xff')
	oversize := 'x'.repeat(notes_body_limit + 1)
	a.paste_input(oversize)
	unsafe { oversize.free() }
	assert a.history_position == position && a.can_redo()
	a.key_input('\x01')
	same := editor_bytes_text(a.body).clone()
	a.paste_input(same)
	unsafe { same.free() }
	assert a.history_position == position && a.can_redo()
	a.focus_field(0)
	a.paste_input('日')
	a.focus_field(3)
	a.key_input('z\x7f')
	assert a.history_position == position && a.can_redo()
	a.focus_field(2)
	a.key_input('X')
	assert a.history_count == notes_history_limit && !a.can_redo()
	a.restore_history(false)
	assert a.body.len == 39 * 3
	a.close_app()
}

fn test_notes_history_selection_forward_delete_and_backspace_are_utf8_edits() {
	home := notes_test_home('history-delete')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	a.focus_field(2)
	a.paste_input('日😀')
	a.key_input('\x1b[D')
	a.key_input('\x1b[3~')
	assert editor_bytes_text(a.body) == '日' && a.cursor == 3
	a.restore_history(false)
	assert editor_bytes_text(a.body) == '日😀' && a.cursor == 3
	a.restore_history(true)
	a.key_input('\x7f')
	assert a.body.len == 0 && a.cursor == 0
	a.restore_history(false)
	assert editor_bytes_text(a.body) == '日' && a.cursor == 3
	a.key_input('\x01')
	a.paste_input('😀\nreplacement')
	a.restore_history(false)
	assert editor_bytes_text(a.body) == '日' && a.select_all && a.cursor == 3
	a.restore_history(true)
	a.key_input('\x01\x7f')
	assert a.body.len == 0
	a.restore_history(false)
	assert editor_bytes_text(a.body) == '😀\nreplacement' && a.select_all
	a.restore_history(true)
	count := a.history_count
	a.backspace(false)
	a.backspace(true)
	assert a.history_count == count && !a.can_redo()
	a.close_app()
}

fn test_notes_history_survives_autosave_failed_save_and_revokes_close_discard_choice() {
	home := notes_test_home('history-save')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	notes_test_edit(mut a, 'Saved', '日😀')
	assert a.poll_at(a.last_edit + notes_autosave_ms) && !a.dirty && a.history_count == 2
	a.restore_history(false)
	assert a.dirty && a.body.len == 0
	assert a.poll_at(a.last_edit + notes_autosave_ms) && !a.dirty && a.can_redo()
	a.restore_history(true)
	assert editor_bytes_text(a.body) == '日😀' && a.save()
	a.focus_field(1)
	a.key_input('\x01\x7f')
	assert !a.prepare_close() && a.status == 'notes.title_required'
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	assert a.discard_allowed
	a.key_input('\x1a')
	assert !a.discard_allowed && !a.close_requested && editor_bytes_text(a.title) == 'Saved'
	assert a.prepare_close() && a.can_redo()
	a.key_input('\x19')
	assert !a.prepare_close() && a.dirty
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.close_app()
	mut check := new_notes_app(home)
	assert check.items[0].title == 'Saved' && check.items[0].body == '日😀'
	assert !check.can_undo() && !check.can_redo()
	check.close_app()
}

fn test_notes_history_blocked_operations_preserve_it_successful_note_changes_clear_it() {
	home := notes_test_home('history-conflict')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	notes_test_edit(mut a, 'First', 'one')
	assert a.save()
	a.new_note()
	assert a.history_count == 0
	notes_test_edit(mut a, 'Second', 'two')
	assert a.save()
	a.select_note(0)
	assert a.history_count == 0
	a.key_input('draft')
	mut newer := new_notes_app(home)
	newer.focus_field(2)
	newer.paste_input('newer')
	assert newer.save()
	count := a.history_count
	assert !a.save() && a.status == 'notes.conflict'
	a.select_note(1)
	a.new_note()
	a.delete_note()
	a.reload()
	assert a.selected == 0 && a.count == 2 && a.history_count == count
	a.restore_history(false)
	assert a.can_redo() && !a.save()
	a.close_app()
	newer.close_app()
	mut b := new_notes_app(home)
	b.focus_field(2)
	b.paste_input('changed')
	assert b.save() && b.history_count == 1
	b.select_note(0)
	assert b.history_count == 1 // Selecting the same note preserves history.
	b.reload()
	assert b.history_count == 0
	b.focus_field(2)
	b.paste_input('changed again')
	assert b.save()
	b.delete_note()
	assert b.history_count == 1 && b.delete_pending
	b.delete_note()
	assert b.history_count == 0 && b.count == 1 && b.selected == 0
	b.close_app()
}

fn test_notes_history_buttons_reflect_both_directions_at_default_compact_and_tiny_sizes() {
	home := notes_test_home('history-layout')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	for size in [ui2.rect(0, 0, 820, 576), ui2.rect(0, 0, 500, 300), ui2.rect(0, 0, 500, 242), ui2.rect(0, 0, 180, 96)]! {
		for state in 0 .. 3 {
			if state == 1 { a.paste_input('Changed') }
			if state == 2 { a.restore_history(false) }
			begin_frame_elements()
			tree := a.build(size)!
			mut seen := 0
			for control in tree.children {
				if control.id !in ['notes.undo', 'notes.redo'] { continue }
				seen++
				assert control.enabled == (if control.id == 'notes.undo' { a.can_undo() } else { a.can_redo() })
				assert control.frame.x >= 0 && control.frame.y >= 0
				assert control.frame.width > 0 && control.frame.height > 0
				assert control.frame.x + control.frame.width <= size.width
				assert control.frame.y + control.frame.height <= size.height
			}
			assert seen == 2
			free_tree(tree)
		}
		a.clear_history()
		a.load_selected(0)
		a.focus_field(1)
		a.select_all = true
	}
	a.close_app()
}

fn test_notes_tiny_history_view_keeps_explicit_failed_save_close_choices_accessible() {
	home := notes_test_home('history-tiny-close')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	assert a.save()
	a.focus_field(1)
	a.key_input('\x01\x7f')
	assert !a.prepare_close()
	for size in [ui2.rect(0, 0, 180, 96), ui2.rect(0, 0, 500, 242), ui2.rect(0, 0, 600, 300)]! {
		assert !a.prepare_close()
		for confirming in [false, true]! {
			if confirming { a.handle('notes.discard')! }
			begin_frame_elements()
			tree := a.build(size)!
			mut keep := false
			mut discard := false
			mut confirm := false
			for control in tree.children {
				keep = keep || control.id == 'notes.keep_editing'
				discard = discard || control.id == 'notes.discard'
				confirm = confirm || control.id == 'notes.confirm_discard'
				assert control.frame.x >= 0 && control.frame.y >= 0
				assert control.frame.width > 0 && control.frame.height > 0
				assert control.frame.x + control.frame.width <= size.width
				assert control.frame.y + control.frame.height <= size.height
			}
			assert keep && discard && confirm == confirming
			free_tree(tree)
		}
	}
	a.handle('notes.keep_editing')!
	assert !a.close_requested && !a.discard_allowed && a.dirty
	a.key_input('\x1a')
	assert a.prepare_close() && !a.dirty
	a.close_app()
}


fn notes_test_import_path(mut app NotesApp, path string) {
 app.open_import()
 app.key_input('\x01')
 app.paste_input(path)
}

fn test_notes_text_import_publishes_current_draft_and_utf8_note_atomically() {
 home := notes_test_home('import')
 source := join_path(home, '日本語.TXT')
 defer { os.rmdir_all(home) or {} unsafe { home.free() source.free() } }
 os.write_file(source, '\xef\xbb\xbfFirst\r\n日本語\t😀\rLast\n')!
 mut app := new_notes_app(home)
 app.new_note()
 notes_test_edit(mut app, 'Old title', 'old body')
 assert app.save()
 notes_test_edit(mut app, 'Draft title', 'unsaved body')
 assert app.dirty && app.can_undo()
 notes_test_import_path(mut app, source)
 app.handle('notes.import_confirm')!
 assert !app.importing && !app.dirty && app.count == 2 && app.selected == 1
 assert app.items[0].title == 'Draft title' && app.items[0].body == 'unsaved body'
 assert app.items[1].id == 2 && app.next_id == 3
 assert editor_bytes_text(app.title) == '日本語'
 assert editor_bytes_text(app.body) == 'First\n日本語\t😀\nLast\n'
 assert app.status == 'notes.import_saved' && !app.can_undo()
 assert app.query.len == 0 && app.matched == 2
 // An old confirmation packet cannot import the file again after closing.
 app.handle('notes.import_confirm')!
 assert app.count == 2
 saved := app.record.clone()
 original := os.read_file(source)!
 assert original == '\xef\xbb\xbfFirst\r\n日本語\t😀\rLast\n'
 unsafe { original.free() }
 app.close_app()
 mut reopened := new_notes_app(home)
 assert reopened.count == 2 && reopened.record == saved
 assert reopened.items[0].body == 'unsaved body'
 assert reopened.items[1].body == 'First\n日本語\t😀\nLast\n'
 reopened.close_app()
 unsafe { saved.free() }
}

fn test_notes_import_normalized_size_empty_file_and_utf8_title_bounds() {
 home := notes_test_home('import-limits')
 source := join_path(home, 'lines.txt')
 defer { os.rmdir_all(home) or {} unsafe { home.free() source.free() } }
 mut app := new_notes_app(home)
 crlf := '\r\n'.repeat(notes_body_limit)
 os.write_file(source, crlf)!
 unsafe { crlf.free() }
 notes_test_import_path(mut app, source)
 app.import_note()
 assert app.count == 1 && app.body.len == notes_body_limit && !app.dirty
 for byte in app.body { assert byte == `\n` }
 os.write_file(source, '')!
 notes_test_import_path(mut app, source)
 app.import_note()
 assert app.count == 2 && app.body.len == 0 && editor_bytes_text(app.title) == 'lines'
 old_record := app.record.clone()
 oversized := 'x'.repeat(notes_body_limit + 1)
 os.write_file(source, oversized)!
 unsafe { oversized.free() }
 notes_test_import_path(mut app, source)
 app.import_note()
 assert app.count == 2 && app.import_status == 'notes.limit' && app.record == old_record
 os.write_file(source, '\xffbroken')!
 app.import_note()
 assert app.count == 2 && app.import_status == 'notes.invalid_text' && app.record == old_record
 os.write_file(source, 'nul\x00byte')!
 app.import_note()
 assert app.count == 2 && app.import_status == 'notes.invalid_text'
 app.cancel_import()
 filename := '日'.repeat(60) + '.txt'
 long_path := join_path(home, filename)
 title := notes_import_title(long_path)
 assert title.len == 159 && notes_valid_text(title, notes_title_limit, false)
 assert title == '日'.repeat(53)
 unsafe { filename.free() long_path.free() title.free() old_record.free() }
 app.close_app()
}

fn test_notes_import_conflicts_invalid_sources_and_cancel_preserve_draft_and_history() {
 home := notes_test_home('import-failures')
 source := join_path(home, 'source.txt')
 link := join_path(home, 'linked.txt')
 directory := join_path(home, 'folder')
 defer { os.rmdir_all(home) or {} unsafe { home.free() source.free() link.free() directory.free() } }
 os.write_file(source, 'imported body')!
 os.symlink(source, link)!
 os.mkdir(directory)!
 mut app := new_notes_app(home)
 app.new_note()
 notes_test_edit(mut app, 'Saved', 'saved body')
 assert app.save()
 notes_test_edit(mut app, 'Draft', 'draft body')
 history := app.history_count
 cursor := app.cursor
 snapshot := app.record.clone()
 for invalid in [link, directory, '/dev/null', '/relative/../file']! {
  notes_test_import_path(mut app, invalid)
  app.import_note()
  assert app.importing && app.count == 1 && app.selected == 0 && app.next_id == 2
  assert editor_bytes_text(app.title) == 'Draft' && editor_bytes_text(app.body) == 'draft body'
  assert app.history_count == history && app.cursor == cursor && app.record == snapshot && app.dirty
 }
 notes_test_import_path(mut app, source)
 lock_fd := notes_lock(app.home_fd)
 assert lock_fd >= 0
 app.import_note()
 assert app.import_status == 'notes.save_failed' && app.count == 1 && app.record == snapshot
 desktop_close(lock_fd)
 mut other := new_notes_app(home)
 notes_test_edit(mut other, 'Newer', 'other body')
 assert other.save()
 app.import_note()
 assert app.import_status == 'notes.conflict' && app.count == 1 && app.record == snapshot
 assert app.history_count == history && app.dirty && editor_bytes_text(app.body) == 'draft body'
 app.handle('notes.new')!
 assert app.count == 1 // Modal import ignores background actions.
 app.key_input('\x1b')
 assert !app.importing && app.focus == 2 && app.history_count == history && app.dirty
 app.handle('notes.import_confirm')!
 assert app.count == 1 && editor_bytes_text(app.body) == 'draft body'
 app.discard_allowed = true
 app.close_app()
 other.close_app()
 unsafe { snapshot.free() }
}

fn test_notes_import_popup_keyboard_bounds_and_registered_home_anchor() {
 home := notes_test_home('import-ui')
 registered := home + '-registration'
 source := join_path(home, 'input.txt')
 alias_source := join_path(registered, 'input.txt')
 defer { os.rm(registered) or {} os.rmdir_all(home) or {} unsafe { home.free() registered.free() source.free() alias_source.free() } }
 os.write_file(source, 'from registered HOME')!
 os.symlink(home, registered)!
 mut app := new_notes_app(registered)
 app.key_input('\x0f')
 assert app.importing && app.focus == 4
 app.paste_input(alias_source)
 for size in [ui2.rect(0, 0, 820, 576), ui2.rect(0, 0, 380, 218), ui2.rect(0, 0, 180, 96), ui2.rect(0, 0, 20, 10)]! {
  begin_frame_elements()
  tree := app.build(size)!
  for child in tree.children {
   assert child.frame.x >= 0 && child.frame.y >= 0 && child.frame.width >= 0 && child.frame.height >= 0
   assert child.frame.x + child.frame.width <= size.width && child.frame.y + child.frame.height <= size.height
  }
  free_tree(tree)
 }
 app.key_input('\r')
 assert !app.importing && app.count == 1 && editor_bytes_text(app.body) == 'from registered HOME'
 app.close_app()
}
