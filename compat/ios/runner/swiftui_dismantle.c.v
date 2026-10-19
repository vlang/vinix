// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This resolves only the protocol extension's empty default implementation.
// The view and indirect generic coordinator are borrowed; this hook does not
// release them, dispatch a custom witness, or remove a view from its parent.
// No argument, metadata, witness or Swift context storage is accessed.
fn swiftui_dismantle_view(view u64, coordinator u64, metadata u64, witness u64) {}

fn swiftui_dismantle_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZ' { return none }
	return u64(unsafe { voidptr(swiftui_dismantle_view) })
}
