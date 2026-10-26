// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Borrow both inputs under the runtime lock. In particular, image constants
// have loader provenance but no allocation header; never synthesize one.
fn ns_string_character_search(object u64, set u64, mut frame RegisterFrame) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.native_size < 8
			|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'],
				ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: character search requires a built-in initialized string')
		}
	}
	text := cf_string_compare_text(object) or {
		panic('iOS: character search requires a live UTF8 string')
	}
	state := ns_character_set_storage(set, true)
	mut offset := 0
	mut location := u64(0)
	for offset < text.len {
		first := text[offset]
		offset++
		width := if first < 0x80 { 1 } else if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
		mut scalar := u32(first & if width == 1 { u8(0x7f) } else if width == 2 {
			u8(0x1f)
		} else if width == 3 { u8(0x0f) } else { u8(7) })
		for _ in 1 .. width {
			scalar = scalar << 6 | u32(text[offset] & 0x3f)
			offset++
		}
		units := if width == 4 { u64(2) } else { u64(1) }
		member := unsafe { state.bits[scalar >> 3] & u8(1 << (scalar & 7)) }
		if member != 0 {
			frame.x[0] = location
			frame.x[1] = units
			return
		}
		location += units
	}
	frame.x[0] = 0x7fffffffffffffff // NSNotFound (NSIntegerMax on ARM64).
	frame.x[1] = 0
}

fn ns_string_character_search_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if selector != 'rangeOfCharacterFromSet:' { return false }
	ns_string_character_search(object, frame.x[2], mut frame)
	return true
}
