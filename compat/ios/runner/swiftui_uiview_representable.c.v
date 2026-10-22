// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Declaration aliases share the sealed opacity/Never/View arena. Reject names
// before borrowing it, and retain the arena's existing drain/retirement rules.
fn swiftui_uiview_representable_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$s7SwiftUI19UIViewRepresentableMp' { u64(0) }
		'_$s7SwiftUI19UIViewRepresentableTL' { u64(52) }
		'_$s7SwiftUI19UIViewRepresentablePAA4ViewTb' { u64(60) }
		'_$s10UIViewType7SwiftUI0A13RepresentablePTl' { u64(68) }
		'_$s11Coordinator7SwiftUI19UIViewRepresentablePTl' { u64(76) }
		'_$s7SwiftUI19UIViewRepresentableP04makeC07context0C4TypeQzAA0cD7ContextVyxG_tFTq' {
			u64(84)
		}
		'_$s7SwiftUI19UIViewRepresentableP06updateC0_7contexty0C4TypeQz_AA0cD7ContextVyxGtFTq' {
			u64(92)
		}
		'_$s7SwiftUI19UIViewRepresentableP06_resetC0_11coordinator7destroyy0C4TypeQz_11CoordinatorQzyyXEtFTq' {
			u64(100)
		}
		'_$s7SwiftUI19UIViewRepresentableP09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZTq' {
			u64(108)
		}
		'_$s7SwiftUI19UIViewRepresentableP15makeCoordinator0F0QzyFTq' { u64(116) }
		'_$s7SwiftUI19UIViewRepresentableP19_identifiedViewTree2inAA011_IdentifiedfG0O0C4TypeQz_tFTq' {
			u64(124)
		}
		'_$s7SwiftUI19UIViewRepresentableP12sizeThatFits_6uiView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtFTq' {
			u64(132)
		}
		'_$s7SwiftUI19UIViewRepresentableP21_overrideSizeThatFits_2in6uiViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztFTq' {
			u64(140)
		}
		'_$s7SwiftUI19UIViewRepresentableP21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztFTq' {
			u64(148)
		}
		'_$s7SwiftUI19UIViewRepresentableP24_modifyBridgedViewInputsyyAA01_gH0VzFZTq' { u64(156) }
		'_$s7SwiftUI19UIViewRepresentableP14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZTq' {
			u64(164)
		}
		else { return none }
	}
	base := swiftui_opacity_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + 1152 + offset
}

$if arm64 {
	// Native _resetUIView borrows the view/coordinator and synchronously invokes
	// destroy once. Swift passes its closure function/context in x2/x3; the
	// context becomes Swift self in x20. Preserve the caller's self and frame.
	@[_naked]
	fn swiftui_uiview_representable_reset() {
		asm volatile arm64 {
			sub sp, sp, 32
			stp x20, x19, [sp]
			stp x29, x30, [sp, 16]
			add x29, sp, 16
			mov x20, x3
			blr x2
			ldp x29, x30, [sp, 16]
			ldp x20, x19, [sp]
			add sp, sp, 32
			ret
		}
	}
}

// Called under the arena lock before publication. The signature refers to the
// existing canonical View and Never descriptors, never synthetic copies.
fn swiftui_uiview_representable_emit(base u64, data u64, view u64) {
	descriptor := data + 1152
	write32(descriptor, 0x30043)
	swift_protocol_relative(descriptor + 4, data + 192)
	swift_protocol_relative(descriptor + 8, data + 1344)
	write32(descriptor + 12, 3)
	write32(descriptor + 16, 14)
	swift_protocol_relative(descriptor + 20, data + 1376)
	C.memcpy(voidptr(data + 1344), c'UIViewRepresentable', 20)
	C.memcpy(voidptr(data + 1376), c'UIViewType Coordinator', 23)
	C.memcpy(voidptr(data + 1400), c'x', 2)
	// Self: View, Self.Body == Never, Self.UIViewType: UIKit.UIView.
	write32(descriptor + 24, 0x80)
	swift_protocol_relative(descriptor + 28, data + 1400)
	swift_protocol_relative(descriptor + 32, view)
	write32(descriptor + 36, 1)
	swift_protocol_relative(descriptor + 40, data + 1408)
	swift_protocol_relative(descriptor + 44, data + 1432)
	C.memcpy(voidptr(data + 1408), c'4Body', 5)
	unsafe { *(&u8(data + 1413)) = 1 }
	swiftui_opacity_symbolic_relative(data + 1414, view)
	C.memcpy(voidptr(data + 1418), c'Qz', 3)
	unsafe { *(&u8(data + 1432)) = 1 }
	swiftui_opacity_symbolic_relative(data + 1433, data + 384)
	write32(descriptor + 48, 2)
	swift_protocol_relative(descriptor + 52, data + 1440)
	swift_protocol_relative(descriptor + 56, data + 1472)
	C.memcpy(voidptr(data + 1440), c'10UIViewType', 12)
	unsafe { *(&u8(data + 1452)) = 1 }
	swiftui_opacity_symbolic_relative(data + 1453, descriptor)
	C.memcpy(voidptr(data + 1457), c'Qz', 3)
	C.memcpy(voidptr(data + 1472), c'So6UIViewC', 11)
	for i, flags in [u32(0), 0xf0490007, 0x28a90007, 0x5f4b0011, 0x30cb0011, 0xf4060011, 0x18d40001,
		0xdad40011, 0x21320011, 0xeb0b0011, 0x4ec80011, 0x681f0011, 0x180f0001, 0xe0fc0001]! {
		write32(descriptor + 60 + u64(i * 8), flags)
	}
	// Coordinator defaults to Void. This entry is a mangled type name preceded
	// by FF, not executable code. makeCoordinator itself has no universal default.
	unsafe { *(&u8(data + 1488)) = 0xff }
	C.memcpy(voidptr(data + 1489), c'yt', 3)
	swift_protocol_relative(descriptor + 80, data + 1489)
	$if arm64 {
		// Private defaults stay distinct from the public extension exports. Native
		// folds the four empty defaults to one address; preserve that identity.
		for i, target in [u64(unsafe { voidptr(swiftui_uiview_representable_reset) }),
			u64(unsafe { voidptr(swiftui_dismantle_view) }),
			u64(unsafe { voidptr(swiftui_identified_tree_unavailable) }),
			u64(unsafe { voidptr(swiftui_sizing_none) }),
			u64(unsafe { voidptr(swiftui_layout_options_default) })]! {
			entry := base + 272 + u64(i * 16)
			write32(entry, 0x58000050)
			write32(entry + 4, 0xd61f0200)
			unsafe { *(&u64(entry + 8)) = target }
		}
		for i, entry in [u64(0), 0, 0, 0, 0, base + 272, base + 288, 0, base + 304, base + 320,
			base + 288, base + 288, base + 288, base + 336]! {
			if entry != 0 { swift_protocol_relative(descriptor + 64 + u64(i * 8), entry) }
		}
	}
}
