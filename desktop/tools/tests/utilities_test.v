// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

import os
import ui2

fn utility_tree_has_text(element ui2.Element, text string) bool {
	if element.text == text {
		return true
	}
	for child in element.children {
		if utility_tree_has_text(child, text) {
			return true
		}
	}
	return false
}

fn utility_element_named(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		found := utility_element_named(child, id) or { continue }
		return found
	}
	return none
}

fn utility_button_with_text(element ui2.Element, text string) ?ui2.Element {
	if element.kind == .button && element.text == text {
		return element
	}
	for child in element.children {
		found := utility_button_with_text(child, text) or { continue }
		return found
	}
	return none
}

struct PointerFocusTestApp {}

fn (mut app PointerFocusTestApp) build(size ui2.Rect) !ui2.Element {
	return ui2.screen(0, [])
}

fn (mut app PointerFocusTestApp) handle(_ string) ! {}

fn (mut app PointerFocusTestApp) pointer_input_enabled() bool {
	return true
}

fn (mut app PointerFocusTestApp) pointer_event(_ AppPointerPhase, _ int, _ int, _ int, _ int) {}

fn test_text_editor_inserts_and_navigates() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.key_input('hello\nworld')
	assert editor_bytes_text(editor.text) == 'hello\nworld'
	assert editor.cursor == editor.text.len

	// Up preserves the column, insertion happens at the cursor, then Home and
	// Delete edit in place rather than reducing the editor to an append box.
	editor.key_input('\x1b[A!')
	assert editor_bytes_text(editor.text) == 'hello!\nworld'
	assert editor.cursor == 6
	editor.key_input('\x1b[H\x1b[C\x1b[3~')
	assert editor_bytes_text(editor.text) == 'hllo!\nworld'
	assert editor.modified

	editor.key_input('\x0e')
	assert editor.text.len == 0
	assert editor_bytes_text(editor.path) == editor_default_path
	assert !editor.modified
}

fn test_text_editor_saves_and_opens_a_real_file() {
	path := os.join_path(os.temp_dir(), 'vinix-desktop-editor-test.txt')
	mut writer := TextEditorApp{}
	writer.set_path(path)
	writer.key_input('Vinix utilities\nwork.')
	writer.save_document()
	assert !writer.modified
	assert editor_bytes_text(writer.status).starts_with('Saved ')

	mut reader := TextEditorApp{}
	reader.set_path(path)
	reader.open_document()
	assert editor_bytes_text(reader.text) == 'Vinix utilities\nwork.'
	assert reader.cursor == reader.text.len
	assert !reader.modified
	os.rm(path) or {}
}

fn test_calendar_arithmetic_and_navigation() {
	assert calendar_is_leap_year(2000)
	assert !calendar_is_leap_year(1900)
	assert calendar_days_in_month(2024, 2) == 29
	assert calendar_days_in_month(2025, 2) == 28
	assert calendar_weekday(1970, 1, 1) == 4
	assert calendar_weekday(2026, 9, 7) == 1

	mut calendar := CalendarApp{
		year: 2024
		month: 1
		selected_day: 31
	}
	calendar.refresh_labels()
	calendar.change_month(1)
	assert calendar.year == 2024
	assert calendar.month == 2
	assert calendar.selected_day == 29
	calendar.change_month(-2)
	assert calendar.year == 2023
	assert calendar.month == 12
}

fn test_clock_stopwatch_format_and_elapsed_time() {
	assert clock_stopwatch_text(0) == '00:00:00.0'
	assert clock_stopwatch_text(3_726_599) == '01:02:06.5'
	clock := ClockApp{
		running: true
		started_ms: 1_000
		accumulated_ms: 250
	}
	assert clock.elapsed(2_500) == 1_750
}

fn test_native_calculator_matches_the_example_layout_and_actions() {
	mut calculator := new_calculator_app()
	defer { calculator.close_app() }
	begin_frame_elements()
	tree := calculator.build(ui2.rect(0, 0, window_width, window_height))!
	panel := utility_element_named(tree, 'calculator') or { panic('missing calculator panel') }
	display := utility_element_named(tree, 'display') or {
		panic('missing calculator display')
	}
	clear := utility_button_with_text(tree, 'C') or { panic('missing clear key') }
	equals := utility_button_with_text(tree, '=') or { panic('missing equals key') }
	assert panel.children.len == 21
	assert display.text == '0'
	assert clear.text == 'C'
	assert clear.action_id == 'C'
	assert clear.box.bg == 0xef4444
	assert clear.native_style
	assert equals.text == '='
	assert equals.action_id == '='
	assert equals.box.bg == 0x3478d4
	assert equals.text_style.bold
	two := utility_button_with_text(tree, '2') or { panic('missing 2 key') }
	plus := utility_button_with_text(tree, '+') or { panic('missing + key') }
	three := utility_button_with_text(tree, '3') or { panic('missing 3 key') }

	// 2 + 3 = 5, routed through the action ids `$vml` put in the tree.
	calculator.handle(two.action_id)!
	calculator.handle(plus.action_id)!
	calculator.handle(three.action_id)!
	calculator.handle(equals.action_id)!
	assert calculator.calculator.display == '5'
	free_tree(tree)
	updated := calculator.build(ui2.rect(0, 0, window_width, window_height))!
	updated_display := utility_element_named(updated, 'display') or {
		panic('missing updated calculator display')
	}
	assert updated_display.text == '5'
	free_tree(updated)

	// The application-process request loop resets the pool before every build.
	// Repeated interaction must not grow it while each compile-time VML tree is
	// released with its frame.
	begin_frame_elements()
	warm := calculator.build(ui2.rect(0, 0, window_width, window_height))!
	free_tree(warm)
	mut warmed_slots := 0
	for bucket in 0 .. frame_element_pool_buckets {
		warmed_slots += frame_element_pool.slots[bucket].len
	}
	for _ in 0 .. 100 {
		begin_frame_elements()
		frame := calculator.build(ui2.rect(0, 0, window_width, window_height))!
		free_tree(frame)
	}
	mut final_slots := 0
	for bucket in 0 .. frame_element_pool_buckets {
		final_slots += frame_element_pool.slots[bucket].len
	}
	assert final_slots == warmed_slots
}

fn test_terminal_sends_every_keystroke_through_the_pty_master() {
	mut input_pipe := [2]i32{}
	assert C.pipe(&input_pipe[0]) == 0
	mut terminal := TerminalApp{
		terminal: int(input_pipe[1])
	}

	// There is no private prompt state or local line buffering: type-ahead and
	// control characters belong to the tty line discipline. Backspace is
	// normalized to the default VERASE byte.
	terminal.key_input('ab\b\n\x03')
	mut sent := []u8{len: 8}
	count := C.read(input_pipe[0], sent.data, sent.len)
	assert count == 5
	assert sent[..count] == [u8(`a`), `b`, 0x7f, `\n`, 0x03]
	assert terminal.lines.len == 0

	C.close(input_pipe[0])
	C.close(input_pipe[1])
}

fn test_terminal_renders_pty_echo_and_carriage_return_updates() {
	mut terminal := TerminalApp{}
	terminal.ingest_output('progress 10%\rprogress 20%\r\n\$ '.bytes())
	assert terminal.lines == ['progress 20%']
	assert terminal.partial.bytestr() == '\$ '
	assert terminal.partial_text == '\$ _'

	// Canonical erase echo is backspace-space-backspace. Interpret it as cursor
	// movement and overwrite, just as a terminal display does.
	terminal.ingest_output('abc\b \bD'.bytes())
	assert terminal.partial.bytestr() == '\$ abD'

	// BusyBox's line editor emits clear-to-end under TERM=linux, and an
	// escape sequence may straddle two non-blocking reads.
	terminal.ingest_output('\x1b['.bytes())
	terminal.ingest_output('J'.bytes())
	assert terminal.partial.bytestr() == '\$ abD'
}

fn test_available_utility_applications_and_shortcut_layouts() {
	assert available_apps.len == 14
	assert available_apps[0].process_name == 'vinix-files'
	assert available_apps[1].title == 'Firefox'
	assert available_apps[1].exclusive_command == ''
	assert available_apps[1].process_name == 'vinix-firefox'
	assert available_apps[1].width == firefox_window_width
	assert available_apps[1].height == firefox_window_height + default_title_height
	assert available_apps[1].polling && available_apps[1].poll_interval_ms == 50
	assert available_apps[1].keyboard && available_apps[1].pointer
	assert available_apps[3].process_name == 'vinix-terminal'
	assert available_apps[3].keyboard && available_apps[3].polling
	assert available_apps[5].title == 'Activity Monitor'
	assert available_apps[5].process_name == 'vinix-activity'
	assert available_apps[9].process_name == 'vinix-cocoa-calculator'
	assert available_apps[10].title == 'Minecraft'
	assert available_apps[10].process_name == 'vinix-minecraft'
	assert available_apps[10].exclusive_command == ''
	assert available_apps[10].keyboard && available_apps[10].polling
	assert available_apps[10].pointer
	assert available_apps[11].title == 'Wine Calculator'
	assert available_apps[11].process_name == 'vinix-wine-calculator'
	assert available_apps[11].keyboard && available_apps[11].polling
	assert available_apps[11].pointer
	assert available_apps[12].title == 'Wine Notepad'
	assert available_apps[12].process_name == 'vinix-wine-notepad'
	assert available_apps[12].keyboard && available_apps[12].polling
	assert available_apps[12].pointer
	assert available_apps[13].title == 'Microsoft Word 2013'
	assert available_apps[13].process_name == 'vinix-wine-word2013'
	assert available_apps[13].keyboard && available_apps[13].polling
	assert available_apps[13].pointer
	assert app_start_actions.len == available_apps.len
	assert app_shortcut_actions.len == available_apps.len
	assert shortcut_rows_for_height(720) == 8
	assert shortcut_rows_for_height(600) == 6
}

fn test_pointer_wire_records_have_fixed_cross_compiler_layouts() {
	// The kernel is built with the established compiler while the desktop uses
	// v3, whose `int` has a different width. These records cross into kernel and
	// C code and must therefore retain their explicit ABI sizes.
	assert sizeof(PointerPacket) == 32
	assert sizeof(WineHostEvent) == 20
}

fn test_xwd_bilinear_filter_preserves_edges_and_blends_the_middle() {
	assert xwd_bilinear_color(0x123456, 0xffffff, 0xffffff, 0xffffff, 0, 0) == 0x123456
	assert xwd_bilinear_color(0x000000, 0xffffff, 0xffffff, 0xffffff, 128, 0) == 0x808080
	assert xwd_bilinear_color(0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 128, 128) == 0x808080
}

fn test_office_xwd_repairs_only_transparent_ui_pixels() {
	assert office2013_is_artifact_pixel(0x000000)
	assert office2013_is_artifact_pixel(0x3c3c3c)
	assert office2013_is_artifact_pixel(0x2d2d2d)
	assert !office2013_is_artifact_pixel(0x3d3d3d)
	assert !office2013_is_artifact_pixel(0x003c3c)
	assert office2013_has_transparent_backing(140, 35)
	assert office2013_presented_color(0x000000, 122, 26) == 0xffffff
	assert office2013_presented_color(0x2d2d2d, 140, 35) == 0xffffff
	assert office2013_presented_color(0x161616, 140, 35) == 0xffffff
	assert office2013_presented_color(0x3c3c3c, 140, 35) == 0xffffff
	assert office2013_presented_color(0x16406a, 140, 35) == 0xffffff
	assert office2013_presented_color(0x000000, 100, 35) == 0x000000
	assert office2013_presented_color(0x000000, 100, 62) == 0xffffff
	assert office2013_presented_color(0x000000, 100, 70) == 0x000000
	assert office2013_presented_color(0x000000, 160, 70) == 0xffffff
	assert office2013_presented_color(0x000000, 500, 70) == 0x000000
	assert office2013_presented_color(0x000000, 567, 70) == 0xffffff
	assert office2013_presented_color(0x000000, 600, 56) == 0xffffff
	assert office2013_presented_color(0x000000, 640, 70) == 0xffffff
	assert office2013_presented_color(0x000000, 600, 145) == 0x000000
}

fn test_office_ribbon_repaints_every_damaged_tab_with_native_text() {
	mut desktop := Desktop{
		canvas: new_canvas(wine_word2013_surface_width, wine_word2013_surface_height)
		fonts: load_fonts()
	}
	desktop.canvas.fill_rect(0, 0, desktop.canvas.width, desktop.canvas.height, 0xffffff)
	desktop.draw_office2013_tab_labels(0, 0, desktop.canvas.width, desktop.canvas.height)
	for index, center in office2013_tab_centers {
		left := if index == 0 {
			122
		} else {
			(office2013_tab_centers[index - 1] + center) / 2
		}
		right := if index + 1 == office2013_tab_centers.len {
			660
		} else {
			(center + office2013_tab_centers[index + 1]) / 2
		}
		mut ink := 0
		for y in office2013_tab_top .. office2013_tab_top + office2013_tab_height {
			for x in left .. right {
				if unsafe { desktop.canvas.pixels[y * desktop.canvas.stride + x] } != 0xffffff {
					ink++
				}
			}
		}
		assert ink > 10
	}
	assert unsafe { desktop.canvas.pixels[26 * desktop.canvas.stride + 157] } == 0xffffff
	unsafe { free(voidptr(desktop.canvas.pixels)) }
}

fn test_start_button_opens_a_windows_7_style_menu_and_searches_programs() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 1024
			height: 768
		}
	}

	root := desktop.build_tree()
	start := utility_element_named(root, action_start_toggle) or { panic('missing Start button') }
	assert start.text == ''
	assert start.image_path == 'builtin:vinix'
	assert int(start.frame.x) == taskbar_padding
	assert int(start.frame.width) == start_button_width
	assert !utility_tree_has_text(root, 'New window')
	free_tree(root)

	desktop.toggle_start_menu()
	assert desktop.start_menu_open
	menu := desktop.build_tree()
	panel := utility_element_named(menu, action_start_panel) or { panic('missing Start menu') }
	assert panel.clickable
	assert int(panel.frame.x) == taskbar_padding
	assert int(panel.frame.y + panel.frame.height) == 768 - taskbar_height
	assert utility_tree_has_text(menu, 'All Programs  >')
	assert utility_tree_has_text(menu, 'Shut down')
	free_tree(menu)

	desktop.handle_start_action(action_start_all)
	assert desktop.start_menu_all_apps
	all_programs := desktop.build_tree()
	assert utility_tree_has_text(all_programs, '<  Back')
	assert utility_tree_has_text(all_programs, 'Microsoft Word 2013')
	free_tree(all_programs)

	desktop.start_menu_key_input('note')
	assert desktop.start_menu_query.bytestr() == 'note'
	assert !desktop.start_menu_all_apps
	results := desktop.build_tree()
	programs := utility_element_named(results, 'start.programs') or {
		panic('missing Start program pane')
	}
	assert utility_tree_has_text(programs, 'Wine Notepad')
	assert !utility_tree_has_text(programs, 'Calculator')
	free_tree(results)

	desktop.start_menu_key_input('\x7f')
	assert desktop.start_menu_query.bytestr() == 'not'
	desktop.start_menu_key_input('\x1b')
	assert !desktop.start_menu_open
	assert desktop.start_menu_query.len == 0
	assert start_menu_matches('Activity Monitor', 'MON')
	assert !start_menu_matches('Terminal', 'file')
}

fn test_start_menu_system_link_opens_system_window() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 1024
			height: 768
		}
	}
	desktop.toggle_start_menu()
	desktop.handle_start_action(action_start_system)
	assert !desktop.start_menu_open
	assert desktop.windows.len == 1
	assert desktop.windows[0].title == 'System'
	assert desktop.windows[0].page == .system
}

fn test_taskbar_keeps_a_bottom_right_clock_and_open_windows() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 1280
			height: 720
		}
	}
	desktop.spawn('One', .welcome, 10, 10, 300, 200)
	desktop.spawn('Two', .system, 20, 20, 300, 200)
	desktop.update_taskbar_clock_at(0)

	root := desktop.build_tree()
	taskbar := utility_element_named(root, 'taskbar') or { panic('missing taskbar') }
	assert taskbar.children.len == 6
	assert utility_element_named(taskbar, action_start_toggle) != none
	assert utility_element_named(taskbar, 'task.1') != none
	assert utility_element_named(taskbar, 'task.2') != none
	clock_time := utility_element_named(taskbar, 'clock.time') or { panic('missing taskbar clock') }
	clock_date := utility_element_named(taskbar, 'clock.date') or { panic('missing taskbar date') }
	assert clock_time.text == '00:00:00'
	assert clock_date.text == 'Thu 1 Jan'
	assert int(clock_time.frame.x + clock_time.frame.width) == 1280 - taskbar_padding
	free_tree(root)

	desktop.close_window(2)
	desktop.close_window(1)
	empty := desktop.build_tree()
	empty_taskbar := utility_element_named(empty, 'taskbar') or { panic('missing empty taskbar') }
	assert empty_taskbar.children.len == 4
	assert utility_element_named(empty_taskbar, action_start_toggle) != none
	assert utility_element_named(empty_taskbar, 'clock.time') != none
	free_tree(empty)
}

fn test_clicking_a_taskbar_window_button_focuses_without_minimizing() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 800
			height: 600
		}
	}
	first := desktop.spawn('One', .welcome, 10, 10, 300, 200)
	second := desktop.spawn('Two', .system, 20, 20, 300, 200)
	assert desktop.focus == second
	desktop.targets << HitTarget{
		action_id: 'task.${first}'
		x: 60
		y: 560
		width: 150
		height: 30
	}

	desktop.on_pointer_down(80, 575)
	assert desktop.focus == first
	assert desktop.windows.last().id == first
	assert !desktop.windows.last().minimized

	// Re-clicking the selected taskbar button keeps the window focused instead
	// of hiding it; minimize remains an explicit title-bar action.
	desktop.on_pointer_down(80, 575)
	assert desktop.focus == first
	assert !desktop.windows.last().minimized
}

fn test_taskbar_clock_stays_visible_at_m1_200_percent_scale() {
	// The 3024×1964 M1 framebuffer becomes a 1512×982 logical desktop. The
	// taskbar reserves a logical status area before allocating task buttons,
	// which maps back to the physical lower-right corner during presentation.
	mut desktop := Desktop{
		canvas: Canvas{
			width: desktop_scaled_extent(3024, desktop_scale_200)
			height: desktop_scaled_extent(1964, desktop_scale_200)
		}
	}
	desktop.update_taskbar_clock_at(0)
	root := desktop.build_tree()
	taskbar := utility_element_named(root, 'taskbar') or { panic('missing taskbar') }
	clock := utility_element_named(taskbar, 'clock.time') or { panic('missing taskbar clock') }
	assert int(clock.frame.x + clock.frame.width) == desktop.canvas.width - taskbar_padding
	assert int(clock.frame.x + clock.frame.width) * desktop_scale_200 == 3024 - 2 * taskbar_padding
	assert int(taskbar.frame.y) * desktop_scale_200 == 1964 - 2 * taskbar_height
	free_tree(root)
}

fn test_firefox_uses_the_hosted_x11_window_path() {
	factory := available_apps[1]
	assert factory.process_name == 'vinix-firefox'
	assert factory.exclusive_command == ''
	assert factory.open != unsafe { nil }
	assert factory.polling && factory.keyboard && factory.pointer
}

fn test_clicking_a_hosted_surface_raises_and_focuses_its_vinix_window() {
	mut desktop := Desktop{
		canvas: Canvas{
			width: 800
			height: 600
		}
	}
	desktop.apps << PointerFocusTestApp{}
	hosted_id := desktop.spawn('Hosted', .app, 20, 20, 300, 220)
	desktop.windows[0].app_index = 0
	desktop.spawn('Other', .welcome, 400, 40, 300, 220)
	assert desktop.focus != hosted_id

	desktop.on_pointer_down(80, 100)
	assert desktop.focus == hosted_id
	assert desktop.windows.last().id == hosted_id
	assert desktop.pointer_capture == hosted_id

	desktop.on_pointer_up(80, 100)
	assert desktop.pointer_capture == 0
}

fn test_external_display_handoff_redraws_and_reports_failures() {
	mut desktop := Desktop{
		canvas: new_canvas(800, 600)
	}
	desktop.wallpaper_valid = true
	desktop.external_finished(.success)
	assert desktop.dirty
	assert !desktop.wallpaper_valid
	assert desktop.windows.len == 0

	desktop.external_finished(.unavailable)
	assert desktop.windows.len == 1
	assert desktop.windows[0].title == 'External application'
	assert desktop.windows[0].page == .external_error
	assert desktop.external_error.contains('not installed')
	assert desktop.external_error_title == 'External application could not start'

	unsafe { free(voidptr(desktop.canvas.pixels)) }
}

fn test_activity_monitor_uses_only_real_process_rows() {
	mut app := ActivityApp{}
	tree := app.build(ui2.rect(0, 0, 520, 360))!
	assert utility_tree_has_text(tree, 'MB')
	free_tree(tree)
	app.monitor.free_rows()
}

fn test_native_process_names_are_presented_as_app_names() {
	mut sample := ActivitySample{}
	name := '/usr/bin/vinix-activity[42]'
	for index := 0; index < name.len; index++ {
		sample.name[index] = name[index]
	}
	display := activity_name_of(&sample)
	assert display == 'Activity Monitor'
	unsafe { display.free() }
}

fn test_application_tree_protocol_round_trip() {
	child := ui2.button_with_image('save', 'Save', 'builtin:editor', ui2.rect(7, 9, 80, 24), ui2.BoxStyle{
		bg: 0x123456
		radius: 6
	}, ui2.TextStyle{
		color: 0xfefefe
		background_color: 0x010203
		size: 13
		font_family: 'mono'
		bold: true
		shadow: true
		align: .center
	})
	root := ui2.screen(0xabcdef, [child])
	mut encoded := []u8{}
	encode_app_element(root, mut encoded)!
	decoded := decode_app_tree(encoded)!
	assert decoded.box.bg == 0xabcdef
	assert decoded.children.len == 1
	button := decoded.children[0]
	assert button.kind == .button
	assert button.id == 'save'
	assert button.text == 'Save'
	assert button.image_path == 'builtin:editor'
	assert button.frame.x == 7 && button.frame.y == 9
	assert button.box.bg == 0x123456 && button.box.radius == 6
	assert button.text_style.font_family == 'mono'
	assert button.text_style.bold && button.text_style.shadow
	assert button.text_style.align == .center
	free_tree(root)
	free_tree(decoded)
	unsafe { encoded.free() }
}
