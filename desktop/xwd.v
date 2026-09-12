// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Xvfb surfaces embedded in compositor-managed Vinix windows.
@[has_globals]
module main

const xwd_image_prefix = 'xwd:'
const office_xwd_image_prefix = 'xwd-office:'
// Office 2013 draws its ribbon and start-page controls through transparent
// Direct2D layers. Xvfb's 24-bit root pixmap has nowhere to retain the alpha
// channel, so a few transparent controls arrive on a near-black backing. Keep
// the repair within the stable Office 2013 ribbon rectangles; inspecting and
// flood-filling the whole ribbon for every frame is prohibitively expensive
// under the x86-to-ARM translation layer.
const office2013_transparent_ui_height = 145
const office2013_artifact_dark_limit = u32(60)
const office2013_tab_probe_x = [130, 450, 700]
const office2013_tab_probe_y = [28, 38, 47]
const xwd_fixed_header_size = u64(100)
const xwd_color_size = u64(12)
const xwd_file_version = u32(7)
const xwd_zpixmap = u32(2)
const xwd_max_surface_bytes = u64(64 * 1024 * 1024)

struct XwdSurface {
	mapping        voidptr
	size           u64
	pixels         &u8 = unsafe { nil }
	width          int
	height         int
	bytes_per_line int
	byte_order     u32
	red_mask       u32
	green_mask     u32
	blue_mask      u32
	red_shift      int
	green_shift    int
	blue_shift     int
	red_max        u32
	green_max      u32
	blue_max       u32
	// A 24-bit TrueColor Xvfb stores exactly the compositor's own pixel
	// layout. Recognising that lets a frame be copied word by word instead of
	// taking every channel apart, which is what the hosted browsers cost.
	direct bool
}

@[inline]
fn xwd_be32(bytes &u8, offset int) u32 {
	return unsafe {
		u32(bytes[offset]) << 24 | u32(bytes[offset + 1]) << 16 | u32(bytes[offset + 2]) << 8 | u32(bytes[offset + 3])
	}
}

fn xwd_mask_parts(mask u32) (int, u32) {
	mut shift := 0
	mut value := mask
	for shift < 32 && value & 1 == 0 {
		value >>= 1
		shift++
	}
	return shift, value
}

// A hosted surface is megabytes of shared pages that the application rewrites
// continuously. Mapping it afresh for every frame faults all of them back in
// every time, and on a machine running from a disk that walks the page cache
// over the very executable pages the hosted application is still demand-paging
// in — the browser and its own picture evicting each other. So a surface is
// mapped once and kept.
struct MappedSurface {
mut:
	path    string
	surface XwdSurface
}

__global mapped_surfaces = []MappedSurface{}

fn mapped_surface(path string) ?XwdSurface {
	for entry in mapped_surfaces {
		if entry.path == path {
			return entry.surface
		}
	}
	surface := open_xwd_surface(path)?
	// One live application per hosted window, and a window that closes leaves
	// its path behind; a handful of entries covers every desktop, and the
	// oldest is dropped rather than grown into.
	if mapped_surfaces.len >= 4 {
		mapped_surfaces[0].surface.close()
		unsafe { mapped_surfaces[0].path.free() }
		mapped_surfaces.delete(0)
	}
	mapped_surfaces << MappedSurface{
		path: path.clone()
		surface: surface
	}
	return surface
}

fn open_xwd_surface(path string) ?XwdSurface {
	info := desktop_stat(path) or { return none }
	if info.size < xwd_fixed_header_size || info.size > xwd_max_surface_bytes {
		return none
	}
	fd := desktop_open_ro_nonblock(path)
	if fd < 0 {
		return none
	}
	mapping := desktop_mmap_readonly(fd, info.size)
	desktop_close(fd)
	if mapping == unsafe { nil } {
		return none
	}
	bytes := unsafe { &u8(mapping) }
	header_size := u64(xwd_be32(bytes, 0))
	version := xwd_be32(bytes, 4)
	format := xwd_be32(bytes, 8)
	width := u64(xwd_be32(bytes, 16))
	height := u64(xwd_be32(bytes, 20))
	byte_order := xwd_be32(bytes, 28)
	bits_per_pixel := xwd_be32(bytes, 44)
	bytes_per_line := u64(xwd_be32(bytes, 48))
	red_mask := xwd_be32(bytes, 56)
	green_mask := xwd_be32(bytes, 60)
	blue_mask := xwd_be32(bytes, 64)
	ncolors := u64(xwd_be32(bytes, 76))
	pixel_offset := header_size + ncolors * xwd_color_size
	valid := version == xwd_file_version && format == xwd_zpixmap && width > 0
		&& height > 0 && width <= 8192 && height <= 8192 && bits_per_pixel == 32
		&& byte_order <= 1 && header_size >= xwd_fixed_header_size
		&& ncolors <= 65536 && pixel_offset <= info.size
		&& bytes_per_line >= width * 4 && height <= (info.size - pixel_offset) / bytes_per_line
		&& red_mask != 0 && green_mask != 0 && blue_mask != 0
	if !valid {
		desktop_munmap(mapping, info.size)
		return none
	}
	red_shift, red_max := xwd_mask_parts(red_mask)
	green_shift, green_max := xwd_mask_parts(green_mask)
	blue_shift, blue_max := xwd_mask_parts(blue_mask)
	if red_max == 0 || green_max == 0 || blue_max == 0 {
		desktop_munmap(mapping, info.size)
		return none
	}
	return XwdSurface{
		direct: byte_order == 0 && red_mask == 0xff0000 && green_mask == 0xff00
			&& blue_mask == 0xff && pixel_offset % 4 == 0 && bytes_per_line % 4 == 0
		mapping: mapping
		size: info.size
		pixels: unsafe { &u8(usize(mapping) + usize(pixel_offset)) }
		width: int(width)
		height: int(height)
		bytes_per_line: int(bytes_per_line)
		byte_order: byte_order
		red_mask: red_mask
		green_mask: green_mask
		blue_mask: blue_mask
		red_shift: red_shift
		green_shift: green_shift
		blue_shift: blue_shift
		red_max: red_max
		green_max: green_max
		blue_max: blue_max
	}
}

fn (surface &XwdSurface) close() {
	if surface.mapping != unsafe { nil } {
		desktop_munmap(surface.mapping, surface.size)
	}
}

@[inline]
fn xwd_channel(pixel u32, mask u32, shift int, maximum u32) u32 {
	value := (pixel & mask) >> shift
	return if maximum == 255 { value } else { value * 255 / maximum }
}

@[inline]
fn (surface &XwdSurface) pixel(x int, y int) u32 {
	offset := y * surface.bytes_per_line + x * 4
	raw := unsafe {
		if surface.byte_order == 0 {
			u32(surface.pixels[offset]) | u32(surface.pixels[offset + 1]) << 8 | u32(surface.pixels[offset + 2]) << 16 | u32(surface.pixels[offset + 3]) << 24
		} else {
			u32(surface.pixels[offset]) << 24 | u32(surface.pixels[offset + 1]) << 16 | u32(surface.pixels[offset + 2]) << 8 | u32(surface.pixels[offset + 3])
		}
	}
	red := xwd_channel(raw, surface.red_mask, surface.red_shift, surface.red_max)
	green := xwd_channel(raw, surface.green_mask, surface.green_shift, surface.green_max)
	blue := xwd_channel(raw, surface.blue_mask, surface.blue_shift, surface.blue_max)
	return red << 16 | green << 8 | blue
}

@[inline]
fn office2013_is_artifact_pixel(color u32) bool {
	red := (color >> 16) & 0xff
	green := (color >> 8) & 0xff
	blue := color & 0xff
	minimum := if red < green {
		if red < blue { red } else { blue }
	} else {
		if green < blue { green } else { blue }
	}
	maximum := if red > green {
		if red > blue { red } else { blue }
	} else {
		if green > blue { green } else { blue }
	}
	return maximum <= office2013_artifact_dark_limit && maximum - minimum <= 2
}

@[inline]
fn office2013_has_transparent_backing(x int, y int) bool {
	// Unselected ribbon tabs.
	if y >= 25 && y <= 49 && x >= 122 {
		return true
	}
	// The stray right edge of the blue File tab.
	if y >= 25 && y <= 49 && x >= 59 && x <= 62 {
		return true
	}
	// Font name and font size frames. Their interiors contain legitimate
	// solid-black glyphs, so repair only the connected frame pixels.
	font_frame := (x >= 76 && x <= 161 && ((y >= 61 && y <= 64) || (y >= 80 && y <= 84)))
		|| (((x >= 76 && x <= 78) || (x >= 159 && x <= 161)) && y >= 65 && y <= 79)
	size_frame := (x >= 174 && x <= 200 && ((y >= 61 && y <= 64) || (y >= 80 && y <= 84)))
		|| (((x >= 174 && x <= 176) || (x >= 198 && x <= 200)) && y >= 65 && y <= 79)
	// The connected Styles-gallery frame changes width with the X desktop,
	// while its left edge and column separators remain fixed.
	styles_frame := (x >= 566 && ((y >= 56 && y <= 61) || (y >= 110 && y <= 116)))
		|| (y >= 62 && y <= 109 && ((x >= 566 && x <= 568) || (x >= 639 && x <= 643)
			|| (x >= 707 && x <= 715)))
	return font_frame || size_frame || styles_frame
}

@[inline]
fn office2013_presented_color(color u32, source_x int, source_y int) u32 {
	if source_y >= 25 && source_y <= 49
		&& (source_x >= 122 || (source_x >= 59 && source_x <= 62)) {
		return 0xffffff
	}
	if source_y >= office2013_transparent_ui_height
		|| !office2013_has_transparent_backing(source_x, source_y)
		|| !office2013_is_artifact_pixel(color) {
		return color
	}
	// The tab glyphs were premultiplied into the missing layer too, so their
	// original coverage cannot be reconstructed. Clear the entire damaged
	// layer here; the renderer replaces those seven labels after scaling.
	return 0xffffff
}

@[inline]
fn (surface &XwdSurface) presented_pixel(x int, y int, repair_office_ui bool) u32 {
	color := surface.pixel(x, y)
	return if repair_office_ui { office2013_presented_color(color, x, y) } else { color }
}

// Interpolate four opaque XWD pixels with 8-bit fractional coordinates.  The
// hosted X server is deliberately independent from a Vinix window, so moving
// to a larger screen or maximising the window often makes their dimensions
// differ.  Nearest-neighbour sampling turned every one-pixel font edge into a
// conspicuous block in that case.
@[inline]
fn xwd_bilinear_color(top_left u32, top_right u32, bottom_left u32, bottom_right u32,
	fraction_x u32, fraction_y u32) u32 {
	inverse_x := 256 - fraction_x
	inverse_y := 256 - fraction_y
	top_left_weight := inverse_x * inverse_y
	top_right_weight := fraction_x * inverse_y
	bottom_left_weight := inverse_x * fraction_y
	bottom_right_weight := fraction_x * fraction_y

	red := (((top_left >> 16) & 0xff) * top_left_weight + ((top_right >> 16) & 0xff) * top_right_weight + ((bottom_left >> 16) & 0xff) * bottom_left_weight + ((bottom_right >> 16) & 0xff) * bottom_right_weight + 32768) >> 16
	green := (((top_left >> 8) & 0xff) * top_left_weight + ((top_right >> 8) & 0xff) * top_right_weight + ((bottom_left >> 8) & 0xff) * bottom_left_weight + ((bottom_right >> 8) & 0xff) * bottom_right_weight + 32768) >> 16
	blue := ((top_left & 0xff) * top_left_weight + (top_right & 0xff) * top_right_weight + (bottom_left & 0xff) * bottom_left_weight + (bottom_right & 0xff) * bottom_right_weight + 32768) >> 16
	return red << 16 | green << 8 | blue
}

// draw_xwd_surface scales the live mmap directly into the compositor canvas.
// Xvfb and the desktop share the kernel page cache, so no screenshot file is
// copied or rewritten for each frame.
fn (mut canvas Canvas) draw_xwd_surface(path string, x int, y int, width int, height int) bool {
	drawn, _ := canvas.draw_presented_xwd_surface(path, x, y, width, height, false)
	return drawn
}

fn (mut canvas Canvas) draw_office_xwd_surface(path string, x int, y int, width int, height int) (bool, bool) {
	return canvas.draw_presented_xwd_surface(path, x, y, width, height, true)
}

@[inline]
fn (surface &XwdSurface) direct_pixel(x int, y int) u32 {
	unsafe {
		return *(&u32(&surface.pixels[y * surface.bytes_per_line + x * 4])) & 0x00ffffff
	}
}

// blit_direct_surface is the same picture as the general path below, for the
// case that covers every hosted browser: a 24-bit surface whose pixels already
// have the compositor's own layout. Dropping the per-pixel channel decode is
// what makes a 1280x900 window affordable on an emulated core.
//
// A window's rounded corners only reach the first and last few rows, so the
// decision is taken per row: the rows clear of them are written straight into
// the canvas, and the rest keep the general blend.
fn (mut canvas Canvas) blit_direct_surface(surface &XwdSurface, x int, y int, width int, height int) {
	unscaled := width == surface.width && height == surface.height
	step_x := if width > 1 { (surface.width - 1) * 65536 / (width - 1) } else { 0 }
	step_y := if height > 1 { (surface.height - 1) * 65536 / (height - 1) } else { 0 }
	for destination_y := 0; destination_y < height; destination_y++ {
		plain := canvas.clip_is_plain(x, y + destination_y, width, 1)
		if unscaled {
			source_row := destination_y * surface.bytes_per_line
			if plain {
				destination_row := (y + destination_y) * canvas.stride + x
				for column := 0; column < width; column++ {
					unsafe {
						canvas.pixels[destination_row + column] = *(&u32(&surface.pixels[
							source_row + column * 4])) & 0x00ffffff
					}
				}
			} else {
				for column := 0; column < width; column++ {
					canvas.blend_pixel(x + column, y + destination_y, surface.direct_pixel(column,
						destination_y), 255)
				}
			}
			continue
		}

		fixed_y := if destination_y + 1 == height {
			(surface.height - 1) * 65536
		} else {
			destination_y * step_y
		}
		source_y := fixed_y >> 16
		next_y := if source_y + 1 < surface.height { source_y + 1 } else { source_y }
		fraction_y := u32(fixed_y & 0xffff) >> 8
		destination_row := (y + destination_y) * canvas.stride + x
		mut fixed_x := 0
		for destination_x := 0; destination_x < width; destination_x++ {
			if destination_x + 1 == width {
				fixed_x = (surface.width - 1) * 65536
			}
			source_x := fixed_x >> 16
			next_x := if source_x + 1 < surface.width { source_x + 1 } else { source_x }
			fraction_x := u32(fixed_x & 0xffff) >> 8
			color := xwd_bilinear_color(surface.direct_pixel(source_x, source_y),
				surface.direct_pixel(next_x, source_y), surface.direct_pixel(source_x,
				next_y), surface.direct_pixel(next_x, next_y), fraction_x, fraction_y)
			if plain {
				unsafe {
					canvas.pixels[destination_row + destination_x] = color
				}
			} else {
				canvas.blend_pixel(x + destination_x, y + destination_y, color, 255)
			}
			fixed_x += step_x
		}
	}
}

fn (mut canvas Canvas) draw_presented_xwd_surface(path string, x int, y int, width int, height int,
	repair_office_ui bool) (bool, bool) {
	if width <= 0 || height <= 0 {
		return false, false
	}
	surface := mapped_surface(path) or { return false, false }
	has_office_ribbon := repair_office_ui && surface.office2013_has_tab_backing()
	if surface.direct && !has_office_ribbon {
		canvas.blit_direct_surface(surface, x, y, width, height)
		return true, has_office_ribbon
	}
	if width == surface.width && height == surface.height {
		for destination_y := 0; destination_y < height; destination_y++ {
			for destination_x := 0; destination_x < width; destination_x++ {
				canvas.blend_pixel(x + destination_x, y + destination_y, surface.presented_pixel(destination_x, destination_y, has_office_ribbon), 255)
			}
		}
		return true, has_office_ribbon
	}

	step_x := if width > 1 { (surface.width - 1) * 65536 / (width - 1) } else { 0 }
	step_y := if height > 1 { (surface.height - 1) * 65536 / (height - 1) } else { 0 }
	for destination_y := 0; destination_y < height; destination_y++ {
		fixed_y := if destination_y + 1 == height {
			(surface.height - 1) * 65536
		} else {
			destination_y * step_y
		}
		source_y := fixed_y >> 16
		next_y := if source_y + 1 < surface.height { source_y + 1 } else { source_y }
		fraction_y := u32(fixed_y & 0xffff) >> 8
		mut fixed_x := 0
		for destination_x := 0; destination_x < width; destination_x++ {
			if destination_x + 1 == width {
				fixed_x = (surface.width - 1) * 65536
			}
			source_x := fixed_x >> 16
			next_x := if source_x + 1 < surface.width { source_x + 1 } else { source_x }
			fraction_x := u32(fixed_x & 0xffff) >> 8
			color := xwd_bilinear_color(surface.presented_pixel(source_x, source_y, has_office_ribbon), surface.presented_pixel(next_x, source_y, has_office_ribbon), surface.presented_pixel(source_x, next_y, has_office_ribbon), surface.presented_pixel(next_x, next_y, has_office_ribbon), fraction_x, fraction_y)
			canvas.blend_pixel(x + destination_x, y + destination_y, color, 255)
			fixed_x += step_x
		}
	}
	return true, has_office_ribbon
}

fn (surface &XwdSurface) office2013_has_tab_backing() bool {
	if surface.width <= 700 || surface.height <= 47 {
		return false
	}
	// A document ribbon has a near-black Direct2D backing across this whole
	// strip. Word's start page is blue on the left and white on the right, so
	// requiring most of these dispersed probes avoids painting tabs there.
	mut matches := 0
	for source_y in office2013_tab_probe_y {
		for source_x in office2013_tab_probe_x {
			if office2013_is_artifact_pixel(surface.pixel(source_x, source_y)) {
				matches++
			}
		}
	}
	return matches >= 6
}
