// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Font.title returns an owned AnyFontBox provider in x0. Provider construction,
// its virtual methods and rendering are unsupported; fail before returning an
// invalid Font value or inspecting caller contexts/result storage.
@[noreturn]
fn swiftui_font_title_unavailable() {
	panic('iOS: SwiftUI Font.title provider construction is not implemented')
}

fn swiftui_font_title_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI4FontV5titleACvgZ' { return none }
	return u64(unsafe { voidptr(swiftui_font_title_unavailable) })
}
