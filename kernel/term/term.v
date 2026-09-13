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
	// Limine can expose one GOP framebuffer per output. Apple Silicon usually
	// has only the framebuffer selected by m1n1/iBoot, but a UEFI stage that
	// keeps both the internal panel and a USB-C display produces more than one.
	// Keep one scanout for now and make every early/late framebuffer user agree
	// on it; mixing index 0 here with another /dev/fb0 later corrupts memory.
	framebuffer_index       = u64(0)
	framebuffer_selected    = false
	framebuffer_external    = false
	// Graphics mode: a userland program owns the framebuffer, so the kernel
	// terminal must not draw. Without it every console line (a program's
	// stderr, a kernel message) scrolls flanterm, which repaints every text
	// cell over the desktop -- the whole boot log reappearing on top of the
	// GUI. The owner is the process that entered it; text mode returns when
	// it exits, so a crashed application cannot leave the console dark.
	terminal_graphics_mode  = false
	terminal_graphics_owner = int(0)
)

fn C.flanterm_full_refresh(context voidptr)

pub fn graphics_mode() bool {
	return terminal_graphics_mode
}

// Pick the framebuffer used by the console and /dev/fb0. In external-display
// handoff mode there is no connector metadata in the Limine protocol, so the
// largest valid GOP surface is the useful discriminator: the M1 Air panel is
// 2560x1600 while a Studio Display surface is 5120x2880. Ties prefer the later
// GOP handle, which is normally the hot-plug output rather than the panel.
//
// This runs before V's runtime initialisation and therefore deliberately does
// not allocate or construct strings.
pub fn select_framebuffer(prefer_external bool) bool {
	framebuffer_index = 0
	framebuffer_selected = false
	framebuffer_external = prefer_external
	if fb_req.response == unsafe { nil }
		|| fb_req.response.framebuffer_count == 0
		|| fb_req.response.framebuffers == unsafe { nil } {
		return false
	}

	mut best_area := u64(0)
	for index := u64(0); index < fb_req.response.framebuffer_count; index++ {
		candidate := unsafe { fb_req.response.framebuffers[index] }
		if candidate == unsafe { nil } || candidate.address == unsafe { nil }
			|| candidate.width == 0 || candidate.height == 0 || candidate.pitch == 0 {
			continue
		}
		// Do not let a larger but unmapped GOP handle displace the firmware
		// default. The selected address is touched during the earliest boot
		// stages, before a fault can be reported anywhere useful.
		if !fb_address_usable(candidate) {
			continue
		}
		if candidate.width > ~u64(0) / candidate.height {
			continue
		}
		area := candidate.width * candidate.height
		if !framebuffer_selected || (prefer_external && area >= best_area) {
			framebuffer_index = index
			best_area = area
			framebuffer_selected = true
		}
		if framebuffer_selected && !prefer_external {
			break
		}
	}
	return framebuffer_selected
}

fn selected_framebuffer() &limine.LimineFramebuffer {
	if !framebuffer_selected && !select_framebuffer(false) {
		return unsafe { nil }
	}
	if fb_req.response == unsafe { nil }
		|| framebuffer_index >= fb_req.response.framebuffer_count {
		return unsafe { nil }
	}
	return unsafe { fb_req.response.framebuffers[framebuffer_index] }
}

// Emit this after the terminal exists. It makes a hardware boot unambiguous:
// the log says which GOP surface Vinix owns and whether external preference
// was requested, instead of requiring a guess from the visible panel.
pub fn report_framebuffer_selection() {
	fb := selected_framebuffer()
	if fb == unsafe { nil } {
		println('framebuffer: no usable GOP output')
		return
	}
	count := if fb_req.response == unsafe { nil } {
		u64(0)
	} else {
		fb_req.response.framebuffer_count
	}
	mode := if framebuffer_external { 'external handoff' } else { 'firmware default' }
	println('framebuffer: selected GOP ${framebuffer_index + 1}/${count}, ${fb.width}x${fb.height}x${fb.bpp} (${mode})')
}

// Dimensions of the one framebuffer chosen during the Limine handoff.  The
// Type-C first-attach policy uses the exact 2560x1600 built-in M1 Air mode as
// its fail-closed discriminator; it does not guess that an unknown surface is
// safe to replace.
pub fn selected_framebuffer_dimensions() (u64, u64) {
	fb := selected_framebuffer()
	if fb == unsafe { nil } || !fb_address_usable(fb) {
		return 0, 0
	}
	return fb.width, fb.height
}

// Stop drawing to the framebuffer on behalf of `owner_pid`. Idempotent: the
// framebuffer's mmap path calls it for every page it hands out.
pub fn enter_graphics_mode(owner_pid int) {
	terminal_print_lock.acquire()
	terminal_graphics_mode = true
	terminal_graphics_owner = owner_pid
	terminal_print_lock.release()
}

// Resume drawing and repaint the terminal's own contents, since whatever the
// application left on screen is not the console.
pub fn leave_graphics_mode() {
	terminal_print_lock.acquire()
	if terminal_graphics_mode {
		terminal_graphics_mode = false
		terminal_graphics_owner = 0
		if flanterm_ctx != unsafe { nil } {
			C.flanterm_full_refresh(flanterm_ctx)
		}
	}
	terminal_print_lock.release()
}

// Called when a process exits: only the owner's exit restores text mode.
pub fn leave_graphics_mode_if_owner(pid int) {
	if terminal_graphics_mode && terminal_graphics_owner == pid {
		leave_graphics_mode()
	}
}

// The boot firmware owns link training for a handed-off external scanout.  A
// reconnect exposes the same framebuffer again; repaint the saved terminal so
// a console that was idle while unplugged becomes visible immediately.  A
// graphics owner keeps its pixels in that framebuffer and will present on its
// own schedule, so do not paint over it.
pub fn display_hotplug(connected bool) {
	if !connected {
		return
	}
	terminal_print_lock.acquire()
	if !terminal_graphics_mode && flanterm_ctx != unsafe { nil } {
		C.flanterm_full_refresh(flanterm_ctx)
	}
	terminal_print_lock.release()
}

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

// Early boot marker that writes directly to the selected Limine framebuffer.
// Safe to call before terminal initialisation; no allocations performed.
pub fn early_stage_mark(stage u32) {
	fb := selected_framebuffer()
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
	fb := selected_framebuffer()
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

// Physical span of the selected framebuffer, for the page-table build. Limine
// reports the framebuffer as a higher-half direct-map address, so the physical
// base is that address minus the HHDM offset. Returns a zero length when there
// is no usable framebuffer.
pub fn framebuffer_phys_span() (u64, u64) {
	fb := selected_framebuffer()
	if fb == unsafe { nil } || fb.address == unsafe { nil } || !fb_address_usable(fb) {
		return 0, 0
	}
	hhdm := memory.get_hhdm_offset()
	base := u64(fb.address)
	if base < hhdm {
		return 0, 0
	}
	return base - hhdm, fb.pitch * fb.height
}

pub fn initialise() {
	// Idempotent. kmain brings the terminal up once before the page-table
	// switch and would call this again after it. The early context keeps
	// rendering on the kernel's tables (the framebuffer is mapped there), so a
	// second flanterm_fb_init is not only redundant, it re-clears and
	// re-allocates a full-screen canvas -- 16 MB on the M1's 2560x1600 native
	// panel -- and hangs there. Reuse the live context instead.
	if flanterm_ctx != unsafe { nil } {
		return
	}
	framebuffer_tag = selected_framebuffer()
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
	// In graphics mode the bytes are dropped rather than queued: the UART
	// still carries them (see kprint.kwrite), and replaying a backlog over a
	// desktop that just exited would be worse than losing it.
	if !terminal_graphics_mode {
		C.flanterm_write(flanterm_ctx, s, len)
	}
	terminal_print_lock.release()
}
