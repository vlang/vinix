// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded source-storyboard subset for builds without Apple's ibtool.
module main

import os
import plist

fn storyboard_view(node &StoryboardNode, controller u64, controller_id string, depth int) !u64 {
	if depth > 32 { return error('storyboard view depth exceeds limit') }
	class_name := match node.name {
		'view' { 'UIView' }
		'button' { 'UIButton' }
		'label' { 'UILabel' }
		else { return error('unsupported storyboard view: ${node.name}') }
	}
	if node.attributes['customClass'] != '' { return error('custom storyboard views are unsupported') }
	object := objc_allocate(ios_runtime.names[class_name])
	mut complete := false
	defer { if !complete { objc_release(object) } }
	mut header := obj_header(object)
	if rect := storyboard_child(node, 'rect') {
		header.frame = ObjRect{rect.attributes['x'].f64(), rect.attributes['y'].f64(), rect.attributes['width'].f64(), rect.attributes['height'].f64()}
	}
	for child in node.children {
		match child.name {
			'color' {
				if child.attributes['key'] != 'backgroundColor' { return error('unsupported storyboard color') }
				color := objc_allocate(ios_runtime.names['UIColor'])
				mut c := obj_header(color)
				if white := child.attributes['white'] {
					c.color = u32(white.f64() * 255) * 0x010101
				} else {
					c.color = u32(child.attributes['red'].f64() * 255) << 16 | u32(child.attributes['green'].f64() * 255) << 8 | u32(child.attributes['blue'].f64() * 255)
				}
				store_field(object, 2, color)
				objc_release(color)
			}
			'subviews' {
				if header.child_count + child.children.len > 64 { return error('storyboard subviews exceed limit') }
				for view in child.children {
					subview := storyboard_view(view, controller, controller_id, depth + 1)!
					ui_add_child(object, subview)
					objc_release(subview)
				}
			}
			'state' {
				if class_name != 'UIButton' || child.attributes['key'] != 'normal' { return error('unsupported storyboard button state') }
				if header.fields[5] == 0 { header.fields[5] = objc_allocate(ios_runtime.names['UILabel']) }
				store_field(header.fields[5], 0, make_string(unsafe { &char(child.attributes['title'].str) }))
				color := objc_allocate(ios_runtime.names['UIColor'])
				mut c := obj_header(color)
				c.color = 0x007aff
				store_field(header.fields[5], 3, color)
				objc_release(color)
			}
			'connections' {
				for connection in child.children {
					if class_name != 'UIButton' || connection.name != 'action'
						|| connection.attributes['destination'] != controller_id
						|| connection.attributes['eventType'] != 'touchUpInside'
						|| connection.attributes['selector'] == '' { return error('unsupported storyboard connection') }
					header.target = controller
					header.action = objc_selector(unsafe { &char(connection.attributes['selector'].str) })
				}
			}
			'rect', 'autoresizingMask' {}
			else { return error('unsupported source storyboard property: ${child.name}') }
		}
	}
	complete = true
	return object
}

fn storyboard_controller(root &StoryboardNode, key string, identifier string) !u64 {
	mut matches := []&StoryboardNode{}
	matches.flags |= .noslices
	defer { unsafe { matches.free() } }
	storyboard_find(root, key, identifier, mut matches)
	if matches.len != 1 { return error('storyboard controller identifier is missing or ambiguous') }
	initial := matches[0]
	class_name := if initial.attributes['customClass'] == '' { 'UIViewController' } else { initial.attributes['customClass'] }
	cls := ios_runtime.names[class_name] or { return error('storyboard controller class is missing: ${class_name}') }
	mut current := cls
	mut valid := false
	for _ in 0 .. 128 {
		if current == ios_runtime.names['UIViewController'] { valid = true; break }
		info := ios_runtime.classes[current] or { break }
		current = info.parent
	}
	if !valid { return error('storyboard controller must inherit UIViewController') }
	for child in initial.children {
		if child.name !in ['view', 'layoutGuides']! { return error('unsupported storyboard controller property') }
	}
	view_node := storyboard_child(initial, 'view') or { return error('storyboard controller view is missing') }
	controller := objc_new(cls)
	if controller == 0 { return error('storyboard controller initialization returned nil') }
	if controller !in ios_runtime.objects { return error('storyboard controller initialization returned unmanaged storage') }
	mut complete := false
	defer { if !complete { objc_release(controller) } }
	if !objc_is_kind(controller, ios_runtime.names['UIViewController']) {
		return error('storyboard controller initialization must return UIViewController')
	}
	view := storyboard_view(view_node, controller, initial.attributes['id'], 0)!
	store_field(controller, 6, view)
	objc_release(view)
	complete = true
	return controller
}

fn ui_load_storyboard(delegate u64) ! {
	path := os.join_path(ios_runtime.bundle, 'Info.plist')
	defer { unsafe { path.free() } }
	if !os.is_file(path) { return }
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	info := plist.parse(bytes)!
	defer { info.free() }
	name := info.fields['UIMainStoryboardFile'].text
	if name == '' { return }
	storyboard := storyboard_open(name, 0)!
	defer { objc_release(storyboard) }
	root := obj_header(storyboard).storyboard_root
	id := root.attributes['initialViewController']
	if id == '' { return error('storyboard initial controller is missing') }
	controller := storyboard_controller(root, 'id', id)!
	window := objc_allocate(ios_runtime.names['UIWindow'])
	store_field(window, 7, controller)
	objc_release(controller)
	invoke_action(delegate, u64(c'setWindow:'), window)
	objc_store_strong(unsafe { &ios_runtime.window }, window)
	objc_release(window)
	ui_load_controller(obj_header(window).fields[7])
}
