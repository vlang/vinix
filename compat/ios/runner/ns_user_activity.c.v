// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A local continuation payload. The measured 32-byte instance reserves its
// three opaque Foundation ivars; owned property references live in fields[0:2].
// Publishing activities, system restoration and Handoff are separate APIs.
struct FoundationUserActivity {
mut:
	initialized bool
	initializing bool
}

fn ns_user_activity_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSUserActivity']] or { panic('iOS: missing NSUserActivity') }
	for i, name in ['_internal', '_delegate', '_frameworkDelegate']! {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: '@'.clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn ns_user_activity_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSUserActivity' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic user activity superclass chain')
}

fn ns_user_activity_require_class(cls u64) {
	if ns_user_activity_family(cls) && cls != ios_runtime.names['NSUserActivity'] {
		panic('iOS: custom user activity subclass construction is not implemented')
	}
}

fn ns_user_activity_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSUserActivity'] { return }
	header.user_activity = unsafe { &FoundationUserActivity(C.calloc(1, sizeof(FoundationUserActivity))) }
	if header.user_activity == unsafe { nil } { panic('iOS: cannot allocate user activity state') }
}

// Caller holds the runtime lock. Allocation provenance survives an isa change.
fn ns_user_activity_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	state := header.user_activity
	if state == unsafe { nil } || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 32
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSUserActivity'] {
		panic('iOS: NSUserActivity requires live owned user activity storage')
	}
	if read64(object + 8) != 0 || read64(object + 16) != 0 || read64(object + 24) != 0 {
		panic('iOS: user activity opaque ivar access is not implemented')
	}
	if initialized && !state.initialized { panic('iOS: user activity requires initialization') }
	return header
}

fn ns_user_activity_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.user_activity != unsafe { nil } && header.user_activity.initializing {
		panic('iOS: destroying an active NSUserActivity')
	}
}

fn ns_user_activity_dispose(object u64, mut header ObjHeader) {
	state := header.user_activity
	header.user_activity = unsafe { nil }
	if state == unsafe { nil } { return }
	// Generic field destruction releases the type and URL exactly once.
	unsafe { C.memset(voidptr(object + 8), 0, 24) }
	C.free(state)
}

fn ns_user_activity_snapshot(input u64) string {
	if input == 0 { panic('iOS: user activity requires a nonnil activity type') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header := ios_runtime.objects[input] {
		if header.destroying || header.cls != header.allocation_cls || read64(input) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: user activity type requires a built-in initialized string')
		}
	}
	text := cf_string_compare_text(input) or { panic('iOS: user activity type requires a live UTF8 string') }
	if text.len == 0 { panic('iOS: user activity requires a nonempty explicit activity type') }
	if text.len > 65536 { panic('iOS: user activity type exceeds byte limit') }
	return text.clone()
}

fn ns_user_activity_failed_init(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_user_activity_storage(object, false)
	if C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: user activity constructor consumed receiver ownership') }
	if header.caller_storage { panic('iOS: failed user activity initializer cannot consume caller-owned storage') }
	header.user_activity.initializing = false
	C.ios_objc_initialize_unlock()
	objc_release(object)
	return 0
}

fn ns_user_activity_initialize(object u64, input u64) u64 {
	snapshot := ns_user_activity_snapshot(input)
	defer { unsafe { snapshot.free() } }
	C.ios_objc_initialize_lock()
	mut header := ns_user_activity_storage(object, false)
	if header.user_activity.initialized || header.user_activity.initializing
		|| header.fields[0] != 0 || header.fields[1] != 0 {
		panic('iOS: user activity is already initialized or its constructor changed storage')
	}
	header.user_activity.initializing = true
	objc_retain(object)
	C.ios_objc_initialize_unlock()
	defer { objc_release(object) }
	// No input borrow or runtime lock survives application string constructors.
	type_string := owned_string(snapshot)
	defer { objc_release(type_string) }
	if type_string == 0 { return ns_user_activity_failed_init(object) }
	C.ios_objc_initialize_lock()
	header = ns_user_activity_storage(object, false)
	type_header := obj_header(type_string)
	if type_header.destroying || type_header.destroyed
		|| C.ios_ref_change(unsafe { &type_header.refs }, 0) <= 0
		|| type_header.allocation_cls != ios_runtime.names['NSString']
		|| type_header.cls != type_header.allocation_cls || read64(type_string) != type_header.allocation_cls {
		panic('iOS: user activity string constructor changed result storage')
	}
	if !header.user_activity.initializing || header.user_activity.initialized
		|| header.fields[0] != 0 || header.fields[1] != 0
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 {
		panic('iOS: user activity string constructor changed destination storage')
	}
	header.fields[0] = objc_retain(type_string)
	header.user_activity.initialized = true
	header.user_activity.initializing = false
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_user_activity_set_url(object u64, value u64) {
	C.ios_objc_initialize_lock()
	mut header := ns_user_activity_storage(object, true)
	if value != 0 {
		url := ios_runtime.objects[value] or { panic('iOS: user activity webpage URL requires a live built-in URL') }
		if url.destroying || url.destroyed || C.ios_ref_change(unsafe { &url.refs }, 0) <= 0
			|| url.cls != url.allocation_cls || read64(value) != url.allocation_cls
			|| url.allocation_cls != ios_runtime.names['NSURL'] || url.fields[0] == 0 {
			panic('iOS: user activity webpage URL requires a live built-in URL')
		}
		// Foundation accepts only HTTP(S) webpage URLs. The URL constructor owns
		// parsing and its existing absolute-URL bounds; no load starts here.
		if url.number != 1 || url.fields[2] == 0 {
			panic('iOS: user activity webpage URL requires an HTTP or HTTPS scheme')
		}
		scheme := cf_string_compare_text(url.fields[2]) or { panic('iOS: user activity webpage URL requires a valid scheme') }
		if !request_ascii_equal(scheme, 'http') && !request_ascii_equal(scheme, 'https') {
			panic('iOS: user activity webpage URL requires an HTTP or HTTPS scheme')
		}
	}
	// The supported built-in NSURL is immutable and its copy is a retain.
	// Acquire before replacing, then release outside the lock: dealloc may reenter.
	owned := objc_retain(value)
	old := header.fields[1]
	header.fields[1] = owned
	C.ios_objc_initialize_unlock()
	objc_release(old)
}

fn ns_user_activity_types(name string, meta bool, selector string) ?string {
	if name != 'NSUserActivity' || meta { return none }
	return match selector {
		'initWithActivityType:' { '@24@0:8@16' }
		'activityType', 'webpageURL', 'referrerURL' { '@16@0:8' }
		'setWebpageURL:' { 'v24@0:8@16' }
		else { return none }
	}
}

fn ns_user_activity_unsupported(selector string) bool {
	return selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'isEqual:', 'hash', 'description',
		'debugDescription', 'setActivityType:', 'setReferrerURL:', 'title', 'setTitle:', 'userInfo', 'setUserInfo:',
		'addUserInfoEntriesFromDictionary:', 'delegate', 'setDelegate:', 'needsSave', 'setNeedsSave:',
		'requiredUserInfoKeys', 'setRequiredUserInfoKeys:', 'expirationDate', 'setExpirationDate:',
		'eligibleForHandoff', 'isEligibleForHandoff', 'setEligibleForHandoff:', 'eligibleForSearch',
		'isEligibleForSearch', 'setEligibleForSearch:', 'eligibleForPublicIndexing', 'isEligibleForPublicIndexing',
		'setEligibleForPublicIndexing:', 'eligibleForPrediction', 'isEligibleForPrediction', 'setEligibleForPrediction:',
		'keywords', 'setKeywords:', 'contentAttributeSet', 'setContentAttributeSet:', 'persistentIdentifier',
		'setPersistentIdentifier:', 'targetContentIdentifier', 'setTargetContentIdentifier:', 'suggestedInvocationPhrase',
		'setSuggestedInvocationPhrase:', 'supportsContinuationStreams', 'setSupportsContinuationStreams:',
		'becomeCurrent', 'resignCurrent', 'invalidate', 'getContinuationStreamsWithCompletionHandler:',
		'deleteSavedUserActivitiesWithPersistentIdentifiers:completionHandler:',
		'deleteAllSavedUserActivitiesWithCompletionHandler:']!
}

fn ns_user_activity_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_user_activity_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.user_activity != unsafe { nil } }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_user_activity_unsupported(selector) { panic('iOS: user activity option is not implemented') }
	if ns_user_activity_types('NSUserActivity', meta, selector) == none { return false }
	match selector {
		'initWithActivityType:' { frame.x[0] = ns_user_activity_initialize(object, frame.x[2]) }
		'setWebpageURL:' { ns_user_activity_set_url(object, frame.x[2]) }
		else {
			C.ios_objc_initialize_lock()
			header := ns_user_activity_storage(object, true)
			result := objc_retain(match selector {
				'activityType' { header.fields[0] }
				'webpageURL' { header.fields[1] }
				else { u64(0) }
			})
			C.ios_objc_initialize_unlock()
			frame.x[0] = objc_autorelease(result)
		}
	}
	return true
}
