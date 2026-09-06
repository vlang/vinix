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

// Limine hands the framebuffer over as a higher-half address inside the HHDM.
// Anything below the higher half is not addressable on the page tables in use
// at handoff, so storing to it faults on the very first pixel -- which, on a
// machine with no console, looks exactly like a kernel that never booted.
// Refusing to draw keeps that case quiet and survivable instead of fatal.
fn fb_address_usable(fb &limine.LimineFramebuffer) bool {
	base := u64(fb.address)
	if base < 0xffff_0000_0000_0000 {
		return false
	}
	span := u64(fb.pitch) * u64(fb.height)
	if span == 0 || base + span < base {
		return false
	}
	return true
}

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
	if !fb_address_usable(fb) {
		return
	}
	if fb.width == 0 || fb.height == 0 || fb.pitch == 0 || fb.bpp < 24 {
		return
	}

	// These bars are the only boot signal before the terminal exists, so build
	// the pixel from the framebuffer's own channel masks rather than assuming
	// 0x00RRGGBB, and step by the real pixel size. Writing 4 bytes per pixel on
	// a 24-bpp framebuffer both mis-colours the bar and runs past each row.
	bytes_per_pixel := u64(fb.bpp) / 8
	if bytes_per_pixel < 3 || bytes_per_pixel > 4 {
		return
	}
	rgb := stage_color(stage)
	color := encode_pixel(fb, u8(rgb >> 16), u8(rgb >> 8), u8(rgb))
	// Stack the stages down the screen instead of repainting the same strip.
	// Every mark used to overwrite the top 48 rows, so only the last one was
	// ever visible and a hang left no record of how far boot got. Stacked,
	// the bar count itself reports the last stage reached.
	bar_h := u64(16)
	top := u64(stage) * bar_h
	if top + bar_h > fb.height {
		return
	}
	for y := top; y < top + bar_h; y++ {
		row := u64(fb.address) + y * fb.pitch
		for x := u64(0); x < fb.width; x++ {
			pixel := row + x * bytes_per_pixel
			unsafe {
				if bytes_per_pixel == 4 {
					*&u32(pixel) = color
				} else {
					*&u8(pixel) = u8(color)
					*&u8(pixel + 1) = u8(color >> 8)
					*&u8(pixel + 2) = u8(color >> 16)
				}
			}
		}
	}
}

// Place each 8-bit channel according to the framebuffer's reported mask, so a
// bar is the intended colour on formats other than 8-8-8 (Apple's handover
// framebuffer is not always plain RGB888).
fn encode_pixel(fb &limine.LimineFramebuffer, red u8, green u8, blue u8) u32 {
	if fb.red_mask_size == 0 || fb.green_mask_size == 0 || fb.blue_mask_size == 0 {
		return (u32(red) << 16) | (u32(green) << 8) | u32(blue)
	}
	return (scale_channel(red, fb.red_mask_size) << fb.red_mask_shift)
		| (scale_channel(green, fb.green_mask_size) << fb.green_mask_shift)
		| (scale_channel(blue, fb.blue_mask_size) << fb.blue_mask_shift)
}

fn scale_channel(value u8, mask_size u8) u32 {
	if mask_size >= 8 {
		return u32(value) << (mask_size - 8)
	}
	return u32(value) >> (8 - mask_size)
}

// Fill the entire framebuffer with one colour. A 16-row bar is easy to miss
// or to mistake for a dark screen; a whole-screen fill answers a single
// question unambiguously: can the kernel put pixels on this display at all.
// If the screen keeps showing the bootloader's text, the kernel never wrote.
// If it turns the fill colour, the framebuffer works and later bars are
// meaningful. If it is black, the panel is not showing our writes.
pub fn early_screen_fill(stage u32) {
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
	if !fb_address_usable(fb) {
		return
	}
	if fb.width == 0 || fb.height == 0 || fb.pitch == 0 {
		return
	}
	bytes_per_pixel := u64(fb.bpp) / 8
	if bytes_per_pixel < 3 || bytes_per_pixel > 4 {
		return
	}
	rgb := stage_color(stage)
	color := encode_pixel(fb, u8(rgb >> 16), u8(rgb >> 8), u8(rgb))
	for y := u64(0); y < fb.height; y++ {
		row := u64(fb.address) + y * fb.pitch
		for x := u64(0); x < fb.width; x++ {
			pixel := row + x * bytes_per_pixel
			unsafe {
				if bytes_per_pixel == 4 {
					*&u32(pixel) = color
				} else {
					*&u8(pixel) = u8(color)
					*&u8(pixel + 1) = u8(color >> 8)
					*&u8(pixel + 2) = u8(color >> 16)
				}
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
