// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native disabled(_:) returns ModifiedContent<Self, Transform<Bool>> with an
// owned WritableKeyPath<EnvironmentValues, Bool> and captured closure. That
// closure combines inherited isEnabled with !disabled; returning Self or an
// opacity modifier would lose the environment behavior. Key-path construction
// and this environment transform remain unsupported. Stop before borrowing
// Self, copying owners, allocating a closure or initializing the result in x8.
@[noreturn]
fn swiftui_view_disabled_unavailable() {
	panic('iOS: SwiftUI View.disabled environment transform construction is not implemented')
}

fn swiftui_view_disabled_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI4ViewPAAE8disabledyQrSbF' { return none }
	return u64(unsafe { voidptr(swiftui_view_disabled_unavailable) })
}
