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

fn test_vinix_start_glyph_uses_the_wordmark_v_polygon() {
	// These coordinates are inside the left arm, the open notch and the right
	// arm of the V in vinix-logo.svg. Keeping this assertion on the shared
	// polygon prevents the Start mark from quietly becoming a generic stroked V.
	assert vinix_v_contains(11.0, 12.0)
	assert !vinix_v_contains(26.3, 12.0)
	assert vinix_v_contains(41.0, 12.0)

	mut canvas := new_canvas(48, 48)
	defer {
		unsafe { free(canvas.pixels) }
	}
	canvas.clear(0x000000)
	canvas.draw_vinix_v(0, 0, 48, 48, 0xffffff)
	assert unsafe { canvas.pixels[24 * canvas.stride + 24] } == 0xffffff
}

fn surface_test_put_u32(mut bytes []u8, offset int, value u32) {
	bytes[offset] = u8(value)
	bytes[offset + 1] = u8(value >> 8)
	bytes[offset + 2] = u8(value >> 16)
	bytes[offset + 3] = u8(value >> 24)
}

fn test_native_vinix_surface_validates_claims_and_draws_active_buffer() {
	path := os.join_path(os.temp_dir(), 'vinix-native-surface-test.bin')
	defer { os.rm(path) or {} }
	// A two-by-one surface has eight bytes in each pixel plane.
	mut bytes := []u8{len: 48 + 16, init: 0}
	surface_test_put_u32(mut bytes, 0, vinix_surface_magic)
	surface_test_put_u32(mut bytes, 4, vinix_surface_version)
	surface_test_put_u32(mut bytes, 8, u32(vinix_surface_header_size))
	surface_test_put_u32(mut bytes, 12, 2)
	surface_test_put_u32(mut bytes, 16, 1)
	surface_test_put_u32(mut bytes, 20, 8)
	surface_test_put_u32(mut bytes, 24, vinix_surface_format_xrgb8888)
	surface_test_put_u32(mut bytes, 28, 1)
	surface_test_put_u32(mut bytes, 32, ~u32(0))
	surface_test_put_u32(mut bytes, 40, 8)
	// Only buffer one is active: red then green in little-endian XRGB8888.
	bytes[56] = 0x00
	bytes[57] = 0x00
	bytes[58] = 0xff
	bytes[60] = 0x00
	bytes[61] = 0xff
	bytes[62] = 0x00
	os.write_file_array(path, bytes) or { assert false }

	surface := open_vinix_surface(path) or {
		assert false
		return
	}
	assert surface.width == 2 && surface.height == 1 && surface.stride == 8
	assert surface.pixel(0, 0) == 0xff0000
	assert surface.pixel(1, 0) == 0x00ff00
	assert vinix_surface_u32(unsafe { &u8(surface.mapping) }, 32) == 1
	surface.close()
	released := os.read_bytes(path) or {
		assert false
		return
	}
	assert vinix_surface_u32(released.data, 32) == ~u32(0)

	mut canvas := new_canvas(2, 1)
	defer {
		unsafe { free(canvas.pixels) }
	}
	canvas.clear(0)
	assert canvas.draw_vinix_surface(path, 0, 0, 2, 1)
	assert unsafe { canvas.pixels[0] } == 0xff0000
	assert unsafe { canvas.pixels[1] } == 0x00ff00
}

struct PointerFocusTestApp {}

fn (mut app PointerFocusTestApp) build(size ui2.Rect) !ui2.Element {
	return ui2.screen(0, [])
}

fn (mut app PointerFocusTestApp) handle(_ string) ! {}

fn (mut app PointerFocusTestApp) pointer_input_enabled() bool {
	return true
}

fn (mut app PointerFocusTestApp) pointer_event(_ AppPointerPhase, _ AppPointerButton, _ int, _ int, _ int, _ int, _ int) {}

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

fn test_capture_png_encoder_writes_standard_truecolour_image() {
	mut canvas := new_canvas(2, 2)
	defer {
		unsafe { free(canvas.pixels) }
	}
	unsafe {
		canvas.pixels[0] = 0xff0000
		canvas.pixels[1] = 0x00ff00
		canvas.pixels[2] = 0x0000ff
		canvas.pixels[3] = 0xffffff
	}
	bytes := capture_png_bytes(&canvas)!
	defer {
		unsafe { bytes.free() }
	}
	assert bytes[..8] == [u8(0x89), `P`, `N`, `G`, `\r`, `\n`, 0x1a, `\n`]
	assert bytes[12..16].bytestr() == 'IHDR'
	assert bytes[16..20] == [u8(0), 0, 0, 2]
	assert bytes[20..24] == [u8(0), 0, 0, 2]
	assert bytes[24] == 8
	assert bytes[25] == 2
	assert bytes[bytes.len - 8..bytes.len - 4].bytestr() == 'IEND'
}

fn test_capture_avi_writer_indexes_every_video_frame() {
	path := os.join_path(os.temp_dir(), 'vinix-capture-test.avi')
	defer {
		os.rm(path) or {}
	}
	mut canvas := new_canvas(4, 2)
	defer {
		unsafe { free(canvas.pixels) }
	}
	canvas.clear(0x3264c8)
	mut writer := capture_open_avi(path, &canvas, 10)!
	total_offset := writer.total_frames_offset
	stream_offset := writer.stream_length_offset
	assert writer.add_frame(&canvas)
	canvas.clear(0xc86432)
	assert writer.add_frame(&canvas)
	assert writer.frames == 2
	assert writer.finish()
	bytes := os.read_bytes(path)!
	defer {
		unsafe { bytes.free() }
	}
	assert bytes[..4].bytestr() == 'RIFF'
	assert bytes[8..12].bytestr() == 'AVI '
	assert bytes[total_offset..total_offset + 4] == [u8(2), 0, 0, 0]
	assert bytes[stream_offset..stream_offset + 4] == [u8(2), 0, 0, 0]
	assert bytes[bytes.len - 40..bytes.len - 36].bytestr() == 'idx1'
}

fn test_capture_ui_issues_compositor_requests() {
	mut desktop := Desktop{}
	mut app := CaptureApp{
		desktop: &desktop
	}
	app.handle(capture_action_delay_5)!
	app.handle(capture_action_take_screenshot)!
	assert desktop.capture.request.command == .screenshot
	assert desktop.capture.request.delay == 5
	assert desktop.capture.request.sequence == 1
	app.handle(capture_action_video_tab)!
	app.handle(capture_action_fps_5)!
	app.handle(capture_action_start_video)!
	assert app.page == .video
	assert desktop.capture.request.command == .start_video
	assert desktop.capture.request.fps == 5
	assert desktop.capture.request.sequence == 2
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 560, 396))!
	assert utility_tree_has_text(tree, 'Record the desktop')
	assert utility_tree_has_text(tree, 'Smooth  10 fps')
	free_tree(tree)
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

fn test_terminal_starts_zsh_by_default() {
	assert terminal_shell == '/bin/zsh'
}

fn test_terminal_renders_pty_echo_and_carriage_return_updates() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(4, 40)
	terminal.ingest_output('progress 10%\rprogress 20%\r\n\$ '.bytes())
	assert terminal.row_string(0) == 'progress 20%'
	assert terminal.row_string(1) == '\$ '
	assert terminal.rendered_row(1) == '\$ _'

	// Canonical erase echo is backspace-space-backspace. Interpret it as cursor
	// movement and overwrite, just as a terminal display does.
	terminal.ingest_output('abc\b \bD'.bytes())
	assert terminal.row_string(1) == '\$ abD'

	// BusyBox's line editor emits clear-to-end under TERM=linux, and an
	// escape sequence may straddle two non-blocking reads.
	terminal.ingest_output('\x1b['.bytes())
	terminal.ingest_output('J'.bytes())
	assert terminal.row_string(1) == '\$ abD'
}

fn test_terminal_handles_vim_alternate_screen_and_cursor_addressing() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(6, 30)
	terminal.ingest_output('vinix# vim notes.txt'.bytes())

	// This is the core of a TERM=linux Vim redraw: enter the alternate screen,
	// erase it, position rows independently, set a scroll region, and finally
	// leave the alternate screen. Split one CSI sequence at a read boundary too.
	terminal.ingest_output('\x1b[?1049h\x1b[2J\x1b[Hhello\x1b[2;1Hworld'.bytes())
	terminal.ingest_output('\x1b[3;'.bytes())
	terminal.ingest_output('1H~\x1b[6;1H"notes.txt" 2L, 12B\x1b[1;6H'.bytes())
	assert terminal.alternate_screen
	assert terminal.row_string(0) == 'hello'
	assert terminal.row_string(1) == 'world'
	assert terminal.row_string(2) == '~'
	assert terminal.row_string(5) == '"notes.txt" 2L, 12B'
	assert terminal.cursor_row == 0
	assert terminal.cursor_column == 5

	// Vim uses line/character edits for economical redraws instead of repainting
	// the entire file after every keystroke.
	terminal.ingest_output('\x1b[2;1H\x1b[2@OK\x1b[1P\x1b[3X'.bytes())
	assert terminal.row_string(1) == 'OK   d'
	terminal.ingest_output('\x1b[2;5r\x1b[2;1H\x1b[Linserted'.bytes())
	assert terminal.row_string(1) == 'inserted'
	assert terminal.row_string(2) == 'OK   d'

	terminal.ingest_output('\x1b[?1049l'.bytes())
	assert !terminal.alternate_screen
	assert terminal.row_string(0) == 'vinix# vim notes.txt'
}

fn test_terminal_answers_cursor_status_queries() {
	mut replies := [2]i32{}
	assert C.pipe(&replies[0]) == 0
	mut terminal := TerminalApp{
		terminal: int(replies[1])
	}
	terminal.set_geometry(5, 20)
	// Linux cursor-shape controls end in `c` too, but are not device-attribute
	// queries and must not inject replies into Vim's keyboard input.
	terminal.ingest_output('\x1b[?1c\x1b[?8c\x1b[4;7H\x1b[6n'.bytes())
	mut answer := [32]u8{}
	count := C.read(replies[0], &answer[0], answer.len)
	assert count == 6
	assert unsafe { tos(&answer[0], count) } == '\x1b[4;7R'
	C.close(replies[0])
	C.close(replies[1])
}

fn test_terminal_consumes_linux_palette_controls_without_swallowing_text() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(2, 20)
	// Linux's OSC P and OSC R controls deliberately have no BEL/ST terminator.
	terminal.ingest_output('\x1b]P1ffffffX\x1b]RY'.bytes())
	assert terminal.row_string(0) == 'XY'
}

fn terminal_screen_contains(terminal &TerminalApp, wanted string) bool {
	for row in 0 .. terminal.rows {
		if terminal.row_string(row).contains(wanted) {
			return true
		}
	}
	return false
}

fn test_terminal_can_edit_a_file_with_vim_over_its_real_pty() {
	vim_path := '/usr/bin/vim'
	if !os.exists(vim_path) {
		return
	}
	path := os.join_path(os.temp_dir(), 'vinix-terminal-vim-test.txt')
	os.rm(path) or {}
	defer { os.rm(path) or {} }

	mut terminal := TerminalApp{
		read_buf: []u8{len: terminal_read_chunk}
	}
	terminal.set_geometry(12, 60)
	terminal.start_shell(12, 60, 480, 192)
	assert terminal.terminal >= 0
	defer { terminal.close_app() }
	terminal.key_input('${vim_path} -Nu NONE -n -i NONE ${path}\n')
	for _ in 0 .. 200 {
		terminal.poll()
		if terminal_screen_contains(&terminal, '[New]') {
			break
		}
		desktop_sleep_ms(10)
	}
	assert terminal_screen_contains(&terminal, '[New]')

	terminal.key_input('iEdited inside Vinix\x1b:wq\n')
	for _ in 0 .. 300 {
		terminal.poll()
		if os.exists(path) {
			break
		}
		desktop_sleep_ms(10)
	}
	assert os.read_file(path)! == 'Edited inside Vinix\n'
}

fn test_available_utility_applications_and_shortcut_layouts() {
	assert available_apps.len == 18
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
	assert available_apps[14].title == 'Blender'
	assert available_apps[14].process_name == 'vinix-blender'
	assert available_apps[14].width == blender_window_width
	assert available_apps[14].height == blender_window_height + default_title_height
	assert available_apps[15].title == capture_app_title
	assert available_apps[15].process_name == 'vinix-capture'
	assert available_apps[15].icon == 'builtin:camera'
	assert available_apps[15].polling
	assert available_apps[14].keyboard && available_apps[14].polling
	assert available_apps[14].pointer
	assert available_apps[16].title == 'GIMP'
	assert available_apps[16].process_name == 'vinix-gimp'
	assert available_apps[16].width == gimp_window_width
	assert available_apps[16].height == gimp_window_height + default_title_height
	assert available_apps[16].keyboard && available_apps[16].pointer
	assert available_apps[16].polling && available_apps[16].poll_interval_ms == 50
	assert available_apps[17].title == 'VSpace'
	assert available_apps[17].process_name == 'vinix-vspace'
	assert available_apps[17].icon == 'builtin:disk'
	assert available_apps[17].polling && available_apps[17].poll_interval_ms == 33
	assert !available_apps[17].keyboard && !available_apps[17].pointer
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
	assert sizeof(AppPointerPayload) == 28
	assert sizeof(WineHostEvent) == 20
	assert sizeof(VinixInputEvent) == 24
}

fn test_native_surface_input_preserves_buttons_and_scroll() {
	mut input_pipe := [2]i32{}
	assert C.pipe(&input_pipe[0]) == 0
	mut app := NativeSurfaceApp{
		input_fd: int(input_pipe[1])
		surface_width: 100
		surface_height: 50
		ready: true
	}

	app.pointer_event(.down, .right, 0, 100, 100, 200, 200)
	app.pointer_event(.scroll, .no_button, -2, 100, 100, 200, 200)
	mut records := [2]VinixInputEvent{}
	assert C.read(input_pipe[0], &records[0], sizeof(VinixInputEvent) * 2) == sizeof(VinixInputEvent) * 2
	assert records[0].kind == u32(VinixInputEventKind.button_down)
	assert records[0].value == int(AppPointerButton.right)
	assert records[0].x == 50 && records[0].y == 25
	assert records[1].kind == u32(VinixInputEventKind.wheel)
	assert records[1].value == -2

	C.close(input_pipe[0])
	C.close(input_pipe[1])
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

fn test_gimp_uses_the_hosted_x11_window_path() {
	factory := available_apps[16]
	assert factory.process_name == 'vinix-gimp'
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

// ── VSpace ─────────────────────────────────────────────────────────

fn vspace_test_tree() string {
	root := os.join_path(os.temp_dir(), 'vinix-vspace-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'big', 'nested')) or { panic(err) }
	os.mkdir_all(os.join_path(root, 'small')) or { panic(err) }
	os.write_file(os.join_path(root, 'big', 'a.bin'), 'a'.repeat(4096)) or { panic(err) }
	os.write_file(os.join_path(root, 'big', 'nested', 'b.bin'), 'b'.repeat(2048)) or { panic(err) }
	original := os.join_path(root, 'small', 'c.bin')
	os.write_file(original, 'c'.repeat(512)) or { panic(err) }
	// The same 512 bytes under a second name, and a directory that is only a
	// name. Counting either one would overstate the tree.
	os.link(original, os.join_path(root, 'small', 'c-link.bin')) or { panic(err) }
	os.symlink(os.join_path(root, 'big'), os.join_path(root, 'big-link')) or { panic(err) }
	return root
}

fn vspace_scan_to_completion(mut app VSpaceApp, root string) {
	app.scan(root)
	for step := 0; app.scanner.phase == .scanning && step < 1000; step++ {
		assert app.poll()
	}
	assert app.scanner.phase == .complete
}

fn test_vspace_walk_counts_a_real_tree_once() {
	root := vspace_test_tree()
	defer {
		os.rmdir_all(root) or {}
	}
	mut app := VSpaceApp{}
	defer {
		app.close_app()
	}
	vspace_scan_to_completion(mut app, root)

	// Three regular files: the hard link is the same bytes under a second name
	// and the symbolic link is followed by nothing.
	assert app.scanner.files == 3
	assert app.scanner.total_bytes == 4096 + 2048 + 512
	assert app.scanner.directories == 4
	assert app.scanner.unreadable == 0

	// A folder's total is its whole subtree, so `big` outranks the nested
	// directory whose bytes it also contains.
	dirs := app.scanner.dirs_rank.entries
	assert dirs.len == 3
	assert dirs[0].name == 'big'
	assert dirs[0].bytes == 4096 + 2048
	assert dirs[1].name == 'nested'
	assert dirs[1].bytes == 2048
	assert dirs[2].name == 'small'
	assert dirs[2].bytes == 512

	files := app.scanner.files_rank.entries
	assert files.len == 3
	assert files[0].name == 'a.bin'
	assert files[0].bytes == 4096
	assert files[1].name == 'b.bin'
	assert files[1].bytes == 2048
	// Whichever of the two names readdir reported first is the one that was
	// counted; the other was recognised as the same inode and skipped.
	assert files[2].bytes == 512
	assert files[2].name in ['c.bin', 'c-link.bin']
}

fn test_vspace_scan_is_resumable_and_can_be_stopped() {
	root := vspace_test_tree()
	defer {
		os.rmdir_all(root) or {}
	}
	mut app := VSpaceApp{}
	defer {
		app.close_app()
	}
	app.scan(root)
	assert app.scanner.phase == .scanning
	// A scan in progress is a stack of open directories, and stopping is what
	// closes them without throwing away what has been counted.
	assert app.scanner.stack.len > 0
	app.scanner.cancel()
	assert app.scanner.phase == .cancelled
	assert app.scanner.stack.len == 0
	// Nothing polls a stopped scan forward.
	assert !app.poll()

	vspace_scan_to_completion(mut app, root)
	assert !app.poll()
	assert app.scanner.files == 3
}

fn test_vspace_reports_an_unreadable_root_instead_of_failing() {
	mut app := VSpaceApp{}
	defer {
		app.close_app()
	}
	app.scan('/vinix-vspace-does-not-exist')
	assert app.scanner.phase == .failed
	assert app.scanner.error == 'cannot open /vinix-vspace-does-not-exist'
	tree := app.build(ui2.rect(0, 0, 880, 546)) or { panic(err) }
	assert utility_tree_has_text(tree, 'UNREADABLE')
	assert utility_tree_has_text(tree, 'cannot open /vinix-vspace-does-not-exist')
}

fn test_vspace_window_ranks_folders_and_descends_into_one() {
	root := vspace_test_tree()
	defer {
		os.rmdir_all(root) or {}
	}
	mut app := VSpaceApp{}
	defer {
		app.close_app()
	}
	vspace_scan_to_completion(mut app, root)

	tree := app.build(ui2.rect(0, 0, 880, 546)) or { panic(err) }
	assert utility_tree_has_text(tree, 'VSpace')
	assert utility_tree_has_text(tree, 'Largest folders')
	assert utility_tree_has_text(tree, 'Largest files')
	assert utility_tree_has_text(tree, 'COMPLETE')
	assert utility_tree_has_text(tree, '6.50 KB')
	assert utility_tree_has_text(tree, 'a.bin')
	// A completed scan's folder rows are what a pointer descends with; a
	// running one's are not, because the ranking moves underneath the click.
	assert utility_element_named(tree, 'vspace.dir.0') != none

	app.handle('vspace.dir.0') or { panic(err) }
	assert app.scanner.root == os.join_path(root, 'big')
	vspace_scan_to_completion(mut app, os.join_path(root, 'big'))
	assert app.scanner.files == 2
	assert app.scanner.total_bytes == 4096 + 2048

	app.handle('vspace.up') or { panic(err) }
	assert app.scanner.root == root
}

fn test_vspace_formats_sizes_counts_and_durations() {
	// The standalone program's formatter, to the digit.
	assert vspace_size_text(0) == '0 B'
	assert vspace_size_text(1023) == '1023 B'
	assert vspace_size_text(1024) == '1.00 KB'
	assert vspace_size_text(1536) == '1.50 KB'
	assert vspace_size_text(10 * 1024) == '10.0 KB'
	assert vspace_size_text(100 * 1024) == '100 KB'
	assert vspace_size_text(1024 * 1024) == '1.00 MB'
	assert vspace_size_text(u64(3) * 1024 * 1024 * 1024) == '3.00 GB'

	assert vspace_count_text(0) == '0'
	assert vspace_count_text(999) == '999'
	assert vspace_count_text(1000) == '1,000'
	assert vspace_count_text(1234567) == '1,234,567'

	assert vspace_duration_text(940) == '940 ms'
	assert vspace_duration_text(1500) == '1.5 sec'
	assert vspace_duration_text(65000) == '1 min 5 sec'
}

fn test_vspace_ranking_keeps_only_the_largest_entries() {
	mut ranking := VSpaceRanking{}
	defer {
		ranking.release()
	}
	// More candidates than the ranking holds, offered smallest first so every
	// one of them has to displace the floor to get in.
	for index in 0 .. vspace_rank_limit * 2 {
		ranking.consider('name'.clone(), 'path'.clone(), u64(index + 1))
	}
	assert ranking.entries.len == vspace_rank_limit
	assert ranking.entries[0].bytes == u64(vspace_rank_limit * 2)
	assert ranking.entries[vspace_rank_limit - 1].bytes == u64(vspace_rank_limit + 1)
	assert ranking.floor == u64(vspace_rank_limit + 1)
	// Anything at or below the floor is rejected without disturbing the order.
	ranking.consider('name'.clone(), 'path'.clone(), 1)
	assert ranking.entries[vspace_rank_limit - 1].bytes == u64(vspace_rank_limit + 1)
}

fn test_vspace_identity_set_answers_each_device_and_inode_once() {
	mut seen := VSpaceIdentitySet{}
	defer {
		seen.release()
	}
	seen.reset()
	assert seen.add(vspace_identity_key(1, 2))
	assert !seen.add(vspace_identity_key(1, 2))
	assert seen.add(vspace_identity_key(2, 2))
	// Past its load factor the table rehashes, and every key it already held
	// has to still be in it afterwards.
	for inode in 0 .. u64(vspace_identity_slots * 2) {
		seen.add(vspace_identity_key(9, inode))
	}
	assert !seen.add(vspace_identity_key(1, 2))
	assert !seen.add(vspace_identity_key(2, 2))
	for inode in 0 .. u64(vspace_identity_slots * 2) {
		assert !seen.add(vspace_identity_key(9, inode))
	}
}
