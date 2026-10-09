// SPDX-License-Identifier: GPL-2.0-or-later
// Typed GCKeyCode values measured from the installed Mac GameController.
module main

fn game_key_symbol(symbol string) ?u64 {
	value := match symbol {
		'_GCKeyCodeDeleteOrBackspace' { i64(42) }
		'_GCKeyCodeSpacebar' { i64(44) }
		'_GCKeyCodeCapsLock' { i64(57) }
		'_GCKeyCodeF1' { i64(58) }
		'_GCKeyCodeF2' { i64(59) }
		'_GCKeyCodeF3' { i64(60) }
		'_GCKeyCodeF4' { i64(61) }
		'_GCKeyCodeF5' { i64(62) }
		'_GCKeyCodeF6' { i64(63) }
		'_GCKeyCodeF7' { i64(64) }
		'_GCKeyCodeF8' { i64(65) }
		'_GCKeyCodeF9' { i64(66) }
		'_GCKeyCodeF10' { i64(67) }
		'_GCKeyCodeF11' { i64(68) }
		'_GCKeyCodeF12' { i64(69) }
		'_GCKeyCodeLeftControl' { i64(224) }
		'_GCKeyCodeLeftShift' { i64(225) }
		'_GCKeyCodeLeftAlt' { i64(226) }
		'_GCKeyCodeLeftGUI' { i64(227) }
		'_GCKeyCodeRightControl' { i64(228) }
		'_GCKeyCodeRightShift' { i64(229) }
		'_GCKeyCodeRightAlt' { i64(230) }
		'_GCKeyCodeRightGUI' { i64(231) }
		else { return none }
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if address := ios_runtime.framework_data[symbol] { return address }
	cell := C.calloc(1, 8)
	if cell == unsafe { nil } { panic('iOS: cannot allocate key-code constant') }
	unsafe { *(&i64(cell)) = value }
	ios_runtime.framework_data[symbol] = u64(cell)
	return u64(cell)
}
