// A ui2 backend that draws into a framebuffer.
//
// ui2's element tree is platform independent — frames, box styles and text
// styles with no toolkit behind them — so a target with nothing but a mapped
// framebuffer only needs a renderer for it. This is that renderer: one walk
// paints the tree and collects the hit targets, which is what keeps what is
// drawn and what is clickable in step.
//
// Two conventions extend ui2 for this backend:
//
//   - `image_path` of the form `builtin:<name>` draws a vector glyph the
//     renderer carries itself, because the target has no image files.
//   - a rounded view at the top level of the tree is a floating surface and is
//     given a drop shadow.
module main

import ui2

// HitTarget is one clickable or draggable region, recorded in painting order.
struct HitTarget {
	action_id string
	x         int
	y         int
	width     int
	height    int
}

// text_inset is the gap between a control's edge and text aligned against it.
const text_inset = 10

// Reserve room for "100%  |  HH:MM:SS" as well as the date below it.
const clock_area_width = 208

// An icon sharing a control with a label is drawn at this size.
const button_icon_size = 16

// face_for picks the baked face closest to what a style asks for: the right
// weight first, then the nearest size. Nothing is scaled — a bitmap atlas
// stretched looks far worse than one a couple of pixels off — so a style
// asking for a size nothing was baked at gets the neighbour instead.
fn (d &Desktop) face_for(style ui2.TextStyle) &FontFace {
	wanted := int(style.size)
	mut best := 0
	mut best_score := 1 << 30
	for i, face in d.fonts {
		mut score := abs_int(face.size - wanted)
		if face.bold != style.bold {
			// Any face of the right weight beats every face of the wrong one.
			score += 1000
		}
		if score < best_score {
			best_score = score
			best = i
		}
	}
	return &d.fonts[best]
}

// free_tree releases the arrays a frame's element tree was built out of.
// There is no garbage collector on this target, so a tree rebuilt whenever the
// screen changes would otherwise grow the process without bound. Only the
// child arrays are freed: every string inside an element is either a literal
// or owned by the window list, and both outlive the tree on purpose.
fn free_tree(el ui2.Element) {
	for child in el.children {
		free_tree(child)
	}
	if el.children.len > 0 {
		unsafe { el.children.free() }
	}
}

fn (mut d Desktop) render(root ui2.Element) {
	// clear() keeps the buffer, so a steady desktop stops allocating one per
	// frame.
	d.targets.clear()
	d.canvas.clip = Clip{
		x: 0
		y: 0
		w: d.canvas.width
		h: d.canvas.height
	}
	d.canvas.vertical_gradient(0, 0, d.canvas.width, d.canvas.height, wallpaper_top,
		wallpaper_bottom)
	d.render_element(root, 0, 0, 0)
	d.draw_cursor()
}

fn (mut d Desktop) render_element(el ui2.Element, off_x int, off_y int, depth int) {
	if el.hidden {
		return
	}

	x := off_x + int(el.frame.x)
	y := off_y + int(el.frame.y)
	w := int(el.frame.width)
	h := int(el.frame.height)

	match el.kind {
		.screen {
			d.canvas.fill_rect(0, 0, d.canvas.width, d.canvas.height, el.box.bg)
		}
		.view, .scroll {
			d.draw_surface(el, x, y, w, h, depth)
		}
		.label {
			d.draw_label(el, x, y, w, h)
		}
		.button, .checkbox, .dropdown, .text_field, .text_area {
			d.draw_button(el, x, y, w, h)
		}
		.image {
			d.draw_builtin_glyph(el.image_path, x, y, w, h, el.text_style.color)
		}
	}

	d.record_target(el, x, y, w, h)

	if el.children.len == 0 {
		return
	}

	// A surface clips its children; the root and plain labels do not need to,
	// so the clip is only pushed where it can actually cut something off.
	mut saved := d.canvas.clip
	mut pushed := false
	if el.kind == .view || el.kind == .scroll || el.kind == .screen {
		if el.kind != .screen {
			saved = if el.box.radius > 0 {
				d.canvas.push_clip_round_rect(x, y, w, h, int(el.box.radius))
			} else {
				d.canvas.push_clip_rect(x, y, w, h)
			}
			pushed = true
		}
	}

	for child in el.children {
		d.render_element(child, x, y, depth + 1)
	}

	if pushed {
		d.canvas.restore_clip(saved)
	}
}

fn (mut d Desktop) record_target(el ui2.Element, x int, y int, w int, h int) {
	interactive := el.kind == .button || el.kind == .checkbox || el.kind == .dropdown
		|| el.draggable || el.clickable
	if !interactive || !el.enabled {
		return
	}
	action := if el.action_id.len > 0 { el.action_id } else { el.id }
	if action.len == 0 {
		return
	}
	d.targets << HitTarget{
		action_id: action
		x: x
		y: y
		width: w
		height: h
	}
}

// draw_surface paints a view's background. A rounded view at the top level of
// the tree is treated as floating and gets a shadow and a hairline edge, which
// is what makes a window read as a window rather than as a flat panel.
fn (mut d Desktop) draw_surface(el ui2.Element, x int, y int, w int, h int, depth int) {
	if el.box.transparent {
		return
	}
	radius := int(el.box.radius)
	floating := depth == 1 && radius > 0
	if floating {
		saved := d.canvas.clip
		d.canvas.clip = Clip{
			x: 0
			y: 0
			w: d.canvas.width
			h: d.canvas.height
		}
		d.canvas.drop_shadow(x, y, w, h, radius, 7, 150)
		d.canvas.restore_clip(saved)
	}
	if radius > 0 {
		d.canvas.fill_round_rect(x, y, w, h, radius, el.box.bg)
		if floating {
			d.canvas.stroke_round_rect(x, y, w, h, radius, window_edge, 190)
		}
	} else {
		d.canvas.fill_rect(x, y, w, h, el.box.bg)
	}
}

fn (mut d Desktop) draw_label(el ui2.Element, x int, y int, w int, h int) {
	if el.text.len == 0 {
		return
	}
	face := d.face_for(el.text_style)
	text := face.truncate(el.text, w)
	baseline_y := y + (h - face.line_height) / 2
	match el.text_style.align {
		.left { d.canvas.draw_text(face, x, baseline_y, text, el.text_style.color) }
		.center { d.canvas.draw_text_centered(face, x, baseline_y, w, text, el.text_style.color) }
		.right { d.canvas.draw_text_right(face, x + w, baseline_y, text, el.text_style.color) }
	}
}

fn (mut d Desktop) draw_button(el ui2.Element, x int, y int, w int, h int) {
	if !el.box.transparent {
		radius := int(el.box.radius)
		if radius > 0 {
			d.canvas.fill_round_rect(x, y, w, h, radius, el.box.bg)
		} else {
			d.canvas.fill_rect(x, y, w, h, el.box.bg)
		}
	}

	// An icon on its own gets the whole control; an icon with a label gets a
	// square at the leading edge and the label takes what is left. Without the
	// second case a glyph drawn across a wide button swamps its text.
	mut text_x := x + text_inset
	mut text_w := w - 2 * text_inset
	if el.image_path.len > 0 {
		if el.text.len == 0 {
			d.draw_builtin_glyph(el.image_path, x, y, w, h, el.text_style.color)
		} else {
			icon := if h - 8 < button_icon_size { h - 8 } else { button_icon_size }
			d.draw_builtin_glyph(el.image_path, x + text_inset, y + (h - icon) / 2, icon,
				icon, el.text_style.color)
			text_x += icon + 6
			text_w -= icon + 6
		}
	}

	if el.text.len == 0 {
		return
	}
	face := d.face_for(el.text_style)
	inner := if el.text_style.align == .center && el.image_path.len == 0 { w } else { text_w }
	text := face.truncate(el.text, inner)
	text_y := y + (h - face.line_height) / 2
	// A label sharing the control with an icon is always placed after it; the
	// declared alignment only decides where a label on its own sits.
	if el.image_path.len > 0 {
		d.canvas.draw_text(face, text_x, text_y, text, el.text_style.color)
		return
	}
	match el.text_style.align {
		.left { d.canvas.draw_text(face, x + text_inset, text_y, text, el.text_style.color) }
		.center { d.canvas.draw_text_centered(face, x, text_y, w, text, el.text_style.color) }
		.right { d.canvas.draw_text_right(face, x + w - text_inset, text_y, text, el.text_style.color) }
	}
}

// draw_builtin_glyph draws the title bar symbols as strokes rather than as
// characters: the baked faces are ASCII only, and a hairline drawn at the
// pixel grid stays crisp at any of the sizes the chrome uses.
fn (mut d Desktop) draw_builtin_glyph(path string, x int, y int, w int, h int, color u32) {
	if !path.starts_with('builtin:') {
		return
	}
	name := path[8..]
	cx := x + w / 2
	cy := y + h / 2
	// The glyph box is a fixed fraction of the button so the three symbols
	// share one optical size.
	half := if w < h { w / 5 } else { h / 5 }

	match name {
		'minimize' {
			d.canvas.fill_rect(cx - half, cy, 2 * half, 1, color)
		}
		'maximize' {
			d.canvas.stroke_round_rect(cx - half, cy - half, 2 * half, 2 * half, 1, color,
				255)
		}
		'restore' {
			// Two offset outlines, the back one clipped by the front's fill.
			d.canvas.stroke_round_rect(cx - half + 2, cy - half - 1, 2 * half - 1, 2 * half - 1,
				1, color, 255)
			d.canvas.fill_rect(cx - half, cy - half + 2, 2 * half - 1, 2 * half - 1,
				d.surface_under(x, y))
			d.canvas.stroke_round_rect(cx - half, cy - half + 2, 2 * half - 1, 2 * half - 1,
				1, color, 255)
		}
		'close' {
			d.canvas.draw_line(cx - half, cy - half, cx + half, cy + half, color, 1)
			d.canvas.draw_line(cx + half, cy - half, cx - half, cy + half, color, 1)
		}
		// Application and file icons. These are filled shapes rather than
		// hairlines: they are read at a glance and at whatever size the
		// element gives them, not aligned to the pixel grid like the chrome's.
		'folder' {
			body := w * 4 / 5
			tall := h * 5 / 8
			left := cx - body / 2
			top := cy - tall / 2
			// The tab, then the body over it, so the two read as one shape.
			d.canvas.fill_round_rect(left, top - tall / 5, body * 2 / 5, tall / 2, 2,
				color)
			d.canvas.fill_round_rect(left, top, body, tall, 3, color)
		}
		'file' {
			body := w * 3 / 5
			tall := h * 3 / 4
			left := cx - body / 2
			top := cy - tall / 2
			fold := body / 3
			d.canvas.fill_round_rect(left, top, body, tall, 2, color)
			// A dog-ear, punched out of the corner in the surface behind it.
			d.canvas.fill_rect(left + body - fold, top, fold, fold, d.surface_under(x,
				y))
		}
		'calculator' {
			body := w * 3 / 5
			tall := h * 3 / 4
			left := cx - body / 2
			top := cy - tall / 2
			d.canvas.fill_round_rect(left, top, body, tall, 3, color)
			// The display, and two rows of keys, punched back out.
			behind := d.surface_under(x, y)
			d.canvas.fill_rect(left + 3, top + 3, body - 6, tall / 4, behind)
			key := (body - 6) / 4
			for row in 0 .. 2 {
				for column in 0 .. 3 {
					d.canvas.fill_rect(left + 3 + column * key, top + tall / 2 + row * key,
						key - 2, key - 2, behind)
				}
			}
		}
		else {}
	}
}

// surface_under samples the canvas so the restore glyph's front square can
// mask the back one without knowing which title bar shade is behind it.
fn (d &Desktop) surface_under(x int, y int) u32 {
	if x < 0 || y < 0 || x >= d.canvas.width || y >= d.canvas.height {
		return title_active_bg
	}
	return unsafe { d.canvas.pixels[y * d.canvas.stride + x] }
}

// The pointer is drawn last, over everything, from a small mask: '#' is the
// outline that keeps the arrow visible on a light window, '.' the fill.
const cursor_mask = [
	'#           ',
	'##          ',
	'#.#         ',
	'#..#        ',
	'#...#       ',
	'#....#      ',
	'#.....#     ',
	'#......#    ',
	'#.......#   ',
	'#........#  ',
	'#.....####  ',
	'#..#..#     ',
	'#.# #..#    ',
	'##  #..#    ',
	'#    #..#   ',
	'     #..#   ',
	'      #..#  ',
	'      #..#  ',
	'       ##   ',
]

fn (mut d Desktop) draw_cursor() {
	if !d.pointer_present {
		return
	}
	for row, line in cursor_mask {
		for col := 0; col < line.len; col++ {
			match line[col] {
				`#` { d.canvas.blend_pixel(d.pointer_x + col, d.pointer_y + row, cursor_edge, 255) }
				`.` { d.canvas.blend_pixel(d.pointer_x + col, d.pointer_y + row, cursor_fill, 255) }
				else {}
			}
		}
	}
}
