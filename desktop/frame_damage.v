// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Partial frames.
//
// Most of what changes on an idle screen is small: the taskbar clock ticks
// once a second, one application redraws its own window, the pointer moves.
// Recomposing all 2048x1536 pixels for each of those, and asking every
// application process for its tree again, is what used to keep the desktop
// busy when nobody was using it. Changes like these record the area they
// touch in `frame_damage` instead of setting `dirty`; the frame then rebuilds
// the tree but paints and presents only that area. A pointer that merely moved
// needs even less: CursorBacking remembers the pixels under it, so the old
// position is restored and the pointer drawn at the new one without
// recomposing anything at all.
module main

// damage_union is the smallest rectangle covering both. An invalid side is
// ignored.
fn damage_union(a DamageRect, b DamageRect) DamageRect {
	if !a.valid || a.w <= 0 || a.h <= 0 {
		return if b.valid && b.w > 0 && b.h > 0 { b } else { DamageRect{} }
	}
	if !b.valid || b.w <= 0 || b.h <= 0 {
		return a
	}
	left := if a.x < b.x { a.x } else { b.x }
	top := if a.y < b.y { a.y } else { b.y }
	right := if a.x + a.w > b.x + b.w { a.x + a.w } else { b.x + b.w }
	bottom := if a.y + a.h > b.y + b.h { a.y + a.h } else { b.y + b.h }
	return DamageRect{
		x:     left
		y:     top
		w:     right - left
		h:     bottom - top
		valid: true
	}
}

// damage_intersection is what the two have in common, invalid when nothing.
fn damage_intersection(a DamageRect, b DamageRect) DamageRect {
	if !a.valid || !b.valid {
		return DamageRect{}
	}
	left := if a.x > b.x { a.x } else { b.x }
	top := if a.y > b.y { a.y } else { b.y }
	right := if a.x + a.w < b.x + b.w { a.x + a.w } else { b.x + b.w }
	bottom := if a.y + a.h < b.y + b.h { a.y + a.h } else { b.y + b.h }
	if right <= left || bottom <= top {
		return DamageRect{}
	}
	return DamageRect{
		x:     left
		y:     top
		w:     right - left
		h:     bottom - top
		valid: true
	}
}

fn damage_contains(outer DamageRect, inner DamageRect) bool {
	return outer.valid && inner.valid && inner.x >= outer.x && inner.y >= outer.y
		&& inner.x + inner.w <= outer.x + outer.w && inner.y + inner.h <= outer.y + outer.h
}

fn damage_of_clip(clip Clip) DamageRect {
	return DamageRect{
		x:     clip.x
		y:     clip.y
		w:     clip.w
		h:     clip.h
		valid: clip.w > 0 && clip.h > 0
	}
}

fn damage_area(r DamageRect) i64 {
	return if r.valid { i64(r.w) * i64(r.h) } else { 0 }
}

// A frame repaints a few separate rectangles rather than the one box around
// them: the clock ticking in the bottom-right corner and a window updating
// near the top-left would otherwise cost most of the screen.
const frame_damage_slots = 4

struct FrameDamage {
mut:
	rects [frame_damage_slots]DamageRect
	count int
}

fn (f &FrameDamage) valid() bool {
	return f.count > 0
}

// add records a rectangle, folding it into one already there when they
// overlap or their union is barely larger than the two apart, so no pixel is
// painted twice and the list stays short.
fn (mut f FrameDamage) add(r DamageRect) {
	if !r.valid || r.w <= 0 || r.h <= 0 {
		return
	}
	mut rect := r
	mut i := 0
	for i < f.count {
		merged := damage_union(f.rects[i], rect)
		if damage_intersection(f.rects[i], rect).valid
			|| damage_area(merged) * 4 <= (damage_area(f.rects[i]) + damage_area(rect)) * 5 {
			// The union can now reach others; take it out and start over.
			rect = merged
			f.count--
			f.rects[i] = f.rects[f.count]
			i = 0
			continue
		}
		i++
	}
	if f.count < frame_damage_slots {
		f.rects[f.count] = rect
		f.count++
		return
	}
	// Full: grow whichever rectangle grows least.
	mut best := 0
	mut best_growth := i64(-1)
	for j in 0 .. f.count {
		growth := damage_area(damage_union(f.rects[j], rect)) - damage_area(f.rects[j])
		if best_growth < 0 || growth < best_growth {
			best = j
			best_growth = growth
		}
	}
	f.rects[best] = damage_union(f.rects[best], rect)
}

fn (d &Desktop) canvas_damage() DamageRect {
	return DamageRect{
		x:     0
		y:     0
		w:     d.canvas.width
		h:     d.canvas.height
		valid: true
	}
}

// damage_clip turns a damage rectangle into the clip that repaints it,
// trimmed to the canvas.
fn (d &Desktop) damage_clip(damage DamageRect) Clip {
	area := damage_intersection(damage, d.canvas_damage())
	return Clip{
		x: area.x
		y: area.y
		w: area.w
		h: area.h
	}
}

// add_frame_damage asks for the area to be recomposed on the next frame
// without invalidating the rest of the screen.
fn (mut d Desktop) add_frame_damage(x int, y int, width int, height int) {
	d.frame_damage.add(DamageRect{
		x:     x
		y:     y
		w:     width
		h:     height
		valid: true
	})
}

// damage_window repaints one window where it stands, for a change to its own
// contents.
fn (mut d Desktop) damage_window(window_index int) {
	window := d.windows[window_index]
	if window.workspace != d.current_workspace || window.minimized {
		return
	}
	d.add_frame_damage(window.x, window.y, window.width, window.height)
}

// damage_hover_change repaints the controls the hover highlight moves
// between. It reports false when the change can reach further than that:
// open menus, flyouts, previews and tooltips arrange themselves around what
// is hovered, so they take the whole frame.
fn (mut d Desktop) damage_hover_change(old string, new string) bool {
	if d.start_menu_open || d.switcher.shown || d.taskbar_preview.open
		|| d.taskbar_preview.tooltip_shown || d.tray.flyout != .none_
		|| create_context_menu.visible || d.keyboard.hud_until != 0 {
		return false
	}
	for target in d.targets {
		if (old.len > 0 && target.action_id == old) || (new.len > 0 && target.action_id == new) {
			// A focus ring or edge can sit just outside the control's frame.
			d.add_frame_damage(target.x - 2, target.y - 2, target.width + 4, target.height + 4)
		}
	}
	return true
}

// damage_frame_counters adds what a composed frame changes by itself being
// composed: the System page reports the frame count.
fn (d &Desktop) damage_frame_counters(mut damage FrameDamage) {
	for window in d.windows {
		if window.page == .system && window.app_index < 0
			&& window.workspace == d.current_workspace && !window.minimized {
			damage.add(DamageRect{
				x:     window.x
				y:     window.y
				w:     window.width
				h:     window.height
				valid: true
			})
		}
	}
}

// damage_taskbar covers the bar, and the gap under a floating dock.
fn (mut d Desktop) damage_taskbar() {
	top := d.canvas.height - taskbar_height - dock_bottom_gap
	d.add_frame_damage(0, top, d.canvas.width, d.canvas.height - top)
}

// ── The software pointer ───────────────────────────────────────────

// CursorBacking holds the composed pixels a drawn pointer covers, at the
// canvas' physical resolution. While `box` is valid the canvas shows the
// pointer inside it and `pixels` is the picture without it.
struct CursorBacking {
mut:
	box    DamageRect
	pixels []u32
}

// cursor_box is every logical pixel the pointer can paint when it is at (x,
// y): the normal arrow and its shadow, or a resize arrow centered on the
// pointer. Trimmed to the canvas.
fn (d &Desktop) cursor_box(x int, y int) DamageRect {
	return damage_intersection(DamageRect{
		x:     x - cursor_backing_inset
		y:     y - cursor_backing_inset
		w:     cursor_backing_width
		h:     cursor_backing_height
		valid: true
	}, d.canvas_damage())
}

// copy_cursor_backing moves the pixels of `area`, which lies inside `box`,
// between the canvas and the backing store laid out for `box`.
fn (mut d Desktop) copy_cursor_backing(box DamageRect, area DamageRect, to_backing bool) {
	scale := d.canvas.scale
	stride := box.w * scale
	if d.cursor_backing.pixels.len < stride * box.h * scale {
		// Sized for the largest box once, so a scale change or a box trimmed
		// at the edge never reallocates.
		if d.cursor_backing.pixels.cap > 0 {
			unsafe { d.cursor_backing.pixels.free() }
		}
		d.cursor_backing.pixels = []u32{len: cursor_backing_width * cursor_backing_height * scale * scale}
	}
	x0 := area.x * scale
	x1 := if (area.x + area.w) * scale < d.canvas.physical_width {
		(area.x + area.w) * scale
	} else {
		d.canvas.physical_width
	}
	y1 := if (area.y + area.h) * scale < d.canvas.physical_height {
		(area.y + area.h) * scale
	} else {
		d.canvas.physical_height
	}
	if x1 <= x0 {
		return
	}
	bytes := usize((x1 - x0) * 4)
	for y := area.y * scale; y < y1; y++ {
		unsafe {
			canvas_pixel := &d.canvas.pixels[y * d.canvas.stride + x0]
			backing_pixel := &d.cursor_backing.pixels[(y - box.y * scale) * stride + x0 - box.x * scale]
			if to_backing {
				vmemcpy(backing_pixel, canvas_pixel, bytes)
			} else {
				vmemcpy(canvas_pixel, backing_pixel, bytes)
			}
		}
	}
}

// save_cursor_backing runs after a frame's contents are painted into `clip`
// and before the pointer is drawn over them. A pointer that has not moved
// keeps its backing outside the clip, whose pixels the frame did not touch; a
// pointer somewhere new can only be backed when the frame repainted all of
// it. Otherwise the backing is dropped, and the next pointer move recomposes.
fn (mut d Desktop) save_cursor_backing(clip Clip) {
	box := d.cursor_box(d.pointer_x, d.pointer_y)
	painted := damage_of_clip(clip)
	if d.cursor_backing.box.valid && d.cursor_backing.box == box {
		area := damage_intersection(box, painted)
		if area.valid {
			d.copy_cursor_backing(box, area, true)
		}
		return
	}
	if !box.valid || !damage_contains(painted, box) {
		d.cursor_backing.box = DamageRect{}
		return
	}
	d.copy_cursor_backing(box, box, true)
	d.cursor_backing.box = box
}

// move_cursor puts back what the pointer covered, backs up the pixels at its
// new position and draws it there. It returns the two areas that changed.
// Only valid while `cursor_backing.box` is.
fn (mut d Desktop) move_cursor() (DamageRect, DamageRect) {
	old := d.cursor_backing.box
	d.copy_cursor_backing(old, old, false)
	box := d.cursor_box(d.pointer_x, d.pointer_y)
	d.cursor_backing.box = DamageRect{}
	if box.valid {
		d.copy_cursor_backing(box, box, true)
		d.cursor_backing.box = box
	}
	d.canvas.clip = Clip{
		x: 0
		y: 0
		w: d.canvas.width
		h: d.canvas.height
	}
	d.draw_cursor()
	return old, box
}
