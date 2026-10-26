// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn ns_string_precomposed(object u64) u64 {
	// The input may be mutable. Snapshot its validated bytes under the runtime
	// lock, then release the lock before normalization or allocation callbacks.
	C.ios_objc_initialize_lock()
	source := cf_string_compare_text(object) or {
		C.ios_objc_initialize_unlock()
		panic('iOS: string normalization requires a live UTF8 string')
	}
	text := source.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	scalars := swift_nfc_normalize(text)
	defer { unsafe { scalars.free() } }
	mut bytes := []u8{cap: text.len}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for scalar in scalars {
		width := if scalar < 0x80 { 1 } else if scalar < 0x800 { 2 } else if scalar < 0x10000 { 3 } else { 4 }
		if u64(bytes.len + width) > mutable_string_limit { panic('iOS: normalized string exceeds size limit') }
		if width == 1 { bytes << u8(scalar) }
		else if width == 2 { bytes << u8(0xc0 | (scalar >> 6)) }
		else if width == 3 { bytes << u8(0xe0 | (scalar >> 12)) }
		else { bytes << u8(0xf0 | (scalar >> 18)) }
		if width == 4 { bytes << u8(0x80 | ((scalar >> 12) & 63)) }
		if width >= 3 { bytes << u8(0x80 | ((scalar >> 6) & 63)) }
		if width >= 2 { bytes << u8(0x80 | (scalar & 63)) }
	}
	encoded := bytes.bytestr()
	defer { unsafe { encoded.free() } }
	return objc_autorelease(owned_string(encoded))
}
