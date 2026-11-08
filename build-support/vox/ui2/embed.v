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
__global vox_native_wheel = fn (_ f64, _ f64, _ f64, _ f64) bool { return false }
__global vox_native_vector_cache = map[string]string{}
__global vox_native_vector_paths = map[string]string{}

pub fn native_embedded_elements() []Element {
	mut elements := vox_native_text.clone()
	elements << vox_native_elements
	vox_native_text.clear()
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

pub fn draw_embedded_elements(_ &gg.Context, elements []Element, _ map[string]int, handler EventFn) {
	vox_native_elements = elements.map(native_element(it, 0xffffff))
	vox_native_action = handler
}

pub fn native_add_text(x int, y int, text string, size int, color u32, bold bool, italic bool) {
	index := vox_native_text.len
	if index >= vox_native_text_cache.len {
		vox_native_text_cache << label('native-text-${index}', text.clone(), rect(0, 0, 0, 0), TextStyle{})
	}
	previous := vox_native_text_cache[index]
	vox_native_text_cache[index] = Element{
		...previous
		text:       if previous.text == text { previous.text } else { text.clone() }
		frame:      rect(x, y, vinix_width - x, size * 2)
		text_style: TextStyle{ size: f64(size), color: color, bold: bold, italic: italic, valign: .top }
	}
	vox_native_text << vox_native_text_cache[index]
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
	vox_native_text = []Element{}
	vox_native_text_cache = []Element{}
	for _, path in vox_native_vector_paths { os.rm(path) or {} }
	vox_native_vector_paths.clear()
	vox_native_vector_cache.clear()
}

fn native_element(source Element, inherited u32) Element {
	background := if source.box.transparent { inherited } else { source.box.bg }
	mut children := source.children.map(native_element(it, background))
	if source.kind == .button && source.box.transparent && source.text != '' {
		children << label(source.id + '-caption', source.text, rect(0, 0, source.frame.width, source.frame.height),
			TextStyle{ ...source.text_style, align: .center })
		return Element{ ...source, text: '', children: children }
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
