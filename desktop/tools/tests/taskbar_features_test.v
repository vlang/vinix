// SPDX-License-Identifier: GPL-2.0-or-later
// Windows 7-style taskbar and Start menu behaviour: reordering, previews and
// Aero Peek, Show Desktop, Jump Lists, Start menu history and pins, the
// notification area, and taskbar progress and badges.
module main

import os
import ui2

fn taskbar_test_home(name string) string {
	home := os.join_path(os.temp_dir(), 'vinix-taskbar-${name}-${os.getpid()}')
	os.rmdir_all(home) or {}
	os.mkdir_all(home) or { panic(err) }
	return home
}

fn taskbar_test_desktop(home string) Desktop {
	return Desktop{
		home:   home
		canvas: new_scaled_canvas(1280, 720, 1280, 720, 1)
		fonts:  load_fonts()
	}
}

fn taskbar_test_frame(mut d Desktop) {
	tree := d.build_tree()
	d.render(tree)
	free_tree(tree)
}

fn taskbar_test_window(mut d Desktop, title string, factory int, x int, y int) int {
	id := d.spawn(title, .welcome, x, y, 300, 180)
	index := d.window_index(id) or { panic('missing window') }
	d.windows[index].factory_index = factory
	return id
}

fn taskbar_test_target(d &Desktop, action string) HitTarget {
	return d.hit_target_named(action) or { panic('no hit target ${action}') }
}

fn taskbar_test_entry_keys(d &Desktop) []string {
	entries := d.taskbar_entries()
	mut keys := []string{}
	for entry in entries {
		keys << entry.key
	}
	unsafe { entries.free() }
	return keys
}

// ── Reordering ─────────────────────────────────────────────────────

fn test_dragging_a_pinned_button_reorders_and_saves_the_pins() {
	home := taskbar_test_home('drag')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	assert d.pin_taskbar_app_in(home, 0)
	assert d.pin_taskbar_app_in(home, 3)
	assert d.pin_taskbar_app_in(home, 1)
	taskbar_test_frame(mut d)
	firefox := taskbar_test_target(d, taskbar_pin_actions[1])
	files := taskbar_test_target(d, taskbar_pin_actions[0])
	d.on_pointer_down(firefox.x + 10, firefox.y + 10)
	// A closed pin does not start on the press.
	assert d.windows.len == 0
	d.buttons = button_left
	d.on_pointer_move(firefox.x + 30, firefox.y + 10)
	assert d.taskbar_press.dragging
	d.on_pointer_move(files.x + 5, files.y + 10)
	assert d.pinned_apps == [1, 0, 3]
	// The same release position again, with no frame in between, is a no-op.
	d.buttons = 0
	assert d.finish_taskbar_press_in(home, taskbar_pin_actions[1], files.x + 5, files.y + 10) == none
	assert d.pinned_apps == [1, 0, 3]
	assert load_taskbar_pins(home) == [1, 0, 3]
	assert !d.taskbar_press.active
}

fn test_a_click_without_a_drag_on_a_closed_pin_launches_on_release() {
	home := taskbar_test_home('click')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	assert d.pin_taskbar_app_in(home, 3)
	taskbar_test_frame(mut d)
	pin := taskbar_test_target(d, taskbar_pin_actions[3])
	d.taskbar_entry_click(taskbar_pin_actions[3], pin.x + 4, pin.y + 4)
	assert d.taskbar_press.launch_on_release
	app := d.finish_taskbar_press_in(home, taskbar_pin_actions[3], pin.x + 5, pin.y + 4) or {
		panic('a click on a closed pin should launch it')
	}
	assert app == 3
	// Releasing somewhere else cancels the click.
	d.taskbar_entry_click(taskbar_pin_actions[3], pin.x + 4, pin.y + 4)
	assert d.finish_taskbar_press_in(home, '', pin.x + 4, 300) == none
}

fn test_dragging_running_buttons_exchanges_their_ranks() {
	home := taskbar_test_home('ranks')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	one := taskbar_test_window(mut d, 'One', -1, 10, 10)
	two := taskbar_test_window(mut d, 'Two', -1, 40, 40)
	three := taskbar_test_window(mut d, 'Three', -1, 80, 80)
	d.move_taskbar_entry('task.${three}', 'task.${one}', false)
	assert taskbar_test_entry_keys(d) == ['task.${three}', 'task.${one}', 'task.${two}']
	// Raising a window changes painting order, not taskbar order.
	d.raise(one)
	assert taskbar_test_entry_keys(d) == ['task.${three}', 'task.${one}', 'task.${two}']

	// Combined groups move as a whole and keep their windows' own order.
	d.settings.taskbar_mode = .combined
	taskbar_test_window(mut d, 'One', -1, 120, 120)
	assert taskbar_test_entry_keys(d) == ['Three', 'One', 'Two']
	d.move_taskbar_entry('Two', 'Three', false)
	assert taskbar_test_entry_keys(d) == ['Two', 'Three', 'One']
}

// ── Previews, the picker and Aero Peek ─────────────────────────────

fn test_resting_on_a_button_opens_its_preview_and_a_thumbnail_peeks() {
	home := taskbar_test_home('preview')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	first := taskbar_test_window(mut d, 'First', -1, 40, 40)
	taskbar_test_window(mut d, 'Second', -1, 600, 300)
	taskbar_test_frame(mut d)
	// Both windows were in full view, so both have pictures of themselves.
	first_index := d.window_index(first) or { panic('missing') }
	assert d.windows[first_index].thumbnail.len > 0
	assert d.windows[first_index].thumbnail_width == thumbnail_max_width
	// A thumbnail is the window's own pixels: its white body, not wallpaper.
	middle := d.windows[first_index].thumbnail[(d.windows[first_index].thumbnail_height / 2) * d.windows[first_index].thumbnail_width +
		d.windows[first_index].thumbnail_width / 2]
	assert middle == d.theme().window_body

	button := taskbar_test_target(d, 'task.${first}')
	d.set_hover('task.${first}')
	d.update_taskbar_hover_at(1000)
	assert !d.taskbar_preview.open
	d.update_taskbar_hover_at(1000 + taskbar_preview_delay_ms)
	assert d.taskbar_preview.open
	assert d.taskbar_preview.anchor_x == button.x + button.width / 2
	taskbar_test_frame(mut d)
	panel := taskbar_test_target(d, taskbar_preview_panel)
	assert panel.y + panel.height <= d.canvas.height - taskbar_height

	d.set_hover('${taskbar_preview_prefix}${first}')
	d.update_taskbar_hover_at(2000)
	d.update_taskbar_hover_at(2000 + taskbar_peek_delay_ms)
	assert d.peek_target() == first
	root := d.build_tree()
	mut ghosts := 0
	for child in root.children {
		if child.id == peek_ghost_id {
			ghosts++
		}
	}
	assert ghosts == 1
	free_tree(root)

	// Leaving the button and the panel closes the preview after a moment.
	d.set_hover('')
	d.update_taskbar_hover_at(3000)
	assert d.peek_target() == 0
	assert d.taskbar_preview.open
	d.update_taskbar_hover_at(3000 + taskbar_preview_linger_ms)
	assert !d.taskbar_preview.open
}

fn test_a_grouped_button_click_opens_the_picker_and_a_tile_activates() {
	home := taskbar_test_home('picker')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	d.settings.taskbar_mode = .combined
	a := taskbar_test_window(mut d, 'Terminal', 3, 10, 10)
	b := taskbar_test_window(mut d, 'Terminal', 3, 400, 10)
	c := taskbar_test_window(mut d, 'Terminal', 3, 10, 300)
	taskbar_test_frame(mut d)
	entry := d.taskbar_entry_for_action('task.${c}') or { panic('missing group') }
	assert entry.window_count == 3
	d.taskbar_entry_click(entry.id, 70, 700)
	assert d.taskbar_preview.open
	assert d.focus == c
	taskbar_test_frame(mut d)
	for id in [a, b, c] {
		index := d.window_index(id) or { panic('missing') }
		taskbar_test_target(d, d.windows[index].id_preview)
	}
	d.handle_preview_action('${taskbar_preview_prefix}${a}')
	assert d.focus == a
	assert !d.taskbar_preview.open
	// The close button on a tile closes that window only.
	d.handle_preview_action('${taskbar_preview_prefix}${b}.close')
	assert d.window_index(b) == none
	assert d.windows.len == 2
}

// ── Show Desktop ───────────────────────────────────────────────────

fn test_show_desktop_hides_and_restores_exactly_its_windows() {
	mut d := taskbar_test_desktop(taskbar_test_home('show'))
	defer {
		os.rmdir_all(d.home) or {}
		unsafe { free(d.canvas.pixels) }
	}
	one := taskbar_test_window(mut d, 'One', -1, 10, 10)
	taskbar_test_window(mut d, 'Two', -1, 40, 40)
	already := taskbar_test_window(mut d, 'Minimized', -1, 80, 80)
	d.minimize(already)
	d.raise(one)
	d.toggle_show_desktop()
	assert d.show_desktop.active
	assert d.visible_window_count() == 0
	assert d.focus == 0
	// Super+D is the same toggle.
	rest := d.take_window_shortcuts(key_super_d)
	assert rest == ''
	assert d.visible_window_count() == 2
	index := d.window_index(already) or { panic('missing') }
	assert d.windows[index].minimized
	// The painting order comes back as it was: One was on top.
	assert d.windows.last().id == one
	taskbar_test_frame(mut d)
	taskbar_test_target(d, action_show_desktop)
	d.set_hover(action_show_desktop)
	d.update_taskbar_hover_at(100)
	d.update_taskbar_hover_at(100 + taskbar_peek_delay_ms)
	assert d.peek_target() == -1
	root := d.build_tree()
	for child in root.children {
		assert !child.id.starts_with('win.')
	}
	free_tree(root)
}

// ── Jump Lists ─────────────────────────────────────────────────────

fn jump_list_titles() []string {
	mut titles := []string{}
	for entry in taskbar_jump_list.entries {
		titles << entry.title
	}
	return titles
}

fn test_jump_list_shows_recent_folders_tasks_and_program_actions() {
	home := taskbar_test_home('jump')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	os.mkdir_all('${home}/Projects') or { panic(err) }
	os.mkdir_all('${home}/Music') or { panic(err) }
	assert record_recent_item_in(home, 'vinix-files', '${home}/Music')
	assert record_recent_item_in(home, 'vinix-files', '${home}/Projects')
	assert record_recent_item_in(home, 'vinix-files', '${home}/Missing')
	assert record_recent_item_in(home, 'vinix-editor', '${home}/Projects')
	files := taskbar_test_window(mut d, 'Files', 0, 10, 10)
	taskbar_test_window(mut d, 'Files', 0, 300, 10)
	d.settings.taskbar_mode = .combined
	taskbar_test_frame(mut d)
	target := taskbar_test_target(d, 'task.${files + 1}')
	assert d.open_create_context_menu(target.x + 4, target.y + 4)
	assert create_context_menu.target == .taskbar
	titles := jump_list_titles()
	// A missing folder is not offered; another program's history is not mixed in.
	assert titles == ['Recent', 'Projects', 'Music', 'Tasks', 'Home', 'Documents', 'Downloads',
		'Computer', '', 'Files', 'Pin this program to taskbar', 'Close all windows']
	// It rises from the taskbar, clear of it.
	assert create_context_menu.y + taskbar_jump_list.height <= d.canvas.height - taskbar_height
	assert context_menu_height(.taskbar, true) == taskbar_jump_list.height

	// Choosing Pin runs through the menu's own click path.
	d.render_create_context_menu()
	mut pin_action := ''
	for entry in taskbar_jump_list.entries {
		if entry.command == .pin {
			pin_action = entry.id
		}
	}
	pin := taskbar_test_target(d, pin_action)
	assert d.create_context_left_down(pin.x + 2, pin.y + 2)
	assert !create_context_menu.visible
	assert taskbar_jump_list.entries.len == 0
	assert d.taskbar_is_pinned(0)
	assert take_create_context_left_release()

	taskbar_test_frame(mut d)
	pinned := taskbar_test_target(d, taskbar_pin_actions[0])
	assert d.open_create_context_menu(pinned.x + 4, pinned.y + 4)
	d.render_create_context_menu()
	mut close_all := ''
	for entry in taskbar_jump_list.entries {
		if entry.command == .close_all {
			close_all = entry.id
		}
	}
	close := taskbar_test_target(d, close_all)
	assert d.create_context_left_down(close.x + 2, close.y + 2)
	assert d.windows.len == 0
	take_create_context_left_release()
}

fn test_recent_history_is_bounded_per_program_and_most_recent_first() {
	home := taskbar_test_home('history')
	defer { os.rmdir_all(home) or {} }
	for index in 0 .. recent_items_per_app + 3 {
		os.mkdir_all('${home}/d${index}') or { panic(err) }
		assert record_recent_item_in(home, 'vinix-files', '${home}/d${index}')
	}
	assert record_recent_item_in(home, 'vinix-files', '${home}/d2')
	items := recent_items_for(home, 'vinix-files', 100)
	assert items.len == recent_items_per_app
	assert items[0].path == '${home}/d2'
	assert items[1].path == '${home}/d${recent_items_per_app + 2}'
	free_recent_items(items)
	assert !record_recent_item_in(home, 'vinix-files', 'relative/path')
	assert !record_recent_item_in(home, 'vinix-files', '/bad\npath')
}

// ── Start menu ─────────────────────────────────────────────────────

fn test_start_menu_lists_pins_then_recent_programs() {
	home := taskbar_test_home('start')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	d.record_recent_program_in(home, 6)
	d.record_recent_program_in(home, 0)
	d.record_recent_program_in(home, 6)
	assert d.recent_programs == [6, 0]
	assert load_recent_programs(home) == [6, 0]
	assert d.pin_start_app_in(home, 4)
	assert load_start_pins(home) == [4]
	d.toggle_start_menu()
	root := d.build_tree()
	programs := utility_find(root, 'start.programs') or { panic('missing program pane') }
	mut order := []string{}
	for child in programs.children {
		if child.id.starts_with(action_start_launch_prefix) {
			order << child.text
		}
	}
	assert order == ['Settings', 'Text Editor', 'Files']
	// Programs that keep a history get the arrow to it.
	assert utility_find(programs, app_start_jump_actions[6]) != none
	assert utility_find(programs, app_start_jump_actions[4]) == none
	free_tree(root)

	entries := d.start_context_entries(0)
	assert entries.len == 4
	assert entries[1].id == start_context_pin_start
	assert entries[3].id == start_context_forget
	unsafe { entries.free() }
	d.start_context_action(start_context_forget, 0)
	assert d.recent_programs == [6]
	d.start_context_action(start_context_unpin_start, 4)
	assert d.start_pins.len == 0
	d.close_start_menu()
}

fn test_start_menu_recent_items_pane_opens_a_programs_history() {
	home := taskbar_test_home('recentpane')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	os.write_file('${home}/notes.txt', 'text') or { panic(err) }
	os.mkdir_all('${home}/Work') or { panic(err) }
	record_recent_item_in(home, 'vinix-editor', '${home}/notes.txt')
	record_recent_item_in(home, 'vinix-files', '${home}/Work')
	d.toggle_start_menu()
	d.set_hover(app_start_jump_actions[6])
	d.update_start_menu_hover()
	assert d.start_menu_recent_app == 6
	assert d.start_menu_recent_titles == ['notes.txt']
	d.handle_start_action(action_start_recent)
	assert d.start_menu_recent_app == start_recent_all
	assert d.start_menu_recent_titles == ['Work', 'notes.txt']
	assert d.start_menu_recent_dirs == [true, false]
	root := d.build_tree()
	assert utility_find(root, start_recent_item_actions[1]) != none
	free_tree(root)
	d.handle_start_action(action_start_recent_back)
	assert d.start_menu_recent_app == start_recent_none
	d.close_start_menu()
}

// ── Notification area ──────────────────────────────────────────────

fn test_notification_area_shows_status_icons_and_moves_them_to_overflow() {
	home := taskbar_test_home('tray')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	d.tray.preferences_loaded = true
	d.apply_tray_sample(TraySample{
		ethernet: .connected
		address:  0x0f02000a
		battery:  37
		charging: true
	})
	assert d.tray.network_tip == 'Ethernet: 10.0.2.15'
	assert d.tray.battery_tip == 'Battery: 37%, charging'
	assert d.tray_glyph(.network) == 'builtin:network_wired'
	assert d.tray_glyph(.battery) == 'builtin:battery_charging_40'
	assert d.tray.on_taskbar(.battery)
	assert d.tray.overflow_count() == 2
	taskbar_test_frame(mut d)
	taskbar_test_target(d, 'tray.icon.network')
	battery := taskbar_test_target(d, 'tray.icon.battery')
	taskbar_test_target(d, action_tray_overflow)

	// Right-click moves an icon into the overflow panel, and it stays there.
	assert d.open_create_context_menu(battery.x + 2, battery.y + 2)
	assert create_context_menu.target == .tray
	d.render_create_context_menu()
	hide := taskbar_test_target(d, tray_context_hide)
	assert d.create_context_left_down(hide.x + 2, hide.y + 2)
	take_create_context_left_release()
	assert !d.tray.on_taskbar(.battery)
	assert d.tray.overflow_count() == 3
	mut reloaded := taskbar_test_desktop(home)
	reloaded.load_tray_preferences(home)
	assert reloaded.tray.hide_battery
	assert !reloaded.tray.hide_network
	unsafe { free(reloaded.canvas.pixels) }

	// The chevron opens the overflow; one of its icons opens that flyout.
	d.handle_tray_action(action_tray_overflow)
	assert d.tray.flyout == .overflow
	taskbar_test_frame(mut d)
	taskbar_test_target(d, 'tray.overflow.icon.battery')
	d.tray.sampled_ms = monotonic_millis()
	d.handle_tray_action('tray.overflow.icon.capture')
	assert d.tray.flyout == .capture
	assert d.tray.flyout_anchor == action_tray_overflow
	taskbar_test_frame(mut d)
	taskbar_test_target(d, action_tray_capture_screenshot)
	// Pressing elsewhere closes it.
	d.on_pointer_down(600, 300)
	assert d.tray.flyout == .none_

	// A machine with no battery shows no battery icon anywhere.
	d.apply_tray_sample(TraySample{
		ethernet: .absent
		battery:  battery_unavailable
	})
	assert !d.tray.present(.battery)
	assert d.tray_glyph(.network) == 'builtin:network_offline'
	assert d.tooltip_text('tray.icon.network') == 'Not connected'
}

// ── Progress and badges ────────────────────────────────────────────

fn test_task_status_file_format_round_trips() {
	status := parse_task_status('state paused\nprogress 250\nbadge 12\nattention 4\njunk\n'.bytes())
	assert status.progress_state == .paused
	assert status.progress == 100
	assert status.badge == '12'
	assert status.attention_serial == 4
	bare := parse_task_status('progress 30'.bytes())
	assert bare.progress_state == .normal
	assert bare.progress == 30
	assert parse_task_status('badge toolong\n'.bytes()).badge == ''
	assert parse_task_status([]u8{}).progress_state == .none_
	text := format_task_status(status)
	again := parse_task_status(text.bytes())
	assert again.same(status)
}

fn test_windows_report_progress_badges_and_attention_on_their_buttons() {
	home := taskbar_test_home('status')
	defer { os.rmdir_all(home) or {} }
	mut d := taskbar_test_desktop(home)
	defer { unsafe { free(d.canvas.pixels) } }
	busy := taskbar_test_window(mut d, 'Busy', -1, 10, 10)
	calling := taskbar_test_window(mut d, 'Calling', -1, 400, 10)
	busy_index := d.window_index(busy) or { panic('missing') }
	d.windows[busy_index].status_path = '${home}/busy'
	calling_index := d.window_index(calling) or { panic('missing') }
	d.windows[calling_index].status_path = '${home}/calling'
	os.write_file('${home}/busy', 'progress 40\nbadge 2\n') or { panic(err) }
	os.write_file('${home}/calling', 'attention 1\n') or { panic(err) }
	d.raise(busy)
	d.poll_taskbar_status()
	entries := d.taskbar_entries()
	assert entries[0].status.progress_state == .normal
	assert entries[0].status.progress == 40
	assert entries[0].status.badge == '2'
	assert entries[1].status.attention
	unsafe { entries.free() }
	root := d.build_tree()
	taskbar := utility_find(root, 'taskbar') or { panic('missing taskbar') }
	assert utility_find(taskbar, taskbar_progress_overlay_id) != none
	free_tree(root)

	// Bringing the window up is what answers the request.
	d.activate(calling)
	calling_now := d.window_index(calling) or { panic('missing') }
	assert !d.windows[calling_now].status.attention
	d.taskbar_status_polled_ms = 0
	d.poll_taskbar_status()
	calling_now2 := d.window_index(calling) or { panic('missing') }
	assert !d.windows[calling_now2].status.attention
	// Closing the window removes its status file.
	d.close_window(busy)
	assert !os.exists('${home}/busy')
}

fn test_terminal_turns_osc_progress_and_the_bell_into_taskbar_status() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(4, 20)
	terminal.ingest_output('\x1b]9;4;1;42\x07'.bytes())
	assert terminal.taskbar.progress_state == .normal
	assert terminal.taskbar.progress == 42
	terminal.ingest_output('\x1b]9;4;2\x1b\\'.bytes())
	assert terminal.taskbar.progress_state == .error
	assert terminal.taskbar.progress == 42
	terminal.ingest_output('\x1b]9;4;3;0\x07\x1b]0;title\x07'.bytes())
	assert terminal.taskbar.progress_state == .indeterminate
	terminal.ingest_output('\x1b]9;4;0;0\x07'.bytes())
	assert terminal.taskbar.progress_state == .none_
	terminal.ingest_output('done\x07'.bytes())
	assert terminal.taskbar.attention_serial == 1
}

// utility_find is a local copy of the utility suite's tree search, so this
// file can run on its own.
fn utility_find(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		if found := utility_find(child, id) {
			return found
		}
	}
	return none
}
