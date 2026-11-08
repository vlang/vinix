// SPDX-License-Identifier: MIT
@[has_globals]
module ui2

import gg
import crypto.sha256
import math
import os

__global vox_native_elements = []Element{}
__global vox_native_action = EventFn(unsafe { nil })
__global vox_native_text = []Element{}
__global vox_native_text_cache = []Element{}
__global vox_native_text_count = 0
__global vox_native_button_cache = []Element{}
__global vox_native_button_count = 0
__global vox_native_wheel = fn (_ f64, _ f64, _ f64, _ f64) bool { return false }
__global vox_native_vector_cache = map[string]string{}
__global vox_native_vector_paths = map[string]string{}
__global vox_native_icon_paths = map[string]string{}

pub fn native_embedded_elements() []Element {
	mut elements := vox_native_text.clone()
	elements << vox_native_elements
	vox_native_text.clear()
	vox_native_text_count = 0
	vox_native_button_count = 0
	return elements
}

pub fn native_embedded_action(id string) {
	if vox_native_action != unsafe { nil } { vox_native_action(id) }
}

pub fn native_chrome_ready() bool { return vox_native_elements.len > 0 }

pub fn native_reset_targets() {
	vinix_targets = map[string]VinixTarget{}
	vinix_hit_targets = []VinixTarget{}
	vinix_scroll_targets = []VinixScrollTarget{}
}

fn native_scroll_state(id string, value f64) {
	previous := gg.native_state_enter()
	vinix_scroll_values[id] = value
	gg.native_state_leave(previous)
}

pub fn draw_embedded_elements(_ &gg.Context, elements []Element, images map[string]int, handler EventFn) {
	vox_native_elements = elements.map(native_element(it, 0xffffff, images))
	vox_native_action = handler
}

pub fn native_add_text(x int, y int, text string, size int, color u32, bold bool, italic bool, mono bool, clip gg.Rect) {
	index := vox_native_text_count
	if index >= vox_native_text_cache.len {
		vox_native_text_cache << view('native-text-clip-${index}', rect(0, 0, 0, 0), BoxStyle{ transparent: true }, [
			label('native-text-${index}', text.clone(), rect(0, 0, 0, 0), TextStyle{}),
		])
	}
	previous := vox_native_text_cache[index].children[0]
	// This child is the cache's reusable label, owned by the host arena.
	mut cached_children := unsafe { vox_native_text_cache[index].children }
	cached_children[0] = Element{
		...previous
		text:       if previous.text == text { previous.text } else { text.clone() }
		frame:      rect(x - clip.x, y - clip.y, math.max(0, int(clip.x + clip.width) - x), native_text_line_height(size, bold, mono))
		text_style: TextStyle{
			size:        f64(size)
			color:       color
			bold:        bold
			italic:      italic
			font_family: if mono {
				'mono'
			} else {
				''
			}
			valign:      .top
		}
	}
	vox_native_text_cache[index] = Element{ ...vox_native_text_cache[index], frame: rect(clip.x, clip.y, clip.width, clip.height) }
	vox_native_text << vox_native_text_cache[index]
	vox_native_text_count++
}

pub fn native_add_document_button(x f32, y f32, width f32, height f32, enabled bool, clip gg.Rect) {
	// An empty action/id keeps this visual control out of UI2's input targets.
	// The browser continues receiving raw pointer events and dispatches DOM
	// click/focus/keyboard behavior against its original layout box.
	index := vox_native_button_count
	if index >= vox_native_button_cache.len {
		vox_native_button_cache << view('', rect(0, 0, 0, 0), BoxStyle{ transparent: true }, [
			Element{ ...button('', '', rect(0, 0, 0, 0), BoxStyle{}, TextStyle{}), native_style: true },
		])
	}
	mut children := unsafe { vox_native_button_cache[index].children }
	children[0] = Element{
		...children[0]
		frame: rect(x - clip.x, y - clip.y, width, height)
		box: BoxStyle{ bg: if enabled { u32(0xe4e9f1) } else { u32(0xf3f5f9) }, radius: 4 }
		enabled: enabled
	}
	vox_native_button_cache[index] = Element{ ...vox_native_button_cache[index], frame: rect(clip.x, clip.y, clip.width, clip.height) }
	vox_native_text << vox_native_button_cache[index]
	vox_native_button_count++
}

pub fn install_embedded_wheel(handler fn (f64, f64, f64, f64) bool) { vox_native_wheel = handler }

pub fn embedded_elements_event(_ &gg.Event) bool { return false }

pub fn select_embedded_textbox() {
	focus('address')
	mut editor := vinix_text_editors['address'] or { text_editor(text('address')) }
	editor.select_all()
	vinix_text_editors['address'] = editor
}

pub fn select_embedded_text_range(id string, start int, end int) {
	mut editor := vinix_text_editors[id] or { text_editor(text(id)) }
	editor.set_selection(start, end)
	vinix_text_editors[id] = editor
}

pub fn embedded_text_composing(_ string) bool { return false }

pub fn blur_embedded_textbox() { vinix_focused = '' }

pub fn copy_embedded_text(_ string) {}

pub fn embedded_host_action(action string) { if action == 'close' { native_quit() } }

pub fn native_quit() { vinix_running = false }

fn close_menu_bar() {}

pub fn native_release_resources() {
	vox_native_elements = []Element{}
	vox_native_action = EventFn(unsafe { nil })
	vox_native_text = []Element{}
	vox_native_text_cache = []Element{}
	vox_native_text_count = 0
	vox_native_button_cache = []Element{}
	vox_native_button_count = 0
	for _, path in vox_native_vector_paths { os.rm(path) or {} }
	for _, path in vox_native_icon_paths { os.rm(path) or {} }
	vox_native_vector_paths.clear()
	vox_native_vector_cache.clear()
	vox_native_icon_paths.clear()
}

fn native_icon_path(source string, width int, height int, background u32, images map[string]int) string {
	if source.starts_with('builtin:') || source.starts_with('vinix-surface:') { return source }
	id := images[source] or { return '' }
	key := '${id}:${width}:${height}:${background}'
	if path := vox_native_icon_paths[key] { return 'vinix-surface:' + path }
	path := '/tmp/vox-${os.getpid()}-icon-' + sha256.sum(key.bytes()).hex() + '.surface'
	if !gg.native_publish_icon(id, path, width, height, background) { return '' }
	vox_native_icon_paths[key.clone()] = path
	return 'vinix-surface:' + path
}

fn native_element(source Element, inherited u32, images map[string]int) Element {
	// Vox owns its frame. Keep its controls and let Vinix perform the scoped
	// window actions instead of routing them to platform-specific host code.
	if source.id in ['window-close', 'window-minimize', 'window-zoom'] {
		action := match source.id {
			'window-close' { window_action_close }
			'window-minimize' { window_action_minimize }
			else { window_action_maximize }
		}
		return Element{
			...source
			action_id: action
			native_style: false
		}
	}
	background := if source.box.transparent {
		inherited
	} else {
		source.box.bg
	}
	content_background := if source.vector.fill_enabled && source.vector.points.len > 0 { source.vector.fill } else { background }
	mut children := source.children.map(native_element(it, content_background, images))
	if source.kind == .image {
		return Element{ ...source, image_path: native_icon_path(source.image_path, int(source.frame.width), int(source.frame.height), background, images), children: children }
	}
	if source.id == 'address-info' {
		return Element{ ...source, text: 'i', text_style: TextStyle{ ...source.text_style, bold: true, align: .center } }
	}
	if source.id.starts_with('tab-close:') {
		// Keep the classic unboxed close mark, using the compositor glyph so
		// it remains legible with the desktop's available font coverage.
		children << Element{ ...image(source.id + '-icon', 'builtin:close', rect(0, 0, source.frame.width, source.frame.height)), text_style: source.text_style }
		return Element{ ...source, text: '', native_style: false, children: children }
	}
	if source.kind == .button && (source.text != '' || source.image_path != '') && !source.id.starts_with('tab-close:') {
		return native_button(source, children, images)
	}
	if source.id == 'tab-strip' {
		return Element{ ...source, action_id: window_action_move, draggable: true,
			children: children }
	}
	if source.vector.points.len < 2 { return Element{ ...source, children: children } }
	key := '${source.frame.width}:${source.frame.height}:${background}:${source.vector}'
	path := '/tmp/vox-${os.getpid()}-' + sha256.sum(source.id.bytes()).hex() + '.surface'
	if (vox_native_vector_cache[source.id] or { '' }) != key {
		mut points := []f32{cap: source.vector.points.len * 2}
		for point in source.vector.points { points << [f32(point.x), f32(point.y)] }
		gg.native_raster_vector(path, int(math.ceil(source.frame.width)), int(math.ceil(source.frame.height)),
			background, points, source.vector.closed, source.vector.fill_enabled, source.vector.fill,
			source.vector.stroke, source.vector.stroke_width)
		vox_native_vector_cache[source.id] = key
		vox_native_vector_paths[source.id] = path
	}
	children.insert(0, image(source.id + '-vector', 'vinix-surface:' + path, rect(0, 0, source.frame.width, source.frame.height)))
	return Element{ ...source, children: children }
}

fn native_button(source Element, children_ []Element, images map[string]int) Element {
	background := if source.enabled { u32(0xe4e9f1) } else { u32(0xf3f5f9) }
	color := if source.enabled { u32(0x30394a) } else { u32(0x9aa5b4) }
	mut children := children_.clone()
	mut caption := source.text
	mut icon := match source.id {
		'back' { 'builtin:arrow_left' }
		'forward' { 'builtin:arrow_right' }
		'history' { 'builtin:clock' }
		'tab-new' { 'builtin:zoom' }
		else {
			if source.id.starts_with('tab-close:') { 'builtin:close' } else { source.image_path }
		}
	}
	// Use geometry for reload, whose Unicode glyph is not in the desktop atlas.
	if source.id == 'reload' {
		mut points := []VectorPoint{}
		for step in 0 .. 33 {
			angle := math.pi / 4 + f64(step) * math.pi * 1.5 / 32
			points << VectorPoint{ x: 8 + 5 * math.cos(angle), y: 8 + 5 * math.sin(angle) }
		}
		points << [VectorPoint{ x: 12, y: 3 }, VectorPoint{ x: 12, y: 7 }, VectorPoint{ x: 8, y: 7 }]
		children << native_element(Element{
			...view('native-reload-icon', rect(3, 3, 16, 16), BoxStyle{ transparent: true }, [])
			vector: VectorPath{ points: points, closed: false, fill_enabled: false, stroke: color, stroke_width: 1.5 }
		}, background, images)
		caption = ''
	}
	if caption.starts_with('○ ') && icon == '' {
		caption = caption.all_after('○ ')
		icon = 'builtin:browser'
	}
	mut frame := source.frame
	if source.id == 'tab-new' { frame = rect(frame.x, 4, 24, 22) }
	icon_only := source.id in ['back', 'forward', 'history', 'tab-new'] || source.id.starts_with('tab-close:')
	// Vinix's builtin symbols include their own inset. Giving them the full
	// control bounds matches Files and keeps the tab close mark legible.
	image_frame := if icon_only {
		rect(0, 0, frame.width, frame.height)
	} else {
		embedded_button_image_frame(Element{ ...source, frame: frame, text: caption, button_image_size: 16 })
	}
	if icon != '' {
		path := native_icon_path(icon, int(image_frame.width), int(image_frame.height), background, images)
		children << Element{ ...image(source.id + '-icon', path, image_frame), text_style: TextStyle{ color: color } }
		if source.image_path != '' || source.id.starts_with('bookmark-open:') {
			left := image_frame.x + image_frame.width + 6
			children << label(source.id + '-caption', caption, rect(left, 0, math.max(0.0, frame.width - left - 5), frame.height), TextStyle{ ...source.text_style, font_family: '', color: color, align: .left })
		}
		caption = ''
	}
	return Element{
		...source
		frame:        frame
		text:         caption
		image_path:   ''
		vector:       VectorPath{}
		box:          BoxStyle{ bg: background, radius: 4 }
		text_style:   TextStyle{ ...source.text_style, font_family: '', color: color, align: .center }
		native_style: true
		children:     children
	}
}

pub fn native_pointer(kind int, button int, scroll int, x f64, y f64) {
	if target := vinix_hit_target_at(x, y) {
		_ = target
		return
	}
	gg.native_dispatch_pointer(kind, button, scroll, x, y)
}

pub fn native_key_input(input string) bool {
	key := vinix_normalized_key(input)
	parts := key.split('+')
	name := parts.last()
	mut modifiers := u32(0)
	if 'shift' in parts { modifiers |= 1 }
	if 'ctrl' in parts { modifiers |= 2 }
	if 'alt' in parts { modifiers |= 4 }
	if 'cmd' in parts { modifiers |= 8 }
	code := match name {
		'enter' { 257 }
		'backspace' { 259 }
		'tab' { 258 }
		'escape' { 256 }
		'left' { 263 }
		'right' { 262 }
		'up' { 265 }
		'down' { 264 }
		'home' { 268 }
		'end' { 269 }
		'page_up' { 266 }
		'page_down' { 267 }
		'forward_delete' { 261 }
		else {
			if name.runes().len == 1 { int(name.to_upper().runes()[0]) } else { 0 }
		}
	}
	vinix_key_consumed = false
	if vinix_key_event_handler != unsafe { nil } {
		vinix_key_event_handler(KeyEvent{
			code:  unsafe { KeyCode(code) }
			shift: modifiers & 1 != 0
			ctrl:  modifiers & 2 != 0
			alt:   modifiers & 4 != 0
			cmd:   modifiers & 8 != 0
		})
	}
	if vinix_key_consumed { return true }
	if vinix_focused != '' { return false }
	characters := if input.starts_with('\x1b') {
		if name.runes().len == 1 { name } else { '' }
	} else {
		input
	}
	gg.native_dispatch_key(code, modifiers, characters)
	return true
}

fn native_message_begin() voidptr {
	$if prealloc {
		return unsafe { prealloc_scope_begin() }
	}
	return unsafe { nil }
}

fn native_message_leave(scope voidptr) {
	$if prealloc {
		unsafe { prealloc_scope_leave(scope) }
	}
}

fn native_message_finish(scope voidptr) {
	$if prealloc {
		unsafe { prealloc_scope_free_after(scope) }
	}
}

fn native_send_tree(fd int, state []u8, root Element) {
	scope := native_message_begin()
	mut encoded := []u8{cap: 16 * 1024}
	vinix_encode_element(root, mut encoded)
	vinix_send_response(fd, true, state, encoded)
	native_message_leave(scope)
	native_message_finish(scope)
}
