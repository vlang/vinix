// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Native Vinix client surfaces consumed by the desktop compositor.
module main

fn C.vinix_surface_claim_reader(active_buffer &u32, reader_buffer &u32) u32

fn C.vinix_surface_release_reader(reader_buffer &u32)

const vinix_surface_image_prefix = 'vinix-surface:'
const vinix_surface_magic = u32(0x31534656) // VSF1 in little-endian memory
const vinix_surface_version = u32(1)
const vinix_surface_header_size = u64(48)
const vinix_surface_format_xrgb8888 = u32(1)
const vinix_surface_max_bytes = u64(128 * 1024 * 1024)

struct VinixSurface {
	mapping       voidptr
	size          u64
	pixels        &u8 = unsafe { nil }
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
		mapping: mapping
		size: info.size
		pixels: unsafe { &u8(usize(mapping) + usize(pixel_offset)) }
		reader_buffer: reader_ptr
		width: int(width)
		height: int(height)
		stride: int(stride)
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
