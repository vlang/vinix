// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

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
	tree := app.build(ui2.rect(0, 0, 340, 510))!
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
