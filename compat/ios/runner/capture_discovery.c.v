// SPDX-License-Identifier: GPL-2.0-or-later
module main

// There is no capture hardware backend. Discovery validates its criteria and
// returns empty immutable arrays. Factory-only allocation and the opaque size
// are compatibility restrictions, not claims about native device storage.
fn capture_discovery_symbol(symbol string) ?u64 {
	return match symbol {
		'_OBJC_CLASS_$_AVCaptureDeviceDiscoverySession' { ios_runtime.names['AVCaptureDeviceDiscoverySession'] }
		'_OBJC_METACLASS_$_AVCaptureDeviceDiscoverySession' { read64(ios_runtime.names['AVCaptureDeviceDiscoverySession']) }
		else { none }
	}
}

fn capture_discovery_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'AVCaptureDeviceDiscoverySession' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic capture discovery superclass chain')
}

fn capture_discovery_unsupported(selector string) bool {
	return selector in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:',
		'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'classForCoder', 'addObserver:forKeyPath:options:context:',
		'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:']!
}

fn capture_discovery_require_factory(cls u64) {
	if capture_discovery_family(cls) { panic('iOS: AVCaptureDeviceDiscoverySession requires discovery factory') }
}

fn capture_discovery_install(cls u64, caller_storage bool) {
	if capture_discovery_family(cls) && (caller_storage || cls != ios_runtime.names['AVCaptureDeviceDiscoverySession']) {
		panic('iOS: AVCaptureDeviceDiscoverySession requires discovery factory')
	}
}

fn capture_discovery_storage(object u64) {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['AVCaptureDeviceDiscoverySession'] || header.caller_storage
		|| header.native_size != 48 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: capture discovery requires live built-in storage')
	}
}

fn capture_discovery_create(types u64, media u64, position u64) u64 {
	cls := ios_runtime.names['AVCaptureDeviceDiscoverySession']
	objc_initialize(cls)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[types] or { panic('iOS: capture discovery requires an NSArray of NSString device types') }
	if !objc_is_kind(types, ios_runtime.names['NSArray']) || header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.cf_raw_values {
		panic('iOS: capture discovery requires an NSArray of NSString device types')
	}
	for item in header.items {
		cf_string_compare_text(item) or { panic('iOS: capture discovery requires NSString device types') }
	}
	if media != 0 {
		cf_string_compare_text(media) or { panic('iOS: capture discovery requires NSString media type or nil') }
	}
	if position > 2 { panic('iOS: capture discovery requires position 0, 1 or 2') }
	object := u64(C.calloc(1, 48))
	if object == 0 { panic('iOS: cannot allocate capture discovery') }
	objc_install_storage(cls, object, false)
	// Criteria are inspected synchronously, never retained or borrowed afterward.
	return objc_autorelease(object)
}

fn capture_discovery_types(name string, meta bool, selector string) ?string {
	if name != 'AVCaptureDeviceDiscoverySession' { return none }
	if meta {
		if selector == 'discoverySessionWithDeviceTypes:mediaType:position:' { return '@40@0:8@16@24q32' }
		return none
	}
	if selector in ['devices', 'supportedMultiCamDeviceSets']! { return '@16@0:8' }
	return none
}

fn capture_discovery_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !capture_discovery_family(cls) { return false }
	if capture_discovery_unsupported(selector) { capture_discovery_require_factory(cls) }
	if capture_discovery_types('AVCaptureDeviceDiscoverySession', meta, selector) == none { return false }
	if meta {
		if object != ios_runtime.names['AVCaptureDeviceDiscoverySession'] {
			panic('iOS: custom capture discovery subclasses are not implemented')
		}
		frame.x[0] = capture_discovery_create(frame.x[2], frame.x[3], frame.x[4])
	} else {
		C.ios_objc_initialize_lock()
		defer { C.ios_objc_initialize_unlock() }
		capture_discovery_storage(object)
		frame.x[0] = ns_empty_array_symbol('___NSArray0__struct') or { panic('iOS: cannot create empty capture discovery results') }
	}
	return true
}
