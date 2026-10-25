// SPDX-License-Identifier: GPL-2.0-or-later
module main

// No capture backend is connected. Match the native unconnected output's
// delegate ownership and discovery results without claiming to deliver audio.
fn capture_audio_symbol(symbol string) ?u64 {
	for name in ['AVCaptureOutput', 'AVCaptureAudioDataOutput']! {
		if symbol == '_OBJC_CLASS_$_' + name { return ios_runtime.names[name] }
		if symbol == '_OBJC_METACLASS_$_' + name { return read64(ios_runtime.names[name]) }
	}
	return none
}

fn capture_audio_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'AVCaptureOutput' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic capture output superclass chain')
}

fn capture_audio_unsupported(selector string) bool {
	return (selector.starts_with('set') && selector.ends_with(':') && selector != 'setSampleBufferDelegate:queue:')
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder',
		'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:',
		'removeObserver:forKeyPath:context:', 'audioSettings', 'spatialAudioChannelLayoutTag']!
}

fn capture_audio_install(cls u64, caller_storage bool) {
	if capture_audio_family(cls) && (caller_storage || cls != ios_runtime.names['AVCaptureAudioDataOutput']) {
		panic('iOS: capture audio output requires built-in allocation')
	}
}

fn capture_audio_storage(object u64) {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['AVCaptureAudioDataOutput'] || header.caller_storage
		|| header.native_size != 24 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: capture audio output requires live built-in storage')
	}
}

fn capture_audio_dispose(mut header ObjHeader) {
	objc_destroy_weak(unsafe { &header.capture_audio_delegate })
	queue := header.capture_audio_queue
	header.capture_audio_queue = 0
	if queue != 0 { darwin_dispatch_release(queue) }
}

fn capture_audio_types(name string, meta bool, selector string) ?string {
	if meta || name !in ['AVCaptureOutput', 'AVCaptureAudioDataOutput']! { return none }
	if selector == 'connections' { return '@16@0:8' }
	if selector == 'connectionWithMediaType:' { return '@24@0:8@16' }
	if name != 'AVCaptureAudioDataOutput' { return none }
	return match selector {
		'init', 'sampleBufferDelegate', 'sampleBufferCallbackQueue' { '@16@0:8' }
		'setSampleBufferDelegate:queue:' { 'v32@0:8@16@24' }
		'recommendedAudioSettingsForAssetWriterWithOutputFileType:' { '@24@0:8@16' }
		else { none }
	}
}

fn capture_audio_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !capture_audio_family(cls) { return false }
	if capture_audio_unsupported(selector) { panic('iOS: unsupported capture audio output method: ' + selector) }
	if capture_audio_types('AVCaptureAudioDataOutput', meta, selector) == none { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	capture_audio_storage(object)
	mut header := obj_header(object)
	match selector {
		'init' { frame.x[0] = object }
		'setSampleBufferDelegate:queue:' {
			delegate := frame.x[2]
			queue := if delegate == 0 { u64(0) } else { frame.x[3] }
			if delegate != 0 {
				if delegate !in ios_runtime.classes && delegate !in ios_runtime.constants {
					owner := ios_runtime.objects[delegate] or { panic('iOS: capture audio output requires an Objective-C delegate') }
					if owner.releasing || owner.destroying || owner.destroyed || C.ios_ref_change(unsafe { &owner.refs }, 0) <= 0 {
						panic('iOS: capture audio output requires a live delegate')
					}
				}
				if queue == 0 || !dispatch_objc_is_queue(queue) { panic('iOS: capture audio output delegate requires a dispatch queue') }
				darwin_dispatch_retain(queue)
			}
			old_queue := header.capture_audio_queue
			objc_store_weak(unsafe { &header.capture_audio_delegate }, delegate)
			header.capture_audio_queue = queue
			if old_queue != 0 { darwin_dispatch_release(old_queue) }
			frame.x[0] = 0
		}
		'sampleBufferDelegate' { frame.x[0] = objc_autorelease(objc_load_weak(unsafe { &header.capture_audio_delegate })) }
		'sampleBufferCallbackQueue' { frame.x[0] = objc_retain_autorelease(header.capture_audio_queue) }
		'connections' { frame.x[0] = ns_empty_array_symbol('___NSArray0__struct') or { panic('iOS: cannot create empty capture output connections') } }
		'connectionWithMediaType:' {
			if frame.x[2] != 0 { cf_string_compare_text(frame.x[2]) or { panic('iOS: capture audio output requires NSString media type or nil') } }
			frame.x[0] = 0
		}
		'recommendedAudioSettingsForAssetWriterWithOutputFileType:' {
			file_type := cf_string_compare_text(frame.x[2]) or { panic('iOS: capture audio output requires NSString file type') }
			if file_type !in ['com.apple.quicktime-movie', 'public.mpeg-4', 'public.3gpp',
				'com.apple.m4v-video', 'com.apple.m4a-audio', 'com.apple.coreaudio-format',
				'com.microsoft.waveform-audio', 'public.aiff-audio', 'public.aifc-audio',
				'org.3gpp.adaptive-multi-rate-audio']! { panic('iOS: capture audio output requires a supported file type') }
			frame.x[0] = 0
		}
		else { return false }
	}
	return true
}
