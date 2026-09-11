// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
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
//     renderer carries itself, because the target has no image files. `xwd:`
//     names a live off-screen Xvfb surface hosted inside a native window.
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

// An icon sharing a control with a label is drawn at this size.
const button_icon_size = 16

// Geometry tables used by builtin glyphs. Keeping them at module scope avoids
// constructing heap-backed array literals for every icon on every redraw.
const gear_tooth_x = [1, 0, -1, 0]
const gear_tooth_y = [0, 1, 0, -1]
const activity_bar_shares = [2, 3, 5]

// Word 2013's unselected tabs are the only text drawn into its missing
// Direct2D backing layer. Their source-space centres are stable because Word
// opens in a fixed private X desktop. Repainting the labels after the XWD has
// been scaled gives them Vinix's native antialiased text at every window size.
const office2013_tab_labels = ['INSERT', 'DESIGN', 'PAGE LAYOUT', 'REFERENCES', 'MAILINGS', 'REVIEW',
	'VIEW']
const office2013_tab_centers = [157, 224, 310, 411, 499, 580, 638]
const office2013_tab_top = 27
const office2013_tab_height = 22
const office2013_tab_font_size = 11
const office2013_tab_color = u32(0x303030)

// Text carrying this private id was formatted solely for the current element
// tree. free_tree releases it after the frame; all other element strings are
// literals or model-owned caches.
const frame_owned_text_id = '__vinix.frame.owned_text'

// The largest builders today are bounded by the battery-history capacity.
// Keep enough power-of-two buckets for those arrays (up to 1024 elements), so
// an unusually tall window cannot outgrow the last slot and allocate while it
// appends on every frame.
const frame_element_pool_buckets = 11

struct FrameElementSlot {
mut:
	elements []ui2.Element
}

struct FrameElementPool {
mut:
	slots [frame_element_pool_buckets][]FrameElementSlot
	used  [frame_element_pool_buckets]int
}

__global frame_element_pool = FrameElementPool{}

// begin_frame_elements makes every backing array from the preceding frame
// available again. Element trees are strictly frame-local: rendering and hit
// collection finish before the next tree is built.
fn begin_frame_elements() {
	for bucket in 0 .. frame_element_pool_buckets {
		frame_element_pool.used[bucket] = 0
	}
}

// Element lists are short-lived frame builders. Reuse their backing storage
// instead of asking libc to mmap and munmap the same large Element arrays once
// per second forever. Capacities are bucketed by powers of two so a window
// being hidden does not make later call sites inherit an undersized slot.
fn frame_elements(capacity int) []ui2.Element {
	mut bucket := 0
	mut bucket_capacity := 1
	for bucket + 1 < frame_element_pool_buckets && bucket_capacity < capacity {
		bucket++
		bucket_capacity *= 2
	}
	index := frame_element_pool.used[bucket]
	frame_element_pool.used[bucket]++
	if index >= frame_element_pool.slots[bucket].len {
		if frame_element_pool.slots[bucket].cap == 0 {
			// A fixed array of dynamic arrays is zero-initialized by V3, so its
			// entries do not yet carry FrameElementSlot's element size. Give the
			// bucket a real array before its first append.
			frame_element_pool.slots[bucket] = []FrameElementSlot{cap: 4}
			unsafe { frame_element_pool.slots[bucket].flags |= .noslices }
		}
		frame_element_pool.slots[bucket] << FrameElementSlot{
			elements: []ui2.Element{cap: bucket_capacity}
		}
	}
	// The final bucket is also the escape hatch for a builder larger than its
	// nominal power of two. Grow the pool-owned array itself, once, so appends
	// cannot move only the borrowed copy and leave the pool pointing at the old
	// storage.
	if frame_element_pool.slots[bucket][index].elements.cap < capacity {
		unsafe { frame_element_pool.slots[bucket][index].elements.free() }
		frame_element_pool.slots[bucket][index].elements = []ui2.Element{cap: capacity}
	}
	mut elements := []ui2.Element{}
	unsafe {
		elements = frame_element_pool.slots[bucket][index].elements
		elements.len = 0
		elements.flags |= .nofree
	}
	// The pool owns this buffer. free_tree still walks it to release strings,
	// but array_free must leave the backing storage for the next frame.
	return elements
}

// frame_child covers the common nested-control case without constructing a
// fresh one-element array literal every time the parent is rebuilt.
fn frame_child(element ui2.Element) []ui2.Element {
	mut children := frame_elements(1)
	children << element
	return children
}

// face_for picks the baked face closest to what a style asks for: the right
// weight first, then the nearest size. Nothing is scaled — a bitmap atlas
// stretched looks far worse than one a couple of pixels off — so a style
// asking for a size nothing was baked at gets the neighbour instead.
fn (d &Desktop) face_for(style ui2.TextStyle) &FontFace {
	wanted := int(style.size)
	// ui2's font_family, honoured for the one family the atlas has a second
	// set of glyphs for. A terminal that does not line its columns up is not a
	// terminal, so the match on it outranks both weight and size.
	want_mono := style.font_family == 'mono'
	mut best := 0
	mut best_score := 1 << 30
	for i, face in d.fonts {
		mut score := abs_int(face.size - wanted)
		if face.mono != want_mono {
			score += 100000
		}
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
// strings copied from a remote application are frame-owned; local strings are
// literals or model-owned caches and outlive the tree on purpose.
fn free_tree(el ui2.Element) {
	for child in el.children {
		free_tree(child)
	}
	if el.key == remote_owned_element_key {
		unsafe {
			if el.id.len > 0 { el.id.free() }
			if el.action_id.len > 0 { el.action_id.free() }
			if el.text.len > 0 { el.text.free() }
			if el.image_path.len > 0 { el.image_path.free() }
			if el.text_style.font_family.len > 0 { el.text_style.font_family.free() }
		}
	} else if el.id == frame_owned_text_id {
		unsafe { el.text.free() }
	}
	if el.children.cap > 0 {
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
			if el.image_path.starts_with(vinix_surface_image_prefix) {
				d.canvas.draw_vinix_surface(el.image_path[vinix_surface_image_prefix.len..], x,
					y, w, h)
			} else if el.image_path.starts_with(office_xwd_image_prefix) {
				drawn, has_ribbon := d.canvas.draw_office_xwd_surface(el.image_path[office_xwd_image_prefix.len..], x, y, w, h)
				if drawn && has_ribbon {
					d.draw_office2013_tab_labels(x, y, w, h)
				}
			} else if el.image_path.starts_with(xwd_image_prefix) {
				d.canvas.draw_xwd_surface(el.image_path[xwd_image_prefix.len..], x, y, w, h)
			} else {
				d.draw_builtin_glyph(el.image_path, x, y, w, h, el.text_style.color)
			}
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

fn (mut d Desktop) draw_office2013_tab_labels(x int, y int, width int, height int) {
	if width <= 0 || height <= 0 {
		return
	}
	requested_size := (office2013_tab_font_size * height + wine_word2013_surface_height / 2) / wine_word2013_surface_height
	face := d.face_for(ui2.TextStyle{
		size: f64(requested_size)
	})
	top := y + office2013_tab_top * height / wine_word2013_surface_height
	strip_height := office2013_tab_height * height / wine_word2013_surface_height
	text_y := top + (strip_height - face.line_height) / 2
	for index, label in office2013_tab_labels {
		center := x + office2013_tab_centers[index] * width / wine_word2013_surface_width
		d.canvas.draw_text(face, center - face.text_width(label) / 2, text_y, label, office2013_tab_color)
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
	floating := depth == 1 && (el.id.starts_with('win.') || el.id == switcher_panel_id
		|| el.id == action_start_panel)
	// The switcher is drawn through: it covers the middle of the screen for as
	// long as a key is held, and what it covers should stay legible behind it.
	// Alpha is not something a ui2 box style can declare, so like the shadow
	// below it is keyed off the window manager's own id.
	translucent := el.id == switcher_panel_id
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
	if translucent {
		d.canvas.blend_round_rect(x, y, w, h, radius, el.box.bg, switcher_alpha)
	} else if radius > 0 {
		d.canvas.fill_round_rect(x, y, w, h, radius, el.box.bg)
	} else {
		d.canvas.fill_rect(x, y, w, h, el.box.bg)
	}
	if floating {
		edge := if translucent {
			switcher_edge
		} else if el.id == action_start_panel {
			u32(0x9db3cc)
		} else {
			d.theme().window_edge
		}
		d.canvas.stroke_round_rect(x, y, w, h, radius, edge, 190)
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
			// White on all of them: no colour offered here is light enough to
			// need a second answer. The mark is rasterised into the cache with
			// the gradient, which is why a wallpaper the desktop draws
			// thousands of times is still one memcpy per frame.
			draw_logo(mut d.wallpaper, width, height, logo_color)
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
	text, text_owned := face.truncate(el.text, w)
	baseline_y := y + (h - face.line_height) / 2
	text_width := face.text_width(text)
	mut text_x := x
	match el.text_style.align {
		.left {
			text_x = x
		}
		.center {
			text_x = x + (w - text_width) / 2
		}
		.right {
			text_x = x + w - text_width
		}
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
	if text_owned {
		unsafe { text.free() }
	}
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
			d.draw_builtin_glyph(el.image_path, x + text_inset, y + (h - icon) / 2, icon, icon, el.text_style.color)
			text_x += icon + 6
			text_w -= icon + 6
		}
	}

	if el.text.len == 0 {
		return
	}
	face := d.face_for(el.text_style)
	inner := if el.text_style.align == .center && el.image_path.len == 0 { w } else { text_w }
	text, text_owned := face.truncate(el.text, inner)
	text_y := y + (h - face.line_height) / 2
	// A label sharing the control with an icon is always placed after it; the
	// declared alignment only decides where a label on its own sits.
	if el.image_path.len > 0 {
		d.canvas.draw_text(face, text_x, text_y, text, el.text_style.color)
		if text_owned {
			unsafe { text.free() }
		}
		return
	}
	match el.text_style.align {
		.left { d.canvas.draw_text(face, x + text_inset, text_y, text, el.text_style.color) }
		.center { d.canvas.draw_text_centered(face, x, text_y, w, text, el.text_style.color) }
		.right {
			d.canvas.draw_text_right(face, x + w - text_inset, text_y, text, el.text_style.color)
		}
	}
	if text_owned {
		unsafe { text.free() }
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
	defer {
		// String slicing owns its result in V's manual-free mode.
		unsafe { name.free() }
	}
	cx := x + w / 2
	cy := y + h / 2
	// The glyph box is a fixed fraction of the button so the three symbols
	// share one optical size.
	half := if w < h { w / 5 } else { h / 5 }

	match name {
		'vinix' {
			// The brand mark is the exact V polygon from vinix-logo.svg. In
			// particular, its outer taper and narrow inner notch carry through
			// to the lower-left Start button.
			d.canvas.draw_vinix_v(x, y, w, h, color)
		}
		'minimize' {
			d.canvas.fill_rect(cx - half, cy, 2 * half, 1, color)
		}
		'maximize' {
			d.canvas.stroke_round_rect(cx - half, cy - half, 2 * half, 2 * half, 1, color, 255)
		}
		'restore' {
			// Two offset outlines, the back one clipped by the front's fill.
			d.canvas.stroke_round_rect(cx - half + 2, cy - half - 1, 2 * half - 1, 2 * half - 1, 1, color, 255)
			d.canvas.fill_rect(cx - half, cy - half + 2, 2 * half - 1, 2 * half - 1, d.surface_under(x, y))
			d.canvas.stroke_round_rect(cx - half, cy - half + 2, 2 * half - 1, 2 * half - 1, 1, color, 255)
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
			d.canvas.fill_round_rect(left, top - tall / 5, body * 2 / 5, tall / 2, 2, color)
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
			d.canvas.fill_rect(left + body - fold, top, fold, fold, d.surface_under(x, y))
		}
		'window' {
			// What stands for a window with no application behind it to lend
			// an icon. A frame with a filled title bar: the least that reads as
			// a window rather than as a plain block.
			body := w * 3 / 4
			tall := h * 5 / 8
			left := cx - body / 2
			top := cy - tall / 2
			bar := tall / 3
			d.canvas.fill_round_rect(left, top, body, tall, 3, color)
			d.canvas.fill_rect(left + 2, top + bar, body - 4, tall - bar - 2, d.surface_under(x, y))
		}
		'menu' {
			// Where the Apple menu's logo would be. A plain mark: the atlas has
			// no such glyph, and an approximation of someone's logo is worse
			// than an honest dot.
			d.canvas.fill_circle(cx, cy, if w < h { w / 3 } else { h / 3 }, color)
		}
		'terminal' {
			body := w * 3 / 4
			tall := h * 3 / 5
			left := cx - body / 2
			top := cy - tall / 2
			d.canvas.fill_round_rect(left, top, body, tall, 2, color)
			// A prompt chevron and its cursor, punched back out.
			behind := d.surface_under(x, y)
			arm := tall / 4
			d.canvas.draw_line(left + 4, top + arm, left + 4 + arm, top + tall / 2, behind, 2)
			d.canvas.draw_line(left + 4 + arm, top + tall / 2, left + 4, top + tall - arm, behind, 2)
			d.canvas.fill_rect(left + 6 + 2 * arm, top + tall - arm - 2, body / 3, 2, behind)
		}
		'browser' {
			// A generic globe rather than an approximation of Mozilla's mark. The
			// application name supplies the identity; the glyph only says web.
			radius := if w < h { w * 3 / 8 } else { h * 3 / 8 }
			behind := d.surface_under(x, y)
			d.canvas.fill_circle(cx, cy, radius, color)
			d.canvas.fill_circle(cx, cy, radius - 2, behind)
			d.canvas.draw_line(cx - radius + 2, cy, cx + radius - 2, cy, color, 1)
			d.canvas.draw_line(cx, cy - radius + 2, cx, cy + radius - 2, color, 1)
			d.canvas.draw_line(cx - radius / 2, cy - radius + 3, cx - radius / 2, cy + radius - 3, color, 1)
			d.canvas.draw_line(cx + radius / 2, cy - radius + 3, cx + radius / 2, cy + radius - 3, color, 1)
		}
		'block' {
			// A compact voxel: the outer square is a block face and the three
			// interior edges hint at its top and two sides at every icon size.
			body := if w < h { w * 3 / 4 } else { h * 3 / 4 }
			left := cx - body / 2
			top := cy - body / 2
			behind := d.surface_under(x, y)
			d.canvas.fill_round_rect(left, top, body, body, 2, color)
			d.canvas.fill_rect(left + 2, top + 2, body - 4, body - 4, behind)
			d.canvas.draw_line(left + 1, top + body / 3, cx, top + 2 * body / 3, color, 2)
			d.canvas.draw_line(left + body - 1, top + body / 3, cx, top + 2 * body / 3, color, 2)
			d.canvas.draw_line(cx, top + 2 * body / 3, cx, top + body - 1, color, 2)
		}
		'settings' {
			// A gear: a disc with a hole, and teeth around it.
			outer := if w < h { w * 3 / 8 } else { h * 3 / 8 }
			tooth := outer / 2
			for i in 0 .. 4 {
				// Four teeth on the axes, and four on the diagonals at 3/4 the
				// reach, which is close enough to a gear at icon size.
				dx := gear_tooth_x[i] * outer
				dy := gear_tooth_y[i] * outer
				d.canvas.fill_rect(cx + dx - tooth / 2, cy + dy - tooth / 2, tooth, tooth, color)
			}
			d.canvas.fill_circle(cx, cy, outer, color)
			d.canvas.fill_circle(cx, cy, outer / 2, d.surface_under(x, y))
		}
		'activity' {
			// A bar chart: three columns of different heights standing on a
			// baseline. It is the one shape that reads as "what is happening
			// right now" at the size a shortcut gets.
			body := w * 3 / 5
			tall := h * 3 / 5
			left := cx - body / 2
			bottom := cy + tall / 2
			bar := body / 4
			// Ascending rather than arbitrary, so the glyph has a direction
			// and does not read as a barcode.
			for i, share in activity_bar_shares {
				height := tall * share / 5
				d.canvas.fill_round_rect(left + i * (bar + bar / 2), bottom - height, bar, height, 1, color)
			}
			d.canvas.fill_rect(left, bottom, body, 1, color)
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
					d.canvas.fill_rect(left + 3 + column * key, top + tall / 2 + row * key, key - 2, key - 2, behind)
				}
			}
		}
		'editor' {
			body := w * 3 / 5
			tall := h * 3 / 4
			left := cx - body / 2
			top := cy - tall / 2
			d.canvas.fill_round_rect(left, top, body, tall, 2, color)
			behind := d.surface_under(x, y)
			for row in 0 .. 3 {
				line_width := if row == 2 { body / 2 } else { body - 8 }
				d.canvas.fill_rect(left + 4, top + 5 + row * (tall - 7) / 4, line_width, 2, behind)
			}
		}
		'calendar' {
			body := w * 3 / 4
			tall := h * 2 / 3
			left := cx - body / 2
			top := cy - tall / 2
			d.canvas.fill_round_rect(left, top, body, tall, 3, color)
			behind := d.surface_under(x, y)
			d.canvas.fill_rect(left + 2, top + tall / 3, body - 4, tall - tall / 3 - 2, behind)
			for column in 0 .. 3 {
				for row in 0 .. 2 {
					d.canvas.fill_rect(left + 4 + column * (body - 6) / 3, top + tall / 2 + row * (tall - 5) / 4, 2, 2, color)
				}
			}
		}
		'clock' {
			radius := if w < h { w * 3 / 8 } else { h * 3 / 8 }
			d.canvas.fill_circle(cx, cy, radius, color)
			d.canvas.fill_circle(cx, cy, radius - 2, d.surface_under(x, y))
			d.canvas.draw_line(cx, cy, cx, cy - radius / 2, color, 2)
			d.canvas.draw_line(cx, cy, cx + radius / 2, cy + radius / 3, color, 2)
			d.canvas.fill_circle(cx, cy, 2, color)
		}
		'camera' {
			body_width := w * 4 / 5
			body_height := h * 3 / 5
			left := cx - body_width / 2
			top := cy - body_height / 2 + h / 12
			behind := d.surface_under(x, y)
			// Lens housing and the small viewfinder bump are one compact,
			// filled silhouette, legible at both shortcut and title sizes.
			d.canvas.fill_round_rect(left, top, body_width, body_height, 3, color)
			d.canvas.fill_round_rect(left + body_width / 6, top - body_height / 4, body_width / 3, body_height / 3, 2, color)
			lens := if body_width < body_height { body_width / 4 } else { body_height / 3 }
			d.canvas.fill_circle(cx, top + body_height / 2, lens, behind)
			d.canvas.fill_circle(cx, top + body_height / 2, if lens > 2 { lens - 2 } else { 1 }, color)
		}
		'search' {
			radius := if w < h { w / 4 } else { h / 4 }
			d.canvas.fill_circle(cx - 2, cy - 2, radius, color)
			if radius > 2 {
				d.canvas.fill_circle(cx - 2, cy - 2, radius - 2, d.surface_under(x, y))
			}
			d.canvas.draw_line(cx + radius / 2, cy + radius / 2, cx + radius, cy + radius, color, 2)
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
// A one-pixel dark halo goes around that outline. It makes the guest cursor
// unmissable over both the pale wordmark and the dark wallpaper without
// changing its hit position or needing a host-side cursor.
const cursor_halo = u32(0x000000)
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
	// Keep a visible cursor even while /dev/pointer is between reports (or is
	// temporarily unavailable). The desktop has a useful initial position at
	// its centre, and hiding that position makes a working QEMU tablet appear
	// to have no cursor at all until its next complete report arrives.
	// Paint the halo first so the arrow retains its crisp dark outline. The
	// framebuffer can be presented at 200%, where this becomes a useful
	// two-physical-pixel boundary instead of a faint single-pixel glyph.
	for row, line in cursor_mask {
		for col := 0; col < line.len; col++ {
			if line[col] == ` ` {
				continue
			}
			for halo_y in -1 .. 2 {
				for halo_x in -1 .. 2 {
					if halo_x == 0 && halo_y == 0 {
						continue
					}
					d.canvas.blend_pixel(d.pointer_x + col + halo_x, d.pointer_y + row + halo_y, cursor_halo, 232)
				}
			}
		}
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
