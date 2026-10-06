// SPDX-License-Identifier: GPL-2.0-or-later
// Bit actions and index labels are literals borrowed by each frame. Editing
// changes the displayed operand only; pending and repeated operations survive.
module main

import ui2

const calculator_programmer_bit_actions = ['calculator.programmer.bit.0',
	'calculator.programmer.bit.1',
	'calculator.programmer.bit.2',
	'calculator.programmer.bit.3',
	'calculator.programmer.bit.4',
	'calculator.programmer.bit.5',
	'calculator.programmer.bit.6',
	'calculator.programmer.bit.7',
	'calculator.programmer.bit.8',
	'calculator.programmer.bit.9',
	'calculator.programmer.bit.10',
	'calculator.programmer.bit.11',
	'calculator.programmer.bit.12',
	'calculator.programmer.bit.13',
	'calculator.programmer.bit.14',
	'calculator.programmer.bit.15',
	'calculator.programmer.bit.16',
	'calculator.programmer.bit.17',
	'calculator.programmer.bit.18',
	'calculator.programmer.bit.19',
	'calculator.programmer.bit.20',
	'calculator.programmer.bit.21',
	'calculator.programmer.bit.22',
	'calculator.programmer.bit.23',
	'calculator.programmer.bit.24',
	'calculator.programmer.bit.25',
	'calculator.programmer.bit.26',
	'calculator.programmer.bit.27',
	'calculator.programmer.bit.28',
	'calculator.programmer.bit.29',
	'calculator.programmer.bit.30',
	'calculator.programmer.bit.31',
	'calculator.programmer.bit.32',
	'calculator.programmer.bit.33',
	'calculator.programmer.bit.34',
	'calculator.programmer.bit.35',
	'calculator.programmer.bit.36',
	'calculator.programmer.bit.37',
	'calculator.programmer.bit.38',
	'calculator.programmer.bit.39',
	'calculator.programmer.bit.40',
	'calculator.programmer.bit.41',
	'calculator.programmer.bit.42',
	'calculator.programmer.bit.43',
	'calculator.programmer.bit.44',
	'calculator.programmer.bit.45',
	'calculator.programmer.bit.46',
	'calculator.programmer.bit.47',
	'calculator.programmer.bit.48',
	'calculator.programmer.bit.49',
	'calculator.programmer.bit.50',
	'calculator.programmer.bit.51',
	'calculator.programmer.bit.52',
	'calculator.programmer.bit.53',
	'calculator.programmer.bit.54',
	'calculator.programmer.bit.55',
	'calculator.programmer.bit.56',
	'calculator.programmer.bit.57',
	'calculator.programmer.bit.58',
	'calculator.programmer.bit.59',
	'calculator.programmer.bit.60',
	'calculator.programmer.bit.61',
	'calculator.programmer.bit.62',
	'calculator.programmer.bit.63']!
const calculator_programmer_bit_labels = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32', '33', '34', '35', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46', '47', '48', '49', '50', '51', '52', '53', '54', '55', '56', '57', '58', '59', '60', '61', '62', '63']!
const calculator_programmer_bit_ranges = ['7 - 0', '15 - 8', '23 - 16', '31 - 24',
	'39 - 32', '47 - 40', '55 - 48', '63 - 56']!

fn (mut state CalculatorProgrammer) toggle_bit(bit int) {
	// Check before shifting, including actions retained from a wider frame.
	if bit < 0 || bit >= state.width || state.has_error { return }
	if state.replace_input && state.pending == .none { state.has_accumulator = false }
	state.set_value(state.value ^ (u64(1) << u32(bit)))
	state.replace_input = false
	state.operand_ready = true
	state.status = ''
}

fn (app &CalculatorApp) programmer_view_control(mut children []ui2.Element, frame ui2.Rect) {
	children << ui2.Element{
		...ui2.button('calculator.programmer.bits', tr(if app.integer.bits_view {
			'calculator.programmer.keypad'
		} else { 'calculator.programmer.bits' }), frame,
			ui2.BoxStyle{ bg: if app.integer.bits_view { app_accent } else { settings_choice_bg }, radius: 4 },
			ui2.TextStyle{ color: if app.integer.bits_view { app_on_accent } else { body_text }, size: 11, align: .center })
		checked: app.integer.bits_view
		tooltip: tr('calculator.programmer.bits.help')
	}
}

fn (app &CalculatorApp) programmer_bit_grid(mut children []ui2.Element, width f64, top f64, compact bool) {
	available := if width > 24 { width - 24 } else { f64(0) }
	columns := if !compact { 16 } else if width >= 260 { 8 } else { 4 }
	count := if compact { 8 } else { app.integer.width }
	first := if compact { app.integer.bit_page * 8 } else { 0 }
	cell_width := (available - f64(columns - 1) * 4) / f64(columns)
	row_height := if compact { f64(28) } else { f64(50) }
	label_height := if compact { f64(10) } else { f64(12) }
	button_height := if compact { f64(18) } else { f64(26) }
	for index in 0 .. count {
		bit := first + count - 1 - index
		set := (app.integer.value & (u64(1) << u32(bit))) != 0
		x := 12 + f64(index % columns) * (cell_width + 4)
		y := top + f64(index / columns) * row_height
		children << ui2.label('', calculator_programmer_bit_labels[bit],
			ui2.rect(x, y, cell_width, label_height),
			ui2.TextStyle{ size: 9, color: body_muted, align: .center })
		children << ui2.Element{
			...ui2.button(calculator_programmer_bit_actions[bit], if set { '1' } else { '0' },
				ui2.rect(x, y + label_height, cell_width, button_height),
				ui2.BoxStyle{ bg: if set { app_accent } else { settings_choice_bg }, radius: 3 },
				ui2.TextStyle{ color: if set { app_on_accent } else { body_text }, size: 12, align: .center })
			checked: set
			tooltip: tr('calculator.programmer.bits.help')
		}
	}
}

fn (app &CalculatorApp) programmer_bit_pages(mut children []ui2.Element, width f64, top f64) {
	// One byte per compact page keeps every width usable in narrow windows.
	range_left := if width < 260 { f64(80) } else { f64(112) }
	children << ui2.Element{
		...calculator_utility_button('calculator.programmer.bits.previous', '<', width - 72, top, 26)
		tooltip: tr('calculator.programmer.bits.previous')
	}
	children << ui2.Element{
		...calculator_utility_button('calculator.programmer.bits.next', '>', width - 38, top, 26)
		tooltip: tr('calculator.programmer.bits.next')
	}
	children << ui2.label('calculator.programmer.bits.range', calculator_programmer_bit_ranges[app.integer.bit_page],
		ui2.rect(range_left, top, width - 84 - range_left, 22),
		ui2.TextStyle{ size: 10, color: body_text, align: .center })
}

fn (app &CalculatorApp) build_programmer_tiny(size ui2.Rect) ui2.Element {
	mut children := frame_elements(8)
	if size.width <= 4 || size.height <= 4 { return ui2.screen(app_surface, children) }
	margin := if size.width < 60 || size.height < 60 { f64(2) } else { f64(10) }
	inner := size.width - margin * 2
	mut top := margin
	if size.width >= 100 && size.height >= 110 {
		app.mode_controls(mut children, size.width)
		top = 44
	}
	if size.height >= 160 {
		children << ui2.label('', app.integer.text(app.integer.base), ui2.rect(margin, top, inner, 24),
			ui2.TextStyle{ size: 10, color: body_heading, align: .right })
		top += 28
	}
	if size.height >= 88 {
		app.programmer_view_control(mut children, ui2.rect(margin, top, inner, 24))
		top += 30
	}
	children << ui2.Element{
		...ui2.label('', tr('calculator.programmer.resize'),
			ui2.rect(margin, top, inner, size.height - top - margin),
			ui2.TextStyle{ size: 10, color: body_muted })
		tooltip: tr('calculator.programmer.resize')
	}
	return ui2.screen(app_surface, children)
}
