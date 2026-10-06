// SPDX-License-Identifier: GPL-2.0-or-later
module main

// CIPA Exif: APP1 begins with Exif\0\0, followed by a TIFF header. Orientation
// is IFD0 tag 0x0112, SHORT, count 1; its value is stored inline. Read only
// this bounded directory: thumbnail/SubIFD offsets and other tag values are
// deliberately never followed. See CIPA DC-008, image orientation/layout.
const preview_max_jpeg_metadata_segments = 4096

@[inline]
fn preview_tiff_u16(bytes []u8, at int, little bool) u16 {
	return if little {
		u16(bytes[at]) | u16(bytes[at + 1]) << 8
	} else {
		u16(bytes[at]) << 8 | u16(bytes[at + 1])
	}
}

@[inline]
fn preview_tiff_u32(bytes []u8, at int, little bool) u32 {
	return if little {
		u32(bytes[at]) | u32(bytes[at + 1]) << 8 | u32(bytes[at + 2]) << 16
			| u32(bytes[at + 3]) << 24
	} else {
		u32(bytes[at]) << 24 | u32(bytes[at + 1]) << 16 | u32(bytes[at + 2]) << 8
			| u32(bytes[at + 3])
	}
}

fn preview_tiff_orientation(bytes []u8, start int, end int) int {
	if start < 0 || end > bytes.len || start > end || end - start < 8 { return 1 }
	little := bytes[start] == `I` && bytes[start + 1] == `I`
	if !little && !(bytes[start] == `M` && bytes[start + 1] == `M`) { return 1 }
	if preview_tiff_u16(bytes, start + 2, little) != 42 { return 1 }
	offset := preview_tiff_u32(bytes, start + 4, little)
	// Compare before narrowing or adding an untrusted u32 offset. A directory
	// needs its count plus the trailing next-IFD field, even when it is empty.
	if offset < 8 || offset & 1 != 0 || offset > u32(end - start - 6) { return 1 }
	ifd := start + int(offset)
	count := int(preview_tiff_u16(bytes, ifd, little))
	if count > (end - ifd - 6) / 12 { return 1 }
	mut orientation := 1
	mut found := false
	for index in 0 .. count {
		entry := ifd + 2 + index * 12
		if preview_tiff_u16(bytes, entry, little) != 0x0112 { continue }
		// Duplicate or unsupported orientation entries are ambiguous metadata.
		if found || preview_tiff_u16(bytes, entry + 2, little) != 3
			|| preview_tiff_u32(bytes, entry + 4, little) != 1 { return 1 }
		value := int(preview_tiff_u16(bytes, entry + 8, little))
		if value < 1 || value > 8 { return 1 }
		orientation = value
		found = true
	}
	return orientation
}

fn preview_jpeg_orientation(bytes []u8) int {
	if bytes.len < 4 || bytes[0] != 0xff || bytes[1] != 0xd8 { return 1 }
	mut at := 2
	for _ in 0 .. preview_max_jpeg_metadata_segments {
		if at >= bytes.len || bytes[at] != 0xff { return 1 }
		for at < bytes.len && bytes[at] == 0xff { at++ }
		if at >= bytes.len { return 1 }
		marker := bytes[at]
		at++
		// Stop before entropy-coded image data; do not mistake its bytes for
		// metadata. Standalone markers have no segment length to consume.
		if marker == 0xda || marker == 0xd9 { return 1 }
		if marker == 0x00 || marker == 0xd8 { return 1 }
		if marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7) { continue }
		if bytes.len - at < 2 { return 1 }
		length := int(bytes[at]) << 8 | int(bytes[at + 1])
		if length < 2 || length > bytes.len - at { return 1 }
		end := at + length
		payload := at + 2
		if marker == 0xe1 && end - payload >= 6 && bytes[payload] == `E`
			&& bytes[payload + 1] == `x` && bytes[payload + 2] == `i`
			&& bytes[payload + 3] == `f` && bytes[payload + 4] == 0
			&& bytes[payload + 5] == 0 {
			// The first Exif APP1 is authoritative. A malformed record defaults
			// to the raw orientation instead of trusting a later conflicting one.
			return preview_tiff_orientation(bytes, payload + 6, end)
		}
		at = end
	}
	return 1
}

@[inline]
fn (a &PreviewApp) exif_dimensions() (int, int) {
	return if a.orientation >= 5 && a.orientation <= 8 { a.height } else { a.width },
		if a.orientation >= 5 && a.orientation <= 8 { a.width } else { a.height }
}
