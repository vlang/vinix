// SPDX-License-Identifier: GPL-2.0-or-later
// EE edits the displayed operand. Root uses the existing pending binary state.
module main

import math
import ui2

#include <stdlib.h>

fn C.strtod(text &char, end &&char) f64

// The ordinary V parser flushes some valid subnormal scientific inputs to zero.
// Use libm's companion parser on a bounded, terminated stack copy instead.
fn calculator_numeric_value(text string) f64 {
	if text.len == 0 || text.len > calculator_input_limit { return math.nan() }
	mut buffer := [calculator_input_limit + 1]u8{}
	for index, ch in text { buffer[index] = ch }
	return unsafe { C.strtod(&char(&buffer[0]), nil) }
}

fn calculator_exponent_at(text string) int {
	for index, ch in text {
		if ch == `e` || ch == `E` { return index }
	}
	return -1
}

fn calculator_exponent_negative(text string) bool {
	at := calculator_exponent_at(text)
	return at >= 0 && at + 1 < text.len && text[at + 1] == `-`
}

fn calculator_exponent_has_digits(text string) bool {
	at := calculator_exponent_at(text)
	return at >= 0 && text.len > at + 1 && text[text.len - 1].is_digit()
}

fn (mut app CalculatorApp) begin_exponent() {
	if !app.scientific || app.calculator.has_error { return }
	if app.calculator.replace_input && app.calculator.pending_operator.len > 0
		&& !app.scientific_operand {
		app.set_display('0e', false)
	} else if calculator_exponent_at(app.calculator.display) < 0 {
		// Reserve space for at least one exponent digit. Repeated EE never
		// introduces a second separator or changes a full-length operand.
		if app.calculator.display.len >= calculator_input_limit - 1 { return }
		app.set_display(app.calculator.display + 'e', true)
	}
	app.exponent_input = true
	app.input_percent = false
	app.scientific_operand = false
	app.scientific_status = ''
	app.calculator.replace_input = false
}

// The display owns the only allocated copy. The bounded stack buffer prevents
// slices and concatenation temporaries while inserting/removing an exponent sign.
fn (mut app CalculatorApp) change_exponent_sign(negative bool) {
	text := app.calculator.display
	at := calculator_exponent_at(text)
	if at < 0 { return }
	mut start := at + 1
	if start < text.len && (text[start] == `+` || text[start] == `-`) { start++ }
	length := at + 1 + if negative { 1 } else { 0 } + text.len - start
	if length > calculator_input_limit { return }
	mut buffer := [calculator_input_limit]u8{}
	for index in 0 .. at + 1 { buffer[index] = text[index] }
	mut end := at + 1
	if negative { buffer[end] = `-` end++ }
	for index in start .. text.len { buffer[end] = text[index] end++ }
	app.set_display(unsafe { tos(&buffer[0], end) }.clone(), true)
}

// Incomplete and overflowing EE operands can be repaired with Backspace, but
// cannot enter arithmetic, memory or a unary operation through f64's parser.
fn (mut app CalculatorApp) commit_exponent() bool {
	if !app.exponent_input { return true }
	text := app.calculator.display
	if !calculator_valid_scientific_number(text) {
		incomplete := !calculator_exponent_has_digits(text)
		app.fail_calculator()
		app.scientific_status = if incomplete { 'calculator.error.exponent' }
			else { 'calculator.error.nonfinite' }
		return false
	}
	app.exponent_input = false
	return true
}

fn calculator_nth_root(radicand f64, degree f64) (f64, string) {
	if !math.is_finite(radicand) || !math.is_finite(degree) {
		return 0, 'calculator.error.nonfinite'
	}
	if degree == 0 || (radicand == 0 && degree < 0)
		|| (radicand < 0 && (math.trunc(degree) != degree || math.fmod(math.abs(degree), 2) != 1)) {
		return 0, 'calculator.error.domain'
	}
	result := if radicand == 0 { f64(0) }
		else if degree == 1 { radicand }
		else if degree == -1 { 1 / radicand }
		else { math.pow(math.abs(radicand), 1 / degree) * if radicand < 0 { f64(-1) } else { f64(1) } }
	return if math.is_finite(result) { result } else { f64(0) },
		if math.is_finite(result) { '' } else { 'calculator.error.nonfinite' }
}

fn calculator_scientific_button(action string, index int, left f64) ui2.Element {
	return ui2.Element{
		...ui2.button(action, tr(action), ui2.rect(left + f64(index % 5) * 48,
			154 + f64(index / 5) * 44, 40, 36), ui2.BoxStyle{ bg: settings_choice_bg, radius: 6 },
			ui2.TextStyle{ size: 12, color: body_text, align: .center })
		tooltip: tr(if action == 'calculator.scientific.ee' { 'calculator.scientific.ee.help' }
			else if action == 'calculator.scientific.root' { 'calculator.scientific.root.help' }
			else { action })
	}
}
