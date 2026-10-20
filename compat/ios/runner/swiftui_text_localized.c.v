// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Takes a key, optional table/bundle and comment, returning Text in x0-x3.
// Native construction consumes the key/table into a LocalizedTextStorage provider;
// it cannot be represented by verbatim String storage. Provider construction,
// localization and its virtual methods remain unsupported.
@[noreturn]
fn swiftui_text_localized_unavailable() {
	panic('iOS: SwiftUI Text localized storage construction is not implemented')
}

fn swiftui_text_localized_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI4TextV_9tableName6bundle7commentAcA18LocalizedStringKeyV_SSSgSo8NSBundleCSgs06StaticI0VSgtcfC' { return none }
	return u64(unsafe { voidptr(swiftui_text_localized_unavailable) })
}
