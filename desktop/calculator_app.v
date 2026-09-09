// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The built-in calculator's lightweight desktop adapter.
//
// The calculator model still comes verbatim from ui2's calculator example.
// Its fixed, twenty-button view is built directly here instead of starting the
// generic QML parser and expression runtime in every calculator process. That
// keeps a tiny utility tiny while preserving the example's layout and actions.
module main

import ui2

const calculator_actions = ['calculator.key.0', 'calculator.key.1', 'calculator.key.2',
	'calculator.key.3', 'calculator.key.4', 'calculator.key.5', 'calculator.key.6', 'calculator.key.7',
	'calculator.key.8', 'calculator.key.9', 'calculator.key.10', 'calculator.key.11',
	'calculator.key.12', 'calculator.key.13', 'calculator.key.14', 'calculator.key.15',
	'calculator.key.16', 'calculator.key.17', 'calculator.key.18', 'calculator.key.19']

const calculator_surface = u32(0xf1f5f9)
const calculator_panel = u32(0x1f2937)
const calculator_display = u32(0xffffff)
const calculator_text = u32(0x111827)
const calculator_clear = u32(0xef4444)
const calculator_operator = u32(0x3478d4)
const calculator_utility = u32(0xcbd5e1)
const calculator_digit = u32(0xf8fafc)

@[heap]
struct CalculatorApp {
mut:
	calculator Calculator
}

fn open_native_calculator() NativeApp {
	return &CalculatorApp{
		calculator: initial_calculator()
	}
}

fn calculator_key_background(role string) u32 {
	return match role {
		'clear' { calculator_clear }
		'operator' { calculator_operator }
		'utility' { calculator_utility }
		else { calculator_digit }
	}
}

fn calculator_key_text(role string) u32 {
	return if role == 'clear' || role == 'operator' {
		calculator_display
	} else {
		calculator_text
	}
}

fn (mut a CalculatorApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	available_width := width - 24
	panel_width := if available_width < 260 { available_width } else { 260 }
	panel_height := 340
	panel_x := if width > panel_width { (width - panel_width) / 2 } else { 0 }
	panel_y := if height > panel_height { (height - panel_height) / 2 } else { 0 }
	padding := 12
	spacing := 8
	content_width := panel_width - padding * 2
	button_width := (content_width - spacing * 3) / 4
	button_height := 44

	mut panel_children := frame_elements(a.calculator.keys.len + 1)
	panel_children << ui2.view('calculator.display.panel', ui2.rect(f64(padding), f64(padding), f64(content_width), 56), ui2.BoxStyle{
		bg: calculator_display
		radius: 8
	}, frame_child(ui2.label('calculator.display', a.calculator.display, ui2.rect(10, 0, f64(content_width - 20), 56), ui2.TextStyle{
		color: calculator_text
		size: 28
		align: .right
	})))

	for index, key in a.calculator.keys {
		if index >= calculator_actions.len {
			break
		}
		x := padding + key.column * (button_width + spacing)
		y := 76 + key.row * (button_height + spacing)
		panel_children << ui2.with_native_style(ui2.button(calculator_actions[index], key.text, ui2.rect(f64(x), f64(y), f64(button_width), f64(button_height)), ui2.BoxStyle{
			bg: calculator_key_background(key.role)
			radius: 8
		}, ui2.TextStyle{
			color: calculator_key_text(key.role)
			size: 18
			bold: key.text == '='
			align: .center
		}))
	}

	mut children := frame_elements(1)
	children << ui2.view('calculator', ui2.rect(f64(panel_x), f64(panel_y), f64(panel_width), f64(panel_height)), ui2.BoxStyle{
		bg: calculator_panel
		radius: 12
	}, panel_children)
	return ui2.screen(calculator_surface, children)
}

fn (mut a CalculatorApp) handle(event_id string) ! {
	for index, action in calculator_actions {
		if event_id == action && index < a.calculator.keys.len {
			a.calculator.press(a.calculator.keys[index].text)
			return
		}
	}
}
