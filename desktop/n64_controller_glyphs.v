// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// A compact front view preserves the controller's three separate grips and
// button positions. Applications overlay their hit targets on this 360×224
// coordinate system; the silhouette itself is decorative and never clickable.
// Fixed arrays keep the repeated paint path free of heap allocations.
const n64_shell_x = [180, 141, 130, 123, 88, 60, 39, 22, 13, 8, 4, 5, 10, 18,
	29, 41, 48, 54, 62, 71, 83, 102, 119, 129, 136, 145, 158, 171, 189, 202,
	215, 224, 231, 241, 258, 277, 289, 298, 306, 312, 319, 331, 342, 350,
	355, 356, 352, 347, 338, 321, 300, 272, 237, 230, 219]!
const n64_shell_y = [5, 5, 7, 16, 18, 23, 34, 50, 69, 93, 127, 153, 180, 193,
	199, 197, 188, 167, 145, 133, 131, 132, 139, 151, 177, 205, 219, 224, 224, 219,
	205, 177, 151, 139, 132, 131, 133, 145, 167, 188, 197, 199, 193, 180,
	153, 127, 93, 69, 50, 34, 23, 18, 16, 7, 5]!

enum N64ControllerGlyph {
	stick
	c_up
	c_down
	c_left
	c_right
}

@[inline]
fn n64_curve_crosses_row(parameter f64, quadratic f64, linear f64) bool {
	return (parameter > 0 && parameter < 1) || (parameter == 0 && linear > 0)
		|| (parameter == 1 && 2 * quadratic + linear < 0)
}

// The concave outline can cross a scanline at most six times: once around
// each grip. A quadratic rounds each corner within its adjacent edge quarters;
// solving those curves per row keeps the molded silhouette smooth at HiDPI
// without flattening it into heap-backed points on every paint.
fn n64_shell_intersections(y f64, mut intersections [6]f64) int {
	mut count := 0
	for index in 0 .. n64_shell_x.len {
		previous := if index == 0 { n64_shell_x.len - 1 } else { index - 1 }
		next := if index + 1 == n64_shell_x.len { 0 } else { index + 1 }
		cx := f64(n64_shell_x[index])
		cy := f64(n64_shell_y[index])
		ax := (f64(n64_shell_x[previous]) + cx * 3) / 4
		ay := (f64(n64_shell_y[previous]) + cy * 3) / 4
		bx := (f64(n64_shell_x[next]) + cx * 3) / 4
		by := (f64(n64_shell_y[next]) + cy * 3) / 4
		// The straight middle half joins the previous rounded corner to
		// this one. Half-open intervals count shared vertices only once.
		join_x := (f64(n64_shell_x[previous]) * 3 + cx) / 4
		join_y := (f64(n64_shell_y[previous]) * 3 + cy) / 4
		if (join_y <= y && ay > y) || (ay <= y && join_y > y) {
			intersections[count] = join_x + (y - join_y) * (ax - join_x) / (ay - join_y)
			count++
		}
		quadratic := ay - 2 * cy + by
		linear := 2 * (cy - ay)
		constant := ay - y
		if quadratic == 0 {
			if linear == 0 { continue }
			parameter := -constant / linear
			if n64_curve_crosses_row(parameter, quadratic, linear) {
				inverse := 1 - parameter
				intersections[count] = inverse * inverse * ax +
					2 * inverse * parameter * cx + parameter * parameter * bx
				count++
			}
		} else {
			discriminant := linear * linear - 4 * quadratic * constant
			if discriminant < 0 { continue }
			root := math.sqrt(discriminant)
			for parameter in [(-linear - root) / (2 * quadratic),
				(-linear + root) / (2 * quadratic)]! {
				if n64_curve_crosses_row(parameter, quadratic, linear) {
					inverse := 1 - parameter
					intersections[count] = inverse * inverse * ax +
						2 * inverse * parameter * cx + parameter * parameter * bx
					count++
				}
			}
		}
	}
	for index in 1 .. count {
		value := intersections[index]
		mut before := index
		for before > 0 && intersections[before - 1] > value {
			intersections[before] = intersections[before - 1]
			before--
		}
		intersections[before] = value
	}
	return count
}

fn (mut d Desktop) draw_n64_controller_body(x int, y int, w int, h int, color u32) {
	if w <= 0 || h <= 0 || d.canvas.scale <= 0 { return }
	scale := d.canvas.scale
	left := x * scale
	top := y * scale
	unit_x := f64(w * scale) / 360
	unit_y := f64(h * scale) / 224
	mut first_x := left
	mut last_x := left + w * scale
	mut first_y := top
	mut last_y := top + h * scale
	if first_x < d.canvas.clip.x * scale { first_x = d.canvas.clip.x * scale }
	if first_y < d.canvas.clip.y * scale { first_y = d.canvas.clip.y * scale }
	if last_x > (d.canvas.clip.x + d.canvas.clip.w) * scale {
		last_x = (d.canvas.clip.x + d.canvas.clip.w) * scale
	}
	if last_y > (d.canvas.clip.y + d.canvas.clip.h) * scale {
		last_y = (d.canvas.clip.y + d.canvas.clip.h) * scale
	}
	if first_x < 0 { first_x = 0 }
	if first_y < 0 { first_y = 0 }
	if last_x > d.canvas.physical_width { last_x = d.canvas.physical_width }
	if last_y > d.canvas.physical_height { last_y = d.canvas.physical_height }
	if first_x >= last_x || first_y >= last_y { return }
	for py in first_y .. last_y {
		mut spans := [4][6]f64{}
		mut counts := [4]int{}
		for sample in 0 .. 4 {
			sy := (f64(py - top) + (f64(sample) + 0.5) / 4) / unit_y
			counts[sample] = n64_shell_intersections(sy, mut spans[sample])
			for index in 0 .. counts[sample] {
				spans[sample][index] = f64(left) + spans[sample][index] * unit_x
			}
		}
		sy := (f64(py - top) + 0.5) / unit_y
		for px in first_x .. last_x {
			mut coverage := f64(0)
			mut nearest_side := f64(360)
			for sample in 0 .. 4 {
				for pair := 0; pair + 1 < counts[sample]; pair += 2 {
					span_left := spans[sample][pair]
					span_right := spans[sample][pair + 1]
					pixel_left := if f64(px) > span_left { f64(px) } else { span_left }
					pixel_right := if f64(px + 1) < span_right { f64(px + 1) } else { span_right }
					if pixel_right > pixel_left {
						coverage += (pixel_right - pixel_left) / 4
						center := f64(px) + 0.5
						near := if center - span_left < span_right - center {
							center - span_left
						} else { span_right - center }
						if near < nearest_side { nearest_side = near }
					}
				}
			}
			if coverage <= 0 { continue }
			sx := (f64(px - left) + 0.5) / unit_x
			// A restrained molded-plastic gradient keeps the real button
			// colours legible against the shell without looking metallic.
			mut fill := if sy < 130 {
				blend(color, 0xffffff, u32(28 - sy * 0.12))
			} else { blend(color, 0x343c49, u32((sy - 130) * 0.55)) }
			if nearest_side < unit_x * 1.1 {
				fill = blend(fill, 0x343c49, 105)
			}
			// The analog stick sits in the original dark circular well and
			// octagonal gate. Its movable cap is a separate overlaid glyph.
			dx := sx - 180
			dy := sy - 129
			well := math.sqrt(dx * dx + dy * dy)
			if well < 40 {
				fill = if well > 38.5 { u32(0xc3c8ce) } else { u32(0x48515e) }
				gate := math.max(math.max(math.abs(dx), math.abs(dy)),
					(math.abs(dx) + math.abs(dy)) * 0.707106781)
				if gate < 23 {
					fill = if gate > 21.5 { u32(0x303944) } else { u32(0x636d79) }
				}
			}
			d.canvas.blend_physical_pixel(px, py, fill, u32(coverage * 255))
		}
	}
}

fn (mut d Desktop) draw_n64_controller_glyph(name string, x int, y int, w int, h int,
	color u32) bool {
	if name == 'n64_body' {
		d.draw_n64_controller_body(x, y, w, h, color)
		return true
	}
	glyph := match name {
		'n64_stick' { N64ControllerGlyph.stick }
		'n64_c_up' { N64ControllerGlyph.c_up }
		'n64_c_down' { N64ControllerGlyph.c_down }
		'n64_c_left' { N64ControllerGlyph.c_left }
		'n64_c_right' { N64ControllerGlyph.c_right }
		else { return false }
	}
	size := if w < h { w } else { h }
	if size <= 0 || d.canvas.scale <= 0 { return true }
	scale := f64(d.canvas.scale)
	unit := f64(size) * scale / 24
	center_x := (f64(x) + f64(w) / 2) * scale
	center_y := (f64(y) + f64(h) / 2) * scale
	left := int(center_x - f64(size) * scale / 2)
	top := int(center_y - f64(size) * scale / 2)
	for py in top .. top + size * d.canvas.scale {
		for px in left .. left + size * d.canvas.scale {
			sx := (f64(px) + 0.5 - center_x) / unit
			sy := (f64(py) + 0.5 - center_y) / unit
			mut fill := color
			mut edge := f64(0)
			match glyph {
				.stick {
					radius := math.sqrt(sx * sx + sy * sy)
					edge = radius - 9.5
					fill = blend(color, 0xffffff, u32(38 - sy * 2))
					if radius > 8.3 {
						fill = blend(color, 0x343c49, 80)
					} else if radius < 1.1 || math.abs(radius - 3.2) < 0.32
						|| math.abs(radius - 5.4) < 0.32 || math.abs(radius - 7.4) < 0.32 {
						fill = blend(color, 0x343c49, 52)
					}
				}
				.c_up { edge = controller_triangle_edge(sx, sy, 0, -6.5, 6, 4, -6, 4) }
				.c_down { edge = controller_triangle_edge(sx, sy, 0, 6.5, -6, -4, 6, -4) }
				.c_left { edge = controller_triangle_edge(sx, sy, -6.5, 0, 4, -6, 4, 6) }
				.c_right { edge = controller_triangle_edge(sx, sy, 6.5, 0, -4, 6, -4, -6) }
			}
			physical_edge := edge * unit
			if physical_edge < 0.5 {
				coverage := if physical_edge <= -0.5 { u32(255) }
					else { u32((0.5 - physical_edge) * 255) }
				d.canvas.blend_physical_pixel(px, py, fill, coverage)
			}
		}
	}
	return true
}
