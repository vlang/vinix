// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift stores a little-endian UInt32, truncating narrow elements and clearing
// the tail of wider ones. In particular an empty case clears its whole payload.
fn swift_enum_store_multi_element(address u64, value u32, count u64) {
	for i in u64(0)..if count < 4 { count } else { u64(4) } {
		unsafe { *(&u8(address + i)) = u8(value >> u32(i * 8)) }
	}
	if count > 4 { unsafe { C.memset(voidptr(address + 4), 0, usize(count - 4)) } }
}
fn swift_enum_store_multi_checked(value u64, metadata u64, which u32) ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_enum_case_multi_failure() }
	layout := swift_enum_multi_layout(metadata)!
	empty := which >= layout.payloads
	// Payload cases with no tag bytes and zero-sized empty cases touch nothing.
	if layout.width == 0 && (!empty || layout.payload == 0) { return }
	if value == 0 || value > ~u64(0) - layout.size { return swift_enum_case_multi_failure() }
	mut tag := which
	mut payload_value := u32(0)
	if empty {
		index := which - layout.payloads
		if layout.payload >= 4 {
			tag = layout.payloads
			payload_value = index
		} else {
			bits := u32(layout.payload * 8)
			tag = layout.payloads + (index >> bits)
			payload_value = index & ((u32(1) << bits) - 1)
		}
	}
	swift_enum_store_multi_element(value + layout.payload, tag, layout.width)
	if empty { swift_enum_store_multi_element(value, payload_value, layout.payload) }
}
// Ordinary Darwin C ABI: x0 value, x1 enum metadata, w2 case index; void result.
fn swift_enum_store_multi(value u64, metadata u64, which u32) {
	swift_enum_store_multi_checked(value, metadata, which) or { panic(err) }
}
