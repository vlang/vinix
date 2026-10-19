// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The extension default leaves the caller's inout _LayoutTraits unchanged.
// Traits, view, generic metadata/witnesses and Swift self remain borrowed.
// No argument or context storage is accessed; custom overrides are not called.
fn swiftui_layout_traits_default(traits u64, view u64, metadata u64, witness u64) {}

fn swiftui_layout_traits_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF' { return none }
	return u64(unsafe { voidptr(swiftui_layout_traits_default) })
}
