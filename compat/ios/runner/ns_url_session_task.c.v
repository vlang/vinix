// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

fn url_session_task_name(name string) bool {
	return name in ['NSURLSessionTask', 'NSURLSessionDownloadTask', 'NSURLSessionDataTask', 'NSURLSessionUploadTask']!
}

fn url_session_task_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSURLSessionTask' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic URL session task superclass chain')
}

fn url_session_task_require_class(cls u64) {
	if url_session_task_family(cls) && !url_session_task_name(ctext(u64(objc_class_name(cls)))) {
		panic('iOS: custom URL session task subclass construction is not implemented')
	}
}

fn url_session_task_metadata() {
	// Measured public property backing fields in the otherwise opaque 720-byte
	// CFNetwork record. Base tasks remain inert; session-created tasks start
	// suspended and own request snapshots. Transfers require a backend.
	mut cls := ios_runtime.classes[ios_runtime.names['NSURLSessionTask']] or { panic('iOS: missing task class') }
	for i, name in ['_priorityAPIStorage', '_taskIdentifier', '_taskDescription', '_originalRequest',
		'_currentRequest', '_response', '_countOfBytesClientExpectsToSend', '_countOfBytesClientExpectsToReceive',
		'_countOfBytesReceived', '_countOfBytesSent', '_countOfBytesExpectedToSend', '_countOfBytesExpectedToReceive', '_state', '_error']! {
		types := ['f', 'Q', '@"NSString"', '@"NSURLRequest"', '@"NSURLRequest"', '@"NSURLResponse"',
			'q', 'q', 'q', 'q', 'q', 'q', 'q', '@"NSError"']![i]
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: types.clone(),
			offset: [i64(116), 120, 128, 144, 152, 160, 168, 176, 184, 208, 216, 224, 232, 240]![i],
			size: if i == 0 { u64(4) } else { u64(8) }}
	}
}

fn url_session_task_types(name string, meta bool, selector string) ?string {
	if !url_session_task_name(name) { return none }
	if meta { if selector == 'new' { return '@16@0:8' }; return none }
	return match selector {
		'init', 'copy', 'taskDescription', 'originalRequest', 'currentRequest', 'response', 'error' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'setTaskDescription:' { 'v24@0:8@16' }
		'taskIdentifier' { 'Q16@0:8' }
		'state', 'countOfBytesClientExpectsToSend', 'countOfBytesClientExpectsToReceive',
		'countOfBytesSent', 'countOfBytesReceived', 'countOfBytesExpectedToSend', 'countOfBytesExpectedToReceive' { 'q16@0:8' }
		'setCountOfBytesClientExpectsToSend:', 'setCountOfBytesClientExpectsToReceive:' { 'v24@0:8q16' }
		'priority' { 'f16@0:8' }
		'setPriority:' { 'v20@0:8f16' }
		else { return none }
	}
}

fn url_session_task_unsupported(selector string) bool {
	return selector in ['resume', 'suspend', 'cancel', 'cancelByProducingResumeData:', 'delegate', 'setDelegate:', 'progress',
		'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'setCountOfBytesSent:', 'setCountOfBytesReceived:', 'setCountOfBytesExpectedToSend:', 'setCountOfBytesExpectedToReceive:']!
}

fn url_session_task_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.url_session_task_owned || header.native_size < 720 || header.destroyed || header.destroying {
		panic('iOS: URL session task requires live base task storage')
	}
	return header
}

fn url_session_task_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !url_session_task_family(if meta { object } else { read64(object) }) { return false }
	if url_session_task_unsupported(selector) {
		name := ctext(u64(objc_class_name(if meta { object } else { read64(object) })))
		scope := if meta { '+' } else { '-' }
		panic('iOS: URL session task transfers, cancellation, delegates, progress and coding are not implemented: ${scope}[${name} ${selector}]')
	}
	if url_session_task_types('NSURLSessionTask', meta, selector) == none { return false }
	if meta { frame.x[0] = objc_new(object); return true }
	// Copy can invoke application code. Keep it, and retirement, outside the lock.
	mut copied := u64(0)
	if selector == 'setTaskDescription:' && frame.x[2] != 0 {
		if !objc_is_kind(frame.x[2], ios_runtime.names['NSString']) { panic('iOS: task description must be a string') }
		copied = objc_copy_value(frame.x[2], false)
		if copied == 0 || !objc_is_kind(copied, ios_runtime.names['NSString']) { panic('iOS: task description copy must be a string') }
	}
	C.ios_objc_initialize_lock()
	mut header := url_session_task_state(object)
	mut retired := u64(0)
	match selector {
		'init' {}
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'originalRequest' { frame.x[0] = objc_retain_autorelease(header.fields[1]) }
		'currentRequest' { frame.x[0] = objc_retain_autorelease(header.fields[2]) }
		'taskIdentifier' { frame.x[0] = read64(object + 120) }
		'state' { frame.x[0] = read64(object + 232) }
		'taskDescription' { frame.x[0] = objc_retain_autorelease(header.fields[0]) }
		'setTaskDescription:' {
			retired = header.fields[0]; header.fields[0] = copied
			unsafe { *(&u64(object + 128)) = copied }
		}
		'countOfBytesClientExpectsToSend' { frame.x[0] = read64(object + 168) }
		'countOfBytesClientExpectsToReceive' { frame.x[0] = read64(object + 176) }
		'setCountOfBytesClientExpectsToSend:' { unsafe { *(&u64(object + 168)) = frame.x[2] } }
		'setCountOfBytesClientExpectsToReceive:' { unsafe { *(&u64(object + 176)) = frame.x[2] } }
		'priority' { frame.q[0] = u64(bits.f32_bits(unsafe { *(&f32(object + 116)) })); frame.q[1] = 0 }
		'setPriority:' {
			value := bits.f32_from_bits(u32(frame.q[0]))
			// Native tasks accept NaNs, but ignore finite outliers and infinities.
			if u32(frame.q[0]) & 0x7fffffff > 0x7f800000 || (value >= 0 && value <= 1) {
				unsafe { *(&f32(object + 116)) = value }
			}
		}
		else { frame.x[0] = 0 }
	}
	C.ios_objc_initialize_unlock()
	objc_release(retired)
	return true
}

fn url_session_task_dispose(object u64, header &ObjHeader) {
	if !header.url_session_task_owned { return }
	// Generic fields own the description, both requests and session, including
	// after an isa replacement. No task is kept alive by its session before resume.
	unsafe { *(&u64(object + 128)) = 0; *(&u64(object + 144)) = 0; *(&u64(object + 152)) = 0 }
}
