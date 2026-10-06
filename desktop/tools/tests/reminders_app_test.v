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

fn reminders_test_sort_record() string {
	return 'VINIX-REMINDERS 2\n0\t0\t\tZeta\n0\t3\t2028-02-29 09:00\talpha\n1\t3\t2028-02-29\tAlpha\n0\t2\t2027-01-01\tÉclair\n0\t1\t2028-02-29 09:00\talpha\n1\t2\t\t日本語\n0\t3\t2028-02-29 00:00\t😀\n0\t2\t2028-02-29\tAl\n0\t0\t\tAlpha\n'
}

fn test_reminders_sorts_stable_keys_without_changing_rows_or_storage() {
	home := reminders_test_home('sort-order')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, reminders_test_sort_record())!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	assert app.sort == .manual && app.match_count == 9
	for slot in 0 .. 9 { assert app.matches[slot] == slot }
	app.handle('reminders.sort.priority')!
	for slot, index in [1, 2, 6, 3, 5, 7, 4, 0, 8]! { assert app.matches[slot] == index }
	app.handle('reminders.sort.due')!
	// Earlier date, all-day ties, midnight, timed ties, then undated ties.
	for slot, index in [3, 2, 7, 6, 1, 4, 0, 5, 8]! { assert app.matches[slot] == index }
	app.handle('reminders.sort.title')!
	// Shorter prefix, uppercase, lowercase, then ascending Unicode code points.
	for slot, index in [7, 2, 8, 0, 1, 4, 3, 5, 6]! { assert app.matches[slot] == index }
	assert app.data.items[0].title == 'Zeta' && app.data.items[6].title == '😀'
	assert app.record == reminders_test_sort_record()
	stored := os.read_file(path)!
	assert stored == reminders_test_sort_record()
	unsafe { stored.free() }
	app.reload()
	assert app.sort == .title
	for slot, index in [7, 2, 8, 0, 1, 4, 3, 5, 6]! { assert app.matches[slot] == index }
	app.handle('reminders.sort.manual')!
	for slot in 0 .. 9 { assert app.matches[slot] == slot }
	mut reopened := new_reminders_app(home, 0)
	defer { reopened.close_app() }
	assert reopened.sort == .manual
	for slot in 0 .. 9 { assert reopened.matches[slot] == slot }
}

fn test_reminders_sort_selection_paging_drafts_and_delete_keep_data_identity() {
	home := reminders_test_home('sort-identities')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, reminders_test_sort_record())!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.page_rows = 2
	app.selected = 0
	app.handle('reminders.delete')!
	app.handle('reminders.sort.title')!
	assert app.selected == 0 && app.confirming_delete
	assert app.scroll == 2 && app.matches[app.scroll + 1] == 0
	app.handle('reminders.sort.due')!
	assert app.selected == 0 && app.confirming_delete
	assert app.scroll == 5 && app.matches[app.scroll + 1] == 0
	app.handle('reminders.delete_confirm')!
	assert app.data.count == 8 && app.selected == -1 && !app.confirming_delete
	assert app.data.items[0].title == 'alpha' && app.data.items[1].title == 'Alpha'
	assert !app.record.contains('Zeta')
	app.selected = 0
	app.begin_edit(0)
	app.key_input('\x01')
	app.paste_input('Draft remains attached')
	app.handle('reminders.priority.low')!
	app.handle('reminders.sort.priority')!
	assert app.selected == 0 && app.edit_index == 0 && app.editing
	assert editor_bytes_text(app.title_input) == 'Draft remains attached'
	assert editor_bytes_text(app.due_input) == '2028-02-29 09:00'
	assert app.edit_priority == .low && app.data.items[0].priority == .high
	app.handle('reminders.delete')!
	app.handle('reminders.delete_confirm')!
	assert app.data.count == 8 && !app.confirming_delete
	app.handle('reminders.cancel')!
	assert app.data.items[0].title == 'alpha'
	app.handle('reminders.filter.completed')!
	assert app.match_count == 2 && app.selected == -1
	assert app.matches[0] == 1 && app.matches[1] == 4
	app.handle('reminders.filter.open')!
	app.handle('reminders.search')!
	app.paste_input('alpha')
	app.handle('reminders.sort.due')!
	assert app.match_count == 2 && app.matches[0] == 0 && app.matches[1] == 3
	app.handle('reminders.row.3')!
	app.handle('reminders.delete')!
	app.handle('reminders.search')!
	app.key_input('\x01')
	app.paste_input('Al')
	assert app.match_count == 2 && app.selected == -1 && !app.confirming_delete
	app.handle('reminders.delete_confirm')!
	assert app.data.count == 8
	app.key_input('\x01\x7f')
	app.handle('reminders.filter.all')!
	app.page_rows = 2
	app.key_input('\x1b[6~')
	assert app.scroll == 2 && app.matches[app.scroll] == 6
	app.key_input('\x1b[5~')
	assert app.scroll == 0
}

fn test_reminders_sorted_exports_include_all_filtered_matches_beyond_current_page() {
	home := reminders_test_home('sort-export')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, 'VINIX-REMINDERS 2\n0\t0\t2028-02-29\tvisible B\n1\t3\t\tvisible A\n0\t3\t2027-01-01\tHidden\n')!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.page_rows = 1
	app.handle('reminders.search')!
	app.paste_input('visible')
	app.handle('reminders.sort.title')!
	app.handle('reminders.next')!
	assert app.scroll == 1 && app.matches[app.scroll] == 0
	text := app.visible_text(false)
	defer { unsafe { text.free() } }
	assert text == '[x] visible A\tPriority: High\n[ ] visible B\t2028-02-29\tPriority: None\n'
	app.handle('reminders.sort.due')!
	app.handle('reminders.next')!
	assert app.scroll == 1 && app.matches[app.scroll] == 1
	csv := app.visible_text(true)
	defer { unsafe { csv.free() } }
	assert csv == '"Title","Due","Completed (0 or 1)","Priority"\n"visible B","2028-02-29",0,"None"\n"visible A","",1,"High"\n'
	export_path := join_path(home, 'sorted.csv')
	defer { unsafe { export_path.free() } }
	app.handle('reminders.export_path')!
	app.key_input('\x01')
	app.paste_input(export_path)
	app.export_visible(true)
	assert app.status == 'reminders.export_saved'
	saved := os.read_file(export_path)!
	assert saved == csv
	unsafe { saved.free() }
}

fn test_reminders_overdue_filter_composes_each_sort_and_clock_unavailability() {
	home := reminders_test_home('sort-overdue')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, reminders_test_sort_record())!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.today = 20280229
	app.minute_of_day = 600
	app.clock_valid = true
	app.handle('reminders.filter.overdue')!
	assert app.match_count == 4
	for slot, index in [1, 3, 4, 6]! { assert app.matches[slot] == index }
	app.handle('reminders.direction.toggle')!
	for slot, index in [6, 4, 3, 1]! { assert app.matches[slot] == index }
	app.handle('reminders.sort.priority')!
	for slot, index in [1, 6, 3, 4]! { assert app.matches[slot] == index }
	app.handle('reminders.direction.toggle')!
	for slot, index in [4, 3, 1, 6]! { assert app.matches[slot] == index }
	app.handle('reminders.sort.due')!
	for slot, index in [3, 6, 1, 4]! { assert app.matches[slot] == index }
	app.handle('reminders.direction.toggle')!
	for slot, index in [1, 4, 6, 3]! { assert app.matches[slot] == index }
	app.handle('reminders.sort.title')!
	for slot, index in [1, 4, 3, 6]! { assert app.matches[slot] == index }
	app.handle('reminders.direction.toggle')!
	for slot, index in [6, 3, 1, 4]! { assert app.matches[slot] == index }
	app.selected = 6
	app.handle('reminders.delete')!
	app.clock_valid = false
	app.refilter()
	assert app.match_count == 0 && app.selected == -1 && !app.confirming_delete
	app.handle('reminders.delete_confirm')!
	assert app.data.count == 9 && app.record == reminders_test_sort_record()
	app.clock_valid = true
	app.minute_of_day = 0
	app.refilter()
	assert app.match_count == 1 && app.matches[0] == 3
}

fn test_reminders_sort_is_readonly_for_v1_and_preserves_busy_conflict_drafts() {
	home := reminders_test_home('sort-conflict')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	legacy := 'VINIX-REMINDERS 1\n0\t2028-02-29\tZebra\n0\t\tApple\n'
	os.write_file(path, legacy)!
	mut first := new_reminders_app(home, 0)
	mut second := new_reminders_app(home, 0)
	defer { first.close_app() second.close_app() }
	second.handle('reminders.sort.title')!
	assert second.matches[0] == 1 && second.matches[1] == 0
	second.handle('reminders.direction.toggle')!
	assert second.matches[0] == 0 && second.matches[1] == 1
	unchanged := os.read_file(path)!
	assert unchanged == legacy && second.record == legacy
	unsafe { unchanged.free() }
	second.selected = 0
	second.begin_edit(0)
	second.key_input('\x01')
	second.paste_input('Pending identity')
	second.handle('reminders.priority.high')!
	first.selected = 1
	first.toggle_selected()
	second.handle('reminders.sort.priority')!
	second.handle('reminders.direction.toggle')!
	second.save_edit()
	assert second.status == 'reminders.changed' && second.editing
	assert second.edit_index == 0 && second.edit_priority == .high
	assert second.sort_reversed[int(RemindersSort.priority)]
	assert editor_bytes_text(second.title_input) == 'Pending identity'
	assert second.record == legacy && second.data.items[0].title == 'Zebra'
	second.reload()
	assert second.sort == .priority && !second.editing
	second.selected = 0
	second.begin_edit(0)
	second.handle('reminders.priority.low')!
	lock_fd := reminders_lock(second.home_fd)
	assert lock_fd >= 0
	second.handle('reminders.sort.due')!
	second.handle('reminders.direction.toggle')!
	second.save_edit()
	assert second.status == 'reminders.busy' && second.editing
	assert second.edit_index == 0 && second.edit_priority == .low
	assert second.sort_reversed[int(RemindersSort.due)]
	assert second.data.items[0].priority == .none
	desktop_close(lock_fd)
	second.save_edit()
	assert !second.editing && second.data.items[0].title == 'Zebra'
	assert second.data.items[0].priority == .low && second.data.items[1].completed
}

fn test_reminders_sort_keyboard_focus_and_bounded_controls_do_not_overlap_rows() {
	saved_language := desktop_language
	defer { desktop_language = saved_language }
	mut desktop := Desktop{fonts: load_fonts()}
	defer { free_fonts(mut desktop.fonts) }
	home := reminders_test_home('sort-frame')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, reminders_test_sort_record())!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.key_input('\t\t\t')
	assert app.focus == 4
	app.key_input('\x1b[C')
	assert app.sort == .priority
	app.key_input('\x1b[D')
	assert app.sort == .manual
	app.key_input('\x1b[D')
	assert app.sort == .title
	app.key_input('\t')
	assert app.focus == 5
	app.key_input('\x1b[C')
	assert app.sort_reversed[int(RemindersSort.title)]
	app.key_input(' ')
	assert !app.sort_reversed[int(RemindersSort.title)]
	app.key_input('\t')
	assert app.focus == 2
	app.key_input('\x1b[C')
	assert app.sort == .title
	app.begin_edit(0)
	app.key_input('\t\t\t\t')
	assert app.focus == 4 && app.editing && app.edit_index == 0
	app.key_input('\x1b[C')
	assert app.sort == .manual && editor_bytes_text(app.title_input) == 'Zeta'
	app.key_input('\t')
	assert app.focus == 5 && app.editing
	app.key_input('\r')
	assert app.sort_reversed[int(RemindersSort.manual)] && app.editing
	app.key_input('\t')
	assert app.focus == 0 && app.editing
	for language in desktop_languages {
		desktop_language = language
		for width in [480, 800, 1000]! {
			begin_frame_elements()
			tree := app.build(ui2.rect(0, 0, width, 616))!
			mut sorts := 0
			mut previous_right := f64(106)
			for child in tree.children {
				if child.id.starts_with('reminders.sort.') {
					assert child.frame.x >= previous_right && child.frame.width >= 80
					assert child.frame.x + child.frame.width <= width - 14
					assert child.frame.y == 84 && child.frame.y + child.frame.height <= 114
					assert child.text == tr(child.id) && child.text != child.id
					face := desktop.face_for(child.text_style)
					assert face.text_width(child.text) <= int(child.frame.width) - 8
					previous_right = child.frame.x + child.frame.width
					sorts++
				}
				if child.id == 'reminders.direction.toggle' {
					assert child.frame.y == 120 && child.frame.height == 28
					assert child.frame.x >= 14 && child.frame.x + child.frame.width <= width - 14
					assert child.text == tr(app.direction_key()) && child.text != app.direction_key()
					face := desktop.face_for(child.text_style)
					assert face.text_width(child.text) <= int(child.frame.width) - 8
				}
				if child.id == 'reminders.new' { assert child.frame.y == 160 }
				if child.id.starts_with('reminders.row.') {
					assert child.frame.y >= 200 && child.frame.y + child.frame.height < 616 - 300
				}
			}
			assert sorts == 4 && app.page_rows == 2
			free_tree(tree)
		}
	}
}

fn test_reminders_each_direction_reverses_primary_keys_keeps_ties_and_is_session_only() {
	home := reminders_test_home('directions')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, reminders_test_sort_record())!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	for order in [RemindersSort.manual, RemindersSort.priority, RemindersSort.due, RemindersSort.title]! {
		app.handle(reminders_sort_key(order))!
		assert !app.sort_reversed[int(order)]
		app.handle('reminders.direction.toggle')!
		assert app.sort_reversed[int(order)] && app.focus == 5
		expected := match order {
			.manual { [8, 7, 6, 5, 4, 3, 2, 1, 0]! }
			.priority { [0, 8, 4, 3, 5, 7, 1, 2, 6]! }
			.due { [1, 4, 6, 2, 7, 3, 0, 5, 8]! }
			.title { [6, 5, 3, 1, 4, 0, 2, 8, 7]! }
		}
		for slot, index in expected { assert app.matches[slot] == index }
		assert app.record == reminders_test_sort_record()
	}
	app.reload()
	assert app.sort == .title && app.sort_reversed[int(RemindersSort.title)]
	assert app.matches[0] == 6 && app.matches[6] == 2 && app.matches[7] == 8
	app.handle('reminders.sort.due')!
	assert app.sort_reversed[int(RemindersSort.due)]
	for slot, index in [1, 4, 6, 2, 7, 3, 0, 5, 8]! { assert app.matches[slot] == index }
	app.key_input('\x1b[D')
	// Sort-key focus changes the key, rather than its remembered direction.
	assert app.sort == .priority && app.sort_reversed[int(RemindersSort.priority)]
	stored := os.read_file(path)!
	assert stored == reminders_test_sort_record()
	unsafe { stored.free() }
	mut reopened := new_reminders_app(home, 0)
	defer { reopened.close_app() }
	assert reopened.sort == .manual
	for order in [RemindersSort.manual, RemindersSort.priority, RemindersSort.due, RemindersSort.title]! {
		assert !reopened.sort_reversed[int(order)]
	}
}

fn test_reminders_direction_changes_keep_selected_delete_guard_edit_draft_and_exports_attached() {
	home := reminders_test_home('direction-identities')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, reminders_test_sort_record())!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.page_rows = 2
	app.selected = 1
	app.handle('reminders.delete')!
	app.handle('reminders.sort.priority')!
	app.handle('reminders.direction.toggle')!
	assert app.selected == 1 && app.confirming_delete && app.scroll == 5
	assert app.matches[app.scroll + 1] == 1
	app.handle('reminders.delete_confirm')!
	assert app.data.count == 8 && app.data.items[1].title == 'Alpha'
	assert app.data.items[3].title == 'alpha' && app.data.items[3].priority == .low
	app.selected = 3
	app.begin_edit(3)
	app.key_input('\x01')
	app.paste_input('Unsaved direction draft')
	app.handle('reminders.priority.high')!
	app.handle('reminders.sort.due')!
	app.handle('reminders.direction.toggle')!
	assert app.selected == 3 && app.edit_index == 3 && app.editing
	assert app.edit_priority == .high && app.data.items[3].priority == .low
	assert editor_bytes_text(app.title_input) == 'Unsaved direction draft'
	assert editor_bytes_text(app.due_input) == '2028-02-29 09:00'
	app.handle('reminders.search')!
	app.paste_input('Al')
	assert app.selected == -1 && app.edit_index == 3 && app.editing && !app.confirming_delete
	app.page_rows = 1
	app.scroll = 1
	text := app.visible_text(false)
	csv := app.visible_text(true)
	assert text == '[x] Alpha\t2028-02-29\tPriority: High\n[ ] Al\t2028-02-29\tPriority: Medium\n[ ] Alpha\tPriority: None\n'
	assert csv == '"Title","Due","Completed (0 or 1)","Priority"\n"Alpha","2028-02-29",1,"High"\n"Al","2028-02-29",0,"Medium"\n"Alpha","",0,"None"\n'
	unsafe { text.free() csv.free() }
	app.cancel_edit()
	assert app.data.items[3].title == 'alpha' && app.sort_reversed[int(RemindersSort.due)]
}

fn test_reminders_direction_and_sort_controls_fit_compact_tiny_frames_without_mutating_drafts() {
	home := reminders_test_home('direction-small')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	path := join_path(home, reminders_filename)
	defer { unsafe { path.free() } }
	os.write_file(path, reminders_test_sort_record())!
	mut app := new_reminders_app(home, 0)
	defer { app.close_app() }
	app.selected = 4
	app.begin_edit(4)
	app.key_input('\x01')
	app.paste_input('Small frame draft')
	app.handle('reminders.sort.due')!
	app.handle('reminders.direction.toggle')!
	for dimensions in [[800, 616]!, [480, 616]!, [360, 616]!, [360, 2000]!, [240, 300]!, [180, 144]!, [120, 100]!, [60, 40]!]! {
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, dimensions[0], dimensions[1]))!
		mut directions := 0
		mut row_bottom := f64(0)
		for child in tree.children {
			assert child.frame.x >= 0 && child.frame.y >= 0
			assert child.frame.width > 0 && child.frame.height > 0
			assert child.frame.x + child.frame.width <= dimensions[0]
			assert child.frame.y + child.frame.height <= dimensions[1]
			if child.id == 'reminders.direction.toggle' {
				directions++
				assert child.text == tr('reminders.direction.latest') && child.text != 'reminders.direction.latest'
				row_bottom = child.frame.y + child.frame.height
			}
			if child.id.starts_with('reminders.row.') { assert child.frame.y >= row_bottom }
		}
		assert directions == 1
		free_tree(tree)
		assert app.selected == 4 && app.edit_index == 4 && app.editing
		assert editor_bytes_text(app.title_input) == 'Small frame draft'
		assert editor_bytes_text(app.due_input) == '2028-02-29 09:00'
		assert app.edit_priority == .low && app.data.items[4].title == 'alpha'
		assert app.sort == .due && app.sort_reversed[int(RemindersSort.due)]
	}
}
