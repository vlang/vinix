// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import math

fn calculator_feature_find(tree ui2.Element, action string) ?ui2.Element {
	if tree.action_id == action || tree.id == action { return tree }
	for child in tree.children {
		if found := calculator_feature_find(child, action) { return found }
	}
	return none
}

fn test_calculator_keyboard_operands_and_repeated_equals() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.key_input('12\x7f3+4\n')
	assert app.calculator.display == '17'
	assert app.history.len == 1
	assert app.history[0].expression == '13 + 4'
	app.key_input('=')
	assert app.calculator.display == '21'
	app.key_input('c1/0=')
	assert app.calculator.has_error
	app.key_input('8')
	assert app.calculator.display == '8'
	app.key_input('\x1b[3~\x1b[1~')
	assert app.calculator.display == '8'
	app.key_input('c1.25*4=')
	assert app.calculator.display == '5'
}

fn test_calculator_paste_is_one_operand_and_rejects_commands() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.key_input('2+')
	app.paste_input('  -12.5  ')
	app.key_input('=')
	assert app.calculator.display == '-10.5'
	app.paste_input('c9+1=')
	app.paste_input('NaN')
	app.paste_input('1\n2')
	assert app.calculator.display == '-10.5'
}

fn test_calculator_memory_and_bounded_history_recall() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.key_input('10')
	app.handle('calculator.memory.add')!
	app.key_input('c3')
	app.handle('calculator.memory.subtract')!
	app.key_input('c')
	app.handle('calculator.memory.recall')!
	assert app.calculator.display == '7'
	app.key_input('+1=')
	for _ in 0 .. 40 { app.key_input('=') }
	assert app.history.len == calculator_history_limit
	assert app.calculator.display == '48'
	app.handle('calculator.history.1')!
	assert app.calculator.display == '47'
	app.key_input('*2=')
	assert app.calculator.display == '94'
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 340, 540))!
	assert calculator_feature_find(tree, 'calculator.history.0') != none
	assert calculator_feature_find(tree, 'calculator.memory.recall') != none
	free_tree(tree)
	app.handle('calculator.history.next')!
	app.handle('calculator.history.0')!
	assert app.calculator.display == '46'
	app.handle('calculator.history.previous')!
	app.handle('calculator.history.0')!
	assert app.calculator.display == '94'
	app.handle('calculator.history.clear')!
	assert app.history.len == 0
	app.handle('calculator.memory.clear')!
	assert !app.has_memory
}

fn test_calculator_relative_percentage_and_repeat_on_new_operand() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.key_input('100+15%=')
	assert app.calculator.display == '115'
	app.key_input('150=')
	assert app.calculator.display == '172.5'
	app.key_input('c200-10%=')
	assert app.calculator.display == '180'
	app.key_input('c200*10%=')
	assert app.calculator.display == '20'
}

fn test_calculator_scientific_unary_functions_and_degree_angles() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	inputs := ['9', '4', '-3', '30', '60', '45', '.5', '.5', '1', '1', '100', '0']!
	expected := [3.0, .25, 9.0, .5, .5, 1.0, 30.0, 60.0, 45.0, 0.0, 2.0, 1.0]!
	for index, action in calculator_scientific_actions {
		if index >= inputs.len { break }
		app.key_input('c')
		app.paste_input(inputs[index])
		app.handle(action)!
		assert !app.calculator.has_error
		assert math.abs(app.calculator.display.f64() - expected[index]) < 1e-12
		assert app.calculator.replace_input
	}
	assert app.history[3].expression == 'sin(30) [DEG]'
	assert app.history[6].expression == 'asin(0.5) [DEG]'
	assert app.history[0].expression == 'sqrt(9)'
	assert app.history[1].expression == '1 / (4)'
	assert app.history[2].expression == '(-3)^2'
}

fn test_calculator_scientific_constants_radians_and_units_leave_operands_unchanged() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.key_input('\x13')
	assert app.scientific
	app.handle('calculator.scientific.pi')!
	assert math.abs(app.calculator.display.f64() - math.pi) < 1e-14
	app.key_input('/2=')
	before := app.calculator.display.clone()
	defer { unsafe { before.free() } }
	app.key_input('\x04')
	assert !app.degrees
	assert app.calculator.display == before
	app.handle('calculator.scientific.sin')!
	assert app.calculator.display == '1'
	assert app.history.last().expression.ends_with('[RAD]')
	app.key_input('c')
	app.paste_input('1')
	app.handle('calculator.scientific.atan')!
	assert math.abs(app.calculator.display.f64() - math.pi / 4) < 1e-14
	app.handle('calculator.scientific.e')!
	app.handle('calculator.scientific.ln')!
	assert math.abs(app.calculator.display.f64() - 1) < 1e-13
	app.key_input('\x13')
	assert !app.scientific
	app.key_input('c2+3==')
	assert app.calculator.display == '8'
}

fn test_calculator_scientific_domains_overflow_and_error_recovery() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	for index, action in ['calculator.scientific.sqrt', 'calculator.scientific.reciprocal',
		'calculator.scientific.ln', 'calculator.scientific.log', 'calculator.scientific.asin',
		'calculator.scientific.acos', 'calculator.scientific.exp', 'calculator.scientific.tan']! {
		app.key_input('c')
		app.paste_input(['-1', '0', '0', '-1', '2', '-2', '1000', '90']![index])
		app.handle(action)!
		assert app.calculator.has_error
		assert app.calculator.display == tr('calculator.error')
		assert app.history.len == 0
		assert app.scientific_status == if index == 6 {
			'calculator.error.nonfinite'
		} else if index == 7 {
			'calculator.error.tangent'
		} else {
			'calculator.error.domain'
		}
		app.key_input('7')
		assert !app.calculator.has_error && app.calculator.display == '7'
	}
	app.key_input('c')
	app.paste_input('1e308')
	app.handle('calculator.scientific.square')!
	assert app.calculator.has_error
	assert app.scientific_status == 'calculator.error.nonfinite'
	app.handle('calculator.scientific.pi')!
	assert !app.calculator.has_error
	app.handle('calculator.angle.radians')!
	app.key_input('/2=')
	app.handle('calculator.scientific.tan')!
	assert app.calculator.has_error
	assert app.scientific_status == 'calculator.error.tangent'
}

fn test_calculator_scientific_pending_operands_repeat_and_new_digit_replacement() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('2+9')
	app.handle('calculator.scientific.sqrt')!
	app.key_input('==')
	assert app.calculator.display == '8'
	assert app.history[0].expression == 'sqrt(9)'
	assert app.history[1].expression == '2 + 3'
	assert app.history[2].expression == '5 + 3'
	app.handle('calculator.scientific.square')!
	app.key_input('=')
	assert app.calculator.display == '64'
	app.key_input('7')
	assert app.calculator.display == '7'
	app.key_input('c2+9')
	app.handle('calculator.scientific.sqrt')!
	app.key_input('*4=')
	assert app.calculator.display == '20'
	app.key_input('c2+')
	app.handle('calculator.scientific.pi')!
	app.key_input('==')
	assert math.abs(app.calculator.display.f64() - (2 + 2 * math.pi)) < 1e-13
	app.key_input('c2+9')
	app.handle('calculator.scientific.sqrt')!
	app.paste_input('4')
	app.key_input('=')
	assert app.calculator.display == '6'
	app.key_input('c2+9')
	app.handle('calculator.scientific.sqrt')!
	app.key_input('4=')
	assert app.calculator.display == '6'
}

fn test_calculator_scientific_history_memory_and_percent_remain_consistent() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('100+15%=')
	assert app.calculator.display == '115'
	app.key_input('=')
	assert app.calculator.display == '132.25'
	app.handle('calculator.scientific.sqrt')!
	app.handle('calculator.memory.add')!
	app.key_input('c2+')
	app.handle('calculator.memory.recall')!
	app.key_input('=')
	assert app.calculator.display == '13.5'
	for _ in 0 .. 40 {
		app.handle('calculator.scientific.square')!
		app.handle('calculator.scientific.sqrt')!
	}
	assert app.history.len == calculator_history_limit
	app.handle('calculator.history.0')!
	app.key_input('+1=')
	assert app.calculator.display == '14.5'
	app.handle('calculator.mode.basic')!
	app.key_input('c3*4=')
	assert app.calculator.display == '12'
}

fn test_calculator_scientific_numeric_paste_rejects_commands_and_nonfinite_values() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('2+')
	app.paste_input('1.25e+2')
	app.key_input('=')
	assert app.calculator.display == '127'
	for text in ['1e309', '1e', '1e+', '1e +2', '1e1.2', 'nan', 'sqrt(9)', 'c9+1=', '1\n2']! {
		app.paste_input(text)
		assert app.calculator.display == '127'
	}
	app.paste_input('1E-3')
	app.key_input('9')
	assert app.calculator.display == '9'
}

fn test_calculator_scientific_ui_has_wire_supported_controls_and_resize_hint() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	begin_frame_elements()
	basic := app.build(ui2.rect(0, 0, 620, 576))!
	assert calculator_feature_find(basic, 'calculator.mode.scientific') != none
	assert calculator_feature_find(basic, 'calculator.scientific.sqrt') == none
	assert calculator_feature_find(basic, '±') != none
	free_tree(basic)
	app.key_input('3')
	app.handle('±')!
	assert app.calculator.display == '-3'
	app.handle('calculator.mode.scientific')!
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 620, 576))!
	for action in calculator_scientific_actions {
		control := calculator_feature_find(tree, action) or { panic('missing scientific control') }
		assert control.kind == .button
		assert control.frame.width > 0 && control.frame.height > 0
	}
	assert calculator_feature_find(tree, 'calculator.angle.degrees') != none
	assert calculator_feature_find(tree, 'calculator.memory.recall') != none
	panel := calculator_feature_find(tree, 'calculator') or { panic('missing keypad panel') }
	assert panel.frame.x >= 0 && panel.frame.x + panel.frame.width <= 620
	assert panel.frame.y >= 0 && panel.frame.y + panel.frame.height <= 576
	for key in calculator_button_texts {
		button := calculator_feature_find(tree, key) or { panic('missing keypad button') }
		assert button.frame.x >= 0 && button.frame.x + button.frame.width <= panel.frame.width
		assert button.frame.y >= 0 && button.frame.y + button.frame.height <= panel.frame.height
	}
	mut encoded := []u8{cap: 65536}
	unsafe { encoded.flags |= .noslices }
	encode_app_element(tree, mut encoded)!
	mut reader := WireReader{ data: encoded }
	decoded := decode_app_element(mut reader, 0)!
	assert calculator_feature_find(decoded, 'calculator.scientific.sqrt') != none
	free_tree(decoded)
	free_tree(tree)
	unsafe { encoded.free() }
	app.handle('calculator.scientific.pi')!
	begin_frame_elements()
	compact := app.build(ui2.rect(0, 0, 340, 510))!
	assert calculator_feature_find(compact, 'calculator.mode.basic') != none
	assert calculator_feature_find(compact, 'calculator.scientific.sqrt') == none
	assert compact.children.last().text == tr('calculator.scientific.resize')
	free_tree(compact)
	app.handle('calculator.mode.basic')!
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 340, 540))!)
	assert math.abs(app.calculator.display.f64() - math.pi) < 1e-14
}
