// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if arm64 {
	// The protocol extension's default declines a preferred size. Swift returns
	// Optional<CGSize> in x0/x1/w2, unlike C's indirect result for 24 bytes.
	// Proposal, view, context, generic witnesses and Swift self remain borrowed.
	@[_naked]
	fn swiftui_sizing_none() {
		asm volatile arm64 {
			mov x0, 0
			mov x1, 0
			mov w2, 1
			ret
		}
	}
}

fn swiftui_sizing_symbol(symbol string) ?u64 {
	$if arm64 {
		if symbol == '_$s7SwiftUI19UIViewRepresentablePAAE12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtF' {
			return u64(unsafe { voidptr(swiftui_sizing_none) })
		}
	}
	return none
}
