// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Frozen ZStack stores Tree<_ZStackLayout, Content>. Construction evaluates
// a borrowed builder once into dependent Content storage. Tree/ZStack generic
// metadata and ownership remain unsupported. Stop before invoking the builder,
// touching metadata/owners or writing the indirect result in x8.
@[noreturn]
fn swiftui_zstack_init_unavailable() {
	panic('iOS: SwiftUI ZStack content construction is not implemented')
}

fn swiftui_zstack_init_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI6ZStackV9alignment7contentACyxGAA9AlignmentV_xyXEtcfC' { return none }
	return u64(unsafe { voidptr(swiftui_zstack_init_unavailable) })
}
