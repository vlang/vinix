// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Text.bold borrows storage/modifiers in x0-x3 and returns an owned Text.
// Modifier arrays and their boxed values are unsupported. Stop before
// inspecting input storage or returning a Text that silently loses styling.
@[noreturn]
fn swiftui_text_bold_unavailable() {
	panic('iOS: SwiftUI Text.bold modifier construction is not implemented')
}

fn swiftui_text_bold_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI4TextV4boldACyF' { return none }
	return u64(unsafe { voidptr(swiftui_text_bold_unavailable) })
}
