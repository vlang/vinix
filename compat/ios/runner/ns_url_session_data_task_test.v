// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type DataTaskSend = fn (u64, u64, u64) u64
type DataTaskPriority = fn (u64, u64) f32
struct DataTaskApi { native bool send u64 }
fn (api DataTaskApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn (api DataTaskApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api DataTaskApi) msg(object u64, selector &char, arg u64) u64 {
	return unsafe { DataTaskSend(voidptr(api.send))(object, api.selector(selector), arg) }
}
fn (api DataTaskApi) priority(object u64) f32 {
	return unsafe { DataTaskPriority(voidptr(api.send))(object, api.selector(c'priority')) }
}
fn (api DataTaskApi) string(value &char) u64 { return api.msg(api.cls(c'NSString'), c'stringWithUTF8String:', u64(value)) }
fn (api DataTaskApi) text(object u64) string { assert object != 0; return ctext(api.msg(object, c'UTF8String', 0)) }
fn (api DataTaskApi) release(object u64) { api.msg(object, c'release', 0) }
fn (api DataTaskApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls(c'NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api DataTaskApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn (api DataTaskApi) session() u64 {
	config := api.msg(api.cls(c'NSURLSessionConfiguration'), c'defaultSessionConfiguration', 0)
	return api.msg(api.msg(api.cls(c'NSURLSession'), c'sessionWithConfiguration:', config), c'retain', 0)
}
fn (api DataTaskApi) request(mutable_request bool) u64 {
	url := api.msg(api.cls(c'NSURL'), c'URLWithString:', api.string(c'https://invalid.example/no-transfer'))
	return api.msg(api.cls(if mutable_request { c'NSMutableURLRequest' } else { c'NSURLRequest' }), c'requestWithURL:', url)
}
fn data_task_cases(api DataTaskApi) {
	pool := api.pool()
	session := api.session()
	for mutable_request in [true, false]! {
		request := api.request(mutable_request)
		if mutable_request { api.msg(request, c'setHTTPMethod:', api.string(c'POST')) }
		task := api.msg(session, c'dataTaskWithRequest:', request)
		assert task != 0 && api.msg(task, c'isKindOfClass:', api.cls(c'NSURLSessionDataTask')) == 1
		assert api.msg(task, c'taskIdentifier', 0) == if mutable_request { u64(1) } else { u64(2) }
		assert api.msg(task, c'state', 0) == 1 && bits.f32_bits(api.priority(task)) == bits.f32_bits(0.5)
		for getter in [c'countOfBytesClientExpectsToSend', c'countOfBytesClientExpectsToReceive']! { assert i64(api.msg(task, getter, 0)) == -1 }
		for getter in [c'countOfBytesSent', c'countOfBytesReceived', c'countOfBytesExpectedToSend', c'countOfBytesExpectedToReceive', c'response', c'error', c'taskDescription']! { assert api.msg(task, getter, 0) == 0 }
		original := api.msg(task, c'originalRequest', 0)
		current := api.msg(task, c'currentRequest', 0)
		assert original != 0 && current != 0 && original != current && current != request
		if mutable_request { assert original != request }
		assert api.msg(original, c'isKindOfClass:', api.cls(c'NSMutableURLRequest')) == u64(mutable_request)
		assert api.msg(current, c'isKindOfClass:', api.cls(c'NSMutableURLRequest')) == 1
		if mutable_request {
			api.msg(request, c'setHTTPMethod:', api.string(c'DELETE'))
			assert api.text(api.msg(original, c'HTTPMethod', 0)) == 'POST' && api.text(api.msg(current, c'HTTPMethod', 0)) == 'POST'
			api.msg(original, c'setHTTPMethod:', api.string(c'PUT'))
			assert api.text(api.msg(current, c'HTTPMethod', 0)) == 'POST'
		} else { assert api.text(api.msg(original, c'HTTPMethod', 0)) == 'GET' }
		for selector in [c'copy', c'copyWithZone:']! { assert api.msg(task, selector, 0) == task; api.release(task) }
	}
	if api.native { api.msg(session, c'invalidateAndCancel', 0) }
	api.release(session); api.drain(pool)
}
fn test_session_data_task_native() {
	$if macos {
		data_task_cases(DataTaskApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))})
		println('IOS-SESSION-DATA-TASK-NATIVE: suspended defaults, sequential identifiers, independent mutable/immutable request snapshots and copy identity; no transfers started')
	}
}
fn data_task_worker(api DataTaskApi, session u64) []u64 {
	pool := api.pool(); request := api.request(true)
	mut identifiers := []u64{cap: 32}
	for _ in 0 .. 32 { task := api.msg(session, c'dataTaskWithRequest:', request); identifiers << api.msg(task, c'taskIdentifier', 0); assert api.msg(task, c'state', 0) == 1 }
	api.drain(pool); return identifiers
}
__global data_task_constructor_owner = u64(0)
__global data_task_constructor_request = u64(0)
__global data_task_constructor_active = false
__global data_task_constructor_fail = false
fn data_task_constructor_worker() {
	assert obj_header(data_task_constructor_owner).fields[2] != 0
	assert obj_header(data_task_constructor_request).request != unsafe { nil }
	objc_release(data_task_constructor_owner)
	objc_release(data_task_constructor_request)
}
fn data_task_constructor(object u64, selector &char) u64 {
	if !data_task_constructor_active { return object }
	data_task_constructor_active = false
	worker := spawn data_task_constructor_worker()
	worker.wait()
	return if data_task_constructor_fail { u64(0) } else { object }
}
fn data_task_constructor_cases(api DataTaskApi) {
	assert objc_add_method(api.cls(c'NSURLSessionDataTask'), u64(c'.cxx_construct'), u64(unsafe { voidptr(data_task_constructor) }), c'@16@0:8')
	for fail in [false, true]! {
		input_pool := api.pool()
		data_task_constructor_owner = api.session()
		data_task_constructor_request = api.msg(api.request(true), c'retain', 0)
		api.drain(input_pool)
		pool := api.pool()
		mut weak_owner := u64(0); mut weak_request := u64(0)
		objc_store_weak(unsafe { &weak_owner }, data_task_constructor_owner)
		objc_store_weak(unsafe { &weak_request }, data_task_constructor_request)
		data_task_constructor_fail = fail; data_task_constructor_active = true
		task := api.msg(data_task_constructor_owner, c'dataTaskWithRequest:', data_task_constructor_request)
		assert !data_task_constructor_active && (task == 0) == fail
		assert weak_request == 0 && (weak_owner == 0) == fail
		api.drain(pool)
		assert weak_owner == 0 && ios_runtime.live == 0
		objc_destroy_weak(unsafe { &weak_owner }); objc_destroy_weak(unsafe { &weak_request })
	}
}
fn test_session_data_task_runtime() {
	api := DataTaskApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for _ in 0 .. 2 {
		objc_start(); data_task_cases(api); assert ios_runtime.live == 0
		cls := api.cls(c'NSURLSession')
		method := objc_instance_method(cls, u64(c'dataTaskWithRequest:'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@24@0:8@16'
		pool := api.pool(); session := api.session(); request := api.request(true)
		imp := objc_method_implementation(cls, u64(c'dataTaskWithRequest:'))
		task := unsafe { DataTaskSend(voidptr(imp))(session, u64(c'dataTaskWithRequest:'), request) }
		assert api.msg(task, c'taskIdentifier', 0) == 1
		assert read64(task + 120) == 1 && read64(task + 232) == 1
		assert read64(task + 144) == api.msg(task, c'originalRequest', 0) && read64(task + 152) == api.msg(task, c'currentRequest', 0)
		signature := api.msg(session, c'methodSignatureForSelector:', u64(c'dataTaskWithRequest:'))
		assert signature != 0 && api.msg(signature, c'numberOfArguments', 0) == 3
		assert ctext(api.msg(signature, c'methodReturnType', 0)) == '@'
		mut workers := []thread []u64{}
		for _ in 0 .. 8 { workers << spawn data_task_worker(api, session) }
		mut seen := map[u64]bool{}
		for worker in workers {
			ids := worker.wait()
			for id in ids { assert id >= 2 && id <= 257 && id !in seen; seen[id] = true }
			unsafe { ids.free() }
		}
		assert seen.len == 256
		unsafe { workers.free(); seen.free() }
		// Two sessions have independent sequences; task ownership keeps the owner
		// and its configuration alive without making the owner retain the task.
		other := api.session(); other_task := api.msg(other, c'dataTaskWithRequest:', request)
		assert api.msg(other_task, c'taskIdentifier', 0) == 1
		api.release(other)
		mut weak_task := u64(0); mut weak_owner := u64(0); mut weak_request := u64(0)
		objc_store_weak(unsafe { &weak_task }, task); objc_store_weak(unsafe { &weak_owner }, session)
		objc_store_weak(unsafe { &weak_request }, api.msg(task, c'originalRequest', 0))
		api.release(session)
		assert weak_owner != 0
		assert objc_set_class(task, api.cls(c'NSObject')) == api.cls(c'NSURLSessionDataTask')
		api.drain(pool)
		assert weak_task == 0 && weak_owner == 0 && weak_request == 0
		for slot in [unsafe { &weak_task }, &weak_owner, &weak_request]! { objc_destroy_weak(slot) }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		data_task_constructor_cases(api)
		shutdown_session := api.session(); shutdown_request := api.request(false)
		shutdown_task := api.msg(shutdown_session, c'dataTaskWithRequest:', shutdown_request)
		api.release(shutdown_session)
		objc_store_weak(unsafe { &weak_task }, shutdown_task); objc_store_weak(unsafe { &weak_owner }, shutdown_session)
		objc_stop()
		assert weak_task == 0 && weak_owner == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-SESSION-DATA-TASK: typed direct IMP and metadata, snapshots, suspended defaults, 256 concurrent identifiers, per-session sequences, reentrant constructors and failure cleanup, isa replacement and two drained runtimes')
}

fn test_session_data_task_rejections() {
	objc_start()
	api := DataTaskApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for mode in ['nil', 'wrong-type', 'uninitialized', 'custom', 'spoof', 'retired-session', 'exhausted', 'resume', 'suspend', 'cancel']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			session := api.session()
			mut request := api.request(true)
			match mode {
				'nil' { request = 0 }
				'wrong-type' { request = objc_new(api.cls(c'NSObject')) }
				'uninitialized' { request = objc_allocate(api.cls(c'NSURLRequest')) }
				'custom' {
					sub := objc_allocate_class(api.cls(c'NSURLRequest'), c'VinixDataTaskCustomRequest', 0)
					objc_register_class(sub)
					request = api.msg(sub, c'new', 0)
				}
				'spoof' {
					spoof := objc_allocate_class(api.cls(c'NSObject'), c'VinixDataTaskRequestSpoof', 0)
					assert objc_add_ivar(spoof, c'bytes', 16, 3, c'[16C]')
					objc_register_class(spoof)
					request = objc_new(spoof)
					objc_set_class(request, api.cls(c'NSURLRequest'))
				}
				'retired-session' { obj_header(session).destroying = true }
				'exhausted' { obj_header(session).url_session_next_task = ~u64(0) }
				else {}
			}
			task := api.msg(session, c'dataTaskWithRequest:', request)
			if mode in ['resume', 'suspend', 'cancel']! {
				api.msg(task, match mode { 'resume' { c'resume' } 'suspend' { c'suspend' } else { c'cancel' } }, 0)
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0; length += int(count)
		}
		C.close(fds[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'custom' { 'data task custom request subclasses are not implemented' }
			'retired-session' { 'URL session requires live base session storage' }
			'exhausted' { 'URL session task identifiers exhausted' }
			'resume', 'suspend', 'cancel' { 'URL session task transfers, cancellation, delegates, progress and coding are not implemented' }
			else { 'data task requires an initialized URL request' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
		if mode in ['resume', 'suspend', 'cancel']! { assert output.contains('-[NSURLSessionDataTask ${mode}]'), output }
	}
	assert ios_runtime.live == 0
	objc_stop()
	println('IOS-SESSION-DATA-TASK-REJECT: ten nil/type/storage/subclass/spoof/lifetime/identifier/transfer cases fail explicitly')
}
