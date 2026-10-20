// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Default View witnesses need the graph engine and Body's View conformance.
// Inputs and outputs are resilient values; an empty result or an invented
// list count would hide an unsupported traversal. Stop before reading caller
// graph/inputs/metadata/witness/Self or writing the indirect result storage.
@[noreturn]
fn swiftui_view_default_make_unavailable() {
	panic('iOS: SwiftUI View._makeView graph construction is not implemented')
}
@[noreturn]
fn swiftui_view_default_list_unavailable() {
	panic('iOS: SwiftUI View._makeViewList graph construction is not implemented')
}
@[noreturn]
fn swiftui_view_default_count_unavailable() {
	panic('iOS: SwiftUI View._viewListCount graph traversal is not implemented')
}

fn swiftui_view_defaults_symbol(symbol string) ?u64 {
	target := match symbol {
		'_$s7SwiftUI4ViewPAAE05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZ' { u64(unsafe { voidptr(swiftui_view_default_make_unavailable) }) }
		'_$s7SwiftUI4ViewPAAE05_makeC4List4view6inputsAA01_cE7OutputsVAA11_GraphValueVyxG_AA01_cE6InputsVtFZ' { u64(unsafe { voidptr(swiftui_view_default_list_unavailable) }) }
		'_$s7SwiftUI4ViewPAAE14_viewListCount6inputsSiSgAA01_ceF6InputsV_tFZ' { u64(unsafe { voidptr(swiftui_view_default_count_unavailable) }) }
		else { return none }
	}
	return target
}
