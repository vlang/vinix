// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.object_dispose(voidptr) voidptr
type ConnSend = fn (u64, u64, u64, u64, u64) u64
type ConnReal = fn (u64, u64, f64) u64
struct ConnApi { native bool send u64 cls u64 strings u64 urls u64 requests u64 mutable_requests u64 probe u64 }
fn (api ConnApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ConnApi) msg(object u64, name &char, a u64, b u64, c u64) u64 { return unsafe { ConnSend(voidptr(api.send))(object, api.selector(name), a, b, c) } }
fn (api ConnApi) string(value string) u64 { return api.msg(api.strings, c'stringWithUTF8String:', u64(value.str), 0, 0) }
fn (api ConnApi) request(path string, mutable bool) u64 {
	url := api.msg(api.urls, c'fileURLWithPath:', api.string(path), 0, 0)
	return api.msg(if mutable { api.mutable_requests } else { api.requests }, c'requestWithURL:', url, 0, 0)
}
fn (api ConnApi) pool() u64 {
	$if macos { if api.native { return api.msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api ConnApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api ConnApi) pump() {
	$if macos { if api.native {
		pool := api.pool()
		loop := api.msg(u64(C.objc_getClass(c'NSRunLoop')), c'currentRunLoop', 0, 0, 0)
		date := unsafe { ConnReal(voidptr(api.send))(u64(C.objc_getClass(c'NSDate')), api.selector(c'dateWithTimeIntervalSinceNow:'), 0.01) }
		api.msg(loop, c'runMode:beforeDate:', api.string('kCFRunLoopDefaultMode'), date, 0)
		api.drain(pool)
		return
	} }
	dispatch_main_drain()
}
__global conn_api = ConnApi{}
__global conn_events = [4]int{}
__global conn_event_count = 0
__global conn_bytes = 0
__global conn_error = i64(0)
__global conn_destroyed = 0
__global conn_cancel_response = false
__global conn_shutdown_callback = false
fn conn_record(event int) { assert conn_event_count < conn_events.len; conn_events[conn_event_count] = event; conn_event_count++ }
fn conn_response(delegate u64, selector &char, object u64, response u64) {
	conn_record(1); assert conn_api.msg(response, c'expectedContentLength', 0, 0, 0) == 5;
	if conn_cancel_response { conn_api.msg(object, c'cancel', 0, 0, 0) }
}
fn conn_data(delegate u64, selector &char, object u64, data u64) {
	conn_record(2); length := conn_api.msg(data, c'length', 0, 0, 0)
	assert length <= 5 && conn_bytes + int(length) <= 5;
	assert C.memcmp(unsafe { voidptr(conn_api.msg(data, c'bytes', 0, 0, 0)) }, unsafe { &u8(c'abcde') + conn_bytes }, usize(length)) == 0;
	conn_bytes += int(length)
}
fn conn_finish(delegate u64, selector &char, object u64) { conn_record(3) }
fn conn_fail(delegate u64, selector &char, object u64, error_object u64) { if conn_shutdown_callback { objc_stop() }; conn_record(4); conn_error = i64(conn_api.msg(error_object, c'code', 0, 0, 0)) }
fn conn_dealloc(delegate u64, selector &char) {
	conn_destroyed++
	$if macos { if conn_api.native { C.object_dispose(unsafe { voidptr(delegate) }) } }
}
fn conn_reset(api ConnApi, cancel bool) { conn_api = api; conn_event_count = 0; conn_bytes = 0; conn_error = 0; conn_destroyed = 0; conn_cancel_response = cancel }
fn connection_cases(api ConnApi) {
	pool := api.pool(); path := '/tmp/vinix-connection-' + os.getpid().str() + if api.native { '-native.txt' } else { '-runtime.txt' }
	os.write_file(path, 'abcde') or { panic(err) }
	defer { os.rm(path) or { panic(err) } }
	for index, filename in [path, path + '-missing', '/tmp'] {
		request := api.request(filename, false)
		assert api.msg(api.cls, c'canHandleRequest:', request, 0, 0) == 1 && api.msg(api.cls, c'canHandleRequest:', 0, 0, 0) == 0;
		mut responses := [u64(0x123456789abcdef0), 0, 0xfedcba9876543210]!
		mut errors := [u64(0x123456789abcdef0), 0, 0xfedcba9876543210]!
		if index == 0 { errors[1] = 0x5678 }
		data := api.msg(api.cls, c'sendSynchronousRequest:returningResponse:error:', request, u64(unsafe { &responses[1] }), u64(unsafe { &errors[1] }))
		if index == 0 {
			assert data != 0 && errors[1] == 0x5678 && responses[1] != 0;
			assert api.msg(data, c'length', 0, 0, 0) == 5 && C.memcmp(unsafe { voidptr(api.msg(data, c'bytes', 0, 0, 0)) }, c'abcde', 5) == 0;
			assert api.msg(responses[1], c'expectedContentLength', 0, 0, 0) == 5;
			assert ctext(api.msg(api.msg(responses[1], c'MIMEType', 0, 0, 0), c'UTF8String', 0, 0, 0)) == 'text/plain';
			assert api.msg(responses[1], c'textEncodingName', 0, 0, 0) == 0;
			assert api.msg(api.cls, c'sendSynchronousRequest:returningResponse:error:', request, 0, 0) != 0;
		} else {
			assert data == 0 && responses[1] == 0 && errors[1] != 0;
			assert i64(api.msg(errors[1], c'code', 0, 0, 0)) == if index == 1 { i64(-1100) } else { i64(21) };
			domain := ctext(api.msg(api.msg(errors[1], c'domain', 0, 0, 0), c'UTF8String', 0, 0, 0))
			assert domain == if index == 1 { 'NSURLErrorDomain' } else { 'NSPOSIXErrorDomain' };
		}
		assert responses[0] == 0x123456789abcdef0 && responses[2] == 0xfedcba9876543210 && errors[0] == 0x123456789abcdef0 && errors[2] == 0xfedcba9876543210;
	}
	request := api.request(path, true)
	connection := api.msg(api.msg(api.cls, c'alloc', 0, 0, 0), c'initWithRequest:delegate:startImmediately:', request, 0, 0)
	original := api.msg(connection, c'originalRequest', 0, 0, 0)
	assert original == request;
	api.msg(original, c'retain', 0, 0, 0)
	api.msg(request, c'setHTTPMethod:', api.string('POST'), 0, 0)
	assert ctext(api.msg(api.msg(original, c'HTTPMethod', 0, 0, 0), c'UTF8String', 0, 0, 0)) == 'POST';
	assert ctext(api.msg(api.msg(api.msg(connection, c'currentRequest', 0, 0, 0), c'HTTPMethod', 0, 0, 0), c'UTF8String', 0, 0, 0)) == 'POST';
	assert api.msg(connection, c'defersCallbacks', 0, 0, 0) == 0;
	api.msg(connection, c'setDefersCallbacks:', 1, 0, 0); assert api.msg(connection, c'defersCallbacks', 0, 0, 0) == 0;
	api.msg(connection, c'cancel', 0, 0, 0); assert api.msg(api.msg(connection, c'originalRequest', 0, 0, 0), c'URL', 0, 0, 0) != 0;
	api.drain(pool); assert api.msg(original, c'URL', 0, 0, 0) != 0; api.msg(connection, c'release', 0, 0, 0); api.msg(original, c'release', 0, 0, 0)
	for mode in 0 .. 4 {
		conn_reset(api, mode == 2); inner := api.pool(); delegate := api.msg(api.probe, c'new', 0, 0, 0)
		object := api.msg(api.msg(api.cls, c'alloc', 0, 0, 0), c'initWithRequest:delegate:startImmediately:', api.request(if mode == 3 { path + '-missing' } else { path }, false), delegate, 0)
		api.msg(delegate, c'release', 0, 0, 0); assert conn_destroyed == 0;
		api.msg(object, c'start', 0, 0, 0); assert conn_event_count == 0;
		if mode == 1 { api.msg(object, c'cancel', 0, 0, 0) }
		api.drain(inner)
		for _ in 0 .. 200 { api.pump(); if (mode == 1 && conn_destroyed > 0) || conn_event_count >= if mode == 0 { 3 } else { 1 } { break } }
		if mode == 0 { assert conn_event_count == 3 && conn_events[0] == 1 && conn_events[1] == 2 && conn_events[2] == 3 && conn_bytes == 5; }
		else if mode == 1 { assert conn_event_count == 0; }
		else if mode == 2 { assert conn_event_count == 1 && conn_events[0] == 1 && conn_bytes == 0; }
		else { assert conn_event_count == 1 && conn_events[0] == 4 && conn_error == -1100; }
		api.msg(object, c'cancel', 0, 0, 0); api.msg(object, c'release', 0, 0, 0)
		for _ in 0 .. 10 { if conn_destroyed == 1 { break }; api.pump() }
		assert conn_destroyed == 1;
	}
}
fn test_connection_native() {
	$if macos {
		cls := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixNativeConnectionProbe', 0); assert cls != unsafe { nil };
		for name, address in {'connection:didReceiveResponse:': u64(unsafe { voidptr(conn_response) }), 'connection:didReceiveData:': u64(unsafe { voidptr(conn_data) }), 'connection:didFailWithError:': u64(unsafe { voidptr(conn_fail) }), 'connectionDidFinishLoading:': u64(unsafe { voidptr(conn_finish) }), 'dealloc': u64(unsafe { voidptr(conn_dealloc) })} {
			types := if name == 'dealloc' { c'v16@0:8' } else if name == 'connectionDidFinishLoading:' { c'v24@0:8@16' } else { c'v32@0:8@16@24' }
			assert C.class_addMethod(cls, C.sel_registerName(unsafe { &char(name.str) }), unsafe { voidptr(address) }, types);
		}
		C.objc_registerClassPair(cls)
		connection_cases(ConnApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSURLConnection')), strings: u64(C.objc_getClass(c'NSString')), urls: u64(C.objc_getClass(c'NSURL')), requests: u64(C.objc_getClass(c'NSURLRequest')), mutable_requests: u64(C.objc_getClass(c'NSMutableURLRequest')), probe: u64(cls)})
		println('IOS-CONNECTION-NATIVE: typed synchronous file loads/errors, retained original requests, callback order, cancellation and retained delegate lifetimes')
	}
}
fn connection_runtime_api() ConnApi {
	probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixConnectionProbe', 0); objc_register_class(probe)
	for name, address in {'connection:didReceiveResponse:': u64(unsafe { voidptr(conn_response) }), 'connection:didReceiveData:': u64(unsafe { voidptr(conn_data) }), 'connection:didFailWithError:': u64(unsafe { voidptr(conn_fail) }), 'connectionDidFinishLoading:': u64(unsafe { voidptr(conn_finish) }), 'dealloc': u64(unsafe { voidptr(conn_dealloc) })} {
		assert objc_add_method(probe, u64(name.str), address, if name == 'dealloc' { c'v16@0:8' } else if name == 'connectionDidFinishLoading:' { c'v24@0:8@16' } else { c'v32@0:8@16@24' });
	}
	return ConnApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSURLConnection'], strings: ios_runtime.names['NSString'], urls: ios_runtime.names['NSURL'], requests: ios_runtime.names['NSURLRequest'], mutable_requests: ios_runtime.names['NSMutableURLRequest'], probe: probe}
}
fn test_connection_runtime() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start() or { panic(err) }; api := connection_runtime_api()
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSURLConnection')! == api.cls;
		assert objc_class_size(api.cls) == 16 && objc_class_parent(api.cls) == ios_runtime.names['NSObject'];
		connection_cases(api); assert ios_runtime.live == 0 && ios_runtime.connections.len == 0;
		method := objc_instance_method(api.cls, u64(c'initWithRequest:delegate:startImmediately:'))
		assert ctext(u64(objc_method_types(method))) == '@36@0:8@16@24B32';
		pool := api.pool(); path := '/tmp/vinix-connection-registry-' + os.getpid().str(); os.write_file(path, 'abcde') or { panic(err) }
		request := api.request(path, false)
		conn_reset(api, false)
		mutable := api.request(path, true); delegate_snapshot := objc_new(api.probe)
		snapshot_connection := objc_allocate(api.cls); connection_initialize(snapshot_connection, mutable, delegate_snapshot, false); objc_release(delegate_snapshot)
		connection_start(snapshot_connection)
		api.msg(mutable, c'setURL:', api.msg(api.urls, c'fileURLWithPath:', api.string(path + '-missing'), 0, 0), 0, 0)
		assert obj_header(snapshot_connection).fields[2] != mutable;
		dispatch_main_drain(); assert conn_event_count == 3 && conn_bytes == 5 && conn_destroyed == 1; objc_release(snapshot_connection)
		conn_reset(api, false); loop := api.msg(ios_runtime.names['NSRunLoop'], c'currentRunLoop', 0, 0, 0)
		mode := api.string('kCFRunLoopDefaultMode'); paused := objc_allocate(api.cls); pause_delegate := objc_new(api.probe)
		connection_initialize(paused, request, pause_delegate, false); objc_release(pause_delegate)
		api.msg(paused, c'unscheduleFromRunLoop:forMode:', loop, mode, 0); connection_start(paused)
		assert !dispatch_main_drain() && conn_event_count == 0 && ios_runtime.connections.len == 1;
		api.msg(paused, c'scheduleInRunLoop:forMode:', loop, mode, 0); dispatch_main_drain()
		assert conn_event_count == 3 && conn_bytes == 5 && conn_destroyed == 1; objc_release(paused)
		for _ in 0 .. 100 {
			object := objc_allocate(api.cls); connection_initialize(object, request, 0, false); connection_start(object)
			objc_set_class(object, ios_runtime.names['NSObject']); objc_release(object); dispatch_main_drain()
		}
		mut bytes := [u64(0x123456789abcdef0), 0, 0, 0xfedcba9876543210]!
		caller := objc_construct_instance(api.cls, u64(unsafe { &bytes[1] })); connection_initialize(caller, request, 0, false)
		assert objc_destruct_instance(caller) == caller && bytes[0] == 0x123456789abcdef0 && bytes[3] == 0xfedcba9876543210;
		conn_reset(api, false); delegate := objc_new(api.probe); pending := objc_allocate(api.cls); connection_initialize(pending, request, delegate, true)
		objc_release(delegate); objc_release(pending); api.drain(pool)
		assert ios_runtime.connections.len == 1; objc_stop(); system_data_stop(); assert ios_runtime.live == 0 && conn_destroyed == 1;
		os.rm(path) or { panic(err) }
	}
	println('IOS-CONNECTION: main-queue file callbacks, original requests and transport snapshots, error/descriptor ownership, guarded16-byte caller storage,100 pending isa changes per cycle and two zero-live-object shutdowns with pending work discarded')
}
fn test_connection_rejections() {
	objc_start(); system_data_start() or { panic(err) }; api := connection_runtime_api()
	for mode in ['nil', 'type', 'url', 'reinit', 'uninitialized', 'network', 'queue', 'copy', 'subclass', 'default', 'caller-pending', 'mode', 'callback-shutdown']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork(); assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := objc_allocate(api.cls); request := api.request('/tmp', false)
			if mode !in ['nil', 'type', 'url', 'uninitialized', 'subclass', 'default']! { connection_initialize(object, request, 0, false) }
			match mode {
				'nil' { connection_initialize(object, 0, 0, false) }
				'type' { connection_initialize(object, objc_new(ios_runtime.names['NSObject']), 0, false) }
				'url' { connection_initialize(object, objc_new(api.requests), 0, false) }
				'reinit' { connection_initialize(object, request, 0, false) }
				'uninitialized' { connection_start(object) }
				'network' { network := api.msg(api.requests, c'requestWithURL:', api.msg(api.urls, c'URLWithString:', api.string('https://example.invalid/path'), 0, 0), 0, 0); connection_file_load(network, unsafe { nil }, unsafe { nil }) }
				'queue', 'copy' { mut frame := RegisterFrame{}; connection_dispatch(object, if mode == 'queue' { 'setDelegateQueue:' } else { 'copy' }, mut frame) }
				'subclass' { cls := objc_allocate_class(api.cls, c'UnsupportedConnection', 0); objc_register_class(cls); objc_allocate(cls) }
				'default' { objc_new(api.cls) }
				'caller-pending' { connection_start(object); objc_destruct_instance(object) }
				'mode' { mut frame := RegisterFrame{}; connection_dispatch(object, 'scheduleInRunLoop:forMode:', mut frame) }
				else { conn_reset(api, false); conn_shutdown_callback = true; objc_release(object); object2 := objc_allocate(api.cls); connection_initialize(object2, request, objc_new(api.probe), true); dispatch_main_drain() }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode { 'nil', 'type' { 'connection requires NSURLRequest' } 'url' { 'connection requires a request URL' } 'reinit' { 'connection reinitialization is not implemented' } 'uninitialized' { 'connection is not initialized' } 'network' { 'HTTP and HTTPS connection loading is not implemented' } 'queue', 'copy' { 'operation queues, coding and private properties are not implemented' } 'subclass' { 'custom connection subclass construction is not implemented' } 'default' { 'connection requires designated construction' } 'caller-pending' { 'cannot destruct pending connection storage' } 'mode' { 'connection scheduling requires the main default run loop' } else { 'runtime shutdown inside a connection callback is not implemented' } }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	objc_stop(); system_data_stop(); assert ios_runtime.live == 0;
	println('IOS-CONNECTION-REJECT: thirteen nil/type/URL/reinit/uninitialized/network/queue/copy/subclass/default/pending-storage/mode/shutdown cases fail explicitly')
}
