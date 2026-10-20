// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native State.projectedValue returns an owned Binding<Value>: a Transaction,
// an AnyLocation object and a cached Value. Even a nil State location builds
// a constant location that owns its own Value. Binding metadata, location
// construction/virtual operations and transactions remain unsupported. Stop
// before reading State/Value metadata, borrowing Self or initializing x8.
@[noreturn]
fn swiftui_state_projected_unavailable() {
	panic('iOS: SwiftUI State.projectedValue Binding construction is not implemented')
}

fn swiftui_state_projected_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI5StateV14projectedValueAA7BindingVyxGvg' { return none }
	return u64(unsafe { voidptr(swiftui_state_projected_unavailable) })
}
