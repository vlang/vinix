// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This binding permits inspection of later imports. A real factory needs the
// platform adapter, SwiftUI graph engine and resilient _ViewOutputs result.
// Stop before reading graph/inputs/metadata/witness/self or writing x8 storage.
// Resolving this diagnostic entry does not create a view or provide rendering.
@[noreturn]
fn swiftui_view_factory_unavailable() {
	panic('iOS: SwiftUI UIViewRepresentable view graph construction is not implemented')
}

fn swiftui_view_factory_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE9_makeView4view6inputsAA01_F7OutputsVAA11_GraphValueVyxG_AA01_F6InputsVtFZ' { return none }
	return u64(unsafe { voidptr(swiftui_view_factory_unavailable) })
}
