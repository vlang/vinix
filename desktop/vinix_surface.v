// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Native Vinix client surfaces consumed by the desktop compositor.
module main

fn C.vinix_surface_claim_reader(active_buffer &u32, reader_buffer &u32) u32

fn C.vinix_surface_release_reader(reader_buffer &u32)

const vinix_surface_image_prefix = 'vinix-surface:'
const vinix_preview_image_prefix = 'vinix-preview:'
const vinix_surface_magic = u32(0x31534656) // VSF1 in little-endian memory
const vinix_surface_version = u32(1)
const vinix_surface_header_size = u64(48)
const vinix_surface_format_xrgb8888 = u32(1)
const vinix_surface_max_bytes = u64(128 * 1024 * 1024)
const vinix_preview_cache_max_pixels = 4 * 1024 * 1024

struct VinixSurface {
	mapping       voidptr
	size          u64
	pixels        &u8  = unsafe { nil }
	reader_buffer &u32 = unsafe { nil }
	width         int
	height        int
	stride        int
}

@[inline]
fn vinix_surface_u32(bytes &u8, offset int) u32 {
	return unsafe {
		u32(bytes[offset]) | u32(bytes[offset + 1]) << 8 | u32(bytes[offset + 2]) << 16 |
			u32(bytes[offset + 3]) << 24
	}
}

fn open_vinix_surface(path string) ?VinixSurface {
	info := desktop_stat(path) or { return none }
	if info.size < vinix_surface_header_size || info.size > vinix_surface_max_bytes {
		return none
	}
	fd := desktop_open_rw(path)
	if fd < 0 {
		return none
	}
	mapping := desktop_mmap_shared(fd, info.size)
	desktop_close(fd)
	if mapping == unsafe { nil } {
		return none
	}
	bytes := unsafe { &u8(mapping) }
	magic := vinix_surface_u32(bytes, 0)
	version := vinix_surface_u32(bytes, 4)
	header_size := u64(vinix_surface_u32(bytes, 8))
	width := u64(vinix_surface_u32(bytes, 12))
	height := u64(vinix_surface_u32(bytes, 16))
	stride := u64(vinix_surface_u32(bytes, 20))
	format := vinix_surface_u32(bytes, 24)
	buffer_size := u64(vinix_surface_u32(bytes, 40))
	valid := magic == vinix_surface_magic && version == vinix_surface_version
		&& header_size == vinix_surface_header_size && width > 0 && height > 0
		&& width <= 8192 && height <= 8192 && stride >= width * 4
		&& stride <= 8192 * 4 && format == vinix_surface_format_xrgb8888
		&& buffer_size == stride * height && buffer_size <= (info.size - header_size) / 2
	if !valid {
		desktop_munmap(mapping, info.size)
		return none
	}
	active_ptr := unsafe { &u32(usize(mapping) + 28) }
	reader_ptr := unsafe { &u32(usize(mapping) + 32) }
	active := C.vinix_surface_claim_reader(active_ptr, reader_ptr)
	if active > 1 {
		C.vinix_surface_release_reader(reader_ptr)
		desktop_munmap(mapping, info.size)
		return none
	}
	pixel_offset := header_size + u64(active) * buffer_size
	return VinixSurface{
		mapping:       mapping
		size:          info.size
		pixels:        unsafe { &u8(usize(mapping) + usize(pixel_offset)) }
		reader_buffer: reader_ptr
		width:         int(width)
		height:        int(height)
		stride:        int(stride)
	}
}

fn (surface &VinixSurface) close() {
	if surface.mapping != unsafe { nil } {
		C.vinix_surface_release_reader(surface.reader_buffer)
		desktop_munmap(surface.mapping, surface.size)
	}
}

@[inline]
fn (surface &VinixSurface) pixel(x int, y int) u32 {
	offset := y * surface.stride + x * 4
	return unsafe {
		u32(surface.pixels[offset]) | u32(surface.pixels[offset + 1]) << 8 |
			u32(surface.pixels[offset + 2]) << 16
	}
}

// Scale a native client surface into its compositor-owned window. Bilinear
// filtering matches hosted surfaces when the desktop is resized or maximized.
fn (mut canvas Canvas) draw_vinix_surface(path string, x int, y int, width int, height int) bool {
	if width <= 0 || height <= 0 {
		return false
	}
	surface := open_vinix_surface(path) or { return false }
	defer {
		surface.close()
	}
	if width == surface.width && height == surface.height {
		for destination_y := 0; destination_y < height; destination_y++ {
			for destination_x := 0; destination_x < width; destination_x++ {
				canvas.blend_pixel(x + destination_x, y + destination_y,
					surface.pixel(destination_x, destination_y), 255)
			}
		}
		return true
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
			color := xwd_bilinear_color(surface.pixel(source_x, source_y),
				surface.pixel(next_x, source_y), surface.pixel(source_x, next_y),
				surface.pixel(next_x, next_y), fraction_x, fraction_y)
			canvas.blend_pixel(x + destination_x, y + destination_y, color, 255)
			fixed_x += step_x
		}
	}
	return true
}

// Quick Look surfaces are immutable. Keep one image at its displayed size so
// pointer redraws copy pixels instead of remapping and filtering the image.
struct VinixPreviewCache {
mut:
	path   string
	width  int
	height int
	pixels &u32 = unsafe { nil }
}

fn (mut cache VinixPreviewCache) clear() {
	if cache.pixels != unsafe { nil } {
		unsafe { free(cache.pixels) }
	}
	if cache.path.len > 0 {
		unsafe { cache.path.free() }
	}
	cache.path = ''
	cache.width = 0
	cache.height = 0
	cache.pixels = unsafe { nil }
}

fn (mut cache VinixPreviewCache) draw(mut canvas Canvas, path string, x int, y int, width int, height int) bool {
	if width <= 0 || height <= 0 {
		return false
	}
	// The preview's normal display area is much smaller. A very large window
	// uses the uncached path rather than holding another screen-sized buffer.
	if i64(width) * i64(height) > vinix_preview_cache_max_pixels {
		return canvas.draw_vinix_surface(path, x, y, width, height)
	}
	x0 := if x > canvas.clip.x { x } else { canvas.clip.x }
	y0 := if y > canvas.clip.y { y } else { canvas.clip.y }
	x1 := if x + width < canvas.clip.x + canvas.clip.w {
		x + width
	} else {
		canvas.clip.x + canvas.clip.w
	}
	y1 := if y + height < canvas.clip.y + canvas.clip.h {
		y + height
	} else {
		canvas.clip.y + canvas.clip.h
	}
	if x1 <= x0 || y1 <= y0 {
		return true
	}
	if cache.pixels == unsafe { nil } || cache.path != path || cache.width != width || cache.height != height {
		cache.clear()
		mut scaled := new_scaled_canvas(width, height, width, height, 1)
		if !scaled.draw_vinix_surface(path, 0, 0, width, height) {
			unsafe { free(scaled.pixels) }
			return false
		}
		cache.path = path.clone()
		cache.width = width
		cache.height = height
		cache.pixels = scaled.pixels
	}
	for row := y0; row < y1; row++ {
		source := unsafe { &cache.pixels[(row - y) * width + x0 - x] }
		if canvas.clip_is_plain(x0, row, x1 - x0, 1) {
			if canvas.scale == 1 {
				unsafe { C.memcpy(&canvas.pixels[row * canvas.stride + x0], source, usize((x1 - x0) * 4)) }
				continue
			}
			if canvas.scale == 2 && x1 * 2 <= canvas.physical_width
				&& (row + 1) * 2 <= canvas.physical_height {
				destination := row * 2 * canvas.stride + x0 * 2
				for column := 0; column < x1 - x0; column++ {
					color := unsafe { source[column] }
					unsafe {
						canvas.pixels[destination + column * 2] = color
						canvas.pixels[destination + column * 2 + 1] = color
					}
				}
				unsafe { C.memcpy(&canvas.pixels[destination + canvas.stride], &canvas.pixels[destination], usize((x1 - x0) * 8)) }
				continue
			}
		}
		for column := x0; column < x1; column++ {
			canvas.blend_pixel(column, row, unsafe { cache.pixels[(row - y) * width + column - x] }, 255)
		}
	}
	return true
}
