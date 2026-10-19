// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Binding this entry allows other imports to be inspected. Constructing its
// unary list requires the SwiftUI graph engine, which is not available yet.
// Never return an uninitialized _ViewListOutputs through Swift's x8 result.
// No incoming graph, inputs, metadata, witness or result storage is accessed.
@[noreturn]
fn swiftui_view_list_unavailable() {
	panic('iOS: SwiftUI UIViewRepresentable view-list graph construction is not implemented')
}

fn swiftui_view_list_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZ' { return none }
	return u64(unsafe { voidptr(swiftui_view_list_unavailable) })
}
