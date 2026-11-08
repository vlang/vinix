// SPDX-License-Identifier: MIT
module sapp

import ui2

pub struct TouchPoint {}

pub struct IconDesc {}

pub struct Desc {
pub mut:
	width  int
	height int
}

pub struct Event {
pub mut:
	type               EventType
	frame_count        u64
	key_code           KeyCode
	char_code          u32
	key_repeat         bool
	modifiers          u32
	mouse_button       MouseButton
	mouse_x            f32
	mouse_y            f32
	mouse_dx           f32
	mouse_dy           f32
	scroll_x           f32
	scroll_y           f32
	num_touches        int
	touches            [8]TouchPoint
	window_width       int
	window_height      int
	framebuffer_width  int
	framebuffer_height int
}

pub fn isvalid() bool { return false }

pub fn dpi_scale() f32 { return 1 }

pub fn frame_duration() f64 { return 1.0 / 30 }

pub fn set_mouse_cursor(_ MouseCursor) {}

pub fn quit() { ui2.native_quit() }

pub fn request_quit() { ui2.native_quit() }

pub fn x11_get_display() voidptr { return unsafe { nil } }

pub fn x11_get_window() u64 { return 0 }

pub fn get_clipboard_string() string { return '' }

pub fn set_clipboard_string(_ &char) {}

pub fn screenshot_png(_ string) ! { return error('Use the Vinix Capture application') }
