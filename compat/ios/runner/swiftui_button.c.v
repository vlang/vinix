// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Button(action:label:) constructs owned Button<Label> storage. The action
// escapes and transfers its context; the borrowed label closure is evaluated
// once using Label metadata and its View conformance. Button layout/metadata,
// action storage and graph execution remain unsupported. Stop before invoking
// either closure, touching owners/metadata or initializing the result in x8.
@[noreturn]
fn swiftui_button_unavailable() {
	panic('iOS: SwiftUI Button action/label construction is not implemented')
}

fn swiftui_button_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI6ButtonV6action5labelACyxGyyc_xyXEtcfC' { return none }
	return u64(unsafe { voidptr(swiftui_button_unavailable) })
}
