// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn C.mkfifo(path &char, mode u32) int

fn activity_preferences_test_home(suffix string) string {
	pid := C.getpid().str()
	home := os.join_path(os.temp_dir(), 'vinix-activity-preferences-${pid}-${suffix}')
	unsafe { pid.free() }
	os.mkdir(home) or { panic(err) }
	canonical := os.real_path(home)
	unsafe { home.free() }
	return canonical
}

fn activity_preferences_test_file(home string) string { return '${home}/${activity_preferences_filename}' }

fn activity_preferences_test_find(root ui2.Element, id string) ?ui2.Element {
	if root.id == id { return root }
	for child in root.children {
		if found := activity_preferences_test_find(child, id) { return found }
	}
	return none
}

fn test_activity_preferences_roundtrip_uses_stable_names_and_validates_all_choices() {
	for sort in [ActivitySort.cpu, .memory, .name, .pid, .ppid, .threads, .cpu_time, .user, .state]! {
		for filter in [ActivityFilter.all, .applications, .user, .active, .system, .inactive, .other_users]! {
			p := ActivityViewPreferences{sort: sort, descending: false, filter: filter, hierarchy: true,
				columns: 511, interval_ms: 5000, view: .resources, resource_tab: .network}
			encoded := activity_encode_view_preferences(p) or { panic('valid settings rejected') }
			decoded := activity_parse_view_preferences(encoded) or { panic('saved settings rejected') }
			assert decoded == p
			assert encoded.contains('resource_tab=network\n')
			unsafe { encoded.free() }
		}
	}
	for interval in [i64(500), 1000, 2000, 5000]! {
		for view in [ActivityView.processes, .resources, .gpu, .energy, .startup]! {
			p := ActivityViewPreferences{interval_ms: interval, view: view}
			text := activity_encode_view_preferences(p) or { panic('valid view rejected') }
			assert (activity_parse_view_preferences(text) or { panic('valid view parse failed') }) == p
			unsafe { text.free() }
		}
	}
}

fn test_activity_preferences_damaged_partial_duplicate_and_unsafe_values_are_atomic() {
	valid := activity_encode_view_preferences(ActivityViewPreferences{}) or { panic('default encoding failed') }
	defer { unsafe { valid.free() } }
	for pair in [
		['version=1', 'version=2']!, ['sort=cpu', 'sort=bogus']!,
		['descending=1', 'descending=true']!, ['filter=all', 'filter=selected']!,
		['tree=0', 'tree=-1']!, ['columns=15', 'columns=0']!,
		['columns=15', 'columns=512']!, ['columns=15', 'columns=14']!,
		['columns=15', 'columns=99999999999999999999']!,
		['interval_ms=1000', 'interval_ms=0']!, ['interval_ms=1000', 'interval_ms=1000junk']!,
		['view=processes', 'view=unknown']!, ['resource_tab=cpu', 'resource_tab=gpu']!,
	]! {
		bad := valid.replace(pair[0], pair[1])
		assert activity_parse_view_preferences(bad) == none
		unsafe { bad.free() }
	}
	for bad in ['version=1\n', 'sort=cpu\n', 'version=1\x00', 'unparseable\n']! {
		assert activity_parse_view_preferences(bad) == none
	}
	for suffix in ['sort=cpu\n', 'version=1\n', 'future_semantics=1\n']! {
		bad := valid + suffix
		assert activity_parse_view_preferences(bad) == none
		unsafe { bad.free() }
	}
	oversized := 'x'.repeat(activity_preferences_limit + 1)
	assert activity_parse_view_preferences(oversized) == none
	unsafe { oversized.free() }
	crlf := valid.replace('\n', '\r\n')
	assert (activity_parse_view_preferences(crlf) or { panic('CRLF parse failed') }) == ActivityViewPreferences{}
	unsafe { crlf.free() }
	assert activity_encode_view_preferences(ActivityViewPreferences{columns: 0}) == none
	invalid_sort := activity_preference_number('99') or { panic('number parse failed') }
	assert activity_encode_view_preferences(ActivityViewPreferences{sort: unsafe { ActivitySort(invalid_sort) }}) == none
}

fn test_activity_preferences_native_actions_restore_registered_user_view_and_sort_behavior() {
	home := activity_preferences_test_home('actions')
	alias := home + '-alias'
	path := activity_preferences_test_file(home)
	os.symlink(home, alias)!
	defer { os.rm(alias) or {} os.rmdir_all(home) or {} unsafe { home.free() alias.free() path.free() } }
	mut app := ActivityApp{}
	app.load_view_preferences(alias)
	assert !app.preferences.read_failed && app.preferences.home_fd >= 0
	assert !os.exists(path)
	for action in [activity_action_name, activity_action_name, activity_action_tree, activity_action_filter,
		'activity.column.toggle.ppid', 'activity.column.toggle.state', activity_action_interval,
		'activity.view.resources', 'activity.resources.network']! { app.handle(action)! }
	expected := app.view_preferences()
	assert expected.sort == .name && expected.descending
	assert expected.filter == .applications && expected.hierarchy
	assert expected.columns == u32(15 | 16 | 256) && expected.interval_ms == 2000
	assert expected.view == .resources && expected.resource_tab == .network
	fd := app.preferences.home_fd
	app.close_app()
	assert C.fcntl(fd, C.F_GETFD) == -1 && C.errno == C.EBADF
	mut reopened := ActivityApp{}
	reopened.load_view_preferences(alias)
	defer { reopened.close_app() }
	assert reopened.view_preferences() == expected
	assert !reopened.monitor.paused && reopened.monitor.selected_pid == 0
	assert !reopened.search_focused && reopened.monitor.query.len == 0
	begin_frame_elements()
	tree := reopened.build(ui2.rect(0, 0, 900, 540))!
	assert activity_preferences_test_find(tree, 'activity.resources') != none
	assert activity_preferences_test_find(tree, 'activity.resources.network') != none
	free_tree(tree)
	reopened.handle('activity.view.processes')!
	mut records := [2]ActivitySample{}
	for index, byte in '/usr/bin/vinix-files' { records[0].name[index] = byte }
	for index, byte in '/bin/zebra' { records[1].name[index] = byte }
	records[0].pid = 900001 records[1].pid = 900002
	header := ActivityTable{sample_ns: 1_000_000_000}
	reopened.monitor.apply_snapshot(&header, &records[0], records.len)
	assert reopened.monitor.rows[0].pid == 900002
	assert reopened.monitor.visible.len == 1
	assert reopened.monitor.rows[reopened.monitor.visible[0].index].pid == 900001
	begin_frame_elements()
	process_tree := reopened.build(ui2.rect(0, 0, 900, 540))!
	assert activity_preferences_test_find(process_tree, 'activity.sort.ppid') != none
	assert activity_preferences_test_find(process_tree, 'activity.sort.state') != none
	free_tree(process_tree)
	reopened.handle(activity_action_name)!
	assert reopened.monitor.rows[0].pid == 900001
	info := os.lstat(path)!
	assert u32(info.mode) & 0o777 == 0o600
}

fn test_activity_preferences_transient_selection_pause_search_and_scroll_are_not_restored() {
	home := activity_preferences_test_home('transient')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := ActivityApp{}
	app.load_view_preferences(home)
	app.monitor.selected_pid = 42
	app.monitor.filter = .selected
	app.monitor.paused = true
	app.monitor.scroll = 12
	app.search_focused = true
	app.search_key_input('worker')
	app.handle(activity_action_tree)!
	app.close_app()
	mut reopened := ActivityApp{}
	reopened.load_view_preferences(home)
	defer { reopened.close_app() }
	assert reopened.monitor.hierarchy && reopened.monitor.filter == .all
	assert reopened.monitor.selected_pid == 0 && !reopened.monitor.paused
	assert reopened.monitor.scroll == 0 && reopened.monitor.query.len == 0
	assert !reopened.search_focused
}

fn test_activity_preferences_two_users_have_independent_records_and_unmodified_windows_do_not_write() {
	first_home := activity_preferences_test_home('first-user')
	second_home := activity_preferences_test_home('second-user')
	first_path := activity_preferences_test_file(first_home)
	second_path := activity_preferences_test_file(second_home)
	defer { os.rmdir_all(first_home) or {} os.rmdir_all(second_home) or {}
		unsafe { first_home.free() second_home.free() first_path.free() second_path.free() } }
	mut first := ActivityApp{}
	first.load_view_preferences(first_home)
	first.handle(activity_action_tree)!
	first.close_app()
	mut second := ActivityApp{}
	second.load_view_preferences(second_home)
	assert !second.monitor.hierarchy
	second.handle(activity_action_scroll_up)!
	second.close_app()
	assert os.exists(first_path) && !os.exists(second_path)
	mut reopened := ActivityApp{}
	reopened.load_view_preferences(first_home)
	assert reopened.monitor.hierarchy
	reopened.close_app()
}

fn test_activity_preferences_damaged_records_remain_untouched_while_live_view_can_change() {
	home := activity_preferences_test_home('damaged')
	path := activity_preferences_test_file(home)
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() } }
	for record in ['version=99\n', 'version=1\nsort=cpu\n', 'garbage\x00data']! {
		os.write_file(path, record)!
		mut app := ActivityApp{}
		app.load_view_preferences(home)
		assert app.preferences.read_failed && app.preferences.status == 'activity.preferences.read_failed'
		assert app.view_preferences() == ActivityViewPreferences{}
		app.handle(activity_action_tree)!
		assert app.monitor.hierarchy
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 900, 540))!
		// Check the actual footer warns rather than only the model flag.
		mut found := false
		for child in tree.children { if child.text == tr('activity.preferences.read_failed') { found = true } }
		assert found
		free_tree(tree)
		app.handle('activity.view.resources')!
		begin_frame_elements()
		pane := app.build(ui2.rect(0, 0, 900, 540))!
		assert activity_preferences_test_find(pane, 'activity.preferences.warning') != none
		free_tree(pane)
		app.close_app()
		preserved := os.read_file(path)!
		assert preserved == record
		unsafe { preserved.free() }
	}
}

fn test_activity_preferences_unsafe_record_types_and_missing_homes_do_not_block_or_replace_files() {
	home := activity_preferences_test_home('types')
	path := activity_preferences_test_file(home)
	target := home + '/target'
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() target.free() } }
	os.write_file(target, 'preserve target')!
	os.symlink(target, path)!
	mut symlink_app := ActivityApp{}
	symlink_app.load_view_preferences(home)
	symlink_app.handle(activity_action_tree)!
	symlink_app.close_app()
	assert os.is_link(path)
	content := os.read_file(target)!
	assert content == 'preserve target'
	unsafe { content.free() }
	os.rm(path)!
	os.mkdir(path)!
	mut directory_app := ActivityApp{}
	directory_app.load_view_preferences(home)
	directory_app.handle(activity_action_interval)!
	directory_app.close_app()
	assert os.is_dir(path)
	os.rmdir(path)!
	assert C.mkfifo(&char(path.str), 0o600) == 0
	mut fifo_app := ActivityApp{}
	fifo_app.load_view_preferences(home)
	assert fifo_app.preferences.read_failed
	fifo_app.close_app()
	os.rm(path)!
	oversized := 'x'.repeat(activity_preferences_limit + 1)
	defer { unsafe { oversized.free() } }
	for data in ['', oversized]! {
		os.write_file(path, data)!
		mut invalid := ActivityApp{}
		invalid.load_view_preferences(home)
		assert invalid.preferences.read_failed
		invalid.close_app()
	}
	mut missing := ActivityApp{}
	missing.load_view_preferences('/nonexistent-vinix-activity-home')
	assert missing.preferences.read_failed && missing.preferences.home_fd == -1
	missing.close_app()
}

fn test_activity_preferences_failed_lock_is_visible_preserves_last_saved_bytes_and_retries_on_change() {
	home := activity_preferences_test_home('failure')
	path := activity_preferences_test_file(home)
	lock_path := home + '/.vinix-activity-settings.lock'
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() lock_path.free() } }
	mut app := ActivityApp{}
	app.load_view_preferences(home)
	app.handle(activity_action_tree)!
	before := os.read_file(path)!
	defer { unsafe { before.free() } }
	lock_fd := activity_preferences_lock(app.preferences.home_fd)
	assert lock_fd >= 0
	app.handle(activity_action_interval)!
	assert app.monitor.interval_ms == 2000 && app.preferences.status == 'activity.preferences.save_failed'
	after := os.read_file(path)!
	assert after == before
	unsafe { after.free() }
	assert desktop_close(lock_fd) == 0
	// An unrelated selection/scroll does not repeatedly attempt storage.
	app.handle(activity_action_scroll_up)!
	assert app.preferences.status == 'activity.preferences.save_failed'
	app.handle(activity_action_interval)!
	assert app.monitor.interval_ms == 5000 && app.preferences.status.len == 0
	app.close_app()
	mut reopened := ActivityApp{}
	reopened.load_view_preferences(home)
	assert reopened.monitor.interval_ms == 5000 && reopened.monitor.hierarchy
	reopened.close_app()
	for entry in os.ls(home)! { assert !entry.starts_with('.vinix-activity-settings.tmp.') }
}

fn test_activity_preferences_newer_window_and_later_damaged_record_are_preserved() {
	home := activity_preferences_test_home('conflict')
	path := activity_preferences_test_file(home)
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() } }
	mut first := ActivityApp{}
	mut stale := ActivityApp{}
	first.load_view_preferences(home)
	stale.load_view_preferences(home)
	first.handle(activity_action_tree)!
	saved := os.read_file(path)!
	defer { unsafe { saved.free() } }
	stale.handle(activity_action_interval)!
	assert stale.monitor.interval_ms == 2000 && stale.preferences.status == 'activity.preferences.changed'
	preserved := os.read_file(path)!
	assert preserved == saved
	unsafe { preserved.free() }
	first.close_app()
	stale.close_app()
	mut app := ActivityApp{}
	app.load_view_preferences(home)
	os.write_file(path, 'damaged after opening')!
	app.handle(activity_action_tree)!
	assert !app.monitor.hierarchy && app.preferences.status == 'activity.preferences.save_failed'
	app.close_app()
	damaged := os.read_file(path)!
	assert damaged == 'damaged after opening'
	unsafe { damaged.free() }
}

fn test_activity_preferences_temporary_cleanup_does_not_unlink_a_replacement() {
	home := activity_preferences_test_home('inode')
	name := '.vinix-activity-settings.tmp.test'
	path := home + '/' + name
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() } }
	mut app := ActivityApp{}
	app.load_view_preferences(home)
	defer { app.close_app() }
	fd := C.openat(app.preferences.home_fd, &char(name.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	assert fd >= 0
	defer { desktop_close(fd) }
	mut original := C.stat{}
	assert unsafe { C.fstat(fd, &original) } == 0
	os.rm(path)!
	os.write_file(path, 'replacement must survive')!
	activity_preferences_remove_temporary(app.preferences.home_fd, name, original)
	replacement := os.read_file(path)!
	assert replacement == 'replacement must survive'
	unsafe { replacement.free() }
	// Exhaust the bounded exclusive-create attempts without overwriting any
	// existing temporary name. A later preference change retries a fresh name.
	pid := C.getpid().str()
	defer { unsafe { pid.free() } }
	for number in 1 .. 17 {
		serial := number.str()
		collision := home + '/.vinix-activity-settings.tmp.' + pid + '.' + serial
		os.write_file(collision, 'preserve collision')!
		unsafe { serial.free() collision.free() }
	}
	app.handle(activity_action_tree)!
	assert app.preferences.status == 'activity.preferences.save_failed'
	assert app.preferences.sequence == 16
	record := activity_preferences_test_file(home)
	defer { unsafe { record.free() } }
	assert !os.exists(record)
	for number in 1 .. 17 {
		serial := number.str()
		collision := home + '/.vinix-activity-settings.tmp.' + pid + '.' + serial
		preserved := os.read_file(collision)!
		assert preserved == 'preserve collision'
		unsafe { serial.free() collision.free() preserved.free() }
	}
	app.handle(activity_action_interval)!
	assert app.preferences.status.len == 0 && os.exists(record)
}
