// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Text.font borrows an optional Font in x0 and Text in x1-x4, returning an
// owned Text in x0-x3. Nil also adds a modifier. Modifier-array construction
// and provider ownership are unsupported; stop before reading caller values.
@[noreturn]
fn swiftui_text_font_unavailable() {
	panic('iOS: SwiftUI Text.font modifier construction is not implemented')
}

fn swiftui_text_font_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI4TextV4fontyAcA4FontVSgF' { return none }
	return u64(unsafe { voidptr(swiftui_text_font_unavailable) })
}
