@[has_globals]
module term

import klock
import dev.fbdev.api
import dev.fbdev.simple
import limine
import flanterm as _
import memory

__global (
	flanterm_ctx        voidptr
	terminal_print_lock klock.Lock
	terminal_rows       = u64(0)
	terminal_cols       = u64(0)
	framebuffer_tag     = &limine.LimineFramebuffer(unsafe { nil })
	framebuffer_width   = u64(0)
	framebuffer_height  = u64(0)
)

fn stage_color(stage u32) u32 {
	return match stage & 0x7 {
		0 { u32(0x00ff0000) } // red
		1 { u32(0x0000ff00) } // green
		2 { u32(0x000000ff) } // blue
		3 { u32(0x00ffff00) } // yellow
		4 { u32(0x0000ffff) } // cyan
		5 { u32(0x00ff00ff) } // magenta
		6 { u32(0x00ffffff) } // white
		else { u32(0x00808080) } // gray
	}
}

// Early boot marker that writes directly to the first Limine framebuffer.
// Safe to call before terminal initialisation; no allocations performed.
pub fn early_stage_mark(stage u32) {
	if fb_req.response == unsafe { nil } {
		return
	}
	if fb_req.response.framebuffer_count == 0 || fb_req.response.framebuffers == unsafe { nil } {
		return
	}
	fb := unsafe { fb_req.response.framebuffers[0] }
	if fb == unsafe { nil } || fb.address == unsafe { nil } {
		return
	}
	if fb.width == 0 || fb.height == 0 || fb.pitch == 0 || fb.bpp < 24 {
		return
	}

	color := stage_color(stage)
	bar_h := if fb.height > 48 { u64(48) } else { fb.height }
	for y := u64(0); y < bar_h; y++ {
		row := u64(fb.address) + y * fb.pitch
		for x := u64(0); x < fb.width; x++ {
			unsafe {
				*&u32(row + x * 4) = color
			}
		}
	}
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile fb_req = limine.LimineFramebufferRequest{
		response: unsafe { nil }
	}
)

pub fn initialise() {
	if fb_req.response == unsafe { nil } {
		// No framebuffer available (headless/serial-only mode)
		return
	}
	if fb_req.response.framebuffer_count == 0 || fb_req.response.framebuffers == unsafe { nil } {
		// No framebuffer available (headless/serial-only mode)
		return
	}
	framebuffer_tag = unsafe { fb_req.response.framebuffers[0] }
	if framebuffer_tag == unsafe { nil } || framebuffer_tag.address == unsafe { nil } {
		framebuffer_tag = unsafe { nil }
		return
	}
	if framebuffer_tag.width == 0 || framebuffer_tag.height == 0 || framebuffer_tag.pitch == 0 {
		framebuffer_tag = unsafe { nil }
		return
	}
	framebuffer_width = framebuffer_tag.width
	framebuffer_height = framebuffer_tag.height

	flanterm_ctx = unsafe {
		C.flanterm_fb_init(voidptr(memory.malloc), voidptr(memory.free), framebuffer_tag.address,
			framebuffer_width, framebuffer_height, framebuffer_tag.pitch, framebuffer_tag.red_mask_size,
			framebuffer_tag.red_mask_shift, framebuffer_tag.green_mask_size, framebuffer_tag.green_mask_shift,
			framebuffer_tag.blue_mask_size, framebuffer_tag.blue_mask_shift, nil, nil,
			nil, nil, nil, nil, nil, nil, 0, 0, 1, 0, 0, 0)
	}

	C.flanterm_get_dimensions(flanterm_ctx, &terminal_cols, &terminal_rows)
}

pub fn framebuffer_init() {
	if framebuffer_tag == unsafe { nil } {
		return
	}
	sfb_config := simple.SimpleFBConfig{
		physical_address: u64(framebuffer_tag.address)
		width:            u32(framebuffer_width)
		height:           u32(framebuffer_height)
		stride:           u32(framebuffer_tag.pitch)
		bits_per_pixel:   u32(framebuffer_tag.bpp)
		red:              api.FBBitfield{
			offset:    framebuffer_tag.red_mask_shift
			length:    framebuffer_tag.red_mask_size
			msb_right: 0
		}
		green:            api.FBBitfield{
			offset:    framebuffer_tag.green_mask_shift
			length:    framebuffer_tag.green_mask_size
			msb_right: 0
		}
		blue:             api.FBBitfield{
			offset:    framebuffer_tag.blue_mask_shift
			length:    framebuffer_tag.blue_mask_size
			msb_right: 0
		}
		transp:           api.FBBitfield{
			offset:    0
			length:    0
			msb_right: 0
		}
	}

	simple.register_simple_framebuffer(sfb_config)
}

pub fn print(s voidptr, len u64) {
	if flanterm_ctx == unsafe { nil } {
		return
	}
	terminal_print_lock.acquire()
	C.flanterm_write(flanterm_ctx, s, len)
	terminal_print_lock.release()
}
