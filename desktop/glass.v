// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Aero glass, for the Windows 7 theme.
//
// A glass surface -- a window's frame, the taskbar -- shows what is behind it,
// blurred and tinted. The canvas is one back buffer painted back to front, so
// when a surface is reached the pixels under it are exactly what is behind it:
// they are averaged into quarter-resolution cells, the cells are blurred, and
// the surface is painted from them through Windows 7's colourisation.
//
// The cells are kept from frame to frame, because a partial frame only
// repaints its clip and the pixels outside it already hold glass, windows and
// the pointer: a blur taken from them would show the glass through itself.
// Each surface therefore remembers its backdrop, and a partial frame only
// refreshes the cells that lie wholly inside its clip. Cells sit on a grid
// fixed to the screen and damage is aligned to it (FrameDamage.align), so no
// cell is ever half repainted. When refreshed cells change the blur outside
// the clip, that fringe is repainted by the next frame.
module main

import ui2

// One cell is this many logical pixels on a side.
const glass_cell = 4
// Three box blurs of this radius, in cells, are close to a Gaussian whose
// reach is what Windows 7's glass has: an edge behind it smears over about 25
// pixels.
const glass_blur_radius = 2
const glass_blur_passes = 3
// How far outside a surface the picture still shows in its glass: the blur's
// reach, a cell for the interpolation between cells and one for the grid.
const glass_reach = (glass_blur_passes * glass_blur_radius + 2) * glass_cell
// Surfaces whose backdrops are remembered. One more than this on the screen
// at once is painted as flat glass over an even grey.
const glass_slot_count = 32
const glass_spare_cell = u32(0x8a9098)

// The reflection is diagonal bands of light fixed to the screen, repeating
// across this many pixels.
const glass_streak_period = 640
// Each band's centre, half-width and strength.
const glass_streak_bands = [60, 40, 15, 150, 18, 9, 262, 70, 17, 392, 26, 8, 470, 12, 6, 566, 50,
	13]!

// GlassBackdrop is the picture behind one surface, as cells.
struct GlassBackdrop {
mut:
	key u64
	// The surface the cells were taken for and the part of it something
	// opaque covers (a window's body), which needs no backdrop.
	sx    int
	sy    int
	sw    int
	sh    int
	hx    int
	hy    int
	hw    int
	hh    int
	scale int
	// The cells' own rectangle, on the screen's grid.
	x    int
	y    int
	cols int
	rows int
	// `raw` is the averaged picture, `blurred` what the glass is painted from.
	capacity int
	raw      &u32 = unsafe { nil }
	blurred  &u32 = unsafe { nil }
	// The render pass that last painted from it.
	pass int
}

struct GlassCache {
mut:
	slots [glass_slot_count]GlassBackdrop
	// What a surface is painted from when every backdrop is taken: one cell.
	spare      GlassBackdrop
	spare_cell u32
	// Work space for the blur, and the blurred cells as they were before it.
	work_a        &u32 = unsafe { nil }
	work_b        &u32 = unsafe { nil }
	before        &u32 = unsafe { nil }
	work_capacity int
	// Whether the theme being painted has glass, and whether the pass being
	// rendered repaints the whole canvas.
	active    bool
	full_pass bool
	pass      int
	// The last pass that repainted the whole canvas.
	last_full_pass int
	allocated      bool
	streaks        [glass_streak_period]u8
	streaks_ready bool
}

// GlassTint is Windows 7's colourisation: how much of the blurred backdrop
// comes through, the colour laid over it, and the colour's afterglow, which
// is as strong as the backdrop is bright.
struct GlassTint {
	blur u32
	base u32
	glow u32
	// White and black laid over the result, and how strong the reflection and
	// the highlight at the top of a fill are.
	veil   u32
	shade  u32
	streak u32
	gloss  u32
}

// glass_key names a surface by its element id.
fn glass_key(id string) u64 {
	mut hash := u64(14695981039346656037)
	for i in 0 .. id.len {
		hash = (hash ^ u64(id[i])) * u64(1099511628211)
	}
	return if hash == 0 { u64(1) } else { hash }
}

@[inline]
fn glass_floor_cell(v int) int {
	return if v >= 0 { v / glass_cell } else { -((-v + glass_cell - 1) / glass_cell) }
}

@[inline]
fn glass_clamp(v int, low int, high int) int {
	return if v < low {
		low
	} else if v > high {
		high
	} else {
		v
	}
}

// glass_begin_pass is called before a pass paints anything.
fn (mut d Desktop) glass_begin_pass(clip Clip) {
	d.glass.active = d.theme().glass
	if !d.glass.active {
		if d.glass.allocated {
			d.glass_release()
		}
		return
	}
	d.glass.pass++
	d.glass.full_pass = clip.x <= 0 && clip.y <= 0 && clip.x + clip.w >= d.canvas.width
		&& clip.y + clip.h >= d.canvas.height
	if !d.glass.full_pass {
		return
	}
	// A surface that the last whole frame did not paint, and nothing since
	// has, is gone: a closed or minimized window, the Start menu shut.
	for i in 0 .. glass_slot_count {
		if d.glass.slots[i].raw != unsafe { nil } && d.glass.slots[i].pass < d.glass.last_full_pass {
			unsafe {
				free(d.glass.slots[i].raw)
				free(d.glass.slots[i].blurred)
			}
			d.glass.slots[i] = GlassBackdrop{}
		}
	}
	d.glass.last_full_pass = d.glass.pass
}

// glass_release gives back every backdrop, for a theme without glass.
fn (mut d Desktop) glass_release() {
	for i in 0 .. glass_slot_count {
		unsafe {
			if d.glass.slots[i].raw != nil {
				free(d.glass.slots[i].raw)
			}
			if d.glass.slots[i].blurred != nil {
				free(d.glass.slots[i].blurred)
			}
		}
		d.glass.slots[i] = GlassBackdrop{}
	}
	unsafe {
		if d.glass.work_a != nil {
			free(d.glass.work_a)
		}
		if d.glass.work_b != nil {
			free(d.glass.work_b)
		}
		if d.glass.before != nil {
			free(d.glass.before)
		}
	}
	d.glass.work_a = unsafe { nil }
	d.glass.work_b = unsafe { nil }
	d.glass.before = unsafe { nil }
	d.glass.work_capacity = 0
	d.glass.allocated = false
	d.glass.last_full_pass = 0
}

// glass_backdrop returns the blurred picture behind the surface (sx, sy, sw,
// sh), refreshed from the canvas. It has to be called before the surface
// paints anything of its own, its shadow included. (hx, hy, hw, hh) is the
// part of the surface that is covered and needs no picture; hw of zero is
// none.
fn (mut d Desktop) glass_backdrop(key u64, sx int, sy int, sw int, sh int, hx int, hy int, hw int,
	hh int) &GlassBackdrop {
	mut index := -1
	mut found := false
	for i in 0 .. glass_slot_count {
		if d.glass.slots[i].key == key {
			index = i
			found = true
			break
		}
		if index < 0 && d.glass.slots[i].raw == unsafe { nil } {
			index = i
		}
	}
	if index < 0 {
		// Every backdrop belongs to a surface that is still on the screen.
		// Taking one would have its owner take another's on the next frame,
		// and so on for as long as they are all there.
		d.glass.spare_cell = glass_spare_cell
		d.glass.spare = GlassBackdrop{
			cols:    1
			rows:    1
			blurred: &d.glass.spare_cell
		}
		return &d.glass.spare
	}
	mut slot := &d.glass.slots[index]
	scale := d.canvas.scale
	x := glass_floor_cell(sx - glass_reach) * glass_cell
	y := glass_floor_cell(sy - glass_reach) * glass_cell
	cols := glass_floor_cell(sx + sw + glass_reach + glass_cell - 1) - x / glass_cell
	rows := glass_floor_cell(sy + sh + glass_reach + glass_cell - 1) - y / glass_cell
	same := found && slot.raw != unsafe { nil } && slot.sx == sx && slot.sy == sy && slot.sw == sw
		&& slot.sh == sh && slot.hx == hx && slot.hy == hy && slot.hw == hw && slot.hh == hh
		&& slot.scale == scale
	slot.pass = d.glass.pass
	if cols <= 0 || rows <= 0 {
		return slot
	}
	if !same {
		slot.key = key
		slot.sx = sx
		slot.sy = sy
		slot.sw = sw
		slot.sh = sh
		slot.hx = hx
		slot.hy = hy
		slot.hw = hw
		slot.hh = hh
		slot.scale = scale
		slot.x = x
		slot.y = y
		slot.cols = cols
		slot.rows = rows
		if slot.capacity < cols * rows {
			unsafe {
				if slot.raw != nil {
					free(slot.raw)
				}
				if slot.blurred != nil {
					free(slot.blurred)
				}
				slot.raw = &u32(malloc(cols * rows * 4))
				slot.blurred = &u32(malloc(cols * rows * 4))
			}
			slot.capacity = cols * rows
		}
		// Cells no capture reaches are still read by the blur.
		unsafe {
			vmemset(slot.raw, 0, cols * rows * 4)
		}
		d.glass.allocated = true
	}
	if d.glass.work_capacity < cols * rows {
		unsafe {
			if d.glass.work_a != nil {
				free(d.glass.work_a)
			}
			if d.glass.work_b != nil {
				free(d.glass.work_b)
			}
			if d.glass.before != nil {
				free(d.glass.before)
			}
			d.glass.work_a = &u32(malloc(cols * rows * 4))
			d.glass.work_b = &u32(malloc(cols * rows * 4))
			d.glass.before = &u32(malloc(cols * rows * 4))
		}
		d.glass.work_capacity = cols * rows
		d.glass.allocated = true
	}

	changed, approximate := d.glass_capture(mut slot, !same)
	if approximate {
		// A surface that is new or has moved needs the picture all around it,
		// and this pass only painted part of that. What it could see will do
		// for one frame; the next one is complete.
		d.dirty = true
	}
	if !changed && same {
		return slot
	}
	follow := same && !d.glass.full_pass
	count := cols * rows
	if follow {
		unsafe { vmemcpy(d.glass.before, slot.blurred, count * 4) }
	}
	mut source := slot.raw
	for pass in 0 .. glass_blur_passes {
		glass_box_rows(source, d.glass.work_a, cols, rows, glass_blur_radius)
		target := if pass == glass_blur_passes - 1 { slot.blurred } else { d.glass.work_b }
		glass_box_columns(d.glass.work_a, target, cols, rows, glass_blur_radius)
		source = target
	}
	if follow {
		d.glass_damage_fringe(slot)
	}
	return slot
}

// glass_capture averages the canvas into the cells this pass can vouch for:
// those whose pixels all lie inside the clip. A backdrop being made afresh
// takes the others from the nearest pixels the clip does hold and reports
// that as approximate. It also reports whether any cell changed.
fn (mut d Desktop) glass_capture(mut slot GlassBackdrop, fresh bool) (bool, bool) {
	width := d.canvas.width
	height := d.canvas.height
	clip := d.canvas.clip
	clip_x0 := if clip.x > 0 { clip.x } else { 0 }
	clip_y0 := if clip.y > 0 { clip.y } else { 0 }
	clip_x1 := if clip.x + clip.w < width { clip.x + clip.w } else { width }
	clip_y1 := if clip.y + clip.h < height { clip.y + clip.h } else { height }
	if clip_x1 <= clip_x0 || clip_y1 <= clip_y0 || width <= 0 || height <= 0 {
		return false, false
	}
	// Cells this deep inside the covered part reach no glass.
	inner_x0 := slot.hx + glass_reach
	inner_y0 := slot.hy + glass_reach
	inner_x1 := slot.hx + slot.hw - glass_reach
	inner_y1 := slot.hy + slot.hh - glass_reach
	has_inner := slot.hw > 0 && inner_x1 - inner_x0 >= glass_cell && inner_y1 - inner_y0 >= glass_cell
	scale := d.canvas.scale
	stride := d.canvas.stride
	pixels := d.canvas.pixels
	mut changed := false
	mut approximate := false
	for row in 0 .. slot.rows {
		cell_y := slot.y + row * glass_cell
		foot_y0 := glass_clamp(cell_y, 0, height - 1)
		foot_y1 := glass_clamp(cell_y + glass_cell - 1, 0, height - 1)
		row_inside := foot_y0 >= clip_y0 && foot_y1 < clip_y1
		if !row_inside && !fresh {
			continue
		}
		skip_row := has_inner && cell_y >= inner_y0 && cell_y + glass_cell <= inner_y1
		mut column := 0
		for column < slot.cols {
			cell_x := slot.x + column * glass_cell
			if skip_row && cell_x >= inner_x0 && cell_x + glass_cell <= inner_x1 {
				// On to the first cell that is not wholly covered.
				column = (inner_x1 - slot.x) / glass_cell
				continue
			}
			foot_x0 := glass_clamp(cell_x, 0, width - 1)
			foot_x1 := glass_clamp(cell_x + glass_cell - 1, 0, width - 1)
			inside := row_inside && foot_x0 >= clip_x0 && foot_x1 < clip_x1
			if !inside && !fresh {
				column++
				continue
			}
			// A cell this pass cannot vouch for is read from as near as the
			// clip comes to it.
			low_x := if inside { 0 } else { clip_x0 }
			high_x := if inside { width - 1 } else { clip_x1 - 1 }
			low_y := if inside { 0 } else { clip_y0 }
			high_y := if inside { height - 1 } else { clip_y1 - 1 }
			if !inside {
				approximate = true
			}
			mut red := u32(0)
			mut green := u32(0)
			mut blue := u32(0)
			for offset_y in 0 .. glass_cell {
				pixel_y := glass_clamp(cell_y + offset_y, low_y, high_y)
				line := pixel_y * scale * stride
				for offset_x in 0 .. glass_cell {
					pixel_x := glass_clamp(cell_x + offset_x, low_x, high_x)
					color := unsafe { pixels[line + pixel_x * scale] }
					red += (color >> 16) & 0xff
					green += (color >> 8) & 0xff
					blue += color & 0xff
				}
			}
			samples := u32(glass_cell * glass_cell)
			value := ((red / samples) << 16) | ((green / samples) << 8) | (blue / samples)
			unsafe {
				cell := &slot.raw[row * slot.cols + column]
				if fresh || glass_cell_differs(*cell, value) {
					*cell = value
					changed = true
				}
			}
			column++
		}
	}
	return changed || fresh, approximate
}

// A cell has changed when it differs by more than this in some channel. A
// partial frame does not paint everything exactly as a whole frame did -- a
// builtin glyph's holes are filled with a colour sampled from the canvas,
// which outside the clip is last frame's, shadows and all -- and a shade
// nobody can see is not worth a blur and another frame for its fringe. The
// cell keeps what it had, so a slow fade is still followed, two shades late.
const glass_cell_tolerance = 2

@[inline]
fn glass_cell_differs(a u32, b u32) bool {
	return abs_int(int((a >> 16) & 0xff) - int((b >> 16) & 0xff)) > glass_cell_tolerance
		|| abs_int(int((a >> 8) & 0xff) - int((b >> 8) & 0xff)) > glass_cell_tolerance
		|| abs_int(int(a & 0xff) - int(b & 0xff)) > glass_cell_tolerance
}

// glass_box_rows blurs each row with a box of the given radius, the edge
// cells standing in for what is past them.
fn glass_box_rows(source &u32, target &u32, cols int, rows int, radius int) {
	window := u32(2 * radius + 1)
	for row in 0 .. rows {
		line := unsafe { &source[row * cols] }
		out := unsafe { &target[row * cols] }
		mut red := u32(0)
		mut green := u32(0)
		mut blue := u32(0)
		for offset in -radius .. radius + 1 {
			color := unsafe { line[glass_clamp(offset, 0, cols - 1)] }
			red += (color >> 16) & 0xff
			green += (color >> 8) & 0xff
			blue += color & 0xff
		}
		for column in 0 .. cols {
			unsafe {
				out[column] = ((red / window) << 16) | ((green / window) << 8) | (blue / window)
			}
			entering := unsafe { line[glass_clamp(column + radius + 1, 0, cols - 1)] }
			leaving := unsafe { line[glass_clamp(column - radius, 0, cols - 1)] }
			red += ((entering >> 16) & 0xff) - ((leaving >> 16) & 0xff)
			green += ((entering >> 8) & 0xff) - ((leaving >> 8) & 0xff)
			blue += (entering & 0xff) - (leaving & 0xff)
		}
	}
}

fn glass_box_columns(source &u32, target &u32, cols int, rows int, radius int) {
	window := u32(2 * radius + 1)
	for column in 0 .. cols {
		mut red := u32(0)
		mut green := u32(0)
		mut blue := u32(0)
		for offset in -radius .. radius + 1 {
			color := unsafe { source[glass_clamp(offset, 0, rows - 1) * cols + column] }
			red += (color >> 16) & 0xff
			green += (color >> 8) & 0xff
			blue += color & 0xff
		}
		for row in 0 .. rows {
			unsafe {
				target[row * cols + column] = ((red / window) << 16) | ((green / window) << 8) | (blue / window)
			}
			entering := unsafe { source[glass_clamp(row + radius + 1, 0, rows - 1) * cols + column] }
			leaving := unsafe { source[glass_clamp(row - radius, 0, rows - 1) * cols + column] }
			red += ((entering >> 16) & 0xff) - ((leaving >> 16) & 0xff)
			green += ((entering >> 8) & 0xff) - ((leaving >> 8) & 0xff)
			blue += (entering & 0xff) - (leaving & 0xff)
		}
	}
}

// glass_damage_fringe asks the next frame to repaint the glass that this
// pass's clip left out but whose blur just changed. The surface's four sides
// are damaged apart, so a change on two of them does not cost the body.
fn (mut d Desktop) glass_damage_fringe(slot &GlassBackdrop) {
	clip := d.canvas.clip
	mut sides := [4]DamageRect{}
	has_body := slot.hw > 0
	for row in 0 .. slot.rows {
		for column in 0 .. slot.cols {
			index := row * slot.cols + column
			if unsafe { slot.blurred[index] == d.glass.before[index] } {
				continue
			}
			// Every pixel within a cell of this one is painted from it.
			x0 := slot.x + (column - 1) * glass_cell
			y0 := slot.y + (row - 1) * glass_cell
			x1 := x0 + 3 * glass_cell
			y1 := y0 + 3 * glass_cell
			if x0 >= clip.x && y0 >= clip.y && x1 <= clip.x + clip.w && y1 <= clip.y + clip.h {
				continue
			}
			area := DamageRect{
				x:     x0
				y:     y0
				w:     x1 - x0
				h:     y1 - y0
				valid: true
			}
			if !has_body {
				sides[0] = damage_union(sides[0], damage_intersection(area, DamageRect{
					x:     slot.sx
					y:     slot.sy
					w:     slot.sw
					h:     slot.sh
					valid: true
				}))
				continue
			}
			// Above the body, below it, and to its left and right.
			sides[0] = damage_union(sides[0], damage_intersection(area, DamageRect{
				x:     slot.sx
				y:     slot.sy
				w:     slot.sw
				h:     slot.hy - slot.sy
				valid: true
			}))
			sides[1] = damage_union(sides[1], damage_intersection(area, DamageRect{
				x:     slot.sx
				y:     slot.hy + slot.hh
				w:     slot.sw
				h:     slot.sy + slot.sh - slot.hy - slot.hh
				valid: true
			}))
			sides[2] = damage_union(sides[2], damage_intersection(area, DamageRect{
				x:     slot.sx
				y:     slot.hy
				w:     slot.hx - slot.sx
				h:     slot.hh
				valid: true
			}))
			sides[3] = damage_union(sides[3], damage_intersection(area, DamageRect{
				x:     slot.hx + slot.hw
				y:     slot.hy
				w:     slot.sx + slot.sw - slot.hx - slot.hw
				h:     slot.hh
				valid: true
			}))
		}
	}
	for side in sides {
		if side.valid {
			d.frame_damage.add(side)
		}
	}
}

// align_to_glass grows every rectangle to whole cells, so a pass never
// repaints part of one.
fn (mut f FrameDamage) align_to_glass() {
	for i in 0 .. f.count {
		rect := f.rects[i]
		x0 := glass_floor_cell(rect.x) * glass_cell
		y0 := glass_floor_cell(rect.y) * glass_cell
		x1 := glass_floor_cell(rect.x + rect.w + glass_cell - 1) * glass_cell
		y1 := glass_floor_cell(rect.y + rect.h + glass_cell - 1) * glass_cell
		f.rects[i] = DamageRect{
			x:     x0
			y:     y0
			w:     x1 - x0
			h:     y1 - y0
			valid: true
		}
	}
}

// ── Colourisation ──────────────────────────────────────────────────

@[inline]
fn glass_scale_color(color u32, amount u32) u32 {
	red := ((color >> 16) & 0xff) * amount / 100
	green := ((color >> 8) & 0xff) * amount / 100
	blue := (color & 0xff) * amount / 100
	return (red << 16) | (green << 8) | blue
}

// glass_color is the preset Settings has chosen.
fn (d &Desktop) glass_color() GlassColor {
	index := if d.settings.glass_color >= 0 && d.settings.glass_color < glass_colors.len {
		d.settings.glass_color
	} else {
		0
	}
	return glass_colors[index]
}

// glass_tint works out the three balances the way Windows 7 does from a
// colour's intensity. Its own Sky is 8% colour, 43% afterglow and 49% blur;
// a stronger colour takes the blur's share. An unfocused window keeps two
// fifths of the colour and goes pale.
fn (d &Desktop) glass_tint(active bool) GlassTint {
	preset := d.glass_color()
	percent := (preset.intensity * 100 + 127) / 255
	mut tint := u32(8)
	mut glow := percent + 1
	mut blur := 100 - tint - glow
	if percent > 50 {
		tint = 8 + (percent - 50) * 8 / 5
		blur = if percent < 79 { 99 - percent } else { 20 }
		glow = 100 - tint - blur
	}
	if !active {
		tint = tint * 2 / 5
		glow = glow * 2 / 5
		blur = 100 - tint - glow
	}
	return GlassTint{
		blur:   blur * 256 / 100
		base:   glass_scale_color(preset.color, tint)
		glow:   glass_scale_color(preset.color, glow)
		veil:   if active { 0 } else { 26 }
		streak: if active { 256 } else { 150 }
		gloss:  if active { 44 } else { 24 }
	}
}

// glass_tinted is one colour of the backdrop through the colourisation: the
// blur's share of it, the colour, and the colour's afterglow, as strong as
// the backdrop is bright.
@[inline]
fn glass_tinted(behind u32, tint GlassTint) u32 {
	behind_red := (behind >> 16) & 0xff
	behind_green := (behind >> 8) & 0xff
	behind_blue := behind & 0xff
	luminance := (77 * behind_red + 151 * behind_green + 28 * behind_blue) >> 8
	mut red := ((behind_red * tint.blur) >> 8) + ((tint.base >> 16) & 0xff) +
		((tint.glow >> 16) & 0xff) * luminance / 255
	mut green := ((behind_green * tint.blur) >> 8) + ((tint.base >> 8) & 0xff) +
		((tint.glow >> 8) & 0xff) * luminance / 255
	mut blue := ((behind_blue * tint.blur) >> 8) + (tint.base & 0xff) +
		(tint.glow & 0xff) * luminance / 255
	if red > 255 {
		red = 255
	}
	if green > 255 {
		green = 255
	}
	if blue > 255 {
		blue = 255
	}
	return (red << 16) | (green << 8) | blue
}

fn (mut d Desktop) glass_prepare_streaks() {
	if d.glass.streaks_ready {
		return
	}
	for position in 0 .. glass_streak_period {
		mut light := 0
		for band := 0; band + 2 < glass_streak_bands.len; band += 3 {
			mut distance := abs_int(position - glass_streak_bands[band])
			if distance > glass_streak_period / 2 {
				distance = glass_streak_period - distance
			}
			half := glass_streak_bands[band + 1]
			if distance < half {
				// A smooth bump rather than a tent: the bands have no edges.
				ramp := (half - distance) * 256 / half
				light += glass_streak_bands[band + 2] * ramp * ramp / 65536
			}
		}
		d.glass.streaks[position] = u8(if light > 255 { 255 } else { light })
	}
	d.glass.streaks_ready = true
}

// glass_fill paints the part of a surface inside (x, y, w, h) as glass. The
// surface's whole outline is (ox, oy, ow, oh) with `radius` corners; `gloss`
// rows from `gloss_top` carry the highlight, strongest at the top.
fn (mut d Desktop) glass_fill(slot &GlassBackdrop, tint GlassTint, x int, y int, w int, h int, ox int,
	oy int, ow int, oh int, radius int, gloss_top int, gloss_rows int) {
	if slot.cols <= 0 || slot.rows <= 0 || slot.blurred == unsafe { nil } {
		return
	}
	d.glass_prepare_streaks()
	clip := d.canvas.clip
	mut x0 := if x > clip.x { x } else { clip.x }
	mut y0 := if y > clip.y { y } else { clip.y }
	mut x1 := if x + w < clip.x + clip.w { x + w } else { clip.x + clip.w }
	mut y1 := if y + h < clip.y + clip.h { y + h } else { clip.y + clip.h }
	if x0 < 0 {
		x0 = 0
	}
	if y0 < 0 {
		y0 = 0
	}
	if x1 > d.canvas.width {
		x1 = d.canvas.width
	}
	if y1 > d.canvas.height {
		y1 = d.canvas.height
	}
	if x1 <= x0 || y1 <= y0 {
		return
	}
	scale := d.canvas.scale
	stride := d.canvas.stride
	pixels := d.canvas.pixels
	plain_clip := clip.mask_radius == 0
	cols := slot.cols
	last_column := cols - 1
	last_row := slot.rows - 1
	blurred := slot.blurred
	for py in y0 .. y1 {
		// The cell row above this pixel's centre, and how far down from it.
		position_y := ((py - slot.y) * 2 + 1) * 256 / (2 * glass_cell) - 128
		row := glass_clamp(position_y >> 8, 0, last_row)
		next_row := if row < last_row { row + 1 } else { row }
		weight_y := if position_y < 0 { u32(0) } else { u32(position_y & 0xff) }
		upper := unsafe { &blurred[row * cols] }
		lower := unsafe { &blurred[next_row * cols] }
		mut gloss := u32(0)
		if gloss_rows > 0 && py >= gloss_top && py < gloss_top + gloss_rows {
			gloss = tint.gloss * u32(gloss_top + gloss_rows - py) / u32(gloss_rows)
		}
		corner_row := radius > 0 && (py < oy + radius || py >= oy + oh - radius)
		for px in x0 .. x1 {
			position_x := ((px - slot.x) * 2 + 1) * 256 / (2 * glass_cell) - 128
			column := glass_clamp(position_x >> 8, 0, last_column)
			next_column := if column < last_column { column + 1 } else { column }
			weight_x := if position_x < 0 { u32(0) } else { u32(position_x & 0xff) }
			top := unsafe { blend(upper[column], upper[next_column], weight_x) }
			bottom := unsafe { blend(lower[column], lower[next_column], weight_x) }
			mut color := glass_tinted(blend(top, bottom, weight_y), tint)
			// The bands lean: nine pixels across for every sixteen down.
			mut band := (px * 16 + py * 9) / 16 % glass_streak_period
			if band < 0 {
				band += glass_streak_period
			}
			mut white := (u32(d.glass.streaks[band]) * tint.streak) >> 8
			white += gloss + tint.veil
			if white > 0 {
				color = blend(color, 0xffffff, if white > 255 { u32(255) } else { white })
			}
			if tint.shade > 0 {
				color = blend(color, 0x000000, tint.shade)
			}
			mut coverage := u32(255)
			if corner_row && (px < ox + radius || px >= ox + ow - radius) {
				coverage = round_rect_coverage(px, py, ox, oy, ow, oh, radius)
				if coverage == 0 {
					continue
				}
			}
			if coverage < 255 || !plain_clip {
				d.canvas.blend_pixel(px, py, color, coverage)
				continue
			}
			first := py * scale * stride + px * scale
			for offset_y in 0 .. scale {
				for offset_x in 0 .. scale {
					unsafe {
						pixels[first + offset_y * stride + offset_x] = color
					}
				}
			}
		}
	}
}

// ── Windows ────────────────────────────────────────────────────────

// The frame's lines. Windows 7 edges the glass with a dark line and a light
// one inside it, and the body with the same pair the other way round.
const aero_edge_dark = u32(0x000000)
const aero_edge_light = u32(0xffffff)
const aero_outer_alpha = u32(158)
const aero_outer_inactive_alpha = u32(122)
const aero_light_alpha = u32(150)
const aero_light_inactive_alpha = u32(132)
const aero_body_alpha = u32(128)
const aero_body_inactive_alpha = u32(112)
// The highlight at the top of the frame fades out over this many rows.
const aero_gloss_rows = 17
// An unfocused window's shadow is this much of a focused one's, in 256ths.
const aero_inactive_shadow = u32(120)

// draw_glass_window paints a window's frame: its shadow, the glass around
// the body, and the frame's lines. The body itself is the window's child.
fn (mut d Desktop) draw_glass_window(el &ui2.Element, x int, y int, w int, h int) {
	theme := d.theme()
	radius := int(el.box.radius)
	active := el.focused
	mut body_x := x
	mut body_y := y + theme.title_height
	mut body_w := w
	mut body_h := h - theme.title_height
	for i in 0 .. el.children.len {
		child := unsafe { &el.children[i] }
		if child.id.ends_with('.body') {
			body_x = x + int(child.frame.x)
			body_y = y + int(child.frame.y)
			body_w = int(child.frame.width)
			body_h = int(child.frame.height)
			break
		}
	}
	framed := body_x > x
	key := glass_key(el.id)
	// A maximized window is glass along its top only.
	slot := if framed {
		d.glass_backdrop(key, x, y, w, h, body_x, body_y, body_w, body_h)
	} else {
		d.glass_backdrop(key, x, y, w, body_y - y, 0, 0, 0, 0)
	}
	tint := d.glass_tint(active)
	if framed {
		shadow := if active { theme.shadow_alpha } else { theme.shadow_alpha * aero_inactive_shadow / 256 }
		d.canvas.drop_shadow_behind(x, y, w, h, radius, theme.shadow_spread, shadow)
	}
	d.glass_fill(slot, tint, x, y, w, body_y - y, x, y, w, h, radius, y, aero_gloss_rows)
	d.walk.title_under = d.glass_title_under(el, slot, tint, x, y)
	if framed {
		below := body_y + body_h
		d.glass_fill(slot, tint, x, below, w, y + h - below, x, y, w, h, radius, 0, 0)
		d.glass_fill(slot, tint, x, body_y, body_x - x, body_h, x, y, w, h, radius, 0, 0)
		d.glass_fill(slot, tint, body_x + body_w, body_y, x + w - body_x - body_w, body_h, x, y, w, h,
			radius, 0, 0)
	}

	outer := if active { aero_outer_alpha } else { aero_outer_inactive_alpha }
	light := if active { aero_light_alpha } else { aero_light_inactive_alpha }
	body := if active { aero_body_alpha } else { aero_body_inactive_alpha }
	if !framed {
		// Only the pair of lines between the caption and the body is left.
		d.canvas.blend_rect(x, body_y - 2, w, 1, aero_edge_light, light)
		d.canvas.blend_rect(x, body_y - 1, w, 1, aero_edge_dark, body)
		return
	}
	d.canvas.stroke_round_rect(x, y, w, h, radius, aero_edge_dark, outer)
	d.canvas.stroke_round_rect(x + 1, y + 1, w - 2, h - 2, if radius > 0 { radius - 1 } else { 0 },
		aero_edge_light, light)
	d.canvas.stroke_round_rect(body_x - 2, body_y - 2, body_w + 4, body_h + 4, 1, aero_edge_light,
		light)
	d.canvas.stroke_round_rect(body_x - 1, body_y - 1, body_w + 2, body_h + 2, 0, aero_edge_dark,
		body)
}

// glass_title_under is the glass where the title's icon goes, worked out from
// the backdrop rather than read back from the canvas: a partial frame's
// canvas outside its clip holds whatever was last on top there.
fn (d &Desktop) glass_title_under(el &ui2.Element, slot &GlassBackdrop, tint GlassTint, x int, y int) u32 {
	if slot.cols <= 0 || slot.rows <= 0 || slot.blurred == unsafe { nil } {
		return d.theme().title_active_bg
	}
	mut icon_x := x + d.theme().frame_border + d.theme().title_icon_inset + title_icon_size / 2
	mut icon_y := y + d.theme().title_height / 2
	for i in 0 .. el.children.len {
		bar := unsafe { &el.children[i] }
		if !bar.id.ends_with('.titlebar') {
			continue
		}
		for j in 0 .. bar.children.len {
			child := unsafe { &bar.children[j] }
			if child.kind == .image {
				icon_x = x + int(bar.frame.x + child.frame.x + child.frame.width / 2)
				icon_y = y + int(bar.frame.y + child.frame.y + child.frame.height / 2)
				break
			}
		}
	}
	column := glass_clamp((icon_x - slot.x) / glass_cell, 0, slot.cols - 1)
	row := glass_clamp((icon_y - slot.y) / glass_cell, 0, slot.rows - 1)
	color := glass_tinted(unsafe { slot.blurred[row * slot.cols + column] }, tint)
	return if tint.veil > 0 { blend(color, 0xffffff, tint.veil) } else { color }
}

// The title's glow: Windows 7 puts a white haze behind the black text, which
// is all that keeps it readable when the glass is over something dark.
const aero_title_glow_layers = 8
const aero_title_glow_alpha = u32(16)

fn (mut d Desktop) draw_aero_title_glow(x int, y int, w int, h int) {
	if w <= 0 || h <= 0 {
		return
	}
	middle := y + h / 2
	for layer := aero_title_glow_layers; layer >= 1; layer-- {
		grow_x := 2 + layer * 2
		grow_y := 4 + layer
		d.canvas.blend_round_rect(x - grow_x, middle - grow_y, w + 2 * grow_x, 2 * grow_y, grow_y,
			0xffffff, aero_title_glow_alpha)
	}
}

// ── Caption buttons ────────────────────────────────────────────────

// A button's face is two gradients, one over each half of its height, with a
// hard line between them: that step is what makes it read as glass. Each
// state names the four colours, top to bottom, and how opaque the face is.
struct AeroFace {
	top       u32
	upper     u32
	lower     u32
	bottom    u32
	alpha     u32
	low_alpha u32
}

// White over the frame's own glass: an idle button on a focused window, and
// the same fainter on an unfocused one.
const aero_face_idle = AeroFace{0xffffff, 0xffffff, 0xffffff, 0xffffff, 112, 26}
const aero_face_idle_inactive = AeroFace{0xffffff, 0xffffff, 0xffffff, 0xffffff, 44, 8}
const aero_face_hover = AeroFace{0xc9e4fa, 0x86c0f0, 0x3d95e2, 0x74c8f7, 240, 240}
const aero_face_pressed = AeroFace{0x9cc4e6, 0x5e9bd0, 0x2472b8, 0x4a9bd0, 245, 245}
const aero_face_close = AeroFace{0xeeb2a5, 0xdb7b6d, 0xc7402d, 0xd66a50, 238, 238}
const aero_face_close_hover = AeroFace{0xfbc5ba, 0xf58d7f, 0xe3492f, 0xf7a55e, 245, 245}
const aero_face_close_pressed = AeroFace{0xd9a093, 0xc0695c, 0xa32b1a, 0xb5503a, 248, 248}
// The group's outline and the bright line just inside it.
const aero_caption_edge_alpha = u32(150)
const aero_caption_edge_inactive_alpha = u32(34)
const aero_caption_shine_alpha = u32(120)
const aero_caption_shine_inactive_alpha = u32(64)
// The marks are white with a dark rim.
const aero_mark = u32(0xffffff)
const aero_mark_rim = u32(0x36404f)
const aero_mark_alpha = u32(255)
const aero_mark_inactive_alpha = u32(215)
const aero_mark_rim_alpha = u32(190)
const aero_mark_rim_inactive_alpha = u32(120)

enum AeroCaption {
	minimize
	maximize
	close
}

// draw_aero_caption_button paints one of Windows 7's caption buttons. The
// three share one outline with rounded lower corners, so each is cut out of
// the whole group's shape.
fn (mut d Desktop) draw_aero_caption_button(el &ui2.Element, x int, y int, w int, h int) {
	kind := if el.id.ends_with('.close') {
		AeroCaption.close
	} else if el.id.ends_with('.maximize') {
		AeroCaption.maximize
	} else {
		AeroCaption.minimize
	}
	active := !d.inactive_window
	hovered := d.hover == el.id
	pressed := hovered && d.buttons & button_left != 0
	// Where the group starts: close is outermost at either end.
	buttons_left := d.settings.button_side == .left
	group_x := match kind {
		.minimize {
			if buttons_left { x - aero_caption_close_width - aero_caption_maximize_width } else { x }
		}
		.maximize {
			if buttons_left { x - aero_caption_close_width } else { x - aero_caption_minimize_width }
		}
		.close {
			if buttons_left { x } else { x - aero_caption_minimize_width - aero_caption_maximize_width }
		}
	}
	last := x + w == group_x + aero_caption_width
	face := if kind == .close {
		if pressed {
			aero_face_close_pressed
		} else if hovered {
			aero_face_close_hover
		} else if active {
			aero_face_close
		} else {
			aero_face_idle_inactive
		}
	} else if pressed {
		aero_face_pressed
	} else if hovered {
		aero_face_hover
	} else if active {
		aero_face_idle
	} else {
		aero_face_idle_inactive
	}
	edge := if active || hovered { aero_caption_edge_alpha } else { aero_caption_edge_inactive_alpha }
	shine := if active || hovered { aero_caption_shine_alpha } else { aero_caption_shine_inactive_alpha }

	// The group reaches up past the frame's top line, so only its lower
	// corners are rounded.
	shape_y := y - 2 * aero_caption_radius
	shape_h := h + 2 * aero_caption_radius
	face_rows := h - 1
	half := face_rows / 2
	for row in 0 .. h {
		py := y + row
		mut color := u32(0)
		mut alpha := u32(0)
		if row < half {
			color = mix(face.top, face.upper, u32(row * 255 / (if half > 1 { half - 1 } else { 1 })))
			alpha = face.alpha
		} else if row < face_rows {
			color = mix(face.lower, face.bottom, u32((row - half) * 255 / (if face_rows - half > 1 {
				face_rows - half - 1
			} else {
				1
			})))
			alpha = if face.low_alpha == face.alpha {
				face.alpha
			} else {
				// White glass: the lower half clears toward the bottom edge.
				face.low_alpha + (face.alpha - face.low_alpha) * u32(row - half) / u32(3 * (face_rows - half))
			}
		}
		for column in 0 .. w {
			px := x + column
			whole := round_rect_coverage(px, py, group_x, shape_y, aero_caption_width, shape_h,
				aero_caption_radius)
			if whole == 0 {
				continue
			}
			inside := round_rect_coverage(px, py, group_x + 1, shape_y, aero_caption_width - 2,
				shape_h - 1, aero_caption_radius - 1)
			if inside > 0 && alpha > 0 {
				d.canvas.blend_pixel(px, py, color, alpha * inside / 255)
			}
			if whole > inside {
				d.canvas.blend_pixel(px, py, aero_edge_dark, edge * (whole - inside) / 255)
			}
		}
	}
	// The bright line inside the outline, and the divider on this button's
	// left with its own bright line.
	first := x == group_x
	shine_bottom := y + face_rows - 1
	// The face between this button's own lines.
	face_left := x + 1
	face_right := if last { x + w - 1 } else { x + w }
	corner := aero_caption_radius - 1
	shine_left := if first { face_left + corner } else { face_left }
	shine_right := if last { face_right - corner } else { face_right }
	d.canvas.blend_rect(shine_left, shine_bottom, shine_right - shine_left, 1, aero_edge_light,
		shine * 2 / 3)
	if !first {
		d.canvas.blend_rect(x, y, 1, face_rows, aero_edge_dark, edge)
	}
	d.canvas.blend_rect(face_left, y, 1, if first { face_rows - corner } else { face_rows - 1 },
		aero_edge_light, shine)
	if last {
		d.canvas.blend_rect(face_right - 1, y, 1, face_rows - corner, aero_edge_light, shine)
	}
	if hovered {
		// The lit button spills a little of its colour under the group.
		glow := if kind == .close { u32(0xf0502c) } else { u32(0x5fb4f5) }
		d.canvas.blend_rect(x + 2, y + h, w - 4, 1, glow, 70)
		d.canvas.blend_rect(x + 4, y + h + 1, w - 8, 1, glow, 30)
	}

	mark := if active || hovered { aero_mark_alpha } else { aero_mark_inactive_alpha }
	rim := if active || hovered { aero_mark_rim_alpha } else { aero_mark_rim_inactive_alpha }
	middle := (face_left + face_right) / 2
	match kind {
		.minimize {
			// A bar sitting on the lower half.
			d.canvas.blend_rect(middle - 6, y + 9, 12, 5, aero_mark_rim, rim)
			d.canvas.blend_rect(middle - 5, y + 10, 10, 3, aero_mark, mark)
		}
		.maximize {
			if el.image_path == 'builtin:restore' {
				// Two smaller frames, the back one showing above and to the
				// right of the front one.
				saved := d.canvas.push_clip_rect(middle - 6, y + 3, 13, 4)
				d.draw_aero_frame_mark(middle - 3, y + 3, 10, 8, 1, mark, rim)
				d.canvas.restore_clip(saved)
				saved_side := d.canvas.push_clip_rect(middle + 3, y + 7, 4, 4)
				d.draw_aero_frame_mark(middle - 3, y + 3, 10, 8, 1, mark, rim)
				d.canvas.restore_clip(saved_side)
				d.draw_aero_frame_mark(middle - 7, y + 6, 10, 8, 1, mark, rim)
			} else {
				d.draw_aero_frame_mark(middle - 6, y + 4, 12, 10, 2, mark, rim)
			}
		}
		.close {
			d.draw_aero_close_mark(face_left, y, face_right - face_left, face_rows, mark, rim)
		}
	}
}

// draw_aero_frame_mark is the maximise mark: a white frame `thickness` wide
// with a dark rim on both of its sides, around a hole that is left alone.
fn (mut d Desktop) draw_aero_frame_mark(x int, y int, w int, h int, thickness int, mark u32, rim u32) {
	d.canvas.stroke_round_rect(x, y, w, h, 0, aero_mark_rim, rim)
	for ring in 1 .. thickness + 1 {
		d.canvas.stroke_round_rect(x + ring, y + ring, w - 2 * ring, h - 2 * ring, 0, aero_mark,
			mark)
	}
	inner := thickness + 1
	d.canvas.stroke_round_rect(x + inner, y + inner, w - 2 * inner, h - 2 * inner, 0, aero_mark_rim,
		rim)
}

// draw_aero_close_mark is the white cross with its dark rim. It is measured
// against the backing pixels, so its diagonals stay smooth at either scale.
fn (mut d Desktop) draw_aero_close_mark(x int, y int, w int, h int, mark u32, rim u32) {
	scale := f64(d.canvas.scale)
	center_x := (f64(x) + f64(w) / 2) * scale
	center_y := (f64(y) + f64(h) / 2 + 0.5) * scale
	reach_x := 3.6 * scale
	reach_y := 3.2 * scale
	stroke := 1.35 * scale
	rim_stroke := stroke + scale
	left := int(center_x - reach_x - rim_stroke) - 1
	right := int(center_x + reach_x + rim_stroke) + 1
	top := int(center_y - reach_y - rim_stroke) - 1
	bottom := int(center_y + reach_y + rim_stroke) + 1
	for py in top .. bottom + 1 {
		for px in left .. right + 1 {
			sample_x := f64(px) + 0.5 - center_x
			sample_y := f64(py) + 0.5 - center_y
			first := distance_to_segment(sample_x, sample_y, -reach_x, -reach_y, reach_x, reach_y)
			second := distance_to_segment(sample_x, sample_y, reach_x, -reach_y, -reach_x, reach_y)
			distance := if first < second { first } else { second }
			if distance >= rim_stroke + 0.5 {
				continue
			}
			rim_coverage := if distance <= rim_stroke - 0.5 {
				u32(255)
			} else {
				u32((rim_stroke + 0.5 - distance) * 255)
			}
			d.canvas.blend_physical_pixel(px, py, aero_mark_rim, rim_coverage * rim / 255)
			if distance < stroke + 0.5 {
				coverage := if distance <= stroke - 0.5 {
					u32(255)
				} else {
					u32((stroke + 0.5 - distance) * 255)
				}
				d.canvas.blend_physical_pixel(px, py, aero_mark, coverage * mark / 255)
			}
		}
	}
}

// ── Taskbar ────────────────────────────────────────────────────────

// The taskbar is the same glass under a shade, so white text holds on it
// whatever the wallpaper is.
const aero_bar_shade = u32(84)
const aero_bar_top_alpha = u32(150)
const aero_bar_shine_alpha = u32(96)
// What a button on the bar is: white at these strengths, edged brighter.
const aero_bar_idle_alpha = u32(30)
const aero_bar_hover_alpha = u32(74)
const aero_bar_active_alpha = u32(104)
const aero_bar_edge_alpha = u32(118)

// draw_glass_taskbar paints the bar: glass, its dark top line and the bright
// one under it.
fn (mut d Desktop) draw_glass_taskbar(el &ui2.Element, x int, y int, w int, h int) {
	slot := d.glass_backdrop(glass_key(el.id), x, y, w, h, 0, 0, 0, 0)
	tint := d.glass_tint(true)
	d.glass_fill(slot, GlassTint{
		...tint
		shade: aero_bar_shade
		gloss: 30
	}, x, y, w, h, x, y, w, h, 0, y + 1, h / 2)
	d.canvas.blend_rect(x, y, w, 1, aero_edge_dark, aero_bar_top_alpha)
	d.canvas.blend_rect(x, y + 1, w, 1, aero_edge_light, aero_bar_shine_alpha)
}

// draw_glass_bar_box paints a taskbar control's background as glass rather
// than as the flat colour its element declares. The colour says which state
// the control is in.
fn (mut d Desktop) draw_glass_bar_box(x int, y int, w int, h int, bg u32, radius int) {
	theme := d.theme()
	if bg == start_menu_shell {
		// A Start menu row at rest is the menu's own glass.
		return
	}
	mut color := u32(0xffffff)
	mut alpha := aero_bar_idle_alpha
	mut edge := u32(0)
	if bg == start_menu_power {
		alpha = aero_bar_hover_alpha * 2 / 3
		edge = aero_bar_edge_alpha * 2 / 3
	} else if bg == theme.taskbar_item_hover || bg == start_menu_right_hover
		|| bg == start_menu_power_hover {
		alpha = aero_bar_hover_alpha
		edge = aero_bar_edge_alpha * 2 / 3
	} else if bg == theme.taskbar_item_active {
		alpha = aero_bar_active_alpha
		edge = aero_bar_edge_alpha
	} else if bg == theme.accent {
		color = theme.accent
		alpha = 200
		edge = aero_bar_edge_alpha
	} else if bg != theme.taskbar_item_bg {
		// A colour with a meaning of its own, such as a button asking for
		// attention.
		color = bg
		alpha = 215
		edge = aero_bar_edge_alpha
	}
	d.canvas.blend_round_rect(x, y, w, h, radius, color, alpha)
	if alpha > aero_bar_idle_alpha && h > 6 {
		// The upper half is lit, as every Aero button's is.
		d.canvas.blend_round_rect(x + 1, y + 1, w - 2, h / 2 - 1, if radius > 1 { radius - 1 } else { 0 },
			0xffffff, 34)
	}
	if edge > 0 {
		d.canvas.stroke_round_rect(x, y, w, h, radius, 0xffffff, edge)
	}
}

// The Start menu's shell is darker glass than the taskbar's: its right pane
// carries white text, and the pale program pane sits in it as a sheet.
const aero_menu_shade = u32(112)

// draw_glass_menu paints the Start menu's shell: its shadow, the glass, and
// the frame's dark and bright lines.
fn (mut d Desktop) draw_glass_menu(el &ui2.Element, x int, y int, w int, h int) {
	theme := d.theme()
	radius := int(el.box.radius)
	slot := d.glass_backdrop(glass_key(el.id), x, y, w, h, 0, 0, 0, 0)
	d.canvas.drop_shadow_behind(x, y, w, h, radius, theme.shadow_spread, theme.shadow_alpha)
	tint := d.glass_tint(true)
	d.glass_fill(slot, GlassTint{
		...tint
		shade: aero_menu_shade
		gloss: 36
	}, x, y, w, h, x, y, w, h, radius, y + 1, 60)
	d.canvas.stroke_round_rect(x, y, w, h, radius, aero_edge_dark, aero_outer_alpha)
	d.canvas.stroke_round_rect(x + 1, y + 1, w - 2, h - 2, if radius > 0 { radius - 1 } else { 0 },
		aero_edge_light, aero_light_alpha * 2 / 3)
}
