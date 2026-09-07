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
	fd     int = -1
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
		fd: fd
		base: unsafe { &u32(mapping) }
		width: width
		height: height
		stride: stride
		size: size
		direct: var.red.offset == 16 && var.green.offset == 8 && var.blue.offset == 0
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
	return ((pixel >> 16) & 0xff) << fb.r_shift | ((pixel >> 8) & 0xff) << fb.g_shift |
		(pixel & 0xff) << fb.b_shift
}

// present copies a finished frame out in one pass. At 200% the desktop composes
// at half resolution and each logical pixel is expanded to a crisp 2x2 block.
// On the usual XRGB8888 framebuffer the 100% path remains one memcpy per frame.
fn (mut fb Framebuffer) present(canvas &Canvas, scale int) {
	if scale == desktop_scale_200 {
		for source_y := 0; source_y < canvas.height; source_y++ {
			physical_y := source_y * desktop_scale_200
			if physical_y >= fb.height {
				break
			}
			source := source_y * canvas.stride
			destination := physical_y * fb.stride
			mut physical_x := 0
			for source_x := 0; source_x < canvas.width; source_x++ {
				if physical_x >= fb.width {
					break
				}
				pixel := unsafe { canvas.pixels[source + source_x] }
				packed := fb.pack_pixel(pixel)
				unsafe {
					fb.base[destination + physical_x] = packed
					if physical_x + 1 < fb.width {
						fb.base[destination + physical_x + 1] = packed
					}
				}
				physical_x += desktop_scale_200
			}
			if physical_y + 1 < fb.height {
				unsafe {
					vmemcpy(&fb.base[(physical_y + 1) * fb.stride], &fb.base[destination],
						usize(fb.width * 4))
				}
			}
		}
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

fn (mut fb Framebuffer) close() {
	if fb.base != unsafe { nil } {
		desktop_munmap(fb.base, fb.size)
		fb.base = unsafe { nil }
	}
	if fb.fd >= 0 {
		desktop_close(fb.fd)
		fb.fd = -1
	}
}
