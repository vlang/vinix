// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This extension default leaves the caller's inout CGSize unchanged.
// No proposal, view, Swift self, metadata/witness or x8 storage is accessed.
// Custom sizing overrides are not dispatched by this direct default entry.
fn swiftui_size_override_default() {}

fn swiftui_size_override_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF' { return none }
	return u64(unsafe { voidptr(swiftui_size_override_default) })
}
