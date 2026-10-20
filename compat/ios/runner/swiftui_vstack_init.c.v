// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Frozen VStack stores Tree<_VStackLayout, Content>. Construction evaluates
// a borrowed builder once into dependent Content storage. Tree/VStack generic
// metadata and ownership remain unsupported. Stop before invoking the builder,
// touching metadata/owners or writing the indirect result in x8.
@[noreturn]
fn swiftui_vstack_init_unavailable() {
	panic('iOS: SwiftUI VStack content construction is not implemented')
}

fn swiftui_vstack_init_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI6VStackV9alignment7spacing7contentACyxGAA19HorizontalAlignmentV_12CoreGraphics7CGFloatVSgxyXEtcfC' { return none }
	return u64(unsafe { voidptr(swiftui_vstack_init_unavailable) })
}
