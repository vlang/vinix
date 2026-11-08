// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

struct ClientFrameTestApp {
mut:
	last_pointer AppPointerPayload
}

fn (mut a ClientFrameTestApp) build(size ui2.Rect) !ui2.Element {
	return ui2.view('test-client', size, ui2.BoxStyle{ bg: 0xffffff }, [])
}

fn (mut a ClientFrameTestApp) handle(_ string) ! {}

fn (a &ClientFrameTestApp) pointer_input_enabled() bool { return true }

fn (mut a ClientFrameTestApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	a.last_pointer = AppPointerPayload{ x: x, y: y, width: width, height: height }
}

fn client_frame_test_desktop() Desktop {
	mut d := Desktop{ canvas: Canvas{ width: 800, height: 600 } }
	d.apps << &ClientFrameTestApp{}
	d.spawn('Client', .app, 100, 80, 400, 260)
	d.windows[0].app_index = 0
	d.windows[0].client_frame = true
	return d
}

fn test_client_frame_hello_is_opt_in_and_legacy_safe() {
	assert !app_hello_client_frame([]u8{})
	assert !app_hello_client_frame(app_hello())
	mut hello := [u8(`V`), `E`, `X`, `T`]
	wire_put_u32(mut hello, app_extended_client_frame)
	wire_put_u32(mut hello, 1)
	assert app_hello_client_frame(hello)
	assert !app_hello_client_frame(hello[..11])
	hello[8] = 0
	assert !app_hello_client_frame(hello)
	hello[8] = 3
	assert !app_hello_client_frame(hello)
	hello[8] = 1
	hello[0] = 0
	assert !app_hello_client_frame(hello)
}

fn test_client_frame_fills_window_under_every_theme_and_recovers_standard_controls() {
	mut d := client_frame_test_desktop()
	for theme in [ThemeKind.default_, .macos, .windows7, .windows_xp] {
		d.settings.theme = theme
		assert d.window_border(&d.windows[0]) == 0
		assert d.window_title_height(&d.windows[0]) == 0
		frame := d.window_element(0)
		assert frame.box.transparent
		assert frame.children.len == 9
		assert frame.children[0].frame == ui2.rect(0, 0, 400, 260)
		for child in frame.children {
			assert child.id != d.windows[0].id_titlebar
		}
		free_tree(frame)
	}
	d.windows[0].recovery = true
	assert d.window_title_height(&d.windows[0]) == d.theme().title_height
	assert d.window_border(&d.windows[0]) == d.theme().frame_border
	frame := d.window_element(0)
	assert !frame.box.transparent
	free_tree(frame)
}

fn test_client_frame_raw_pointer_uses_the_entire_client_area() {
	mut d := client_frame_test_desktop()
	assert d.forward_pointer_to_window(105, 85, .down, .left, 0) == 0
	mut app := d.apps[0]
	if mut app is ClientFrameTestApp {
		assert app.last_pointer.x == 5 && app.last_pointer.y == 5
		assert app.last_pointer.width == 400 && app.last_pointer.height == 260
	} else {
		assert false
	}
}

fn test_client_controls_are_scoped_and_keep_move_maximize_and_minimize_working() {
	mut d := client_frame_test_desktop()
	id := d.windows[0].id
	assert !d.handle_client_window_action('win.999.close', 120, 90)
	assert !d.handle_client_window_action('ui2.window.close', 0, 0)
	assert d.handle_client_window_action('ui2.window.move', 120, 90)
	assert d.drag.kind == .move && d.drag.window_id == id
	assert d.drag.offset_x == 20 && d.drag.offset_y == 10
	assert d.chrome_pointer_capture
	d.drag = Drag{}
	assert d.handle_client_window_action('ui2.window.maximize', 120, 90)
	assert d.windows[0].maximized
	assert d.window_title_height(&d.windows[0]) == 0
	assert d.handle_client_window_action('ui2.window.maximize', 120, 90)
	assert !d.windows[0].maximized && d.windows[0].width == 400
	assert d.handle_client_window_action('ui2.window.minimize', 120, 90)
	assert d.windows[0].minimized
	d.windows[0].minimized = false
	d.windows[0].client_frame = false
	assert !d.handle_client_window_action('ui2.window.close', 120, 90)
	assert d.windows.len == 1
	d.windows[0].client_frame = true
	assert d.handle_client_window_action('ui2.window.close', 120, 90)
	assert d.windows.len == 0
}
