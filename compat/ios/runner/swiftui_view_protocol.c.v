// SPDX-License-Identifier: GPL-2.0-or-later
module main

// View is already shared by Never's concrete conformance and the opacity
// modifier's Body constraint. Export that declaration, preserving its identity
// and its existing arena's publication and quiescent retirement rules.
fn swiftui_view_protocol_symbol(symbol string) ?u64 {
	page := u64(C.getpagesize())
	offset := match symbol {
		'_$s7SwiftUI4ViewMp' { page + 640 }
		'_$s7SwiftUI4ViewTL' { page + 668 }
		'_$s7SwiftUI4ViewP4BodyAC_AaBTn' { page + 676 }
		'_$s4Body7SwiftUI4ViewPTl' { page + 684 }
		'_$s7SwiftUI4ViewP05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZTq' {
			page + 692
		}
		'_$s7SwiftUI4ViewP05_makeC4List4view6inputsAA01_cE7OutputsVAA11_GraphValueVyxG_AA01_cE6InputsVtFZTq' {
			page + 700
		}
		'_$s7SwiftUI4ViewP14_viewListCount6inputsSiSgAA01_ceF6InputsV_tFZTq' { page + 708 }
		'_$s7SwiftUI4ViewP4body4BodyQzvgTq' { page + 716 }
		else { return none }
	}
	base := swiftui_opacity_arena_checked() or { return none }
	return base + offset
}

// Only the three graph requirements have defaults. Native uses private
// non-PAAE thunks, distinct from the exported protocol-extension defaults.
// Until graph execution exists, each terminates with its specific diagnostic
// before reading resilient inputs or writing caller result storage.
fn swiftui_view_protocol_emit(base u64, view u64) {
	for i, target in [u64(unsafe { voidptr(swiftui_view_default_make_unavailable) }),
		u64(unsafe { voidptr(swiftui_view_default_list_unavailable) }),
		u64(unsafe { voidptr(swiftui_view_default_count_unavailable) })]! {
		entry := base + 224 + u64(i * 16)
		write32(entry, 0x58000050)
		write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
		swift_protocol_relative(view + 56 + u64(i * 8), entry)
	}
}
