// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The empty default still requires the resilient _IdentifiedViewTree enum's
// metadata, layout and value witnesses. Those are not implemented yet.
// Stop before accessing borrowed view/self/metadata or caller-owned x8 storage.
// Resolving this diagnostic entry does not provide an empty tree or rendering.
@[noreturn]
fn swiftui_identified_tree_unavailable() {
	panic('iOS: SwiftUI UIViewRepresentable identified-view tree result is not implemented')
}

fn swiftui_identified_tree_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE19_identifiedViewTree2inAA011_IdentifiedfG0O0C4TypeQz_tF' { return none }
	return u64(unsafe { voidptr(swiftui_identified_tree_unavailable) })
}
