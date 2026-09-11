// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Applications using Vinix's native shared-surface window-system boundary.
module main

import ui2

const blender_surface_width = 1280
const blender_surface_height = 900
const blender_window_width = 1280
const blender_window_height = 900
const blender_native_executable = '/usr/libexec/vinix-blender-native'
const blender_data_directory = '/usr/share/blender/4.3'
const vinix_input_event_magic = u32(0x31494e56) // VNI1 in little-endian memory

enum VinixInputEventKind as u32 {
	motion = 1
	button_down
	button_up
	keys
	wheel
}

struct VinixInputEvent {
	magic u32
	kind  u32
	// The Blender GHOST backend uses fixed-width C fields and asserts this
	// 24-byte record.
	x      i32
	y      i32
	value  i32
	length u32
}

struct NativeSurfaceApp {
mut:
	client_pid     int = -1
	input_fd       int = -1
	surface_path   string
	surface_width  int
	surface_height int
	icon           string
	starting_text  string
	exited_text    string
	ready          bool
	failed         bool
	error_message  string
}

fn open_blender(mut _ Desktop) !NativeApp {
	mut app := &NativeSurfaceApp{
		surface_width: blender_surface_width
		surface_height: blender_surface_height
		icon: 'builtin:block'
		starting_text: 'Starting native Blender…'
		exited_text: 'Blender exited.'
	}
	if C.access(&char(blender_native_executable.str), C.X_OK) != 0 {
		app.failed = true
		app.error_message = 'Native Blender is not staged. Run build-blender-native-aarch64.sh.'
		return app
	}
	if C.access(&char(blender_data_directory.str), C.R_OK) != 0 {
		app.failed = true
		app.error_message = 'Blender data is not installed. Run pkg install blender in Terminal.'
		return app
	}
	app.surface_path = '/tmp/vinix-blender-${C.getpid()}.surface'
	desktop_unlink(app.surface_path)
	client := desktop_spawn_native_surface(blender_native_executable, '-noaudio', app.surface_path, blender_surface_width, blender_surface_height) or {
		app.failed = true
		app.error_message = 'Vinix could not start the native Blender client.'
		return app
	}
	app.client_pid = client.pid
	app.input_fd = client.input
	return app
}

fn (mut app NativeSurfaceApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(2)
	if app.ready {
		children << ui2.image('', '${vinix_surface_image_prefix}${app.surface_path}', ui2.rect(0, 0, f64(width), f64(height)))
	} else {
		message := if app.failed { app.error_message } else { app.starting_text }
		children << ui2.button_with_image('', '', app.icon, ui2.rect(f64((width - 48) / 2), f64((height - 82) / 2), 48, 48), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: app_accent })
		children << ui2.label('', message, ui2.rect(16, f64((height - 82) / 2 + 58), f64(width - 32), 20), ui2.TextStyle{
			color: if app.failed { u32(0xb42318) } else { body_muted }
			size: 12
			align: .center
		})
	}
	return ui2.screen(0xf3f4f6, children)
}

fn (mut app NativeSurfaceApp) handle(_ string) ! {}

fn (mut app NativeSurfaceApp) poll() bool {
	if app.client_pid > 0 && desktop_child_exited(app.client_pid) {
		app.client_pid = -1
		if app.input_fd >= 0 {
			desktop_close(app.input_fd)
			app.input_fd = -1
		}
		app.ready = false
		app.failed = true
		app.error_message = app.exited_text
		desktop_unlink(app.surface_path)
		return true
	}
	if app.failed {
		return false
	}
	if !app.ready {
		mut surface := open_vinix_surface(app.surface_path) or { return false }
		surface.close()
		app.ready = true
		return true
	}
	// The producer replaces the active mapped buffer without changing the ui2
	// tree. Keep asking the compositor to present the newest complete frame.
	return true
}

fn (mut app NativeSurfaceApp) pointer_input_enabled() bool {
	return app.ready && app.input_fd >= 0
}

fn (mut app NativeSurfaceApp) send_input_event(kind VinixInputEventKind, x int, y int, value int, keys string) {
	if app.input_fd < 0 || keys.len > 4096 {
		return
	}
	event := VinixInputEvent{
		magic: vinix_input_event_magic
		kind: u32(kind)
		x: i32(x)
		y: i32(y)
		value: i32(value)
		length: u32(keys.len)
	}
	if !desktop_write_all(app.input_fd, &event, sizeof(VinixInputEvent)) {
		return
	}
	if keys.len > 0 {
		desktop_write_all(app.input_fd, keys.str, u64(keys.len))
	}
}

fn (mut app NativeSurfaceApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	if !app.pointer_input_enabled() || width <= 0 || height <= 0 {
		return
	}
	mut surface_x := x * app.surface_width / width
	mut surface_y := y * app.surface_height / height
	if surface_x < 0 {
		surface_x = 0
	} else if surface_x >= app.surface_width {
		surface_x = app.surface_width - 1
	}
	if surface_y < 0 {
		surface_y = 0
	} else if surface_y >= app.surface_height {
		surface_y = app.surface_height - 1
	}
	kind := match phase {
		.move { VinixInputEventKind.motion }
		.down { VinixInputEventKind.button_down }
		.up { VinixInputEventKind.button_up }
		.scroll { VinixInputEventKind.wheel }
	}
	value := if phase == .scroll { scroll } else { int(button) }
	app.send_input_event(kind, surface_x, surface_y, value, '')
}

fn (mut app NativeSurfaceApp) key_input(text string) {
	if text.len > 0 {
		app.send_input_event(.keys, 0, 0, 0, text)
	}
}

fn (mut app NativeSurfaceApp) close_app() {
	if app.input_fd >= 0 {
		// EOF is the native GHOST close request. Do not wait here: the Blender
		// shutdown path must not freeze the compositor's window-close action.
		desktop_close(app.input_fd)
		app.input_fd = -1
	}
	app.client_pid = -1
	if app.surface_path != '' {
		desktop_unlink(app.surface_path)
	}
}
