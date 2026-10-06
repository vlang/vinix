// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn reminders_test_home(suffix string) string {
	path := os.join_path(os.temp_dir(), 'vinix-reminders-${os.getpid()}-${suffix}')
	os.mkdir(path) or { panic(err) }
	canonical := os.real_path(path)
	unsafe { path.free() }
	return canonical
}

fn reminders_test_add(mut app RemindersApp, title string, due string) {
	app.begin_edit(-1)
	app.paste_input(title)
	app.handle('reminders.due') or { panic(err) }
	app.paste_input(due)
	app.save_edit()
}

fn test_reminders_create_complete_reopen_edit_delete_and_reload() {
	home := reminders_test_home('roundtrip')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	assert !app.read_failed
	reminders_test_add(mut app, '買い物 😀', '2028-02-29 13:45')
	assert app.data.count == 1
	assert !app.editing
	assert app.data.items[0].due == '2028-02-29 13:45'
	app.handle('reminders.row.0')!
	app.toggle_selected()
	assert app.data.items[0].completed
	app.toggle_selected()
	assert !app.data.items[0].completed
	mut reloaded := new_reminders_app(home, 0)
	defer { reloaded.close_app() }
	assert reloaded.data.count == 1
	assert reloaded.data.items[0].title == '買い物 😀'
	reloaded.begin_edit(0)
	reloaded.key_input('\x01')
	reloaded.paste_input('Updated')
	reloaded.handle('reminders.due')!
	reloaded.key_input('\x01\x7f')
	reloaded.save_edit()
	assert reloaded.data.items[0].title == 'Updated'
	assert reloaded.data.items[0].due == ''
	reloaded.handle('reminders.row.0')!
	reloaded.handle('reminders.delete')!
	assert reloaded.confirming_delete
	assert reloaded.data.count == 1
	reloaded.handle('reminders.delete_cancel')!
	reloaded.handle('reminders.delete_confirm')!
	assert reloaded.data.count == 1
	reloaded.handle('reminders.delete')!
	reloaded.handle('reminders.delete_confirm')!
	assert reloaded.data.count == 0
	app.reload()
	assert app.data.count == 0
}

fn test_reminders_due_parser_checks_gregorian_dates_and_local_time() {
	for due in ['', '0001-01-01', '9999-12-31', '2000-02-29', '2024-02-29 00:00', '2026-10-06 23:59']! {
		assert reminders_due_valid(due)
	}
	for due in ['0000-01-01', '1900-02-29', '2025-02-29', '2026-04-31', '2026-13-01', '2026-00-01',
		'2026-01-00', '2026-1-01', '2026-01-01 24:00', '2026-01-01 12:60', '2026-01-01T12:00',
		'2026-01-01 1a:00', '2026-01-01 9:00', '2026-01-01 12:00x']! {
		assert !reminders_due_valid(due)
	}
	home := reminders_test_home('invalid-date')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.begin_edit(-1)
	app.save_edit()
	assert app.status == 'reminders.title_required'
	app.paste_input('Appointment')
	app.handle('reminders.due')!
	app.paste_input('2025-02-29')
	app.save_edit()
	assert app.editing
	assert app.data.count == 0
	assert app.status == 'reminders.invalid_due'
	assert editor_bytes_text(app.title_input) == 'Appointment'
}

fn test_reminders_filters_search_and_overdue_preserve_visible_selection() {
	home := reminders_test_home('filters')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	reminders_test_add(mut app, 'Yesterday', '2026-10-05')
	reminders_test_add(mut app, 'Today', '2026-10-06')
	reminders_test_add(mut app, 'Morning', '2026-10-06 09:00')
	reminders_test_add(mut app, 'No date', '')
	app.today = 20261006
	app.minute_of_day = 600
	app.clock_valid = true
	assert app.is_overdue(0)
	assert !app.is_overdue(1)
	assert app.is_overdue(2)
	assert !app.is_overdue(3)
	assert app.due_status(1) == 'reminders.due_today'
	app.handle('reminders.filter.overdue')!
	assert app.match_count == 2
	assert app.matches[0] == 0 && app.matches[1] == 2
	app.handle('reminders.row.0')!
	app.toggle_selected()
	assert app.match_count == 1
	assert app.selected == -1
	app.handle('reminders.filter.completed')!
	assert app.match_count == 1
	app.handle('reminders.filter.open')!
	assert app.match_count == 3
	app.handle('reminders.search')!
	app.paste_input('Today')
	assert app.match_count == 1
	assert app.matches[0] == 1
	app.key_input('\x01\x7f')
	assert app.match_count == 3
	app.clock_valid = false
	app.handle('reminders.filter.overdue')!
	assert app.match_count == 0
}

fn test_reminders_clock_poll_updates_only_on_local_minute_changes() {
	home := reminders_test_home('clock')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 3600)
	defer { app.close_app() }
	reminders_test_add(mut app, 'Due', '1970-01-01 01:00')
	assert app.poll_time(0)
	assert app.today == 19700101 && app.minute_of_day == 60
	assert !app.is_overdue(0)
	assert !app.poll_time(30)
	assert app.poll_time(60)
	assert app.is_overdue(0)
	assert app.poll_time(-1)
	assert !app.clock_valid
	assert !app.is_overdue(0)
	assert !app.poll_time(-1)
}

fn test_reminders_keyboard_clipboard_utf8_limits_and_escape_commands() {
	home := reminders_test_home('utf8')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.begin_edit(-1)
	app.key_input('Привет😀')
	app.key_input('\x7f')
	assert editor_bytes_text(app.title_input) == 'Привет'
	app.key_input('\x01')
	app.paste_input('Café\n\t日本語\x1b\xff')
	assert editor_bytes_text(app.title_input) == 'Café日本語'
	app.key_input('\x1b[D')
	assert editor_bytes_text(app.title_input) == 'Café日本語'
	app.key_input('\x01')
	for _ in 0 .. reminders_title_limit - 1 { app.key_input('a') }
	app.key_input('é')
	assert app.title_input.len == reminders_title_limit - 1
	app.key_input('b')
	assert app.title_input.len == reminders_title_limit
	app.key_input('\x1b')
	assert !app.editing
	assert app.data.count == 0
}

fn test_reminders_corruption_read_failures_and_invalid_records_are_preserved() {
	home := reminders_test_home('corruption')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	bad := 'VINIX-REMINDERS 1\n0\t2026-02-30\tImpossible\n'
	os.write_file(path, bad)!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	assert app.read_failed
	assert app.status == 'reminders.read_failed'
	app.begin_edit(-1)
	assert !app.editing
	assert !app.publish(reminders_record_header)
	assert os.read_file(path)! == bad
	for record in ['VINIX-REMINDERS 3\n', 'VINIX-REMINDERS 1\n2\t\tInvalid\n',
		'VINIX-REMINDERS 1\n0\t\t\n', 'VINIX-REMINDERS 1\n0\t\tIncomplete',
		'VINIX-REMINDERS 1\n0\t\tInvalid\tfield\n', 'VINIX-REMINDERS 1\n0\t\tBad\xff\n']! {
		mut parsed := reminders_parse(record) or { continue }
		parsed.free_items()
		assert false, 'invalid reminder record accepted'
	}
	os.write_file(path, reminders_record_header)!
	app.reload()
	assert !app.read_failed && app.data.count == 0
	reminders_test_add(mut app, 'Good snapshot', '')
	os.write_file(path, bad)!
	app.reload()
	assert app.read_failed
	assert app.data.count == 1
	assert app.data.items[0].title == 'Good snapshot'
}

fn test_reminders_second_window_conflict_and_advisory_lock_keep_edits() {
	home := reminders_test_home('conflict')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut first := new_reminders_app(home, 0)
	mut second := new_reminders_app(home, 0)
	defer { first.close_app() second.close_app() }
	reminders_test_add(mut first, 'First window', '')
	reminders_test_add(mut second, 'Second window', '')
	assert second.editing
	assert second.status == 'reminders.changed'
	assert second.data.count == 0
	assert editor_bytes_text(second.title_input) == 'Second window'
	second.reload()
	assert !second.editing
	assert second.data.count == 1
	second.begin_edit(-1)
	second.paste_input('Locked edit')
	lock_fd := reminders_lock(second.home_fd)
	assert lock_fd >= 0
	second.save_edit()
	assert second.status == 'reminders.busy'
	assert second.editing && second.data.count == 1
	desktop_close(lock_fd)
	second.save_edit()
	assert !second.editing && second.data.count == 2
	first.reload()
	assert first.data.count == 2
}

fn test_reminders_record_lock_and_export_refuse_symlinks_and_existing_files() {
	home := reminders_test_home('symlinks')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	lock_path := join_path(home, '.vinix-reminders.lock')
	target := join_path(home, 'unrelated.txt')
	alias := join_path(home, 'alias')
	defer { unsafe { path.free() lock_path.free() target.free() alias.free() } }
	os.write_file(target, 'Original')!
	os.symlink(target, path)!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	assert app.read_failed
	os.rm(path)!
	app.reload()
	os.symlink(target, lock_path)!
	reminders_test_add(mut app, 'Rejected save', '')
	assert app.status == 'reminders.save_failed' && app.editing
	assert os.read_file(target)! == 'Original'
	assert !os.exists(path)
	os.rm(lock_path)!
	app.save_edit()
	assert app.data.count == 1
	assert reminders_write_export(target, 'Replacement') == 'reminders.export_exists'
	assert os.read_file(target)! == 'Original'
	os.symlink(home, alias)!
	linked_export := join_path(alias, 'export.txt')
	defer { unsafe { linked_export.free() } }
	assert reminders_write_export(linked_export, 'Data') == 'reminders.invalid_path'
	assert !os.exists(join_path(home, 'export.txt'))
}

fn test_reminders_exclusive_filtered_text_csv_export_and_frame_build() {
	home := reminders_test_home('export')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	reminders_test_add(mut app, '日本語, "quoted"', '2028-02-29')
	reminders_test_add(mut app, 'Hidden', '')
	app.handle('reminders.search')!
	app.paste_input('日本語')
	csv := app.visible_text(true)
	text := app.visible_text(false)
	defer { unsafe { csv.free() text.free() } }
	assert csv.contains('"日本語, ""quoted""","2028-02-29",0,"None"\n')
	assert !csv.contains('Hidden')
	assert text == '[ ] 日本語, "quoted"\t2028-02-29\tPriority: None\n'
	path := join_path(home, 'export.csv')
	defer { unsafe { path.free() } }
	app.handle('reminders.export_path')!
	app.key_input('\x01')
	app.paste_input(path)
	app.export_visible(true)
	assert app.status == 'reminders.export_saved'
	assert os.read_file(path)! == csv
	app.export_visible(false)
	assert app.status == 'reminders.export_exists'
	assert os.read_file(path)! == csv
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 800, 616))!
	free_tree(tree)
}

fn test_reminders_count_bound_rejects_new_tasks_and_oversized_storage() {
	home := reminders_test_home('limits')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	mut bytes := []u8{cap: 8192}
	defer { unsafe { bytes.free() } }
	editor_append(mut bytes, reminders_record_header)
	for _ in 0 .. reminders_limit { reminders_append_row(mut bytes, 'Task', '', false, .none) }
	assert app.publish(editor_bytes_text(bytes))
	assert app.data.count == reminders_limit
	app.begin_edit(-1)
	assert !app.editing && app.status == 'reminders.limit'
	path := join_path(home, reminders_filename)
	oversized := 'x'.repeat(reminders_record_limit + 1)
	os.write_file(path, oversized)!
	unsafe { path.free() oversized.free() }
	app.reload()
	assert app.read_failed
	assert app.data.count == reminders_limit
	reminders_append_row(mut bytes, 'One more', '', false, .none)
	mut invalid := reminders_parse(editor_bytes_text(bytes)) or { return }
	invalid.free_items()
	assert false, 'record above task count bound accepted'
}

fn test_reminders_trusted_home_alias_is_resolved_before_anchoring_records() {
	home := reminders_test_home('home-alias')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	alias := join_path(home, 'profile-alias')
	defer { unsafe { alias.free() } }
	os.symlink(home, alias)!
	mut app := new_reminders_app(alias, 0)
	defer { app.close_app() }
	assert !app.read_failed
	reminders_test_add(mut app, 'Aliased profile', '')
	assert app.data.count == 1
	mut direct := new_reminders_app(home, 0)
	defer { direct.close_app() }
	assert direct.data.count == 1
	assert direct.data.items[0].title == 'Aliased profile'
}

fn test_reminders_v1_record_stays_unchanged_until_saved_and_then_migrates() {
	home := reminders_test_home('priority-migration')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	legacy := 'VINIX-REMINDERS 1\n0\t2028-02-29\tLegacy task\n1\t\tCompleted legacy\n'
	os.write_file(path, legacy)!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	assert !app.read_failed && app.data.count == 2
	assert app.data.items[0].priority == .none && app.data.items[1].priority == .none
	assert app.data.items[1].completed
	app.begin_edit(0)
	app.handle('reminders.priority.high')!
	assert app.edit_priority == .high && app.data.items[0].priority == .none
	app.handle('reminders.cancel')!
	app.poll_time(0)
	app.reload()
	unchanged := os.read_file(path)!
	assert unchanged == legacy
	unsafe { unchanged.free() }
	app.begin_edit(0)
	assert app.edit_priority == .none
	app.handle('reminders.priority.medium')!
	app.save_edit()
	assert !app.editing && app.data.items[0].priority == .medium
	migrated := os.read_file(path)!
	assert migrated == 'VINIX-REMINDERS 2\n0\t2\t2028-02-29\tLegacy task\n1\t0\t\tCompleted legacy\n'
	unsafe { migrated.free() }
	mut reopened := new_reminders_app(home, 0)
	defer { reopened.close_app() }
	assert reopened.data.items[0].priority == .medium
	assert reopened.data.items[1].priority == .none && reopened.data.items[1].completed
}

fn test_reminders_each_priority_roundtrips_and_toggle_edit_cancel_preserve_values() {
	home := reminders_test_home('priorities')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	for priority in [ReminderPriority.none, .low, .medium, .high]! {
		app.begin_edit(-1)
		assert app.edit_priority == .none
		app.paste_input('Task')
		app.handle(reminders_priority_key(priority))!
		assert app.edit_priority == priority
		app.save_edit()
		assert !app.editing
	}
	app.reload()
	for index, priority in [ReminderPriority.none, .low, .medium, .high]! {
		assert app.data.items[index].priority == priority
		app.selected = index
		app.toggle_selected()
		assert app.data.items[index].completed && app.data.items[index].priority == priority
		app.begin_edit(index)
		assert app.edit_priority == priority
		app.handle('reminders.priority.none')!
		app.key_input('\x1b')
		assert !app.editing && app.edit_priority == .none
		assert app.data.items[index].priority == priority
		app.handle('reminders.priority.high')!
		assert app.edit_priority == .none && app.data.items[index].priority == priority
	}
	app.begin_edit(3)
	app.handle('reminders.priority.low')!
	app.save_edit()
	assert app.data.items[3].priority == .low && app.data.items[3].completed
	app.selected = 1
	app.confirming_delete = true
	app.delete_selected()
	assert app.data.count == 3
	assert app.data.items[1].priority == .medium
	assert app.data.items[2].priority == .low
}

fn test_reminders_v2_rejects_malformed_priority_fields_and_preserves_loaded_tasks() {
	for record in ['VINIX-REMINDERS 2\n0\t4\t\tTask\n',
		'VINIX-REMINDERS 2\n0\t-1\t\tTask\n', 'VINIX-REMINDERS 2\n0\t03\t\tTask\n',
		'VINIX-REMINDERS 2\n0\t\t\tTask\n', 'VINIX-REMINDERS 2\n0\ta\t\tTask\n',
		'VINIX-REMINDERS 2\n0\t3 \t\tTask\n', 'VINIX-REMINDERS 2\n0\t3\tTask\n',
		'VINIX-REMINDERS 2\n0\t3\t\tTask', 'VINIX-REMINDERS 2\n0\t3\t\tTask\tExtra\n',
		'VINIX-REMINDERS 2\n0\t3\t\tGood first\n0\t4\t\tBad second\n',
		'VINIX-REMINDERS 1\n0\t3\t\tTask\n']! {
		mut parsed := reminders_parse(record) or { continue }
		parsed.free_items()
		assert false, 'malformed priority record accepted'
	}
	home := reminders_test_home('priority-invalid')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.begin_edit(-1)
	app.paste_input('Protected task')
	app.handle('reminders.priority.high')!
	app.save_edit()
	bad := 'VINIX-REMINDERS 2\n0\t9\t\tBad priority\n'
	os.write_file(path, bad)!
	app.reload()
	assert app.read_failed && app.data.count == 1
	assert app.data.items[0].priority == .high && app.data.items[0].title == 'Protected task'
	app.begin_edit(0)
	assert !app.editing
	stored := os.read_file(path)!
	assert stored == bad
	unsafe { stored.free() }
}

fn test_reminders_v1_migration_conflict_and_busy_save_keep_priority_draft() {
	home := reminders_test_home('priority-conflict')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, 'VINIX-REMINDERS 1\n0\t\tLegacy\n')!
	mut first := new_reminders_app(home, 0)
	mut second := new_reminders_app(home, 0)
	defer { first.close_app() second.close_app() }
	second.begin_edit(0)
	second.handle('reminders.priority.high')!
	first.selected = 0
	first.toggle_selected()
	second.save_edit()
	assert second.status == 'reminders.changed' && second.editing
	assert second.edit_priority == .high && second.data.items[0].priority == .none
	assert second.record == 'VINIX-REMINDERS 1\n0\t\tLegacy\n'
	second.reload()
	assert !second.editing && second.data.items[0].completed
	second.begin_edit(0)
	second.handle('reminders.priority.low')!
	lock_fd := reminders_lock(second.home_fd)
	assert lock_fd >= 0
	second.save_edit()
	assert second.status == 'reminders.busy' && second.editing && second.edit_priority == .low
	assert second.data.items[0].priority == .none
	desktop_close(lock_fd)
	second.save_edit()
	assert !second.editing && second.data.items[0].priority == .low
	assert second.data.items[0].completed
}

fn test_reminders_priority_exports_csv_text_and_list_badge_with_safe_editor_geometry() {
	home := reminders_test_home('priority-export')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.begin_edit(-1)
	app.paste_input('Important, "quoted"')
	app.handle('reminders.priority.high')!
	app.save_edit()
	csv := app.visible_text(true)
	text := app.visible_text(false)
	defer { unsafe { csv.free() text.free() } }
	assert csv == '"Title","Due","Completed (0 or 1)","Priority"\n"Important, ""quoted""","",0,"High"\n'
	assert text == '[ ] Important, "quoted"\tPriority: High\n'
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 800, 616))!
	mut found_badge := false
	for child in tree.children {
		if child.id == 'reminders.row.0' {
			for label in child.children { if label.text == 'High' { found_badge = true } }
		}
	}
	assert found_badge
	free_tree(tree)
	app.begin_edit(0)
	for width in [480, 800, 1000]! {
		begin_frame_elements()
		editor := app.build(ui2.rect(0, 0, width, 616))!
		mut priorities := 0
		mut previous_right := f64(0)
		for child in editor.children {
			if child.id.starts_with('reminders.priority.') {
				assert child.frame.x >= previous_right && child.frame.width >= 70
				assert child.frame.x + child.frame.width <= width - 14
				assert child.frame.y > 616 - 300 + 142 && child.frame.y + child.frame.height < 616 - 105
				assert child.text == tr(child.id) && child.text != child.id
				previous_right = child.frame.x + child.frame.width
				priorities++
			}
		}
		assert priorities == 4
		free_tree(editor)
	}
}
