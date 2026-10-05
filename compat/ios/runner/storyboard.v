// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded source-storyboard subset for builds without Apple's ibtool.
// No application-specific classes or callbacks are named here.
module main

import encoding.xml
import os

fn xml_resource(path string) !xml.XMLDocument {
	if os.file_size(path) > 1024 * 1024 { return error('XML resource exceeds limit') }
	mut text := os.read_file(path)!
	// V's XML parser does not understand plist's external PUBLIC doctype.
	// The resource loader never fetches DTDs or accepts internal entities.
	if start := text.index('<!DOCTYPE') {
		end := text.index_after('>', start) or { return error('unterminated XML doctype') }
		if text[start..end].contains('[') { return error('XML internal entities are unsupported') }
		text = text[..start] + text[end + 1..]
	}
	return xml.XMLDocument.from_string(text)
}

fn xml_child(node xml.XMLNode, name string) ?xml.XMLNode {
	for child in node.children { if child is xml.XMLNode && child.name == name { return child } }
	return none
}

fn xml_text(node xml.XMLNode) string {
	for child in node.children { if child is string { return child } }
	return ''
}

fn plist_string(document xml.XMLDocument, key string) string {
	dictionary := xml_child(document.root, 'dict') or { return '' }
	mut found := false
	for child in dictionary.children {
		if child is xml.XMLNode {
			if found { return if child.name == 'string' { xml_text(child) } else { '' } }
			found = child.name == 'key' && xml_text(child) == key
		}
	}
	return ''
}

fn storyboard_view(node xml.XMLNode, controller u64, controller_id string, depth int) !u64 {
	if depth > 32 { return error('storyboard view depth exceeds limit') }
	class_name := match node.name {
		'view' { 'UIView' }
		'button' { 'UIButton' }
		'label' { 'UILabel' }
		else { return error('unsupported storyboard view: ${node.name}') }
	}
	object := objc_allocate(ios_runtime.names[class_name])
	mut header := obj_header(object)
	if rect := xml_child(node, 'rect') {
		header.frame = ObjRect{rect.attributes['x'].f64(), rect.attributes['y'].f64(), rect.attributes['width'].f64(), rect.attributes['height'].f64()}
	}
	for child in node.children {
		if child is xml.XMLNode {
			match child.name {
				'color' {
					if child.attributes['key'] == 'backgroundColor' {
						color := objc_allocate(ios_runtime.names['UIColor'])
						mut c := obj_header(color)
						if white := child.attributes['white'] {
							c.color = u32(white.f64() * 255) * 0x010101
						} else {
							c.color = u32(child.attributes['red'].f64() * 255) << 16 | u32(child.attributes['green'].f64() * 255) << 8 | u32(child.attributes['blue'].f64() * 255)
						}
						header.fields[2] = color
					}
				}
				'subviews' {
					for view in child.children {
						if view is xml.XMLNode {
							subview := storyboard_view(view, controller, controller_id, depth + 1)!
							ui_add_child(object, subview)
							objc_release(subview)
						}
					}
				}
				'state' {
					if class_name != 'UIButton' || child.attributes['key'] != 'normal' { continue }
					if header.fields[5] == 0 {
						header.fields[5] = objc_allocate(ios_runtime.names['UILabel'])
					}
					store_field(header.fields[5], 0, make_string(unsafe { &char(child.attributes['title'].str) }))
					color := objc_allocate(ios_runtime.names['UIColor'])
					mut c := obj_header(color)
					c.color = 0x007aff
					store_field(header.fields[5], 3, color)
					objc_release(color)
				}
				'connections' {
					for connection in child.children {
						if connection is xml.XMLNode {
							if connection.name != 'action' || connection.attributes['destination'] != controller_id || connection.attributes['eventType'] != 'touchUpInside' {
								return error('unsupported storyboard connection')
							}
							ios_runtime.selectors << connection.attributes['selector'].clone()
							header.target = controller
							header.action = u64(ios_runtime.selectors.last().str)
						}
					}
				}
				'rect', 'autoresizingMask' {}
				else { return error('unsupported source storyboard property: ${child.name}') }
			}
		}
	}
	return object
}

fn ui_load_storyboard(delegate u64) ! {
	path := os.join_path(ios_runtime.bundle, 'Info.plist')
	if !os.is_file(path) { return }
	info := xml_resource(path)!
	name := plist_string(info, 'UIMainStoryboardFile')
	if name == '' { return }
	if name.contains('/') || name.contains('..') {
		return error('invalid storyboard resource name')
	}
	resource := os.join_path(ios_runtime.bundle, 'Base.lproj', name + '.storyboard')
	if os.file_size(resource) > 1024 * 1024 { return error('storyboard resource exceeds limit') }
	storyboard := xml_resource(resource)!
	id := storyboard.root.attributes['initialViewController']
	initial := storyboard.get_element_by_id(id) or { return error('storyboard initial controller is missing') }
	class_name := initial.attributes['customClass']
	cls := ios_runtime.names[class_name] or { return error('storyboard controller class is missing: ${class_name}') }
	controller := objc_new(cls)
	view_node := xml_child(initial, 'view') or { return error('storyboard controller view is missing') }
	view := storyboard_view(view_node, controller, id, 0)!
	store_field(controller, 6, view)
	objc_release(view)
	window := objc_allocate(ios_runtime.names['UIWindow'])
	store_field(window, 7, controller)
	objc_release(controller)
	invoke_action(delegate, u64(c'setWindow:'), window)
	objc_store_strong(unsafe { &ios_runtime.window }, window)
	objc_release(window)
	ui_load_controller(obj_header(window).fields[7])
}
