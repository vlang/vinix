// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn activity_kill_element_named(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := activity_kill_element_named(child, id) {
			return found
		}
	}
	return none
}

fn activity_kill_tree_has_text(element ui2.Element, text string) bool {
	if element.text == text {
		return true
	}
	for child in element.children {
		if activity_kill_tree_has_text(child, text) {
			return true
		}
	}
	return false
}

fn activity_kill_record(pid int, name string, memory u64) ActivitySample {
	mut record := ActivitySample{
		pid:          i32(pid)
		memory_bytes: memory
	}
	for index := 0; index < name.len && index < activity_name_len - 1; index++ {
		record.name[index] = name[index]
	}
	return record
}

fn activity_kill_snapshot(mut app ActivityApp, records []ActivitySample, sample_ns u64) {
	header := ActivityTable{
		total:        u32(records.len)
		total_memory: 256 * 1024 * 1024
		free_memory:  192 * 1024 * 1024
		sample_ns:    sample_ns
	}
	app.monitor.apply_snapshot(&header, unsafe { &records[0] }, records.len)
}

fn activity_kill_free(mut app ActivityApp) {
	app.monitor.free_rows()
	unsafe {
		app.monitor.previous.free()
		app.monitor.error.free()
	}
}

fn test_activity_kill_button_is_an_icon_at_the_top_left_and_disabled_without_selection() {
	mut app := ActivityApp{}
	defer { activity_kill_free(mut app) }
	tree := app.build(ui2.rect(0, 0, 520, 360))!
	defer { free_tree(tree) }
	button := activity_kill_element_named(tree, activity_action_kill) or {
		panic('missing Kill process button')
	}
	assert button.kind == .button
	assert button.text == ''
	assert button.image_path == 'builtin:close'
	assert button.tooltip == tr('activity.kill')
	assert button.accessibility_label == tr('activity.kill')
	assert !button.enabled
	assert button.frame.x == f64(activity_padding)
	assert button.frame.y >= 0 && button.frame.y + button.frame.height <= activity_toolbar_height
	heading := activity_kill_element_named(tree, activity_action_name) or {
		panic('missing Name heading')
	}
	assert heading.frame.y >= button.frame.y + button.frame.height
	assert !activity_kill_tree_has_text(tree, tr('activity.kill'))

	// A direct action is harmless even when a disabled control is bypassed.
	app.monitor.last_poll_ms = 123
	app.handle(activity_action_kill)!
	assert app.monitor.selected_pid == 0
	assert !app.kill_failed
	assert app.monitor.last_poll_ms == 123
}

fn test_activity_kill_selection_follows_the_pid_through_sort_and_refresh() {
	mut app := ActivityApp{}
	defer { activity_kill_free(mut app) }
	mut records := [
		activity_kill_record(2, '/bin/sh[2]', 9_000_000),
		activity_kill_record(7, '/usr/bin/vinix-files[7]', 13_000_000),
		activity_kill_record(3, '/usr/bin/vinix-desktop[3]', 30_000_000),
	]
	defer { unsafe { records.free() } }
	activity_kill_snapshot(mut app, records, 1_000_000_000)
	index := app.monitor.process_row_index(7)
	app.handle(app.monitor.rows[index].select_action)!
	assert app.monitor.selected_pid == 7
	assert app.monitor.can_kill_selected()
	tree := app.build(ui2.rect(0, 0, 520, 360))!
	button := activity_kill_element_named(tree, activity_action_kill) or { panic('missing kill button') }
	assert button.enabled
	row := activity_kill_element_named(tree, app.monitor.rows[index].select_action) or {
		panic('missing selected process row')
	}
	assert row.box.bg == files_sidebar_selected && !row.box.transparent
	assert row.frame.y >= activity_toolbar_height + activity_header_height
	free_tree(tree)

	app.handle(activity_action_pid)!
	assert app.monitor.selected_pid == 7
	app.handle(activity_action_pid)!
	assert app.monitor.selected_pid == 7
	app.handle(activity_action_memory)!
	assert app.monitor.selected_pid == 7
	app.handle(activity_action_name)!
	assert app.monitor.selected_pid == 7
	// Changing both source order and usage moves rows without changing selection.
	records.reverse_in_place()
	records[1].memory_bytes = 40_000_000
	activity_kill_snapshot(mut app, records, 2_000_000_000)
	assert app.monitor.selected_pid == 7
	assert app.monitor.can_kill_selected()

	remaining := [activity_kill_record(2, '/bin/sh[2]', 9_000_000)]
	defer { unsafe { remaining.free() } }
	activity_kill_snapshot(mut app, remaining, 3_000_000_000)
	assert app.monitor.selected_pid == 0
	assert !app.monitor.can_kill_selected()
	app.handle('activity.select.7')!
	assert app.monitor.selected_pid == 0
	app.handle(app.monitor.rows[0].select_action)!
	assert app.monitor.selected_pid == 2
	app.monitor.fail('sample failed'.clone())
	assert app.monitor.selected_pid == 0
	assert !app.monitor.can_kill_selected()
	failed := app.build(ui2.rect(0, 0, 520, 360))!
	defer { free_tree(failed) }
	failed_button := activity_kill_element_named(failed, activity_action_kill) or {
		panic('missing kill button after failed sample')
	}
	assert !failed_button.enabled
}

fn test_activity_kill_never_signals_init_or_special_process_ids() {
	// These calls must return before kill(2), whose nonpositive PIDs address groups.
	assert !desktop_kill_process(-1)
	assert !desktop_kill_process(-22)
	assert !desktop_kill_process(0)
	assert !desktop_kill_process(1)
	mut app := ActivityApp{}
	defer { activity_kill_free(mut app) }
	records := [activity_kill_record(1, '/sbin/init[1]', 1_000_000)]
	defer { unsafe { records.free() } }
	activity_kill_snapshot(mut app, records, 1_000_000_000)
	app.handle(app.monitor.rows[0].select_action)!
	assert app.monitor.selected_pid == 1
	assert !app.monitor.can_kill_selected()
	tree := app.build(ui2.rect(0, 0, 520, 360))!
	defer { free_tree(tree) }
	button := activity_kill_element_named(tree, activity_action_kill) or { panic('missing kill button') }
	assert !button.enabled
	app.handle(activity_action_kill)!
	assert app.monitor.selected_pid == 1
	assert !app.kill_failed
}

fn test_activity_kill_action_sends_sigkill_to_an_owned_child() {
	mut child := os.new_process('/bin/sleep')
	child.set_args(['60'])
	child.run()
	assert child.status == .running && child.pid > 1
	defer {
		if child.status in [.running, .stopped] {
			C.kill(child.pid, C.SIGKILL)
			child.wait()
		}
		child.close()
	}
	mut app := ActivityApp{}
	defer { activity_kill_free(mut app) }
	records := [activity_kill_record(child.pid, '/bin/sleep', 1_000_000)]
	defer { unsafe { records.free() } }
	activity_kill_snapshot(mut app, records, 1_000_000_000)
	app.handle(app.monitor.rows[0].select_action)!
	assert app.monitor.can_kill_selected()
	app.handle(activity_action_kill)!
	assert !app.kill_failed
	assert app.monitor.selected_pid == 0
	assert monotonic_millis() - app.monitor.last_poll_ms >= activity_interval_ms
	// The app signals without consuming the exit status; the parent can still reap it.
	child.wait()
	assert child.status == .aborted
	assert child.code == 128 + int(C.SIGKILL)
}

fn test_activity_kill_failure_is_visible_and_resets_when_selection_disappears() {
	mut child := os.new_process('/usr/bin/true')
	child.run()
	assert child.pid > 1
	child.wait()
	assert child.status == .exited && child.code == 0
	defer { child.close() }
	mut app := ActivityApp{}
	defer { activity_kill_free(mut app) }
	// A retained snapshot of our already reaped child exercises ESRCH safely.
	records := [activity_kill_record(child.pid, '/usr/bin/true', 1_000_000)]
	defer { unsafe { records.free() } }
	activity_kill_snapshot(mut app, records, 1_000_000_000)
	app.handle(app.monitor.rows[0].select_action)!
	app.handle(activity_action_kill)!
	assert app.kill_failed
	assert app.monitor.selected_pid == child.pid
	assert app.monitor.rows.len == 1
	tree := app.build(ui2.rect(0, 0, 520, 360))!
	assert activity_kill_tree_has_text(tree, tr('activity.error.kill'))
	free_tree(tree)
	app.handle(app.monitor.rows[0].select_action)!
	assert !app.kill_failed
	app.handle(activity_action_kill)!
	assert app.kill_failed
	remaining := [activity_kill_record(1, '/sbin/init[1]', 1_000_000)]
	defer { unsafe { remaining.free() } }
	activity_kill_snapshot(mut app, remaining, 2_000_000_000)
	assert app.monitor.selected_pid == 0
	cleared := app.build(ui2.rect(0, 0, 520, 360))!
	defer { free_tree(cleared) }
	assert !app.kill_failed
	assert !activity_kill_tree_has_text(cleared, tr('activity.error.kill'))
}
