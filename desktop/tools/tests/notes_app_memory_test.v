// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

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
	assert C.vinix_heap_end() == 0
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
	assert C.vinix_heap_end() == 0
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
	assert C.vinix_heap_end() == 0
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
	assert C.vinix_heap_end() == 0
}
