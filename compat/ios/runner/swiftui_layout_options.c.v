// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if arm64 {
	// LayoutOptions is resilient: Swift returns it indirectly through x8 even
	// though its current POD representation is one Int. The UIKit extension
	// default initializes rawValue to 1 without inspecting its borrowed view.
	@[_naked]
	fn swiftui_layout_options_default() {
		asm volatile arm64 {
			mov x9, 1
			str x9, [x8]
			ret
		}
	}
}

fn swiftui_layout_options_symbol(symbol string) ?u64 {
	$if arm64 {
		if symbol == '_$s7SwiftUI19UIViewRepresentablePAAE14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ' {
			return u64(unsafe { voidptr(swiftui_layout_options_default) })
		}
	}
	return none
}
