// SPDX-License-Identifier: GPL-2.0-or-later
module main

// No App Attest provider exists. Availability is false; key generation,
// attestation and assertions remain unsupported. The factory-only storage
// profile is a shim restriction, not a native allocation contract.

fn app_attest_symbol(symbol string) ?u64 {
	return match symbol {
		'_OBJC_CLASS_$_DCAppAttestService' { ios_runtime.names['DCAppAttestService'] }
		'_OBJC_METACLASS_$_DCAppAttestService' { read64(ios_runtime.names['DCAppAttestService']) }
		else { none }
	}
}

fn app_attest_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'DCAppAttestService' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic App Attest superclass chain')
}

fn app_attest_unsupported(selector string) bool {
	return selector in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:',
		'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'classForCoder']!
}

fn app_attest_require_factory(cls u64) {
	if app_attest_family(cls) { panic('iOS: DCAppAttestService requires sharedService') }
}

fn app_attest_install(cls u64, caller_storage bool) {
	if app_attest_family(cls) && (caller_storage || cls != ios_runtime.names['DCAppAttestService']) {
		panic('iOS: DCAppAttestService requires sharedService')
	}
}

fn app_attest_storage(object u64) {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['DCAppAttestService'] || header.caller_storage
		|| header.native_size != 16 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: App Attest requires live built-in storage')
	}
}

fn app_attest_shared() u64 {
	// Initialize outside the recursive cache lock: +initialize can call user code.
	cls := ios_runtime.names['DCAppAttestService']
	objc_initialize(cls)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.app_attest_retired { panic('iOS: App Attest cache is retired') }
	if ios_runtime.app_attest == 0 {
		object := u64(C.calloc(1, 16))
		if object == 0 { panic('iOS: cannot allocate App Attest') }
		// The built-in has no C++ constructor. Public allocation and caller
		// storage are rejected; only this factory owns the initial reference.
		objc_install_storage(cls, object, false)
		ios_runtime.app_attest = object
	}
	object := ios_runtime.app_attest
	app_attest_storage(object)
	return object
}

fn app_attest_retire(object u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if object == ios_runtime.app_attest && object != 0 {
		panic('iOS: destroying cached App Attest storage')
	}
}

fn app_attest_stop() {
	C.ios_objc_initialize_lock()
	ios_runtime.app_attest_retired = true
	object := ios_runtime.app_attest
	ios_runtime.app_attest = 0
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn app_attest_types(name string, meta bool, selector string) ?string {
	if name != 'DCAppAttestService' { return none }
	if meta {
		if selector == 'sharedService' { return '@16@0:8' }
		return none
	}
	if selector == 'isSupported' { return 'B16@0:8' }
	return none
}

fn app_attest_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !app_attest_family(cls) { return false }
	if app_attest_unsupported(selector) { app_attest_require_factory(cls) }
	if app_attest_types('DCAppAttestService', meta, selector) == none { return false }
	if meta && object != ios_runtime.names['DCAppAttestService'] {
		panic('iOS: custom App Attest subclasses are not implemented')
	}
	if !meta {
		C.ios_objc_initialize_lock()
		app_attest_storage(object)
		C.ios_objc_initialize_unlock()
	}
	match selector {
		'sharedService' { frame.x[0] = app_attest_shared() }
		'isSupported' { frame.x[0] = 0 }
		else { return false }
	}
	return true
}
