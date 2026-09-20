// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Decoding and drawing the small set of official application icons shipped by
// the desktop. QOI keeps those source-quality 512px images compact without
// bringing a PNG library into Vinix's static framebuffer compositor.
module main

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
}

fn (d &Desktop) app_icon(path string) &AppIcon {
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
		else { return unsafe { nil } }
	}
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
