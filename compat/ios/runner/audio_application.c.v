// SPDX-License-Identifier: GPL-2.0-or-later
module main

// There is no microphone capture/authorization provider. Permission requests
// complete synchronously with denial; they never grant access or present UI.
const audio_application_denied = u64(0x64656e79) // 'deny', AVAudioApplicationRecordPermissionDenied.

fn audio_application_symbol(symbol string) ?u64 {
	return match symbol {
		'_OBJC_CLASS_$_AVAudioApplication' { ios_runtime.names['AVAudioApplication'] }
		'_OBJC_METACLASS_$_AVAudioApplication' { read64(ios_runtime.names['AVAudioApplication']) }
		else { none }
	}
}

fn audio_application_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'AVAudioApplication' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic audio application superclass chain')
}

fn audio_application_unsupported(selector string) bool {
	return selector in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:',
		'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'classForCoder']!
}

fn audio_application_require_factory(cls u64) {
	if audio_application_family(cls) { panic('iOS: AVAudioApplication requires sharedInstance') }
}

fn audio_application_install(cls u64, caller_storage bool) {
	if audio_application_family(cls) && (caller_storage || cls != ios_runtime.names['AVAudioApplication']) {
		panic('iOS: AVAudioApplication requires sharedInstance')
	}
}

fn audio_application_storage(object u64) {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['AVAudioApplication'] || header.caller_storage
		|| header.native_size != 24 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: audio application requires live built-in storage')
	}
}

fn audio_application_shared() u64 {
	// Initialize outside the recursive cache lock: +initialize can call user code.
	cls := ios_runtime.names['AVAudioApplication']
	objc_initialize(cls)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.audio_application_retired { panic('iOS: audio application cache is retired') }
	if ios_runtime.audio_application == 0 {
		object := u64(C.calloc(1, 24))
		if object == 0 { panic('iOS: cannot allocate audio application') }
		// The built-in has no C++ constructor. Public allocation and caller
		// storage are rejected; only this factory owns the initial reference.
		objc_install_storage(cls, object, false)
		ios_runtime.audio_application = object
	}
	object := ios_runtime.audio_application
	audio_application_storage(object)
	return object
}

fn audio_application_retire(object u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if object == ios_runtime.audio_application && object != 0 {
		panic('iOS: destroying cached audio application storage')
	}
}

fn audio_application_stop() {
	C.ios_objc_initialize_lock()
	ios_runtime.audio_application_retired = true
	object := ios_runtime.audio_application
	ios_runtime.audio_application = 0
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn audio_application_types(name string, meta bool, selector string) ?string {
	if name != 'AVAudioApplication' { return none }
	if selector == 'requestRecordPermissionWithCompletionHandler:' { return 'v24@0:8@?16' }
	if meta {
		if selector == 'sharedInstance' { return '@16@0:8' }
		return none
	}
	return match selector {
		'recordPermission' { 'q16@0:8' }
		'isInputMuted' { 'B16@0:8' }
		else { none }
	}
}

fn audio_application_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !audio_application_family(cls) { return false }
	if audio_application_unsupported(selector) { audio_application_require_factory(cls) }
	if audio_application_types('AVAudioApplication', meta, selector) == none { return false }
	if meta && object != ios_runtime.names['AVAudioApplication'] {
		panic('iOS: custom audio application subclasses are not implemented')
	}
	if !meta {
		C.ios_objc_initialize_lock()
		audio_application_storage(object)
		C.ios_objc_initialize_unlock()
	}
	match selector {
		'sharedInstance' { frame.x[0] = audio_application_shared() }
		'recordPermission' { frame.x[0] = audio_application_denied }
		'isInputMuted' { frame.x[0] = 0 }
		'requestRecordPermissionWithCompletionHandler:' {
			block := frame.x[2]
			if block == 0 { panic('iOS: audio record permission requires a completion block') }
			// No lock is held while invoking the caller; reentrant queries work.
			block_invoke_bool(block, false)
			frame.x[0] = 0
		}
		else { return false }
	}
	return true
}
