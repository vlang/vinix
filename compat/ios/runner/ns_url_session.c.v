// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The public base class is a 160-byte NSObject. Its Foundation/CFNetwork
// implementation state remains opaque. A base session has no configuration
// or delegate. Configured factories store settings and delegate/queue ownership;
// data tasks can resume using the bounded HTTP(S) profile; full session policy
// and invalidation callbacks remain unsupported.
// Owned references follow the allocation, including after an isa replacement.
fn url_session_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSURLSession' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic URL session superclass chain')
}

fn url_session_require_class(cls u64) {
	if url_session_family(cls) && cls != ios_runtime.names['NSURLSession'] {
		panic('iOS: custom URL session subclass construction is not implemented')
	}
}

fn url_session_metadata() {
	// These are measured metadata, not a native CFNetwork/C++ implementation.
	for index, name in ['_nwContextManager', '_nwContext', '_atsState_ivar', '_lock',
		'_invalid_ivar', '_rootPort', '_notifyPortRef', '_notifierObject',
		'_isSharedSession_ivar', '_delegateWrapper', '_delegateQueue_ivar',
		'_delegateDispatchQueue', '_delegate_ivar', '_sessionDescription_ivar',
		'_local_immutable_configuration_ivar', '_workQueue', '_uuid_ivar',
		'_tlsSessionCachePrefix', '_httpFallbackHosts', '_coalescing']! {
		types := ['@"__CFN_ConnectionContextManager"',
			'{shared_ptr<NSObject<OS_nw_context>>="__ptr_"@"NSObject<OS_nw_context>""__cntrl_"^{__shared_weak_count}}',
			'@"NSDictionary"', '{os_unfair_lock_s="_os_unfair_lock_opaque"I}', 'B', 'I',
			'^{IONotificationPort=}', 'I', 'B', '@"__NSCFURLSessionDelegateWrapper"',
			'@"NSOperationQueue"', '@"NSObject<OS_dispatch_queue>"', '@"<NSURLSessionDelegate>"',
			'@"NSString"', '@"NSURLSessionConfiguration"', '@"NSObject<OS_dispatch_queue>"',
			'@"NSUUID"', '@"NSString"', '@"NSMutableDictionary"', '@"NSMutableDictionary"']![index]
		offset := [u64(8), 16, 32, 40, 44, 48, 56, 64, 68, 72, 80, 88, 96, 104, 112, 120, 128, 136, 144, 152]![index]
		size := [u64(8), 16, 8, 4, 1, 4, 8, 4, 1, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]![index]
		mut cls := ios_runtime.classes[ios_runtime.names['NSURLSession']] or { panic('iOS: missing URL session class') }
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: types.clone(), offset: i64(offset), size: size}
	}
}

fn url_session_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.url_session_owned || header.native_size < 160 || header.destroyed || header.destroying {
		panic('iOS: URL session requires live base session storage')
	}
	return header
}

fn url_session_types(name string, meta bool, selector string) ?string {
	if name != 'NSURLSession' { return none }
	if meta {
		return match selector {
			'new' { '@16@0:8' }
			'sessionWithConfiguration:' { '@24@0:8@16' }
			'sessionWithConfiguration:delegate:delegateQueue:' { '@40@0:8@16@24@32' }
			else { return none }
		}
	}
	return match selector {
		'init', 'copy', 'delegate', 'delegateQueue', 'configuration', 'sessionDescription' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'dataTaskWithRequest:' { '@24@0:8@16' }
		'setSessionDescription:' { 'v24@0:8@16' }
		else { return none }
	}
}

fn url_session_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return url_session_family(if meta { object } else { read64(object) })
		&& url_session_types('NSURLSession', meta, selector) != none
}

fn url_session_unsupported(selector string) bool {
	return selector in ['sharedSession', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'finishTasksAndInvalidate', 'invalidateAndCancel', 'flushWithCompletionHandler:',
		'resetWithCompletionHandler:', 'getTasksWithCompletionHandler:', 'getAllTasksWithCompletionHandler:']!
		|| selector.starts_with('initWithConfiguration:')
		|| (selector.contains('TaskWith') && selector != 'dataTaskWithRequest:')
}

fn url_session_data_task(object u64, request u64) u64 {
	C.ios_objc_initialize_lock()
	header := url_session_state(object)
	configured := header.fields[2] != 0
	if !configured { panic('iOS: data task requires a configured URL session: -[NSURLSession dataTaskWithRequest:]') }
	if request == 0 || !objc_is_kind(request, ios_runtime.names['NSURLRequest']) {
		panic('iOS: data task requires an initialized URL request')
	}
	source := obj_header(request)
	if !source.request_owned || source.request == unsafe { nil } || source.destroyed || source.destroying {
		panic('iOS: data task requires an initialized URL request')
	}
	if read64(request) !in [ios_runtime.names['NSURLRequest'], ios_runtime.names['NSMutableURLRequest']]! {
		panic('iOS: data task custom request subclasses are not implemented')
	}
	mutable_request := source.request.mutable
	// Constructors may reenter application code. Pin both inputs until the
	// snapshots and task have acquired their own references.
	objc_retain(object)
	objc_retain(request)
	C.ios_objc_initialize_unlock()
	// Request copies can allocate and run constructors. Do not hold the session
	// lock across them. Each property owns an independent snapshot; an unresumed
	// task is owned only by its caller/autorelease pool, so no session/task cycle
	// is introduced. Resume acquires a separate owned transfer context.
	original := request_copy(request, mutable_request)
	current := request_copy(original, true)
	objc_release(request)
	task := objc_allocate(ios_runtime.names['NSURLSessionDataTask'])
	if task == 0 {
		objc_release(original)
		objc_release(current)
		objc_release(object)
		return 0
	}
	C.ios_objc_initialize_lock()
	mut owner := url_session_state(object)
	if owner.url_session_next_task == ~u64(0) { panic('iOS: URL session task identifiers exhausted') }
	owner.url_session_next_task++
	mut state := url_session_task_state(task)
	state.fields[1] = original
	state.fields[2] = current
	state.fields[3] = object
	unsafe {
		*(&f32(task + 116)) = 0.5
		*(&u64(task + 120)) = owner.url_session_next_task
		*(&u64(task + 144)) = original
		*(&u64(task + 152)) = current
		*(&i64(task + 168)) = -1
		*(&i64(task + 176)) = -1
		*(&u64(task + 232)) = 1 // NSURLSessionTaskStateSuspended.
	}
	C.ios_objc_initialize_unlock()
	return objc_autorelease(task)
}

fn url_session_configured(cls u64, configuration u64, delegate u64, queue u64) u64 {
	url_session_require_class(cls)
	if configuration == 0 || !objc_is_kind(configuration, ios_runtime.names['NSURLSessionConfiguration']) {
		panic('iOS: URL session requires a session configuration')
	}
	if queue != 0 && !objc_is_kind(queue, ios_runtime.names['NSOperationQueue']) {
		panic('iOS: URL session delegate queue must be NSOperationQueue')
	}
	// Copy/allocation may invoke application initializers or constructors. Keep
	// supplied references alive, and hold no state lock across those callbacks.
	owned_delegate := objc_retain(delegate)
	owned_queue := objc_retain(queue)
	copied := url_session_configuration_copy(configuration)
	if copied == 0 { objc_release(owned_queue); objc_release(owned_delegate); return 0 }
	object := objc_allocate(cls)
	if object == 0 {
		objc_release(copied); objc_release(owned_queue); objc_release(owned_delegate)
		return 0
	}
	C.ios_objc_initialize_lock()
	mut header := url_session_state(object)
	retired := [header.fields[1], header.fields[2], header.fields[3]]!
	header.fields[1] = owned_queue
	header.fields[2] = copied
	header.fields[3] = owned_delegate
	unsafe {
		*(&u64(object + 80)) = owned_queue
		*(&u64(object + 96)) = owned_delegate
		*(&u64(object + 112)) = copied
	}
	C.ios_objc_initialize_unlock()
	for value in retired { objc_release(value) }
	return objc_autorelease(object)
}

fn url_session_configuration_snapshot(object u64) u64 {
	C.ios_objc_initialize_lock()
	configuration := objc_retain(url_session_state(object).fields[2])
	C.ios_objc_initialize_unlock()
	if configuration == 0 { return 0 }
	defer { objc_release(configuration) }
	return objc_autorelease(url_session_configuration_copy(configuration))
}

fn url_session_delegate_queue(object u64) u64 {
	C.ios_objc_initialize_lock()
	header := url_session_state(object)
	if header.fields[1] != 0 {
		result := objc_retain_autorelease(header.fields[1])
		C.ios_objc_initialize_unlock()
		return result
	}
	C.ios_objc_initialize_unlock()
	// Construction can invoke a replaced initializer. Publish only one winner,
	// and release a concurrent losing candidate without holding the state lock.
	candidate := objc_new(ios_runtime.names['NSOperationQueue'])
	if candidate == 0 || !objc_is_kind(candidate, ios_runtime.names['NSOperationQueue']) {
		panic('iOS: URL session delegate queue construction requires NSOperationQueue')
	}
	obj_header(candidate).number = 1
	C.ios_objc_initialize_lock()
	mut current := url_session_state(object)
	mut retired := candidate
	if current.fields[1] == 0 {
		current.fields[1] = candidate
		unsafe { *(&u64(object + 80)) = candidate }
		retired = 0
	}
	result := objc_retain_autorelease(current.fields[1])
	C.ios_objc_initialize_unlock()
	objc_release(retired)
	return result
}

fn url_session_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !url_session_family(if meta { object } else { read64(object) }) { return false }
	if url_session_unsupported(selector) {
		kind := if meta { '+' } else { '-' }
		panic('iOS: URL session shared/configured sessions, mutable copying, lifecycle callbacks, tasks and coding are not implemented: '
			+ kind + '[NSURLSession ' + selector + ']')
	}
	if url_session_types('NSURLSession', meta, selector) == none { return false }
	if meta {
		frame.x[0] = if selector == 'new' { objc_new(object) }
			else { url_session_configured(object, frame.x[2],
				if selector == 'sessionWithConfiguration:' { u64(0) } else { frame.x[3] },
				if selector == 'sessionWithConfiguration:' { u64(0) } else { frame.x[4] }) }
		return true
	}
	if selector == 'dataTaskWithRequest:' { frame.x[0] = url_session_data_task(object, frame.x[2]); return true }
	if selector == 'delegateQueue' { frame.x[0] = url_session_delegate_queue(object); return true }
	if selector == 'configuration' { frame.x[0] = url_session_configuration_snapshot(object); return true }
	// Acquire a setter's copied argument before retiring the old value. A copy
	// method can run application code, so do not hold the state lock across it.
	mut copied := u64(0)
	if selector == 'setSessionDescription:' && frame.x[2] != 0 {
		if !objc_is_kind(frame.x[2], ios_runtime.names['NSString']) { panic('iOS: URL session description must be a string') }
		copied = objc_copy_value(frame.x[2], false)
		if copied == 0 || !objc_is_kind(copied, ios_runtime.names['NSString']) { panic('iOS: URL session description copy must be a string') }
	}
	C.ios_objc_initialize_lock()
	mut header := url_session_state(object)
	mut retired := u64(0)
	match selector {
		'init' {}
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'delegate' { frame.x[0] = objc_retain_autorelease(header.fields[3]) }
		'sessionDescription' { frame.x[0] = objc_retain_autorelease(header.fields[0]) }
		'setSessionDescription:' {
			retired = header.fields[0]
			header.fields[0] = copied
			unsafe { *(&u64(object + 104)) = copied }
		}
		else {}
	}
	C.ios_objc_initialize_unlock()
	objc_release(retired)
	return true
}

fn url_session_dispose(object u64, header &ObjHeader) {
	if !header.url_session_owned { return }
	// Generic fields own all references and release them after disposal. Clear
	// the public record as well when its bytes belong to a caller.
	unsafe {
		*(&u64(object + 80)) = 0; *(&u64(object + 96)) = 0
		*(&u64(object + 104)) = 0; *(&u64(object + 112)) = 0
	}
}
