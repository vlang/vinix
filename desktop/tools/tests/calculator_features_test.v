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

fn calculator_feature_random_write(fd int, bits u64) {
	mut bytes := [8]u8{}
	for index in 0 .. 8 { bytes[index] = u8(bits >> u32((7 - index) * 8)) }
	assert desktop_write(fd, &bytes[0], 8) == 8
}

fn test_calculator_random_conversion_is_exact_bounded_and_endian_independent() {
	assert calculator_random_value(0) == 0
	assert calculator_random_value(2047) == 0
	assert calculator_random_value(2048) == 1.0 / 9007199254740992.0
	assert calculator_random_value(u64(1) << 63) == 0.5
	assert calculator_random_value(calculator_programmer_max) == 1 - 1.0 / 9007199254740992.0
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]) desktop_close(pair[1]) }
	assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
	for bits in [u64(0), 2048, 0x0123456789abcdef, u64(1) << 63, calculator_programmer_max]! {
		calculator_feature_random_write(pair[1], bits)
		read := calculator_random_bits(pair[0]) or { panic('entropy read failed') }
		assert read == bits
		value := calculator_random_value(bits)
		assert value >= 0 && value < 1 && math.is_finite(value)
	}
}

fn test_calculator_random_empty_short_eof_and_bad_descriptors_fail_without_waiting() {
	assert calculator_random_bits(-1) == none
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]) }
	assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
	assert calculator_random_bits(pair[0]) == none
	bytes := [u8(255), 255, 255, 255]!
	assert desktop_write(pair[1], &bytes[0], 4) == 4
	assert calculator_random_bits(pair[0]) == none
	assert desktop_write(pair[1], &bytes[0], 4) == 4
	desktop_close(pair[1])
	assert calculator_random_bits(pair[0]) == none
	assert calculator_random_bits(pair[0]) == none
}

fn test_calculator_random_pending_arithmetic_repeat_memory_history_and_replacement() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.handle('calculator.angle.radians')!
	app.key_input('7')
	app.handle('calculator.memory.add')!
	app.key_input('c2+')
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]) desktop_close(pair[1]) }
	assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
	calculator_feature_random_write(pair[1], u64(1) << 63)
	app.scientific_random_from_fd(pair[0])
	assert app.calculator.display == '0.5' && app.scientific_operand && app.calculator.replace_input
	assert app.calculator.pending_operator == '+' && app.calculator.accumulator == 2
	assert app.memory == 7 && app.has_memory && !app.degrees && app.scientific && !app.programmer
	assert app.history.len == 1 && app.history[0].expression == tr('calculator.scientific.random')
	assert app.history[0].result == '0.5'
	app.key_input('==')
	assert app.calculator.display == '3' && app.calculator.last_operand == 0.5
	assert app.history.last().expression == '2.5 + 0.5'
	calculator_feature_random_write(pair[1], u64(1) << 63)
	app.scientific_random_from_fd(pair[0])
	app.key_input('=')
	assert app.calculator.display == '0.5' && app.calculator.last_operator == ''
	app.key_input('9')
	assert app.calculator.display == '9'
	app.key_input('c200+10%')
	calculator_feature_random_write(pair[1], u64(1) << 63)
	app.scientific_random_from_fd(pair[0])
	assert !app.input_percent && !app.last_percent
	app.key_input('=')
	assert app.calculator.display == '200.5'
	app.handle('calculator.history.1')!
	assert app.calculator.display == '0.5' && app.calculator.pending_operator == ''
}

fn test_calculator_random_upper_boundary_zero_exponent_error_recovery_and_mode_scope() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]) desktop_close(pair[1]) }
	assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
	calculator_feature_random_write(pair[1], calculator_programmer_max)
	app.scientific_random_from_fd(pair[0])
	assert app.calculator.display == '0.99999999999999989'
	assert calculator_numeric_value(app.calculator.display) < 1 && app.copy_value() == app.calculator.display
	app.key_input('c2+1e-')
	calculator_feature_random_write(pair[1], 0)
	app.scientific_random_from_fd(pair[0])
	assert app.calculator.display == '0' && !app.exponent_input && !app.calculator.has_error
	app.key_input('=')
	assert app.calculator.display == '2'
	app.key_input('c1/0=')
	assert app.calculator.has_error
	calculator_feature_random_write(pair[1], u64(1) << 63)
	app.scientific_random_from_fd(pair[0])
	assert app.calculator.display == '0.5' && !app.calculator.has_error
	app.handle('calculator.mode.basic')!
	before := app.history.len
	app.scientific_random_from_fd(-1)
	app.handle('calculator.scientific.random')!
	assert app.calculator.display == '0.5' && app.history.len == before && app.scientific_status == ''
	app.handle('calculator.mode.programmer')!
	app.key_input('123')
	app.scientific_random_from_fd(-1)
	app.handle('calculator.scientific.random')!
	assert app.integer.value == 123 && app.history.len == before && app.scientific_status == ''
	app.handle('calculator.mode.scientific')!
	app.scientific_random_from_fd(-1)
	assert app.scientific_status == 'calculator.random.unavailable'
}

fn test_calculator_random_unavailable_preserves_draft_pending_memory_and_history() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('5')
	app.handle('calculator.memory.add')!
	app.key_input('+2=')
	app.key_input('+1e-')
	before_display := app.calculator.display.str
	before_history := app.history.len
	app.scientific_random_from_fd(-1)
	assert app.calculator.display.str == before_display && app.calculator.display == '1e-'
	assert app.exponent_input && !app.calculator.has_error && !app.calculator.replace_input
	assert app.calculator.pending_operator == '+' && app.calculator.accumulator == 7
	assert app.memory == 5 && app.has_memory && app.history.len == before_history
	assert app.scientific_status == 'calculator.random.unavailable'
	app.key_input('3=')
	assert app.calculator.display == '7.001' && app.scientific_status == ''
}

fn test_calculator_random_control_wire_dispatch_real_entropy_and_bounded_history() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 540, 430))!
	defer { free_tree(tree) }
	mut encoded := []u8{cap: 65536}
	unsafe { encoded.flags |= .noslices }
	defer { unsafe { encoded.free() } }
	encode_app_element(tree, mut encoded)!
	mut reader := WireReader{ data: encoded }
	decoded := decode_app_element(mut reader, 0)!
	defer { free_tree(decoded) }
	button := calculator_feature_find(decoded, 'calculator.scientific.random') or { panic('missing Rand') }
	assert button.frame.y == 374 && button.frame.y + button.frame.height < 422
	assert button.text == tr('calculator.scientific.random') && button.tooltip == tr('calculator.scientific.random.help')
	for _ in 0 .. 30 {
		app.key_input('c2+')
		app.handle(if button.action_id.len > 0 { button.action_id } else { button.id })!
		assert app.scientific_status == '' && !app.calculator.has_error
		operand := calculator_numeric_value(app.calculator.display)
		assert operand >= 0 && operand < 1 && app.calculator.pending_operator == '+'
		assert app.copy_value() == app.calculator.display
		app.key_input('=')
		assert math.abs(calculator_numeric_value(app.calculator.display) - (2 + operand)) < 1e-14
	}
	assert app.history.len == calculator_history_limit
}

fn test_calculator_ee_keyboard_control_sign_backspace_and_decimal_state() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('1.25E-3')
	assert app.calculator.display == '1.25e-3' && app.exponent_input
	app.press('±')
	assert app.calculator.display == '1.25e3'
	app.press('±')
	assert app.calculator.display == '1.25e-3'
	app.key_input('.')
	assert app.calculator.display == '1.25e-3'
	app.key_input('\x7f\x7f')
	assert app.calculator.display == '1.25e' && app.exponent_input
	app.key_input('-+2')
	assert app.calculator.display == '1.25e2'
	app.key_input('+1=')
	assert app.calculator.display == '126' && !app.exponent_input
	assert app.history.last().expression == '125 + 1'
	app.key_input('c6')
	app.handle('calculator.scientific.ee')!
	app.handle('calculator.scientific.ee')!
	assert app.calculator.display == '6e'
	app.key_input('\x7f.5')
	assert app.calculator.display == '6.5' && !app.exponent_input
	app.key_input('e-2')
	app.handle('calculator.scientific.sqrt')!
	assert math.abs(app.calculator.display.f64() - math.sqrt(.065)) < 1e-14
	app.key_input('9')
	assert app.calculator.display == '9'
}

fn test_calculator_ee_incomplete_overflow_underflow_and_finite_boundary_guards() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('4')
	app.handle('calculator.memory.add')!
	for operand in ['1e', '1e-', '1e+']! {
		app.key_input('c')
		app.key_input(operand)
		assert app.copy_value() == ''
		before := app.history.len
		app.handle('calculator.memory.add')!
		assert app.memory == 4 && app.has_memory
		assert app.calculator.has_error && app.scientific_status == 'calculator.error.exponent'
		assert app.history.len == before
	}
	for command in ['=', '*', '%']! {
		app.key_input('c1e309')
		assert app.calculator.display == '1e309' && !app.calculator.has_error
		assert app.copy_value() == ''
		app.key_input(command)
		assert app.calculator.has_error && app.scientific_status == 'calculator.error.nonfinite'
	}
	app.key_input('c1e309\x7f8+0=')
	assert app.calculator.display == '1e+308' && !app.calculator.has_error
	app.key_input('c1.7976931348623157e308+0=')
	assert !app.calculator.has_error && math.is_finite(app.calculator.display.f64())
	assert app.calculator.display.f64() == 1.7976931348623157e308
	assert app.copy_value() == app.calculator.display
	app.key_input('c5e-324+0=')
	assert calculator_numeric_value(app.calculator.display) == 5e-324
	app.key_input('c1e-400+2=')
	assert app.calculator.display == '2'
	app.key_input('c1e-')
	app.handle('calculator.scientific.pi')!
	assert !app.exponent_input && !app.calculator.has_error
}

fn test_calculator_ee_paste_equivalence_limits_pending_operand_and_modes() {
	mut typed := new_calculator_app()
	mut pasted := new_calculator_app()
	defer { typed.close_app() pasted.close_app() }
	for index, operand in ['1.25e3', '1.25E-3', '.5e+2', '5e-324']! {
		typed.handle('calculator.mode.scientific')!
		pasted.handle('calculator.mode.scientific')!
		typed.key_input('c2+')
		pasted.key_input('c2+')
		typed.key_input(operand)
		pasted.paste_input(operand)
		typed.key_input('==')
		pasted.key_input('==')
		assert typed.calculator.display == pasted.calculator.display
		assert typed.history.last().expression == pasted.history.last().expression
		assert typed.calculator.last_operand == pasted.calculator.last_operand
		assert typed.history.len == (index + 1) * 2
	}
	long_mantissa := '1'.repeat(calculator_input_limit - 2)
	defer { unsafe { long_mantissa.free() } }
	typed.key_input('c')
	typed.key_input(long_mantissa)
	typed.key_input('e3')
	assert typed.calculator.display.len == calculator_input_limit
	typed.press('±')
	assert !calculator_exponent_negative(typed.calculator.display)
	typed.key_input('4')
	assert typed.calculator.display.len == calculator_input_limit
	typed.key_input('\x7f\x7f\x7fe')
	typed.press('±')
	typed.key_input('2')
	assert calculator_exponent_negative(typed.calculator.display)
	assert typed.calculator.display.len == calculator_input_limit
	typed.key_input('c2+')
	typed.handle('calculator.scientific.ee')!
	assert typed.calculator.display == '0e' && typed.calculator.accumulator == 2
	typed.key_input('3=')
	assert typed.calculator.display == '2'
	typed.key_input('c6e2')
	typed.handle('calculator.memory.add')!
	assert typed.memory == 600 && !typed.exponent_input
	typed.handle('calculator.mode.programmer')!
	typed.handle('calculator.programmer.base.hex')!
	typed.key_input('FE')
	assert typed.integer.value == 254
	typed.handle('calculator.scientific.ee')!
	typed.handle('calculator.scientific.root')!
	assert typed.integer.value == 254
	typed.handle('calculator.mode.basic')!
	typed.handle('calculator.memory.recall')!
	assert typed.calculator.display == '600' && !typed.exponent_input
	typed.key_input('e')
	assert typed.calculator.display == '600'
	typed.handle('calculator.mode.scientific')!
	typed.handle('calculator.history.0')!
	assert typed.calculator.display == '2'
}

fn test_calculator_nth_root_real_domains_reciprocals_and_numeric_boundaries() {
	for index, radicand in [27.0, -27.0, -8.0, 16.0, .0625, 0.0, 1e308, 1e-300, 5e-324]! {
		degree := [3.0, 3.0, -3.0, .5, -2.0, 3.0, 2.0, 3.0, 1.0]![index]
		expected := [3.0, -3.0, -.5, 256.0, 4.0, 0.0, 1e154, 1e-100, 5e-324]![index]
		value, status := calculator_nth_root(radicand, degree)
		assert status == '' && math.is_finite(value)
		assert if expected == 0 { value == 0 } else { math.abs(value / expected - 1) < 1e-13 }
	}
	for index, radicand in [4.0, 0.0, -16.0, -27.0, -27.0, -27.0, 1e308, 1e-300]! {
		degree := [0.0, -2.0, 2.0, 2.5, 9007199254740992.0, -2.0, .5, -1.0e-308]![index]
		value, status := calculator_nth_root(radicand, degree)
		assert value == 0
		assert status == if index < 6 { 'calculator.error.domain' } else { 'calculator.error.nonfinite' }
	}
	for nonfinite in [math.inf(1), math.inf(-1), math.nan()]! {
		_, left_status := calculator_nth_root(nonfinite, 3)
		_, right_status := calculator_nth_root(27, nonfinite)
		assert left_status == 'calculator.error.nonfinite'
		assert right_status == 'calculator.error.nonfinite'
	}
}

fn test_calculator_nth_root_pending_unary_repeat_history_memory_and_recovery() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('81')
	app.handle('calculator.scientific.root')!
	assert app.calculator.pending_operator == 'root' && app.calculator.replace_input
	app.key_input('2==')
	assert app.calculator.display == '3'
	assert app.history[0].expression == 'root(81, 2)' && app.history[0].result == '9'
	assert app.history[1].expression == 'root(9, 2)'
	app.handle('calculator.memory.add')!
	app.key_input('c27')
	app.handle('calculator.scientific.root')!
	app.key_input('9')
	app.handle('calculator.scientific.sqrt')!
	assert app.scientific_operand && app.calculator.pending_operator == 'root'
	app.key_input('=')
	assert app.calculator.display == '3'
	assert app.history.last().expression == 'root(27, 3)'
	app.key_input('c2+25')
	app.handle('calculator.scientific.root')!
	app.key_input('2=')
	assert math.abs(app.calculator.display.f64() - math.sqrt(27)) < 1e-14
	app.handle('calculator.history.2')!
	assert app.calculator.display == '3' && app.calculator.pending_operator == ''
	app.key_input('c')
	app.paste_input('-27')
	app.handle('calculator.scientific.root')!
	app.paste_input('-3')
	app.key_input('=')
	assert math.abs(app.calculator.display.f64() + 1.0 / 3) < 1e-14
	app.key_input('c16')
	app.handle('calculator.scientific.root')!
	before := app.history.len
	app.key_input('0=')
	assert app.calculator.has_error && app.scientific_status == 'calculator.error.domain'
	assert app.history.len == before
	app.handle('calculator.memory.recall')!
	assert app.calculator.display == '3' && !app.calculator.has_error
	app.handle('calculator.mode.basic')!
	app.handle('calculator.scientific.root')!
	assert app.calculator.pending_operator == ''
}

fn test_calculator_ee_root_controls_wire_minimum_windows_and_scoped_dispatch() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	previous_language := desktop_language
	defer { set_desktop_language(previous_language) }
	for language in desktop_languages {
		set_desktop_language(language)
		for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
			begin_frame_elements()
			tree := app.build(size)!
			for action in calculator_scientific_entry_actions {
				control := calculator_feature_find(tree, action) or { panic('missing entry control') }
				assert control.kind == .button && control.text == tr(action)
				assert control.tooltip.len > 0
				assert control.frame.x >= 0 && control.frame.x + control.frame.width <= size.width
				assert control.frame.y >= 154 && control.frame.y + control.frame.height < 422
			}
			mut wire := []u8{cap: 65536}
			unsafe { wire.flags |= .noslices }
			encode_app_element(tree, mut wire)!
			mut reader := WireReader{ data: wire }
			decoded := decode_app_element(mut reader, 0)!
			app.key_input('c2')
			ee := calculator_feature_find(decoded, 'calculator.scientific.ee') or { panic('missing wire EE') }
			app.handle(if ee.action_id.len > 0 { ee.action_id } else { ee.id })!
			app.key_input('3')
			root := calculator_feature_find(decoded, 'calculator.scientific.root') or { panic('missing wire root') }
			app.handle(if root.action_id.len > 0 { root.action_id } else { root.id })!
			app.key_input('2=')
			assert math.abs(app.calculator.display.f64() - math.sqrt(2000)) < 1e-13
			free_tree(decoded)
			free_tree(tree)
			unsafe { wire.free() }
		}
	}
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

fn test_calculator_hyperbolic_known_values_symmetry_and_angle_independence() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	actions := ['calculator.scientific.sinh', 'calculator.scientific.cosh',
		'calculator.scientific.tanh', 'calculator.scientific.asinh',
		'calculator.scientific.acosh', 'calculator.scientific.atanh']!
	inputs := ['1', '-1', '1', '-1', '2', '-.5']!
	expressions := ['sinh(1)', 'cosh(-1)', 'tanh(1)', 'asinh(-1)', 'acosh(2)', 'atanh(-0.5)']!
	expected := [1.1752011936438014, 1.5430806348152437, .7615941559557649,
		-.881373587019543, 1.3169578969248166, -.5493061443340548]!
	for angle in ['calculator.angle.degrees', 'calculator.angle.radians']! {
		app.handle(angle)!
		for index, action in actions {
			app.key_input('c')
			app.paste_input(inputs[index])
			app.handle(action)!
			assert !app.calculator.has_error
			assert math.abs(app.calculator.display.f64() - expected[index]) < 1e-14
			assert app.calculator.replace_input
			assert app.history.last().expression == expressions[index]
			assert !app.history.last().expression.ends_with('[DEG]')
			assert !app.history.last().expression.ends_with('[RAD]')
		}
	}
	for index, action in actions {
		value, status := calculator_scientific_value(action, if index == 4 { f64(1) } else { f64(0) }, true)
		assert status == ''
		assert value == if index == 1 { f64(1) } else { f64(0) }
	}
	for action in ['calculator.scientific.sinh', 'calculator.scientific.tanh',
		'calculator.scientific.asinh', 'calculator.scientific.atanh']! {
		positive, positive_status := calculator_scientific_value(action, .25, true)
		negative, negative_status := calculator_scientific_value(action, -.25, false)
		assert positive_status == '' && negative_status == ''
		assert positive == -negative
	}
}

fn test_calculator_hyperbolic_domains_full_finite_range_and_error_recovery() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	for index, action in ['calculator.scientific.acosh', 'calculator.scientific.acosh',
		'calculator.scientific.atanh', 'calculator.scientific.atanh',
		'calculator.scientific.atanh', 'calculator.scientific.atanh',
		'calculator.scientific.sinh', 'calculator.scientific.cosh']! {
		app.key_input('c')
		app.paste_input(['.999999999999999', '-2', '1', '-1', '2', '-2', '711', '-711']![index])
		before := app.history.len
		app.handle(action)!
		assert app.calculator.has_error
		assert app.scientific_status == if index < 6 {
			'calculator.error.domain'
		} else { 'calculator.error.nonfinite' }
		assert app.history.len == before
		app.key_input('7')
		assert !app.calculator.has_error && app.calculator.display == '7'
	}
	for action in ['calculator.scientific.sinh', 'calculator.scientific.cosh']! {
		for input in ['710', '-710']! {
			app.key_input('c')
			app.paste_input(input)
			app.handle(action)!
			assert !app.calculator.has_error && math.is_finite(app.calculator.display.f64())
			assert math.abs(math.abs(app.calculator.display.f64()) / 1.1169973830808557e308 - 1) < 1e-14
		}
	}
	for index, action in ['calculator.scientific.asinh', 'calculator.scientific.acosh',
		'calculator.scientific.tanh', 'calculator.scientific.tanh',
		'calculator.scientific.atanh', 'calculator.scientific.atanh']! {
		app.key_input('c')
		app.paste_input(['-1e308', '1e308', '1e308', '-1e308', '.999999999999999', '1e-300']![index])
		app.handle(action)!
		assert !app.calculator.has_error && math.is_finite(app.calculator.display.f64())
		if index < 2 {
			assert math.abs(math.abs(app.calculator.display.f64()) - 709.889355822726) < 1e-12
		} else if index < 4 {
			assert app.calculator.display == if index == 2 { '1' } else { '-1' }
		} else if index == 4 {
			assert app.calculator.display.f64() > 17
		} else {
			assert math.abs(app.calculator.display.f64() / 1e-300 - 1) < 1e-14
		}
	}
	for action in ['calculator.scientific.sinh', 'calculator.scientific.cosh',
		'calculator.scientific.tanh', 'calculator.scientific.asinh',
		'calculator.scientific.acosh', 'calculator.scientific.atanh']! {
		for input in [math.inf(1), math.inf(-1), math.nan()]! {
			value, status := calculator_scientific_value(action, input, true)
			assert value == 0 && status == 'calculator.error.nonfinite'
		}
	}
}

fn test_calculator_hyperbolic_pending_operands_modes_history_memory_and_copy() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('2+0')
	app.handle('calculator.scientific.cosh')!
	assert app.calculator.pending_operator == '+' && app.calculator.accumulator == 2
	app.key_input('==')
	assert app.calculator.display == '4'
	assert app.history[0].expression == 'cosh(0)'
	assert app.history[1].expression == '2 + 1'
	assert app.history[2].expression == '3 + 1'
	app.key_input('c1')
	app.handle('calculator.scientific.sinh')!
	result := app.calculator.display.clone()
	defer { unsafe { result.free() } }
	app.handle('calculator.memory.add')!
	app.key_input('\x03')
	packet := app.take_clipboard_copy_request()
	defer { unsafe { packet.free() } }
	assert console_borrow(editor_bytes_text(packet), text_copy_header_size, packet.len) == result
	assert app.history.len == 4
	app.handle('calculator.mode.programmer')!
	app.paste_input('0xFF')
	app.key_input('+1=')
	assert app.integer.value == 256 && app.integer.history.len == 1
	app.handle('calculator.scientific.cosh')!
	assert app.integer.value == 256 && app.history.len == 4
	app.key_input('\x13')
	assert !app.programmer
	if !app.scientific { app.key_input('\x13') }
	assert app.calculator.display == result && app.integer.value == 256
	app.handle('calculator.angle.radians')!
	app.handle('calculator.history.0')!
	assert app.calculator.display == result
	app.handle('calculator.scientific.asinh')!
	assert math.abs(app.calculator.display.f64() - 1) < 1e-14
	app.handle('calculator.mode.basic')!
	app.handle('calculator.scientific.cosh')!
	assert math.abs(app.calculator.display.f64() - 1) < 1e-14
	app.key_input('c2+3==')
	assert app.calculator.display == '8'
	app.handle('calculator.mode.scientific')!
	assert !app.degrees
	app.handle('calculator.memory.recall')!
	assert app.calculator.display == result
	app.handle('calculator.scientific.asinh')!
	app.key_input('7')
	assert app.calculator.display == '7'
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

fn test_calculator_hyperbolic_controls_fit_all_scientific_windows_and_dispatch_wire_actions() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566),
		ui2.rect(0, 0, 760, 620)]! {
		begin_frame_elements()
		tree := app.build(size)!
		panel := calculator_feature_find(tree, 'calculator') or { panic('missing keypad') }
		for index, action in calculator_scientific_actions {
			control := calculator_feature_find(tree, action) or { panic('missing scientific control') }
			assert control.kind == .button && control.text == tr(action)
			assert control.frame.width == 40 && control.frame.height == 36
			assert control.frame.x >= 0 && control.frame.x + control.frame.width <= panel.frame.x - 16
			assert control.frame.y >= 154 && control.frame.y + control.frame.height <= 410
			assert control.frame.x + control.frame.width <= size.width
			assert control.frame.y + control.frame.height <= size.height
			if index > 0 {
				previous := calculator_feature_find(tree, calculator_scientific_actions[index - 1]) or { panic('missing previous control') }
				assert control.frame.x >= previous.frame.x + previous.frame.width
					|| control.frame.y >= previous.frame.y + previous.frame.height
			}
		}
		mut encoded := []u8{cap: 65536}
		unsafe { encoded.flags |= .noslices }
		encode_app_element(tree, mut encoded)!
		mut reader := WireReader{ data: encoded }
		decoded := decode_app_element(mut reader, 0)!
		for index, action in ['calculator.scientific.sinh', 'calculator.scientific.cosh',
			'calculator.scientific.tanh', 'calculator.scientific.asinh',
			'calculator.scientific.acosh', 'calculator.scientific.atanh']! {
			control := calculator_feature_find(decoded, action) or { panic('missing wire operation') }
			app.key_input('c')
			app.paste_input(if index == 4 { '1' } else { '0' })
			app.handle(if control.action_id.len > 0 { control.action_id } else { control.id })!
			assert !app.calculator.has_error
			assert app.calculator.display == if index == 1 { '1' } else { '0' }
		}
		free_tree(decoded)
		free_tree(tree)
		unsafe { encoded.free() }
	}
}

fn test_calculator_programmer_parse_exact_limits_prefixes_and_four_base_texts() {
	for index, text in ['18446744073709551615', 'FFFFFFFFFFFFFFFF',
		'1777777777777777777777', '1111111111111111111111111111111111111111111111111111111111111111']! {
		value, status := calculator_integer_parse(text, calculator_programmer_bases[index])
		assert status == '' && value == calculator_programmer_max
		formatted := calculator_integer_text(value, calculator_programmer_bases[index])
		assert formatted == text
		unsafe { formatted.free() }
	}
	for text in ['0xFFFFFFFFFFFFFFFF', '0Xffffffffffffffff', '0o1777777777777777777777',
		'0b1111111111111111111111111111111111111111111111111111111111111111']! {
		value, status := calculator_integer_parse(text, 10)
		assert status == '' && value == calculator_programmer_max
	}
	for index, text in ['18446744073709551616', '10000000000000000',
		'2000000000000000000000', '10000000000000000000000000000000000000000000000000000000000000000']! {
		_, status := calculator_integer_parse(text, calculator_programmer_bases[index])
		assert status == 'calculator.programmer.error.range'
	}
	for text in ['', '-1', '+1', '1.5', '1e3', '0x', '0b', '1\n2', '1 2', '1\x00', '数字']! {
		_, status := calculator_integer_parse(text, 10)
		assert status.len > 0
	}
	_, invalid_base := calculator_integer_parse('1', 3)
	assert invalid_base == 'calculator.programmer.error.input'
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.programmer')!
	app.paste_input('255')
	assert app.integer.decimal_text == '255'
	assert app.integer.hex_text == 'FF'
	assert app.integer.octal_text == '377'
	assert app.integer.binary_text == '11111111'
}

fn test_calculator_programmer_base_entry_keyboard_and_floating_state_are_isolated() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.key_input('2+9')
	app.handle('calculator.scientific.sqrt')!
	assert app.calculator.display == '3'
	assert app.scientific_operand
	app.key_input('\x10\x02')
	assert app.programmer && app.integer.base == 16
	app.key_input('af\x7fC')
	assert app.integer.hex_text == 'AC'
	app.key_input('g')
	assert app.integer.hex_text == 'AC' && app.integer.status == 'calculator.programmer.error.input'
	app.key_input('\x1b[3~\x1b[1~')
	assert app.integer.hex_text == 'AC'
	app.key_input('\x04')
	assert app.degrees
	app.key_input('\x1b\x02')
	assert app.integer.value == 0 && app.integer.base == 8
	app.key_input('78')
	assert app.integer.value == 7
	assert app.integer.status == 'calculator.programmer.error.digit'
	app.key_input('\x02\x1b10101')
	assert app.integer.base == 2 && app.integer.value == 21
	app.key_input('\x02')
	assert app.integer.base == 10 && app.integer.decimal_text == '21'
	app.handle('calculator.programmer.base.hex')!
	app.handle('calculator.programmer.digit.F')!
	assert app.integer.value == 351
	app.key_input('\x10=')
	assert !app.programmer && app.scientific
	assert app.calculator.display == '5'
	app.handle('calculator.mode.programmer')!
	assert app.integer.hex_text == '15F'
	app.handle('calculator.mode.basic')!
	assert !app.programmer && !app.scientific
	assert app.calculator.display == '5'
}

fn test_calculator_programmer_arithmetic_wraps_and_divides_without_float_rounding() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.programmer')!
	app.paste_input('18446744073709551615')
	app.key_input('+1=')
	assert app.integer.value == 0
	assert app.integer.history.last().expression == '18446744073709551615 + 1'
	app.key_input('\x1b0-1=')
	assert app.integer.value == calculator_programmer_max
	app.key_input('*2=')
	assert app.integer.decimal_text == '18446744073709551614'
	app.key_input('\x1b')
	app.paste_input('18446744073709551615')
	app.key_input('/2=')
	assert app.integer.decimal_text == '9223372036854775807'
	app.key_input('\x1b')
	app.paste_input('18446744073709551615')
	app.key_input('%2=')
	assert app.integer.value == 1
	app.key_input('\x1b1+2*3=')
	assert app.integer.value == 9
	app.key_input('=')
	assert app.integer.value == 27
}

fn test_calculator_programmer_bitwise_unsigned_shifts_and_unary_pending_operands() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.programmer')!
	app.key_input('255&15=')
	assert app.integer.value == 15
	app.key_input('\x1b240|15=')
	assert app.integer.value == 255
	app.key_input('\x1b255^15=')
	assert app.integer.value == 240
	app.key_input('\x1b~')
	assert app.integer.value == calculator_programmer_max
	app.key_input('>>1=')
	assert app.integer.decimal_text == '9223372036854775807'
	app.key_input('\x1b1<<63=')
	assert app.integer.decimal_text == '9223372036854775808'
	app.key_input('>>63=')
	assert app.integer.value == 1
	app.key_input('<<0=')
	assert app.integer.value == 1
	app.key_input('\x1b1&0~=')
	assert app.integer.value == 1
	app.key_input('\x1b1')
	app.handle('calculator.programmer.not')!
	assert app.integer.value == calculator_programmer_max - 1
	app.handle('calculator.programmer.shr')!
	app.paste_input('63')
	app.handle('calculator.programmer.equals')!
	assert app.integer.value == 1
}

fn test_calculator_programmer_domain_errors_and_invalid_paste_preserve_values() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.programmer')!
	for operation in ['/', '%', '<', '>']! {
		app.key_input('\x1b7')
		app.key_input(operation)
		app.paste_input(if operation == '/' || operation == '%' { '0' } else { '64' })
		app.key_input('=')
		assert app.integer.has_error
		assert app.integer.value == if operation == '/' || operation == '%' { u64(0) } else { u64(64) }
		assert app.integer.status == if operation == '/' || operation == '%' {
			'calculator.programmer.error.zero'
		} else { 'calculator.programmer.error.shift' }
		assert app.integer.history.len == 0
		app.key_input('5')
		assert !app.integer.has_error && app.integer.value == 5
		assert app.integer.pending == .none
	}
	app.key_input('\x1b42+')
	for text in ['-1', '+3', '3.5', 'NaN', '1e3', '2+3=', '1\n2',
		'18446744073709551616', '0x10000000000000000', '0b2']! {
		app.paste_input(text)
		assert app.integer.value == 42
		assert app.integer.accumulator == 42 && app.integer.pending == .add
		assert !app.integer.has_error && app.integer.status.len > 0
	}
	app.paste_input(' 0x10 ')
	app.key_input('=')
	assert app.integer.value == 58 && app.integer.status == ''
	app.key_input('\x1b')
	app.paste_input('18446744073709551615')
	app.key_input('0')
	assert app.integer.value == calculator_programmer_max
	assert app.integer.status == 'calculator.programmer.error.range'
	app.key_input('\x7f')
	assert app.integer.decimal_text == '1844674407370955161'
	app.paste_input('0')
	assert app.integer.value == 0 && app.integer.status == ''
}

fn test_calculator_programmer_history_is_bounded_exact_and_separate_from_float_history() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.key_input('2+3=')
	assert app.history.len == 1
	app.handle('calculator.mode.programmer')!
	app.paste_input('18446744073709551615')
	app.key_input('-1=')
	for _ in 0 .. 40 { app.key_input('=') }
	assert app.integer.history.len == calculator_history_limit
	assert app.integer.value == calculator_programmer_max - 41
	app.handle('calculator.programmer.base.hex')!
	app.handle('calculator.programmer.history.1')!
	assert app.integer.value == calculator_programmer_max - 40
	assert app.integer.hex_text == 'FFFFFFFFFFFFFFD7'
	app.handle('calculator.programmer.history.next')!
	app.handle('calculator.programmer.history.0')!
	assert app.integer.value == calculator_programmer_max - 40
	app.handle('calculator.programmer.history.previous')!
	app.handle('calculator.programmer.history.0')!
	assert app.integer.value == calculator_programmer_max - 41
	app.handle('calculator.programmer.history.clear')!
	assert app.integer.history.len == 0
	app.handle('calculator.mode.basic')!
	assert app.history.len == 1 && app.calculator.display == '5'
	app.handle('calculator.history.0')!
	assert app.calculator.display == '5'
}

fn test_calculator_programmer_native_controls_readouts_wire_and_compact_layout() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.programmer')!
	app.paste_input('0xFFFFFFFFFFFFFFFF')
	app.handle('calculator.programmer.and')!
	app.paste_input('255')
	app.handle('calculator.programmer.equals')!
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 620, 576))!
	for action in calculator_programmer_key_actions {
		control := calculator_feature_find(tree, action) or { panic('missing integer key') }
		assert control.kind == .button
		assert control.frame.x >= 0 && control.frame.x + control.frame.width <= 620
		assert control.frame.y >= 0 && control.frame.y + control.frame.height <= 576
	}
	for action in calculator_programmer_base_actions {
		assert calculator_feature_find(tree, action) != none
	}
	assert calculator_feature_find(tree, 'calculator.mode.basic') != none
	assert calculator_feature_find(tree, 'calculator.mode.scientific') != none
	assert calculator_feature_find(tree, 'calculator.programmer.history.0') != none
	mut matching_readouts := 0
	for child in tree.children {
		if child.kind == .label && child.text in ['255', 'FF', '377', '11111111']! {
			matching_readouts++
		}
	}
	assert matching_readouts == 4
	mut encoded := []u8{cap: 65536}
	unsafe { encoded.flags |= .noslices }
	encode_app_element(tree, mut encoded)!
	mut reader := WireReader{ data: encoded }
	decoded := decode_app_element(mut reader, 0)!
	assert calculator_feature_find(decoded, 'calculator.programmer.not') != none
	free_tree(decoded)
	free_tree(tree)
	unsafe { encoded.free() }
	for size in [ui2.rect(0, 0, 540, 560), ui2.rect(0, 0, 340, 510)]! {
		begin_frame_elements()
		compact := app.build(size)!
		assert calculator_feature_find(compact, 'calculator.mode.basic') != none
		assert calculator_feature_find(compact, 'calculator.programmer.base.bin') != none
		assert (calculator_feature_find(compact, 'calculator.programmer.not') != none) == (size.width >= 540)
		free_tree(compact)
	}
	app.handle('calculator.programmer.base.bin')!
	app.handle('calculator.programmer.digit.1')!
	assert app.integer.value == 1
}

fn test_calculator_cube_cube_root_log2_domains_and_pending_arithmetic() {
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.scientific')!
	app.paste_input('-2')
	app.handle('calculator.scientific.cube')!
	assert app.calculator.display == '-8'
	assert app.history.last().expression == '(-2)^3'
	app.handle('calculator.scientific.cbrt')!
	assert math.abs(app.calculator.display.f64() + 2) < 1e-14
	assert app.history.last().expression == 'cbrt(-8)'
	app.key_input('c5+8')
	app.handle('calculator.scientific.log2')!
	assert app.calculator.display == '3'
	assert app.history.last().expression == 'log2(8)'
	app.key_input('==')
	assert app.calculator.display == '11'
	app.key_input('c2+')
	app.paste_input('-8')
	app.handle('calculator.scientific.cbrt')!
	app.key_input('==')
	assert app.calculator.display == '-2'
	app.key_input('c0')
	app.handle('calculator.scientific.cbrt')!
	assert app.calculator.display == '0'
	for value in ['0', '-1']! {
		app.key_input('c')
		app.paste_input(value)
		before := app.history.len
		app.handle('calculator.scientific.log2')!
		assert app.calculator.has_error
		assert app.scientific_status == 'calculator.error.domain'
		assert app.history.len == before
	}
	app.key_input('c')
	app.paste_input('1e200')
	app.handle('calculator.scientific.cube')!
	assert app.calculator.has_error
	assert app.scientific_status == 'calculator.error.nonfinite'
	app.key_input('c')
	app.paste_input('-1e300')
	app.handle('calculator.scientific.cbrt')!
	assert !app.calculator.has_error
	assert math.abs(app.calculator.display.f64() / -1e100 - 1) < 1e-14
}

fn test_calculator_copy_snapshots_exact_float_display_without_changing_arithmetic() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.key_input('2+')
	app.paste_input('-12.500')
	app.key_input('\x03')
	assert app.calculator.pending_operator == '+'
	assert app.calculator.accumulator == 2
	assert app.calculator.display == '-12.500'
	assert app.history.len == 0
	app.key_input('=')
	packet := app.take_clipboard_copy_request()
	defer { unsafe { packet.free() } }
	assert console_borrow(editor_bytes_text(packet), text_copy_header_size, packet.len) == '-12.500'
	assert app.calculator.display == '-10.5'
	assert app.history.len == 1
	ack := text_copy_reply(app.copy_client.sequence, true)
	defer { unsafe { ack.free() } }
	app.receive_clipboard_copy_reply(editor_bytes_text(ack))
	assert app.copy_client.status_key() == 'clipboard.copy.copied'
	app.key_input('=')
	assert app.calculator.display == '-23'
	assert app.copy_client.status_key() == ''
	app.handle('calculator.mode.scientific')!
	app.key_input('c')
	app.paste_input('1e-12')
	app.handle('calculator.mode.basic')!
	app.handle('calculator.copy')!
	second := app.take_clipboard_copy_request()
	defer { unsafe { second.free() } }
	assert console_borrow(editor_bytes_text(second), text_copy_header_size, second.len) == '1e-12'
	assert app.history.len == 2
	app.handle('calculator.mode.scientific')!
	app.handle('calculator.scientific.pi')!
	app.key_input('\x03')
	precise := app.take_clipboard_copy_request()
	defer { unsafe { precise.free() } }
	assert console_borrow(editor_bytes_text(precise), text_copy_header_size, precise.len) == '3.14159265358979'
	assert app.calculator.display == '3.14159265358979'
}

fn test_calculator_copy_selected_integer_base_errors_and_acknowledgements() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut app := new_calculator_app()
	defer { app.close_app() }
	app.handle('calculator.mode.programmer')!
	app.paste_input('18446744073709551615')
	for index, action in calculator_programmer_base_actions {
		app.handle(action)!
		app.key_input('\x03')
		packet := app.take_clipboard_copy_request()
		assert console_borrow(editor_bytes_text(packet), text_copy_header_size, packet.len)
			== ['18446744073709551615', 'FFFFFFFFFFFFFFFF', '1777777777777777777777',
				'1111111111111111111111111111111111111111111111111111111111111111']![index]
		unsafe { packet.free() }
		assert app.integer.value == calculator_programmer_max
		assert app.integer.history.len == 0
	}
	old_ack := text_copy_reply(app.copy_client.sequence, true)
	defer { unsafe { old_ack.free() } }
	app.handle('calculator.programmer.base.dec')!
	app.key_input('\x1b7/0=\x03')
	assert app.integer.has_error
	assert app.take_clipboard_copy_request().len == 0
	assert app.copy_client.status_key() == 'clipboard.copy.empty'
	app.receive_clipboard_copy_reply(editor_bytes_text(old_ack))
	assert app.copy_client.status_key() == 'clipboard.copy.empty'
	app.handle('calculator.mode.basic')!
	app.key_input('c1/0=')
	app.handle('calculator.copy')!
	assert app.calculator.has_error
	assert app.take_clipboard_copy_request().len == 0
	app.key_input('c9\x03')
	packet := app.take_clipboard_copy_request()
	defer { unsafe { packet.free() } }
	failed := text_copy_reply(app.copy_client.sequence, false)
	defer { unsafe { failed.free() } }
	app.receive_clipboard_copy_reply('malformed')
	assert app.copy_client.status_key() == 'clipboard.copy.pending'
	app.receive_clipboard_copy_reply(editor_bytes_text(failed))
	assert app.copy_client.status_key() == 'clipboard.copy.failed'
	assert app.calculator.display == '9'
	app_compositor_features = 0
	app.handle('calculator.copy')!
	assert app.copy_client.status_key() == 'clipboard.copy.unavailable'
	assert app.take_clipboard_copy_request().len == 0
	assert app.calculator.display == '9'
}

fn test_calculator_copy_controls_status_and_scientific_rows_fit_native_windows() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut app := new_calculator_app()
	defer { app.close_app() }
	for mode in ['calculator.mode.basic', 'calculator.mode.scientific', 'calculator.mode.programmer']! {
		app.handle(mode)!
		app.handle('calculator.copy')!
		for size in [ui2.rect(0, 0, 620, 566), ui2.rect(0, 0, 540, 560),
			ui2.rect(0, 0, 340, 510), ui2.rect(0, 0, 340, 430), ui2.rect(0, 0, 340, 400)]! {
			begin_frame_elements()
			tree := app.build(size)!
			copy := calculator_feature_find(tree, 'calculator.copy') or { panic('missing Copy') }
			assert copy.kind == .button
			assert copy.text == tr('calculator.copy') || copy.text == tr('clipboard.copy.pending')
			assert copy.frame.x >= 0 && copy.frame.x + copy.frame.width <= size.width
			assert copy.frame.y >= 0 && copy.frame.y + copy.frame.height <= size.height
			if mode == 'calculator.mode.basic' && size.height >= 430 {
				last_mode := calculator_feature_find(tree, 'calculator.mode.programmer') or { panic('missing Programmer mode') }
				assert copy.frame.x >= last_mode.frame.x + last_mode.frame.width
			}
			status := calculator_feature_find(tree, 'calculator.copy.status') or { panic('missing copy status') }
			assert status.text == tr('clipboard.copy.pending')
			assert status.action_id == 'calculator.copy'
				|| status.frame.x >= copy.frame.x + copy.frame.width || status.frame.y >= copy.frame.y + copy.frame.height
			if app.scientific && !app.programmer && size.width >= 540 && size.height >= 430 {
				for action in calculator_scientific_actions {
					control := calculator_feature_find(tree, action) or { panic('missing scientific operation') }
					assert control.frame.y + control.frame.height <= 422
				}
			}
			if mode == 'calculator.mode.programmer' && size.width == 620 {
				assert app.integer.history_rows == 2
			}
			mut wire := []u8{cap: 65536}
			unsafe { wire.flags |= .noslices }
			encode_app_element(tree, mut wire)!
			mut reader := WireReader{ data: wire }
			decoded := decode_app_element(mut reader, 0)!
			assert calculator_feature_find(decoded, 'calculator.copy') != none
			free_tree(decoded)
			free_tree(tree)
			unsafe { wire.free() }
		}
	}
}
