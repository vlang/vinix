module sys

#include <glyph.h>

struct ConGlyph {
	code byte
	bitmap [16]byte
}

struct FbConState {
mut:
	width u16
	height u16
	cur_x u16
	cur_y u16
	char_width byte
	char_height byte
	framebuffer &Framebuffer
	buf [16384]byte
}

fn C.fbcon_get_glyph(idx byte) &byte

__global fb_con_state FbConState

fn fbcon_init(fb &Framebuffer) {
	fb_con_state.char_width = 8
	fb_con_state.char_height = 16

	fb_con_state.framebuffer = fb
	fb_con_state.width = u16(fb.width / fb_con_state.char_width)
	fb_con_state.height = u16(fb.height / fb_con_state.char_height)

	fb_con_state.cur_x = 0
	fb_con_state.cur_y = 0
	printk('fbcon init completed.')
}

// 32 - 126
// 160 - 255
[inline]
fn translate_glyph(code byte) byte {
	if code >= 32 && code <= 160 {
		return code - 32
	} else if code >= 160 && code <= 255 {
		return code - 255
	} else {
		return 0
	}
}

fn fbcon_println(str string) {
	fb_con_state.draw()
}

fn (fbcon &FbConState) scroll_up() {

}

fn (fbcon &FbConState) draw_glyph(chr byte, x, y int) {
	glyph := fbcon_get_glyph(translate_glyph(chr))
	fb := fbcon.framebuffer
	
	for fy := 0; fy < 16; fy++ {
		mut data := glyph[fy]
		for fx := 0; fx < 8; fx++ {
			if data & 1 != 0 {
				fb.plot(u32((x + 1) * 8 - fx - 1), u32(y * 16 + fy), 0xFFFFFF)
			} else {
				fb.plot(u32((x + 1) * 8 - fx - 1), u32(y * 16 + fy), 0x0000FF)
			}

			data >>= 1
		}
	}
}

fn (fbcon &FbConState) draw() {
	for x := 0; x < fbcon.width; x++ {
		for y := 0; y < fbcon.height; y++ {
			fbcon.draw_glyph(fbcon.buf[x * fbcon.width + y], x, y)
		}
	}
}