// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn preview_button(action string, key string, x int, y int, width int, enabled bool) ui2.Element {
	return ui2.Element{
		...ui2.button(action, tr(key), ui2.rect(f64(x), f64(y), f64(width), 28),
			ui2.BoxStyle{ bg: if enabled { body_panel } else { app_surface }, radius: 5 },
			ui2.TextStyle{ color: if enabled { body_text } else { body_muted }, size: 12, align: .center })
		enabled:             enabled
		accessibility_label: tr(key)
	}
}

fn preview_path_field(action string, placeholder string, bytes []u8, x int, y int,
	width int, focused bool, select_all bool) ui2.Element {
	count := files_rune_count(bytes)
	return ui2.Element{
		...ui2.text_field(action, tr(placeholder), editor_bytes_text(bytes),
			ui2.rect(f64(x), f64(y), f64(width), 28), ui2.BoxStyle{ bg: body_panel, radius: 5 },
			ui2.TextStyle{ color: body_text, size: 12 }, 0)
		focused:        focused
		text_selection: ui2.TextSelection{ anchor: if focused && select_all { 0 } else { count }, caret: count }
	}
}

fn preview_tool_button(action string, key string, x int, width int, enabled bool,
	selected bool) ui2.Element {
	button := preview_button(action, key, x, 114, width, enabled)
	if !enabled || !selected { return button }
	return ui2.Element{
		...button
		box: ui2.BoxStyle{bg: catalina_control_accent, radius: 5}
		text_style: ui2.TextStyle{color: app_on_accent, size: 12, align: .center}
	}
}

fn preview_status_error(key string) bool {
	return key in ['preview.status.cannot_open', 'preview.status.source_limit',
		'preview.status.unsupported', 'preview.status.pdf_unavailable', 'preview.status.cannot_decode',
		'preview.status.pixel_limit', 'preview.status.surface_failed', 'preview.status.exists',
		'preview.status.export_failed', 'preview.status.crop_failed',
		'preview.status.resize_invalid', 'preview.status.resize_failed']
}

fn (mut a PreviewApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	available_height := if height > preview_toolbar_height + preview_status_height {
		height - preview_toolbar_height - preview_status_height
	} else {
		1
	}
	a.set_viewport(width, available_height)
	if a.pixels != unsafe { nil } && a.details_language != desktop_language { a.refresh_details() }
	if a.pixels != unsafe { nil } && a.surface_background != body_panel {
		a.surface_dirty = true
	}
	if a.surface_dirty {
		if !a.publish_surface() {
			a.surface_dirty = false
			a.set_status('preview.status.surface_failed')
		}
	}
	loaded := a.pixels != unsafe { nil }
	mut children := frame_elements(31)
	children << preview_button(preview_action_open, 'preview.open', 8, 6, 64, true)
	children << preview_path_field(preview_action_open_path, 'preview.path.open.placeholder',
		a.open_path, 80, 6, if width > 88 { width - 88 } else { 1 }, a.focus == .open_path, a.select_all)
	children << preview_button(preview_action_fit, 'preview.fit', 8, 42, 50, loaded)
	children << preview_button(preview_action_actual, 'preview.actual', 64, 42, 58, loaded)
	children << preview_button(preview_action_zoom_out, 'preview.zoom.out', 128, 42, 34, loaded)
	children << preview_button(preview_action_zoom_in, 'preview.zoom.in', 168, 42, 34, loaded)
	children << preview_button(preview_action_rotate_left, 'preview.rotate.left', 208, 42, 90, loaded)
	children << preview_button(preview_action_rotate_right, 'preview.rotate.right', 304, 42, 90, loaded)
	children << preview_button(preview_action_export_png, 'preview.export.png', 400, 42, 112, loaded)
	children << preview_button(preview_action_export_copy, 'preview.export.copy', 518, 42, 140, loaded)
	children << ui2.label('', tr('preview.export.to'), ui2.rect(8, 78, 78, 28), ui2.TextStyle{
		color: body_muted
		size:  12
	})
	children << preview_path_field(preview_action_export_path, 'preview.path.export.placeholder',
		a.export_path, 94, 78, if width > 102 { width - 102 } else { 1 },
		a.focus == .export_path, a.select_all)
	children << preview_tool_button(preview_action_pan, 'preview.pan', 8, 70, loaded, a.tool == .pan)
	children << preview_tool_button(preview_action_select, 'preview.select', 84, 80, loaded, a.tool == .select)
	children << preview_button(preview_action_crop, 'preview.crop', 170, 114, 80,
		loaded && a.crop_rect_valid(a.crop_rect()))
	children << preview_button(preview_action_clear_selection, 'preview.selection.clear', 256, 114, 80,
		loaded && a.selection.active)
	children << preview_button(preview_action_undo_crop, 'preview.undo', 344, 114, 100,
		a.can_undo_crop())
	children << preview_button(preview_action_redo_crop, 'preview.redo', 450, 114, 100,
		a.can_redo_crop())
	children << ui2.label('', tr(if a.tool == .select { 'preview.status.select' } else { 'preview.status.pan' }),
		ui2.rect(558, 114, if width > 566 { f64(width - 566) } else { 1 }, 28),
		ui2.TextStyle{color: body_muted, size: 11})
	children << ui2.label('', tr('preview.resize.width.label'), ui2.rect(8, 150, 58, 28), ui2.TextStyle{color: body_muted, size: 11})
	children << ui2.label('', tr('preview.resize.height.label'), ui2.rect(140, 150, 64, 28), ui2.TextStyle{color: body_muted, size: 11})
	children << preview_dimension_field(preview_action_resize_width, 'preview.resize.width.label',
		a.resize_width.text(), 70, 150, a.focus == .resize_width, a.select_all)
	children << preview_dimension_field(preview_action_resize_height, 'preview.resize.height.label',
		a.resize_height.text(), 208, 150, a.focus == .resize_height, a.select_all)
	lock_button := preview_button(preview_action_resize_lock, 'preview.resize.lock.label', 278, 150, 142, loaded)
	children << if loaded && a.resize_locked { ui2.Element{...lock_button
		box: ui2.BoxStyle{bg: catalina_control_accent, radius: 5}
		text_style: ui2.TextStyle{color: app_on_accent, size: 12, align: .center}
	} } else { lock_button }
	children << preview_button(preview_action_resize, 'preview.resize.apply', 426, 150, 112, a.resize_valid())
	children << ui2.label('', tr('preview.resize.limit'), ui2.rect(546, 150,
		if width > 554 { f64(width - 554) } else { 1 }, 28), ui2.TextStyle{color: body_muted, size: 11})
	children << ui2.view('', ui2.rect(0, preview_toolbar_height - 1, size.width, 1), ui2.BoxStyle{ bg: body_rule }, [])
	mut image := frame_elements(1)
	if a.surface_image.len > 0 {
		image << ui2.image('', a.surface_image, ui2.rect(f64((width - a.viewport_width) / 2),
			f64((available_height - a.viewport_height) / 2), f64(a.viewport_width), f64(a.viewport_height)))
	} else {
		image << ui2.label('', tr(if loaded {
			'preview.status.surface_failed'
		} else {
			'preview.status.choose'
		}),
			ui2.rect(16, f64(available_height / 2 - 20), f64(width - 32), 40),
			ui2.TextStyle{ color: body_muted, size: 14, align: .center })
	}
	children << ui2.clickable_view(preview_action_image, ui2.rect(0, preview_toolbar_height,
		size.width, f64(available_height)), ui2.BoxStyle{ bg: body_panel }, image)
	status_top := height - preview_status_height
	children << ui2.view('', ui2.rect(0, f64(status_top), size.width, 1), ui2.BoxStyle{ bg: body_rule }, [])
	if loaded {
		children << ui2.label('', a.details, ui2.rect(8, f64(status_top), 230, preview_status_height),
			ui2.TextStyle{ color: body_muted, size: 11 })
	}
	status_left := if loaded { 246 } else { 8 }
	children << ui2.Element{
		...ui2.label('', tr(a.status_key), ui2.rect(f64(status_left), f64(status_top),
			f64(width - status_left - 8), preview_status_height),
			ui2.TextStyle{
				color: if preview_status_error(a.status_key) {
					files_error
				} else {
					body_muted
				}
				size:  11
			})
		tooltip: tr(a.status_key)
	}
	return ui2.screen(app_surface, children)
}

fn preview_dimension_field(action string, key string, text string, x int, y int,
	focused bool, select_all bool) ui2.Element {
	return ui2.Element{
		...ui2.text_field(action, tr(key), text, ui2.rect(f64(x), f64(y), 62, 28),
			ui2.BoxStyle{bg: body_panel, radius: 5}, ui2.TextStyle{color: body_text, size: 12}, 0)
		focused: focused
		text_selection: ui2.TextSelection{anchor: if focused && select_all { 0 } else { text.len }, caret: text.len}
		accessibility_label: tr(key)
	}
}
