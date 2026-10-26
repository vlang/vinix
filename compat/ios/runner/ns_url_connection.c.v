// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The measured public record is16 bytes. Private Foundation state stays opaque.
// Fields own the original request, delegate and transport snapshot on start.
fn connection_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSURLConnection' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic connection superclass chain')
}
fn connection_main() {
	if u64(C.pthread_self()) != ios_runtime.main_thread { panic('iOS: connection lifecycle requires the main thread') }
}
fn connection_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.connection_owned || !header.connection_initialized { panic('iOS: connection is not initialized') }
	return header
}
fn connection_request(request u64) &URLRequestState {
	if request == 0 || !objc_is_kind(request, ios_runtime.names['NSURLRequest']) { panic('iOS: connection requires NSURLRequest') }
	state := obj_header(request).request
	if state == unsafe { nil } { panic('iOS: connection request is not initialized') }
	if state.refs[0] == 0 { panic('iOS: connection requires a request URL') }
	return state
}
fn connection_can_handle(request u64) bool {
	if request == 0 { return false }
	state := connection_request(request)
	return obj_header(state.refs[0]).number != 1
}
fn connection_file_request(request u64) u64 {
	state := connection_request(request)
	if obj_header(state.refs[0]).number == 1 { panic('iOS: HTTP and HTTPS connection loading is not implemented') }
	return state.refs[0]
}
fn connection_error(url u64, domain_text string, code i64) u64 {
	info := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	mut header := obj_header(info)
	for index, name in ['NSErrorFailingURLKey', 'NSErrorFailingURLStringKey']! {
		value := if index == 0 { url } else { ui_file_url_string(url) }
		key := owned_string(name); cf_dictionary_insert(mut header, key, value); objc_release(key)
	}
	domain := owned_string(domain_text); result := ns_error_create(domain, code, info)
	objc_release(domain); objc_release(info)
	return objc_autorelease(result)
}
fn connection_posix_error(url u64, native i32) u64 {
	code := i64(darwin_native_error(native))
	return if code == 2 { connection_error(url, 'NSURLErrorDomain', -1100) }
		else if code == 13 { connection_error(url, 'NSURLErrorDomain', -1102) }
		else { connection_error(url, 'NSPOSIXErrorDomain', code) }
}
fn connection_file_load(request u64, response &u64, error_output &u64) u64 {
	url := connection_file_request(request)
	return url_file_load(url, ios_runtime.names['NSData'], response, error_output)
}

// Shared by NSData's file factory and the connection transport. The caller
// validates the URL profile before opening; all results own their byte storage.
fn url_file_load(url u64, data_class u64, response &u64, error_output &u64) u64 {
	if response != unsafe { nil } { unsafe { *response = 0 } }
	path := ns_file_manager_path(obj_header(url).fields[0])
	mut buffer := [1024]u8{}
	unsafe { C.memcpy(&buffer[0], path.str, usize(path.len)) }
	fd := C.open(unsafe { &char(&buffer[0]) }, C.O_RDONLY)
	if fd < 0 { native := unsafe { *C.ios_errno_address() }; if error_output != unsafe { nil } { unsafe { *error_output = connection_posix_error(url, native) } }; return 0 }
	defer { C.close(fd) }
	mut fields := [20]u64{}
	if C.ios_stat_info(unsafe { nil }, i32(fd), 2, unsafe { &fields[0] }) != 0 { native := unsafe { *C.ios_errno_address() }; if error_output != unsafe { nil } { unsafe { *error_output = connection_posix_error(url, native) } }; return 0 }
	if fields[1] & 0xf000 != 0x8000 { if error_output != unsafe { nil } { unsafe { *error_output = connection_posix_error(url, if fields[1] & 0xf000 == 0x4000 { C.EISDIR } else { C.EINVAL }) } }; return 0 }
	if fields[15] > 16777216 { if error_output != unsafe { nil } { unsafe { *error_output = connection_error(url, 'NSURLErrorDomain', -1103) } }; return 0 }
	data := objc_allocate(data_class)
	mut header := obj_header(data)
	header.data.flags |= .noslices
	mut chunk := [8192]u8{}
	mut plain := true
	for {
		count := C.read(fd, unsafe { &chunk[0] }, chunk.len)
		if count < 0 {
			native := unsafe { *C.ios_errno_address() }; if native == C.EINTR { continue }
			objc_release(data); if error_output != unsafe { nil } { unsafe { *error_output = connection_posix_error(url, native) } }; return 0
		}
		if count == 0 { break }
		if count > 16777216 - header.data.len { objc_release(data); if error_output != unsafe { nil } { unsafe { *error_output = connection_error(url, 'NSURLErrorDomain', -1103) } }; return 0 }
		for i in 0 .. int(count) { byte := chunk[i]; if (byte < 32 && byte !in [u8(9), 10, 13]!) || byte >= 127 { plain = false } }
		unsafe { header.data.push_many(&chunk[0], int(count)) }
	}
	if response != unsafe { nil } {
		object := objc_allocate(ios_runtime.names['NSURLResponse'])
		mime := owned_string(if plain { 'text/plain' } else { 'application/octet-stream' })
		response_init_base(object, url, mime, i64(header.data.len), 0); objc_release(mime)
		unsafe { *response = objc_autorelease(object) }
	}
	return objc_autorelease(data)
}
fn connection_initialize(object u64, request u64, delegate u64, immediate bool) {
	connection_main(); connection_request(request)
	mut header := obj_header(object)
	if !header.connection_owned { panic('iOS: connection initialization requires owned metadata') }
	if header.connection_initialized { panic('iOS: connection reinitialization is not implemented') }
	if delegate != 0 && delegate !in ios_runtime.objects { panic('iOS: connection delegate requires an owned object') }
	header.fields[0] = objc_retain(request)
	header.fields[1] = objc_retain(delegate)
	header.connection_initialized = true
	header.connection_scheduled = true
	if immediate { connection_start(object) }
}
fn connection_enqueue(object u64) {
	mut header := connection_state(object)
	if header.connection_queued || !header.connection_scheduled { return }
	header.connection_queued = true
	darwin_dispatch_async_f(darwin_dispatch_get_main_queue(), unsafe { voidptr(object) }, connection_run)
}
fn connection_start(object u64) {
	connection_main(); mut header := connection_state(object)
	if header.connection_started || header.connection_cancelled { return }
	connection_file_request(header.fields[0])
	snapshot := request_copy(header.fields[0], false)
	if obj_header(snapshot).request.mutable { obj_header(snapshot).request.mutable = false; objc_set_class(snapshot, ios_runtime.names['NSURLRequest']) }
	header.fields[2] = snapshot
	header.connection_started = true; header.connection_pending = true
	ios_runtime.connections << objc_retain(object)
	connection_enqueue(object)
}
fn connection_finish(object u64) {
	mut header := connection_state(object)
	if !header.connection_pending { return }
	header.connection_pending = false
	mut index := -1
	for i, value in ios_runtime.connections { if value == object { index = i; break } }
	if index < 0 { panic('iOS: connection registry lost its owning reference') }
	ios_runtime.connections.delete(index)
	delegate := header.fields[1]; header.fields[1] = 0
	objc_release(delegate); objc_release(object)
}
fn connection_cancel(object u64) {
	connection_main(); mut header := connection_state(object)
	header.connection_cancelled = true
	delegate := header.fields[1]; header.fields[1] = 0; objc_release(delegate)
	if header.connection_pending && !header.connection_queued && !header.connection_running { connection_finish(object) }
}
type ConnectionCallback = fn (u64, &char, u64, u64)
type ConnectionFinish = fn (u64, &char, u64)
fn connection_callback(delegate u64, selector &char, object u64, value u64) {
	if delegate == 0 { return }
	imp := native_method(read64(delegate), ctext(u64(selector)))
	if imp != 0 {
		if selector == c'connectionDidFinishLoading:' { unsafe { ConnectionFinish(voidptr(imp))(delegate, selector, object) } }
		else { unsafe { ConnectionCallback(voidptr(imp))(delegate, selector, object, value) } }
	}
}
fn connection_run(context voidptr) {
	object := u64(context); connection_main(); mut header := connection_state(object)
	header.connection_queued = false
	if header.connection_cancelled { connection_finish(object); return }
	if !header.connection_scheduled { return }
	header.connection_running = true; ios_runtime.connection_callbacks++
	delegate := objc_retain(header.fields[1])
	mut response := u64(0); mut error_object := u64(0)
	data := connection_file_load(header.fields[2], unsafe { &response }, unsafe { &error_object })
	if error_object != 0 { connection_callback(delegate, c'connection:didFailWithError:', object, error_object) }
	else {
		connection_callback(delegate, c'connection:didReceiveResponse:', object, response)
		if !header.connection_cancelled && data_length(data) != 0 { connection_callback(delegate, c'connection:didReceiveData:', object, data) }
		if !header.connection_cancelled { connection_callback(delegate, c'connectionDidFinishLoading:', object, 0) }
	}
	objc_release(delegate)
	ios_runtime.connection_callbacks--; header.connection_running = false
	connection_finish(object)
}
fn connection_require_shutdown() {
	if ios_runtime.connection_callbacks != 0 { panic('iOS: runtime shutdown inside a connection callback is not implemented') }
}
fn connection_stop() {
	// Dispatch has joined workers and discarded all queued main callbacks.
	for ios_runtime.connections.len != 0 {
		object := ios_runtime.connections.last(); mut header := connection_state(object)
		header.connection_cancelled = true; header.connection_queued = false
		connection_finish(object)
	}
	unsafe { ios_runtime.connections.free() }
}
fn connection_dispose(header &ObjHeader) {
	if header.connection_owned && header.connection_pending { panic('iOS: cannot destruct pending connection storage') }
}
fn connection_types(name string, meta bool, selector string) ?string {
	if name != 'NSURLConnection' { return none }
	if meta { return match selector {
		'canHandleRequest:' { 'B24@0:8@16' }
		'sendSynchronousRequest:returningResponse:error:' { '@40@0:8@16^@24^@32' }
		'connectionWithRequest:delegate:' { '@32@0:8@16@24' }
		else { return none }
	} }
	return match selector {
		'initWithRequest:delegate:' { '@32@0:8@16@24' }
		'initWithRequest:delegate:startImmediately:' { '@36@0:8@16@24B32' }
		'originalRequest', 'currentRequest' { '@16@0:8' }
		'start', 'cancel' { 'v16@0:8' }
		'defersCallbacks' { 'B16@0:8' }
		'setDefersCallbacks:' { 'v20@0:8B16' }
		'scheduleInRunLoop:forMode:', 'unscheduleFromRunLoop:forMode:' { 'v32@0:8@16@24' }
		else { return none }
	}
}
fn connection_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return connection_family(if meta { object } else { read64(object) }) && connection_types('NSURLConnection', meta, selector) != none
}
fn connection_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !connection_family(if meta { object } else { read64(object) }) { return false }
	if selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'setDelegateQueue:', 'sendAsynchronousRequest:queue:completionHandler:', 'connectionProperties', 'initWithCoder:', 'encodeWithCoder:']! { panic('iOS: connection default construction, copying, operation queues, coding and private properties are not implemented') }
	if connection_types('NSURLConnection', meta, selector) == none { return false }
	if meta {
		if selector == 'canHandleRequest:' { frame.x[0] = u64(connection_can_handle(frame.x[2])); return true }
		if selector == 'sendSynchronousRequest:returningResponse:error:' { frame.x[0] = connection_file_load(frame.x[2], unsafe { &u64(frame.x[3]) }, unsafe { &u64(frame.x[4]) }); return true }
		result := objc_allocate(object); connection_initialize(result, frame.x[2], frame.x[3], true); frame.x[0] = objc_autorelease(result); return true
	}
	if selector.starts_with('initWithRequest:') { connection_initialize(object, frame.x[2], frame.x[3], selector == 'initWithRequest:delegate:' || u8(frame.x[4]) != 0); return true }
	connection_main(); mut header := connection_state(object)
	match selector {
		'start' { connection_start(object) }
		'cancel' { connection_cancel(object) }
		'originalRequest' { frame.x[0] = header.fields[0] }
		'currentRequest' { frame.x[0] = if header.fields[2] == 0 { header.fields[0] } else { header.fields[2] } }
		'defersCallbacks' { frame.x[0] = 0 }
		'setDefersCallbacks:' {} // This installed Foundation setter is ignored.
		else {
			if header.connection_running { panic('iOS: connection scheduling inside a callback is not implemented') }
			if frame.x[2] == 0 || frame.x[2] != ios_runtime.run_loop || !objc_is_kind(frame.x[3], ios_runtime.names['NSString']) || string_text(frame.x[3]) != 'kCFRunLoopDefaultMode' { panic('iOS: connection scheduling requires the main default run loop') }
			header.connection_scheduled = selector == 'scheduleInRunLoop:forMode:'
			if header.connection_scheduled && header.connection_pending { connection_enqueue(object) }
		}
	}
	return true
}
