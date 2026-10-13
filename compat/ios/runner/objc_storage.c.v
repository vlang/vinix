// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn objc_install_storage(cls u64, object u64, caller_storage bool) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { panic('iOS: construction of an unknown class') }
	if info.meta || (info.dynamic && !info.registered) { panic('iOS: construction requires a registered instance class') }
	if object in ios_runtime.objects { panic('iOS: object storage is already constructed') }
	mut header := unsafe { &ObjHeader(C.calloc(1, sizeof(ObjHeader))) }
	if header == unsafe { nil } { panic('iOS: cannot allocate object metadata') }
	header.refs = 1
	header.cls = cls
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
	ns_thread_install(object, mut header)
	header.auth_owned = objc_is_kind(object, ios_runtime.names['ASWebAuthenticationSession'])
	header.image_view_owned = objc_is_kind(object, ios_runtime.names['UIImageView'])
	header.uuid_owned = objc_is_kind(object, ios_runtime.names['NSUUID'])
	header.date_owned = ns_date_family(cls)
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
	if header.image_dictionary { panic('iOS: cannot destruct image dictionary storage') }
	objc_destroy_contents(object, mut header, true)
	// A dealloc callback can still be running in objc_release. Defer metadata
	// removal until it returns; the callback may itself free the object bytes.
	if !header.releasing && !header.destroying { objc_forget_storage(object, header) }
	return object
}

fn objc_destroy_contents(object u64, mut header ObjHeader, destructors bool) {
	if header.destroyed || header.destroying { return }
	ns_pool_require_inactive(header)
	header.destroying = true
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
	bitmap_dispose(object)
	cg_provider_dispose(object)
	layout_dispose(object, mut header)
	ns_error_dispose(object)
	ns_condition_dispose(object, mut header)
	ns_thread_dispose(mut header)
	web_auth_dispose(mut header)
	image_view_dispose(mut header)
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
	if !header.image_dictionary {
		if !header.cf_raw_values { for item in header.items { objc_release(item) } }
		if !header.cf_raw_keys { for key in header.keys { objc_release(key) } }
	}
	for gesture in header.gestures { objc_release(gesture) }
	unsafe { header.items.free(); header.keys.free(); header.gestures.free(); header.data.free() }
	if header.file != unsafe { nil } { C.fclose(header.file) }
	if header.free_data { C.free(unsafe { voidptr(header.external_data) }) }
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
