// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Public iOS UIViewController hierarchy with an opaque Catalyst-sized reserve.
// Private layout differs on Catalyst; state stays in ObjHeader. No device
// transport exists yet, so this implements configuration, not event delivery.
fn gc_event_controller_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GCEventViewController' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GCEventViewController superclass chain')
}

fn gc_event_controller_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn gc_event_controller_types(name string, meta bool, selector string) ?string {
	if name != 'GCEventViewController' || meta { return none }
	return match selector {
		'init' { '@16@0:8' }
		'initWithNibName:bundle:' { '@32@0:8@16@24' }
		'controllerUserInteractionEnabled' { 'B16@0:8' }
		'setControllerUserInteractionEnabled:' { 'v20@0:8B16' }
		else { none }
	}
}

fn gc_event_controller_require_storage(object u64, initialized bool) {
	header := obj_header(object)
	if header.destroying || header.destroyed || header.caller_storage
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 1112
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| !gc_event_controller_family(header.allocation_cls) {
		panic('iOS: GCEventViewController requires live owned controller storage')
	}
	if initialized && !header.gc_event_controller_initialized {
		panic('iOS: GCEventViewController requires initialization')
	}
}

fn gc_event_controller_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	gc_event_controller_require_storage(object, false)
	// Allocation supplies default NO. Native repeated initialization preserves it.
	obj_header(object).gc_event_controller_initialized = true
	return object
}

fn gc_event_controller_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !gc_event_controller_family(cls) { return false }
	if gc_event_controller_unsupported(selector) { panic('iOS: unsupported GCEventViewController method: ' + selector) }
	if meta || gc_event_controller_types('GCEventViewController', false, selector) == none { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	gc_event_controller_require_storage(object, selector !in ['init', 'initWithNibName:bundle:']!)
	match selector {
		'init', 'initWithNibName:bundle:' {
			if selector == 'initWithNibName:bundle:' && (frame.x[2] != 0 || frame.x[3] != 0) {
				panic('iOS: GCEventViewController nib resources are not implemented')
			}
			frame.x[0] = gc_event_controller_initialize(object)
		}
		'controllerUserInteractionEnabled' { frame.x[0] = u64(obj_header(object).gc_event_controller_interaction) }
		'setControllerUserInteractionEnabled:' {
			obj_header(object).gc_event_controller_interaction = u8(frame.x[2]) != 0
			frame.x[0] = 0
		}
		else {}
	}
	return true
}
