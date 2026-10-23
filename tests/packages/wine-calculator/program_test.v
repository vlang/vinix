// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn check_display(calculator &Calculator, expected string) {
	if calculator.length != expected.len { panic('calculator result length differs') }
	for index, byte in expected {
		if calculator.text[index] != byte { panic('calculator result differs') }
	}
	if calculator.text[calculator.length] != 0 { panic('calculator result lost its terminator') }
}

fn check_sequence(keys string, expected string) {
	// The pinned compiler promotes mutable receiver locals to the heap. Own
	// and retire that fixture explicitly; the Win32 context stays on its stack.
	mut calculator := &Calculator{}
	defer { unsafe { free(calculator) } }
	calculator.press(`C`)
	for key in keys {
		if !calculator.press(key) { panic('calculator refused a supported button') }
	}
	check_display(calculator, expected)
}

fn test_calculator_button_sequences() {
	check_sequence('', '0')
	check_sequence('=', '0')
	check_sequence('12+=', '24')
	check_sequence('12++3=', '27')
	check_sequence('12+30=', '42')
	check_sequence('9-12=', '-3')
	check_sequence('7*8=', '56')
	check_sequence('7/2=', '3.5')
	check_sequence('7/0=', '0')
	check_sequence('12+3*4=', '60')
	check_sequence('12+3==', '15')
	check_sequence('12+3=7', '7')
	check_sequence('123C4', '4')
	check_sequence('9*9C2+3=', '5')
	check_sequence('0-1+2=', '1')
	println('WIN64 CALCULATOR arithmetic, clear, chained operators and input replacement PASS')
}

fn test_calculator_fixed_input_bound_and_unknown_buttons() {
	mut calculator := &Calculator{}
	defer { unsafe { free(calculator) } }
	calculator.press(`C`)
	for _ in 0 .. 1000 { calculator.press(`9`) }
	if calculator.length != 63 || calculator.text[63] != 0 { panic('calculator input bound differs') }
	before := *calculator
	for code in 0 .. 256 {
		button := u8(code)
		if (button >= `0` && button <= `9`) || button in [`C`, `+`, `-`, `*`, `/`, `=`]! { continue }
		if calculator.press(button) || *calculator != before { panic('calculator unknown button changed state') }
	}
	calculator.press(`C`)
	if *calculator != new_calculator() { panic('calculator clear did not reset complete state') }
	println('WIN64 CALCULATOR fixed input bound, terminator, unknown button and reset PASS')
}

fn check_format_extremes() {
	mut calculator := &Calculator{}
	defer { unsafe { free(calculator) } }
	calculator.show(1.7976931348623157e308)
	check_display(calculator, '1.79769313486e+308')
	calculator.show(2.2250738585072014e-308)
	check_display(calculator, '2.22507385851e-308')
	calculator.show(-123456789012345.0)
	check_display(calculator, '-1.23456789012e+14')
	calculator.show(0.125)
	check_display(calculator, '0.125')
	calculator.show(0)
	check_display(calculator, '0')
	calculator.show(calculate(1.7976931348623157e308, 2, `*`))
	if calculator.length < 1 || calculator.length >= 64 || calculator.text[calculator.length] != 0 {
		panic('calculator overflow formatting escaped its fixed buffer')
	}
	calculator.press(`C`)
	check_display(calculator, '0')
}

fn test_calculator_format_extremes() {
	check_format_extremes()
	println('WIN64 CALCULATOR largest/smallest finite, exponent, fractional and overflow formatting PASS')
}

fn test_calculator_repeated_buttons_retain_no_v_allocations() {
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 10000 {
		check_sequence('12+30=', '42')
		check_sequence('7/2=', '3.5')
		check_sequence('9*9C2+3=', '5')
		check_format_extremes()
	}
	$if track_heap ? {
		if C.vinix_heap_end() != 0 || C.vinix_heap_count() != 0 { panic('calculator retains V allocations') }
	}
	println('WIN64 CALCULATOR 10000 arithmetic/clear button cycles retain zero tracked V bytes PASS')
}
