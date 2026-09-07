// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Windows and what they show. Native windows contain a built-in page or a
// ui2 tree received from an application process. External display-owning programs are launched by
// the window manager and only use a native window to report a startup error.
module main

import ui2

enum Page {
	welcome
	system
	palette
	notes
	external_error
	// A window whose contents come from a native application process rather than
	// from one of the pages below.
	app
}

struct Window {
mut:
	id     int
	title  string
	page   Page
	x      int
	y      int
	width  int
	height int
	// The glyph that stands for the window in the switcher. An application
	// lends its own; a built-in page has none of its own to lend.
	icon string = 'builtin:window'
	// Element ids, built once when the window opens. The tree is rebuilt every
	// frame and this target has no garbage collector, so interpolating them
	// per frame would grow the process for no reason.
	id_frame    string
	id_titlebar string
	id_title    string
	id_close    string
	id_maximize string
	id_minimize string
	id_divider  string
	id_body     string
	id_task     string
	// Geometry to come back to when a maximised window is restored.
	restore_x      int
	restore_y      int
	restore_width  int
	restore_height int
	maximized      bool
	minimized      bool
	// Index into Desktop.apps for a `.app` window, or -1 for a built-in page.
	app_index int = -1
}

fn (w &Window) frame_rect() ui2.Rect {
	return ui2.rect(f64(w.x), f64(w.y), f64(w.width), f64(w.height))
}

// content builds the page inside a window's body. Coordinates are relative to
// the body, so a window can be moved or maximised without the page knowing.
//
// Page elements carry no ids: nothing looks them up and nothing in them is
// clickable, and an id would have to be built afresh on every frame.
fn (w &Window) content(width int, height int, desktop &Desktop) []ui2.Element {
	return match w.page {
		.welcome { welcome_page(width, height) }
		.system { system_page(width, height, desktop) }
		.palette { palette_page(width, height) }
		.notes { notes_page(width, height) }
		.external_error { external_error_page(width, desktop) }
		// An application's contents are built by the window manager, which is
		// the only thing holding a mutable reference to it.
		.app { []ui2.Element{} }
	}
}

fn external_error_page(width int, desktop &Desktop) []ui2.Element {
	pad := 18
	inner := width - 2 * pad
	mut children := frame_elements(5)
	children << ui2.view('', ui2.rect(f64(pad), 18, f64(inner), 4), ui2.BoxStyle{
		bg: app_accent
		radius: 2
	}, [])
	children << heading('Firefox could not start', pad, 34, inner)
	children << body_line(desktop.external_error, pad, 68, inner)
	children << muted_line('Firefox uses its packaged GTK/X11 runtime; the native desktop stays GTK-free.', pad, 100, inner)
	children << muted_line('Build Firefox/Xorg, then rebuild the userland and desktop image.', pad, 120, inner)
	return children
}

fn heading(text string, x int, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(x), f64(y), f64(width), 20), ui2.TextStyle{
		color: body_heading
		size: 17
		bold: true
	})
}

fn body_line(text string, x int, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(x), f64(y), f64(width), 18), ui2.TextStyle{
		color: body_text
		size: 13
	})
}

// owned_body_line takes ownership of a string formatted for this frame. Its
// marker is understood by free_tree, after rendering has finished with it.
fn owned_body_line(text string, x int, y int, width int) ui2.Element {
	return ui2.label(frame_owned_text_id, text, ui2.rect(f64(x), f64(y), f64(width), 18), ui2.TextStyle{
		color: body_text
		size: 13
	})
}

fn muted_line(text string, x int, y int, width int) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(x), f64(y), f64(width), 16), ui2.TextStyle{
		color: body_muted
		size: 11
	})
}

fn welcome_page(width int, _height int) []ui2.Element {
	pad := 18
	inner := width - 2 * pad
	mut children := frame_elements(7)
	children << ui2.view('', ui2.rect(f64(pad), 18, f64(inner), 4), ui2.BoxStyle{
		bg: app_accent
		radius: 2
	}, [])
	children << heading('Welcome to Vinix', pad, 32, inner)
	children << body_line('A desktop written from scratch in V,', pad, 60, inner)
	children << body_line('drawing straight into the framebuffer.', pad, 78, inner)
	children << ui2.view('', ui2.rect(f64(pad), 104, f64(inner), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << muted_line('Drag a title bar to move a window.', pad, 116, inner)
	children << muted_line('The taskbar lists everything that is open.', pad, 134, inner)
	return children
}

fn system_page(width int, height int, desktop &Desktop) []ui2.Element {
	pad := 18
	inner := width - 2 * pad
	display_width := desktop.canvas.width.str()
	display_height := desktop.canvas.height.str()
	display := 'Display   ${display_width} x ${display_height}'
	unsafe {
		display_width.free()
		display_height.free()
	}
	pointer := 'Pointer   ${desktop.pointer_description()}'
	open_windows := desktop.windows.len.str()
	visible_windows := desktop.visible_window_count().str()
	windows := 'Windows   ${open_windows} open, ${visible_windows} on screen'
	unsafe {
		open_windows.free()
		visible_windows.free()
	}
	frame_count := desktop.frames.str()
	frames := 'Frames    ${frame_count}'
	unsafe { frame_count.free() }
	battery := device_line('Battery   ', '/dev/battery')
	backlight := device_line('Backlight ', '/dev/apple-panel-bl')
	mut panel_children := frame_elements(7)
	panel_children << owned_body_line(display, 12, 12, inner - 24)
	panel_children << owned_body_line(pointer, 12, 32, inner - 24)
	panel_children << owned_body_line(windows, 12, 52, inner - 24)
	panel_children << owned_body_line(frames, 12, 72, inner - 24)
	panel_children << owned_body_line(battery, 12, 92, inner - 24)
	panel_children << owned_body_line(backlight, 12, 112, inner - 24)
	panel_children << muted_line('Ctrl-Q leaves the desktop, Ctrl-N opens a window.', 12, 136, inner - 24)
	mut children := frame_elements(2)
	children << heading('System', pad, 18, inner)
	children << ui2.view('', ui2.rect(f64(pad), 46, f64(inner), f64(height - 46 - pad)), ui2.BoxStyle{
		bg: body_panel
		radius: 6
	}, panel_children)
	return children
}

// Whether a device node is there at all, which is the difference between a
// driver that failed and a feature that does nothing. A machine with no serial
// port paints the boot log over with this desktop, so "the battery reads --%"
// and "F1 changes no brightness" otherwise look like desktop bugs when both
// are really the kernel never having registered the device.
fn device_line(label string, path string) string {
	desktop_stat(path) or { return '${label}absent (driver did not register it)' }
	return '${label}present at ${path}'
}

fn palette_page(width int, height int) []ui2.Element {
	swatches := [
		u32(0xe5484d),
		u32(0xf76b15),
		u32(0xffc53d),
		u32(0x46a758),
		u32(0x5b9cf8),
		u32(0x8e4ec6),
	]
	pad := 18
	gap := 10
	top := 48
	columns := 3
	rows := (swatches.len + columns - 1) / columns
	inner := width - 2 * pad
	// Square cells, sized by whichever axis runs out first, so the grid stays
	// inside a window of any shape instead of running off the bottom.
	cell_width := (inner - (columns - 1) * gap) / columns
	cell_height := (height - top - pad - (rows - 1) * gap) / rows
	cell := if cell_width < cell_height { cell_width } else { cell_height }

	mut children := frame_elements(swatches.len + 1)
	children << heading('Palette', pad, 18, inner)
	for i, color in swatches {
		column := i % columns
		row := i / columns
		children << ui2.view('', ui2.rect(f64(pad + column * (cell + gap)), f64(top + row * (cell + gap)), f64(cell), f64(cell)), ui2.BoxStyle{
			bg: color
			radius: 6
		}, [])
	}
	return children
}

fn notes_page(width int, _height int) []ui2.Element {
	pad := 18
	inner := width - 2 * pad
	lines := [
		'The compositor owns every pixel:',
		'wallpaper, frames, text and cursor.',
		'',
		'Layout and hit testing come from a',
		'ui2 element tree, rebuilt each frame.',
	]
	mut children := frame_elements(lines.len + 1)
	children << heading('Notes', pad, 18, inner)
	for i, line in lines {
		children << body_line(line, pad, 50 + i * 19, inner)
	}
	return children
}
