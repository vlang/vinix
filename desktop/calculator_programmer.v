// SPDX-License-Identifier: GPL-2.0-or-later
// The integer model never converts through f64. Unsigned arithmetic wraps at
// the selected 8/16/32/64-bit width; right shifts are logical. Narrowing drops
// high bits of live operands, while history keeps each result's original width.
module main

const calculator_programmer_max = u64(0xffffffffffffffff)
const calculator_programmer_digit_actions = ['calculator.programmer.digit.0',
	'calculator.programmer.digit.1', 'calculator.programmer.digit.2',
	'calculator.programmer.digit.3', 'calculator.programmer.digit.4',
	'calculator.programmer.digit.5', 'calculator.programmer.digit.6',
	'calculator.programmer.digit.7', 'calculator.programmer.digit.8',
	'calculator.programmer.digit.9', 'calculator.programmer.digit.A',
	'calculator.programmer.digit.B', 'calculator.programmer.digit.C',
	'calculator.programmer.digit.D', 'calculator.programmer.digit.E',
	'calculator.programmer.digit.F']!
const calculator_programmer_base_actions = ['calculator.programmer.base.dec',
	'calculator.programmer.base.hex', 'calculator.programmer.base.oct',
	'calculator.programmer.base.bin']!
const calculator_programmer_bases = [10, 16, 8, 2]!
const calculator_programmer_widths = [8, 16, 32, 64]!
const calculator_programmer_width_actions = ['calculator.programmer.width.8',
	'calculator.programmer.width.16', 'calculator.programmer.width.32',
	'calculator.programmer.width.64']!
const calculator_programmer_history_actions = ['calculator.programmer.history.0',
	'calculator.programmer.history.1', 'calculator.programmer.history.2',
	'calculator.programmer.history.3', 'calculator.programmer.history.4']!

enum CalculatorIntegerOperation {
	none
	add
	subtract
	multiply
	divide
	remainder
	bit_and
	bit_or
	bit_xor
	shift_left
	shift_right
}

struct CalculatorIntegerHistory {
	expression string
	value u64
	width int = 64
}

struct CalculatorProgrammer {
mut:
	value u64
	base int = 10
	width int = 64
	decimal_text string = '0'
	hex_text string = '0'
	octal_text string = '0'
	binary_text string = '0'
	texts_owned bool
	accumulator u64
	pending CalculatorIntegerOperation
	last_operator CalculatorIntegerOperation
	last_operand u64
	has_accumulator bool
	replace_input bool = true
	operand_ready bool
	has_error bool
	status string
	history []CalculatorIntegerHistory
	history_offset int
	history_rows int = 1
}

fn calculator_integer_digit(ch u8) int {
	if ch >= `0` && ch <= `9` { return int(ch - `0`) }
	if ch >= `A` && ch <= `F` { return int(ch - `A`) + 10 }
	if ch >= `a` && ch <= `f` { return int(ch - `a`) + 10 }
	return -1
}

// Prefixes are allowed for a pasted single operand, regardless of the active
// display base. Leading signs, whitespace within a number and commands fail.
fn calculator_integer_parse(text string, selected_base int) (u64, string) {
	return calculator_integer_parse_width(text, selected_base, 64)
}

fn calculator_integer_mask(width int) u64 {
	// Validate before shifting so neither negative nor 64-bit shifts occur.
	if width !in calculator_programmer_widths { return calculator_programmer_max }
	return calculator_programmer_max >> u32(64 - width)
}

fn calculator_integer_width_action(width int) string {
	for index, candidate in calculator_programmer_widths {
		if width == candidate { return calculator_programmer_width_actions[index] }
	}
	return calculator_programmer_width_actions[3]
}

fn calculator_integer_parse_width(text string, selected_base int, width int) (u64, string) {
	if text.len == 0 || text.len > 66 || selected_base !in calculator_programmer_bases
		|| width !in calculator_programmer_widths {
		return 0, 'calculator.programmer.error.input'
	}
	maximum := calculator_integer_mask(width)
	mut base := selected_base
	mut at := 0
	if text.len >= 2 && text[0] == `0` {
		prefix := text[1]
		if prefix == `x` || prefix == `X` {
			base = 16
			at = 2
		} else if prefix == `o` || prefix == `O` {
			base = 8
			at = 2
		} else if prefix == `b` || prefix == `B` {
			base = 2
			at = 2
		}
	}
	if at == text.len { return 0, 'calculator.programmer.error.input' }
	mut result := u64(0)
	for at < text.len {
		digit := calculator_integer_digit(text[at])
		if digit < 0 { return 0, 'calculator.programmer.error.input' }
		if digit >= base { return 0, 'calculator.programmer.error.digit' }
		if result > (maximum - u64(digit)) / u64(base) {
			return 0, 'calculator.programmer.error.range'
		}
		result = result * u64(base) + u64(digit)
		at++
	}
	return result, ''
}

// Exactly one owned result, including zero. The stack buffer is borrowed only
// while cloning its used suffix; no integer interpolation or signed casts.
fn calculator_integer_text(value u64, base int) string {
	mut buffer := [65]u8{}
	mut at := 64
	mut remaining := value
	for {
		at--
		digit := u8(remaining % u64(base))
		buffer[at] = if digit < 10 { `0` + digit } else { `A` + digit - 10 }
		remaining /= u64(base)
		if remaining == 0 { break }
	}
	return unsafe { tos(&buffer[at], 64 - at).clone() }
}

fn (state &CalculatorProgrammer) text(base int) string {
	return match base {
		16 { state.hex_text }
		8 { state.octal_text }
		2 { state.binary_text }
		else { state.decimal_text }
	}
}

fn (mut state CalculatorProgrammer) free_texts() {
	if state.texts_owned {
		unsafe {
			state.decimal_text.free()
			state.hex_text.free()
			state.octal_text.free()
			state.binary_text.free()
		}
	}
	state.decimal_text = '0'
	state.hex_text = '0'
	state.octal_text = '0'
	state.binary_text = '0'
	state.texts_owned = false
}

fn (mut state CalculatorProgrammer) set_value(value u64) {
	masked := value & calculator_integer_mask(state.width)
	decimal := calculator_integer_text(masked, 10)
	hex := calculator_integer_text(masked, 16)
	octal := calculator_integer_text(masked, 8)
	binary := calculator_integer_text(masked, 2)
	state.free_texts()
	state.value = masked
	state.decimal_text = decimal
	state.hex_text = hex
	state.octal_text = octal
	state.binary_text = binary
	state.texts_owned = true
}

// A width change alters representations only. Pending operations, repeat
// state, entry flags, errors and base survive; widening zero-extends. AC keeps
// the selected width. Saved history values and widths are never truncated.
fn (mut state CalculatorProgrammer) set_width(width int) {
	if width !in calculator_programmer_widths || width == state.width { return }
	state.width = width
	mask := calculator_integer_mask(width)
	state.accumulator &= mask
	state.last_operand &= mask
	state.set_value(state.value)
}

fn (mut state CalculatorProgrammer) clear() {
	state.free_texts()
	state.value = 0
	state.accumulator = 0
	state.pending = .none
	state.last_operator = .none
	state.last_operand = 0
	state.has_accumulator = false
	state.replace_input = true
	state.operand_ready = false
	state.has_error = false
	state.status = ''
}

fn (mut state CalculatorProgrammer) next_base() {
	state.base = match state.base {
		10 { 16 }
		16 { 8 }
		8 { 2 }
		else { 10 }
	}
}

fn (mut state CalculatorProgrammer) digit(digit int) {
	if digit < 0 || digit >= state.base {
		state.status = 'calculator.programmer.error.digit'
		return
	}
	if state.has_error { state.clear() }
	left := if state.replace_input { u64(0) } else { state.value }
	if left > (calculator_integer_mask(state.width) - u64(digit)) / u64(state.base) {
		state.status = 'calculator.programmer.error.range'
		return
	}
	if state.replace_input && state.pending == .none { state.has_accumulator = false }
	state.set_value(left * u64(state.base) + u64(digit))
	state.replace_input = false
	state.operand_ready = true
	state.status = ''
}

fn (mut state CalculatorProgrammer) paste(text string) {
	trimmed := text.trim_space()
	defer { unsafe { trimmed.free() } }
	value, status := calculator_integer_parse_width(trimmed, state.base, state.width)
	if status.len > 0 {
		state.status = status
		return
	}
	if state.has_error { state.clear() }
	if state.replace_input && state.pending == .none { state.has_accumulator = false }
	state.set_value(value)
	state.replace_input = false
	state.operand_ready = true
	state.status = ''
}

fn (mut state CalculatorProgrammer) backspace() {
	if state.has_error { state.clear(); return }
	if state.replace_input { return }
	state.set_value(state.value / u64(state.base))
	state.status = ''
	state.operand_ready = true
}

fn calculator_integer_result(left u64, right u64, operation CalculatorIntegerOperation) (u64, string) {
	return calculator_integer_result_width(left, right, operation, 64)
}

fn calculator_integer_result_width(left u64, right u64, operation CalculatorIntegerOperation, width int) (u64, string) {
	if width !in calculator_programmer_widths { return 0, 'calculator.programmer.error.input' }
	mask := calculator_integer_mask(width)
	lhs := left & mask
	rhs := right & mask
	if (operation == .divide || operation == .remainder) && rhs == 0 {
		return 0, 'calculator.programmer.error.zero'
	}
	if (operation == .shift_left || operation == .shift_right) && right >= u64(width) {
		return 0, 'calculator.programmer.error.shift'
	}
	result := match operation {
		.add { lhs + rhs }
		.subtract { lhs - rhs }
		.multiply { lhs * rhs }
		.divide { lhs / rhs }
		.remainder { lhs % rhs }
		.bit_and { lhs & rhs }
		.bit_or { lhs | rhs }
		.bit_xor { lhs ^ rhs }
		.shift_left { lhs << int(right) }
		.shift_right { lhs >> int(right) }
		else { lhs }
	}
	return result & mask, ''
}

fn calculator_integer_operator(operation CalculatorIntegerOperation) string {
	return match operation {
		.add { '+' }
		.subtract { '-' }
		.multiply { '*' }
		.divide { '/' }
		.remainder { '%' }
		.bit_and { 'AND' }
		.bit_or { 'OR' }
		.bit_xor { 'XOR' }
		.shift_left { '<<' }
		.shift_right { '>>' }
		else { '' }
	}
}

fn (mut state CalculatorProgrammer) remember(expression string) {
	if state.history.len == calculator_history_limit {
		unsafe { state.history[0].expression.free() }
		state.history.delete(0)
	}
	state.history << CalculatorIntegerHistory{ expression: expression, value: state.value, width: state.width }
	state.history_offset = 0
}

fn (mut state CalculatorProgrammer) remember_binary(left u64, right u64, operation CalculatorIntegerOperation) {
	left_text := calculator_integer_text(left, 10)
	right_text := calculator_integer_text(right, 10)
	expression := left_text + ' ' + calculator_integer_operator(operation) + ' ' + right_text
	unsafe { left_text.free(); right_text.free() }
	state.remember(expression)
}

fn (mut state CalculatorProgrammer) evaluate(operation CalculatorIntegerOperation, right u64) bool {
	result, status := calculator_integer_result_width(state.accumulator, right, operation, state.width)
	if status.len > 0 {
		state.status = status
		state.has_error = true
		return false
	}
	state.set_value(result)
	state.accumulator = result
	state.status = ''
	return true
}

fn (mut state CalculatorProgrammer) operator(operation CalculatorIntegerOperation) {
	if state.has_error { return }
	if state.has_accumulator && state.pending != .none && state.operand_ready {
		if !state.evaluate(state.pending, state.value) { return }
	} else if !state.has_accumulator || state.pending == .none {
		state.accumulator = state.value
	}
	state.has_accumulator = true
	state.pending = operation
	state.last_operator = .none
	state.replace_input = true
	state.operand_ready = false
	state.status = ''
}

fn (mut state CalculatorProgrammer) equals() {
	if state.has_error { return }
	operation := if state.pending != .none { state.pending } else { state.last_operator }
	if operation == .none { return }
	right := if state.pending != .none {
		if state.operand_ready { state.value } else { state.accumulator }
	} else {
		state.last_operand
	}
	if state.pending == .none { state.accumulator = state.value }
	left := state.accumulator
	if !state.evaluate(operation, right) { return }
	state.remember_binary(left, right, operation)
	state.last_operator = operation
	state.last_operand = right
	state.pending = .none
	state.replace_input = true
	state.operand_ready = false
}

fn (mut state CalculatorProgrammer) bit_not() {
	if state.has_error { return }
	before := calculator_integer_text(state.value, 10)
	state.set_value(state.value ^ calculator_integer_mask(state.width))
	expression := 'NOT ' + before
	unsafe { before.free() }
	state.remember(expression)
	state.last_operator = .none
	state.replace_input = true
	state.operand_ready = true
	state.status = ''
	if state.pending == .none {
		state.accumulator = state.value
		state.has_accumulator = true
	}
}

fn (mut state CalculatorProgrammer) clear_history() {
	for item in state.history { unsafe { item.expression.free() } }
	state.history.clear()
	state.history_offset = 0
}

fn (mut state CalculatorProgrammer) key(ch u8) {
	digit := calculator_integer_digit(ch)
	if digit >= 0 { state.digit(digit); return }
	match ch {
		`+` { state.operator(.add) }
		`-` { state.operator(.subtract) }
		`*` { state.operator(.multiply) }
		`/` { state.operator(.divide) }
		`%` { state.operator(.remainder) }
		`&` { state.operator(.bit_and) }
		`|` { state.operator(.bit_or) }
		`^` { state.operator(.bit_xor) }
		`<` { state.operator(.shift_left) }
		`>` { state.operator(.shift_right) }
		`~` { state.bit_not() }
		`=`, `\r`, `\n` { state.equals() }
		8, 127 { state.backspace() }
		0x1b { state.clear() }
		`.` { state.status = 'calculator.programmer.error.input' }
		else {
			if ch > 0x20 { state.status = 'calculator.programmer.error.input' }
		}
	}
}

fn (mut state CalculatorProgrammer) handle(action string) {
	for index, candidate in calculator_programmer_digit_actions {
		if candidate == action { state.digit(index); return }
	}
	for index, candidate in calculator_programmer_base_actions {
		if candidate == action { state.base = calculator_programmer_bases[index]; return }
	}
	for index, candidate in calculator_programmer_width_actions {
		if candidate == action { state.set_width(calculator_programmer_widths[index]); return }
	}
	for row, candidate in calculator_programmer_history_actions {
		if candidate == action && row + state.history_offset < state.history.len {
			value := state.history[state.history.len - 1 - row - state.history_offset].value
			width := state.history[state.history.len - 1 - row - state.history_offset].width
			state.clear()
			state.width = width
			state.set_value(value)
			state.replace_input = false
			state.operand_ready = true
			return
		}
	}
	match action {
		'calculator.programmer.add' { state.operator(.add) }
		'calculator.programmer.subtract' { state.operator(.subtract) }
		'calculator.programmer.multiply' { state.operator(.multiply) }
		'calculator.programmer.divide' { state.operator(.divide) }
		'calculator.programmer.remainder' { state.operator(.remainder) }
		'calculator.programmer.and' { state.operator(.bit_and) }
		'calculator.programmer.or' { state.operator(.bit_or) }
		'calculator.programmer.xor' { state.operator(.bit_xor) }
		'calculator.programmer.shl' { state.operator(.shift_left) }
		'calculator.programmer.shr' { state.operator(.shift_right) }
		'calculator.programmer.not' { state.bit_not() }
		'calculator.programmer.equals' { state.equals() }
		'calculator.programmer.clear' { state.clear() }
		'calculator.programmer.backspace' { state.backspace() }
		'calculator.programmer.history.clear' { state.clear_history() }
		'calculator.programmer.history.previous' {
			state.history_offset = if state.history_offset > state.history_rows {
				state.history_offset - state.history_rows
			} else { 0 }
		}
		'calculator.programmer.history.next' {
			if state.history_offset + state.history_rows < state.history.len {
				state.history_offset += state.history_rows
			}
		}
		else {}
	}
}

fn (mut state CalculatorProgrammer) close() {
	state.clear()
	state.clear_history()
	if state.history.cap > 0 { unsafe { state.history.free() } }
	state.history = []CalculatorIntegerHistory{}
}
