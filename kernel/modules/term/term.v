// term.v: Terminal stuff.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module term

import klock
import dev.fbdev.api
import dev.fbdev.simple
import limine
import flanterm
import memory

__global (
	flanterm_ctx voidptr

	terminal_print_lock klock.Lock
	terminal_rows       = u64(0)
	terminal_cols       = u64(0)
	framebuffer_tag     = &limine.LimineFramebuffer(unsafe { nil })
	framebuffer_width   = u64(0)
	framebuffer_height  = u64(0)
)

@[cinit]
@[_linker_section: '.requests']
__global (
	volatile fb_req = limine.LimineFramebufferRequest{
		response: unsafe { nil }
	}

	volatile flanterm_info_req = limine.LimineFlantermInfoRequest{
		response: unsafe { nil }
	}
)

pub fn initialise() {
	framebuffer_tag = unsafe { fb_req.response.framebuffers[0] }
	framebuffer_width = framebuffer_tag.width
	framebuffer_height = framebuffer_tag.height

	mut flanterm_info := &limine.LimineFlantermInfoResponse{
		canvas: unsafe { nil }
		ansi_colours: unsafe { nil }
		ansi_bright_colours: unsafe { nil }
		default_bg: unsafe { nil }
		default_fg: unsafe { nil }
		default_bg_bright: unsafe { nil }
		default_fg_bright: unsafe { nil }
		font: unsafe { nil }
		font_spacing: 1
	}
	if flanterm_info_req.response != unsafe { nil } {
		unsafe { *flanterm_info = *flanterm_info_req.response }
	}

	flanterm_ctx = unsafe { C.flanterm_fb_init(voidptr(memory.malloc), voidptr(memory.free),
											   framebuffer_tag.address, framebuffer_width, framebuffer_height, framebuffer_tag.pitch,
											   framebuffer_tag.red_mask_size, framebuffer_tag.red_mask_shift,
											   framebuffer_tag.green_mask_size, framebuffer_tag.green_mask_shift,
											   framebuffer_tag.blue_mask_size, framebuffer_tag.blue_mask_shift,
											   flanterm_info.canvas,
											   flanterm_info.ansi_colours, flanterm_info.ansi_bright_colours,
											   flanterm_info.default_bg, flanterm_info.default_fg,
											   flanterm_info.default_bg_bright, flanterm_info.default_fg_bright,
											   flanterm_info.font,
											   flanterm_info.font_width, flanterm_info.font_height,
											   flanterm_info.font_spacing,
											   flanterm_info.font_scale_x, flanterm_info.font_scale_y,
											   flanterm_info.margin) }

	terminal_rows = C.flanterm_get_rows(flanterm_ctx)
	terminal_cols = C.flanterm_get_cols(flanterm_ctx)
}

pub fn framebuffer_init() {
	sfb_config := simple.SimpleFBConfig {
		physical_address: u64(framebuffer_tag.address),
		width: u32(framebuffer_width),
		height: u32(framebuffer_height),
		stride: u32(framebuffer_tag.pitch),
		bits_per_pixel: u32(framebuffer_tag.bpp),
		red: api.FBBitfield {
			offset: framebuffer_tag.red_mask_shift,
			length: framebuffer_tag.red_mask_size,
			msb_right: 0,
		},
		green: api.FBBitfield {
			offset: framebuffer_tag.green_mask_shift,
			length: framebuffer_tag.green_mask_size,
			msb_right: 0,
		},
		blue: api.FBBitfield {
			offset: framebuffer_tag.blue_mask_shift,
			length: framebuffer_tag.blue_mask_size,
			msb_right: 0,
		},
		transp: api.FBBitfield {
			offset: 0,
			length: 0,
			msb_right: 0,
		},
	}

	simple.register_simple_framebuffer(sfb_config)
}

pub fn print(s voidptr, len u64) {
	terminal_print_lock.acquire()
	C.flanterm_write(flanterm_ctx, s, len)
	terminal_print_lock.release()
}
