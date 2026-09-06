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
	d.paint_wallpaper()
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
	floating := depth == 1 && el.id.starts_with('win.')
	if floating {
		saved := d.canvas.clip
		d.canvas.clip = Clip{
			x: 0
			y: 0
			w: d.canvas.width
			h: d.canvas.height
		}
		d.canvas.drop_shadow(x, y, w, h, radius, 7, d.theme().shadow_alpha)
		d.canvas.restore_clip(saved)
	}
	if radius > 0 {
		d.canvas.fill_round_rect(x, y, w, h, radius, el.box.bg)
	} else {
		d.canvas.fill_rect(x, y, w, h, el.box.bg)
	}
	if floating {
		d.canvas.stroke_round_rect(x, y, w, h, radius, d.theme().window_edge, 190)
	}

	// A title bar is shaded down its height. Like the shadow above, this is
	// keyed off the window manager's own id: the effect belongs to the chrome,
	// not to anything a view can declare. The element carries the top colour
	// and the theme supplies the one to fade to, so a flat bar is a theme that
	// names the same colour twice and costs nothing extra.
	theme := d.theme()
	if el.id.ends_with('.titlebar') {
		bottom := if el.box.bg == theme.title_active_bg {
			theme.title_active_bg2
		} else {
			theme.title_inactive_bg2
		}
		if bottom != el.box.bg {
			d.canvas.vertical_gradient(x, y, w, h, el.box.bg, bottom)
		}
	}
}

// paint_wallpaper blits the cached backdrop, building it first if the setting
// changed. Both kinds end up in the same buffer, so the frame after is a
// straight copy whichever was chosen.
fn (mut d Desktop) paint_wallpaper() {
	width := d.canvas.width
	height := d.canvas.height
	if !d.wallpaper_valid || d.wallpaper.len != width * height {
		d.wallpaper = []u32{len: width * height}
		mut done := false
		if d.settings.wallpaper_image >= 0 {
			images := list_wallpapers()
			if d.settings.wallpaper_image < images.len {
				if image := load_raw_image(images[d.settings.wallpaper_image].file) {
					image.scale_into(mut d.wallpaper, width, height)
					done = true
				}
			}
		}
		if !done {
			// A colour, or the fallback when an image will not load.
			index := if d.settings.wallpaper_color < wallpaper_colors.len {
				d.settings.wallpaper_color
			} else {
				0
			}
			color := wallpaper_colors[index]
			for y in 0 .. height {
				shade := mix(color.top, color.bottom, u32(y * 255 / height))
				row := y * width
				for x in 0 .. width {
					d.wallpaper[row + x] = shade
				}
			}
		}
		d.wallpaper_valid = true
	}

	unsafe {
		C.memcpy(d.canvas.pixels, d.wallpaper.data, usize(width * height * 4))
	}
}

fn (mut d Desktop) draw_label(el ui2.Element, x int, y int, w int, h int) {
	if el.text.len == 0 {
		return
	}
	face := d.face_for(el.text_style)
	text := face.truncate(el.text, w)
	baseline_y := y + (h - face.line_height) / 2
	text_width := face.text_width(text)
	mut text_x := x
	match el.text_style.align {
		.left { text_x = x }
		.center { text_x = x + (w - text_width) / 2 }
		.right { text_x = x + w - text_width }
	}
	if el.text_style.background_color != 0 {
		// Padded, so the run is not touched by whatever it is sitting on.
		d.canvas.fill_rect(text_x - 6, y + 2, text_width + 12, h - 4, el.text_style.background_color)
	}
	if el.text_style.shadow {
		// A shortcut's label sits on a wallpaper that could be any photograph,
		// so it cannot rely on contrast with what is behind it. The shadow's
		// colour comes from the text's own: dark text is backed with light and
		// light text with dark, which keeps one of the two legible whatever the
		// picture does.
		d.canvas.draw_text(face, text_x + 1, baseline_y + 1, text, shadow_for(el.text_style.color))
	}
	d.canvas.draw_text(face, text_x, baseline_y, text, el.text_style.color)
}

// shadow_for picks a backing colour from a text colour's brightness. The
// weights are the usual approximation of perceived luminance.
fn shadow_for(color u32) u32 {
	luminance := (77 * ((color >> 16) & 0xff) + 151 * ((color >> 8) & 0xff) + 28 * (color & 0xff)) >> 8
	return if luminance > 128 { u32(0x000000) } else { u32(0xffffff) }
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
		'menu' {
			// Where the Apple menu's logo would be. A plain mark: the atlas has
			// no such glyph, and an approximation of someone's logo is worse
			// than an honest dot.
			d.canvas.fill_circle(cx, cy, if w < h { w / 3 } else { h / 3 }, color)
		}
		'settings' {
			// A gear: a disc with a hole, and teeth around it.
			outer := if w < h { w * 3 / 8 } else { h * 3 / 8 }
			tooth := outer / 2
			for i in 0 .. 4 {
				// Four teeth on the axes, and four on the diagonals at 3/4 the
				// reach, which is close enough to a gear at icon size.
				dx := [1, 0, -1, 0][i] * outer
				dy := [0, 1, 0, -1][i] * outer
				d.canvas.fill_rect(cx + dx - tooth / 2, cy + dy - tooth / 2, tooth, tooth,
					color)
			}
			d.canvas.fill_circle(cx, cy, outer, color)
			d.canvas.fill_circle(cx, cy, outer / 2, d.surface_under(x, y))
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
		return d.theme().title_active_bg
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
