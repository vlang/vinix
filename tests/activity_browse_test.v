// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn browse_record(pid int, parent int, name string, cpu u64) ActivitySample {
	mut record := ActivitySample{ pid: i32(pid), ppid: i32(parent), threads: 3, cpu_time_ns: cpu, memory_bytes: 2_000_000 }
	for index, byte in name { if index < activity_name_len - 1 { record.name[index] = byte } }
	return record
}

fn browse_snapshot(mut app ActivityApp, records []ActivitySample, time u64) {
	header := ActivityTable{ total: u32(records.len), sample_ns: time, total_memory: 256_000_000, free_memory: 128_000_000 }
	app.monitor.apply_snapshot(&header, unsafe { &records[0] }, records.len)
}

fn browse_pid_at(app &ActivityApp, index int) int {
	return app.monitor.rows[app.monitor.visible[index].index].pid
}

fn test_activity_search_filters_names_paths_and_pid_without_losing_selection() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	mut records := [browse_record(900001, 1, '/bin/Worker[900001]', 0),
		browse_record(900002, 900001, '/usr/bin/vinix-files[900002]', 0),
		browse_record(900003, 1, '/bin/background[900003]', 0)]
	defer { unsafe { records.free() } }
	browse_snapshot(mut app, records, 1_000_000_000)
	app.monitor.selected_pid = 900002
	app.handle(activity_action_search)!
	app.key_input('fIlEs')
	assert app.monitor.visible.len == 1
	assert browse_pid_at(&app, 0) == 900002
	assert app.monitor.selected_pid == 900002
	app.key_input('\x1b')
	assert app.monitor.visible.len == 3
	app.key_input('\x06')
	app.key_input('900003')
	assert app.monitor.visible.len == 1
	assert browse_pid_at(&app, 0) == 900003
	assert app.monitor.selected_pid == 900002
	app.key_input('\x1b')
	app.handle(activity_action_filter)!
	assert app.monitor.filter == .applications
	assert app.monitor.visible.len == 1 && browse_pid_at(&app, 0) == 900002
	app.monitor.filter = .active
	records[0].cpu_time_ns = 250_000_000
	browse_snapshot(mut app, records, 2_000_000_000)
	assert app.monitor.visible.len == 1 && browse_pid_at(&app, 0) == 900001
	app.monitor.viewer_uid = 501
	index := app.monitor.process_row_index(900003)
	app.monitor.rows[index].uid_known = true
	app.monitor.rows[index].uid = 501
	app.monitor.filter = .user
	app.monitor.rebuild_visible()
	assert app.monitor.visible.len == 1 && browse_pid_at(&app, 0) == 900003
}

fn test_activity_process_tree_keeps_ancestors_and_survives_cycles() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	records := [browse_record(900002, 900001, '/bin/child', 0),
		browse_record(900001, 1, '/bin/parent', 0),
		browse_record(900003, 900002, '/bin/grandchild', 0),
		browse_record(900004, 900005, '/bin/cycle-a', 0),
		browse_record(900005, 900004, '/bin/cycle-b', 0)]
	defer { unsafe { records.free() } }
	browse_snapshot(mut app, records, 1_000_000_000)
	app.set_sort(.pid)
	app.handle(activity_action_tree)!
	assert app.monitor.visible.len == 5
	assert browse_pid_at(&app, 0) == 900001
	assert browse_pid_at(&app, 1) == 900002
	assert browse_pid_at(&app, 2) == 900003
	assert app.monitor.visible[0].depth == 0
	assert app.monitor.visible[1].depth == 1
	assert app.monitor.visible[2].depth == 2
	app.search_focused = true
	app.key_input('grandchild')
	assert app.monitor.visible.len == 3
	assert app.monitor.visible[0].context
	assert app.monitor.visible[1].context
	assert !app.monitor.visible[2].context
}

fn test_activity_identity_columns_and_cpu_totals_are_real_and_cached() {
	mut row := ActivityRow{}
	defer { unsafe {
		row.user_text.free()
		row.state_text.free()
	}
	 }
	status := 'Name:\tworker\nState:\tT (stopped)\nUid:\t501\t501\t501\t501\n'
	activity_parse_identity(mut row, status.str, status.len)
	assert row.uid_known && row.uid == 501
	assert row.state == `T`
	assert row.user_text == '501'
	assert row.state_text == tr('activity.state.stopped')
	activity_parse_identity(mut row, status.str, 0)
	assert !row.uid_known && row.state == 0 && row.user_text == '—'
	text := activity_cpu_time_text(3_250_000_000)
	assert text == '3.25'
	unsafe { text.free() }
	mut app := ActivityApp{}
	defer { app.close_app() }
	records := [browse_record(900003, 900001, '/bin/worker[900003]', 3_250_000_000)]
	defer { unsafe { records.free() } }
	browse_snapshot(mut app, records, 1_000_000_000)
	assert app.monitor.rows[0].ppid == 900001
	assert app.monitor.rows[0].ppid_text == '900001'
	assert app.monitor.rows[0].threads_text == '3'
	assert app.monitor.rows[0].cpu_time_text == '3.25'
	assert app.monitor.rows[0].executable == '/bin/worker'
	app.handle('activity.column.toggle.threads')!
	assert app.monitor.columns & activity_column_bit(.threads) != 0
	app.handle('activity.column.toggle.cpu')!
	assert app.monitor.columns & activity_column_bit(.cpu) == 0
	app.handle('activity.sort.threads')!
	assert app.monitor.sort == .threads && app.monitor.descending
}

fn test_activity_keyboard_wheel_and_scrollbar_bound_the_visible_list() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	mut records := []ActivitySample{cap: 40}
	defer { unsafe { records.free() } }
	for index in 0 .. 40 { records << browse_record(900001 + index, 1, '/bin/worker', 0) }
	browse_snapshot(mut app, records, 1_000_000_000)
	app.set_sort(.pid)
	tree := app.build(ui2.rect(0, 0, 900, 280))!
	free_tree(tree)
	app.key_input('\x1b[B')
	assert app.monitor.selected_pid == 900001
	app.key_input('\x1b[B')
	assert app.monitor.selected_pid == 900002
	app.key_input('\x1b[6~')
	assert app.monitor.selected_pid == 900002 + app.monitor.visible_rows
	assert app.monitor.scroll > 0
	app.key_input('\x1b[F')
	assert app.monitor.selected_pid == 900040
	assert app.monitor.scroll == 40 - app.monitor.visible_rows
	app.pointer_event(.scroll, .no_button, 100, 400, app.rows_top + 10, 900, 280)
	assert app.monitor.scroll == 0
	app.pointer_event(.scroll, .no_button, -100, 400, app.rows_top + 10, 900, 280)
	assert app.monitor.scroll == 40 - app.monitor.visible_rows
	position, thumb := activity_scroll_thumb(app.rows_height, app.monitor.visible_rows, 40, app.monitor.scroll)
	assert position + thumb == app.rows_height
	app.pointer_event(.down, .left, 0, 895, app.rows_top + position + 1, 900, 280)
	assert app.scroll_drag
	app.pointer_event(.move, .no_button, 0, 895, app.rows_top - 1000, 900, 280)
	assert app.monitor.scroll == 0
	app.pointer_event(.up, .left, 0, 895, app.rows_top, 900, 280)
	assert !app.scroll_drag
}

fn test_activity_refresh_pause_interval_and_inspector_shortcuts() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	app.handle(activity_action_pause)!
	assert app.monitor.paused
	assert !app.poll()
	app.handle(activity_action_pause)!
	assert !app.monitor.paused
	assert monotonic_millis() - app.monitor.last_poll_ms >= app.monitor.interval_ms
	app.handle(activity_action_interval)!
	assert app.monitor.interval_ms == 2000
	app.handle(activity_action_interval)!
	assert app.monitor.interval_ms == 5000
	app.handle(activity_action_interval)!
	assert app.monitor.interval_ms == 500
	app.handle(activity_action_interval)!
	assert app.monitor.interval_ms == 1000
	app.monitor.selected_pid = 12
	app.handle(activity_action_inspect)!
	assert app.inspector_open
	app.key_input('\x1b')
	assert !app.inspector_open
}
