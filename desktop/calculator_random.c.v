// SPDX-License-Identifier: GPL-2.0-or-later
// Rand installs a fresh operand without consuming the pending binary operation.
module main

// Every representable result is a multiple of 2^-53, including zero and the
// greatest such value below one. Ignore the low bits rather than round a u64.
fn calculator_random_value(bits u64) f64 {
	return f64(bits >> 11) / 9007199254740992.0
}

// The caller owns a nonblocking descriptor. Partial reads and interruptions
// have a fixed attempt budget; EOF and unavailable entropy never become zero.
fn calculator_random_bits(fd int) ?u64 {
	if fd < 0 { return none }
	mut bytes := [8]u8{}
	mut offset := 0
	for _ in 0 .. 16 {
		count := desktop_read(fd, unsafe { &bytes[offset] }, u64(8 - offset))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 || count > 8 - offset { return none }
		offset += int(count)
		if offset == 8 {
			mut bits := u64(0)
			for byte in bytes { bits = (bits << 8) | u64(byte) }
			return bits
		}
	}
	return none
}

fn (mut app CalculatorApp) scientific_random_from_fd(fd int) {
	if !app.scientific || app.programmer { return }
	bits := calculator_random_bits(fd) or {
		// Keep the editable operand, pending operation, memory and history intact.
		app.scientific_status = 'calculator.random.unavailable'
		return
	}
	result := calculator_random_value(bits)
	mut text := [32]u8{}
	// Fifteen significant digits would round the upper boundary to "1".
	length := unsafe { C.snprintf(&char(&text[0]), 32, c'%.17g', result) }
	if length <= 0 || length >= 32 {
		app.scientific_status = 'calculator.random.unavailable'
		return
	}
	if app.calculator.has_error { app.clear_calculator() }
	app.set_display(unsafe { tos(&text[0], length) }.clone(), true)
	app.scientific_status = ''
	app.input_percent = false
	app.last_percent = false
	app.exponent_input = false
	app.calculator.last_operator = ''
	app.calculator.last_operand = 0
	app.scientific_operand = true
	app.calculator.replace_input = true
	if app.calculator.pending_operator.len == 0 {
		app.calculator.accumulator = result
		app.calculator.has_accumulator = true
	}
	app.remember_expression(tr('calculator.scientific.random').clone())
}

fn (mut app CalculatorApp) scientific_random() {
	if !app.scientific || app.programmer { return }
	fd := C.open(c'/dev/urandom', C.O_RDONLY | C.O_CLOEXEC | C.O_NONBLOCK | C.O_NOFOLLOW, 0)
	defer { if fd >= 0 { desktop_close(fd) } }
	app.scientific_random_from_fd(fd)
}
