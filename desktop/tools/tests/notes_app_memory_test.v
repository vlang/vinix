// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"
#include "@VMODROOT/notes_heap_test_guard.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_notes_heap_require_tracking()
fn C.vinix_notes_heap_require_clean()

fn notes_heap_home(name string) string {
	base := os.real_path(os.temp_dir())
	pid := os.getpid().str()
	path := '${base}/vinix-notes-heap-${name}-${pid}'
	unsafe {
		base.free()
		pid.free()
	}
	os.rmdir_all(path) or {}
	os.mkdir(path) or { panic(err) }
	return path
}

fn test_notes_repeated_model_saves_filter_build_poll_and_exports_release_all_owned_bytes() {
	home := notes_heap_home('operations')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	export_path := join_path(home, 'export.txt')
	defer { unsafe { export_path.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	assert a.save()
	begin_frame_elements()
	warm := a.build(ui2.rect(0, 0, 820, 576))!
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		a.focus_field(1)
		a.key_input('\x01')
		a.paste_input('日本語 😀')
		a.focus_field(2)
		a.key_input('\x01')
		a.paste_input('First\nРусский\t😀')
		a.key_input('\x1b[D')
		a.key_input('X\x7f')
		assert a.poll_at(a.last_edit + notes_autosave_ms)
		a.focus_field(0)
		a.key_input('\x01')
		a.paste_input('Русский')
		assert a.matched == 1
		assert notes_export(export_path, editor_bytes_text(a.title), editor_bytes_text(a.body)) == 'notes.export_saved'
		assert desktop_unlink(export_path) == 0
		begin_frame_elements()
		tree := a.build(ui2.rect(0, 0, 820, 576))!
		free_tree(tree)
		a.reload()
		assert !a.dirty
	}
	a.close_app()
	a.close_app()
	C.vinix_notes_heap_require_clean()
}

fn test_notes_init_close_creation_deletion_and_failed_parse_release_owned_bytes() {
	home := notes_heap_home('lifecycle')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	C.vinix_heap_begin()
	for _ in 0 .. 30 {
		mut a := new_notes_app(home)
		for index in 0 .. 10 {
			a.new_note()
			assert a.count == index + 1
			a.focus_field(2)
			a.paste_input('😀\n日本語')
			assert a.save()
		}
		for _ in 0 .. 10 {
			a.delete_note()
			a.delete_note()
		}
		assert a.count == 0
		assert !a.decode('VINIX-NOTES 1\n2\n1 2 0\n日本語\n')
		a.close_app()
	}
	C.vinix_notes_heap_require_clean()
}

fn test_notes_conflicting_saves_and_invalid_pastes_keep_drafts_without_leaks() {
	home := notes_heap_home('conflicts')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut first := new_notes_app(home)
	first.new_note()
	assert first.save()
	C.vinix_heap_begin()
	for _ in 0 .. 30 {
		mut second := new_notes_app(home)
		first.focus_field(2)
		first.paste_input('日')
		assert first.save()
		second.focus_field(2)
		second.paste_input('Draft 😀')
		assert !second.save() && second.dirty
		second.key_input('\x01')
		second.paste_input('\xff')
		assert editor_bytes_text(second.body).contains('Draft 😀')
		second.reload()
		second.close_app()
	}
	first.close_app()
	C.vinix_notes_heap_require_clean()
}

fn test_notes_maximum_text_wrapping_and_oversize_store_releases_buffers() {
	home := notes_heap_home('growth')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	text := '😀'.repeat(notes_body_limit / 4)
	defer { unsafe { text.free() } }
	begin_frame_elements()
	C.vinix_heap_begin()
	mut a := new_notes_app(home)
	for index in 0 .. 64 {
		a.items[index] = NotesEntry{ id: u64(index + 1), title: 'Dense'.clone(), body: text.clone() }
	}
	a.count = 64
	a.next_id = 65
	a.load_selected(0)
	a.mark_dirty()
	for _ in 0 .. 10 {
		assert !a.save() && a.status == 'notes.limit'
		begin_frame_elements()
		tree := a.build(ui2.rect(0, 0, 820, 576))!
		free_tree(tree)
		assert a.wrap_count > 50
	}
	a.close_app()
	C.vinix_notes_heap_require_clean()
}

fn test_notes_repeated_denied_close_confirmation_editing_frames_and_cleanup_keep_zero_bytes() {
	home := notes_heap_home('close')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	mut a := new_notes_app(home)
	a.new_note()
	assert a.save()
	a.focus_field(1)
	a.key_input('\x01\x7f')
	begin_frame_elements()
	warm := a.build(ui2.rect(0, 0, 820, 576))!
	free_tree(warm)
	// The close panel reserves fewer text rows and uses another arena bucket.
	// Warm both persistent frame capacities before measuring repeated frames.
	assert !a.prepare_close()
	a.handle('notes.discard')!
	begin_frame_elements()
	close_warm := a.build(ui2.rect(0, 0, 820, 576))!
	free_tree(close_warm)
	begin_frame_elements()
	small_warm := a.build(ui2.rect(0, 0, 180, 96))!
	free_tree(small_warm)
	a.handle('notes.keep_editing')!
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert !a.prepare_close() && a.close_requested
		a.handle('notes.discard')!
		begin_frame_elements()
		tree := a.build(ui2.rect(0, 0, 820, 576))!
		free_tree(tree)
		a.handle('notes.confirm_discard')!
		begin_frame_elements()
		small := a.build(ui2.rect(0, 0, 180, 96))!
		free_tree(small)
		assert a.prepare_close() && a.discard_allowed
		a.focus_field(2)
		a.paste_input('日😀')
		assert !a.discard_allowed
		a.key_input('\x01\x7f')
		assert !a.prepare_close()
		a.handle('notes.keep_editing')!
		assert !a.close_requested && a.dirty
	}
	a.prepare_close()
	a.handle('notes.discard')!
	a.handle('notes.confirm_discard')!
	a.close_app()
	C.vinix_notes_heap_require_clean()
}

fn test_notes_maximum_history_eviction_buffer_swaps_branching_and_idempotent_close_keep_zero_bytes() {
	home := notes_heap_home('history-maximum')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut text := []u8{len: notes_body_limit, init: `x`}
	defer { unsafe { text.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 20 {
		mut a := new_notes_app(home)
		if a.count == 0 { a.new_note() }
		a.focus_field(2)
		for index in 0 .. 40 {
			text[0] = if index % 2 == 0 { `a` } else { `b` }
			a.key_input('\x01')
			a.paste_input(editor_bytes_text(text))
		}
		assert a.history_count == notes_history_limit && a.body.len == notes_body_limit
		for _ in 0 .. notes_history_limit { a.restore_history(false) }
		assert !a.can_undo() && a.can_redo()
		for _ in 0 .. notes_history_limit { a.restore_history(true) }
		assert a.can_undo() && !a.can_redo()
		for _ in 0 .. 10 { a.restore_history(false) }
		a.key_input('\x01')
		a.paste_input('Branch 日😀')
		assert !a.can_redo()
		assert a.poll_at(a.last_edit + notes_autosave_ms)
		a.close_app()
		a.close_app()
	}
	C.vinix_notes_heap_require_clean()
}

fn test_notes_history_repeated_undo_redo_autosave_and_successful_scope_changes_release_all_snapshots() {
	home := notes_heap_home('history-scope')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut a := new_notes_app(home)
	a.new_note()
	a.focus_field(2)
	a.paste_input('日😀\nfirst')
	assert a.save()
	for size in [ui2.rect(0, 0, 820, 576), ui2.rect(0, 0, 500, 300), ui2.rect(0, 0, 180, 96)]! {
		begin_frame_elements()
		warm := a.build(size)!
		free_tree(warm)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 80 {
		a.focus_field(2)
		a.key_input('\x01')
		a.paste_input('changed\n日本語😀')
		for _ in 0 .. 10 {
			a.key_input('\x1a\x19')
			assert editor_bytes_text(a.body) == 'changed\n日本語😀'
		}
		assert a.poll_at(a.last_edit + notes_autosave_ms)
		a.new_note()
		assert a.history_count == 0
		a.focus_field(2)
		a.paste_input('Second draft')
		assert a.save()
		a.select_note(0)
		assert a.history_count == 0
		a.focus_field(2)
		a.key_input('X')
		assert a.save()
		a.reload()
		assert a.history_count == 0
		a.select_note(1)
		a.focus_field(1)
		a.key_input('\x01')
		a.paste_input('Delete me')
		assert a.save()
		a.delete_note()
		a.delete_note()
		assert a.history_count == 0 && a.count == 1
		begin_frame_elements()
		tree := a.build(ui2.rect(0, 0, 820, 576))!
		free_tree(tree)
	}
	a.close_app()
	C.vinix_notes_heap_require_clean()
}

fn test_notes_history_rejected_edits_and_failed_conflicting_store_actions_keep_zero_bytes() {
	home := notes_heap_home('history-failed')
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	oversize := 'x'.repeat(notes_body_limit + 1)
	defer { unsafe { oversize.free() } }
	mut first := new_notes_app(home)
	first.new_note()
	assert first.save()
	first.new_note()
	assert first.save()
	first.select_note(0)
	C.vinix_heap_begin()
	for _ in 0 .. 40 {
		mut stale := new_notes_app(home)
		first.focus_field(2)
		first.paste_input('日')
		assert first.save()
		stale.focus_field(2)
		stale.paste_input('Draft 😀')
		stale.paste_input('second')
		stale.restore_history(false)
		count := stale.history_count
		position := stale.history_position
		stale.paste_input('\xff')
		stale.paste_input(oversize)
		assert stale.history_count == count && stale.history_position == position && stale.can_redo()
		assert !stale.save()
		stale.select_note(1)
		stale.new_note()
		stale.delete_note()
		stale.reload()
		assert stale.history_count == count && stale.history_position == position && stale.selected == 0
		stale.key_input('\x19')
		assert !stale.prepare_close()
		stale.handle('notes.discard')!
		stale.handle('notes.confirm_discard')!
		stale.key_input('\x1a')
		assert !stale.discard_allowed
		stale.close_app()
	}
	first.close_app()
	C.vinix_notes_heap_require_clean()
}


fn test_notes_repeated_text_imports_publish_and_release_all_new_owners() {
 $if prod { panic('Notes retention fixtures require assertions') }
 home := notes_heap_home('imports')
 source := join_path(home, 'source.txt')
 defer { os.rmdir_all(home) or {} unsafe { home.free() source.free() } }
 os.write_file(source, '\xef\xbb\xbf日\r\n😀\tlast\r')!
 C.vinix_heap_begin()
 witness := 'notes import tracker witness'.clone()
 C.vinix_notes_heap_require_tracking()
 unsafe { witness.free() }
 mut app := new_notes_app(home)
 for index in 0 .. 100 {
  app.open_import()
  app.key_input('\x01')
  app.paste_input(source)
  app.import_note()
  assert !app.importing && !app.dirty && app.count == index + 1
  assert editor_bytes_text(app.body) == '日\n😀\tlast\n'
 }
 app.close_app()
 app.close_app()
 C.vinix_notes_heap_require_clean()
}

fn test_notes_failed_imports_and_modal_frames_keep_draft_history_and_zero_owned_bytes() {
 $if prod { panic('Notes retention fixtures require assertions') }
 home := notes_heap_home('import-failures')
 source := join_path(home, 'source.txt')
 defer { os.rmdir_all(home) or {} unsafe { home.free() source.free() } }
 os.write_file(source, '\xffinvalid')!
 mut app := new_notes_app(home)
 app.new_note()
 app.focus_field(2)
 app.paste_input('Draft 日😀')
 app.open_import()
 app.paste_input(source)
 begin_frame_elements()
 warm := app.build(ui2.rect(0, 0, 820, 576))!
 free_tree(warm)
 begin_frame_elements()
 small := app.build(ui2.rect(0, 0, 180, 96))!
 free_tree(small)
 history := app.history_count
 C.vinix_heap_begin()
 for _ in 0 .. 100 {
  app.import_note()
  assert app.import_status == 'notes.invalid_text' && app.count == 1 && app.dirty
  assert editor_bytes_text(app.body) == 'Draft 日😀' && app.history_count == history
  begin_frame_elements()
  tree := app.build(ui2.rect(0, 0, 820, 576))!
  free_tree(tree)
  begin_frame_elements()
  tiny := app.build(ui2.rect(0, 0, 180, 96))!
  free_tree(tiny)
  app.cancel_import()
  app.open_import()
 }
 app.discard_allowed = true
 app.close_app()
 C.vinix_notes_heap_require_clean()
}
