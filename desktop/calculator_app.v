// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The built-in calculator's native desktop adapter.
// The model comes from ui2's calculator example; the original VML view remains
// compile-checked while the runtime keypad uses bounded, owned element lists.
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
const calculator_scientific_actions = ['calculator.scientific.sqrt', 'calculator.scientific.reciprocal',
	'calculator.scientific.square', 'calculator.scientific.sin', 'calculator.scientific.cos',
	'calculator.scientific.tan', 'calculator.scientific.asin', 'calculator.scientific.acos',
	'calculator.scientific.atan', 'calculator.scientific.ln', 'calculator.scientific.log',
	'calculator.scientific.exp', 'calculator.scientific.pi', 'calculator.scientific.e',
	'calculator.scientific.cube', 'calculator.scientific.cbrt', 'calculator.scientific.log2']!

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
	scientific         bool
	degrees            bool = true
	layout_scientific  bool
	scientific_operand bool
	scientific_status  string
	programmer         bool
	integer            CalculatorProgrammer
	copy_client        TextCopyClient
}

fn new_calculator_app() &CalculatorApp {
	mut keys := []CalculatorKey{cap: 20}
	for index, text in calculator_button_texts {
		keys << CalculatorKey{ text: text, row: index / 4, column: index % 4 }
	}
	mut app := &CalculatorApp{ calculator: Calculator{ keys: keys } }
	unsafe { app.history.flags |= .noslices }
	unsafe { app.integer.history.flags |= .noslices }
	return app
}

fn open_native_calculator() NativeApp {
	return new_calculator_app()
}

fn build_compiled_calculator(app &CalculatorApp) ui2.Element {
	return $vml('calculator_vinix.vml')
}

// V3 currently deep-clones each local Element appended by `$vml`, stranding
// the original nested arrays. Direct constructor results avoid those copies;
// the cached keypad owns only the three child arrays released below.
fn build_native_calculator_layout(app &CalculatorApp) ui2.Element {
	mut display_children := []ui2.Element{cap: 1}
	mut keys := []ui2.Element{cap: 21}
	mut children := []ui2.Element{cap: 1}
	unsafe {
		display_children.flags |= .noslices
		keys.flags |= .noslices
		children.flags |= .noslices
	}
	content_width := app.panel_width - 24
	display_children << ui2.label('display', '0', ui2.rect(10, 0, content_width - 20, 56),
		ui2.TextStyle{ color: 0x111827, size: 28, align: .right })
	keys << ui2.Element{
		kind: .view
		frame: ui2.rect(12, 12, content_width, 56)
		box: ui2.BoxStyle{ bg: 0xffffff, radius: 8 }
		children: display_children
	}
	button_width := (content_width - 24) / 4
	for index, text in calculator_button_texts {
		operator := text in ['÷', '*', '-', '+', '=']!
		keys << ui2.Element{
			...ui2.button(text, text, ui2.rect(12 + f64(index % 4) * (button_width + 8),
				76 + f64(index / 4) * 52, button_width, 44), ui2.BoxStyle{
				bg: if text == 'C' { u32(0xef4444) } else if operator { u32(0x3478d4) }
					else if text == '%' || text == '^' { u32(0xcbd5e1) } else { u32(0xf8fafc) }
				radius: 8
			}, ui2.TextStyle{
				color: if text == 'C' || operator { u32(0xffffff) } else { u32(0x111827) }
				size: 18
				bold: text == '='
				align: .center
			})
			action_id: text
			native_style: true
		}
	}
	children << ui2.Element{
		kind: .view
		id: 'calculator'
		frame: ui2.rect(app.panel_x, app.panel_y, app.panel_width, 340)
		box: ui2.BoxStyle{ bg: 0x1f2937, radius: 12 }
		children: keys
	}
	return ui2.Element{
		...ui2.screen(0xf1f5f9, children)
		id: 'root'
		frame: ui2.rect(0, 0, app.width, app.height)
	}
}

// Each adapted frame borrows the model-owned display and cached literal text.
fn calculator_layout_with_display(element ui2.Element, display string) ui2.Element {
	if element.id == 'display' {
		return ui2.Element{
			...element
			text:       display
			text_style: ui2.TextStyle{
				...element.text_style
				size: if display.len > 14 { 18 } else { 28 }
			}
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

// The native layout uses literals and owns only its child arrays. The adapted
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
	if app.programmer { return app.build_programmer(size) }
	if app.calculator.has_error { app.set_display(tr('calculator.error'), false) }
	if app.scientific && (size.width < 540 || size.height < 430) {
		mut children := frame_elements(10)
		app.mode_controls(mut children, size.width)
		app.copy_controls(mut children, ui2.rect(12, 206, 140, 26),
			ui2.rect(164, 206, size.width - 176, 26))
		children << ui2.label('', app.calculator.display, ui2.rect(12, 72, size.width - 24, 46),
			ui2.TextStyle{ size: 22, color: body_heading, align: .right })
		children << ui2.label('', tr('calculator.scientific.resize'), ui2.rect(12, 132, size.width - 24, 56),
			ui2.TextStyle{ size: 12, color: body_muted })
		return ui2.screen(app_surface, children)
	}
	rebuild := !app.layout_ready || app.width != size.width || app.height != size.height
		|| app.layout_scientific != app.scientific
	if rebuild {
		if app.layout_ready {
			release_compiled_calculator_layout(app.layout)
		}
		app.width = size.width
		app.height = size.height
		app.layout_scientific = app.scientific
		available_width := size.width - 24
		app.panel_width = if available_width < 260 { available_width } else { 260 }
		app.panel_x = if app.scientific && size.width >= 540 {
			(size.width - 508) / 2 + 248
		} else if size.width > app.panel_width {
			(size.width - app.panel_width) / 2
		} else {
			0
		}
		app.panel_y = if size.height >= 430 { 78 } else { 42 }
		app.layout = build_native_calculator_layout(&app)
		app.layout_ready = true
	}
	// ui2 Elements are immutable declarations. Cache the static layout once;
	// each adapted frame owns replacement arrays while
	// the Calculator owns the display string.
	tree := calculator_layout_with_display(app.layout, app.calculator.display)
	if size.height >= 430 {
		return app.with_utility_controls(tree, size)
	}
	// Short Basic windows retain their keypad; only the spare header rows are
	// used so Copy cannot cover either the display or an arithmetic key.
	mut children := unsafe { tree.children }
	app.copy_controls(mut children, ui2.rect(12, 10, 140, 26),
		ui2.rect(164, 10, size.width - 176, 26))
	return ui2.Element{ ...tree, children: children }
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

fn (app &CalculatorApp) number_text(value f64) string {
	if !app.scientific { return calculator_number_text(value) }
	mut buffer := [96]u8{}
	length := unsafe {
		C.snprintf(&char(&buffer[0]), 96, c'%.15g', if value == 0 {
			f64(0)
		} else {
			value
		})
	}
	return unsafe { tos(&buffer[0], if length > 0 && length < 96 { length } else { 0 }).clone() }
}

fn (mut app CalculatorApp) clear_calculator() {
	app.set_display('0', false)
	app.calculator.clear()
	app.input_percent = false
	app.last_percent = false
	app.scientific_operand = false
	app.scientific_status = ''
}

fn (mut app CalculatorApp) fail_calculator() {
	app.set_display('Error', false)
	app.calculator.fail()
	app.input_percent = false
	app.last_percent = false
	app.scientific_operand = false
	app.scientific_status = 'calculator.error.operation'
	app.set_display(tr('calculator.error'), false)
}

fn (mut app CalculatorApp) calculate(operator string, right f64) bool {
	result := calculate_binary(app.calculator.accumulator, right, operator) or {
		app.fail_calculator()
		return false
	}
	app.calculator.accumulator = result
	app.set_display(app.number_text(result), true)
	return true
}

fn (mut app CalculatorApp) remember_result(left f64, operator string, right f64) {
	left_text := app.number_text(left)
	right_text := app.number_text(right)
	expression := left_text + ' ' + operator + ' ' + right_text
	unsafe {
		left_text.free()
		right_text.free()
	}
	app.remember_expression(expression)
}

// The caller transfers this expression; result text is a separate owned copy.
fn (mut app CalculatorApp) remember_expression(expression string) {
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

fn calculator_scientific_value(action string, value f64, degrees bool) (f64, string) {
	if !math.is_finite(value) { return 0, 'calculator.error.nonfinite' }
	if (action == 'calculator.scientific.sqrt' && value < 0)
		|| (action == 'calculator.scientific.reciprocal' && value == 0)
		|| ((action == 'calculator.scientific.ln' || action == 'calculator.scientific.log'
			|| action == 'calculator.scientific.log2') && value <= 0)
		|| ((action == 'calculator.scientific.asin' || action == 'calculator.scientific.acos') && math.abs(value) > 1) {
		return 0, 'calculator.error.domain'
	}
	angle := if degrees { value * (math.pi / 180) } else { value }
	if action == 'calculator.scientific.tan' && math.abs(math.cos(angle)) < 1e-12 {
		return 0, 'calculator.error.tangent'
	}
	result := match action {
		'calculator.scientific.sqrt' { math.sqrt(value) }
		'calculator.scientific.reciprocal' { 1 / value }
		'calculator.scientific.square' { value * value }
		'calculator.scientific.cube' { value * value * value }
		'calculator.scientific.cbrt' { math.cbrt(value) }
		'calculator.scientific.log2' { math.log2(value) }
		'calculator.scientific.sin' { math.sin(angle) }
		'calculator.scientific.cos' { math.cos(angle) }
		'calculator.scientific.tan' { math.tan(angle) }
		'calculator.scientific.asin' {
			math.asin(value) * if degrees { 180 / math.pi } else { f64(1) }
		}
		'calculator.scientific.acos' {
			math.acos(value) * if degrees { 180 / math.pi } else { f64(1) }
		}
		'calculator.scientific.atan' {
			math.atan(value) * if degrees { 180 / math.pi } else { f64(1) }
		}
		'calculator.scientific.ln' { math.log(value) }
		'calculator.scientific.log' { math.log10(value) }
		'calculator.scientific.exp' { math.exp(value) }
		else { return 0, 'calculator.error.operation' }
	}
	return if math.is_finite(result) { result } else { f64(0) }, if math.is_finite(result) {
		''
	} else {
		'calculator.error.nonfinite'
	}
}

fn (mut app CalculatorApp) scientific_apply(action string) {
	if !app.scientific { return }
	constant := action == 'calculator.scientific.pi' || action == 'calculator.scientific.e'
	if app.calculator.has_error {
		if constant { app.clear_calculator() } else { return }
	}
	input := app.calculator.display.f64()
	mut result := if action == 'calculator.scientific.pi' { math.pi } else { math.e }
	if !constant {
		value, status := calculator_scientific_value(action, input, app.degrees)
		if status.len > 0 {
			app.fail_calculator()
			app.scientific_status = status
			return
		}
		result = value
	}
	app.set_display(app.number_text(result), true)
	app.scientific_status = ''
	app.input_percent = false
	app.last_percent = false
	app.calculator.last_operator = ''
	app.calculator.last_operand = 0
	// replace_input makes a new digit replace the transformed value. This flag
	// separately says that a pending binary operation has a real right operand.
	app.scientific_operand = true
	app.calculator.replace_input = true
	if app.calculator.pending_operator.len == 0 {
		app.calculator.accumulator = result
		app.calculator.has_accumulator = true
	}
	mut expression := ''
	if constant {
		expression = tr(action).clone()
	} else {
		argument := app.number_text(input)
		expression = match action {
			'calculator.scientific.reciprocal' { '1 / (' + argument + ')' }
			'calculator.scientific.square' { '(' + argument + ')^2' }
			'calculator.scientific.cube' { '(' + argument + ')^3' }
			else { tr(action) + '(' + argument + ')' }
		}
		unsafe { argument.free() }
		if action in ['calculator.scientific.sin', 'calculator.scientific.cos',
			'calculator.scientific.tan', 'calculator.scientific.asin', 'calculator.scientific.acos',
			'calculator.scientific.atan']! {
			unit := tr(if app.degrees {
				'calculator.angle.degrees'
			} else {
				'calculator.angle.radians'
			})
			with_unit := expression + ' [' + unit + ']'
			unsafe { expression.free() }
			expression = with_unit
		}
	}
	app.remember_expression(expression)
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
		app.scientific_operand = false
		app.scientific_status = ''
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
			app.scientific_operand = false
			app.scientific_status = ''
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
				app.set_display(app.number_text(value), true)
				app.scientific_operand = false
				calculator.replace_input = false
			}
		}
		'+', '-', '*', '÷', '^' {
			if calculator.has_error { return }
			current := calculator.display.f64()
			if calculator.has_accumulator && calculator.pending_operator.len > 0
				&& (!calculator.replace_input || app.scientific_operand) {
				if !app.calculate(calculator.pending_operator, current) { return }
			} else {
				calculator.accumulator = current
			}
			calculator.has_accumulator = true
			calculator.pending_operator = key
			calculator.last_operator = ''
			app.input_percent = false
			app.last_percent = false
			app.scientific_operand = false
			calculator.replace_input = true
		}
		'=' {
			if calculator.has_error { return }
			mut operator := calculator.pending_operator
			mut right := calculator.display.f64()
			if operator.len > 0 {
				if calculator.replace_input && !app.scientific_operand {
					right = calculator.accumulator
				}
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
			app.scientific_operand = false
			calculator.replace_input = true
		}
		else {}
	}
}

fn (mut app CalculatorApp) backspace() {
	app.input_percent = false
	app.scientific_status = ''
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
	app.copy_client.clear_status()
	mut at := 0
	for at < text.len {
		ch := text[at]
		if ch == 0x03 {
			app.copy_result()
			at++
			continue
		}
		if ch == 0x10 {
			app.programmer = !app.programmer
			at++
			continue
		}
		if ch == 0x13 {
			app.programmer = false
			app.scientific = !app.scientific
			at++
			continue
		}
		if ch == 0x02 && app.programmer {
			app.integer.next_base()
			at++
			continue
		}
		if ch == 0x04 {
			if app.scientific && !app.programmer { app.degrees = !app.degrees }
			at++
			continue
		}
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
		if app.programmer {
			app.integer.key(ch)
			at++
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
	app.copy_client.clear_status()
	if app.programmer {
		app.integer.paste(text)
		return
	}
	trimmed := text.trim_space()
	defer { unsafe { trimmed.free() } }
	if !calculator_valid_number(trimmed)
		&& !(app.scientific && calculator_valid_scientific_number(trimmed)) {
		return
	}
	if app.calculator.has_error { app.clear_calculator() }
	if app.calculator.replace_input && app.calculator.pending_operator.len == 0 {
		app.calculator.has_accumulator = false
	}
	app.input_percent = false
	app.scientific_operand = false
	app.scientific_status = ''
	app.set_display(trimmed.clone(), true)
	app.calculator.replace_input = app.scientific && (trimmed.contains('e') || trimmed.contains('E'))
	app.scientific_operand = app.calculator.replace_input
}

fn calculator_valid_scientific_number(text string) bool {
	if text.len == 0 || text.len > calculator_input_limit { return false }
	mut at := 0
	if text[0] == `+` || text[0] == `-` { at++ }
	mut digits := 0
	mut decimal := false
	for at < text.len && text[at] != `e` && text[at] != `E` {
		ch := text[at]
		if ch.is_digit() {
			digits++
		} else if ch == `.` && !decimal {
			decimal = true
		} else {
			return false
		}
		at++
	}
	if digits == 0 || at == text.len { return false }
	at++
	if at < text.len && (text[at] == `+` || text[at] == `-`) { at++ }
	start := at
	for at < text.len {
		if !text[at].is_digit() { return false }
		at++
	}
	return at > start && math.is_finite(text.f64())
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

fn calculator_mode_button(action string, selected bool, x f64, width f64, font_size int) ui2.Element {
	return ui2.Element{
		...ui2.button(action, tr(action), ui2.rect(x, 10, width, 26), ui2.BoxStyle{
			bg:     if selected { app_accent } else { settings_choice_bg }
			radius: 5
		}, ui2.TextStyle{ color: if selected { app_on_accent } else { body_text }, size: font_size, align: .center })
		tooltip: tr(if action == 'calculator.mode.programmer' {
			'calculator.programmer.shortcuts'
		} else {
			'calculator.scientific.shortcuts'
		})
	}
}

fn (app &CalculatorApp) mode_controls(mut children []ui2.Element, width f64) {
	compact_basic := !app.scientific && !app.programmer && width < 480
	available := if width > 42 { width - 42 } else { f64(0) }
	factor := if compact_basic { available / 444 } else if width >= 340 { f64(1) }
		else { if width > 36 { (width - 36) / 304 } else { f64(0) } }
	font_size := if compact_basic { 9 } else { 11 }
	children << calculator_mode_button('calculator.mode.basic', !app.scientific && !app.programmer, 12, 72 * factor, font_size)
	children << calculator_mode_button('calculator.mode.scientific', app.scientific && !app.programmer, 18 + 72 * factor, 116 * factor, font_size)
	children << calculator_mode_button('calculator.mode.programmer', app.programmer, 24 + 188 * factor, 116 * factor, font_size)
	if app.scientific && !app.programmer && width >= 480 {
		children << calculator_mode_button('calculator.angle.degrees', app.degrees, width - 124, 54, 11)
		children << calculator_mode_button('calculator.angle.radians', !app.degrees, width - 64, 54, 11)
	}
}

fn (mut app CalculatorApp) with_utility_controls(tree ui2.Element, size ui2.Rect) ui2.Element {
	// Transfer the adapted tree's array into the returned immutable element.
	mut children := unsafe { tree.children }
	app.mode_controls(mut children, size.width)
	x := app.panel_x
	width := app.panel_width
	compact_basic := !app.scientific && size.width < 480
	if app.scientific {
		app.copy_controls(mut children, ui2.rect(x - 248, 42, 232, 26),
			ui2.rect(x - 140, 86, 124, 24))
	} else if compact_basic {
		factor := if size.width > 42 { (size.width - 42) / 444 } else { f64(0) }
		app.copy_controls(mut children, ui2.rect(30 + 304 * factor, 10, 140 * factor, 26),
			ui2.rect(0, 0, 0, 0))
	} else {
		copy_width := if size.width >= 486 { f64(140) } else { size.width - 346 }
		app.copy_controls(mut children, ui2.rect(334, 10, copy_width, 26),
			ui2.rect(12, 42, if x > 24 { x - 24 } else { 0 }, 26))
	}
	button_width := (width - 24) / 5
	for index, action in ['calculator.memory.clear', 'calculator.memory.recall', 'calculator.memory.add',
		'calculator.memory.subtract', 'calculator.backspace']! {
		// Use signs covered by the desktop's baked font atlases.
		text := ['MC', 'MR', 'M+', 'M−', '<-']![index]
		children << calculator_utility_button(action, text, x + f64(index) * (button_width + 6), 42, button_width)
	}
	if app.scientific {
		left := x - 248
		children << ui2.label('', tr('calculator.mode.scientific'), ui2.rect(left, 86, 100, 24),
			ui2.TextStyle{ size: 13, bold: true, color: body_heading })
		key := if app.scientific_status.len > 0 {
			app.scientific_status
		} else {
			'calculator.scientific.instructions'
		}
		children << ui2.Element{
			...ui2.label('', tr(key), ui2.rect(left, 116, 232, 30),
				ui2.TextStyle{
					size:  11
					color: if app.calculator.has_error {
						files_error
					} else {
						body_muted
					}
				})
			tooltip: tr(key)
		}
		for index, action in calculator_scientific_actions {
			children << ui2.button(action, tr(action), ui2.rect(left + f64(index % 3) * 80,
				154 + f64(index / 3) * 44, 72, 36), ui2.BoxStyle{ bg: settings_choice_bg, radius: 6 },
				ui2.TextStyle{ size: 13, color: body_text, align: .center })
		}
	}
	history_x := if app.scientific { x - 248 } else { x }
	history_width := if app.scientific { width + 248 } else { width }
	children << ui2.label('', tr('calculator.history.title'), ui2.rect(history_x, 425, history_width - 116, 20),
		ui2.TextStyle{ color: body_heading, size: 12, bold: true })
	children << calculator_utility_button('calculator.history.clear', tr('calculator.history.clear'), history_x + history_width - 56, 422, 56)
	children << calculator_utility_button('calculator.history.previous', '<', history_x + history_width - 110, 422, 22)
	children << calculator_utility_button('calculator.history.next', '>', history_x + history_width - 84, 422, 22)
	rows := int((size.height - 456) / 22)
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
		children << ui2.button(calculator_history_actions[row], text, ui2.rect(history_x, f64(455 + row * 22), history_width, 20),
			ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text, size: 11, align: .right })
		// The string belongs to this frame, not to the bounded history.
		children[children.len - 1] = ui2.Element{ ...children.last(), id: frame_owned_text_id, action_id: calculator_history_actions[row] }
	}
	if app.has_memory {
		children << ui2.label('', tr('calculator.memory.indicator'), ui2.rect(x - 12, 42, 10, 26),
			ui2.TextStyle{ color: app_accent, size: 11, bold: true })
	}
	return ui2.Element{ ...tree, children: children }
}

fn (mut app CalculatorApp) handle(event_id string) ! {
	if event_id == 'calculator.copy' {
		app.copy_result()
		return
	}
	app.copy_client.clear_status()
	if event_id == 'calculator.mode.programmer' {
		app.programmer = true
		return
	}
	if app.programmer && event_id != 'calculator.mode.basic'
		&& event_id != 'calculator.mode.scientific' {
		app.integer.handle(event_id)
		return
	}
	match event_id {
		'calculator.mode.basic' {
			app.programmer = false
			app.scientific = false
			return
		}
		'calculator.mode.scientific' {
			app.programmer = false
			app.scientific = true
			return
		}
		'calculator.angle.degrees' {
			app.degrees = true
			return
		}
		'calculator.angle.radians' {
			app.degrees = false
			return
		}
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
				app.set_display(app.number_text(app.memory), true)
				app.scientific_operand = false
				app.scientific_status = ''
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
	for action in calculator_scientific_actions {
		if event_id == action {
			app.scientific_apply(action)
			return
		}
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
	app.copy_client.close()
	app.integer.close()
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
