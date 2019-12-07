module sys

struct ConGlyph {
	code byte
	bitmap [16]u16
}

__global fb_con_glyphs [190]sys.ConGlyph

__global fb_con_buf [16384]byte

// 32 - 126
// 160 - 255

[inline]
fn translate_glyph(code byte) byte {
	if code >= 32 && code <= 160 {
		return code - 32
	} else if code >= 160 && code <= 255 {
		return code - 255
	} else {
		return 32
	}
}