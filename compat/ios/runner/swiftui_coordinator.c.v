// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This constrained extension default returns Swift Void, which has no value
// bytes. It creates no coordinator and accesses no borrowed self, metadata,
// witnesses or x8 storage. Custom coordinator implementations are not dispatched
// by this direct default entry.
fn swiftui_coordinator_default() {}

fn swiftui_coordinator_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAyt11CoordinatorRtzrlE04makeE0yyF' { return none }
	return u64(unsafe { voidptr(swiftui_coordinator_default) })
}
