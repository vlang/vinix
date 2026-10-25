// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import math.bits

// Constructor/property profile only. Downloading, access completion and progress
// need an on-demand resource provider; they must not report fictitious success.
fn ns_bundle_resource_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSBundleResourceRequest']] or { panic('iOS: missing resource request class') }
	for i, pair in [['_tags', '@"NSSet"']!, ['_priority', 'd']!, ['_bundle', '@"NSBundle"']!, ['_progress', '@"NSProgress"']!, ['_fetchState', 'q']!]! {
		cls.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn ns_bundle_resource_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSBundleResourceRequest' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic resource request superclass chain')
}

fn ns_bundle_resource_require_class(cls u64) {
	if ns_bundle_resource_family(cls) && cls != ios_runtime.names['NSBundleResourceRequest'] { panic('iOS: custom resource request construction is not implemented') }
}

// Runtime lock held. Allocation ownership survives changes to isa.
fn ns_bundle_resource_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.bundle_resource_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size != 48
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSBundleResourceRequest']
		|| read64(object + 8) != header.fields[0] || read64(object + 24) != header.fields[1]
		|| read64(object + 16) != bits.f64_bits(header.bundle_resource_priority)
		|| read64(object + 32) != 0 || read64(object + 40) != 0 {
		panic('iOS: resource request requires live owned storage')
	}
	if initialized && !header.bundle_resource_initialized { panic('iOS: resource request requires initialization') }
	return header
}

fn ns_bundle_resource_bundle(object u64) {
	if object == 0 { panic('iOS: resource request requires a bundle') }
	header := obj_header(object)
	if object == 0 || object != ios_runtime.bundle_object || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSBundle'] {
		panic('iOS: resource requests support the live built-in main bundle only')
	}
}

// Publish one runtime-owned bundle. Constructors can reenter on another thread.
fn ns_main_bundle() u64 {
	C.ios_objc_initialize_lock()
	current := ios_runtime.bundle_object
	if current != 0 { ns_bundle_resource_bundle(current) }
	C.ios_objc_initialize_unlock()
	if current != 0 { return current }
	candidate := objc_allocate(ios_runtime.names['NSBundle'])
	if candidate == 0 { return 0 }
	C.ios_objc_initialize_lock()
	header := obj_header(candidate)
	if header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.cls != header.allocation_cls || read64(candidate) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSBundle'] { panic('iOS: bundle constructor changed storage') }
	if ios_runtime.bundle_object == 0 { ios_runtime.bundle_object = candidate }
	winner := ios_runtime.bundle_object
	ns_bundle_resource_bundle(winner)
	C.ios_objc_initialize_unlock()
	if winner != candidate { objc_release(candidate) }
	return winner
}

// Take a shallow immutable-set snapshot before any application constructor can
// mutate or release the input. Built-in strings avoid custom hashing callbacks.
fn ns_bundle_resource_tags(tags u64) []u64 {
	mut items := []u64{cap: 4096}
	if tags == 0 { return items }
	header := obj_header(tags)
	if !header.set_owned || !header.set_initialized || header.set_mutating || header.cf_raw_values
		|| header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.cls != header.allocation_cls || read64(tags) != header.allocation_cls
		|| header.allocation_cls !in [ios_runtime.names['NSSet'], ios_runtime.names['NSMutableSet']]!
		|| header.items.len > 4096 { panic('iOS: resource tags require a live built-in set') }
	for item in header.items {
		string_header := obj_header(item)
		if string_header.destroying || string_header.destroyed || C.ios_ref_change(unsafe { &string_header.refs }, 0) <= 0
			|| string_header.cls != string_header.allocation_cls || read64(item) != string_header.allocation_cls
			|| string_header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (string_header.mutable_string_owned && !string_header.mutable_string_initialized) {
			panic('iOS: resource tags require built-in initialized strings')
		}
		text := cf_string_compare_text(item) or { panic('iOS: resource tags require UTF8 strings') }
		if text.len > 65536 { panic('iOS: resource tag exceeds byte limit') }
		items << objc_retain(item)
	}
	return items
}

fn ns_bundle_resource_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.bundle_resource_initializing { panic('iOS: destroying an active resource request') }
}

fn ns_bundle_resource_dispose(object u64, mut header ObjHeader) {
	if !header.bundle_resource_owned { return }
	// Generic field destruction releases the copied set and retained bundle.
	unsafe { C.memset(voidptr(object + 8), 0, 40) }
	header.bundle_resource_initialized = false
}

fn ns_bundle_resource_failed_init(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_bundle_resource_storage(object, false)
	if C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: resource constructor consumed receiver ownership') }
	if header.caller_storage { panic('iOS: failed resource initializer cannot consume caller-owned storage') }
	header.bundle_resource_initializing = false
	C.ios_objc_initialize_unlock()
	objc_release(object)
	return 0
}

fn ns_bundle_resource_initialize(object u64, tags u64, requested_bundle u64, explicit bool) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_bundle_resource_storage(object, false)
	if header.bundle_resource_initialized || header.bundle_resource_initializing || header.fields[0] != 0 || header.fields[1] != 0 {
		panic('iOS: resource request is already initialized')
	}
	items := ns_bundle_resource_tags(tags)
	if requested_bundle != 0 { ns_bundle_resource_bundle(requested_bundle); objc_retain(requested_bundle) }
	header.bundle_resource_initializing = true
	objc_retain(object)
	C.ios_objc_initialize_unlock()
	defer {
		for item in items { objc_release(item) }
		unsafe { items.free() }
		objc_release(requested_bundle)
		objc_release(object)
	}
	// These allocations may invoke application constructors: never hold the lock.
	bundle := if explicit { requested_bundle } else { ns_main_bundle() }
	if !explicit && bundle == 0 { return ns_bundle_resource_failed_init(object) }
	copied := if tags != 0 { objc_allocate(ios_runtime.names['NSSet']) } else { u64(0) }
	defer { objc_release(copied) }
	if tags != 0 && copied == 0 { return ns_bundle_resource_failed_init(object) }
	C.ios_objc_initialize_lock()
	header = ns_bundle_resource_storage(object, false)
	if !header.bundle_resource_initializing || header.bundle_resource_initialized
		|| header.fields[0] != 0 || header.fields[1] != 0
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: resource constructor changed destination storage') }
	if bundle != 0 { ns_bundle_resource_bundle(bundle) }
	if copied != 0 {
		mut target := obj_header(copied)
		if !target.set_owned || target.set_initialized || target.items.len != 0 || target.destroying || target.destroyed
			|| C.ios_ref_change(unsafe { &target.refs }, 0) <= 0
			|| target.cls != target.allocation_cls || read64(copied) != target.allocation_cls
			|| target.allocation_cls != ios_runtime.names['NSSet'] { panic('iOS: resource constructor changed copied tags') }
		ns_set_initialize(copied, u64(items.len))
		for item in items { array_append(mut target, item) }
	}
	header.fields[0] = objc_retain(copied)
	header.fields[1] = objc_retain(bundle)
	header.bundle_resource_priority = 0.5
	header.bundle_resource_initialized = true
	header.bundle_resource_initializing = false
	unsafe {
		*(&u64(object + 8)) = header.fields[0]
		*(&f64(object + 16)) = 0.5
		*(&u64(object + 24)) = header.fields[1]
	}
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_bundle_resource_types(name string, meta bool, selector string) ?string {
	if name != 'NSBundleResourceRequest' || meta { return none }
	return match selector {
		'initWithTags:' { '@24@0:8@16' }
		'initWithTags:bundle:' { '@32@0:8@16@24' }
		'tags', 'bundle' { '@16@0:8' }
		'loadingPriority' { 'd16@0:8' }
		'setLoadingPriority:' { 'v24@0:8d16' }
		else { return none }
	}
}

fn ns_bundle_resource_unsupported(selector string) bool {
	return selector in ['init', 'new', 'progress', 'beginAccessingResourcesWithCompletionHandler:', 'conditionallyBeginAccessingResourcesWithCompletionHandler:',
		'endAccessingResources', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'initWithTag:', 'isEqual:', 'hash', 'description', 'debugDescription']!
}

fn ns_bundle_resource_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_bundle_resource_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.bundle_resource_owned }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_bundle_resource_unsupported(selector) { panic('iOS: resource access, progress, copying and this option are not implemented') }
	if ns_bundle_resource_types('NSBundleResourceRequest', meta, selector) == none { return false }
	if selector in ['initWithTags:', 'initWithTags:bundle:']! {
		explicit := selector == 'initWithTags:bundle:'
		frame.x[0] = ns_bundle_resource_initialize(object, frame.x[2], if explicit { frame.x[3] } else { u64(0) }, explicit)
		return true
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := ns_bundle_resource_storage(object, true)
	match selector {
		'tags' { frame.x[0] = header.fields[0] }
		'bundle' { frame.x[0] = header.fields[1] }
		'loadingPriority' { frame_float_return(mut frame, 0, header.bundle_resource_priority) }
		'setLoadingPriority:' {
			value := frame_double(frame, 0)
			if math.is_nan(value) || math.is_inf(value, 0) { panic('iOS: nonfinite resource priority is not implemented') }
			header.bundle_resource_priority = if value < 0 { 0.0 } else if value > 1 { 1.0 } else { value }
			unsafe { *(&f64(object + 16)) = header.bundle_resource_priority }
			frame.x[0] = 0
		}
		else { return false }
	}
	return true
}
