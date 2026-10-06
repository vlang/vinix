// SPDX-License-Identifier: GPL-2.0-or-later
// Integer readouts borrow model-owned strings. Only formatted history labels
// belong to the current frame; the frame pool owns the bounded element list.
module main

import ui2

const calculator_programmer_key_actions = ['calculator.programmer.digit.A',
	'calculator.programmer.digit.B', 'calculator.programmer.digit.C',
	'calculator.programmer.digit.D', 'calculator.programmer.digit.E',
	'calculator.programmer.digit.F', 'calculator.programmer.digit.7',
	'calculator.programmer.digit.8', 'calculator.programmer.digit.9',
	'calculator.programmer.and', 'calculator.programmer.or', 'calculator.programmer.xor',
	'calculator.programmer.digit.4', 'calculator.programmer.digit.5',
	'calculator.programmer.digit.6', 'calculator.programmer.shl',
	'calculator.programmer.shr', 'calculator.programmer.not',
	'calculator.programmer.digit.1', 'calculator.programmer.digit.2',
	'calculator.programmer.digit.3', 'calculator.programmer.add',
	'calculator.programmer.subtract', 'calculator.programmer.multiply',
	'calculator.programmer.digit.0', 'calculator.programmer.clear',
	'calculator.programmer.backspace', 'calculator.programmer.divide',
	'calculator.programmer.remainder', 'calculator.programmer.equals']!
const calculator_programmer_key_texts = ['A', 'B', 'C', 'D', 'E', 'F', '7', '8', '9',
	'AND', 'OR', 'XOR', '4', '5', '6', '<<', '>>', 'NOT', '1', '2', '3', '+', '-', '*',
	'0', 'AC', '<-', '/', '%', '=']!
const calculator_programmer_readout_ids = ['calculator.programmer.readout.dec',
	'calculator.programmer.readout.hex', 'calculator.programmer.readout.oct',
	'calculator.programmer.readout.bin']!

fn (app &CalculatorApp) programmer_base_controls(mut children []ui2.Element, width f64, top f64, readouts bool) {
	available := if width > 24 { width - 24 } else { f64(0) }
	button_width := if readouts { f64(54) } else if available >= 18 { (available - 18) / 4 }
		else { f64(0) }
	for index, action in calculator_programmer_base_actions {
		selected := app.integer.base == calculator_programmer_bases[index]
		left := if readouts { f64(12) } else { 12 + f64(index) * (button_width + 6) }
		top_y := if readouts { top + f64(index) * 28 } else { top }
		children << ui2.Element{
			...ui2.button(action, tr(action), ui2.rect(left, top_y, button_width, 24),
				ui2.BoxStyle{ bg: if selected { app_accent } else { settings_choice_bg }, radius: 4 },
				ui2.TextStyle{ color: if selected { app_on_accent } else { body_text }, size: 11, align: .center })
			tooltip: tr('calculator.programmer.shortcuts')
		}
		if readouts {
			children << ui2.label(calculator_programmer_readout_ids[index], app.integer.text(calculator_programmer_bases[index]),
				ui2.rect(78, top_y, width - 90, 24),
				ui2.TextStyle{ size: if index == 3 { 10 } else { 15 }, color: body_heading, align: .right })
		}
	}
}

fn (app &CalculatorApp) programmer_width_controls(mut children []ui2.Element, width f64, top f64) {
	available := if width > 24 { width - 24 } else { f64(0) }
	button_width := if available >= 18 { (available - 18) / 4 } else { f64(0) }
	for index, action in calculator_programmer_width_actions {
		selected := app.integer.width == calculator_programmer_widths[index]
		children << ui2.Element{
			...ui2.button(action, tr(action), ui2.rect(12 + f64(index) * (button_width + 6),
				top, button_width, 24), ui2.BoxStyle{
				bg: if selected { app_accent } else { settings_choice_bg }, radius: 4
			}, ui2.TextStyle{
				color: if selected { app_on_accent } else { body_text }, size: 11, align: .center
			})
			checked: selected
			tooltip: tr('calculator.programmer.width.help')
		}
	}
}

fn (mut app CalculatorApp) build_programmer(size ui2.Rect) ui2.Element {
	mut children := frame_elements(70)
	app.mode_controls(mut children, size.width)
	available := if size.width > 24 { size.width - 24 } else { f64(0) }
	compact := size.width < 540 || size.height < 560
	if compact {
		app.copy_controls(mut children, ui2.rect(12, 292, 140, 26),
			ui2.rect(164, 292, size.width - 176, 26))
		app.programmer_base_controls(mut children, size.width, 46, false)
		app.programmer_width_controls(mut children, size.width, 82)
		children << ui2.label('', app.integer.text(app.integer.base), ui2.rect(12, 116, available, 42),
			ui2.TextStyle{ size: if app.integer.base == 2 { 9 } else { 20 }, color: body_heading, align: .right })
		children << ui2.label('', tr(if app.integer.status.len > 0 {
			app.integer.status
		} else { 'calculator.programmer.resize' }), ui2.rect(12, 174, available, 34),
			ui2.TextStyle{ size: 11, color: if app.integer.status.len > 0 { files_error } else { body_muted } })
		children << ui2.Element{
			...ui2.label('', tr('calculator.programmer.rules'), ui2.rect(12, 218, available, 24),
				ui2.TextStyle{ size: 10, color: body_muted })
			tooltip: tr('calculator.programmer.rules')
		}
		children << ui2.Element{
			...ui2.label('', tr('calculator.programmer.shortcuts'), ui2.rect(12, 248, available, 32),
				ui2.TextStyle{ size: 10, color: body_muted })
			tooltip: tr('calculator.programmer.shortcuts')
		}
		return ui2.screen(app_surface, children)
	}
	app.copy_controls(mut children, ui2.rect(334, 10, 116, 26),
		ui2.rect(462, 10, size.width - 474, 26))
	app.programmer_width_controls(mut children, size.width, 74)
	children << ui2.Element{
		...ui2.label('', tr('calculator.programmer.rules'), ui2.rect(12, 44, available, 14),
			ui2.TextStyle{ size: 11, color: body_muted })
		tooltip: tr('calculator.programmer.rules')
	}
	children << ui2.Element{
		...ui2.label('', tr('calculator.programmer.shifts'), ui2.rect(12, 58, available, 14),
			ui2.TextStyle{ size: 11, color: body_muted })
		tooltip: tr('calculator.programmer.shifts')
	}
	children << ui2.Element{
		...ui2.label('', tr(if app.integer.status.len > 0 {
			app.integer.status
	} else { 'calculator.programmer.input_hint' }), ui2.rect(12, 102, available, 18),
			ui2.TextStyle{ size: 11, color: if app.integer.status.len > 0 { files_error } else { body_muted } })
		tooltip: tr(if app.integer.status.len > 0 {
			app.integer.status
		} else { 'calculator.programmer.shortcuts' })
	}
	app.programmer_base_controls(mut children, size.width, 126, true)
	button_width := (available - 40) / 6
	for index, action in calculator_programmer_key_actions {
		text := calculator_programmer_key_texts[index]
		digit := if text.len == 1 { calculator_integer_digit(text[0]) } else { -1 }
		unavailable := digit >= app.integer.base
		label := if action == 'calculator.programmer.and' || action == 'calculator.programmer.or'
			|| action == 'calculator.programmer.xor' || action == 'calculator.programmer.not' {
			tr(action)
		} else { text }
		children << ui2.Element{
			...ui2.button(action, label, ui2.rect(12 + f64(index % 6) * (button_width + 8),
				250 + f64(index / 6) * 46, button_width, 38), ui2.BoxStyle{
				bg: if action == 'calculator.programmer.equals' { app_accent }
					else if unavailable { app_surface } else { settings_choice_bg }
				radius: 5
			}, ui2.TextStyle{
				color: if action == 'calculator.programmer.equals' { app_on_accent }
					else if unavailable { body_muted } else { body_text }
				size: 13
				align: .center
			})
			tooltip: tr(if unavailable { 'calculator.programmer.error.digit' }
				else { 'calculator.programmer.shortcuts' })
		}
	}
	children << ui2.label('', tr('calculator.history.title'), ui2.rect(12, 488, available - 116, 20),
		ui2.TextStyle{ size: 12, bold: true, color: body_heading })
	children << calculator_utility_button('calculator.programmer.history.previous', '<', size.width - 122, 486, 22)
	children << calculator_utility_button('calculator.programmer.history.next', '>', size.width - 96, 486, 22)
	children << calculator_utility_button('calculator.programmer.history.clear', tr('calculator.history.clear'), size.width - 68, 486, 56)
	rows := int((size.height - 522) / 22)
	app.integer.history_rows = if rows > 5 { 5 } else if rows < 1 { 1 } else { rows }
	if app.integer.history_offset >= app.integer.history.len { app.integer.history_offset = 0 }
	for row in 0 .. app.integer.history_rows {
		if row + app.integer.history_offset >= app.integer.history.len { break }
		item := app.integer.history[app.integer.history.len - 1 - row - app.integer.history_offset]
		value := calculator_integer_text(item.value, 10)
		text := 'DEC: ' + item.expression + ' = ' + value + ' [' + tr(calculator_integer_width_action(item.width)) + ']'
		unsafe { value.free() }
		children << ui2.Element{
			...ui2.button(calculator_programmer_history_actions[row], text,
				ui2.rect(12, 520 + f64(row) * 22, available, 20), ui2.BoxStyle{ transparent: true },
				ui2.TextStyle{ size: 11, color: body_text, align: .right })
			id: frame_owned_text_id
			action_id: calculator_programmer_history_actions[row]
		}
	}
	return ui2.screen(app_surface, children)
}
