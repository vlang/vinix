// SPDX-License-Identifier: GPL-2.0-or-later
// Ordinary view rectangles and labels survive the native process protocol.
module main

import math
import ui2

fn grapher_button(action string, key string, x int, y int, width int) ui2.Element {
	return ui2.button(action, tr(key), ui2.rect(f64(x), f64(y), f64(width), 28),
		ui2.BoxStyle{ bg: settings_choice_bg, radius: 5 }, ui2.TextStyle{ size: 12, color: body_text, align: .center })
}

fn (app &GrapherApp) field(index int, x int, y int, width int) ui2.Element {
	count := files_rune_count(app.fields[index].bytes)
	return ui2.Element{
		...ui2.text_field(grapher_field_actions[index], '', app.field_text(index), ui2.rect(f64(x), f64(y), f64(width), 28),
			ui2.BoxStyle{ bg: body_panel, radius: 5 }, ui2.TextStyle{ size: 12, color: body_text }, 0)
		focused:        app.focus == index
		text_selection: ui2.TextSelection{
			anchor: if app.focus == index && app.selected {
				0
			} else {
				count
			}
			caret:  count
		}
	}
}

fn grapher_project_y(value f64, minimum f64, maximum f64, height int) int {
	if value <= minimum { return height - 1 }
	if value >= maximum { return 0 }
	return int((maximum - value) / (maximum - minimum) * f64(height - 1))
}

fn grapher_tick(value f64, x int, y int, width int, align ui2.Align) ui2.Element {
	mut buffer := [64]u8{}
	length := unsafe { C.snprintf(&char(&buffer[0]), 64, c'%.5g', value) }
	text := unsafe { tos(&buffer[0], if length > 0 && length < 64 { length } else { 0 }).clone() }
	return ui2.label(frame_owned_text_id, text, ui2.rect(f64(x), f64(y), f64(width), 18), ui2.TextStyle{ size: 10, color: body_muted, align: align })
}

fn (app &GrapherApp) chart(width int, height int) ui2.Element {
	mut children := frame_elements(grapher_sample_count + 24)
	for index in 1 .. 10 {
		children << ui2.view('', ui2.rect(f64(width * index / 10), 0, 1, f64(height)), ui2.BoxStyle{ bg: body_rule }, [])
		children << ui2.view('', ui2.rect(0, f64(height * index / 10), f64(width), 1), ui2.BoxStyle{ bg: body_rule }, [])
	}
	if app.plotted {
		if app.range[0] <= 0 && app.range[1] >= 0 {
			x := int(-app.range[0] / (app.range[1] - app.range[0]) * f64(width - 1))
			children << ui2.view('', ui2.rect(f64(x), 0, 1, f64(height)), ui2.BoxStyle{ bg: body_muted }, [])
		}
		if app.range[2] <= 0 && app.range[3] >= 0 {
			y := grapher_project_y(0, app.range[2], app.range[3], height)
			children << ui2.view('', ui2.rect(0, f64(y), f64(width), 1), ui2.BoxStyle{ bg: body_muted }, [])
		}
		step := f64(width - 1) / f64(grapher_sample_count - 1)
		for index in 0 .. grapher_sample_count {
			value := app.values[index]
			if !value.valid { continue }
			x := int(f64(index) * step)
			y := grapher_project_y(value.value, app.range[2], app.range[3], height)
			if index > 0 && app.connect[index] {
				previous := app.values[index - 1].value
				if (previous < app.range[2] && value.value < app.range[2]) || (previous > app.range[3] && value.value > app.range[3]) {
					continue
				}
				previous_y := grapher_project_y(previous, app.range[2], app.range[3], height)
				top := if y < previous_y { y } else { previous_y }
				children << ui2.view('', ui2.rect(f64(x), f64(top), math.ceil(step) + 1, f64(math.abs(y - previous_y) + 2)), ui2.BoxStyle{ bg: app_accent }, [])
			} else if value.value >= app.range[2] && value.value <= app.range[3] {
				children << ui2.view('', ui2.rect(f64(x), f64(y), 2, 2), ui2.BoxStyle{ bg: app_accent }, [])
			}
		}
	}
	return ui2.view('grapher.chart', ui2.rect(52, 174, f64(width), f64(height)),
		ui2.BoxStyle{ bg: body_panel, border_color: body_rule, border_left: 1, border_top: 1, border_right: 1, border_bottom: 1 }, children)
}

fn (mut app GrapherApp) build(size ui2.Rect) !ui2.Element {
	if !app.initialized { app.initialize() }
	width := if int(size.width) > 320 { int(size.width) } else { 320 }
	height := if int(size.height) > 380 { int(size.height) } else { 380 }
	mut children := frame_elements(32)
	children << ui2.label('', tr('app.grapher'), ui2.rect(12, 10, f64(width - 24), 26), ui2.TextStyle{ size: 18, bold: true, color: body_heading })
	children << ui2.label('', tr('grapher.equation_label'), ui2.rect(12, 44, 38, 28), ui2.TextStyle{ size: 12, color: body_text })
	children << app.field(0, 52, 44, width - 168)
	children << grapher_button('grapher.plot', 'grapher.plot', width - 104, 44, 92)
	column := (width - 24) / 4
	for index, key in ['grapher.xmin_label', 'grapher.xmax_label', 'grapher.ymin_label',
		'grapher.ymax_label']! {
		children << ui2.label('', tr(key), ui2.rect(f64(12 + index * column), 77, f64(column - 8), 18), ui2.TextStyle{ size: 11, color: body_muted })
		children << app.field(index + 1, 12 + index * column, 96, column - 8)
	}
	children << grapher_button('grapher.reset', 'grapher.reset', 12, 134, 94)
	children << grapher_button('grapher.zoom_in', 'grapher.zoom_in', 114, 134, 88)
	children << grapher_button('grapher.zoom_out', 'grapher.zoom_out', 210, 134, 88)
	if width >= 440 {
		children << ui2.label('', tr('grapher.radians'), ui2.rect(310, 134, f64(width - 322), 28), ui2.TextStyle{ size: 11, color: body_muted })
	}
	chart_width := width - 76
	chart_height := height - 282
	children << app.chart(chart_width, chart_height)
	if app.plotted {
		children << grapher_tick(app.range[3], 2, 174, 44, .right)
		children << grapher_tick(app.range[2], 2, 174 + chart_height - 18, 44, .right)
		children << grapher_tick(app.range[0], 52, 176 + chart_height, chart_width / 2, .left)
		children << grapher_tick(app.range[1], 52 + chart_width / 2, 176 + chart_height, chart_width / 2, .right)
	}
	children << ui2.label('', tr('grapher.syntax'), ui2.rect(12, f64(height - 86), f64(width - 24), 18), ui2.TextStyle{ size: 10, color: body_muted })
	children << app.field(5, 12, height - 62, width - 136)
	children << grapher_button('grapher.export', 'grapher.export', width - 116, height - 62, 104)
	status := if app.export_status.len > 0 { app.export_status } else { app.status }
	children << ui2.Element{
		...ui2.label('', tr(status), ui2.rect(12, f64(height - 27), f64(width - 24), 22), ui2.TextStyle{ size: 11, color: body_muted })
		tooltip: tr(status)
	}
	return ui2.view('grapher.body', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ bg: app_surface }, children)
}
