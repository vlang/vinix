// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

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
fn C.objc_getProtocol(&char) voidptr
fn C.class_addProtocol(voidptr, voidptr) bool
fn C.__atomic_load_n(&u64, int) u64
fn C.__atomic_store_n(&u64, u64, int)
fn C.__atomic_fetch_add(&u64, u64, int) u64
type CancelSend = fn (u64, u64, u64, u64, u64) u64
struct CancelApi { native bool send u64 }
fn (a CancelApi) cls(name &char) u64 {
	$if macos { if a.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn (a CancelApi) sel(name &char) u64 {
	$if macos { if a.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (a CancelApi) msg(object u64, name &char, x u64, y u64, z u64) u64 {
	return unsafe { CancelSend(voidptr(a.send))(object, a.sel(name), x, y, z) }
}
fn (a CancelApi) pool() u64 {
	return if a.native { a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } else { objc_pool_push() }
}
fn (a CancelApi) drain(pool u64) {
	if a.native { a.msg(pool, c'drain', 0, 0, 0) } else { objc_pool_pop(pool) }
}
fn (a CancelApi) text(object u64) string { return ctext(a.msg(object, c'UTF8String', 0, 0, 0)) }
fn (a CancelApi) release(object u64) { a.msg(object, c'release', 0, 0, 0) }
struct CancelProbe {
	api CancelApi
	queue u64
	wanted_delegate u64
	thread u64
mut:
	finished u64
	calls u64
	error_object u64
	delegate_at_completion u64
	failure u64
}
__global cancel_probe = unsafe { &CancelProbe(nil) }
fn cancel_callback(delegate u64, _ &char, session u64, task u64, error_object u64) {
	mut p := cancel_probe
	a := p.api
	// Foreign callbacks report failures to the test thread. V's test assertion
	// recovery context belongs to that thread and cannot unwind this C caller.
	if delegate != p.wanted_delegate || u64(C.pthread_self()) == p.thread { p.failure |= 1 }
	current_queue := if a.native { a.msg(a.cls(c'NSOperationQueue'), c'currentQueue', 0, 0, 0) } else { ns_operation_queue_current() }
	if current_queue != p.queue { p.failure |= 2 }
	if a.msg(task, c'state', 0, 0, 0) != 3 { p.failure |= 4 }
	if error_object == 0 || i64(a.msg(error_object, c'code', 0, 0, 0)) != -999
		|| a.text(a.msg(error_object, c'domain', 0, 0, 0)) != 'NSURLErrorDomain' { p.failure |= 8 }
	stored := a.msg(task, c'error', 0, 0, 0)
	// Foundation can hand the delegate a separate NSError with the same error
	// semantics. Neither API promises object identity with the task getter.
	if stored == 0 || i64(a.msg(stored, c'code', 0, 0, 0)) != -999
		|| a.text(a.msg(stored, c'domain', 0, 0, 0)) != 'NSURLErrorDomain' { p.failure |= 16 }
	if a.msg(task, c'response', 0, 0, 0) != 0 { p.failure |= 32 }
	if a.msg(session, c'delegateQueue', 0, 0, 0) != p.queue { p.failure |= 64 }
	if !a.native {
		// A different thread must reenter successfully while this callback waits.
		worker := spawn cancel_worker(a, task)
		worker.wait()
	}
	p.delegate_at_completion = a.msg(task, c'delegate', 0, 0, 0)
	p.error_object = a.msg(error_object, c'retain', 0, 0, 0)
	// Reentrant cancellation is idempotent, including from the delegate queue.
	a.msg(task, c'cancel', 0, 0, 0)
	C.__atomic_fetch_add(unsafe { &p.calls }, 1, 5)
	C.__atomic_store_n(unsafe { &p.finished }, 1, 5)
}
fn cancel_wait(value &u64) {
	deadline := time.sys_mono_now() + 5 * time.second
	for C.__atomic_load_n(value, 5) == 0 { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
}
fn cancel_class(a CancelApi, name &char, callback bool) u64 {
	$if macos { if a.native {
		cls := C.objc_allocateClassPair(voidptr(a.cls(c'NSObject')), name, 0)
		assert cls != unsafe { nil };
		assert C.class_addProtocol(cls, C.objc_getProtocol(c'NSURLSessionTaskDelegate'));
		if callback { assert C.class_addMethod(cls, C.sel_registerName(c'URLSession:task:didCompleteWithError:'), unsafe { voidptr(cancel_callback) }, c'v40@0:8@16@24@32'); }
		C.objc_registerClassPair(cls)
		return u64(cls)
	} }
	cls := objc_allocate_class(a.cls(c'NSObject'), name, 0)
	assert cls != 0;
	if callback { assert objc_add_method(cls, u64(c'URLSession:task:didCompleteWithError:'), u64(unsafe { voidptr(cancel_callback) }), c'v40@0:8@16@24@32'); }
	objc_register_class(cls)
	return cls
}
fn cancel_worker(a CancelApi, task u64) {
	pool := a.pool()
	for _ in 0 .. 32 { a.msg(task, c'cancel', 0, 0, 0) }
	a.drain(pool)
}
fn cancel_cases(a CancelApi) {
	full := cancel_class(a, c'VinixCancellationDelegate', true)
	partial := cancel_class(a, c'VinixCancellationPartial', false)
	for mode in ['session', 'task', 'fallback', 'concurrent', 'replace-pending'] {
		pool := a.pool()
		queue := a.msg(a.cls(c'NSOperationQueue'), c'new', 0, 0, 0)
		a.msg(queue, c'setMaxConcurrentOperationCount:', 1, 0, 0)
		a.msg(queue, c'setSuspended:', 1, 0, 0)
		session_delegate := a.msg(full, c'new', 0, 0, 0)
		task_delegate := if mode in ['session', 'fallback'] { a.msg(partial, c'new', 0, 0, 0) } else { a.msg(full, c'new', 0, 0, 0) }
		config := a.msg(a.cls(c'NSURLSessionConfiguration'), c'defaultSessionConfiguration', 0, 0, 0)
		session := a.msg(a.msg(a.cls(c'NSURLSession'), c'sessionWithConfiguration:delegate:delegateQueue:', config, session_delegate, queue), c'retain', 0, 0, 0)
		url := a.msg(a.cls(c'NSURL'), c'URLWithString:', a.msg(a.cls(c'NSString'), c'stringWithUTF8String:', u64(c'http://127.0.0.1:9/never-resumed'), 0, 0), 0, 0)
		request := a.msg(a.cls(c'NSURLRequest'), c'requestWithURL:', url, 0, 0)
		task := a.msg(session, c'dataTaskWithRequest:', request, 0, 0)
		if mode != 'session' { a.msg(task, c'setDelegate:', task_delegate, 0, 0) }
		mut p := CancelProbe{api: a, queue: queue, wanted_delegate: if mode in ['session', 'fallback', 'replace-pending'] { session_delegate } else { task_delegate }, thread: u64(C.pthread_self())}
		cancel_probe = unsafe { &p }
		mut workers := []thread{}
		if mode == 'concurrent' { for _ in 0 .. 8 { workers << spawn cancel_worker(a, task) } }
		else { a.msg(task, c'cancel', 0, 0, 0); a.msg(task, c'cancel', 0, 0, 0) }
		workers.wait(); unsafe { workers.free() }
		if mode == 'replace-pending' { a.msg(task, c'setDelegate:', 0, 0, 0) }
		assert C.__atomic_load_n(unsafe { &p.finished }, 5) == 0;
		a.msg(queue, c'setSuspended:', 0, 0, 0)
		cancel_wait(unsafe { &p.finished })
		a.msg(queue, c'waitUntilAllOperationsAreFinished', 0, 0, 0)
		assert p.calls == 1 && p.failure == 0, 'mode=${mode} failures=${p.failure}';
		assert p.delegate_at_completion == if mode in ['session', 'replace-pending'] { u64(0) } else { task_delegate };
		assert a.msg(task, c'delegate', 0, 0, 0) == 0;
		println('IOS-SESSION-CANCEL-${if a.native { "NATIVE" } else { "RUNTIME" }}: ${mode} callback_delegate=${p.delegate_at_completion == task_delegate} delegate_after=${a.msg(task, c"delegate", 0, 0, 0) == task_delegate} state=${a.msg(task, c"state", 0, 0, 0)}')
		a.release(p.error_object)
		if a.native { a.msg(session, c'invalidateAndCancel', 0, 0, 0) }
		a.release(session); a.release(session_delegate); a.release(task_delegate); a.release(queue)
		a.drain(pool)
		cancel_probe = unsafe { nil }
	}
}
fn test_session_cancel_native() {
	$if macos {
		a := CancelApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		cancel_cases(a)
	}
}

fn cancel_runtime_task(a CancelApi, queue u64, delegate u64, nil_url bool) u64 {
	config := a.msg(a.cls(c'NSURLSessionConfiguration'), c'defaultSessionConfiguration', 0, 0, 0)
	session := a.msg(a.cls(c'NSURLSession'), c'sessionWithConfiguration:delegate:delegateQueue:', config, delegate, queue)
	url := if nil_url { u64(0) } else {
		a.msg(a.cls(c'NSURL'), c'URLWithString:', objc_autorelease(owned_string('https://127.0.0.1:9/never-resumed')), 0, 0)
	}
	request := a.msg(a.cls(c'NSURLRequest'), c'requestWithURL:', url, 0, 0)
	return a.msg(session, c'dataTaskWithRequest:', request, 0, 0)
}
fn cancel_barrier(_ voidptr) {}
__global cancel_constructor_task = u64(0)
__global cancel_constructor_calls = u64(0)
fn cancel_error_construct(object u64, _ &char) u64 {
	if cancel_constructor_task == 0 { return object }
	worker := spawn cancel_worker(CancelApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}, cancel_constructor_task)
	worker.wait()
	cancel_constructor_calls++
	return object
}
fn cancel_runtime_ownership(a CancelApi) {
	// No delegate, no URL: the error still has the correct domain/code and its
	// public getter owns an autorelease reference independently of the task.
	for nil_url in [false, true]! {
		inputs := a.pool()
		task := a.msg(cancel_runtime_task(a, 0, 0, nil_url), c'retain', 0, 0, 0)
		queue := a.msg(a.msg(obj_header(task).fields[3], c'delegateQueue', 0, 0, 0), c'retain', 0, 0, 0)
		// Invoke through the typed IMP, rather than only the message trampoline.
		method := objc_instance_method(a.cls(c'NSURLSessionDataTask'), u64(c'cancel'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'v16@0:8';
		unsafe { CancelSend(voidptr(objc_method_imp(method)))(task, u64(c'cancel'), 0, 0, 0) }
		a.msg(queue, c'waitUntilAllOperationsAreFinished', 0, 0, 0)
		assert a.msg(task, c'state', 0, 0, 0) == 3;
		a.drain(inputs)
		pool := a.pool()
		error_object := a.msg(task, c'error', 0, 0, 0)
		assert error_object != 0 && read64(task + 240) == error_object && obj_header(task).fields[6] == error_object;
		assert i64(a.msg(error_object, c'code', 0, 0, 0)) == -999;
		mut weak_error := u64(0)
		objc_store_weak(unsafe { &weak_error }, error_object)
		a.release(task); a.release(queue)
		assert weak_error == error_object;
		a.drain(pool)
		assert weak_error == 0;
		objc_destroy_weak(unsafe { &weak_error })
	}
	// A suspended queued completion pins the full task/session/queue chain,
	// including after the task's isa changes. The barrier includes job cleanup.
	inputs := a.pool()
	queue := a.msg(a.cls(c'NSOperationQueue'), c'new', 0, 0, 0)
	a.msg(queue, c'setSuspended:', 1, 0, 0)
	task := cancel_runtime_task(a, queue, 0, false)
	mut weak_task := u64(0); mut weak_session := u64(0); mut weak_queue := u64(0)
	objc_store_weak(unsafe { &weak_task }, task)
	objc_store_weak(unsafe { &weak_session }, obj_header(task).fields[3])
	objc_store_weak(unsafe { &weak_queue }, queue)
	a.msg(task, c'cancel', 0, 0, 0)
	assert a.msg(queue, c'operationCount', 0, 0, 0) == 1;
	backing := obj_header(queue).operation_queue.backing
	darwin_dispatch_retain(backing)
	objc_set_class(task, a.cls(c'NSObject'))
	a.release(queue); a.drain(inputs)
	assert weak_task == task && weak_queue == queue && weak_session != 0;
	a.msg(queue, c'setSuspended:', 0, 0, 0)
	darwin_dispatch_sync_f(backing, unsafe { nil }, cancel_barrier)
	assert weak_task == 0 && weak_session == 0 && weak_queue == 0;
	for slot in [unsafe { &weak_task }, &weak_session, &weak_queue]! { objc_destroy_weak(slot) }
	darwin_dispatch_release(backing)
	// Completion releases the task delegate even if it owns the task itself.
	cycle_inputs := a.pool()
	cycle_queue := a.msg(a.cls(c'NSOperationQueue'), c'new', 0, 0, 0)
	a.msg(cycle_queue, c'setSuspended:', 1, 0, 0)
	cycle_task := cancel_runtime_task(a, cycle_queue, 0, false)
	cycle_delegate := objc_new(a.cls(c'NSObject'))
	obj_header(cycle_delegate).fields[0] = objc_retain(cycle_task)
	a.msg(cycle_task, c'setDelegate:', cycle_delegate, 0, 0)
	mut weak_cycle_task := u64(0); mut weak_cycle_delegate := u64(0)
	objc_store_weak(unsafe { &weak_cycle_task }, cycle_task)
	objc_store_weak(unsafe { &weak_cycle_delegate }, cycle_delegate)
	a.msg(cycle_task, c'cancel', 0, 0, 0)
	cycle_backing := obj_header(cycle_queue).operation_queue.backing
	darwin_dispatch_retain(cycle_backing)
	a.release(cycle_delegate); a.drain(cycle_inputs)
	assert weak_cycle_task == cycle_task && weak_cycle_delegate == cycle_delegate;
	a.msg(cycle_queue, c'setSuspended:', 0, 0, 0)
	darwin_dispatch_sync_f(cycle_backing, unsafe { nil }, cancel_barrier)
	assert weak_cycle_task == 0 && weak_cycle_delegate == 0;
	objc_destroy_weak(unsafe { &weak_cycle_task }); objc_destroy_weak(unsafe { &weak_cycle_delegate })
	a.release(cycle_queue); darwin_dispatch_release(cycle_backing)
	// Constructors run outside the task lock after the completion is reserved.
	assert objc_add_method(a.cls(c'NSError'), u64(c'.cxx_construct'), u64(unsafe { voidptr(cancel_error_construct) }), c'@16@0:8');
	pool := a.pool()
	cancel_constructor_task = cancel_runtime_task(a, 0, 0, false)
	cancel_constructor_calls = 0
	a.msg(cancel_constructor_task, c'cancel', 0, 0, 0)
	queue2 := a.msg(obj_header(cancel_constructor_task).fields[3], c'delegateQueue', 0, 0, 0)
	a.msg(queue2, c'waitUntilAllOperationsAreFinished', 0, 0, 0)
	assert cancel_constructor_calls == 1;
	cancel_constructor_task = 0
	a.drain(pool)
}
fn test_session_cancel_runtime() {
	a := CancelApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		cancel_cases(a)
		cancel_runtime_ownership(a)
		// Discarded suspended completions release all their references and never
		// invoke a delegate while the runtime and image mappings are retired.
		pool := a.pool()
		queue := a.msg(a.cls(c'NSOperationQueue'), c'new', 0, 0, 0)
		a.msg(queue, c'setSuspended:', 1, 0, 0)
		mut weak_task := u64(0); mut weak_session := u64(0); mut weak_queue := u64(0)
		for index in 0 .. 32 {
			task := cancel_runtime_task(a, queue, 0, false)
			a.msg(task, c'cancel', 0, 0, 0)
			if index == 0 {
				objc_store_weak(unsafe { &weak_task }, task)
				objc_store_weak(unsafe { &weak_session }, obj_header(task).fields[3])
			}
		}
		objc_store_weak(unsafe { &weak_queue }, queue)
		assert a.msg(queue, c'operationCount', 0, 0, 0) == 32;
		a.release(queue); a.drain(pool)
		assert weak_task != 0 && weak_session != 0 && weak_queue != 0;
		objc_stop()
		assert weak_task == 0 && weak_session == 0 && weak_queue == 0;
		for slot in [unsafe { &weak_task }, &weak_session, &weak_queue]! { objc_destroy_weak(slot) }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0;
		system_data_stop()
	}
	println('IOS-SESSION-CANCEL: queued completion, eight callers, reentrant cancellation, fallback, result ownership, nil URL, typed IMP, constructors, isa replacement and shutdown discard PASS')
}

fn cancel_shutdown_callback(_ u64, _ &char, _ u64, _ u64, _ u64) { objc_stop() }
fn cancel_reject_watchdog() { time.sleep(5 * time.second); C._exit(124) }
fn test_session_cancel_lifetime_rejections() {
	for mode in ['pending-destruct', 'callback-shutdown'] {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork()
		assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); C.dup2(fds[1], 2); C.close(fds[1])
			spawn cancel_reject_watchdog()
			objc_start(); system_data_start()!
			a := CancelApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
			queue := a.msg(a.cls(c'NSOperationQueue'), c'new', 0, 0, 0)
			a.msg(queue, c'setSuspended:', 1, 0, 0)
			mut delegate := u64(0)
			if mode == 'callback-shutdown' {
				cls := objc_allocate_class(a.cls(c'NSObject'), c'VinixCancelShutdown', 0)
				objc_add_method(cls, u64(c'URLSession:task:didCompleteWithError:'), u64(unsafe { voidptr(cancel_shutdown_callback) }), c'v40@0:8@16@24@32')
				objc_register_class(cls)
				delegate = objc_new(cls)
			}
			task := cancel_runtime_task(a, queue, delegate, false)
			a.msg(task, c'cancel', 0, 0, 0)
			if mode == 'pending-destruct' { objc_destruct_instance(task) }
			else { a.msg(queue, c'setSuspended:', 0, 0, 0); time.sleep(6 * time.second) }
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [8192]u8{}
		mut length := 0
		for {
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0 && length + int(count) < bytes.len;
			length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains(if mode == 'pending-destruct' { 'cannot destruct pending URL session completion storage' } else { 'runtime shutdown inside a URL session task callback is not implemented' }), output;
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	println('IOS-SESSION-CANCEL-REJECT: explicit pending destruction and shutdown from completion fail before storage retirement or worker join PASS')
}
