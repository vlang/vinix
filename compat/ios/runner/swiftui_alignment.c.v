// SPDX-License-Identifier: GPL-2.0-or-later
module main

// AlignmentKey is a POD UInt identity, not a metadata pointer. Native keys
// depend on initialization order: bit 0 identifies the axis, higher bits
// identify the registered alignment. Reserve identities 1 and 2 for center;
// future alignment registrations must use distinct identities starting at 3.
const swiftui_horizontal_center_key = u64(2)
const swiftui_vertical_center_key = u64(5)

struct SwiftUIAlignmentValue {
	horizontal u64
	vertical u64
}

fn swiftui_horizontal_center() u64 { return swiftui_horizontal_center_key }

// Two POD words return directly in x0/x1 under both C and Swift ARM64 ABIs.
fn swiftui_alignment_center() SwiftUIAlignmentValue {
	return SwiftUIAlignmentValue{swiftui_horizontal_center_key, swiftui_vertical_center_key}
}

fn swiftui_alignment_symbol(symbol string) ?u64 {
	return match symbol {
		'_$s7SwiftUI19HorizontalAlignmentV6centerACvgZ' { u64(unsafe { voidptr(swiftui_horizontal_center) }) }
		'_$s7SwiftUI9AlignmentV6centerACvgZ' { u64(unsafe { voidptr(swiftui_alignment_center) }) }
		else { none }
	}
}
