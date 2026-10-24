// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn objc_install_storage(cls u64, object u64, caller_storage bool) {
	ns_keyed_archiver_require_class(cls)
	ns_operation_require_class(cls)
	ns_invocation_require_class(cls)
	ns_date_formatter_require_class(cls)
	ns_number_formatter_require_class(cls)
	un_trigger_require_class(cls)
	un_request_require_class(cls)
	un_center_require_class(cls)
	un_content_require_class(cls)
	un_sound_require_class(cls)
	un_attachment_require_class(cls)
	ns_cache_require_class(cls)
	ns_map_table_require_class(cls)
	telephony_require_class(cls)
	ns_credential_require_class(cls)
	ns_calendar_require_class(cls)
	ns_predicate_require_class(cls)
	ns_index_set_require_class(cls)
	ns_character_set_require_class(cls)
	ns_scanner_require_class(cls)
	ns_user_activity_require_class(cls)
	ns_notification_queue_require_class(cls)
	ns_url_query_item_require_class(cls)
	ns_lock_require_class(cls)
	ns_recursive_lock_require_class(cls)
	dispatch_objc_allocation_checked(cls) or { panic(err) }
	url_session_require_class(cls)
	url_session_configuration_require_class(cls)
	sort_descriptor_require_class(cls)
	regular_expression_require_class(cls)
	mutable_string_require_class(cls)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { panic('iOS: construction of an unknown class') }
	if info.meta || (info.dynamic && !info.registered) { panic('iOS: construction requires a registered instance class') }
	if object in ios_runtime.objects { panic('iOS: object storage is already constructed') }
	mut header := unsafe { &ObjHeader(C.calloc(1, sizeof(ObjHeader))) }
	if header == unsafe { nil } { panic('iOS: cannot allocate object metadata') }
	header.refs = 1
	header.cls = cls
	header.allocation_cls = cls
	header.caller_storage = caller_storage
	header.native_size = info.size
	header.font_size = 17
	header.content_scale = 1
	header.items = []u64{}
	header.keys = []u64{}
	header.gestures = []u64{}
	header.data = []u8{}
	header.items.flags |= .noslices
	header.keys.flags |= .noslices
	header.gestures.flags |= .noslices
	ios_runtime.objects[object] = header
	unsafe { *(&u64(object)) = cls }
	if objc_is_kind(object, ios_runtime.names['NSOperationQueue']) { header.number = -1 }
	if objc_is_kind(object, ios_runtime.names['NSLayoutConstraint']) { layout_constraint_initialize(object) }
	header.condition_owned = objc_is_kind(object, ios_runtime.names['NSCondition'])
	header.foundation_lock_owned = ns_lock_family(cls)
	header.recursive_lock_owned = ns_recursive_lock_family(cls)
	ns_thread_install(object, mut header)
	ns_operation_install(cls, mut header)
	ns_invocation_install(cls, mut header)
	ns_date_formatter_install(cls, mut header)
	ns_number_formatter_install(cls, mut header)
	ns_calendar_install(cls, mut header)
	ns_predicate_install(cls, mut header)
	ns_index_set_install(cls, mut header)
	ns_character_set_install(cls, mut header)
	ns_scanner_install(cls, mut header)
	ns_user_activity_install(cls, mut header)
	ns_cache_install(cls, mut header)
	ns_map_table_install(cls, mut header)
	header.telephony_owned = cls == ios_runtime.names['CTTelephonyNetworkInfo']
	header.credential_owned = cls == ios_runtime.names['NSURLCredential']
	ns_notification_queue_install(cls, mut header)
	header.un_trigger_owned = cls in [ios_runtime.names['UNNotificationTrigger'], ios_runtime.names['UNCalendarNotificationTrigger']]!
	header.un_request_owned = cls == ios_runtime.names['UNNotificationRequest']
	header.un_sound_owned = cls == ios_runtime.names['UNNotificationSound']
	header.un_attachment_owned = cls == ios_runtime.names['UNNotificationAttachment']
	header.un_center_owned = cls == ios_runtime.names['UNUserNotificationCenter']
	if cls in [ios_runtime.names['UNNotificationContent'], ios_runtime.names['UNMutableNotificationContent']]! {
		header.un_content = unsafe { &UNContent(C.calloc(1, sizeof(UNContent))) }
		if header.un_content == unsafe { nil } { panic('iOS: cannot allocate notification content state') }
		header.un_content.interruption = 1
	}
	header.url_query_item_owned = cls == ios_runtime.names['NSURLQueryItem']
	header.auth_owned = objc_is_kind(object, ios_runtime.names['ASWebAuthenticationSession'])
	header.image_view_owned = objc_is_kind(object, ios_runtime.names['UIImageView'])
	header.uuid_owned = objc_is_kind(object, ios_runtime.names['NSUUID'])
	header.date_owned = ns_date_family(cls)
	header.input_stream_owned = ns_input_stream_family(cls)
	header.connection_owned = connection_family(cls)
	header.url_session_owned = url_session_family(cls)
	header.url_session_configuration_owned = url_session_configuration_family(cls)
	if header.url_session_configuration_owned { url_session_configuration_initialize(object) }
	header.sort_descriptor_owned = sort_descriptor_family(cls)
	header.regular_expression_owned = regular_expression_family(cls)
	header.regex_result_owned = regex_result_family(cls)
	header.mutable_string_owned = mutable_string_family(cls)
	if header.input_stream_owned { header.input_stream_fd = -1 }
	header.pool_owned = objc_is_kind(object, ios_runtime.names['NSAutoreleasePool'])
	header.cookie_owned = objc_is_kind(object, ios_runtime.names['NSHTTPCookie'])
	header.webview_owned = objc_is_kind(object, ios_runtime.names['WKWebView'])
	header.request_owned = objc_is_kind(object, ios_runtime.names['NSURLRequest'])
	header.response_owned = objc_is_kind(object, ios_runtime.names['NSURLResponse'])
	header.set_owned = objc_is_kind(object, ios_runtime.names['NSSet'])
	header.set_mutable = objc_is_kind(object, ios_runtime.names['NSMutableSet'])
	header.alert_owned = objc_is_kind(object, ios_runtime.names['UIAlertController']) || objc_is_kind(object, ios_runtime.names['UIAlertAction'])
	header.value_owned = objc_is_kind(object, ios_runtime.names['NSValue']) && !objc_is_kind(object, ios_runtime.names['NSNumber'])
	C.ios_ref_change(unsafe { &ios_runtime.live }, 1)
	C.ios_ref_change(unsafe { &info.instances }, 1)
}

fn objc_construct_instance(cls u64, bytes u64) u64 {
	if cls == 0 || bytes == 0 { return 0 }
	if bytes & 7 != 0 { panic('iOS: objc_constructInstance requires aligned storage') }
	// Native construction does not send +initialize or -init. Its caller owns
	// the zero-filled buffer, including after a C++ constructor returns nil.
	objc_install_storage(cls, bytes, true)
	return objc_construct(bytes, cls)
}

fn objc_destruct_instance(object u64) u64 {
	if object == 0 { return 0 }
	mut header := obj_header(object)
	if header.image_integer { panic('iOS: cannot destruct image integer storage') }
	if header.image_array { panic('iOS: cannot destruct image array storage') }
	if header.image_dictionary { panic('iOS: cannot destruct image dictionary storage') }
	objc_destroy_contents(object, mut header, true)
	// A dealloc callback can still be running in objc_release. Defer metadata
	// removal until it returns; the callback may itself free the object bytes.
	if !header.releasing && !header.destroying { objc_forget_storage(object, header) }
	return object
}

fn objc_destroy_contents(object u64, mut header ObjHeader, destructors bool) {
	if header.destroyed || header.destroying { return }
	connection_dispose(header)
	ns_pool_require_inactive(header)
	ns_lock_retire(mut header)
	ns_recursive_lock_retire(mut header)
	ns_operation_retire(mut header)
	ns_invocation_retire(mut header)
	ns_date_formatter_retire(mut header)
	ns_number_formatter_retire(mut header)
	ns_calendar_retire(mut header)
	ns_predicate_retire(mut header)
	ns_url_query_item_retire(mut header)
	un_attachment_retire(header)
	ns_cache_retire(header)
	ns_map_table_retire(header)
	telephony_retire(header)
	ns_credential_retire(mut header)
	ns_user_activity_retire(mut header)
	ns_notification_queue_retire(mut header)
	un_center_retire(object, header)
	header.destroying = true
	C.ios_objc_initialize_lock()
	swift_unknown_weak_retire_locked(object)
	C.ios_objc_initialize_unlock()
	swift_data_bridge_dispose(mut header)
	if destructors {
		mut cls := header.cls
		for _ in 0 .. 128 {
			if cls == 0 { break }
			info := ios_runtime.classes[cls] or { panic('iOS: unknown object destructor class') }
			if imp := info.methods['.cxx_destruct'] { unsafe { ObjVoid(voidptr(imp))(object, c'.cxx_destruct') } }
			cls = info.parent
		}
		if cls != 0 { panic('iOS: cyclic destructor superclass chain') }
	}
	objc_remove_associated(object)
	C.ios_objc_initialize_lock()
	for location, referent in ios_runtime.weak {
		if referent == object { unsafe { *(&u64(location)) = 0 }; ios_runtime.weak[location] = 0 }
	}
	C.ios_objc_initialize_unlock()
	$if ios_gles ? { gles_dispose(object) }
	$if ios_text ? { text_dispose(object) }
	accessibility_dispose(object)
	cv_pixel_dispose(mut header)
	cv_metal_dispose(mut header)
	cm_format_dispose(mut header)
	cm_block_dispose(mut header)
	cm_sample_dispose(mut header)
	vt_dispose(mut header)
	reachability_dispose(mut header)
	nw_dispose(mut header)
	bitmap_dispose(object)
	cg_provider_dispose(object)
	layout_dispose(object, mut header)
	ns_error_dispose(object)
	ns_condition_dispose(object, mut header)
	ns_lock_dispose(object, mut header)
	ns_recursive_lock_dispose(object, mut header)
	ns_thread_dispose(mut header)
	ns_operation_dispose(object, mut header)
	ns_invocation_dispose(object, mut header)
	ns_date_formatter_dispose(mut header)
	ns_number_formatter_dispose(mut header)
	ns_calendar_dispose(mut header)
	ns_predicate_dispose(mut header)
	ns_index_set_dispose(mut header)
	ns_character_set_dispose(mut header)
	ns_scanner_dispose(mut header)
	ns_user_activity_dispose(object, mut header)
	ns_notification_queue_dispose(object, mut header)
	un_trigger_dispose(object, mut header)
	un_request_dispose(object, mut header)
	un_sound_dispose(object, mut header)
	un_attachment_dispose(object, mut header)
	ns_cache_dispose(object, mut header)
	ns_map_table_dispose(mut header)
	telephony_dispose(object, mut header)
	ns_credential_dispose(object, mut header)
	un_center_dispose(object, mut header)
	un_content_dispose(object, mut header)
	ns_url_query_item_dispose(object, mut header)
	web_auth_dispose(mut header)
	image_view_dispose(mut header)
	ns_input_stream_dispose(mut header)
	url_session_dispose(object, header)
	url_session_configuration_dispose(object, header)
	sort_descriptor_dispose(object, header)
	regular_expression_dispose(object, mut header)
	cookie_dispose(object, mut header)
	webkit_dispose(mut header)
	webview_dispose(object, mut header)
	request_dispose(mut header)
	response_dispose(mut header)
	alert_dispose(mut header)
	objc_destroy_weak(unsafe { &header.presenter })
	for field in header.fields { objc_release(field) }
	for i in 0 .. header.child_count {
		mut child := obj_header(header.children[i])
		child.parent_view = 0
		objc_release(header.children[i])
	}
	if !header.image_array && !header.image_dictionary {
		if !header.cf_raw_values { for item in header.items { objc_release(item) } }
		if !header.cf_raw_keys { for key in header.keys { objc_release(key) } }
	}
	for gesture in header.gestures { objc_release(gesture) }
	unsafe { header.items.free(); header.keys.free(); header.gestures.free(); header.data.free() }
	if header.file != unsafe { nil } { C.fclose(header.file) }
	if header.free_data { darwin_free(unsafe { voidptr(header.external_data) }) }
	objc_destroy_weak(unsafe { &header.target })
	if ios_runtime.first_responder == object { ios_runtime.first_responder = 0 }
	C.free(header.text)
	header.destroyed = true
	header.destroying = false
}

fn objc_forget_storage(object u64, header &ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[header.cls] or { panic('iOS: unknown destroyed object class') }
	ios_runtime.objects.delete(object)
	C.ios_ref_change(unsafe { &info.instances }, -1)
	C.ios_ref_change(unsafe { &ios_runtime.live }, -1)
	C.free(header)
}

fn objc_failed_construction(object u64) {
	mut header := obj_header(object)
	caller_storage := header.caller_storage
	// The constructor walker already destroyed only the completed bases.
	objc_destroy_contents(object, mut header, false)
	objc_forget_storage(object, header)
	if !caller_storage { C.free(unsafe { voidptr(object) }) }
}
