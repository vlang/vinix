// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

// Native diagnostic and X11 adapters share the qualified replacement decoder.
pub fn decode_utf8(bytes []u8) string { return replace_utf8(bytes) }

fn replace_utf8(bytes []u8) string {
	// Decode malformed serial diagnostics without discarding valid text.
	mut result := []u8{}
	mut index := 0
	for index < bytes.len {
		first := bytes[index]
		width := if first < 0x80 {
			1
		} else if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		mut consumed := 1
		if width > 0 {
			for position in 1 .. width {
				if index + position >= bytes.len { break }
				value := bytes[index + position]
				if value < 0x80 || value > 0xbf || (position == 1 && ((first == 0xe0 && value < 0xa0) || (first == 0xed && value > 0x9f) || (first == 0xf0 && value < 0x90) || (first == 0xf4 && value > 0x8f))) {
					break
				}
				consumed++
			}
		}
		if width > 0 && consumed == width {
			result << bytes[index..index + width]
			index += width
		} else {
			result << '\ufffd'.bytes()
			index += consumed
		}
	}
	return result.bytestr()
}

