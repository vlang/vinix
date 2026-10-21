// SPDX-License-Identifier: GPL-2.0-or-later
module main

// SwiftUI's existing Never metadata, accessor and descriptor are canonical.
// Export the declaration through Swift core too, so bound symbolic context
// references open the same type as the associated Body witnesses. The arena
// owns all three records and remains available to draining callbacks.
fn swift_never_nominal_symbol(symbol string) ?u64 {
	if symbol != '_$ss5NeverOMn' { return none }
	base := swiftui_opacity_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + 384
}
