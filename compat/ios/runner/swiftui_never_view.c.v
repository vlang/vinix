// SPDX-License-Identifier: GPL-2.0-or-later
module main

@[noreturn]
fn swiftui_never_view_graph_unavailable() {
	panic('iOS: SwiftUI Never View graph construction is not implemented')
}
@[noreturn]
fn swiftui_never_view_body_unavailable() {
	panic('iOS: SwiftUI Never.body must not be called')
}

// Extend the opacity arena, sharing its complete zero-size Never metadata and
// View declaration. Called under the arena lock, before RX/RO publication.
fn swiftui_never_view_emit(base u64, data u64, never u64, descriptor u64, view u64) {
	conformance := data + 944; table := data + 960
	swift_protocol_relative(conformance, view)
	swift_protocol_relative(conformance + 4, data + 1040)
	swift_protocol_relative(conformance + 8, table)
	write32(conformance + 12, 8) // Indirect type descriptor, no generic control.
	unsafe {
		*(&u64(data + 1040)) = descriptor
		*(&u64(table)) = conformance
		*(&u64(table + 8)) = (data + 1024) | 1
		*(&u64(table + 16)) = never // Body is already Complete; no cache write.
		*(&u8(data + 1024)) = 0xff; *(&u8(data + 1025)) = 7
		*(&u64(table + 24)) = base + 192
		*(&u64(table + 32)) = base + 192
		*(&u64(table + 40)) = base + 176
		*(&u64(table + 48)) = base + 208
	}
	// Body == Never and Body: View is this same table. Ignore caller storage.
	swiftui_opacity_symbolic_relative(data + 1026, base + 160)
	write32(base + 160, 0x58000040); write32(base + 164, 0xd65f03c0)
	unsafe { *(&u64(base + 168)) = table }
	// Native _viewListCount returns Optional<Int>.none in x0/w1.
	write32(base + 176, 0xd2800000); write32(base + 180, 0x52800021)
	write32(base + 184, 0xd65f03c0)
	for i, target in [u64(unsafe { voidptr(swiftui_never_view_graph_unavailable) }),
		u64(unsafe { voidptr(swiftui_never_view_body_unavailable) })]! {
		entry := base + 192 + u64(i * 16)
		write32(entry, 0x58000050); write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
	}
}
