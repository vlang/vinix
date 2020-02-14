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
	buf [16384]byte // TODO: use kernel heap instead
}

fn C.fbcon_get_glyph(idx byte) &byte

__global fb_con_state FbConState

fn fbcon_preinit() {
	fb_con_state.char_width = 8
	fb_con_state.char_height = 16
	
	fb_con_state.width = 80
	fb_con_state.height = 50

	fb_con_state.cur_x = 0
	fb_con_state.cur_y = 0

	register_callback(CALLBACK_FRAMEBUFFER_ATTACH, fb_attach_cb)
}

fn fb_attach_cb(fb voidptr) {
	fbcon_init(&Framebuffer(fb))
}

fn fbcon_init(fb &Framebuffer) {
	old_buf := [4000]byte

	// copy old buffer contents
	memcpy(&old_buf, fb_con_state.buf, 4000)
	memset(fb_con_state.buf, 0, 16384)

	fb_con_state.char_width = 8
	fb_con_state.char_height = 16

	fb_con_state.width = u16(fb.width / fb_con_state.char_width)
	fb_con_state.height = u16(fb.height / fb_con_state.char_height)

	last_line := fb_con_state.cur_y
	fb_con_state.cur_x = 0
	fb_con_state.cur_y = 0
	
	for line := 0; line < last_line; line++ {
		addr := voidptr(u64(&old_buf) + line * 80)
		fbcon_println(tos(byteptr(addr), 80))
	}

	//fb_con_state.scroll_up()
	fb_con_state.framebuffer = fb
	fb_con_state.draw()
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
	fbcon_print(str)
	fbcon_putc(`\n`)
}

fn fbcon_print(str string) {
	for i := 0; i < str.len; i++ {
		fbcon_putc(str.str[i])
	}
}

fn fbcon_putc(c byte) {
	if c == `\n` {
		fb_con_state.cur_x = 0
		fb_con_state.cur_y++

		if fb_con_state.cur_y == fb_con_state.height {
			fb_con_state.cur_y--
			fb_con_state.scroll_up()
		}
	} else if c == `\r` {
		fb_con_state.cur_x = 0
	} else {
		fb_con_state.draw_glyph(c, int(fb_con_state.cur_x), int(fb_con_state.cur_y))
		fb_con_state.buf[(fb_con_state.cur_y * fb_con_state.width) + fb_con_state.cur_x] = c
		fb_con_state.cur_x++
	}

	if fb_con_state.cur_x == fb_con_state.width {
		fb_con_state.cur_x = 0
		fb_con_state.cur_y++
	}

	if fb_con_state.cur_y == fb_con_state.height {
		fb_con_state.cur_y--
		fb_con_state.scroll_up()
	}
}

fn (fbcon &FbConState) scroll_up() {
	memcpy(voidptr(fbcon.buf), voidptr(u64(fbcon.buf) + u64(fbcon.width)), fbcon.width * (fbcon.height - 1))
	memset(voidptr(u64(fbcon.buf) + u64(fbcon.width * (fbcon.height - 1))), 0, fbcon.width)

	if voidptr(fbcon.framebuffer) != nullptr {
		memcpy(voidptr(fbcon.framebuffer.addr_virt), voidptr(u64(fbcon.framebuffer.addr_virt) + u64(fbcon.framebuffer.pitch * 16)), fbcon.framebuffer.pitch * 16 * (fbcon.height - 1))
		memset32(voidptr(u64(fbcon.framebuffer.addr_virt) + u64(fbcon.framebuffer.pitch * 16 * (fbcon.height - 1))), 0x000080, fbcon.framebuffer.width * 16)
	}
}

fn (fbcon &FbConState) draw_glyph(chr byte, x, y int) {
	if voidptr(fbcon.framebuffer) == nullptr {
		return
	}

	glyph := fbcon_get_glyph(translate_glyph(chr))
	fb := fbcon.framebuffer
	
	for fy := 0; fy < 16; fy++ {
		mut data := glyph[fy]
		for fx := 0; fx < 8; fx++ {
			if data & 1 != 0 {
				fb.plot(u32((x + 1) * 8 - fx - 1), u32(y * 16 + fy), 0xFFFFFF)
			} else {
				//fb.plot(u32((x + 1) * 8 - fx - 1), u32(y * 16 + fy), 0x000000)
			}

			data >>= 1
		}
	}
}

fn (fbcon &FbConState) draw() {
	if voidptr(fbcon.framebuffer) == nullptr {
		return
	}

	memset32(fbcon.framebuffer.addr_virt, 0x000080, fbcon.framebuffer.width * fbcon.framebuffer.height)

	for x := 0; x < fbcon.width; x++ {
		for y := 0; y < fbcon.height; y++ {
			fbcon.draw_glyph(fbcon.buf[y * fbcon.width + x], x, y)
		}
	}
}