// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The static extension default does not modify the opaque inout _ViewInputs.
// No input, metadata/witness, Swift context or x8 storage is accessed. This
// direct default entry does not dispatch custom representable implementations.
fn swiftui_bridged_inputs_default() {}

fn swiftui_bridged_inputs_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE24_modifyBridgedViewInputsyyAA01_gH0VzFZ' { return none }
	return u64(unsafe { voidptr(swiftui_bridged_inputs_default) })
}
