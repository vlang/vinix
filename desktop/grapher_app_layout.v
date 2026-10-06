// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

// Paging and resize state are inline scalars. A resize never edits fields,
// invalidates samples or creates an owned label or persistent layout buffer.
enum GrapherPage {
	graph
	document
	csv
	png
}

fn grapher_page_for_field(index int) GrapherPage {
	return match index {
		5 { .csv }
		6 { .document }
		7 { .png }
		else { .graph }
	}
}

fn (mut app GrapherApp) reveal_focused_page() {
	if app.focus >= 0 { app.compact_page = grapher_page_for_field(app.focus) }
}

fn (mut app GrapherApp) select_page(page GrapherPage) {
	app.compact_page = page
	if app.focus >= 0 && grapher_page_for_field(app.focus) != page {
		// Hidden fields must not continue accepting edits after a mouse page switch.
		app.focus = -1
		app.selected = false
		app.pending_length = 0
	}
}

fn (app &GrapherApp) layout_status(width int, height int) ui2.Element {
	status := if app.document_status.len > 0 {
		app.document_status
	} else if app.export_status.len > 0 {
		app.export_status
	} else { app.status }
	return ui2.Element{
		...ui2.label('grapher.status', tr(status), ui2.rect(12, f64(height - 27), f64(width - 24), 22),
			ui2.TextStyle{ size: 11, color: body_muted })
		tooltip: tr(status)
	}
}

// The native compositor draws a label as one line. Keep each translated line
// a borrowed catalog slice instead of allocating split strings or relying on
// a TextStyle.lines setting the native renderer does not consume.
fn grapher_compact_help(mut children []ui2.Element, key string, width int, y int, font_size int) {
	text := tr(key)
	mut start := 0
	for line in 0 .. 3 {
		if start >= text.len { return }
		mut end := start
		for end < text.len && text[end] != `\n` { end++ }
		children << ui2.Element{
			...ui2.label('', unsafe { tos(text.str + start, end - start) },
				ui2.rect(12, f64(y + line * 14), f64(width - 24), 14),
				ui2.TextStyle{size: f64(font_size), color: body_muted})
			tooltip: text
		}
		start = end + 1
	}
}

fn (app &GrapherApp) build_compact(width int, height int) ui2.Element {
	mut children := frame_elements(32)
	children << ui2.label('', tr('app.grapher'), ui2.rect(12, 10, f64(width - 24), 26),
		ui2.TextStyle{ size: 18, bold: true, color: body_heading })
	column := (width - 48) / 4
	for index, key in ['grapher.page.graph', 'grapher.page.document', 'grapher.page.csv',
		'grapher.page.png']! {
		selected := int(app.compact_page) == index
		children << ui2.button(key, tr(key), ui2.rect(f64(12 + index * (column + 8)), 44, f64(column), 28),
			ui2.BoxStyle{ bg: if selected { app_accent } else { settings_choice_bg }, radius: 5 },
			ui2.TextStyle{ size: 11, color: if selected { u32(0xffffff) } else { body_text }, align: .center })
	}
	if app.compact_page == .graph {
		children << ui2.label('', tr('grapher.equation_label'), ui2.rect(12, 82, 38, 28), ui2.TextStyle{ size: 12, color: body_text })
		children << app.field(0, 52, 82, width - 168)
		children << grapher_button('grapher.plot', 'grapher.plot', width - 104, 82, 92)
		range_column := (width - 24) / 4
		for index, key in ['grapher.xmin_label', 'grapher.xmax_label', 'grapher.ymin_label',
			'grapher.ymax_label']! {
			children << ui2.label('', tr(key), ui2.rect(f64(12 + index * range_column), 115, f64(range_column - 8), 18),
				ui2.TextStyle{ size: 11, color: body_muted })
			children << app.field(index + 1, 12 + index * range_column, 134, range_column - 8)
		}
		button_width := (width - 40) / 3
		for index, key in ['grapher.reset', 'grapher.zoom_in', 'grapher.zoom_out']! {
			children << grapher_button(key, key, 12 + index * (button_width + 8), 172, button_width)
		}
		chart_width := width - 76
		chart_height := height - 260
		children << app.chart_at(chart_width, chart_height, 52, 212)
		if app.plotted {
			children << grapher_tick(app.range[3], 2, 212, 44, .right)
			children << grapher_tick(app.range[2], 2, 212 + chart_height - 18, 44, .right)
			children << grapher_tick(app.range[0], 52, 214 + chart_height, chart_width / 2, .left)
			children << grapher_tick(app.range[1], 52 + chart_width / 2, 214 + chart_height, chart_width / 2, .right)
		}
	} else {
		field, label, help := match app.compact_page {
			.document { 6, 'grapher.document_path', 'grapher.compact.document' }
			.csv { 5, 'grapher.page.csv', 'grapher.compact.csv' }
			.png { 7, 'grapher.png_path', 'grapher.compact.png' }
			else { 6, 'grapher.document_path', 'grapher.compact.document' }
		}
		children << ui2.label('', tr(label), ui2.rect(12, 84, f64(width - 24), 22), ui2.TextStyle{ size: 12, color: body_text })
		children << app.field(field, 12, 114, width - 24)
		if app.compact_page == .document {
			button_width := (width - 32) / 2
			children << grapher_button('grapher.document_open', 'grapher.document_open', 12, 152, button_width)
			children << grapher_button('grapher.document_save_as', 'grapher.document_save_as', 20 + button_width, 152, button_width)
		} else {
			action := if app.compact_page == .csv { 'grapher.export' } else { 'grapher.export_png' }
			children << grapher_button(action, action, 12, 152, width - 24)
		}
		grapher_compact_help(mut children, help, width, 192, 11)
		grapher_compact_help(mut children, 'grapher.compact.keyboard', width, 244, 10)
	}
	children << app.layout_status(width, height)
	return ui2.view('grapher.body', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ bg: app_surface }, children)
}

fn (app &GrapherApp) build_tiny(width int, height int) ui2.Element {
	mut children := frame_elements(4)
	if width >= 96 && height >= 96 {
		children << ui2.label('', tr('app.grapher'), ui2.rect(8, 8, f64(width - 16), 22),
			ui2.TextStyle{ size: 14, bold: true, color: body_heading })
		children << grapher_button('grapher.plot', 'grapher.plot', 8, 36, width - 16)
		children << ui2.Element{
			...ui2.label('grapher.resize', tr('grapher.resize'), ui2.rect(8, 72, f64(width - 16), f64(height - 80)),
				ui2.TextStyle{ size: 10, color: body_muted })
			tooltip: tr('grapher.resize')
		}
	} else if width > 0 && height > 0 {
		children << ui2.Element{
			...ui2.label('grapher.resize', tr('grapher.resize'), ui2.rect(0, 0, f64(width), f64(height)),
				ui2.TextStyle{ size: 10, color: body_muted })
			tooltip: tr('grapher.resize')
		}
	}
	return ui2.view('grapher.body', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ bg: app_surface }, children)
}
