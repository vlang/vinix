// SPDX-License-Identifier: GPL-2.0-or-later
// Local Win64 graphical probe; compile through wine-pe-check.v.
module main

#include <stdio.h>
#include <stdlib.h>
fn C.strtod(&char, voidptr) f64

// Fixed storage keeps button handling independent of V's allocator under
// -gc none. The layout and arithmetic match tests/wine/calculator.c.
struct Calculator {
mut:
	text [64]u8
	length int = 1
	accumulator f64
	pending u8
	replace bool = true
}

fn new_calculator() Calculator {
	mut value := Calculator{}
	value.text[0] = `0`
	return value
}

fn (calculator &Calculator) value() f64 {
	return C.strtod(unsafe { &char(&calculator.text[0]) }, unsafe { nil })
}

fn (mut calculator Calculator) show(value f64) {
	length := unsafe { int(C.snprintf(&char(&calculator.text[0]), usize(calculator.text.len), c'%.12g', value)) }
	if length < 1 || length >= calculator.text.len {
		calculator.text[0] = `0`
		calculator.text[1] = 0
		calculator.length = 1
		return
	}
	calculator.length = length
}

fn calculate(left f64, right f64, operation u8) f64 {
	return match operation {
		`+` { left + right }
		`-` { left - right }
		`*` { left * right }
		`/` { if right == 0 { f64(0) } else { left / right } }
		else { right }
	}
}

fn (mut calculator Calculator) press(button u8) bool {
	if button >= `0` && button <= `9` {
		if calculator.replace { calculator.length = 0; calculator.replace = false }
		if calculator.length < calculator.text.len - 1 {
			calculator.text[calculator.length] = button
			calculator.length++
			calculator.text[calculator.length] = 0
		}
		return true
	}
	if button == `C` { calculator = new_calculator(); return true }
	if button in [`+`, `-`, `*`, `/`]! {
		calculator.accumulator = calculate(calculator.accumulator, calculator.value(), calculator.pending)
		calculator.show(calculator.accumulator)
		calculator.pending = button
		calculator.replace = true
		return true
	}
	if button == `=` {
		if calculator.pending != 0 {
			calculator.accumulator = calculate(calculator.accumulator, calculator.value(), calculator.pending)
			calculator.show(calculator.accumulator)
			calculator.pending = 0
		}
		calculator.replace = true
		return true
	}
	return false
}

$if windows {
	#include <windows.h>
	struct C.HWND__ {}
	@[typedef]
	struct C.WNDCLASSA {
	mut:
		lpfnWndProc fn (&C.HWND__, u32, usize, isize) isize
		hInstance voidptr
		hCursor voidptr
		hbrBackground voidptr
		lpszClassName &char
	}
	@[typedef]
	struct C.MSG { wParam usize }
	fn C.GetModuleHandleA(&char) voidptr
	fn C.LoadCursorA(voidptr, &char) voidptr
	fn C.RegisterClassA(&C.WNDCLASSA) u16
	fn C.UnregisterClassA(&char, voidptr) int
	fn C.CreateWindowExA(u32, &char, &char, u32, int, int, int, int, voidptr, voidptr, voidptr, voidptr) voidptr
	fn C.GetWindowLongPtrA(voidptr, int) isize
	fn C.SetWindowLongPtrA(voidptr, int, isize) isize
	fn C.SetWindowTextA(voidptr, &char) int
	fn C.ShowWindow(voidptr, int) int
	fn C.UpdateWindow(voidptr) int
	fn C.GetMessageA(&C.MSG, voidptr, u32, u32) int
	fn C.TranslateMessage(&C.MSG) int
	fn C.DispatchMessageA(&C.MSG) isize
	fn C.DefWindowProcA(voidptr, u32, usize, isize) isize
	fn C.PostQuitMessage(int)
	fn C.DestroyWindow(voidptr) int
	fn C.GetStdHandle(u32) voidptr
	fn C.WriteFile(voidptr, voidptr, u32, voidptr, voidptr) int

	struct CalculatorWindow {
	mut:
		calculator Calculator
		display voidptr
		closed bool
	}

	fn output(text string) {
		mut written := u32(0)
		C.WriteFile(C.GetStdHandle(u32(0xfffffff5)), text.str, u32(text.len), unsafe { voidptr(&written) }, unsafe { nil })
	}

	fn window_proc(window &C.HWND__, message u32, wparam usize, lparam isize) isize {
		if message == 0x0002 { // WM_DESTROY
			pointer := C.GetWindowLongPtrA(window, -21)
			if pointer != 0 {
				mut context := unsafe { &CalculatorWindow(voidptr(pointer)) }
				context.closed = true
				C.SetWindowLongPtrA(window, -21, 0)
			}
			output('VINIX WIN64 CALCULATOR CLOSED\n')
			C.PostQuitMessage(0)
			return 0
		}
		if message == 0x0111 && wparam >> 16 == 0 { // WM_COMMAND, BN_CLICKED
			pointer := C.GetWindowLongPtrA(window, -21) // GWLP_USERDATA
			if pointer != 0 {
				mut context := unsafe { &CalculatorWindow(voidptr(pointer)) }
				id := wparam & 0xffff
				if id <= 255 && context.calculator.press(u8(id)) {
					C.SetWindowTextA(context.display, &char(&context.calculator.text[0]))
					if id == `=` {
						output('VINIX WIN64 CALCULATOR RESULT ')
						output(unsafe { tos(&context.calculator.text[0], context.calculator.length) })
						output('\n')
					}
					return 0
				}
			}
		}
		return C.DefWindowProcA(window, message, wparam, lparam)
	}

	fn run_window() ! {
		instance := C.GetModuleHandleA(unsafe { nil })
		class := C.WNDCLASSA{
			lpfnWndProc: window_proc
			hInstance: instance
			hCursor: C.LoadCursorA(unsafe { nil }, unsafe { &char(usize(32512)) })
			hbrBackground: voidptr(usize(16)) // COLOR_BTNFACE + 1
			lpszClassName: c'VinixVWineCalculator'
		}
		if C.RegisterClassA(unsafe { &class }) == 0 { return error('calculator window class failed') }
		defer { C.UnregisterClassA(c'VinixVWineCalculator', instance) }
		window := C.CreateWindowExA(0, c'VinixVWineCalculator', c'Calculator', 0x00ca0000,
			100, 100, 326, 430, unsafe { nil }, unsafe { nil }, instance, unsafe { nil })
		if window == unsafe { nil } { return error('calculator window failed') }
		mut context := CalculatorWindow{calculator: new_calculator()}
		// The callback borrows this stack object only while this message loop is
		// active. Destroy/detach the window before returning from this function.
		C.SetWindowLongPtrA(window, -21, isize(unsafe { &context }))
		defer {
			if !context.closed {
				C.SetWindowLongPtrA(window, -21, 0)
				C.DestroyWindow(window)
			}
		}
		// Standard controls use USER32's default font; this probe needs no GDI
		// allocation or additional producer linker inputs.
		context.display = C.CreateWindowExA(0x200, c'EDIT', c'0', 0x50000802,
			16, 18, 278, 58, window, voidptr(usize(100)), instance, unsafe { nil })
		if context.display == unsafe { nil } { return error('calculator display failed') }
		for index, label in ['7', '8', '9', '/', '4', '5', '6', '*', '1', '2', '3', '-', 'C', '0', '=', '+']! {
			button := C.CreateWindowExA(0, c'BUTTON', &char(label.str), 0x50000000,
				16 + (index % 4) * 71, 92 + (index / 4) * 70, 65, 60, window,
				voidptr(usize(label[0])), instance, unsafe { nil })
			if button == unsafe { nil } { return error('calculator button failed') }
		}
		C.ShowWindow(window, 1)
		C.UpdateWindow(window)
		output('VINIX WIN64 CALCULATOR READY\n')
		mut message := C.MSG{}
		for {
			status := C.GetMessageA(unsafe { &message }, unsafe { nil }, 0, 0)
			if status < 0 { return error('calculator message read failed') }
			if status == 0 { break }
			C.TranslateMessage(&message)
			C.DispatchMessageA(&message)
		}
		if message.wParam != 0 { return error('calculator message loop failed') }
	}
}

fn main() {
	$if windows {
		run_window() or { eprintln(err); exit(1) }
	} $else {
		panic('the graphical calculator requires Windows or Wine')
	}
}
