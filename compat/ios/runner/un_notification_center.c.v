// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Inspection only: no permission, scheduling, delivery or daemon simulation.
// The cache owns one reference. The delegate lives in a registered weak ivar.
fn un_center_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['UNUserNotificationCenter']] or { panic('iOS: missing user notification center') }
	for i, pair in [['_delegate', '@"<UNUserNotificationCenterDelegate>"']!, ['_bundleIdentifier', '@"NSString"']!, ['_queue', '@"NSObject<OS_dispatch_queue>"']!, ['_privateDelegate', '@"<UNUserNotificationCenterDelegatePrivate>"']!]! {
		cls.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn un_center_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UNUserNotificationCenter' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic user notification center superclass chain')
}

fn un_center_require_class(cls u64) {
	if un_center_family(cls) && cls != ios_runtime.names['UNUserNotificationCenter'] {
		panic('iOS: custom user notification center construction is not implemented')
	}
}

// Caller holds the runtime lock. A changed isa cannot grant owned storage.
fn un_center_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.un_center_owned || header.destroying || header.destroyed || header.caller_storage
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 40
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['UNUserNotificationCenter'] {
		panic('iOS: user notification center requires live owned built-in storage')
	}
	if initialized && (!header.un_center_initialized || object != ios_runtime.user_notification_center) {
		panic('iOS: user notification center requires currentNotificationCenter')
	}
	if read64(object + 16) != 0 || read64(object + 24) != 0 || read64(object + 32) != 0 {
		panic('iOS: user notification center private storage is not implemented')
	}
	if header.un_center_initialized && (u64(object + 8) !in ios_runtime.weak
		|| ios_runtime.weak[object + 8] != read64(object + 8)) {
		panic('iOS: user notification center delegate storage was changed directly')
	}
	return header
}

fn un_center_current(cls u64) u64 {
	un_center_require_class(cls)
	if cls != ios_runtime.names['UNUserNotificationCenter'] { panic('iOS: user notification center requires its built-in class') }
	C.ios_objc_initialize_lock()
	if ios_runtime.user_notification_center_retired { panic('iOS: user notification center is stopped') }
	if ios_runtime.user_notification_center != 0 {
		object := ios_runtime.user_notification_center
		un_center_storage(object, true)
		C.ios_objc_initialize_unlock()
		return object
	}
	// Constructors may call application code. Release the lock first and reject
	// recursive/concurrent first construction instead of deadlocking or publishing
	// a partly constructed singleton. Cached access works from any thread.
	if ios_runtime.user_notification_center_initializing { panic('iOS: overlapping user notification center construction is not implemented') }
	ios_runtime.user_notification_center_initializing = true
	C.ios_objc_initialize_unlock()
	object := objc_allocate(cls)
	C.ios_objc_initialize_lock()
	defer { ios_runtime.user_notification_center_initializing = false; C.ios_objc_initialize_unlock() }
	if object == 0 { return 0 }
	mut header := un_center_storage(object, false)
	if ios_runtime.user_notification_center_retired || ios_runtime.user_notification_center != 0
		|| header.un_center_initialized || read64(object + 8) != 0 {
		panic('iOS: user notification center constructor changed destination storage')
	}
	objc_store_weak(unsafe { &u64(object + 8) }, 0)
	header.un_center_initialized = true
	ios_runtime.user_notification_center = object
	return object
}

fn un_center_retire(object u64, header &ObjHeader) {
	if !header.un_center_owned { return }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if object == ios_runtime.user_notification_center { panic('iOS: cannot destruct a cached user notification center') }
}

fn un_center_dispose(object u64, mut header ObjHeader) {
	if !header.un_center_owned { return }
	objc_destroy_weak(unsafe { &u64(object + 8) })
	unsafe { C.memset(voidptr(object + 8), 0, 32) }
	header.un_center_initialized = false
}

fn un_center_stop() {
	C.ios_objc_initialize_lock()
	if ios_runtime.user_notification_center_initializing { panic('iOS: user notification center construction is active during shutdown') }
	ios_runtime.user_notification_center_retired = true
	object := ios_runtime.user_notification_center
	ios_runtime.user_notification_center = 0
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn un_center_types(name string, meta bool, selector string) ?string {
	if name != 'UNUserNotificationCenter' { return none }
	if selector == 'supportsContentExtensions' { return 'B16@0:8' }
	if meta { return if selector == 'currentNotificationCenter' { '@16@0:8' } else { none } }
	return match selector { 'delegate' { '@16@0:8' } 'setDelegate:' { 'v24@0:8@16' } else { none } }
}

fn un_center_unsupported(selector string) bool {
	return selector in ['new', 'init', 'initWithBundleIdentifier:', 'initWithBundleIdentifier:queue:',
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'requestAuthorizationWithOptions:completionHandler:', 'requestRemoveAuthorizationWithCompletionHandler:',
		'setNotificationCategories:', 'getNotificationCategoriesWithCompletionHandler:', 'notificationCategories',
		'getNotificationSettingsWithCompletionHandler:', 'notificationSettings', 'notificationSettingsForTopics',
		'getNotificationSettingsForTopicsWithCompletionHandler:', 'addNotificationRequest:', 'addNotificationRequest:withCompletionHandler:',
		'getPendingNotificationRequestsWithCompletionHandler:', 'pendingNotificationRequests', 'removePendingNotificationRequestsWithIdentifiers:',
		'removeAllPendingNotificationRequests', 'removeSimilarNotificationRequests:', 'setNotificationRequests:', 'setNotificationRequests:completionHandler:',
		'getDeliveredNotificationsWithCompletionHandler:', 'deliveredNotifications', 'removeDeliveredNotificationsWithIdentifiers:', 'removeAllDeliveredNotifications',
		'setBadgeCount:withCompletionHandler:', 'setBadgeString:withCompletionHandler:', 'getBadgeNumberWithCompletionHandler:', 'badgeNumber',
		'setBadgeNumber:withCompletionHandler:', 'replaceContentForRequestWithIdentifier:replacementContent:completionHandler:', 'didChangeSettings:',
		'setNotificationTopics:withCompletionHandler:', 'getNotificationTopicsWithCompletionHandler:', 'notificationTopics',
		'setPrivateDelegate:', 'privateDelegate', 'setBundleIdentifier:', 'bundleIdentifier', 'setQueue:', 'queue',
		'didOpenApplicationForResponse:', 'didReceiveNotificationResponse:withCompletionHandler:', 'willPresentNotification:withCompletionHandler:',
		'setWantsNotificationResponsesDelivered', 'invalidateAndUnregister', 'clearedInfoForDataProviderMigration']!
}

fn un_center_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	mut cls := if meta { object } else { read64(object) }
	mut owned := un_center_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { if header.un_center_owned { owned = true; cls = header.allocation_cls } }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if un_center_unsupported(selector) { panic('iOS: user notification center service or construction option is not implemented') }
	info := ios_runtime.classes[cls] or { panic('iOS: missing user notification center class') }
	if un_center_types(info.name, meta, selector) == none { return false }
	if meta {
		un_center_require_class(cls)
		frame.x[0] = if selector == 'currentNotificationCenter' { un_center_current(cls) } else { u64(0) }
		return true
	}
	C.ios_objc_initialize_lock()
	un_center_storage(object, true)
	match selector {
		'delegate' { frame.x[0] = objc_autorelease(objc_load_weak(unsafe { &u64(object + 8) })) }
		'setDelegate:' { objc_store_weak(unsafe { &u64(object + 8) }, frame.x[2]); frame.x[0] = 0 }
		else { frame.x[0] = 0 }
	}
	C.ios_objc_initialize_unlock()
	return true
}
