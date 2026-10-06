// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(index u32) u64

fn activity_preferences_memory_home(suffix string) string {
	pid := C.getpid().str()
	home := os.join_path(os.temp_dir(), 'vinix-activity-prefs-memory-${pid}-${suffix}')
	unsafe { pid.free() }
	os.mkdir(home) or { panic(err) }
	canonical := os.real_path(home)
	unsafe { home.free() }
	return canonical
}

fn test_activity_preferences_codec_success_and_rejection_have_no_retained_allocations() {
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for columns in [u32(1), 15, 511]! {
			p := ActivityViewPreferences{sort: .cpu_time, descending: false, filter: .other_users,
				hierarchy: true, columns: columns, interval_ms: 500, view: .resources, resource_tab: .disk}
			text := activity_encode_view_preferences(p) or { panic('valid encode failed') }
			assert (activity_parse_view_preferences(text) or { panic('valid parse failed') }) == p
			bad := text + 'tree=0\n'
			assert activity_parse_view_preferences(bad) == none
			unsafe { text.free() bad.free() }
		}
		assert activity_parse_view_preferences('version=1\nsort=cpu\n') == none
		assert activity_encode_view_preferences(ActivityViewPreferences{columns: 0}) == none
	}
	assert C.vinix_heap_end() == 0
}

fn activity_preferences_memory_frames(mut app ActivityApp) {
	for action in ['activity.view.processes', 'activity.view.resources', 'activity.resources.memory']! {
		app.handle(action) or { panic(err) }
		for size in [ui2.rect(0, 0, 900, 540), ui2.rect(0, 0, 360, 260)]! {
			begin_frame_elements()
			free_tree(app.build(size) or { panic(err) })
		}
	}
}

fn test_activity_preferences_complete_registered_user_save_reopen_resize_and_close_release_owned_memory() {
	home := activity_preferences_memory_home('complete')
	alias := home + '-alias'
	path := home + '/' + activity_preferences_filename
	os.symlink(home, alias)!
	defer { os.rm(alias) or {} os.rmdir_all(home) or {} unsafe { home.free() alias.free() path.free() } }
	mut warm := ActivityApp{}
	warm.load_view_preferences(alias)
	activity_preferences_memory_frames(mut warm)
	warm.close_app()
	assert C.unlink(&char(path.str)) == 0
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := ActivityApp{}
		app.load_view_preferences(alias)
		app.handle(activity_action_tree)!
		app.handle(activity_action_interval)!
		app.handle(activity_action_name)!
		app.handle('activity.column.toggle.state')!
		activity_preferences_memory_frames(mut app)
		assert app.preferences.status.len == 0
		app.close_app()
		mut reopened := ActivityApp{}
		reopened.load_view_preferences(alias)
		assert reopened.monitor.sort == .name && reopened.monitor.hierarchy
		assert reopened.monitor.interval_ms == 2000 && reopened.resources.tab == .memory
		reopened.close_app()
		assert C.unlink(&char(path.str)) == 0
	}
	assert C.vinix_heap_end() == 0
}

fn test_activity_preferences_damaged_init_and_failed_lock_retries_do_not_retain_memory() {
	home := activity_preferences_memory_home('failures')
	path := home + '/' + activity_preferences_filename
	os.write_file(path, 'damaged record')!
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() } }
	mut warm := ActivityApp{}
	warm.load_view_preferences(home)
	activity_preferences_memory_frames(mut warm)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut damaged := ActivityApp{}
		damaged.load_view_preferences(home)
		activity_preferences_memory_frames(mut damaged)
		assert damaged.preferences.read_failed
		damaged.close_app()
	}
	assert C.vinix_heap_end() == 0
	assert C.unlink(&char(path.str)) == 0
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := ActivityApp{}
		app.load_view_preferences(home)
		app.handle(activity_action_tree)!
		lock_fd := activity_preferences_lock(app.preferences.home_fd)
		assert lock_fd >= 0
		app.handle(activity_action_interval)!
		assert app.preferences.status == 'activity.preferences.save_failed'
		assert desktop_close(lock_fd) == 0
		app.handle(activity_action_interval)!
		assert app.preferences.status.len == 0
		app.close_app()
		assert C.unlink(&char(path.str)) == 0
	}
	assert C.vinix_heap_end() == 0
}

fn test_activity_preferences_stale_windows_keep_live_choices_and_free_all_error_paths() {
	home := activity_preferences_memory_home('conflict')
	path := home + '/' + activity_preferences_filename
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut first := ActivityApp{}
		mut stale := ActivityApp{}
		first.load_view_preferences(home)
		stale.load_view_preferences(home)
		first.handle(activity_action_tree)!
		stale.handle(activity_action_interval)!
		assert stale.preferences.status == 'activity.preferences.changed'
		assert stale.monitor.interval_ms == 2000
		first.close_app()
		stale.close_app()
		assert C.unlink(&char(path.str)) == 0
		mut missing := ActivityApp{}
		missing.load_view_preferences('/nonexistent-vinix-activity-home')
		assert missing.preferences.read_failed
		missing.close_app()
	}
	assert C.vinix_heap_end() == 0
	pid := C.getpid().str()
	defer { unsafe { pid.free() } }
	for number in 1 .. 17 {
		serial := number.str()
		collision := home + '/.vinix-activity-settings.tmp.' + pid + '.' + serial
		os.write_file(collision, 'collision')!
		unsafe { serial.free() collision.free() }
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := ActivityApp{}
		app.load_view_preferences(home)
		app.handle(activity_action_tree)!
		assert app.preferences.status == 'activity.preferences.save_failed'
		assert app.preferences.sequence == 16
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}
