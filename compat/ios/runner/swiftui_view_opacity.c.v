// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftUIOpacityInitialize = fn (u64, u64, u64) u64

// View.opacity borrows indirect Self and initializes the frozen two-field
// ModifiedContent<Self, _OpacityEffect> result. Copy through Self's witness:
// views can own references or use out-of-line existential storage. The Double
// follows Self's size rounded up to alignment eight, not Self's stride.
fn swiftui_view_opacity(result u64, self_value u64, metadata u64, opacity f64) {
	witness := read64(metadata - 8)
	size := read64(witness + 64)
	if size > ~u64(0) - 15 { panic('iOS: SwiftUI View.opacity result size overflow') }
	modifier_offset := (size + 7) & ~u64(7)
	initialize := unsafe { SwiftUIOpacityInitialize(voidptr(read64(witness + 16))) }
	initialize(result, self_value, metadata)
	unsafe { *(&f64(result + modifier_offset)) = opacity }
}

fn swiftui_view_opacity_emit(code u64) {
	// Swift x0 metadata, x1 unused View table, x20 Self, d0 opacity, x8 result
	// -> ordinary V x0 result, x1 Self, x2 metadata, d0 opacity. Tail call keeps
	// Swift context/error registers x20/x21 intact. The existing opacity arena
	// seals and retires this adapter with its metadata after callbacks drain.
	write32(code, 0xaa0003e2) // mov x2,x0
	write32(code + 4, 0xaa1403e1) // mov x1,x20
	write32(code + 8, 0xaa0803e0) // mov x0,x8
	write32(code + 12, 0x58000070) // ldr x16,literal at +24
	write32(code + 16, 0xd61f0200) // br x16
	unsafe { *(&u64(code + 24)) = u64(voidptr(swiftui_view_opacity)) }
}

fn swiftui_view_opacity_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI4ViewPAAE7opacityyQrSdF' { return none }
	base := swiftui_opacity_arena_checked() or { return none }
	return base + 128
}
