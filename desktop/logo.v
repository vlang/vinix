// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The Vinix wordmark, painted in the middle of a colour wallpaper.
//
// The repository's vinix-logo.svg is five shapes on a 200 x 61.9 canvas:
// three polygons and two rectangles, with no curves, no strokes and no
// transforms. That is little
// enough to carry here as its own points, which is the whole of an SVG parser
// the desktop would otherwise use exactly once and then have to defend against
// every file that is not this one. The rectangles are written out as their
// four corners, so there is a single kind of shape to fill.
//
// The mark only goes on the colour wallpapers. A photograph already has a
// subject, and stamping a logo over it would be someone else's picture with
// our name on it.
module main

// The SVG's viewBox. The glyphs sit symmetrically inside it — 6.7 of margin at
// both sides, 10.1 above and below — so centring the box centres the mark.
const logo_view_width = 200.0
const logo_view_height = 61.9

// Points as x, y pairs, in viewBox units, straight from vinix-logo.svg.
const logo_shapes = [
	// V
	[45.4, 10.1, 26.3, 51.8, 6.7, 10.1, 16.8, 10.1, 26.3, 31.3, 35.9, 10.1],
	// I
	[57.4, 10.1, 66.9, 10.1, 66.9, 51.8, 57.4, 51.8],
	// N
	[107.8, 10.1, 107.8, 30.9, 84.5, 10.1, 84.5, 51.8, 94.0, 51.8, 94.0, 31.0, 117.3, 51.8, 117.3,
		10.1],
	// I
	[134.9, 10.1, 144.4, 10.1, 144.4, 51.8, 134.9, 51.8],
	// X
	[182.7, 51.8, 175.4, 38.6, 166.9, 51.8, 156.8, 51.8, 169.7, 30.0, 157.7, 10.1, 168.3, 10.1,
		175.4, 21.9, 182.4, 10.1, 192.4, 10.1, 180.4, 30.1, 193.3, 51.8],
]

const logo_color = u32(0xffffff)

// The V is also used as the Start-button glyph. Keep its bounds in the
// wordmark's coordinate space so that glyph is the actual first letter, not a
// similar-looking character or a separately maintained drawing.
const logo_v_left = 6.7
const logo_v_top = 10.1
const logo_v_right = 45.4
const logo_v_bottom = 51.8
const logo_v_subsamples = 4

// A quarter of the screen across, and never taller than a fifth of it, so the
// mark keeps its proportions on a framebuffer of any shape.
const logo_width_fraction = 4.0
const logo_height_fraction = 5.0

// Coverage is accumulated per pixel at 1024 for fully painted, which leaves
// room for the four sub-scanlines to add up without rounding away.
const logo_subsamples = 4
const logo_coverage_full = u32(1024)
const logo_subsample_weight = 256.0

struct LogoCrossing {
	x       f64
	winding int
}

// draw_logo paints the wordmark into the middle of a screen-sized buffer. It
// goes into the cached wallpaper rather than onto the canvas: the mark never
// moves, so it is rasterised with the backdrop and blitted with it after.
fn draw_logo(mut pixels []u32, width int, height int, color u32) {
	if width <= 0 || height <= 0 {
		return
	}
	mut scale := f64(width) / logo_width_fraction / logo_view_width
	fit_height := f64(height) / logo_height_fraction / logo_view_height
	if scale > fit_height {
		scale = fit_height
	}
	// One pixel of slack on each axis: an edge that lands mid-pixel still has
	// a pixel to be antialiased into.
	box_w := int(logo_view_width * scale) + 2
	box_h := int(logo_view_height * scale) + 2
	if box_w < 8 || box_h < 8 || box_w > width || box_h > height {
		return
	}
	origin_x := (width - box_w) / 2
	origin_y := (height - box_h) / 2

	// The shapes are rasterised into a mask first, so a pixel two of them share
	// an edge on is blended once and does not come out darker than the rest.
	mut coverage := []u16{len: box_w * box_h}
	for shape in logo_shapes {
		accumulate_polygon(shape, scale, mut coverage, box_w, box_h)
	}

	for y in 0 .. box_h {
		row := y * box_w
		out_row := (origin_y + y) * width + origin_x
		for x in 0 .. box_w {
			cov := u32(coverage[row + x])
			if cov == 0 {
				continue
			}
			alpha := if cov >= logo_coverage_full {
				u32(255)
			} else {
				cov * 255 / logo_coverage_full
			}
			pixels[out_row + x] = blend(pixels[out_row + x], color, alpha)
		}
	}
	unsafe { coverage.free() }
}

// draw_vinix_v paints the V polygon from vinix-logo.svg into an icon-sized
// rectangle. The Start button is small enough that drawing it as two thick
// lines changes its taper and central notch noticeably, so sample the source
// polygon directly instead. This is only a few dozen pixels and is drawn at
// most twice per frame (the taskbar and an open Start menu).
fn (mut c Canvas) draw_vinix_v(x int, y int, width int, height int, color u32) {
	if width <= 0 || height <= 0 {
		return
	}
	inset := if width < height { width / 8 } else { height / 8 }
	available_width := width - 2 * inset
	available_height := height - 2 * inset
	if available_width <= 0 || available_height <= 0 {
		return
	}
	mut scale := f64(available_width) / (logo_v_right - logo_v_left)
	height_scale := f64(available_height) / (logo_v_bottom - logo_v_top)
	if scale > height_scale {
		scale = height_scale
	}
	if scale <= 0 {
		return
	}
	glyph_width := (logo_v_right - logo_v_left) * scale
	glyph_height := (logo_v_bottom - logo_v_top) * scale
	origin_x := f64(x) + (f64(width) - glyph_width) / 2 - logo_v_left * scale
	origin_y := f64(y) + (f64(height) - glyph_height) / 2 - logo_v_top * scale

	for py in y .. y + height {
		for px in x .. x + width {
			mut covered := 0
			for sample_y in 0 .. logo_v_subsamples {
				for sample_x in 0 .. logo_v_subsamples {
					shape_x := (f64(px) + (f64(sample_x) + 0.5) / logo_v_subsamples - origin_x) / scale
					shape_y := (f64(py) + (f64(sample_y) + 0.5) / logo_v_subsamples - origin_y) / scale
					if vinix_v_contains(shape_x, shape_y) {
						covered++
					}
				}
			}
			if covered > 0 {
				c.blend_pixel(px, py, color, u32(covered * 255 / (logo_v_subsamples * logo_v_subsamples)))
			}
		}
	}
}

// vinix_v_contains uses the usual even-odd polygon rule. logo_shapes[0] is
// the V's untouched SVG point list, shared with draw_logo above.
fn vinix_v_contains(x f64, y f64) bool {
	points := logo_shapes[0]
	mut inside := false
	for i in 0 .. points.len / 2 {
		j := if i == 0 { points.len / 2 - 1 } else { i - 1 }
		x0 := points[i * 2]
		y0 := points[i * 2 + 1]
		x1 := points[j * 2]
		y1 := points[j * 2 + 1]
		if (y0 > y) != (y1 > y) && x < (x1 - x0) * (y - y0) / (y1 - y0) + x0 {
			inside = !inside
		}
	}
	return inside
}

// accumulate_polygon adds one shape to the mask. Every pixel row is sampled at
// four heights, and the edge crossings on each are paired by winding number,
// which is the rule the SVG is drawn under. Horizontal coverage is exact, so
// a diagonal — and this wordmark is mostly diagonals — comes out smooth along
// its length rather than only across it.
fn accumulate_polygon(points []f64, scale f64, mut coverage []u16, box_w int, box_h int) {
	count := points.len / 2
	if count < 3 {
		return
	}
	mut crossings := []LogoCrossing{cap: count}
	for y in 0 .. box_h {
		row := y * box_w
		for sub in 0 .. logo_subsamples {
			sample_y := f64(y) + (f64(sub) + 0.5) / logo_subsamples
			crossings.clear()
			for i in 0 .. count {
				j := (i + 1) % count
				y0 := points[i * 2 + 1] * scale
				y1 := points[j * 2 + 1] * scale
				// A horizontal edge crosses nothing; the half-open test below
				// counts a shared vertex once, so spans do not double up.
				if y0 == y1 {
					continue
				}
				if (sample_y < y0 && sample_y < y1) || (sample_y >= y0 && sample_y >= y1) {
					continue
				}
				x0 := points[i * 2] * scale
				x1 := points[j * 2] * scale
				crossings << LogoCrossing{
					x: x0 + (sample_y - y0) * (x1 - x0) / (y1 - y0)
					winding: if y1 > y0 { 1 } else { -1 }
				}
			}
			if crossings.len < 2 {
				continue
			}
			crossings.sort(a.x < b.x)
			mut winding := 0
			for i in 0 .. crossings.len - 1 {
				winding += crossings[i].winding
				if winding == 0 {
					continue
				}
				add_span(mut coverage, row, box_w, crossings[i].x, crossings[i + 1].x)
			}
		}
	}
	unsafe { crossings.free() }
}

// add_span accumulates one sub-scanline's worth of a horizontal run. Whole
// pixels take a full share of it; the two ends take the fraction they are
// actually covered by.
fn add_span(mut coverage []u16, row int, box_w int, from f64, to f64) {
	mut x0 := from
	mut x1 := to
	if x1 <= x0 || x1 <= 0 || x0 >= f64(box_w) {
		return
	}
	if x0 < 0 {
		x0 = 0
	}
	if x1 > f64(box_w) {
		x1 = f64(box_w)
	}
	first := int(x0)
	last := int(x1)
	if first == last {
		add_coverage(mut coverage, row + first, logo_subsample_weight * (x1 - x0))
		return
	}
	add_coverage(mut coverage, row + first, logo_subsample_weight * (f64(first + 1) - x0))
	for px in first + 1 .. last {
		add_coverage(mut coverage, row + px, logo_subsample_weight)
	}
	// int(x1) is past the last pixel when the run ends exactly on the edge of
	// the mask.
	if last < box_w {
		add_coverage(mut coverage, row + last, logo_subsample_weight * (x1 - f64(last)))
	}
}

@[inline]
fn add_coverage(mut coverage []u16, index int, amount f64) {
	sum := u32(coverage[index]) + u32(amount)
	coverage[index] = if sum > logo_coverage_full {
		u16(logo_coverage_full)
	} else {
		u16(sum)
	}
}
