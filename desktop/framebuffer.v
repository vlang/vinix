// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The display side of the desktop: /dev/fb0 is queried for its geometry and
// then mapped, so a frame reaches the screen as one memcpy out of the back
// buffer instead of a write syscall per scanline.
module main

const fbioget_vscreeninfo = u64(0x4600)
const fbioget_fscreeninfo = u64(0x4602)

// Field order and widths follow linux/fb.h, which is what the Vinix fbdev
// driver copies out. The whole structure has to be present even though only a
// few fields are read: the driver copies its own sizeof into this buffer.
struct FBBitfield {
mut:
	offset    u32
	length    u32
	msb_right u32
}

struct FBVarScreenInfo {
mut:
	xres           u32
	yres           u32
	xres_virtual   u32
	yres_virtual   u32
	xoffset        u32
	yoffset        u32
	bits_per_pixel u32
	grayscale      u32
	red            FBBitfield
	green          FBBitfield
	blue           FBBitfield
	transp         FBBitfield
	nonstd         u32
	activate       u32
	height         u32
	width          u32
	accel_flags    u32
	pixclock       u32
	left_margin    u32
	right_margin   u32
	upper_margin   u32
	lower_margin   u32
	hsync_len      u32
	vsync_len      u32
	sync           u32
	vmode          u32
	rotate         u32
	colorspace     u32
	reserved       [4]u32
}

struct FBFixScreenInfo {
mut:
	id           [16]u8
	smem_start   u64
	smem_len     u32
	typ          u32
	type_aux     u32
	visual       u32
	xpanstep     u16
	ypanstep     u16
	ywrapstep    u16
	line_length  u32
	mmio_start   u64
	mmio_len     u32
	accel        u32
	capabilities u16
	reserved     [2]u16
}

// Framebuffer owns the mapping. `stride` is in pixels, not bytes, because
// every consumer indexes the mapping as u32.
struct Framebuffer {
mut:
	fd     int  = -1
	base   &u32 = unsafe { nil }
	width  int
	height int
	stride int
	size   u64
	// The canvas composes in 0xRRGGBB. A framebuffer laid out any other way
	// is repacked on the way out rather than making every primitive care.
	direct  bool
	r_shift u32
	g_shift u32
	b_shift u32
	gpu     GpuPresenter
}

fn open_framebuffer(path string) !Framebuffer {
	fd := desktop_open_rw(path)
	if fd < 0 {
		return error('cannot open ${path}')
	}

	mut var := FBVarScreenInfo{}
	if desktop_ioctl(fd, fbioget_vscreeninfo, &var) < 0 {
		desktop_close(fd)
		return error('FBIOGET_VSCREENINFO failed on ${path}')
	}

	mut fix := FBFixScreenInfo{}
	if desktop_ioctl(fd, fbioget_fscreeninfo, &fix) < 0 {
		desktop_close(fd)
		return error('FBIOGET_FSCREENINFO failed on ${path}')
	}

	if var.bits_per_pixel != 32 {
		desktop_close(fd)
		return error('${path} is ${var.bits_per_pixel}bpp; this desktop draws 32bpp only')
	}

	width := int(var.xres)
	height := int(var.yres)
	// A driver that reports no pitch is laying the scanlines out end to end.
	stride := if fix.line_length > 0 { int(fix.line_length) / 4 } else { width }
	size := u64(stride) * u64(height) * 4

	mapping := desktop_mmap_shared(fd, size)
	if mapping == unsafe { nil } {
		desktop_close(fd)
		return error('cannot map ${path}')
	}

	return Framebuffer{
		fd:      fd
		base:    unsafe { &u32(mapping) }
		width:   width
		height:  height
		stride:  stride
		size:    size
		direct:  var.red.offset == 16 && var.green.offset == 8 && var.blue.offset == 0
		r_shift: var.red.offset
		g_shift: var.green.offset
		b_shift: var.blue.offset
	}
}

@[inline]
fn (fb &Framebuffer) pack_pixel(pixel u32) u32 {
	if fb.direct {
		return pixel
	}
	return ((pixel >> 16) & 0xff) << fb.r_shift | ((pixel >> 8) & 0xff) << fb.g_shift | (pixel & 0xff) << fb.b_shift
}

// present copies a finished native-resolution frame out in one pass. Canvas
// keeps logical geometry separately from its backing dimensions, allowing 2x
// font masks to remain sharp while this final transfer stays scale-agnostic.
fn (mut fb Framebuffer) present(canvas &Canvas, _ int) {
	// On an M1 build this creates a surfaceless EGL context lazily and lets AGX
	// composite the CPU canvas into the firmware framebuffer. The static
	// desktop and any failed GPU initialization continue through this file's
	// existing software paths.
	if fb.direct && fb.gpu.present(canvas, fb.base, fb.width, fb.height, fb.stride) {
		return
	}
	if fb.direct {
		if canvas.stride == fb.stride {
			unsafe {
				vmemcpy(fb.base, canvas.pixels, usize(u64(fb.stride) * u64(fb.height) * 4))
			}
			return
		}
		for y := 0; y < fb.height; y++ {
			unsafe {
				vmemcpy(&fb.base[y * fb.stride], &canvas.pixels[y * canvas.stride], usize(fb.width * 4))
			}
		}
		return
	}

	for y := 0; y < fb.height; y++ {
		src := y * canvas.stride
		dst := y * fb.stride
		for x := 0; x < fb.width; x++ {
			pixel := unsafe { canvas.pixels[src + x] }
			unsafe { fb.base[dst + x] = fb.pack_pixel(pixel) }
		}
	}
}

// present_damage transfers only a changed logical rectangle. The GPU presenter
// owns a full-frame hardware path, so it remains preferable when active;
// software fbdev output otherwise avoids copying untouched desktop pixels.
fn (mut fb Framebuffer) present_damage(canvas &Canvas, damage DamageRect) {
	if !damage.valid {
		return
	}
	if fb.direct && fb.gpu.present(canvas, fb.base, fb.width, fb.height, fb.stride) {
		return
	}
	x0 := if damage.x > 0 { damage.x } else { 0 }
	y0 := if damage.y > 0 { damage.y } else { 0 }
	x1 := if damage.x + damage.w < canvas.width { damage.x + damage.w } else { canvas.width }
	y1 := if damage.y + damage.h < canvas.height { damage.y + damage.h } else { canvas.height }
	if x1 <= x0 || y1 <= y0 {
		return
	}
	physical_x0 := x0 * canvas.scale
	physical_y0 := y0 * canvas.scale
	physical_x1 := if x1 * canvas.scale < fb.width { x1 * canvas.scale } else { fb.width }
	physical_y1 := if y1 * canvas.scale < fb.height { y1 * canvas.scale } else { fb.height }
	if fb.direct {
		for y := physical_y0; y < physical_y1; y++ {
			unsafe {
				vmemcpy(&fb.base[y * fb.stride + physical_x0], &canvas.pixels[y * canvas.stride + physical_x0], usize((physical_x1 - physical_x0) * 4))
			}
		}
		return
	}
	for y := physical_y0; y < physical_y1; y++ {
		src := y * canvas.stride
		dst := y * fb.stride
		for x := physical_x0; x < physical_x1; x++ {
			pixel := unsafe { canvas.pixels[src + x] }
			unsafe { fb.base[dst + x] = fb.pack_pixel(pixel) }
		}
	}
}

fn (mut fb Framebuffer) close() {
	fb.gpu.close()
	if fb.base != unsafe { nil } {
		desktop_munmap(fb.base, fb.size)
		fb.base = unsafe { nil }
	}
	if fb.fd >= 0 {
		desktop_close(fb.fd)
		fb.fd = -1
	}
}
