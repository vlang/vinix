// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Decoding and drawing application images. The desktop's own icons use QOI;
// trusted native applications can also load their bundled PNG resources.
module main

import compress.zlib
import os

const app_icon_dir = '/usr/share/vinix/icons'

struct AppIcon {
	width  int
	height int
	// Pixels are 0xAARRGGBB, so the transparent edges of the source artwork
	// compose correctly over every wallpaper and menu colour.
	pixels []u32
}

fn qoi_u32_be(bytes []u8, at int) ?u32 {
	if at < 0 || at + 4 > bytes.len {
		return none
	}
	return u32(bytes[at]) << 24 | u32(bytes[at + 1]) << 16 | u32(bytes[at + 2]) << 8 | u32(bytes[at + 3])
}

// decode_qoi is intentionally small: QOI's lossless opcode stream gives the
// desktop alpha-correct, high-resolution icons with no graphics dependency.
fn decode_qoi(bytes []u8) ?AppIcon {
	if bytes.len < 22 || bytes[0] != `q` || bytes[1] != `o` || bytes[2] != `i` || bytes[3] != `f` {
		return none
	}
	width := int(qoi_u32_be(bytes, 4)?)
	height := int(qoi_u32_be(bytes, 8)?)
	channels := bytes[12]
	if width <= 0 || height <= 0 || width > 2048 || height > 2048 || channels < 3 || channels > 4 {
		return none
	}
	pixel_count := width * height
	if pixel_count / width != height {
		return none
	}
	mut pixels := []u32{len: pixel_count}
	mut index := [64]u32{}
	mut at := 14
	mut r := u8(0)
	mut g := u8(0)
	mut b := u8(0)
	mut a := u8(255)
	mut run := 0
	for pixel in 0 .. pixel_count {
		if run > 0 {
			run--
		} else {
			if at >= bytes.len {
				return none
			}
			op := bytes[at]
			at++
			if op == 0xfe {
				if at + 3 > bytes.len {
					return none
				}
				r = bytes[at]
				g = bytes[at + 1]
				b = bytes[at + 2]
				at += 3
			} else if op == 0xff {
				if at + 4 > bytes.len {
					return none
				}
				r = bytes[at]
				g = bytes[at + 1]
				b = bytes[at + 2]
				a = bytes[at + 3]
				at += 4
			} else if op & 0xc0 == 0x00 {
				packed := index[op]
				r = u8(packed >> 24)
				g = u8(packed >> 16)
				b = u8(packed >> 8)
				a = u8(packed)
			} else if op & 0xc0 == 0x40 {
				r = u8(int(r) + int(op >> 4 & 0x03) - 2)
				g = u8(int(g) + int(op >> 2 & 0x03) - 2)
				b = u8(int(b) + int(op & 0x03) - 2)
			} else if op & 0xc0 == 0x80 {
				if at >= bytes.len {
					return none
				}
				next := bytes[at]
				at++
				dg := int(op & 0x3f) - 32
				r = u8(int(r) + dg + int(next >> 4) - 8)
				g = u8(int(g) + dg)
				b = u8(int(b) + dg + int(next & 0x0f) - 8)
			} else {
				run = int(op & 0x3f)
			}
		}
		packed := u32(r) << 24 | u32(g) << 16 | u32(b) << 8 | u32(a)
		index[(u32(r) * 3 + u32(g) * 5 + u32(b) * 7 + u32(a) * 11) % 64] = packed
		pixels[pixel] = u32(a) << 24 | u32(r) << 16 | u32(g) << 8 | u32(b)
	}
	return AppIcon{
		width:  width
		height: height
		pixels: pixels
	}
}

fn png_u32_be(bytes []u8, at int) ?u32 {
	if at < 0 || at + 4 > bytes.len {
		return none
	}
	return u32(bytes[at]) << 24 | u32(bytes[at + 1]) << 16 | u32(bytes[at + 2]) << 8 |
		u32(bytes[at + 3])
}

fn png_paeth(left int, above int, upper_left int) int {
	predicted := left + above - upper_left
	left_distance := if predicted > left { predicted - left } else { left - predicted }
	above_distance := if predicted > above { predicted - above } else { above - predicted }
	upper_left_distance := if predicted > upper_left {
		predicted - upper_left
	} else {
		upper_left - predicted
	}
	return if left_distance <= above_distance && left_distance <= upper_left_distance {
		left
	} else if above_distance <= upper_left_distance {
		above
	} else {
		upper_left
	}
}

// decode_png covers the lossless formats used by VOffice's ribbon artwork:
// 8-bit RGB/RGBA, standard row filters, and a non-interlaced image. Keeping
// this narrow avoids pulling a general image stack into the compositor.
fn decode_png(bytes []u8) ?AppIcon {
	if bytes.len < 33 || bytes[..8] != [u8(0x89), `P`, `N`, `G`, `\r`, `\n`, 0x1a, `\n`] {
		return none
	}
	mut at := 8
	mut width := 0
	mut height := 0
	mut channels := 0
	mut saw_header := false
	mut saw_end := false
	mut compressed := []u8{}
	defer {
		unsafe { compressed.free() }
	}
	for at + 12 <= bytes.len {
		length := int(png_u32_be(bytes, at)?)
		if length < 0 || at + 12 + length > bytes.len {
			return none
		}
		kind := bytes[at + 4..at + 8].bytestr()
		data := bytes[at + 8..at + 8 + length]
		match kind {
			'IHDR' {
				if saw_header || length != 13 {
					return none
				}
				width = int(png_u32_be(data, 0)?)
				height = int(png_u32_be(data, 4)?)
				channels = if data[9] == 2 {
					3
				} else if data[9] == 6 { 4 } else { 0 }
				if width <= 0 || height <= 0 || width > 4096 || height > 4096
					|| i64(width) * i64(height) > 16 * 1024 * 1024 || data[8] != 8
					|| channels == 0 || data[10] != 0 || data[11] != 0 || data[12] != 0 {
					return none
				}
				saw_header = true
			}
			'IDAT' {
				if !saw_header {
					return none
				}
				compressed << data
			}
			'IEND' {
				saw_end = true
			}
			else {}
		}
		at += length + 12
		if saw_end {
			break
		}
	}
	if !saw_header || !saw_end || compressed.len == 0 {
		return none
	}
	raw := zlib.decompress(compressed) or { return none }
	defer {
		unsafe { raw.free() }
	}
	row_bytes := width * channels
	if raw.len != (row_bytes + 1) * height {
		return none
	}
	mut decoded := []u8{len: row_bytes * height}
	defer {
		unsafe { decoded.free() }
	}
	for y in 0 .. height {
		filter := raw[y * (row_bytes + 1)]
		if filter > 4 {
			return none
		}
		for x in 0 .. row_bytes {
			source := int(raw[y * (row_bytes + 1) + 1 + x])
			left := if x >= channels { int(decoded[y * row_bytes + x - channels]) } else { 0 }
			above := if y > 0 { int(decoded[(y - 1) * row_bytes + x]) } else { 0 }
			upper_left := if y > 0 && x >= channels {
				int(decoded[(y - 1) * row_bytes + x - channels])
			} else {
				0
			}
			predictor := match filter {
				1 { left }
				2 { above }
				3 { (left + above) / 2 }
				4 { png_paeth(left, above, upper_left) }
				else { 0 }
			}
			decoded[y * row_bytes + x] = u8(source + predictor)
		}
	}
	mut pixels := []u32{len: width * height}
	for pixel in 0 .. pixels.len {
		offset := pixel * channels
		alpha := if channels == 4 { u32(decoded[offset + 3]) } else { u32(255) }
		pixels[pixel] = alpha << 24 | u32(decoded[offset]) << 16 |
			u32(decoded[offset + 1]) << 8 | u32(decoded[offset + 2])
	}
	return AppIcon{
		width:  width
		height: height
		pixels: pixels
	}
}

fn load_app_icon(name string) AppIcon {
	bytes := os.read_bytes('${app_icon_dir}/${name}.qoi') or { return AppIcon{} }
	defer {
		if bytes.cap > 0 {
			unsafe { bytes.free() }
		}
	}
	return decode_qoi(bytes) or { AppIcon{} }
}

fn (mut d Desktop) load_app_icons() {
	d.firefox_icon = load_app_icon('firefox')
	d.chromium_icon = load_app_icon('chromium')
	d.blender_icon = load_app_icon('blender')
	d.minecraft_icon = load_app_icon('minecraft')
	d.terminal_icon = load_app_icon('terminal')
	d.settings_icon = load_app_icon('settings')
	d.activity_icon = load_app_icon('activity')
	d.calculator_icon = load_app_icon('calculator')
	d.vspace_icon = load_app_icon('vspace')
	d.editor_icon = load_app_icon('editor')
	d.files_icon = load_app_icon('files')
	d.clock_icon = load_app_icon('clock')
	d.calendar_icon = load_app_icon('calendar')
	d.capture_icon = load_app_icon('capture')
}

fn (d &Desktop) bundled_app_icon(path string) &AppIcon {
	match path {
		'asset:firefox' { return &d.firefox_icon }
		'asset:chromium' { return &d.chromium_icon }
		'asset:blender' { return &d.blender_icon }
		'asset:minecraft' { return &d.minecraft_icon }
		'asset:terminal' { return &d.terminal_icon }
		'asset:settings' { return &d.settings_icon }
		'asset:activity' { return &d.activity_icon }
		'asset:calculator' { return &d.calculator_icon }
		'asset:vspace' { return &d.vspace_icon }
		'asset:editor' { return &d.editor_icon }
		'asset:files' { return &d.files_icon }
		'asset:clock' { return &d.clock_icon }
		'asset:calendar' { return &d.calendar_icon }
		'asset:capture' { return &d.capture_icon }
		else { return unsafe { nil } }
	}
}

fn (mut d Desktop) app_icon(path string) &AppIcon {
	bundled := d.bundled_app_icon(path)
	if !isnil(bundled) {
		return bundled
	}
	// Native UI2 apps may only ask the compositor to open installed, immutable
	// application assets. Do not turn arbitrary document paths into reads by
	// the privileged desktop process.
	if !path.starts_with('/usr/bin/assets/') || !path.ends_with('.png')
		|| path.contains('/../') || path.contains('/./') || path.contains('//') {
		return unsafe { nil }
	}
	if cached := d.native_asset_icons[path] {
		return cached
	}
	bytes := os.read_bytes(path) or {
		missing := &AppIcon{}
		d.native_asset_icons[path] = missing
		return missing
	}
	defer {
		unsafe { bytes.free() }
	}
	icon := decode_png(bytes) or {
		invalid := &AppIcon{}
		d.native_asset_icons[path] = invalid
		return invalid
	}
	loaded := &AppIcon{
		width:  icon.width
		height: icon.height
		pixels: icon.pixels
	}
	d.native_asset_icons[path] = loaded
	return loaded
}

// draw_app_icon samples the original 512px artwork on the physical output
// grid. The desktop therefore remains sharp on 2x panels instead of scaling a
// 30px logical bitmap into soft blocks.
fn (mut d Desktop) draw_app_icon(path string, x int, y int, w int, h int) bool {
	icon := d.app_icon(path)
	if isnil(icon) || icon.width == 0 || icon.height == 0 || w <= 0 || h <= 0 {
		return false
	}
	physical_w := w * d.canvas.scale
	physical_h := h * d.canvas.scale
	for py in 0 .. physical_h {
		sy := py * icon.height / physical_h
		for px in 0 .. physical_w {
			sx := px * icon.width / physical_w
			pixel := icon.pixels[sy * icon.width + sx]
			d.canvas.blend_physical_pixel(x * d.canvas.scale + px, y * d.canvas.scale + py,
				pixel & 0x00ffffff, pixel >> 24)
		}
	}
	return true
}
