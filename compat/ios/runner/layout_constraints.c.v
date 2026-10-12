// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import math.bits

// Native Foundation records: isa plus nine eight-byte slots, with the last
// slot holding two floats. Engine variables stay empty until a solver exists.
struct AbiLayoutConstraint {
mut:
	isa u64
	container u64
	first_anchor u64
	second_anchor u64
	constant f64
	lowered_constant f64
	marker u64
	negative_extra u64
	flags u64
	coefficient f32
	priority f32
}

struct AbiLayoutAnchor {
mut:
	isa u64
	item u64
	attribute i64
	variable u64
	name u64
	cached_items u64
	reserved u64
	flags u64
}

struct LayoutAnchors {
mut:
	values [13]u64
}

fn layout_anchor_attribute(selector string) i64 {
	return match selector {
		'leftAnchor' { 1 }
		'rightAnchor' { 2 }
		'topAnchor' { 3 }
		'bottomAnchor' { 4 }
		'leadingAnchor' { 5 }
		'trailingAnchor' { 6 }
		'widthAnchor' { 7 }
		'heightAnchor' { 8 }
		'centerXAnchor' { 9 }
		'centerYAnchor' { 10 }
		'lastBaselineAnchor' { 11 }
		'firstBaselineAnchor' { 12 }
		else { 0 }
	}
}

fn layout_anchor_kind(attribute i64) string {
	return match attribute {
		1, 2, 5, 6, 9 { 'NSLayoutXAxisAnchor' }
		3, 4, 10, 11, 12 { 'NSLayoutYAxisAnchor' }
		7, 8 { 'NSLayoutDimension' }
		else { panic('iOS: unsupported layout attribute') }
	}
}

fn layout_anchor(item u64, attribute i64) u64 {
	if !objc_is_kind(item, ios_runtime.names['UIView']) {
		panic('iOS: layout item must be a UIView; layout guides are not implemented')
	}
	name := layout_anchor_kind(attribute)
	mut header := obj_header(item)
	if header.layout_anchors == unsafe { nil } {
		header.layout_anchors = unsafe { &LayoutAnchors(C.calloc(1, sizeof(LayoutAnchors))) }
		if header.layout_anchors == unsafe { nil } { panic('iOS: cannot allocate layout anchors') }
	}
	if header.layout_anchors.values[attribute] == 0 {
		anchor := objc_allocate(ios_runtime.names[name])
		mut record := unsafe { &AbiLayoutAnchor(anchor) }
		record.attribute = attribute
		// Native anchors borrow the view. Use a zeroing slot so a retained
		// constraint cannot hand out freed Vinix view storage after teardown.
		objc_store_weak(unsafe { &record.item }, item)
		header.layout_anchors.values[attribute] = anchor
	}
	return header.layout_anchors.values[attribute]
}

fn layout_constraint_initialize(object u64) {
	mut record := unsafe { &AbiLayoutConstraint(object) }
	record.coefficient = 1
	record.priority = 1000
}

fn layout_constraint_create(cls u64, first u64, relation i64, second u64, multiplier f64, constant f64) u64 {
	if first == 0 || !objc_is_kind(first, ios_runtime.names['NSLayoutAnchor'])
		|| (second != 0 && !objc_is_kind(second, ios_runtime.names['NSLayoutAnchor'])) {
		panic('iOS: constraint requires layout anchors')
	}
	if relation < -1 || relation > 1 { panic('iOS: invalid layout relation') }
	if !math.is_finite(multiplier) || !math.is_finite(constant)
		|| !math.is_finite(f64(f32(multiplier))) { panic('iOS: non-finite layout coefficient') }
	object := objc_allocate(cls)
	mut record := unsafe { &AbiLayoutConstraint(object) }
	record.first_anchor = objc_retain(first)
	record.second_anchor = objc_retain(second)
	record.coefficient = if second == 0 { f32(1) } else { f32(multiplier) }
	record.constant = constant
	obj_header(object).number = relation
	return objc_autorelease(object)
}

fn layout_constraint_from_items(cls u64, first u64, first_attribute i64, relation i64, second u64, second_attribute i64, multiplier f64, constant f64) u64 {
	if (second == 0 && (first_attribute !in [i64(7), 8] || second_attribute != 0))
		|| (second != 0 && second_attribute == 0) {
		panic('iOS: invalid item-less layout dimension')
	}
	a := layout_anchor(first, first_attribute)
	b := if second == 0 { u64(0) } else { layout_anchor(second, second_attribute) }
	return layout_constraint_create(cls, a, relation, b, multiplier, constant)
}

fn layout_dispose(object u64, mut header ObjHeader) {
	if objc_is_kind(object, ios_runtime.names['NSLayoutConstraint']) {
		mut record := unsafe { &AbiLayoutConstraint(object) }
		objc_release(record.first_anchor)
		objc_release(record.second_anchor)
		record.first_anchor = 0
		record.second_anchor = 0
	} else if objc_is_kind(object, ios_runtime.names['NSLayoutAnchor']) {
		mut record := unsafe { &AbiLayoutAnchor(object) }
		objc_destroy_weak(unsafe { &record.item })
	}
	if header.layout_anchors != unsafe { nil } {
		for anchor in header.layout_anchors.values { objc_release(anchor) }
		C.free(header.layout_anchors)
		header.layout_anchors = unsafe { nil }
	}
}

fn layout_builtin_types(name string, meta bool, selector string) ?string {
	if name == 'NSLayoutConstraint' {
		if meta {
			return match selector {
				'constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:' { '@72@0:8@16q24q32@40q48d56d64' }
				'constraintWithItem:attribute:relatedBy:toItem:attribute:' { '@56@0:8@16q24q32@40q48' }
				'constraintWithItem:attribute:relatedBy:toItem:attribute:constant:',
				'constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:' { '@64@0:8@16q24q32@40q48d56' }
				'constraintWithItem:attribute:relatedBy:constant:' { '@48@0:8@16q24q32d40' }
				'constraintWithAnchor:relatedBy:toAnchor:multiplier:constant:' { '@56@0:8@16q24@32d40d48' }
				'activateConstraints:', 'deactivateConstraints:' { 'v24@0:8@16' }
				else { return none }
			}
		}
		return match selector {
			'constant', 'multiplier' { 'd16@0:8' }
			'priority' { 'f16@0:8' }
			'setPriority:' { 'v20@0:8f16' }
			'setConstant:' { 'v24@0:8d16' }
			'firstItem', 'secondItem', 'firstAnchor', 'secondAnchor', 'identifier' { '@16@0:8' }
			'setIdentifier:' { 'v24@0:8@16' }
			'firstAttribute', 'secondAttribute', 'relation' { 'q16@0:8' }
			'isActive', 'shouldBeArchived' { 'B16@0:8' }
			'setActive:', 'setShouldBeArchived:' { 'v20@0:8B16' }
			else { return none }
		}
	}
	if !meta && name in ['NSLayoutAnchor', 'NSLayoutDimension', 'NSLayoutXAxisAnchor', 'NSLayoutYAxisAnchor'] {
		return match selector {
			'constraintEqualToAnchor:', 'constraintGreaterThanOrEqualToAnchor:', 'constraintLessThanOrEqualToAnchor:' { '@24@0:8@16' }
			'constraintEqualToAnchor:constant:', 'constraintGreaterThanOrEqualToAnchor:constant:', 'constraintLessThanOrEqualToAnchor:constant:' { '@32@0:8@16d24' }
			else {
				if name != 'NSLayoutDimension' { return none }
				return match selector {
					'constraintEqualToConstant:', 'constraintGreaterThanOrEqualToConstant:', 'constraintLessThanOrEqualToConstant:' { '@24@0:8d16' }
					'constraintEqualToAnchor:multiplier:', 'constraintGreaterThanOrEqualToAnchor:multiplier:', 'constraintLessThanOrEqualToAnchor:multiplier:' { '@32@0:8@16d24' }
					'constraintEqualToAnchor:multiplier:constant:', 'constraintGreaterThanOrEqualToAnchor:multiplier:constant:', 'constraintLessThanOrEqualToAnchor:multiplier:constant:' { '@40@0:8@16d24d32' }
					else { return none }
				}
			}
		}
	}
	return none
}

fn layout_selector(object u64, selector string) bool {
	if object !in ios_runtime.classes && objc_is_kind(object, ios_runtime.names['UIView']) {
		return layout_anchor_attribute(selector) != 0
	}
	info := ios_runtime.classes[objc_class(object)] or { return false }
	if _ := layout_builtin_types(info.name, object in ios_runtime.classes, selector) { return true }
	return false
}

fn layout_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	cls := objc_class(object)
	if object in ios_runtime.classes {
		if cls != ios_runtime.names['NSLayoutConstraint'] { return false }
		if _ := layout_builtin_types('NSLayoutConstraint', true, selector) {} else { return false }
		if selector in ['activateConstraints:', 'deactivateConstraints:'] {
			array := frame.x[2]
			if !objc_is_kind(array, ios_runtime.names['NSArray']) { panic('iOS: constraint batch must be an array') }
			for constraint in obj_header(array).items {
				if !objc_is_kind(constraint, cls) { panic('iOS: constraint batch contains a non-constraint') }
			}
			if selector == 'activateConstraints:' && obj_header(array).items.len != 0 {
				panic('iOS: Auto Layout constraint activation requires a solver')
			}
			return true
		}
		if selector == 'constraintWithAnchor:relatedBy:toAnchor:multiplier:constant:' {
			frame.x[0] = layout_constraint_create(cls, frame.x[2], i64(frame.x[3]), frame.x[4], frame_double(frame, 0), frame_double(frame, 1))
			return true
		}
		mut second := frame.x[5]
		mut attribute := i64(frame.x[6])
		mut multiplier := f64(1)
		mut constant := f64(0)
		match selector {
			'constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:' {
				multiplier = frame_double(frame, 0); constant = frame_double(frame, 1)
			}
			'constraintWithItem:attribute:relatedBy:toItem:attribute:constant:' { constant = frame_double(frame, 0) }
			'constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:' { multiplier = frame_double(frame, 0) }
			'constraintWithItem:attribute:relatedBy:constant:' {
				second = 0; attribute = 0; constant = frame_double(frame, 0)
			}
			else {}
		}
		frame.x[0] = layout_constraint_from_items(cls, frame.x[2], i64(frame.x[3]), i64(frame.x[4]), second, attribute, multiplier, constant)
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UIView']) {
		attribute := layout_anchor_attribute(selector)
		if attribute == 0 { return false }
		frame.x[0] = layout_anchor(object, attribute)
		return true
	}
	if objc_is_kind(object, ios_runtime.names['NSLayoutAnchor']) {
		info := ios_runtime.classes[cls] or { return false }
		if _ := layout_builtin_types(info.name, false, selector) {} else { return false }
		relation := if selector.starts_with('constraintLess') { i64(-1) } else if selector.starts_with('constraintGreater') { i64(1) } else { i64(0) }
		second := if selector.contains('ToConstant:') { u64(0) } else { frame.x[2] }
		if second != 0 && (!objc_is_kind(second, cls) || cls == ios_runtime.names['NSLayoutAnchor']) {
			panic('iOS: incompatible layout anchor axes')
		}
		if second == 0 && !selector.contains('ToConstant:') { panic('iOS: anchor constraint requires a second anchor') }
		multiplier := if selector.contains('multiplier:') { frame_double(frame, 0) } else { f64(1) }
		constant := if selector.contains('constant:') || second == 0 { frame_double(frame, if selector.contains('multiplier:') { 1 } else { 0 }) } else { f64(0) }
		frame.x[0] = layout_constraint_create(ios_runtime.names['NSLayoutConstraint'], object, relation, second, multiplier, constant)
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['NSLayoutConstraint']) { return false }
	mut record := unsafe { &AbiLayoutConstraint(object) }
	mut header := obj_header(object)
	match selector {
		'init' {}
		'constant' { frame_float_return(mut frame, 0, record.constant) }
		'multiplier' { frame_float_return(mut frame, 0, f64(record.coefficient)) }
		'priority' { frame.q[0] = u64(bits.f32_bits(record.priority)); frame.q[1] = 0 }
		'setConstant:' {
			value := frame_double(frame, 0)
			if !math.is_finite(value) { panic('iOS: non-finite layout constant') }
			record.constant = value
		}
		'setPriority:' {
			value := bits.f32_from_bits(u32(frame.q[0]))
			if !math.is_finite(f64(value)) || value <= 0 || value > 1000 { panic('iOS: invalid layout priority') }
			record.priority = value
		}
		'firstAnchor' { frame.x[0] = record.first_anchor }
		'secondAnchor' { frame.x[0] = record.second_anchor }
		'firstItem', 'secondItem', 'firstAttribute', 'secondAttribute' {
			anchor := if selector.starts_with('first') { record.first_anchor } else { record.second_anchor }
			frame.x[0] = if anchor == 0 { u64(0) } else if selector.ends_with('Item') { unsafe { (&AbiLayoutAnchor(anchor)).item } } else { unsafe { u64((&AbiLayoutAnchor(anchor)).attribute) } }
		}
		'relation' { frame.x[0] = u64(header.number) }
		'identifier' { frame.x[0] = header.fields[0] }
		'setIdentifier:' {
			if frame.x[2] != 0 && !objc_is_kind(frame.x[2], ios_runtime.names['NSString']) { panic('iOS: constraint identifier must be a string') }
			copy := if frame.x[2] == 0 { u64(0) } else { owned_string(string_text(frame.x[2])) }
			store_field(object, 0, copy)
			objc_release(copy)
		}
		'shouldBeArchived' { frame.x[0] = u64(header.valid) }
		'setShouldBeArchived:' { header.valid = u8(frame.x[2]) != 0 }
		'isActive' { frame.x[0] = 0 }
		'setActive:' { if u8(frame.x[2]) != 0 { panic('iOS: Auto Layout constraint activation requires a solver') } }
		else { return false }
	}
	return true
}
