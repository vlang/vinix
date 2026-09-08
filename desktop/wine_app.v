// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A translated Win64 application embedded in a native Vinix window.
module main

import ui2

const wine_surface_width = 326
const wine_surface_height = 430
const wine_host_event_magic = u32(0x56574831) // VWH1

enum WineHostEventKind as u32 {
	motion = 1
	button_down
	button_up
	keys
}

struct WineHostEvent {
	magic  u32
	kind   u32
	x      int
	y      int
	length u32
}

struct WineApp {
mut:
	host_pid      int = -1
	input_fd      int = -1
	directory     string
	xwd_path      string
	image_path    string
	ready         bool
	failed        bool
	error_message string
}

fn open_wine_calculator(mut _ Desktop) !NativeApp {
	mut app := &WineApp{}
	process_id := C.getpid()
	app.directory = '/tmp/vinix-wine-${process_id}'
	app.xwd_path = '${app.directory}/Xvfb_screen0'
	app.image_path = '${xwd_image_prefix}${app.xwd_path}'

	if C.access(c'/usr/bin/Xvfb', C.X_OK) != 0 {
		app.failed = true
		app.error_message = 'Xvfb is not installed. Rebuild the Vinix X11 layer.'
		return app
	}
	if C.access(c'/usr/bin/calculator', C.X_OK) != 0 {
		app.failed = true
		app.error_message = 'The translated Wine runtime is not installed.'
		return app
	}
	host := desktop_spawn_wine_host(app.directory, wine_surface_width, wine_surface_height, '/usr/bin/calculator') or {
		app.failed = true
		app.error_message = 'Vinix could not start the embedded Wine host.'
		return app
	}
	app.host_pid = host.pid
	app.input_fd = host.input
	return app
}

fn (mut app WineApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(2)
	if app.ready {
		children << ui2.image('', app.image_path, ui2.rect(0, 0, f64(width), f64(height)))
	} else {
		message := if app.failed { app.error_message } else { 'Starting Windows application…' }
		children << ui2.button_with_image('', '', 'builtin:calculator', ui2.rect(f64((width - 48) / 2), f64((height - 82) / 2), 48, 48), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: app_accent })
		children << ui2.label('', message, ui2.rect(16, f64((height - 82) / 2 + 58), f64(width - 32), 20), ui2.TextStyle{
			color: if app.failed { u32(0xb42318) } else { body_muted }
			size: 12
			align: .center
		})
	}
	return ui2.screen(0xf3f4f6, children)
}

fn (mut app WineApp) handle(_ string) ! {}

fn (mut app WineApp) poll() bool {
	if app.host_pid > 0 && desktop_child_exited(app.host_pid) {
		app.host_pid = -1
		if app.input_fd >= 0 {
			desktop_close(app.input_fd)
			app.input_fd = -1
		}
		app.ready = false
		app.failed = true
		app.error_message = 'The Windows application exited.'
		return true
	}
	if !app.ready {
		desktop_stat(app.xwd_path) or { return false }
		app.ready = true
		return true
	}
	// Xvfb changes its shared XWD mapping in place. Ask the compositor to blit
	// the next frame even though no ui2 model property changed.
	return true
}

fn (mut app WineApp) pointer_input_enabled() bool {
	return app.ready && app.input_fd >= 0
}

fn (mut app WineApp) send_host_event(kind WineHostEventKind, x int, y int, keys string) {
	if app.input_fd < 0 || keys.len > 4096 {
		return
	}
	event := WineHostEvent{
		magic: wine_host_event_magic
		kind: u32(kind)
		x: x
		y: y
		length: u32(keys.len)
	}
	if !desktop_write_all(app.input_fd, &event, sizeof(WineHostEvent)) {
		return
	}
	if keys.len > 0 {
		desktop_write_all(app.input_fd, keys.str, u64(keys.len))
	}
}

fn (mut app WineApp) pointer_event(phase AppPointerPhase, x int, y int, width int, height int) {
	if !app.pointer_input_enabled() || width <= 0 || height <= 0 {
		return
	}
	mut surface_x := x * wine_surface_width / width
	mut surface_y := y * wine_surface_height / height
	if surface_x < 0 {
		surface_x = 0
	}
	if surface_y < 0 {
		surface_y = 0
	}
	if surface_x >= wine_surface_width {
		surface_x = wine_surface_width - 1
	}
	if surface_y >= wine_surface_height {
		surface_y = wine_surface_height - 1
	}
	kind := match phase {
		.move { WineHostEventKind.motion }
		.down { WineHostEventKind.button_down }
		.up { WineHostEventKind.button_up }
	}
	app.send_host_event(kind, surface_x, surface_y, '')
}

fn (mut app WineApp) key_input(text string) {
	if text.len > 0 {
		app.send_host_event(.keys, 0, 0, text)
	}
}

fn (mut app WineApp) close_app() {
	if app.input_fd >= 0 {
		desktop_close(app.input_fd)
		app.input_fd = -1
	}
	if app.host_pid > 0 {
		desktop_wait_child(app.host_pid)
		app.host_pid = -1
	}
}
