// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_enum_store_single_checked(value u64, which u32, cases u32, metadata u64, callback u64) ! {
	layout := swift_enum_tag_single_layout(metadata, cases)!
	inhabitant := which != 0 && which <= layout.extra
	if inhabitant && (callback == 0 || callback & 3 != 0 || callback > ~u64(0) - 4) {
		return swift_enum_tag_single_failure()
	}
	if layout.width != 0 || (which > layout.extra && layout.size != 0) {
		if value == 0 || value > ~u64(0) - layout.size - u64(layout.width) {
			return swift_enum_tag_single_failure()
		}
	}
	if which <= layout.extra {
		swift_enum_store_multi_element(value + layout.size, 0, layout.width)
		if inhabitant {
			// The borrowed SwiftCC callback takes x0/w1/w2/x3. Release the
			// layout lock before entering app code; forward its opaque value.
			store := unsafe { SwiftSequenceStoreTag(voidptr(callback)) }
			store(value, which, layout.extra, metadata)
		}
		return
	}
	index := which - layout.extra - u32(1)
	tag := if layout.size < 4 { u32(1) + (index >> u32(layout.size * 8)) } else { u32(1) }
	swift_enum_store_multi_element(value, index, layout.size)
	swift_enum_store_multi_element(value + layout.size, tag, layout.width)
}

// Five scalar SwiftCC arguments: x0 value, w1 case, w2 empty cases,
// x3 payload metadata, x4 extra-inhabitant callback; void result.
fn swift_enum_store_single(value u64, which u32, cases u32, metadata u64, callback u64) {
	swift_enum_store_single_checked(value, which, cases, metadata, callback) or { panic(err) }
}
