// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The software renderer. Everything the desktop puts on screen goes through
// these primitives: there is no GPU on the machines Vinix boots on yet, so the
// compositor owns every pixel it draws.
//
// Colors are 0xRRGGBB. The canvas is a back buffer; a frame is composed in
// full and then handed to Framebuffer.present, so a half-drawn window is never
// visible.
module main

import math

// Clip is what a drawing call is allowed to touch: a rectangle, plus an
// optional rounded mask. The two are separate because a window is a rounded
// rectangle whose children are clipped by *its* corners while their own
// rectangles keep trimming the area further in — one rounded shape and one
// rectangle is everything this compositor nests.
struct Clip {
mut:
	x int
	y int
	w int
	h int
	// Rounded mask; mask_radius == 0 means there is none.
	mask_x      int
	mask_y      int
	mask_w      int
	mask_h      int
	mask_radius int
}

struct Canvas {
mut:
	// width and height stay in logical desktop coordinates. The backing store
	// is allowed to be denser, so HiDPI text can be rasterised at the panel's
	// native resolution without changing any window geometry or hit targets.
	width           int
	height          int
	physical_width  int
	physical_height int
	scale           int = 1
	stride          int
	pixels          &u32 = unsafe { nil }
	clip            Clip
}

/*
fn new_canvas(width int, height int) Canvas {
	return new_scaled_canvas(width, height, width, height, 1)
}
*/

fn new_scaled_canvas(width int, height int, physical_width int, physical_height int,
	scale int) Canvas {
	pixels := unsafe { &u32(malloc(physical_width * physical_height * 4)) }
	return Canvas{
		width:           width
		height:          height
		physical_width:  physical_width
		physical_height: physical_height
		scale:           scale
		stride:          physical_width
		pixels:          pixels
		clip:            Clip{
			x: 0
			y: 0
			w: width
			h: height
		}
	}
}

// blend mixes `src` over `dst` at coverage `a` (0..255). The doubled shift is
// the usual approximation of a divide by 255 and is exact at both ends, so a
// fully covered pixel is the source color untouched.
@[inline]
fn blend(dst u32, src u32, a u32) u32 {
	if a == 0 {
		return dst
	}
	if a >= 255 {
		return src
	}
	inv := 255 - a
	rb := (src & 0xff00ff) * a + (dst & 0xff00ff) * inv + 0x800080
	g := (src & 0x00ff00) * a + (dst & 0x00ff00) * inv + 0x008000
	return ((rb + ((rb >> 8) & 0xff00ff)) >> 8) & 0xff00ff | ((g + ((g >> 8) & 0x00ff00)) >> 8) & 0x00ff00
}

// mix interpolates between two opaque colors, for gradients and hover shades.
@[inline]
fn mix(a u32, b u32, t u32) u32 {
	return blend(a, b, t)
}

// corner_coverage is the fraction of a pixel inside a disc of radius `r`
// centred at (cx, cy). Sampling the pixel centre and taking the distance to
// the arc gives a one pixel wide ramp, which is all a small radius needs to
// stop looking like a staircase.
@[inline]
fn corner_coverage(px f64, py f64, cx f64, cy f64, r f64) u32 {
	dx := px - cx
	dy := py - cy
	d := math.sqrt(dx * dx + dy * dy)
	edge := r - d + 0.5
	if edge <= 0 {
		return 0
	}
	if edge >= 1 {
		return 255
	}
	return u32(edge * 255)
}

// ── Clipping ───────────────────────────────────────────────────────

// push_clip_rect narrows the drawable area and returns the previous clip so
// the caller can restore it.
fn (mut c Canvas) push_clip_rect(x int, y int, w int, h int) Clip {
	saved := c.clip
	left := if x > c.clip.x { x } else { c.clip.x }
	top := if y > c.clip.y { y } else { c.clip.y }
	mut right := x + w
	if c.clip.x + c.clip.w < right {
		right = c.clip.x + c.clip.w
	}
	mut bottom := y + h
	if c.clip.y + c.clip.h < bottom {
		bottom = c.clip.y + c.clip.h
	}
	c.clip.x = left
	c.clip.y = top
	c.clip.w = if right > left { right - left } else { 0 }
	c.clip.h = if bottom > top { bottom - top } else { 0 }
	return saved
}

// push_clip_round_rect narrows the area and installs the rounded mask. A
// window sets it once; everything drawn inside then stops at its corners.
fn (mut c Canvas) push_clip_round_rect(x int, y int, w int, h int, radius int) Clip {
	saved := c.push_clip_rect(x, y, w, h)
	if radius > 0 {
		c.clip.mask_x = x
		c.clip.mask_y = y
		c.clip.mask_w = w
		c.clip.mask_h = h
		c.clip.mask_radius = radius
	}
	return saved
}

fn (mut c Canvas) restore_clip(saved Clip) {
	c.clip = saved
}

@[inline]
fn (c &Canvas) clip_coverage(x int, y int) u32 {
	if x < c.clip.x || y < c.clip.y || x >= c.clip.x + c.clip.w || y >= c.clip.y + c.clip.h {
		return 0
	}
	r := c.clip.mask_radius
	if r == 0 {
		return 255
	}
	mut cx := 0
	if x < c.clip.mask_x + r {
		cx = c.clip.mask_x + r
	} else if x >= c.clip.mask_x + c.clip.mask_w - r {
		cx = c.clip.mask_x + c.clip.mask_w - r
	} else {
		return 255
	}
	mut cy := 0
	if y < c.clip.mask_y + r {
		cy = c.clip.mask_y + r
	} else if y >= c.clip.mask_y + c.clip.mask_h - r {
		cy = c.clip.mask_y + c.clip.mask_h - r
	} else {
		return 255
	}
	return corner_coverage(f64(x) + 0.5, f64(y) + 0.5, f64(cx), f64(cy), f64(r))
}

// clip_is_plain reports that a rectangle lies wholly inside the clip and clear
// of any rounded corner, so it can be filled without a per-pixel test.
@[inline]
fn (c &Canvas) clip_is_plain(x int, y int, w int, h int) bool {
	if x < c.clip.x || y < c.clip.y || x + w > c.clip.x + c.clip.w
		|| y + h > c.clip.y + c.clip.h {
		return false
	}
	r := c.clip.mask_radius
	if r == 0 {
		return true
	}
	// Clear of the corners when the span is inside the mask's middle cross.
	inside_columns := x >= c.clip.mask_x + r && x + w <= c.clip.mask_x + c.clip.mask_w - r
	inside_rows := y >= c.clip.mask_y + r && y + h <= c.clip.mask_y + c.clip.mask_h - r
	return inside_columns || inside_rows
}

// ── Primitives ─────────────────────────────────────────────────────

@[inline]
fn (mut c Canvas) blend_pixel(x int, y int, color u32, coverage u32) {
	if coverage == 0 {
		return
	}
	clip := c.clip_coverage(x, y)
	if clip == 0 {
		return
	}
	a := if clip == 255 { coverage } else { coverage * clip / 255 }
	physical_x := x * c.scale
	physical_y := y * c.scale
	for offset_y := 0; offset_y < c.scale && physical_y + offset_y < c.physical_height; offset_y++ {
		row := (physical_y + offset_y) * c.stride
		for offset_x := 0; offset_x < c.scale && physical_x + offset_x < c.physical_width; offset_x++ {
			unsafe {
				idx := row + physical_x + offset_x
				c.pixels[idx] = blend(c.pixels[idx], color, a)
			}
		}
	}
}

// blend_physical_pixel is used by assets that have a native HiDPI raster,
// notably the 2x font atlases. Clips are still declared in logical units, but
// their edges and rounded masks are evaluated on the physical pixel grid.
@[inline]
fn (mut c Canvas) blend_physical_pixel(x int, y int, color u32, coverage u32) {
	if coverage == 0 || x < 0 || y < 0 || x >= c.physical_width || y >= c.physical_height {
		return
	}
	clip_x := c.clip.x * c.scale
	clip_y := c.clip.y * c.scale
	clip_w := c.clip.w * c.scale
	clip_h := c.clip.h * c.scale
	if x < clip_x || y < clip_y || x >= clip_x + clip_w || y >= clip_y + clip_h {
		return
	}

	mut clip := u32(255)
	if c.clip.mask_radius > 0 {
		mask_x := c.clip.mask_x * c.scale
		mask_y := c.clip.mask_y * c.scale
		mask_w := c.clip.mask_w * c.scale
		mask_h := c.clip.mask_h * c.scale
		radius := c.clip.mask_radius * c.scale
		mut center_x := 0
		mut center_y := 0
		mut in_corner := true
		if x < mask_x + radius {
			center_x = mask_x + radius
		} else if x >= mask_x + mask_w - radius {
			center_x = mask_x + mask_w - radius
		} else {
			in_corner = false
		}
		if y < mask_y + radius {
			center_y = mask_y + radius
		} else if y >= mask_y + mask_h - radius {
			center_y = mask_y + mask_h - radius
		} else {
			in_corner = false
		}
		if in_corner {
			clip = corner_coverage(f64(x) + 0.5, f64(y) + 0.5, f64(center_x), f64(center_y), f64(radius))
		}
	}
	if clip == 0 {
		return
	}
	a := if clip == 255 { coverage } else { coverage * clip / 255 }
	unsafe {
		index := y * c.stride + x
		c.pixels[index] = blend(c.pixels[index], color, a)
	}
}

@[inline]
fn (c &Canvas) logical_pixel(x int, y int) u32 {
	return unsafe { c.pixels[y * c.scale * c.stride + x * c.scale] }
}

fn (mut c Canvas) clear(color u32) {
	for i := 0; i < c.stride * c.physical_height; i++ {
		unsafe {
			c.pixels[i] = color
		}
	}
}

// copy_logical_pixels expands a cached logical image onto the backing pixel
// grid. Wallpaper generation therefore stays cheap while the text drawn over
// it can use the full native-resolution canvas.
fn (mut c Canvas) copy_logical_pixels(source []u32) {
	if source.len < c.width * c.height {
		return
	}
	x0 := if c.clip.x > 0 { c.clip.x } else { 0 }
	y0 := if c.clip.y > 0 { c.clip.y } else { 0 }
	x1 := if c.clip.x + c.clip.w < c.width { c.clip.x + c.clip.w } else { c.width }
	y1 := if c.clip.y + c.clip.h < c.height { c.clip.y + c.clip.h } else { c.height }
	if x1 <= x0 || y1 <= y0 {
		return
	}
	if c.scale == 1 && c.width == c.physical_width && c.height == c.physical_height {
		for y := y0; y < y1; y++ {
			unsafe {
				C.memcpy(&c.pixels[y * c.stride + x0], &source[y * c.width + x0], usize((x1 - x0) * 4))
			}
		}
		return
	}
	for y := y0; y < y1; y++ {
		for x := x0; x < x1; x++ {
			color := source[y * c.width + x]
			physical_x := x * c.scale
			physical_y := y * c.scale
			for offset_y := 0; offset_y < c.scale
				&& physical_y + offset_y < c.physical_height; offset_y++ {
				row := (physical_y + offset_y) * c.stride
				for offset_x := 0; offset_x < c.scale
					&& physical_x + offset_x < c.physical_width; offset_x++ {
					unsafe { c.pixels[row + physical_x + offset_x] = color }
				}
			}
		}
	}
}

fn (mut c Canvas) fill_rect(x int, y int, w int, h int, color u32) {
	c.blend_rect(x, y, w, h, color, 255)
}

fn (mut c Canvas) blend_rect(x int, y int, w int, h int, color u32, alpha u32) {
	if w <= 0 || h <= 0 || alpha == 0 {
		return
	}
	x0 := if x > c.clip.x { x } else { c.clip.x }
	y0 := if y > c.clip.y { y } else { c.clip.y }
	mut x1 := x + w
	mut y1 := y + h
	if x1 > c.clip.x + c.clip.w {
		x1 = c.clip.x + c.clip.w
	}
	if y1 > c.clip.y + c.clip.h {
		y1 = c.clip.y + c.clip.h
	}
	if x1 <= x0 || y1 <= y0 {
		return
	}

	if c.clip_is_plain(x0, y0, x1 - x0, y1 - y0) {
		physical_x0 := x0 * c.scale
		physical_y0 := y0 * c.scale
		physical_x1 := if x1 * c.scale < c.physical_width { x1 * c.scale } else { c.physical_width }
		physical_y1 := if y1 * c.scale < c.physical_height {
			y1 * c.scale
		} else {
			c.physical_height
		}
		if alpha >= 255 {
			for py := physical_y0; py < physical_y1; py++ {
				row := py * c.stride
				for px := physical_x0; px < physical_x1; px++ {
					unsafe {
						c.pixels[row + px] = color
					}
				}
			}
		} else {
			for py := physical_y0; py < physical_y1; py++ {
				row := py * c.stride
				for px := physical_x0; px < physical_x1; px++ {
					unsafe {
						c.pixels[row + px] = blend(c.pixels[row + px], color, alpha)
					}
				}
			}
		}
		return
	}

	for py := y0; py < y1; py++ {
		for px := x0; px < x1; px++ {
			c.blend_pixel(px, py, color, alpha)
		}
	}
}

// vertical_gradient paints the wallpaper. The interpolation is per scanline,
// so the cost is one blend per row rather than per pixel.
fn (mut c Canvas) vertical_gradient(x int, y int, w int, h int, top u32, bottom u32) {
	if h <= 0 {
		return
	}
	for row := 0; row < h; row++ {
		c.fill_rect(x, y + row, w, 1, mix(top, bottom, u32(row * 255 / h)))
	}
}

// vertical_gradient_inclusive reaches both declared colours. Window chrome
// needs that exact contract because its first and last gradient rows were
// measured independently; wallpaper gradients use the half-open variant
// above so adjacent tiles would not repeat an endpoint.
fn (mut c Canvas) vertical_gradient_inclusive(x int, y int, w int, h int, top u32, bottom u32) {
	if h <= 0 {
		return
	}
	if h == 1 {
		c.fill_rect(x, y, w, 1, top)
		return
	}
	for row := 0; row < h; row++ {
		c.fill_rect(x, y + row, w, 1, mix(top, bottom, u32(row * 255 / (h - 1))))
	}
}

// fill_native_vertical_palette_round_rect draws a small control at the backing
// store's physical resolution. `rows` describes the measured 1x scanlines;
// denser displays interpolate between them instead of enlarging every source
// pixel into a square scale-by-scale block. This is the same reason the title
// bar's traffic lights have a native-resolution path below.
fn (mut c Canvas) fill_native_vertical_palette_round_rect(x int, y int, w int, h int,
	radius int, rows []u32) {
	if w <= 0 || h <= 0 || rows.len == 0 || c.scale <= 0 {
		return
	}
	physical_x := x * c.scale
	physical_y := y * c.scale
	physical_w := w * c.scale
	physical_h := h * c.scale
	mut physical_radius := radius * c.scale
	half := if physical_w < physical_h { physical_w / 2 } else { physical_h / 2 }
	if physical_radius > half {
		physical_radius = half
	}

	for offset_y := 0; offset_y < physical_h; offset_y++ {
		mut color := rows[0]
		if rows.len > 1 && physical_h > 1 {
			position := offset_y * (rows.len - 1)
			index := position / (physical_h - 1)
			if index >= rows.len - 1 {
				color = rows[rows.len - 1]
			} else {
				remainder := position % (physical_h - 1)
				color = mix(rows[index], rows[index + 1], u32(remainder * 255 / (physical_h - 1)))
			}
		}
		for offset_x := 0; offset_x < physical_w; offset_x++ {
			mut coverage := u32(255)
			if physical_radius > 0 {
				mut center_x := 0
				mut center_y := 0
				mut in_corner := true
				if offset_x < physical_radius {
					center_x = physical_radius
				} else if offset_x >= physical_w - physical_radius {
					center_x = physical_w - physical_radius
				} else {
					in_corner = false
				}
				if offset_y < physical_radius {
					center_y = physical_radius
				} else if offset_y >= physical_h - physical_radius {
					center_y = physical_h - physical_radius
				} else {
					in_corner = false
				}
				if in_corner {
					coverage = corner_coverage(f64(offset_x) + 0.5, f64(offset_y) + 0.5,
						f64(center_x), f64(center_y), f64(physical_radius))
				}
			}
			c.blend_physical_pixel(physical_x + offset_x, physical_y + offset_y, color,
				coverage)
		}
	}
}

// fill_round_rect draws the body as plain spans and only pays for coverage
// inside the four corner squares.
fn (mut c Canvas) fill_round_rect(x int, y int, w int, h int, radius int, color u32) {
	c.blend_round_rect(x, y, w, h, radius, color, 255)
}

fn (mut c Canvas) blend_round_rect(x int, y int, w int, h int, radius int, color u32, alpha u32) {
	if w <= 0 || h <= 0 || alpha == 0 {
		return
	}
	mut r := radius
	half := if w < h { w / 2 } else { h / 2 }
	if r > half {
		r = half
	}
	if r <= 0 {
		c.blend_rect(x, y, w, h, color, alpha)
		return
	}

	c.blend_rect(x, y + r, w, h - 2 * r, color, alpha) // middle band
	c.blend_rect(x + r, y, w - 2 * r, r, color, alpha) // top band
	c.blend_rect(x + r, y + h - r, w - 2 * r, r, color, alpha) // bottom band

	rf := f64(r)
	for cy := 0; cy < r; cy++ {
		for cx := 0; cx < r; cx++ {
			coverage := corner_coverage(f64(cx) + 0.5, f64(cy) + 0.5, rf, rf, rf)
			if coverage == 0 {
				continue
			}
			a := if alpha >= 255 { coverage } else { coverage * alpha / 255 }
			c.blend_pixel(x + cx, y + cy, color, a)
			c.blend_pixel(x + w - 1 - cx, y + cy, color, a)
			c.blend_pixel(x + cx, y + h - 1 - cy, color, a)
			c.blend_pixel(x + w - 1 - cx, y + h - 1 - cy, color, a)
		}
	}
}

// stroke_round_rect outlines a shape with a one pixel edge, taking the ring
// between two coverages so the corners are antialiased like the fill's.
fn (mut c Canvas) stroke_round_rect(x int, y int, w int, h int, radius int, color u32, alpha u32) {
	if w <= 0 || h <= 0 {
		return
	}
	c.blend_rect(x + radius, y, w - 2 * radius, 1, color, alpha)
	c.blend_rect(x + radius, y + h - 1, w - 2 * radius, 1, color, alpha)
	c.blend_rect(x, y + radius, 1, h - 2 * radius, color, alpha)
	c.blend_rect(x + w - 1, y + radius, 1, h - 2 * radius, color, alpha)

	if radius <= 0 {
		return
	}
	rf := f64(radius)
	for cy := 0; cy < radius; cy++ {
		for cx := 0; cx < radius; cx++ {
			px := f64(cx) + 0.5
			py := f64(cy) + 0.5
			outer := corner_coverage(px, py, rf, rf, rf)
			inner := corner_coverage(px, py, rf, rf, rf - 1.0)
			if outer <= inner {
				continue
			}
			a := (outer - inner) * alpha / 255
			c.blend_pixel(x + cx, y + cy, color, a)
			c.blend_pixel(x + w - 1 - cx, y + cy, color, a)
			c.blend_pixel(x + cx, y + h - 1 - cy, color, a)
			c.blend_pixel(x + w - 1 - cx, y + h - 1 - cy, color, a)
		}
	}
}

// fill_stroke_hidpi_circle draws the small circular controls directly on the
// native pixel grid.  Most chrome is deliberately made from logical pixels so
// its dimensions remain stable at either display scale.  A 12-point traffic
// light is different: expanding its 1x edge into 2x2 blocks makes the curve
// visibly stepped on a HiDPI panel.  Sampling every physical pixel keeps the
// same logical diameter while giving the disc and its ring a proper smooth
// edge.
fn (mut c Canvas) fill_stroke_hidpi_circle(x int, y int, w int, h int, border_width int, fill u32, edge u32) {
	if c.scale <= 1 || w <= 0 || h <= 0 {
		return
	}
	diameter := if w < h { w } else { h }
	physical_diameter := diameter * c.scale
	if physical_diameter <= 0 {
		return
	}
	center_x := x * c.scale + w * c.scale / 2
	center_y := y * c.scale + h * c.scale / 2
	radius := f64(physical_diameter) / 2
	inner_radius := radius - f64(border_width * c.scale)
	left := center_x - physical_diameter / 2
	top := center_y - physical_diameter / 2

	for py := top; py < top + physical_diameter; py++ {
		for px := left; px < left + physical_diameter; px++ {
			outer := corner_coverage(f64(px) + 0.5, f64(py) + 0.5, f64(center_x), f64(center_y), radius)
			if outer == 0 {
				continue
			}
			c.blend_physical_pixel(px, py, fill, outer)
			if inner_radius > 0 {
				inner := corner_coverage(f64(px) + 0.5, f64(py) + 0.5, f64(center_x), f64(center_y), inner_radius)
				if outer > inner {
					c.blend_physical_pixel(px, py, edge, outer - inner)
				}
			}
		}
	}
}

// drop_shadow stacks a few translucent rounded rects behind a window.
// Layering cheap shapes reads as a soft edge without the cost of a real blur.
fn (mut c Canvas) drop_shadow(x int, y int, w int, h int, radius int, spread int, alpha u32) {
	for i := spread; i >= 1; i-- {
		layer := alpha * u32(spread - i + 1) / u32(spread * 3)
		c.blend_round_rect(x - i, y - i + 2, w + 2 * i, h + 2 * i, radius + i, 0x000000, layer)
	}
}

fn (mut c Canvas) fill_circle(cx int, cy int, radius int, color u32) {
	rf := f64(radius)
	for dy := -radius; dy <= radius; dy++ {
		for dx := -radius; dx <= radius; dx++ {
			c.blend_pixel(cx + dx, cy + dy, color, corner_coverage(f64(dx), f64(dy), 0, 0, rf))
		}
	}
}

// draw_line is only ever asked for the short strokes inside a title bar
// glyph, so a plain DDA with a square pen is enough.
fn (mut c Canvas) draw_line(x0 int, y0 int, x1 int, y1 int, color u32, thickness int) {
	dx := x1 - x0
	dy := y1 - y0
	steps := if abs_int(dx) > abs_int(dy) { abs_int(dx) } else { abs_int(dy) }
	if steps == 0 {
		c.fill_rect(x0, y0, thickness, thickness, color)
		return
	}
	for i := 0; i <= steps; i++ {
		c.fill_rect(x0 + dx * i / steps, y0 + dy * i / steps, thickness, thickness, color)
	}
}

@[inline]
fn abs_int(v int) int {
	return if v < 0 { -v } else { v }
}
