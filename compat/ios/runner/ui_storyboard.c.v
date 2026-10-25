// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn storyboard_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UIStoryboard' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic storyboard superclass chain')
}

fn storyboard_unsupported(selector string) bool {
	return selector in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:',
		'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'classForCoder', 'instantiateInitialViewControllerWithCreator:',
		'instantiateViewControllerWithIdentifier:creator:']!
}

fn storyboard_require_factory(cls u64) {
	if storyboard_family(cls) { panic('iOS: UIStoryboard requires storyboardWithName:bundle:') }
}

fn storyboard_types(name string, meta bool, selector string) ?string {
	if name != 'UIStoryboard' { return none }
	if meta {
		if selector == 'storyboardWithName:bundle:' { return '@32@0:8@16@24' }
		return none
	}
	return match selector {
		'instantiateInitialViewController' { '@16@0:8' }
		'instantiateViewControllerWithIdentifier:' { '@24@0:8@16' }
		else { none }
	}
}

fn storyboard_open(name string, bundle u64) !u64 {
	if bundle != 0 && (bundle != ios_runtime.bundle_object || bundle !in ios_runtime.objects
		|| read64(bundle) != ios_runtime.names['NSBundle']) { return error('storyboard requires the main bundle') }
	if name.len == 0 || name.len > 128 || name.contains('/') || name.contains('\\')
		|| name.contains('..') || name.contains('\x00') { return error('invalid storyboard resource name') }
	filename := name + '.storyboard'
	defer { unsafe { filename.free() } }
	base := os.join_path(ios_runtime.bundle, 'Base.lproj', filename)
	plain := os.join_path(ios_runtime.bundle, filename)
	defer { unsafe { base.free(); plain.free() } }
	path := if os.is_file(base) { base } else { plain }
	if !os.is_file(path) { return error('storyboard source is missing; compiled storyboardc resources are unsupported') }
	resolved := os.real_path(path)
	bundle_root := os.real_path(ios_runtime.bundle)
	root := bundle_root + os.path_separator
	defer { unsafe { resolved.free(); bundle_root.free(); root.free() } }
	if !resolved.starts_with(root) { return error('storyboard resource escapes the main bundle') }
	if os.file_size(resolved) > 1024 * 1024 { return error('storyboard resource exceeds size limit') }
	bytes := os.read_bytes(resolved)!
	mut complete := false
	defer { if !complete { unsafe { bytes.free() } } }
	tree := storyboard_parse(unsafe { tos(bytes.data, bytes.len) })!
	defer { if !complete { storyboard_node_free(tree) } }
	cls := ios_runtime.names['UIStoryboard']
	objc_initialize(cls)
	// Opaque compatibility storage, not Apple's private instance layout.
	object := u64(C.calloc(1, 8))
	if object == 0 { return error('cannot allocate storyboard') }
	objc_install_storage(cls, object, false)
	mut header := obj_header(object)
	unsafe { header.data.free() }
	header.data = bytes
	header.storyboard_root = tree
	complete = true
	return object
}

fn storyboard_string(object u64) string {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	text := cf_string_compare_text(object) or { panic('iOS: storyboard requires an NSString argument') }
	return text.clone()
}

fn storyboard_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !storyboard_family(cls) { return false }
	if storyboard_unsupported(selector) { panic('iOS: unsupported storyboard construction, coding or creator method') }
	if storyboard_types('UIStoryboard', meta, selector) == none { return false }
	if meta {
		if object != ios_runtime.names['UIStoryboard'] { panic('iOS: custom storyboard subclasses are unsupported') }
		name := storyboard_string(frame.x[2])
		defer { unsafe { name.free() } }
		frame.x[0] = objc_autorelease(storyboard_open(name, frame.x[3]) or { panic('iOS: ${err}') })
		return true
	}
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['UIStoryboard'] || header.caller_storage
		|| header.native_size != 8 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.storyboard_root == unsafe { nil } || header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 { panic('iOS: storyboard requires live built-in storage') }
	// Retain the immutable resource across custom controller +initialize/init.
	objc_retain(object)
	defer { objc_release(object) }
	initial := selector == 'instantiateInitialViewController'
	identifier := if initial { header.storyboard_root.attributes['initialViewController'].clone() } else { storyboard_string(frame.x[2]) }
	defer { unsafe { identifier.free() } }
	if identifier == '' {
		if initial { frame.x[0] = 0; return true }
		panic('iOS: storyboard controller identifier is empty')
	}
	frame.x[0] = objc_autorelease(storyboard_controller(header.storyboard_root,
		if initial { 'id' } else { 'storyboardIdentifier' }, identifier) or { panic('iOS: ${err}') })
	return true
}
