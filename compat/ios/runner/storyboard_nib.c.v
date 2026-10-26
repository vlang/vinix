// SPDX-License-Identifier: GPL-2.0-or-later
// Data-only launch storyboard subset. Never dispatches initWithCoder: or
// archive-supplied class names. Unsupported properties fail explicitly.
module main

import math
import nib
import os
import plist

struct StoryboardNib {
	archive &nib.Archive
mut:
	seen map[int]bool
	remaining int = 4096
	image_budget int = 32 * 1024 * 1024
}

fn storyboard_resource_name(name string) bool {
	return name.len > 0 && name.len <= 128 && !name.contains('/') && !name.contains('\\')
		&& !name.contains('..') && !name.contains('\x00')
}

fn storyboard_resource(path string, limit int) ![]u8 {
	if !os.is_file(path) { return error('storyboard resource is missing: ${path}') }
	resolved := os.real_path(path)
	bundle := os.real_path(ios_runtime.bundle)
	root := bundle + os.path_separator
	defer { unsafe { resolved.free(); bundle.free(); root.free() } }
	if !resolved.starts_with(root) { return error('storyboard resource escapes the main bundle') }
	if os.file_size(resolved) > u64(limit) { return error('storyboard resource exceeds size limit') }
	bytes := os.read_bytes(resolved)!
	if bytes.len > limit { unsafe { bytes.free() }; return error('storyboard resource exceeds size limit') }
	return bytes
}

fn (n &StoryboardNib) class(object int) string {
	return n.archive.classes[n.archive.objects[object].class_id]
}

fn (n &StoryboardNib) property(object int, key string) ?nib.Value {
	obj := n.archive.objects[object]
	for i in obj.first .. obj.first + obj.count {
		value := n.archive.values[i]
		if n.archive.keys[value.key] == key { return value }
	}
	return none
}

fn (n &StoryboardNib) required(object int, key string) !nib.Value {
	return n.property(object, key) or { return error('missing compiled storyboard property: ${key}') }
}

fn (n &StoryboardNib) reference(object int, key string) !int {
	value := n.required(object, key)!
	if value.kind != 10 { return error('compiled storyboard property requires an object: ${key}') }
	return int(value.integer)
}

fn (n &StoryboardNib) text(object int) !string {
	if n.class(object) != 'NSString' { return error('compiled storyboard requires NSString') }
	value := n.required(object, 'NS.bytes')!
	if value.kind != 8 || value.data.len > 1024 { return error('invalid compiled storyboard string') }
	if value.data.len == 0 { return '' }
	for b in value.data { if b == 0 || b > 127 { return error('unsupported compiled storyboard string') } }
	return unsafe { tos(value.data.data, value.data.len) }
}

fn (n &StoryboardNib) string_property(object int, key string) !string {
	return n.text(n.reference(object, key)!)!
}

fn (n &StoryboardNib) number(object int, key string) !f64 {
	value := n.required(object, key)!
	if value.kind !in [u8(6), 7] { return error('compiled storyboard requires a real number: ${key}') }
	return value.real
}

fn (n &StoryboardNib) integer(object int, key string) !u64 {
	value := n.required(object, key)!
	if value.kind > 3 { return error('compiled storyboard requires an integer: ${key}') }
	return value.integer
}

fn (n &StoryboardNib) boolean(object int, key string, fallback bool) !bool {
	value := n.property(object, key) or { return fallback }
	if value.kind !in [u8(4), 5] { return error('compiled storyboard requires a boolean: ${key}') }
	return value.kind == 5
}

fn (n &StoryboardNib) array(object int) ![]int {
	if n.class(object) !in ['NSArray', 'NSMutableArray', 'NSDictionary']! { return error('compiled storyboard requires an inline collection') }
	if !n.boolean(object, 'NSInlinedValue', false)! { return error('compiled storyboard requires inline values') }
	obj := n.archive.objects[object]
	mut result := []int{cap: obj.count}
	mut complete := false
	defer { if !complete { unsafe { result.free() } } }
	for i in obj.first .. obj.first + obj.count {
		value := n.archive.values[i]
		if n.archive.keys[value.key] == 'NSInlinedValue' { continue }
		if n.archive.keys[value.key] != 'UINibEncoderEmptyKey' || value.kind != 10 { return error('invalid compiled storyboard collection item') }
		result << int(value.integer)
	}
	if n.class(object) == 'NSDictionary' && result.len != 0 { return error('compiled storyboard external objects are unsupported') }
	complete = true
	return result
}

fn (n &StoryboardNib) validate() ! {
	for index, obj in n.archive.objects {
		if obj.count > 128 { return error('compiled storyboard object property limit') }
		cls := n.class(index)
		allowed := match cls {
			'NSObject' { ['UINibTopLevelObjectsKey', 'UINibObjectsKey', 'UINibConnectionsKey', 'UINibVisibleWindowsKey', 'UINibAccessibilityConfigurationsKey', 'UINibTraitStorageListsKey', 'UINibKeyValuePairsKey'] }
			'NSString' { ['NS.bytes'] }
			'NSArray', 'NSMutableArray', 'NSDictionary' { ['NSInlinedValue', 'UINibEncoderEmptyKey'] }
			'UIProxyObject' { ['UIProxiedObjectIdentifier'] }
			'UIRuntimeOutletConnection' { ['UILabel', 'UISource', 'UIDestination'] }
			'UIClassSwapper' { ['UIExternalObjectsTableForViewLoading', 'UINibName', 'UIStoryboardIdentifier', 'UIRestorationIdentifier', 'UIClassName', 'UIOriginalClassName'] }
			'UIView', 'UIImageView' { ['UIBounds', 'UICenter', 'UISubviews', 'UIBackgroundColor', 'UIDeepDrawRect', 'UIOpaque', 'UIUserInteractionDisabled', 'UIAutoresizeSubviews', 'UIAutoresizingMask', 'UIContentMode', 'UIClipsToBounds', 'UIViewContentHuggingPriority', 'UIViewSemanticContentAttribute', 'UIViewLargeContentStoredProperties', 'UIImage'] }
			'UIColor' { ['UIColorComponentCount', 'UIRed', 'UIGreen', 'UIBlue', 'UIAlpha', 'NSRGB', 'NSColorSpace'] }
			'UIImageNibPlaceholder' { ['UIImageWidth', 'UIImageHeight', 'UIResourceName'] }
			'UILayoutGuide' { ['UILayoutGuideOwningView', 'UILayoutGuideIdentifier', 'UILayoutGuideOwningViewIsLocked', 'UILayoutGuideShouldBeArchived', 'UILayoutGuideAllowsNegativeDimensions'] }
			else { return error('unsupported compiled storyboard class: ${cls}') }
		}
		defer { unsafe { allowed.free() } }
		for i in obj.first .. obj.first + obj.count {
			value := n.archive.values[i]
			key := n.archive.keys[value.key]
			if key !in allowed { return error('unsupported compiled storyboard property: ${cls}.${key}') }
			if key != 'UINibEncoderEmptyKey' {
				for j in obj.first .. i {
					if n.archive.values[j].key == value.key { return error('duplicate compiled storyboard property') }
				}
			}
		}
		match cls {
			'NSObject' { if index != 0 { return error('unexpected compiled storyboard root') } }
			'NSString' { n.text(index)! }
			'NSArray', 'NSMutableArray', 'NSDictionary' { items := n.array(index)!; unsafe { items.free() } }
			'UIProxyObject' {
				if n.string_property(index, 'UIProxiedObjectIdentifier')! !in ['IBFilesOwner', 'IBFirstResponder', 'UIStoryboardPlaceholder']! { return error('unsupported compiled storyboard proxy') }
			}
			'UILayoutGuide' {
				if n.required(index, 'UILayoutGuideOwningView')!.kind != 9 || n.string_property(index, 'UILayoutGuideIdentifier')! != ''
					|| n.boolean(index, 'UILayoutGuideOwningViewIsLocked', false)! || n.boolean(index, 'UILayoutGuideShouldBeArchived', false)!
					|| n.boolean(index, 'UILayoutGuideAllowsNegativeDimensions', false)! { return error('compiled storyboard layout constraints are unsupported') }
			}
			else {}
		}
	}
	if n.class(0) != 'NSObject' { return error('compiled storyboard root is missing') }
	for key in ['UINibTopLevelObjectsKey', 'UINibObjectsKey', 'UINibConnectionsKey', 'UINibVisibleWindowsKey', 'UINibAccessibilityConfigurationsKey', 'UINibTraitStorageListsKey', 'UINibKeyValuePairsKey']! {
		items := n.array(n.reference(0, key)!)!
		defer { unsafe { items.free() } }
		if key !in ['UINibTopLevelObjectsKey', 'UINibObjectsKey', 'UINibConnectionsKey']! && items.len != 0 { return error('unsupported compiled storyboard root configuration') }
	}
}

fn (n &StoryboardNib) connections(count int) ![]int {
	items := n.array(n.reference(0, 'UINibConnectionsKey')!)!
	mut complete := false
	defer { if !complete { unsafe { items.free() } } }
	if items.len != count { return error('unsupported compiled storyboard connection count') }
	for item in items { if n.class(item) != 'UIRuntimeOutletConnection' { return error('unsupported compiled storyboard connection') } }
	complete = true
	return items
}

fn (n &StoryboardNib) proxy(object int, name string) bool {
	if n.class(object) != 'UIProxyObject' { return false }
	identifier := n.string_property(object, 'UIProxiedObjectIdentifier') or { return false }
	return identifier == name
}

fn (n &StoryboardNib) outlet(connections []int, label string) !int {
	mut found := -1
	for connection in connections {
		if n.string_property(connection, 'UILabel')! == label {
			if found != -1 { return error('duplicate compiled storyboard outlet') }
			found = connection
		}
	}
	if found == -1 { return error('missing compiled storyboard outlet: ${label}') }
	return found
}

fn (n &StoryboardNib) doubles(object int, key string, count int) ![]f64 {
	value := n.required(object, key)!
	if value.kind != 8 || value.data.len != 1 + count * 8 || value.data[0] != 7 { return error('unsupported compiled storyboard geometry') }
	mut result := []f64{cap: count}
	mut complete := false
	defer { if !complete { unsafe { result.free() } } }
	for i in 0 .. count {
		mut bits := u64(0)
		for b in 0 .. 8 { bits |= u64(value.data[1 + i * 8 + b]) << (b * 8) }
		number := unsafe { *(&f64(&bits)) }
		if !math.is_finite(number) || math.abs(number) > 8192 { return error('compiled storyboard geometry exceeds limit') }
		result << number
	}
	complete = true
	return result
}

fn (mut n StoryboardNib) view(object int, depth int) !&StoryboardNode {
	if depth > 32 || n.remaining <= 0 || object in n.seen { return error('compiled storyboard view cycle, alias or limit') }
	n.remaining--; n.seen[object] = true
	cls := n.class(object)
	if cls !in ['UIView', 'UIImageView']! { return error('unsupported compiled storyboard view class') }
	mut node := &StoryboardNode{name: if cls == 'UIView' { 'view' } else { 'imageView' }, compiled: true}
	node.children.flags |= .noslices
	mut complete := false
	defer { if !complete { storyboard_node_free(node) } }
	bounds := n.doubles(object, 'UIBounds', 4)!
	defer { unsafe { bounds.free() } }
	center := n.doubles(object, 'UICenter', 2)!
	defer { unsafe { center.free() } }
	if bounds[0] != 0 || bounds[1] != 0 || bounds[2] < 0 || bounds[3] < 0 { return error('unsupported compiled storyboard bounds') }
	node.compiled_frame = ObjRect{center[0] - bounds[2] / 2, center[1] - bounds[3] / 2, bounds[2], bounds[3]}
	node.compiled_mask = n.integer(object, 'UIAutoresizingMask')!
	if node.compiled_mask > 63 || !n.boolean(object, 'UIAutoresizeSubviews', true)!
		|| !n.boolean(object, 'UIDeepDrawRect', true)! { return error('unsupported compiled storyboard resizing/drawing') }
	node.compiled_opaque = n.boolean(object, 'UIOpaque', true)!
	node.compiled_interaction = !n.boolean(object, 'UIUserInteractionDisabled', cls == 'UIImageView')!
	node.compiled_clips = n.boolean(object, 'UIClipsToBounds', false)!
	if cls == 'UIView' && (!node.compiled_opaque || !node.compiled_interaction || node.compiled_clips) {
		return error('unsupported compiled storyboard UIView flags')
	}
	if _ := n.property(object, 'UIViewSemanticContentAttribute') {
		if n.integer(object, 'UIViewSemanticContentAttribute')! != 0 { return error('compiled storyboard semantic direction is unsupported') }
	}
	if value := n.property(object, 'UIViewLargeContentStoredProperties') {
		if value.kind != 9 { return error('compiled storyboard large content is unsupported') }
	}
	if _ := n.property(object, 'UIViewContentHuggingPriority') {
		if n.string_property(object, 'UIViewContentHuggingPriority')! != '{251, 251}' { return error('compiled storyboard hugging constraints are unsupported') }
	}
	if _ := n.property(object, 'UIContentMode') {
		mode := n.integer(object, 'UIContentMode')!
		if mode > 12 || cls != 'UIImageView' { return error('unsupported compiled storyboard content mode') }
		node.compiled_mode = i64(mode)
	}
	if _ := n.property(object, 'UIBackgroundColor') {
		color := n.reference(object, 'UIBackgroundColor')!
		if n.class(color) != 'UIColor' || n.integer(color, 'UIColorComponentCount')! != 4
			|| n.integer(color, 'NSColorSpace')! != 2 || n.number(color, 'UIAlpha')! != 1 { return error('unsupported compiled storyboard color') }
		mut rgb := u32(0)
		for key in ['UIRed', 'UIGreen', 'UIBlue']! {
			channel := n.number(color, key)!
			if channel < 0 || channel > 1 { return error('invalid compiled storyboard color channel') }
			rgb = (rgb << 8) | u32(math.round(channel * 255))
		}
		node.compiled_color = rgb
	}
	if cls == 'UIImageView' {
		image := n.reference(object, 'UIImage')!
		if n.class(image) != 'UIImageNibPlaceholder' || n.number(image, 'UIImageWidth')! <= 0 || n.number(image, 'UIImageHeight')! <= 0 { return error('unsupported compiled storyboard image') }
		name := n.string_property(image, 'UIResourceName')!
		if !storyboard_resource_name(name) { return error('invalid compiled storyboard image resource name') }
		path := os.join_path(ios_runtime.bundle, name)
		defer { unsafe { path.free() } }
		node.compiled_image = storyboard_resource(path, 16 * 1024 * 1024)!
		if node.compiled_image.len > n.image_budget { return error('compiled storyboard image budget exceeded') }
		n.image_budget -= node.compiled_image.len
	} else if _ := n.property(object, 'UIImage') { return error('compiled storyboard image requires UIImageView') }
	if _ := n.property(object, 'UISubviews') {
		items := n.array(n.reference(object, 'UISubviews')!)!
		defer { unsafe { items.free() } }
		if items.len > 64 { return error('compiled storyboard subviews exceed limit') }
		mut children := &StoryboardNode{name: 'subviews'}
		children.children.flags |= .noslices
		node.children << children
		for item in items { children.children << n.view(item, depth + 1)! }
	}
	complete = true
	return node
}

fn storyboard_nib_view(path string) !&StoryboardNode {
	bytes := storyboard_resource(path, 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	archive := nib.parse(bytes)!
	defer { archive.free() }
	mut n := StoryboardNib{archive: &archive}
	defer { unsafe { n.seen.free() } }
	n.validate()!
	connections := n.connections(1)!
	defer { unsafe { connections.free() } }
	connection := n.outlet(connections, 'view')!
	if !n.proxy(n.reference(connection, 'UISource')!, 'IBFilesOwner') { return error('compiled storyboard view owner is unsupported') }
	root := n.view(n.reference(connection, 'UIDestination')!, 0)!
	mut complete := false
	defer { if !complete { storyboard_node_free(root) } }
	if root.name != 'view' { return error('compiled storyboard root requires UIView') }
	for i, _ in archive.objects {
		if n.class(i) in ['UIView', 'UIImageView']! && i !in n.seen { return error('unconnected compiled storyboard view') }
	}
	complete = true
	return root
}

fn storyboard_nib_controller(directory string, name string, identifier string) !&StoryboardNode {
	if !storyboard_resource_name(name) || !storyboard_resource_name(identifier) { return error('invalid compiled storyboard controller name') }
	path := os.join_path(directory, name + '.nib')
	defer { unsafe { path.free() } }
	bytes := storyboard_resource(path, 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	archive := nib.parse(bytes)!
	defer { archive.free() }
	n := StoryboardNib{archive: &archive}
	n.validate()!
	connections := n.connections(2)!
	defer { unsafe { connections.free() } }
	connection := n.outlet(connections, 'sceneViewController')!
	if !n.proxy(n.reference(connection, 'UISource')!, 'IBFilesOwner') { return error('unsupported compiled storyboard controller owner') }
	controller := n.reference(connection, 'UIDestination')!
	if n.class(controller) != 'UIClassSwapper' || n.string_property(controller, 'UIClassName')! != 'UIViewController'
		|| n.string_property(controller, 'UIOriginalClassName')! != 'UIViewController'
		|| n.string_property(controller, 'UIStoryboardIdentifier')! != identifier
		|| n.string_property(controller, 'UIRestorationIdentifier')! != identifier { return error('unsupported compiled storyboard controller') }
	external := n.array(n.reference(controller, 'UIExternalObjectsTableForViewLoading')!)!
	defer { unsafe { external.free() } }
	if external.len != 0 { return error('compiled storyboard external objects are unsupported') }
	storyboard := n.outlet(connections, 'storyboard')!
	if n.reference(storyboard, 'UISource')! != controller || !n.proxy(n.reference(storyboard, 'UIDestination')!, 'UIStoryboardPlaceholder') { return error('unsupported compiled storyboard back reference') }
	view_name := n.string_property(controller, 'UINibName')!
	if !storyboard_resource_name(view_name) { return error('invalid compiled storyboard view name') }
	view_path := os.join_path(directory, view_name + '.nib')
	defer { unsafe { view_path.free() } }
	mut node := &StoryboardNode{name: 'viewController'}
	node.children.flags |= .noslices
	mut complete := false
	defer { if !complete { storyboard_node_free(node) } }
	node.attributes['id'] = identifier.clone()
	node.attributes['storyboardIdentifier'] = identifier.clone()
	node.children << storyboard_nib_view(view_path)!
	complete = true
	return node
}

fn storyboard_compiled(name string) !&StoryboardNode {
	base := os.join_path(ios_runtime.bundle, 'Base.lproj', name + '.storyboardc')
	plain := os.join_path(ios_runtime.bundle, name + '.storyboardc')
	defer { unsafe { base.free(); plain.free() } }
	directory := if os.is_dir(base) { base } else { plain }
	path := os.join_path(directory, 'Info.plist')
	defer { unsafe { path.free() } }
	bytes := storyboard_resource(path, 65536)!
	defer { unsafe { bytes.free() } }
	info := plist.parse(bytes)!
	defer { info.free() }
	version := info.fields['UIStoryboardVersion']
	entry := info.fields['UIStoryboardDesignatedEntryPointIdentifier']
	controllers := info.fields['UIViewControllerIdentifiersToNibNames']
	if info.kind != .dictionary || version.kind != .integer || version.integer != 1 || entry.kind != .string
		|| controllers.kind != .dictionary || controllers.fields.len != 1
		|| entry.text !in controllers.fields { return error('unsupported compiled storyboard index') }
	mut root := &StoryboardNode{name: 'document'}
	root.children.flags |= .noslices
	mut complete := false
	defer { if !complete { storyboard_node_free(root) } }
	root.attributes['initialViewController'] = entry.text.clone()
	for identifier, resource in controllers.fields {
		if resource.kind != .string { return error('invalid compiled storyboard controller resource') }
		root.children << storyboard_nib_controller(directory, resource.text, identifier)!
	}
	complete = true
	return root
}
