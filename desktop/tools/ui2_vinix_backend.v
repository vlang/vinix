// SPDX-License-Identifier: GPL-2.0-or-later
// A headless ui2 backend for applications hosted by the Vinix compositor.
// It deliberately lives outside the ui2 checkout: staging adds it to a
// disposable module overlay, leaving the user's ~/code/ui2 tree untouched.
@[has_globals]
module ui2

import math.bits
import os

const vinix_app_magic = u32(0x56415050)
const vinix_app_version = u8(8)
const vinix_request_header_size = 124
const vinix_response_header_size = 116
const vinix_state_size = 104
const vinix_max_payload = 16 * 1024 * 1024

enum VinixCommand as u8 {
	build = 1
	handle
	key_input
	poll
	pointer
	close
}

struct VinixTarget {
	kind                      Kind
	id                        string
	action_id                 string
	submit_id                 string
	emit_change               bool
	readonly                  bool
	menu                      []MenuEntry
	frame                     Rect
	min_value                 f64
	max_value                 f64
	step                      f64
	orientation               Orientation
	padding                   f64
	toggle_group              string
	toggle_allow_no_selection bool
	clickable                 bool
	draggable                 bool
}

struct VinixScrollTarget {
	id      string
	frame   Rect
	maximum f64
}

__global vinix_build_handler = BuildFn(unsafe { nil })
__global vinix_event_handler = EventFn(unsafe { nil })
__global vinix_key_handler = KeyFn(unsafe { nil })
__global vinix_key_event_handler = KeyEventFn(unsafe { nil })
__global vinix_scroll_handler = ScrollFn(unsafe { nil })
__global vinix_drop_handler = DropFn(unsafe { nil })
__global vinix_width = 800
__global vinix_height = 600
__global vinix_running = false
__global vinix_focused = ''
__global vinix_pointer_x = 0.0
__global vinix_pointer_y = 0.0
__global vinix_pointer_target = VinixTarget{}
__global vinix_targets = map[string]VinixTarget{}
__global vinix_hit_targets = []VinixTarget{}
__global vinix_scroll_targets = []VinixScrollTarget{}
__global vinix_text_values = map[string]string{}
__global vinix_text_declared = map[string]string{}
__global vinix_text_editors = map[string]TextEditor{}
__global vinix_slider_values = map[string]f64{}
__global vinix_slider_declared = map[string]f64{}
__global vinix_switch_values = map[string]bool{}
__global vinix_switch_declared = map[string]bool{}
__global vinix_checkbox_values = map[string]bool{}
__global vinix_checkbox_declared = map[string]bool{}
__global vinix_toggle_values = map[string]bool{}
__global vinix_toggle_declared = map[string]bool{}
__global vinix_toggle_groups = map[string]string{}
__global vinix_scroll_values = map[string]f64{}
__global vinix_key_consumed = false
__global vinix_refresh_requested = true

fn vinix_put_u8(mut out []u8, value u8) {
	out << value
}

fn vinix_put_u32(mut out []u8, value u32) {
	out << u8(value)
	out << u8(value >> 8)
	out << u8(value >> 16)
	out << u8(value >> 24)
}

fn vinix_put_i32(mut out []u8, value int) {
	vinix_put_u32(mut out, u32(value))
}

fn vinix_put_u64(mut out []u8, value u64) {
	for shift := 0; shift < 64; shift += 8 {
		out << u8(value >> shift)
	}
}

fn vinix_put_f64(mut out []u8, value f64) {
	vinix_put_u64(mut out, bits.f64_bits(value))
}

fn vinix_put_string(mut out []u8, value string) {
	vinix_put_u32(mut out, u32(value.len))
	for byte in value {
		out << byte
	}
}

fn vinix_take_u32(data []u8, offset int) u32 {
	if offset < 0 || offset + 4 > data.len {
		return 0
	}
	return u32(data[offset]) | (u32(data[offset + 1]) << 8) | (u32(data[offset + 2]) << 16) |
		(u32(data[offset + 3]) << 24)
}

fn vinix_take_i32(data []u8, offset int) int {
	return int(i32(vinix_take_u32(data, offset)))
}

fn vinix_read_exact(fd int, count int) ?[]u8 {
	if fd < 0 || count < 0 {
		return none
	}
	mut result := []u8{cap: count}
	for result.len < count {
		chunk, read := os.fd_read(fd, count - result.len)
		if read <= 0 {
			return none
		}
		for byte in chunk.bytes() {
			result << byte
		}
	}
	return result
}

fn vinix_write_all(fd int, data []u8) {
	if data.len == 0 {
		return
	}
	os.fd_write(fd, unsafe { tos(data.data, data.len) })
}

fn vinix_default_state() []u8 {
	mut state := []u8{len: vinix_state_size}
	// requested_scale follows nine i32 Settings fields and must be 1 or 2.
	state[36] = 1
	return state
}

fn vinix_send_response(fd int, ok bool, state []u8, payload []u8) {
	mut header := []u8{cap: vinix_response_header_size}
	vinix_put_u32(mut header, vinix_app_magic)
	vinix_put_u8(mut header, vinix_app_version)
	vinix_put_u8(mut header, if ok { u8(0) } else { u8(1) })
	vinix_put_u8(mut header, 0)
	vinix_put_u8(mut header, 0)
	if state.len == vinix_state_size {
		header << state
	} else {
		header << vinix_default_state()
	}
	vinix_put_u32(mut header, u32(payload.len))
	vinix_write_all(fd, header)
	vinix_write_all(fd, payload)
}

fn vinix_encode_element(element Element, mut out []u8) {
	vinix_put_u8(mut out, u8(element.kind))
	mut flags := u8(0)
	if element.box.transparent {
		flags |= 1
	}
	if element.text_style.bold {
		flags |= 2
	}
	if element.text_style.shadow {
		flags |= 4
	}
	if element.clickable {
		flags |= 8
	}
	if element.draggable {
		flags |= 16
	}
	if element.hidden {
		flags |= 32
	}
	if element.enabled {
		flags |= 64
	}
	vinix_put_u8(mut out, flags)
	vinix_put_u8(mut out, u8(element.text_style.align))
	vinix_put_u8(mut out, u8(element.orientation))
	vinix_put_u8(mut out, 0)
	vinix_put_u8(mut out, 0)
	mut style_flags := u32(0)
	if element.native_style {
		style_flags |= 1
	}
	if element.checked {
		style_flags |= 2
	}
	if element.text_style.italic {
		style_flags |= 1 << 2
	}
	if element.text_style.underline {
		style_flags |= 1 << 3
	}
	if element.text_style.strikethrough {
		style_flags |= 1 << 4
	}
	if element.text_style.outline {
		style_flags |= 1 << 5
	}
	if element.emit_change {
		style_flags |= 1 << 6
	}
	if element.readonly {
		style_flags |= 1 << 7
	}
	if element.disable_scroll {
		style_flags |= 1 << 8
	}
	if element.persistent_scrollbars {
		style_flags |= 1 << 9
	}
	if element.secure {
		style_flags |= 1 << 10
	}
	if element.long_press {
		style_flags |= 1 << 11
	}
	if element.swipe_left {
		style_flags |= 1 << 12
	}
	if element.value_track {
		style_flags |= 1 << 13
	}
	if element.toggle_allow_no_selection {
		style_flags |= 1 << 14
	}
	if element.autocorrect {
		style_flags |= 1 << 15
	}
	if element.focused {
		style_flags |= 1 << 16
	}
	vinix_put_u32(mut out, style_flags)
	vinix_put_f64(mut out, element.frame.x)
	vinix_put_f64(mut out, element.frame.y)
	vinix_put_f64(mut out, element.frame.width)
	vinix_put_f64(mut out, element.frame.height)
	vinix_put_u32(mut out, element.box.bg)
	vinix_put_f64(mut out, element.box.radius)
	vinix_put_u32(mut out, element.box.border_color)
	vinix_put_f64(mut out, element.box.border_left)
	vinix_put_f64(mut out, element.box.border_top)
	vinix_put_f64(mut out, element.box.border_right)
	vinix_put_f64(mut out, element.box.border_bottom)
	vinix_put_u32(mut out, element.text_style.color)
	vinix_put_u32(mut out, element.text_style.background_color)
	vinix_put_f64(mut out, element.text_style.size)
	vinix_put_f64(mut out, element.text_style.head_indent)
	vinix_put_f64(mut out, element.text_style.first_line_indent)
	vinix_put_f64(mut out, element.text_style.hyphenation_factor)
	vinix_put_i32(mut out, element.text_style.lines)
	vinix_put_i32(mut out, element.keyboard)
	vinix_put_i32(mut out, element.text_selection.anchor)
	vinix_put_i32(mut out, element.text_selection.caret)
	vinix_put_f64(mut out, element.padding_left)
	vinix_put_f64(mut out, element.value)
	vinix_put_f64(mut out, element.min_value)
	vinix_put_f64(mut out, element.max_value)
	vinix_put_f64(mut out, element.step)
	vinix_put_f64(mut out, element.padding)
	vinix_put_u32(mut out, element.slider_style.track_color)
	vinix_put_u32(mut out, element.slider_style.value_track_color)
	vinix_put_u32(mut out, element.slider_style.thumb_color)
	vinix_put_f64(mut out, element.slider_style.track_width)
	vinix_put_f64(mut out, element.slider_style.thumb_size)
	vinix_put_u32(mut out, element.switch_style.inactive_track_color)
	vinix_put_u32(mut out, element.switch_style.active_track_color)
	vinix_put_u32(mut out, element.switch_style.thumb_color)
	vinix_put_u32(mut out, element.switch_style.disabled_track_color)
	vinix_put_u32(mut out, element.switch_style.disabled_thumb_color)
	vinix_put_u32(mut out, element.toggle_down_box.bg)
	vinix_put_f64(mut out, element.toggle_down_box.radius)
	vinix_put_u32(mut out, element.toggle_down_box.border_color)
	vinix_put_u32(mut out, element.toggle_down_text_style.color)
	vinix_put_u32(mut out, element.toggle_down_text_style.background_color)
	vinix_put_f64(mut out, element.toggle_down_text_style.size)
	vinix_put_string(mut out, element.id)
	vinix_put_string(mut out, element.action_id)
	vinix_put_string(mut out, element.submit_id)
	vinix_put_string(mut out, element.text)
	vinix_put_string(mut out, element.image_path)
	vinix_put_string(mut out, element.tooltip)
	vinix_put_string(mut out, element.placeholder)
	vinix_put_string(mut out, element.cursor)
	vinix_put_string(mut out, element.toggle_group)
	vinix_put_string(mut out, element.text_style.font_family)
	vinix_put_string(mut out, element.text_style.vertical_align)
	vinix_put_string(mut out, element.text_style.link)
	vinix_put_u32(mut out, u32(element.menu.len))
	for entry in element.menu {
		vinix_put_string(mut out, entry.id)
		vinix_put_string(mut out, entry.title)
	}
	vinix_put_u32(mut out, u32(element.children.len))
	for child in element.children {
		vinix_encode_element(child, mut out)
	}
}

fn vinix_action_id(element Element) string {
	return if element.action_id.len > 0 { element.action_id } else { element.id }
}

fn vinix_store_target(element Element, frame Rect) {
	interactive := element.kind in [.button, .checkbox, .dropdown, .text_field, .text_area, .slider,
		.switch_control, .toggle_button] || element.clickable || element.draggable
	action := vinix_action_id(element)
	if !interactive || !element.enabled || action.len == 0 {
		return
	}
	target := VinixTarget{
		kind:                      element.kind
		id:                        element.id
		action_id:                 action
		submit_id:                 element.submit_id
		emit_change:               element.emit_change
		readonly:                  element.readonly
		menu:                      element.menu
		frame:                     frame
		min_value:                 element.min_value
		max_value:                 element.max_value
		step:                      element.step
		orientation:               element.orientation
		padding:                   element.padding
		toggle_group:              element.toggle_group
		toggle_allow_no_selection: element.toggle_allow_no_selection
		clickable:                 element.clickable
		draggable:                 element.draggable
	}
	vinix_hit_targets << target
	vinix_targets[action] = target
	if element.id.len > 0 && element.id != action {
		vinix_targets[element.id] = target
	}
}

fn vinix_runtime_element(element Element, off_x f64, off_y f64) Element {
	mut text_value := element.text
	mut checked := element.checked
	mut slider_value_ := element.value
	mut focused := element.focused
	mut text_selection := element.text_selection
	// ui2.text() also exposes labels and buttons. Several examples use that
	// lookup to verify or coordinate their declarative tree, not only inputs.
	if element.id.len > 0 && element.kind !in [.text_field, .text_area, .dropdown] {
		vinix_text_values[element.id] = element.text.clone()
	}
	match element.kind {
		.text_field, .text_area, .dropdown {
			declared := vinix_text_declared[element.id] or { '\x00' }
			if element.id !in vinix_text_values || declared != element.text {
				vinix_text_values[element.id] = element.text.clone()
				vinix_text_declared[element.id] = element.text.clone()
				if element.kind in [.text_field, .text_area] {
					mut editor := vinix_text_editors[element.id] or { text_editor(element.text.clone()) }
					editor.set_text(element.text.clone())
					vinix_text_editors[element.id] = editor
				}
			}
			text_value = vinix_text_values[element.id] or { element.text }
			if element.secure {
				text_value = text_field_display_text(text_value, true)
			}
			if element.kind in [.text_field, .text_area] {
				focused = element.id == vinix_focused
				text_selection = (vinix_text_editors[element.id] or {
					text_editor(text_value.clone())
				}).selection
			}
		}
		.slider {
			declared := vinix_slider_declared[element.id] or { element.value - 1.0 }
			if element.id !in vinix_slider_values || declared != element.value {
				vinix_slider_values[element.id] = element.value
				vinix_slider_declared[element.id] = element.value
			}
			slider_value_ = vinix_slider_values[element.id] or { element.value }
		}
		.switch_control {
			declared := vinix_switch_declared[element.id] or { !element.checked }
			if element.id !in vinix_switch_values || declared != element.checked {
				vinix_switch_values[element.id] = element.checked
				vinix_switch_declared[element.id] = element.checked
			}
			checked = vinix_switch_values[element.id] or { element.checked }
		}
		.checkbox {
			declared := vinix_checkbox_declared[element.id] or { !element.checked }
			if element.id !in vinix_checkbox_values || declared != element.checked {
				vinix_checkbox_values[element.id] = element.checked
				vinix_checkbox_declared[element.id] = element.checked
			}
			checked = vinix_checkbox_values[element.id] or { element.checked }
		}
		.toggle_button {
			declared := vinix_toggle_declared[element.id] or { !element.checked }
			if element.id !in vinix_toggle_values || declared != element.checked {
				vinix_toggle_values[element.id] = element.checked
				vinix_toggle_declared[element.id] = element.checked
			}
			checked = vinix_toggle_values[element.id] or { element.checked }
			vinix_toggle_groups[element.id] = element.toggle_group
		}
		else {}
	}
	absolute_frame := Rect{
		x:      off_x + element.frame.x
		y:      off_y + element.frame.y
		width:  element.frame.width
		height: element.frame.height
	}
	vinix_store_target(element, absolute_frame)
	mut children := []Element{cap: element.children.len}
	child_x := off_x + element.frame.x
	child_y := off_y + element.frame.y
	if element.kind == .scroll {
		mut content_height := 0.0
		for child in element.children {
			if !child.hidden && child.frame.y + child.frame.height > content_height {
				content_height = child.frame.y + child.frame.height
			}
		}
		if content_height > 0 {
			content_height += 16
		}
		maximum := if content_height > element.frame.height {
			content_height - element.frame.height
		} else {
			0.0
		}
		mut offset := vinix_scroll_values[element.id] or { 0.0 }
		if offset < 0 {
			offset = 0
		} else if offset > maximum {
			offset = maximum
		}
		if element.id.len > 0 {
			vinix_scroll_values[element.id] = offset
			if element.enabled && !element.disable_scroll {
				vinix_scroll_targets << VinixScrollTarget{
					id:      element.id
					frame:   absolute_frame
					maximum: maximum
				}
			}
		}
		for child in element.children {
			shifted := Element{
				...child
				frame: Rect{
					x:      child.frame.x
					y:      child.frame.y - offset
					width:  child.frame.width
					height: child.frame.height
				}
			}
			children << vinix_runtime_element(shifted, child_x, child_y)
		}
	} else {
		for child in element.children {
			children << vinix_runtime_element(child, child_x, child_y)
		}
	}
	return Element{
		...element
		text:           text_value
		checked:        checked
		value:          slider_value_
		focused:        focused
		text_selection: text_selection
		children:       children
	}
}

fn vinix_fire(action string) {
	if action.len > 0 && voidptr(vinix_event_handler) != unsafe { nil } {
		vinix_event_handler(action)
		vinix_refresh_requested = true
	}
}

fn vinix_slider_from_pointer(target VinixTarget) f64 {
	mut normalized := 0.0
	if target.orientation == .vertical {
		extent := target.frame.height - target.padding * 2
		if extent > 0 {
			normalized = (target.frame.y + target.frame.height - target.padding - vinix_pointer_y) /
				extent
		}
	} else {
		extent := target.frame.width - target.padding * 2
		if extent > 0 {
			normalized = (vinix_pointer_x - target.frame.x - target.padding) / extent
		}
	}
	return slider_value_from_normalized(normalized, target.min_value, target.max_value,
		target.step)
}

fn vinix_hit_target_at(x f64, y f64) ?VinixTarget {
	for index := vinix_hit_targets.len - 1; index >= 0; index-- {
		target := vinix_hit_targets[index]
		if x >= target.frame.x && x < target.frame.x + target.frame.width && y >= target.frame.y
			&& y < target.frame.y + target.frame.height {
			return target
		}
	}
	return none
}

fn vinix_scroll_target_at(x f64, y f64) ?VinixScrollTarget {
	for index := vinix_scroll_targets.len - 1; index >= 0; index-- {
		target := vinix_scroll_targets[index]
		if x >= target.frame.x && x < target.frame.x + target.frame.width && y >= target.frame.y
			&& y < target.frame.y + target.frame.height {
			return target
		}
	}
	return none
}

fn vinix_fire_pointer(phase string, target VinixTarget) {
	if target.action_id.len > 0 {
		vinix_fire('pointer:${phase}:${target.action_id}:${vinix_pointer_x}:${vinix_pointer_y}')
	}
}

fn vinix_handle_pointer(kind int, scroll int) {
	match kind {
		0 { // move / drag
			target := vinix_pointer_target
			if target.action_id.len == 0 {
				return
			}
			if target.kind == .slider {
				vinix_slider_values[target.id] = vinix_slider_from_pointer(target)
				vinix_fire(target.action_id)
			} else if target.kind == .switch_control {
				vinix_switch_values[target.id] = vinix_pointer_x >= target.frame.x + target.frame.width / 2
				vinix_fire(target.action_id)
			} else if target.draggable {
				vinix_fire_pointer('drag', target)
			}
		}
		1 { // down
			target := vinix_hit_target_at(vinix_pointer_x, vinix_pointer_y) or { return }
			vinix_pointer_target = target
			if target.clickable || target.draggable {
				vinix_fire_pointer('down', target)
			}
		}
		2 { // up
			target := vinix_pointer_target
			if target.action_id.len > 0 && (target.clickable || target.draggable) {
				vinix_fire_pointer('up', target)
			}
			vinix_pointer_target = VinixTarget{}
		}
		3 { // wheel
			target := vinix_scroll_target_at(vinix_pointer_x, vinix_pointer_y) or { return }
			current := vinix_scroll_values[target.id] or { 0.0 }
			requested := current - f64(scroll * 48)
			next := if requested < 0 {
				0.0
			} else if requested > target.maximum {
				target.maximum
			} else {
				requested
			}
			if next != current {
				vinix_scroll_values[target.id] = next
				vinix_refresh_requested = true
				if voidptr(vinix_scroll_handler) != unsafe { nil } {
					vinix_scroll_handler(target.id)
				}
			}
		}
		else {}
	}
}

fn vinix_handle_action(action string) {
	target := vinix_targets[action] or {
		vinix_fire(action)
		return
	}
	match target.kind {
		.text_field, .text_area {
			vinix_focused = target.id
			mut editor := vinix_text_editors[target.id] or {
				text_editor((vinix_text_values[target.id] or { '' }).clone())
			}
			editor.set_caret(rune_len(editor.text))
			vinix_text_editors[target.id] = editor
		}
		.checkbox {
			vinix_checkbox_values[target.id] = !(vinix_checkbox_values[target.id] or { false })
			vinix_fire(target.action_id)
		}
		.dropdown {
			if target.menu.len > 0 {
				current := vinix_text_values[target.id] or { '' }
				mut next := 0
				for index, option in target.menu {
					if option.title == current || option.id == current {
						next = (index + 1) % target.menu.len
						break
					}
				}
				vinix_text_values[target.id] = target.menu[next].title.clone()
			}
			vinix_fire(target.action_id)
		}
		.slider {
			vinix_slider_values[target.id] = vinix_slider_from_pointer(target)
			vinix_fire(target.action_id)
		}
		.switch_control {
			vinix_switch_values[target.id] = !(vinix_switch_values[target.id] or { false })
			vinix_fire(target.action_id)
		}
		.toggle_button {
			was_pressed := vinix_toggle_values[target.id] or { false }
			if !was_pressed || target.toggle_allow_no_selection {
				vinix_toggle_values[target.id] = !was_pressed
			}
			if !was_pressed && target.toggle_group.len > 0 {
				for id, group in vinix_toggle_groups {
					if id != target.id && group == target.toggle_group {
						vinix_toggle_values[id] = false
					}
				}
			}
			vinix_fire(target.action_id)
		}
		else {
			// Coordinate-bearing surface events are emitted by the raw pointer
			// path, just as they are by ui2's native backends.
			if !target.clickable && !target.draggable {
				vinix_fire(target.action_id)
			}
		}
	}
	vinix_refresh_requested = true
}

fn vinix_key_name(input string) string {
	return match input {
		'\x1b[A', '\x1bOA' { 'up' }
		'\x1b[B', '\x1bOB' { 'down' }
		'\x1b[C', '\x1bOC' { 'right' }
		'\x1b[D', '\x1bOD' { 'left' }
		'\x1b[H', '\x1bOH', '\x1b[1~' { 'home' }
		'\x1b[F', '\x1bOF', '\x1b[4~' { 'end' }
		'\x1b[3~' { 'forward_delete' }
		'\x1b[5~' { 'page_up' }
		'\x1b[6~' { 'page_down' }
		'\x7f', '\b' { 'backspace' }
		'\r', '\n' { 'enter' }
		'\t' { 'tab' }
		'\x1b' { 'escape' }
		else { input }
	}
}

fn vinix_csi_u_key(input string) string {
	if !input.starts_with('\x1b[') || !input.ends_with('u') {
		return ''
	}
	parts := input[2..input.len - 1].split(';')
	if parts.len == 0 {
		return ''
	}
	code := parts[0].int()
	if code <= 0 {
		return ''
	}
	mut key := match code {
		8, 127 { 'backspace' }
		9 { 'tab' }
		13 { 'enter' }
		27 { 'escape' }
		else { rune(code).str().to_lower() }
	}
	modifier := if parts.len > 1 { parts[1].int() - 1 } else { 0 }
	mut modifiers := []string{}
	if modifier & 8 != 0 {
		modifiers << 'cmd'
	}
	if modifier & 4 != 0 {
		modifiers << 'ctrl'
	}
	if modifier & 2 != 0 {
		modifiers << 'alt'
	}
	if modifier & 1 != 0 {
		modifiers << 'shift'
	}
	if modifiers.len > 0 {
		key = modifiers.join('+') + '+' + key
	}
	return key
}

fn vinix_normalized_key(input string) string {
	csi := vinix_csi_u_key(input)
	return if csi.len > 0 { csi } else { vinix_key_name(input) }
}

fn vinix_fire_key(key string, target VinixTarget) bool {
	if voidptr(vinix_key_handler) == unsafe { nil } || key.len == 0 {
		return false
	}
	mut event_key := key
	if target.kind == .text_area {
		event_key = 'text:${target.id}:${key}'
	}
	vinix_key_consumed = false
	vinix_key_handler(event_key)
	consumed := vinix_key_consumed
	vinix_key_consumed = false
	return consumed
}

fn vinix_commit_editor(target VinixTarget, editor TextEditor) {
	vinix_text_editors[target.id] = editor
	vinix_text_values[target.id] = editor.text.clone()
	vinix_refresh_requested = true
	if target.emit_change {
		vinix_fire(target.action_id)
	}
}

fn vinix_handle_key(input string) {
	target := vinix_targets[vinix_focused] or { VinixTarget{} }
	key := vinix_normalized_key(input)
	consumed := vinix_fire_key(key, target)
	if consumed || target.kind !in [.text_field, .text_area] || target.readonly {
		return
	}
	mut editor := vinix_text_editors[target.id] or {
		text_editor((vinix_text_values[target.id] or { '' }).clone())
	}
	mut changed := false
	match key {
		'backspace' {
			changed = editor.backspace()
		}
		'forward_delete' {
			changed = editor.delete_forward()
		}
		'left', 'right', 'home', 'end', 'page_up', 'page_down' {
			if apply_text_editor_navigation(mut editor, key, false, false) {
				vinix_text_editors[target.id] = editor
				vinix_refresh_requested = true
			}
		}
		'enter' {
			if target.kind == .text_area {
				editor.insert_text('\n')
				changed = true
			} else {
				vinix_focused = ''
				vinix_fire(target.submit_id)
			}
		}
		else {
			// CSI-u represents shortcuts and key-down events. Ordinary UTF-8 input
			// is text and replaces the current selection.
			mut printable := input.len > 0 && !input.starts_with('\x1b')
			for byte in input.bytes() {
				if byte < 32 || byte == 127 {
					printable = false
					break
				}
			}
			if printable {
				editor.insert_text(input)
				changed = true
			}
		}
	}
	if changed {
		vinix_commit_editor(target, editor)
	}
}

fn vinix_serve(request_fd int, response_fd int) {
	mut state := vinix_default_state()
	vinix_send_response(response_fd, true, state, []u8{})
	vinix_running = true
	for vinix_running {
		header := vinix_read_exact(request_fd, vinix_request_header_size) or { break }
		if vinix_take_u32(header, 0) != vinix_app_magic || header[4] != vinix_app_version {
			break
		}
		command_value := header[5]
		width := vinix_take_i32(header, 8)
		height := vinix_take_i32(header, 12)
		state = header[16..16 + vinix_state_size].clone()
		payload_length := int(vinix_take_u32(header, 120))
		if payload_length < 0 || payload_length > vinix_max_payload {
			break
		}
		payload := vinix_read_exact(request_fd, payload_length) or { break }
		command := unsafe { VinixCommand(command_value) }
		match command {
			.build {
				vinix_width = width
				vinix_height = height
				vinix_targets = map[string]VinixTarget{}
				vinix_hit_targets = []VinixTarget{}
				vinix_scroll_targets = []VinixScrollTarget{}
				vinix_refresh_requested = false
				root := if voidptr(vinix_build_handler) == unsafe { nil } {
					screen(0xffffff, []Element{})
				} else {
					vinix_runtime_element(vinix_build_handler(), 0, 0)
				}
				mut encoded := []u8{cap: 16 * 1024}
				vinix_encode_element(root, mut encoded)
				vinix_send_response(response_fd, true, state, encoded)
			}
			.handle {
				vinix_handle_action(payload.bytestr())
				vinix_send_response(response_fd, true, state, []u8{})
			}
			.key_input {
				vinix_handle_key(payload.bytestr())
				vinix_send_response(response_fd, true, state, []u8{})
			}
			.poll {
				vinix_send_response(response_fd, true, state, [u8(if vinix_refresh_requested {
					1
				} else {
					0
				})])
			}
			.pointer {
				if payload.len == 28 {
					vinix_pointer_x = f64(vinix_take_i32(payload, 12))
					vinix_pointer_y = f64(vinix_take_i32(payload, 16))
					vinix_handle_pointer(vinix_take_i32(payload, 0), vinix_take_i32(payload,
						8))
				}
				vinix_send_response(response_fd, true, state, []u8{})
			}
			.close {
				vinix_send_response(response_fd, true, state, []u8{})
				vinix_running = false
			}
		}
	}
	os.fd_close(request_fd)
	os.fd_close(response_fd)
}

fn vinix_process_fds() ?(int, int) {
	// Standalone applications keep argv available for document paths.
	mut request_fd := os.getenv('VINIX_REQUEST_FD').int()
	mut response_fd := os.getenv('VINIX_RESPONSE_FD').int()
	for argument in os.args {
		if argument.starts_with('--request-fd=') {
			request_fd = argument.all_after('=').int()
		} else if argument.starts_with('--response-fd=') {
			response_fd = argument.all_after('=').int()
		}
	}
	if request_fd < 3 || response_fd < 3 || request_fd == response_fd {
		return none
	}
	return request_fd, response_fd
}

pub fn bounds() Rect {
	return rect(0, 0, f64(vinix_width), f64(vinix_height))
}

pub fn run(build_fn BuildFn, event_fn EventFn) {
	run_window('App', 800, 600, build_fn, event_fn)
}

pub fn run_window(_title string, width int, height int, build_fn BuildFn, event_fn EventFn) {
	run_window_with_min_size(_title, width, height, 0, 0, build_fn, event_fn)
}

fn run_window_with_min_size(title string, width int, height int, _min_width int, _min_height int,
	build_fn BuildFn, event_fn EventFn) {
	vinix_width = width
	vinix_height = height
	vinix_build_handler = build_fn
	vinix_event_handler = event_fn
	configure_animation_driver(request_refresh, false)
	publish_menu_context(event_fn, title, unsafe { nil })
	request_fd, response_fd := vinix_process_fds() or {
		eprintln('ui2: this headless application must be launched by Vinix')
		return
	}
	vinix_serve(request_fd, response_fd)
}

pub fn refresh() {
	vinix_refresh_requested = true
}

pub fn request_refresh() {
	vinix_refresh_requested = true
}

pub fn refresh_element(_id string, _element Element) {
	vinix_refresh_requested = true
}

pub fn on_key(handler KeyFn) {
	vinix_key_handler = handler
}

pub fn on_key_event(handler KeyEventFn) {
	vinix_key_event_handler = handler
}

pub fn on_scroll(handler ScrollFn) {
	vinix_scroll_handler = handler
}

pub fn on_drop(handler DropFn) {
	vinix_drop_handler = handler
}

pub fn text(id string) string {
	return (vinix_text_values[id] or { '' }).clone()
}

pub fn set_text(id string, value string) {
	vinix_text_values[id] = value.clone()
	mut editor := vinix_text_editors[id] or { text_editor(value.clone()) }
	editor.set_text(value.clone())
	vinix_text_editors[id] = editor
	vinix_refresh_requested = true
}

pub fn slider_value(id string) f64 {
	return vinix_slider_values[id] or { 0 }
}

pub fn set_slider_value(id string, value f64) {
	vinix_slider_values[id] = value
	vinix_refresh_requested = true
}

pub fn switch_active(id string) bool {
	return vinix_switch_values[id] or { false }
}

pub fn set_switch_active(id string, active bool) {
	vinix_switch_values[id] = active
	vinix_refresh_requested = true
}

pub fn toggle_button_pressed(id string) bool {
	return vinix_toggle_values[id] or { false }
}

pub fn set_toggle_button_pressed(id string, pressed bool) {
	vinix_toggle_values[id] = pressed
	vinix_refresh_requested = true
}

pub fn toggle_button_group_members(id string) []string {
	group := vinix_toggle_groups[id] or { return [] }
	mut members := []string{}
	for member, member_group in vinix_toggle_groups {
		if (group.len == 0 && member == id) || (group.len > 0 && member_group == group) {
			members << member
		}
	}
	return members
}

pub fn focus(id string) {
	vinix_focused = id
	mut editor := vinix_text_editors[id] or { text_editor((vinix_text_values[id] or { '' }).clone()) }
	editor.set_caret(rune_len(editor.text))
	vinix_text_editors[id] = editor
	vinix_refresh_requested = true
}

pub fn focused_id() string {
	return vinix_focused
}

pub fn focused_text_area_id() string {
	target := vinix_targets[vinix_focused] or { return '' }
	return if target.kind == .text_area { vinix_focused } else { '' }
}

pub fn dismiss_keyboard() {
	vinix_focused = ''
	vinix_refresh_requested = true
}

pub fn quit() {
	vinix_running = false
}

pub fn consume_key() {
	vinix_key_consumed = true
}

pub fn consume_text_key() {
	consume_key()
}

pub fn safe_area_top() f64 {
	return 0
}

pub fn start_barcode_scan() {
	vinix_fire('scan_error:barcode scanner unavailable')
}

pub fn insert_text_area_text(id string, value string) {
	mut editor := vinix_text_editors[id] or {
		text_editor((vinix_text_values[id] or { '' }).clone())
	}
	editor.insert_text(value)
	vinix_text_editors[id] = editor
	vinix_text_values[id] = editor.text.clone()
	vinix_refresh_requested = true
	target := vinix_targets[id] or { return }
	if target.emit_change {
		vinix_fire(target.action_id)
	}
}

pub fn scroll_offset(id string) f64 {
	return vinix_scroll_values[id] or { 0 }
}

pub fn scroll_to_offset(id string, offset f64) {
	vinix_scroll_values[id] = if offset > 0 { offset } else { 0 }
	vinix_refresh_requested = true
}

pub fn scroll_to_rect(id string, _x f64, y f64, _width f64, _height f64) {
	scroll_to_offset(id, y)
}

pub fn clipboard_has_image() bool {
	return false
}

pub fn save_clipboard_image_png(_path string) bool {
	return false
}

pub fn text_area_runs(id string) []TextRun {
	value := text(id)
	return if value.len > 0 { [TextRun{ text: value }] } else { []TextRun{} }
}

pub fn text_area_format_state(_id string) TextFormatState {
	return TextFormatState{}
}

pub fn toggle_text_area_format(id string, _format TextFormat) TextFormatState {
	return text_area_format_state(id)
}

pub fn set_text_area_font_family(id string, _family string) TextFormatState {
	return text_area_format_state(id)
}

pub fn set_text_area_font_size(id string, _size f64) TextFormatState {
	return text_area_format_state(id)
}

pub fn set_text_area_color(id string, _color u32) TextFormatState {
	return text_area_format_state(id)
}

pub fn set_text_area_background_color(id string, _color u32) TextFormatState {
	return text_area_format_state(id)
}

pub fn set_text_area_effect(id string, _effect string) TextFormatState {
	return text_area_format_state(id)
}

pub fn toggle_text_area_superscript(id string) TextFormatState {
	return text_area_format_state(id)
}

pub fn toggle_text_area_subscript(id string) TextFormatState {
	return text_area_format_state(id)
}

pub fn toggle_text_area_vertical_align(id string, _align string) TextFormatState {
	return text_area_format_state(id)
}

pub fn text_area_set_selection(id string, location int, length int) {
	value := text(id)
	selection := clamped_text_area_selection(value, location, length)
	mut editor := vinix_text_editors[id] or { text_editor(value.clone()) }
	start := utf16_offset_to_rune_index(value, selection.location)
	end := utf16_offset_to_rune_index(value, selection.location + selection.length)
	// Native AppKit/Win32 APIs report a selection's location as the caret.
	// Keep the anchor at the range end so ordered editing still spans the same
	// text while text_area_caret() returns the requested location.
	editor.set_selection(end, start)
	vinix_text_editors[id] = editor
	vinix_refresh_requested = true
}

pub fn text_area_set_caret(id string, position int) {
	text_area_set_selection(id, position, 0)
}

pub fn text_area_caret(id string) int {
	editor := vinix_text_editors[id] or { return 0 }
	return rune_index_to_utf16_offset(editor.text, editor.selection.caret)
}

pub fn text_area_selection_length(id string) int {
	editor := vinix_text_editors[id] or { return 0 }
	start, end := editor.selection.ordered()
	return rune_index_to_utf16_offset(editor.text, end) - rune_index_to_utf16_offset(editor.text,
		start)
}
