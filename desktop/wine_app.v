// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// X11 applications embedded in native Vinix windows. Xvfb owns the upstream
// application's display while the Vinix compositor maps its live XWD surface.
module main

import ui2

const firefox_surface_width = 1280
const firefox_surface_height = 900
const firefox_window_width = 1280
const firefox_window_height = 900
const wine_surface_width = 326
const wine_surface_height = 430
const wine_notepad_surface_width = 310
const wine_notepad_surface_height = 230
// Office 2013 restores a 768x576 top-level window in a fresh prefix. Matching
// the private X server to it avoids unused root-window bands, and its 4:3
// aspect ratio maps exactly into the native 680x510 Vinix frame.
const wine_word2013_surface_width = 768
const wine_word2013_surface_height = 576
const wine_word2013_window_width = 680
const wine_word2013_window_height = 510
const minecraft_surface_width = 1280
const minecraft_surface_height = 720
const minecraft_window_width = 760
const minecraft_window_height = 428
const blender_surface_width = 1280
const blender_surface_height = 900
const blender_window_width = 1280
const blender_window_height = 900
const wine_host_event_magic = u32(0x56574831) // VWH1

enum WineHostEventKind as u32 {
	motion = 1
	button_down
	button_up
	keys
}

struct WineHostEvent {
	magic u32
	kind  u32
	// The receiving C host uses int32_t and asserts a 20-byte wire record.
	x      i32
	y      i32
	length u32
}

struct HostedX11App {
mut:
	host_pid       int = -1
	input_fd       int = -1
	directory      string
	xwd_path       string
	image_path     string
	surface_width  int
	surface_height int
	icon           string
	starting_text  string
	exited_text    string
	ready          bool
	failed         bool
	error_message  string
}

fn open_firefox(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('firefox', '/usr/bin/run-firefox', firefox_surface_width, firefox_surface_height, 'builtin:browser', 'Starting Firefox…', 'Firefox is not installed in this desktop image.', 'Firefox exited.')
}

fn open_wine_calculator(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('wine', '/usr/bin/calculator', wine_surface_width, wine_surface_height, 'builtin:calculator', 'Starting Windows application…', 'The translated Wine runtime is not installed.', 'The Windows application exited.')
}

fn open_wine_notepad(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('wine-notepad', '/usr/bin/notepad', wine_notepad_surface_width, wine_notepad_surface_height, 'builtin:editor', 'Starting Windows application…', 'The translated Wine runtime is not installed.', 'The Windows application exited.')
}

fn open_wine_word2013(mut _ Desktop) !NativeApp {
	for word in [
		'/root/.wine-word2013-x86_64/drive_c/Program Files/Microsoft Office 15/root/office15/WINWORD.EXE',
		'/root/.wine-word2013-x86_64/drive_c/Program Files/Microsoft Office/Office15/WINWORD.EXE',
	] {
		if C.access(&char(word.str), 0) == 0 {
			mut app := open_hosted_x11_app('wine-word2013', '/usr/bin/word2013', wine_word2013_surface_width, wine_word2013_surface_height, 'builtin:editor', 'Starting Microsoft Word 2013…', 'The translated Win64 Wine runtime is not installed.', 'Microsoft Word 2013 exited.')
			app.image_path = '${office_xwd_image_prefix}${app.xwd_path}'
			return app
		}
	}
	for setup in ['/root/word2013-media/office/setup64.exe', '/root/word2013-media/office/SETUP64.EXE',
		'/root/word2013-media/setup.exe', '/root/word2013-media/SETUP.EXE'] {
		if C.access(&char(setup.str), 0) == 0 {
			return open_hosted_x11_app('wine-word2013-setup', '/usr/bin/word2013-setup', wine_word2013_surface_width, wine_word2013_surface_height, 'builtin:editor', 'Starting 64-bit Word 2013 setup…', 'The translated Win64 Wine runtime is not installed.', 'Word 2013 setup closed. Launch Word again after installation.')
		}
	}
	return &HostedX11App{
		surface_width: wine_word2013_surface_width
		surface_height: wine_word2013_surface_height
		icon: 'builtin:editor'
		failed: true
		error_message: 'Stage licensed Word 2013 x64 media, then launch Word again.'
	}
}

fn open_minecraft(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('minecraft', '/usr/bin/minecraft', minecraft_surface_width, minecraft_surface_height, 'builtin:block', 'Starting Minecraft…', 'Minecraft is not installed. Build its AArch64 runtime first.', 'Minecraft exited.')
}

fn open_blender(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('blender', '/usr/bin/blender', blender_surface_width, blender_surface_height, 'builtin:block', 'Starting Blender…', 'Blender is not installed. Run pkg install blender in Terminal first.', 'Blender exited.')
}

fn open_hosted_x11_app(name string, command string, surface_width int, surface_height int,
	icon string, starting_text string, missing_text string, exited_text string) &HostedX11App {
	mut app := &HostedX11App{
		surface_width: surface_width
		surface_height: surface_height
		icon: icon
		starting_text: starting_text
		exited_text: exited_text
	}
	process_id := C.getpid()
	app.directory = '/tmp/vinix-${name}-${process_id}'
	app.xwd_path = '${app.directory}/Xvfb_screen0'
	app.image_path = '${xwd_image_prefix}${app.xwd_path}'

	if C.access(c'/usr/bin/Xvfb', C.X_OK) != 0 {
		app.failed = true
		app.error_message = 'Xvfb is not installed. Rebuild the Vinix X11 layer.'
		return app
	}
	if C.access(&char(command.str), C.X_OK) != 0 {
		app.failed = true
		app.error_message = missing_text
		return app
	}
	host := desktop_spawn_wine_host(app.directory, surface_width, surface_height, command) or {
		app.failed = true
		app.error_message = 'Vinix could not start the embedded X11 host.'
		return app
	}
	app.host_pid = host.pid
	app.input_fd = host.input
	return app
}

fn (mut app HostedX11App) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(2)
	if app.ready {
		children << ui2.image('', app.image_path, ui2.rect(0, 0, f64(width), f64(height)))
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

fn (mut app HostedX11App) handle(_ string) ! {}

fn (mut app HostedX11App) poll() bool {
	if app.host_pid > 0 && desktop_child_exited(app.host_pid) {
		app.host_pid = -1
		if app.input_fd >= 0 {
			desktop_close(app.input_fd)
			app.input_fd = -1
		}
		app.ready = false
		app.failed = true
		app.error_message = app.exited_text
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

fn (mut app HostedX11App) pointer_input_enabled() bool {
	return app.ready && app.input_fd >= 0
}

fn (mut app HostedX11App) send_host_event(kind WineHostEventKind, x int, y int, keys string) {
	if app.input_fd < 0 || keys.len > 4096 {
		return
	}
	event := WineHostEvent{
		magic: wine_host_event_magic
		kind: u32(kind)
		x: i32(x)
		y: i32(y)
		length: u32(keys.len)
	}
	if !desktop_write_all(app.input_fd, &event, sizeof(WineHostEvent)) {
		return
	}
	if keys.len > 0 {
		desktop_write_all(app.input_fd, keys.str, u64(keys.len))
	}
}

fn (mut app HostedX11App) pointer_event(phase AppPointerPhase, x int, y int, width int, height int) {
	if !app.pointer_input_enabled() || width <= 0 || height <= 0 {
		return
	}
	mut surface_x := x * app.surface_width / width
	mut surface_y := y * app.surface_height / height
	if surface_x < 0 {
		surface_x = 0
	}
	if surface_y < 0 {
		surface_y = 0
	}
	if surface_x >= app.surface_width {
		surface_x = app.surface_width - 1
	}
	if surface_y >= app.surface_height {
		surface_y = app.surface_height - 1
	}
	kind := match phase {
		.move { WineHostEventKind.motion }
		.down { WineHostEventKind.button_down }
		.up { WineHostEventKind.button_up }
	}
	app.send_host_event(kind, surface_x, surface_y, '')
}

fn (mut app HostedX11App) key_input(text string) {
	if text.len > 0 {
		app.send_host_event(.keys, 0, 0, text)
	}
}

fn (mut app HostedX11App) close_app() {
	if app.input_fd >= 0 {
		// The host treats EOF as its shutdown request and owns the Wine and Xvfb
		// process tree. Do not synchronously wait for that cleanup here: under
		// translation a Windows process can take long enough to stop that it
		// would freeze the compositor while an otherwise ordinary Vinix window
		// is being closed. The app process exits after replying to the close
		// request, and init reaps the now-orphaned host when it finishes.
		desktop_close(app.input_fd)
		app.input_fd = -1
	}
	app.host_pid = -1
}
