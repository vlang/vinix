// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Controller symbols are geometry rather than font characters, so their
// shapes and transparent centres survive both the small toolbar size and
// HiDPI scaling. The application supplies each symbol's controller colour.
module main

import math

enum ControllerGlyph {
	cross
	circle
	square
	triangle
	select
	start
	pause
	reset
}

// Signed distance to the triangle's nearest edge, negative inside. This
// keeps a filled Start/arrowhead and an outlined Triangle on the same crisp
// pixel coverage path without allocating a polygon or repainting its centre.
@[inline]
fn controller_triangle_edge(px f64, py f64, ax f64, ay f64, bx f64, by f64, cx f64, cy f64) f64 {
	ab := (bx - ax) * (py - ay) - (by - ay) * (px - ax)
	bc := (cx - bx) * (py - by) - (cy - by) * (px - bx)
	ca := (ax - cx) * (py - cy) - (ay - cy) * (px - cx)
	inside := (ab >= 0 && bc >= 0 && ca >= 0) || (ab <= 0 && bc <= 0 && ca <= 0)
	mut distance := distance_to_segment(px, py, ax, ay, bx, by)
	for edge in [distance_to_segment(px, py, bx, by, cx, cy),
		distance_to_segment(px, py, cx, cy, ax, ay)]! {
		if edge < distance { distance = edge }
	}
	return if inside { -distance } else { distance }
}

fn (mut d Desktop) draw_controller_glyph(name string, x int, y int, w int, h int, color u32) bool {
	glyph := match name {
		'ps_cross' { ControllerGlyph.cross }
		'ps_circle' { ControllerGlyph.circle }
		'ps_square' { ControllerGlyph.square }
		'ps_triangle' { ControllerGlyph.triangle }
		'ps_select' { ControllerGlyph.select }
		'ps_start' { ControllerGlyph.start }
		'ps_pause' { ControllerGlyph.pause }
		'ps_reset' { ControllerGlyph.reset }
		else { return false }
	}
	size := if w < h { w } else { h }
	if size <= 0 || d.canvas.scale <= 0 { return true }
	// A 24-unit drawing retains the same proportions in an icon beside text
	// and on a round face button. Sample the physical grid so Retina edges do
	// not become enlarged logical pixels.
	physical_scale := f64(d.canvas.scale)
	unit := f64(size) * physical_scale / 24
	center_x := (f64(x) + f64(w) / 2) * physical_scale
	center_y := (f64(y) + f64(h) / 2) * physical_scale
	left := int(center_x - f64(size) * physical_scale / 2)
	top := int(center_y - f64(size) * physical_scale / 2)
	physical_size := size * d.canvas.scale
	for py in top .. top + physical_size {
		for px in left .. left + physical_size {
			sx := (f64(px) + 0.5 - center_x) / unit
			sy := (f64(py) + 0.5 - center_y) / unit
			mut edge := f64(0)
			match glyph {
				.cross {
					first := distance_to_segment(sx, sy, -7, -7, 7, 7)
					second := distance_to_segment(sx, sy, -7, 7, 7, -7)
					edge = (if first < second { first } else { second }) - 1
				}
				.circle {
					edge = math.abs(math.sqrt(sx * sx + sy * sy) - 8) - 1
				}
				.square {
					outer := if math.abs(sx) > math.abs(sy) { math.abs(sx) } else { math.abs(sy) }
					edge = math.abs(outer - 7.5) - 1
				}
				.triangle {
					edge = math.abs(controller_triangle_edge(sx, sy, 0, -8, 8, 7, -8, 7)) - 1
				}
				.select {
					dx := math.abs(sx) - 8
					dy := math.abs(sy) - 3
					edge = if dx > dy { dx } else { dy }
				}
				.start {
					edge = controller_triangle_edge(sx, sy, -6, -8, 8, 0, -6, 8)
				}
				.pause {
					dx := math.abs(math.abs(sx) - 5) - 2
					dy := math.abs(sy) - 8
					edge = if dx > dy { dx } else { dy }
				}
				.reset {
					// A clockwise arc with an open upper-right quarter and a
					// solid arrowhead at its leading end.
					edge = if sx > 0 && sy < -3 {
						f64(24)
					} else {
						math.abs(math.sqrt(sx * sx + sy * sy) - 7) - 1
					}
					arrow := controller_triangle_edge(sx, sy, 1, -5, 7, -9, 9, -1)
					if arrow < edge { edge = arrow }
				}
			}
			physical_edge := edge * unit
			if physical_edge < 0.5 {
				coverage := if physical_edge <= -0.5 {
					u32(255)
				} else {
					u32((0.5 - physical_edge) * 255)
				}
				d.canvas.blend_physical_pixel(px, py, color, coverage)
			}
		}
	}
	return true
}
