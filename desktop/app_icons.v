// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// High-resolution application icons staged in a tiny raw RGBA format.
module main

const app_icon_dir = '/usr/share/vinix/app-icons'
const app_icon_prefix = 'appicon:'
const app_icon_magic = 'VAI1'
const app_icon_header_size = 9

struct AppIconImage {
	width  int
	height int
	pixels []u8 // RGBA, row-major
}

struct AppIconCacheEntry {
mut:
	attempted bool
	image     AppIconImage
}

struct AppIconCache {
mut:
	entries [5]AppIconCacheEntry
}

__global app_icon_cache = AppIconCache{}

fn app_icon_slot(key string) ?int {
	match key {
		'firefox' { return 0 }
		'chromium' { return 1 }
		'blender' { return 2 }
		'gimp' { return 3 }
		'libreoffice' { return 4 }
		else { return none }
	}
}

fn app_icon_fallback(key string) string {
	return match key {
		'firefox', 'chromium' { 'builtin:browser' }
		'blender' { 'builtin:block' }
		'gimp', 'libreoffice' { 'builtin:editor' }
		else { '' }
	}
}

fn load_app_icon_file(path string) ?AppIconImage {
	info := desktop_stat(path) or { return none }
	if info.size <= u64(app_icon_header_size) || info.size > u64(8 * 1024 * 1024) {
		return none
	}
	mut buffer := []u8{len: int(info.size)}
	got := desktop_read_file(path, buffer.data, info.size)
	if got < i64(app_icon_header_size) {
		unsafe { buffer.free() }
		return none
	}
	for i in 0 .. app_icon_magic.len {
		if buffer[i] != app_icon_magic[i] {
			unsafe { buffer.free() }
			return none
		}
	}
	width := int(u16(buffer[4]) | u16(buffer[5]) << 8)
	height := int(u16(buffer[6]) | u16(buffer[7]) << 8)
	if width <= 0 || height <= 0 || width > 1024 || height > 1024 {
		unsafe { buffer.free() }
		return none
	}
	needed := app_icon_header_size + width * height * 4
	if int(got) < needed {
		unsafe { buffer.free() }
		return none
	}
	pixels := buffer[app_icon_header_size..needed].clone()
	unsafe { buffer.free() }
	return AppIconImage{
		width: width
		height: height
		pixels: pixels
	}
}

fn app_icon_channel(image &AppIconImage, a int, b int, c int, d int, channel int,
	fraction_x u32, fraction_y u32) u32 {
	top := blend_channel(image.pixels[a + channel], image.pixels[b + channel], fraction_x)
	bottom := blend_channel(image.pixels[c + channel], image.pixels[d + channel], fraction_x)
	return blend_channel(u8(top), u8(bottom), fraction_y)
}

// draw_app_icon samples at physical resolution. A 48-logical-pixel shortcut
// therefore uses 96 real pixels at 2x instead of stretching a 48-pixel raster.
fn (mut d Desktop) draw_app_icon(key string, x int, y int, width int, height int) bool {
	slot := app_icon_slot(key) or { return false }
	mut entry := &app_icon_cache.entries[slot]
	if !entry.attempted {
		entry.attempted = true
		path := '${app_icon_dir}/${key}.vai'
		if image := load_app_icon_file(path) {
			entry.image = image
		}
		unsafe { path.free() }
	}
	if entry.image.pixels.len == 0 || width <= 0 || height <= 0 {
		return false
	}

	dest_width := width * d.canvas.scale
	dest_height := height * d.canvas.scale
	if dest_width <= 0 || dest_height <= 0 {
		return false
	}
	step_x := if dest_width > 1 {
		(entry.image.width - 1) * 65536 / (dest_width - 1)
	} else {
		0
	}
	step_y := if dest_height > 1 {
		(entry.image.height - 1) * 65536 / (dest_height - 1)
	} else {
		0
	}
	base_x := x * d.canvas.scale
	base_y := y * d.canvas.scale

	for out_y in 0 .. dest_height {
		fixed_y := out_y * step_y
		src_y := fixed_y >> 16
		fraction_y := u32(fixed_y & 0xffff) >> 8
		next_y := if src_y + 1 < entry.image.height { src_y + 1 } else { src_y }
		row0 := src_y * entry.image.width * 4
		row1 := next_y * entry.image.width * 4
		mut fixed_x := 0
		for out_x in 0 .. dest_width {
			src_x := fixed_x >> 16
			fraction_x := u32(fixed_x & 0xffff) >> 8
			next_x := if src_x + 1 < entry.image.width { src_x + 1 } else { src_x }
			fixed_x += step_x

			a := row0 + src_x * 4
			b := row0 + next_x * 4
			c := row1 + src_x * 4
			e := row1 + next_x * 4
			r := app_icon_channel(&entry.image, a, b, c, e, 0, fraction_x, fraction_y)
			g := app_icon_channel(&entry.image, a, b, c, e, 1, fraction_x, fraction_y)
			blue := app_icon_channel(&entry.image, a, b, c, e, 2, fraction_x, fraction_y)
			alpha := app_icon_channel(&entry.image, a, b, c, e, 3, fraction_x, fraction_y)
			d.canvas.blend_physical_pixel(base_x + out_x, base_y + out_y,
				r << 16 | g << 8 | blue, alpha)
		}
	}
	return true
}
