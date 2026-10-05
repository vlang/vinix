// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The built-in calculator's compile-time VML desktop adapter.
//
// The model comes from ui2's calculator example. The view is parsed and
// type-checked by V's `$vml` expression, which emits direct Element
// constructors; no VML parser or expression interpreter ships in the process.
module main

import ui2
import math

#include <stdio.h>

const calculator_history_limit = 20
const calculator_input_limit = 48
const calculator_button_texts = ['C', '%', '^', '÷', '7', '8', '9', '*', '4', '5', '6', '-', '1',
	'2', '3', '+', '0', '.', '±', '=']!
const calculator_history_actions = ['calculator.history.0', 'calculator.history.1',
	'calculator.history.2', 'calculator.history.3', 'calculator.history.4']

struct CalculatorHistoryEntry {
	expression string
	result     string
}

@[heap]
struct CalculatorApp {
mut:
	calculator         Calculator
	layout             ui2.Element
	layout_ready       bool
	width              f64
	height             f64
	panel_width        f64
	panel_x            f64
	panel_y            f64
	display_owned      bool
	history            []CalculatorHistoryEntry
	history_offset     int
	history_rows       int = 1
	memory             f64
	has_memory         bool
	input_percent      bool
	input_percent_rate f64
	last_percent       bool
	last_percent_rate  f64
}

fn new_calculator_app() &CalculatorApp {
	mut keys := []CalculatorKey{cap: 20}
	for index, text in calculator_button_texts {
		keys << CalculatorKey{ text: text, row: index / 4, column: index % 4 }
	}
	mut app := &CalculatorApp{ calculator: Calculator{ keys: keys } }
	unsafe { app.history.flags |= .noslices }
	return app
}

fn open_native_calculator() NativeApp {
	return new_calculator_app()
}

fn build_compiled_calculator(app &CalculatorApp) ui2.Element {
	return $vml('calculator_vinix.vml')
}

// Current `$vml` lowers a dynamic string expression to an interpolation that
// owns a temporary string. Substitute the model-owned display after the VML
// layout is built so the tree still has no parser or retained mutable state.
fn calculator_layout_with_display(element ui2.Element, display string) ui2.Element {
	if element.id == 'display' {
		return ui2.Element{
			...element
			text: display
		}
	}
	if element.children.len == 0 {
		return element
	}
	mut children := []ui2.Element{cap: element.children.len}
	unsafe { children.flags |= .noslices }
	for child in element.children {
		children << calculator_layout_with_display(child, display)
	}
	return ui2.Element{
		...element
		children: children
	}
}

// The `$vml` layout uses literals and owns only its child arrays. The adapted
// copy above owns its replacement arrays and is released by free_tree.
fn release_compiled_calculator_layout(element ui2.Element) {
	for child in element.children {
		release_compiled_calculator_layout(child)
	}
	if element.children.cap > 0 {
		unsafe { element.children.free() }
	}
}

fn (mut app CalculatorApp) build(size ui2.Rect) !ui2.Element {
	rebuild := !app.layout_ready || app.width != size.width || app.height != size.height
	if rebuild {
		if app.layout_ready {
			release_compiled_calculator_layout(app.layout)
		}
		app.width = size.width
		app.height = size.height
		available_width := size.width - 24
		app.panel_width = if available_width < 260 { available_width } else { 260 }
		app.panel_x = if size.width > app.panel_width {
			(size.width - app.panel_width) / 2
		} else {
			0
		}
		app.panel_y = if size.height >= 430 { 46 } else { 0 }
		app.layout = build_compiled_calculator(&app)
		app.layout_ready = true
	}
	// ui2 Elements are immutable declarations in current ui2. `$vml` lowers
	// the static layout once; each adapted frame owns replacement arrays while
	// the Calculator owns the display string.
	tree := calculator_layout_with_display(app.layout, app.calculator.display)
	if size.height >= 430 {
		return app.with_utility_controls(tree, size)
	}
	return tree
}

// The ui2 example's immutable display is adapted here with explicit ownership.
// Its arithmetic state and keys are retained, while replacing a display never
// leaves an old input or formatter's intermediate string allocated.
fn (mut app CalculatorApp) set_display(text string, owned bool) {
	if app.display_owned && app.calculator.display.str != text.str {
		unsafe { app.calculator.display.free() }
	}
	app.calculator.display = text
	app.display_owned = owned
}

fn calculator_number_text(value f64) string {
	mut buffer := [96]u8{}
	mut length := 0
	if value == 0 {
		return '0'.clone()
	}
	absolute := math.abs(value)
	unsafe {
		if absolute >= 1.0e12 || absolute < 1.0e-9 {
			length = C.snprintf(&char(&buffer[0]), 96, c'%.12g', value)
		} else {
			length = C.snprintf(&char(&buffer[0]), 96, c'%.10f', value)
			for length > 0 && buffer[length - 1] == `0` {
				length--
			}
			if length > 0 && buffer[length - 1] == `.` {
				length--
			}
		}
		return tos(&buffer[0], length).clone()
	}
}

fn (mut app CalculatorApp) clear_calculator() {
	app.set_display('0', false)
	app.calculator.clear()
	app.input_percent = false
	app.last_percent = false
}

fn (mut app CalculatorApp) fail_calculator() {
	app.set_display('Error', false)
	app.calculator.fail()
	app.input_percent = false
	app.last_percent = false
}

fn (mut app CalculatorApp) calculate(operator string, right f64) bool {
	result := calculate_binary(app.calculator.accumulator, right, operator) or {
		app.fail_calculator()
		return false
	}
	app.calculator.accumulator = result
	app.set_display(calculator_number_text(result), true)
	return true
}

fn (mut app CalculatorApp) remember_result(left f64, operator string, right f64) {
	left_text := calculator_number_text(left)
	right_text := calculator_number_text(right)
	expression := left_text + ' ' + operator + ' ' + right_text
	unsafe {
		left_text.free()
		right_text.free()
	}
	if app.history.len == calculator_history_limit {
		unsafe {
			app.history[0].expression.free()
			app.history[0].result.free()
		}
		app.history.delete(0)
	}
	app.history_offset = 0
	app.history << CalculatorHistoryEntry{ expression: expression, result: app.calculator.display.clone() }
}

fn (mut app CalculatorApp) clear_history() {
	for entry in app.history {
		unsafe {
			entry.expression.free()
			entry.result.free()
		}
	}
	app.history.clear()
	app.history_offset = 0
}

fn (mut app CalculatorApp) press(key string) {
	mut calculator := &app.calculator
	if key.len == 1 && key[0].is_digit() {
		app.input_percent = false
		if calculator.has_error {
			app.clear_calculator()
		}
		if calculator.replace_input || calculator.display == '0' {
			if calculator.replace_input && calculator.pending_operator.len == 0 {
				calculator.has_accumulator = false
			}
			app.set_display(key, false)
		} else if calculator.display.len < calculator_input_limit {
			app.set_display(calculator.display + key, true)
		}
		calculator.replace_input = false
		return
	}
	match key {
		'C' { app.clear_calculator() }
		'.' {
			app.input_percent = false
			if calculator.has_error { app.clear_calculator() }
			if calculator.replace_input {
				if calculator.pending_operator.len == 0 { calculator.has_accumulator = false }
				app.set_display('0.', false)
			} else if !calculator.display.contains('.') && calculator.display.len < calculator_input_limit {
				app.set_display(calculator.display + '.', true)
			}
			calculator.replace_input = false
		}
		'±', '%' {
			if !calculator.has_error {
				mut value := -calculator.display.f64()
				if key == '%' {
					app.input_percent_rate = calculator.display.f64() / 100
					app.input_percent = calculator.pending_operator == '+' || calculator.pending_operator == '-'
					value = if app.input_percent {
						calculator.accumulator * app.input_percent_rate
					} else {
						app.input_percent_rate
					}
				} else if app.input_percent {
					app.input_percent_rate = -app.input_percent_rate
				}
				if !math.is_finite(value) {
					app.fail_calculator()
					return
				}
				app.set_display(calculator_number_text(value), true)
				calculator.replace_input = false
			}
		}
		'+', '-', '*', '÷', '^' {
			if calculator.has_error { return }
			current := calculator.display.f64()
			if calculator.has_accumulator && calculator.pending_operator.len > 0 && !calculator.replace_input {
				if !app.calculate(calculator.pending_operator, current) { return }
			} else {
				calculator.accumulator = current
			}
			calculator.has_accumulator = true
			calculator.pending_operator = key
			calculator.last_operator = ''
			app.input_percent = false
			app.last_percent = false
			calculator.replace_input = true
		}
		'=' {
			if calculator.has_error { return }
			mut operator := calculator.pending_operator
			mut right := calculator.display.f64()
			if operator.len > 0 {
				if calculator.replace_input { right = calculator.accumulator }
				calculator.last_operator = operator
				calculator.last_operand = right
				app.last_percent = app.input_percent
				app.last_percent_rate = app.input_percent_rate
			} else {
				operator = calculator.last_operator
				right = calculator.last_operand
				calculator.accumulator = calculator.display.f64()
				if app.last_percent { right = calculator.accumulator * app.last_percent_rate }
			}
			if operator.len == 0 { return }
			left := calculator.accumulator
			if !app.calculate(operator, right) { return }
			app.remember_result(left, operator, right)
			calculator.pending_operator = ''
			app.input_percent = false
			calculator.replace_input = true
		}
		else {}
	}
}

fn (mut app CalculatorApp) backspace() {
	app.input_percent = false
	if app.calculator.has_error {
		app.clear_calculator()
		return
	}
	if app.calculator.replace_input { return }
	if app.calculator.display.contains('e') || app.calculator.display.contains('E') {
		app.set_display('0', false)
		return
	}
	text := app.calculator.display
	if text.len <= 1 || (text.len == 2 && text[0] == `-`) {
		app.set_display('0', false)
	} else {
		app.set_display(unsafe { tos(text.str, text.len - 1) }.clone(), true)
	}
}

fn (mut app CalculatorApp) key_input(text string) {
	mut at := 0
	for at < text.len {
		ch := text[at]
		// Navigation sequences are ignored as a whole, including their numeric
		// parameters, so Delete/Home never type an operand by accident.
		if ch == 0x1b && at + 1 < text.len && text[at + 1] == `[` {
			at += 2
			for at < text.len {
				final := text[at] >= 0x40 && text[at] <= 0x7e
				at++
				if final { break }
			}
			continue
		}
		key := match ch {
			`0` { '0' }
			`1` { '1' }
			`2` { '2' }
			`3` { '3' }
			`4` { '4' }
			`5` { '5' }
			`6` { '6' }
			`7` { '7' }
			`8` { '8' }
			`9` { '9' }
			`.` { '.' }
			`+` { '+' }
			`-` { '-' }
			`*`, `x`, `X` { '*' }
			`/` { '÷' }
			`^` { '^' }
			`%` { '%' }
			`=`, `\n`, `\r` { '=' }
			`c`, `C`, 0x1b { 'C' }
			else { '' }
		}
		if ch == 8 || ch == 127 { app.backspace() }
		if key.len > 0 { app.press(key) }
		at++
	}
}

// Pasted text is one numeric operand; control bytes and operators do not run
// commands. Invalid or non-finite input leaves the calculator unchanged.
fn (mut app CalculatorApp) paste_input(text string) {
	trimmed := text.trim_space()
	defer { unsafe { trimmed.free() } }
	if !calculator_valid_number(trimmed) { return }
	if app.calculator.has_error { app.clear_calculator() }
	if app.calculator.replace_input && app.calculator.pending_operator.len == 0 {
		app.calculator.has_accumulator = false
	}
	app.input_percent = false
	app.set_display(trimmed.clone(), true)
	app.calculator.replace_input = false
}

fn calculator_valid_number(text string) bool {
	if text.len == 0 || text.len > calculator_input_limit { return false }
	mut digits := 0
	mut decimal := false
	for index, ch in text {
		if ch.is_digit() {
			digits++
			continue
		}
		if index == 0 && (ch == `-` || ch == `+`) { continue }
		if ch == `.` && !decimal {
			decimal = true
			continue
		}
		return false
	}
	return digits > 0 && math.is_finite(text.f64())
}

fn calculator_utility_button(action string, text string, x f64, y f64, width f64) ui2.Element {
	return ui2.button(action, text, ui2.rect(x, y, width, 26), ui2.BoxStyle{
		bg:     settings_choice_bg
		radius: 5
	}, ui2.TextStyle{ color: body_text, size: 11, align: .center })
}

fn (mut app CalculatorApp) with_utility_controls(tree ui2.Element, size ui2.Rect) ui2.Element {
	// Transfer the adapted tree's array into the returned immutable element.
	mut children := unsafe { tree.children }
	x := app.panel_x
	width := app.panel_width
	button_width := (width - 24) / 5
	for index, action in ['calculator.memory.clear', 'calculator.memory.recall', 'calculator.memory.add',
		'calculator.memory.subtract', 'calculator.backspace']! {
		text := ['MC', 'MR', 'M+', 'M−', '⌫']![index]
		children << calculator_utility_button(action, text, x + f64(index) * (button_width + 6), 10, button_width)
	}
	children << ui2.label('', tr('calculator.history.title'), ui2.rect(x, 393, width - 116, 20),
		ui2.TextStyle{ color: body_heading, size: 12, bold: true })
	children << calculator_utility_button('calculator.history.clear', tr('calculator.history.clear'), x + width - 56, 390, 56)
	children << calculator_utility_button('calculator.history.previous', '‹', x + width - 110, 390, 22)
	children << calculator_utility_button('calculator.history.next', '›', x + width - 84, 390, 22)
	rows := int((size.height - 424) / 22)
	app.history_rows = if rows > 5 {
		5
	} else if rows < 1 {
		1
	} else {
		rows
	}
	if app.history_offset >= app.history.len { app.history_offset = 0 }
	for row in 0 .. rows {
		if row >= calculator_history_actions.len || row + app.history_offset >= app.history.len {
			break
		}
		entry := app.history[app.history.len - 1 - app.history_offset - row]
		text := entry.expression + ' = ' + entry.result
		children << ui2.button(calculator_history_actions[row], text, ui2.rect(x, f64(423 + row * 22), width, 20),
			ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text, size: 11, align: .right })
		// The string belongs to this frame, not to the bounded history.
		children[children.len - 1] = ui2.Element{ ...children.last(), id: frame_owned_text_id, action_id: calculator_history_actions[row] }
	}
	if app.has_memory {
		children << ui2.label('', tr('calculator.memory.indicator'), ui2.rect(x - 12, 10, 10, 26),
			ui2.TextStyle{ color: app_accent, size: 11, bold: true })
	}
	return ui2.Element{ ...tree, children: children }
}

fn (mut app CalculatorApp) handle(event_id string) ! {
	match event_id {
		'calculator.backspace' {
			app.backspace()
			return
		}
		'calculator.history.previous' {
			app.history_offset = if app.history_offset > app.history_rows {
				app.history_offset - app.history_rows
			} else {
				0
			}
			return
		}
		'calculator.history.next' {
			if app.history_offset + app.history_rows < app.history.len {
				app.history_offset += app.history_rows
			}
			return
		}
		'calculator.history.clear' {
			app.clear_history()
			return
		}
		'calculator.memory.clear' {
			app.memory = 0
			app.has_memory = false
			return
		}
		'calculator.memory.recall' {
			if app.has_memory {
				app.input_percent = false
				app.set_display(calculator_number_text(app.memory), true)
				app.calculator.has_error = false
				app.calculator.replace_input = false
			}
			return
		}
		'calculator.memory.add', 'calculator.memory.subtract' {
			if !app.calculator.has_error {
				value := app.calculator.display.f64()
				next := app.memory + if event_id == 'calculator.memory.add' {
					value
				} else {
					-value
				}
				if math.is_finite(next) {
					app.memory = next
					app.has_memory = true
				}
			}
			return
		}
		else {}
	}
	for row, action in calculator_history_actions {
		if action == event_id && row + app.history_offset < app.history.len {
			value := app.history[app.history.len - 1 - app.history_offset - row].result.clone()
			app.clear_calculator()
			app.set_display(value, true)
			app.calculator.replace_input = false
			return
		}
	}
	// Requests own event_id. Retain only model keys stored for its lifetime.
	for key in app.calculator.keys {
		if key.text == event_id {
			app.press(key.text)
			return
		}
	}
}

fn (mut app CalculatorApp) close_app() {
	if app.layout_ready {
		release_compiled_calculator_layout(app.layout)
		app.layout_ready = false
	}
	app.clear_history()
	if app.history.cap > 0 { unsafe { app.history.free() } }
	app.history = []CalculatorHistoryEntry{}
	app.set_display('0', false)
	if app.calculator.keys.cap > 0 { unsafe { app.calculator.keys.free() } }
	app.calculator = Calculator{}
}
