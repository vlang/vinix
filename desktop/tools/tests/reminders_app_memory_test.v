// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"
#include "@VMODROOT/reminders_heap_test_guard.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_reminders_heap_require_tracking()
fn C.vinix_reminders_heap_require_clean()

fn reminders_heap_descriptors() int {
	mut count := 0
	for fd in 0 .. 512 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn reminders_heap_home(suffix string) string {
	pid := os.getpid().str()
	name := 'vinix-reminders-heap-${pid}-${suffix}'
	base := os.temp_dir()
	path := join_path(base, name)
	os.mkdir(path) or { panic(err) }
	canonical := os.real_path(path)
	unsafe { pid.free() name.free() base.free() path.free() }
	return canonical
}

fn reminders_heap_add(mut app RemindersApp, title string, due string) {
	app.begin_edit(-1)
	app.paste_input(title)
	app.handle('reminders.due') or { panic(err) }
	app.paste_input(due)
	app.handle('reminders.priority.high') or { panic(err) }
	app.save_edit()
}

fn test_reminders_repeated_edits_filters_exports_reload_and_frames_release_owned_memory() {
	home := reminders_heap_home('workflows')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, 'export.txt')
	defer { unsafe { path.free() } }
	mut app := new_reminders_app(home, 0)
	reminders_heap_add(mut app, 'Warm task', '2028-02-29')
	app.begin_edit(0)
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 800, 616))!
	free_tree(warm)
	app.cancel_edit()
	app.selected = 0
	app.confirming_delete = true
	app.delete_selected()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		reminders_heap_add(mut app, 'Café 日本語 😀', '2028-02-29 12:00')
		assert app.data.count == 1 && !app.editing
		app.handle('reminders.row.0')!
		app.toggle_selected()
		assert app.data.items[0].completed && app.data.items[0].priority == .high
		app.handle('reminders.filter.completed')!
		app.handle('reminders.search')!
		app.key_input('\x01')
		app.paste_input('日本語')
		assert app.match_count == 1
		app.handle('reminders.export_path')!
		app.key_input('\x01')
		app.paste_input(path)
		app.export_visible(false)
		assert app.status == 'reminders.export_saved'
		assert desktop_unlink(path) == 0
		csv := app.visible_text(true)
		assert csv.contains('"Café 日本語 😀","2028-02-29 12:00",1,"High"')
		unsafe { csv.free() }
		app.reload()
		assert app.data.count == 1 && app.data.items[0].priority == .high
		app.handle('reminders.row.0')!
		app.begin_edit(0)
		app.key_input('\x01')
		app.paste_input('Renamed 😀')
		app.handle('reminders.priority.medium')!
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 800, 616))!
		free_tree(tree)
		app.save_edit()
		assert !app.editing && app.data.items[0].priority == .medium
		app.handle('reminders.search')!
		app.key_input('\x01\x7f')
		app.handle('reminders.row.0')!
		app.handle('reminders.delete')!
		app.delete_selected()
		assert app.data.count == 0
		app.handle('reminders.filter.all')!
	}
	app.close_app()
	app.close_app()
	C.vinix_reminders_heap_require_clean()
}

fn test_reminders_repeated_initialization_and_close_release_all_model_buffers_and_descriptors() {
	home := reminders_heap_home('lifecycle')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut warm := new_reminders_app(home, 0)
	reminders_heap_add(mut warm, 'Persisted 😀', '2028-02-29')
	begin_frame_elements()
	tree := warm.build(ui2.rect(0, 0, 800, 616))!
	free_tree(tree)
	warm.close_app()
	descriptors := reminders_heap_descriptors()
	C.vinix_heap_begin()
	for _ in 0 .. 40 {
		mut app := new_reminders_app(home, 0)
		assert app.data.count == 1 && app.data.items[0].priority == .high
		assert app.data.items[0].title == 'Persisted 😀'
		app.reload()
		begin_frame_elements()
		frame := app.build(ui2.rect(0, 0, 800, 616))!
		free_tree(frame)
		app.close_app()
		app.close_app()
	}
	assert reminders_heap_descriptors() == descriptors
	C.vinix_reminders_heap_require_clean()
}

fn test_reminders_parse_failure_and_save_conflict_paths_release_temporary_allocations() {
	home := reminders_heap_home('failure')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut first := new_reminders_app(home, 0)
	mut second := new_reminders_app(home, 0)
	reminders_heap_add(mut first, 'First saved task', '')
	begin_frame_elements()
	warm := second.build(ui2.rect(0, 0, 800, 616))!
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		reminders_heap_add(mut second, 'Pending task 😀', '2028-02-29')
		assert second.editing && second.status == 'reminders.changed'
		assert editor_bytes_text(second.title_input) == 'Pending task 😀'
		assert second.edit_priority == .high
		second.cancel_edit()
		mut invalid := reminders_parse('VINIX-REMINDERS 1\n0\t\tGood first row\n0\t2026-02-30\tBad second row\n') or { continue }
		invalid.free_items()
		assert false, 'invalid record accepted'
	}
	first.close_app()
	second.close_app()
	C.vinix_reminders_heap_require_clean()
}

fn test_reminders_priority_legacy_parse_failure_and_draft_cancel_release_all_owned_memory() {
	home := reminders_heap_home('priority-parser')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	app.begin_edit(-1)
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 800, 616))!
	free_tree(warm)
	app.cancel_edit()
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		mut legacy := reminders_parse('VINIX-REMINDERS 1\n0\t2028-02-29\tLegacy\n1\t\tDone\n') or { panic('legacy parse') }
		assert legacy.items[0].priority == .none && legacy.items[1].priority == .none
		legacy.free_items()
		mut current := reminders_parse('VINIX-REMINDERS 2\n0\t1\t\tLow\n0\t2\t\tMedium\n1\t3\t\tHigh\n') or { panic('v2 parse') }
		assert current.items[0].priority == .low && current.items[1].priority == .medium && current.items[2].priority == .high
		current.free_items()
		for invalid in ['VINIX-REMINDERS 2\n0\t3\t\tGood\n0\t4\t\tBad\n',
			'VINIX-REMINDERS 2\n0\t3\t\tGood\n0\t3\t2026-02-30\tBad date\n']! {
			mut parsed := reminders_parse(invalid) or { continue }
			parsed.free_items()
			assert false, 'invalid priority record accepted'
		}
		app.begin_edit(-1)
		app.paste_input('Canceled task')
		app.handle('reminders.priority.high')!
		assert app.edit_priority == .high
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 480, 616))!
		free_tree(tree)
		app.cancel_edit()
		assert app.edit_priority == .none && app.data.count == 0
	}
	app.close_app()
	C.vinix_reminders_heap_require_clean()
}

fn test_reminders_full_bounded_sorting_filter_exports_and_draft_frames_retain_no_memory() {
	home := reminders_heap_home('sort-full')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	mut bytes := []u8{cap: 16384}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, reminders_record_header)
	for index in 0 .. reminders_limit {
		title := match index % 4 { 0 { 'Alpha' } 1 { 'alpha' } 2 { '日本語' } else { '😀' } }
		due := match index % 4 { 0 { '' } 1 { '2028-02-29 09:00' } 2 { '2028-02-29' } else { '2027-01-01' } }
		priority := match index % 4 { 0 { ReminderPriority.none } 1 { ReminderPriority.high } 2 { ReminderPriority.medium } else { ReminderPriority.low } }
		reminders_append_row(mut bytes, title, due, false, priority)
	}
	assert app.publish(editor_bytes_text(bytes))
	unsafe { bytes.free() }
	app.selected = 0
	app.begin_edit(0)
	app.handle('reminders.priority.high')!
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 480, 616))!
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for order in [RemindersSort.manual, RemindersSort.priority, RemindersSort.due, RemindersSort.title]! {
			app.handle(reminders_sort_key(order))!
			assert app.sort == order && app.selected == 0
			assert app.editing && app.edit_index == 0 && app.edit_priority == .high
			assert editor_bytes_text(app.title_input) == 'Alpha' && app.data.items[0].priority == .none
			assert app.match_count == reminders_limit
			if order == .manual { assert app.matches[255] == 255 }
			else if order == .priority { assert app.matches[0] == 1 && app.matches[63] == 253 && app.matches[255] == 252 }
			else if order == .due { assert app.matches[0] == 3 && app.matches[63] == 255 && app.matches[255] == 252 }
			else { assert app.matches[0] == 0 && app.matches[63] == 252 && app.matches[255] == 255 }
			csv := app.visible_text(true)
			text := app.visible_text(false)
			assert csv.len > 4000 && text.len > 4000
			unsafe { csv.free() text.free() }
			begin_frame_elements()
			tree := app.build(ui2.rect(0, 0, 480, 616))!
			free_tree(tree)
		}
		app.handle('reminders.search')!
		app.key_input('\x01')
		app.paste_input('Alpha')
		assert app.match_count == 64 && app.selected == 0
		app.handle('reminders.sort.due')!
		assert app.matches[0] == 0 && app.matches[63] == 252
		app.handle('reminders.search')!
		app.key_input('\x01\x7f')
		app.handle('reminders.filter.open')!
		assert app.match_count == reminders_limit && app.edit_index == 0
		app.handle('reminders.filter.all')!
	}
	app.close_app()
	C.vinix_reminders_heap_require_clean()
}

fn test_reminders_direction_controls_full_model_exports_and_compact_frames_release_all_allocations() {
	$if prod { panic('Reminders memory coverage requires enabled assertions') }
	// Prove that the C checks observe a real V heap allocation before measuring.
	C.vinix_heap_begin()
	sentinel := 'Reminders heap tracker guard'.clone()
	C.vinix_reminders_heap_require_tracking()
	unsafe { sentinel.free() }
	C.vinix_reminders_heap_require_clean()
	home := reminders_heap_home('direction-full')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	mut bytes := []u8{cap: 16384}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, reminders_record_header)
	for index in 0 .. reminders_limit {
		title := match index % 4 { 0 { 'Alpha' } 1 { 'alpha' } 2 { '日本語' } else { '😀' } }
		due := match index % 4 { 0 { '' } 1 { '2028-02-29 09:00' } 2 { '2028-02-29' } else { '2027-01-01' } }
		priority := match index % 4 { 0 { ReminderPriority.none } 1 { ReminderPriority.high } 2 { ReminderPriority.medium } else { ReminderPriority.low } }
		reminders_append_row(mut bytes, title, due, false, priority)
	}
	assert app.publish(editor_bytes_text(bytes))
	unsafe { bytes.free() }
	app.selected = 0
	app.begin_edit(0)
	app.paste_input(' direction draft')
	for dimensions in [[800, 616]!, [480, 616]!, [360, 616]!, [360, 2000]!, [240, 300]!, [180, 144]!, [120, 100]!, [60, 40]!]! {
		begin_frame_elements()
		warm := app.build(ui2.rect(0, 0, dimensions[0], dimensions[1]))!
		free_tree(warm)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 40 {
		for order in [RemindersSort.manual, RemindersSort.priority, RemindersSort.due, RemindersSort.title]! {
			app.handle(reminders_sort_key(order))!
			app.focus_field(5)
			app.key_input('\x1b[C')
			assert app.sort_reversed[int(order)] && app.selected == 0
			assert app.editing && app.edit_index == 0
			assert editor_bytes_text(app.title_input) == 'Alpha direction draft'
			assert app.data.items[0].title == 'Alpha' && app.match_count == reminders_limit
			if order == .manual { assert app.matches[0] == 255 && app.matches[255] == 0 }
			else if order == .priority { assert app.matches[0] == 0 && app.matches[63] == 252 && app.matches[255] == 253 }
			else if order == .due { assert app.matches[0] == 1 && app.matches[63] == 253 && app.matches[255] == 252 }
			else { assert app.matches[0] == 3 && app.matches[63] == 255 && app.matches[255] == 252 }
			for dimensions in [[800, 616]!, [480, 616]!, [360, 616]!, [360, 2000]!, [240, 300]!, [180, 144]!, [120, 100]!, [60, 40]!]! {
				begin_frame_elements()
				tree := app.build(ui2.rect(0, 0, dimensions[0], dimensions[1]))!
				free_tree(tree)
			}
			csv := app.visible_text(true)
			text := app.visible_text(false)
			assert csv.len > 4000 && text.len > 4000
			unsafe { csv.free() text.free() }
			app.handle('reminders.direction.toggle')!
			assert !app.sort_reversed[int(order)] && app.edit_index == 0
		}
		app.handle('reminders.search')!
		app.key_input('\x01')
		app.paste_input('Alpha')
		app.handle('reminders.sort.manual')!
		app.handle('reminders.direction.toggle')!
		assert app.match_count == 64 && app.matches[0] == 252 && app.matches[63] == 0
		app.handle('reminders.search')!
		app.key_input('\x01\x7f')
		app.set_sort_reversed(false)
	}
	app.close_app()
	C.vinix_reminders_heap_require_clean()
}
