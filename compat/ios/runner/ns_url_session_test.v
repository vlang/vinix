// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
type SessionMessage = fn (u64, u64, u64, u64, u64) u64
struct SessionApi { native bool send u64 cls u64 strings u64 mutable_strings u64 queues u64 }
fn (api SessionApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { SessionMessage(voidptr(api.send))(object, selector, a, b, c) }
}
fn (api SessionApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0, 0) }
fn (api SessionApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0, 0)) }
fn (api SessionApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0, 0) }
fn (api SessionApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api SessionApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api SessionApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn session_probe_copy(object u64, selector &char) u64 { return owned_string(string_text(object)) }
fn session_probe_bad_copy(object u64, selector &char) u64 { return objc_new(ios_runtime.names['NSObject']) }
fn session_app_tasks(object u64, selector u64, a u64, b u64, c u64) u64 { return object }
__global session_initializer_owner = u64(0)
__global session_initializer_calls = 0
fn session_initializer_reader(object u64) {
	pool := objc_pool_push()
	api := SessionApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) })}
	assert api.text(api.message(object, c'sessionDescription', 0, 0, 0)) == 'initializer reentry'
	objc_pool_pop(pool)
}
fn session_queue_initializer(object u64, selector &char) u64 {
	session_initializer_calls++
	worker := spawn session_initializer_reader(session_initializer_owner)
	worker.wait()
	return object
}
fn (api SessionApi) mutable_string(value &char) u64 {
	$if macos { if api.native { return api.retain(api.message(api.mutable_strings, c'stringWithUTF8String:', u64(value), 0, 0)) } }
	object := owned_string(ctext(u64(value)))
	objc_set_class(object, api.mutable_strings)
	return object
}
fn (api SessionApi) change_string(object u64, value &char) {
	$if macos { if api.native { api.message(object, c'setString:', api.string(value), 0, 0); return } }
	text := ctext(u64(value)); mut header := obj_header(object)
	C.free(header.text); header.text = unsafe { &char(C.malloc(usize(text.len + 1))) }
	assert header.text != unsafe { nil }
	unsafe { C.memcpy(header.text, text.str, usize(text.len)); header.text[text.len] = 0 }
	header.text_length = text.len
}
fn session_runtime_api() SessionApi {
	mutable := objc_allocate_class(ios_runtime.names['NSString'], c'VinixSessionMutableString', 0)
	assert mutable != 0 && objc_add_method(mutable, u64(c'copy'), u64(unsafe { voidptr(session_probe_copy) }), c'@16@0:8')
	objc_register_class(mutable)
	return SessionApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cls: ios_runtime.names['NSURLSession'], strings: ios_runtime.names['NSString'], mutable_strings: mutable, queues: ios_runtime.names['NSOperationQueue']}
}

fn session_base_cases(api SessionApi) {
	for construction in [c'alloc', c'new']! {
		pool := api.pool()
		object := api.message(api.cls, construction, 0, 0, 0)
		assert object != 0 && api.message(object, c'class', 0, 0, 0) == api.cls
		assert read64(object + 80) == 0 && read64(object + 104) == 0
		assert api.message(object, c'delegate', 0, 0, 0) == 0
		assert api.message(object, c'configuration', 0, 0, 0) == 0
		assert api.message(object, c'sessionDescription', 0, 0, 0) == 0
		assert api.message(object, c'init', 0, 0, 0) == object
		assert api.message(object, c'init', 0, 0, 0) == object
		if !api.native { assert obj_header(object).refs == 1 }
		source := api.mutable_string(c'original session')
		api.message(object, c'setSessionDescription:', source, 0, 0)
		if !api.native { assert obj_header(source).refs == 1 }
		stored := api.message(object, c'sessionDescription', 0, 0, 0)
		assert stored != source && read64(object + 104) == stored && api.text(stored) == 'original session'
		api.change_string(source, c'changed input')
		assert api.text(api.message(object, c'sessionDescription', 0, 0, 0)) == 'original session'
		api.release(source)
		assert api.retain(stored) == stored
		api.message(object, c'setSessionDescription:', 0, 0, 0)
		assert read64(object + 104) == 0 && api.message(object, c'sessionDescription', 0, 0, 0) == 0
		assert api.text(stored) == 'original session'
		api.message(object, c'setSessionDescription:', stored, 0, 0)
		api.message(object, c'setSessionDescription:', api.message(object, c'sessionDescription', 0, 0, 0), 0, 0)
		queue := api.message(object, c'delegateQueue', 0, 0, 0)
		assert queue != 0 && read64(object + 80) == queue && api.message(object, c'delegateQueue', 0, 0, 0) == queue
		assert api.message(queue, c'isKindOfClass:', api.queues, 0, 0) == 1
		assert api.message(queue, c'maxConcurrentOperationCount', 0, 0, 0) == 1
		assert api.retain(queue) == queue
		assert api.message(object, c'init', 0, 0, 0) == object
		assert read64(object + 80) == queue && read64(object + 104) == stored
		assert api.message(object, c'delegateQueue', 0, 0, 0) == queue
		assert api.message(object, c'sessionDescription', 0, 0, 0) == stored
		for selector in [c'copy', c'copyWithZone:']! {
			assert api.message(object, selector, 0, 0, 0) == object
			if !api.native { assert obj_header(object).refs == 2 }
			api.release(object)
		}
		if !api.native {
			for zone in [false, true]! {
				assert objc_copy_value(object, zone) == object && obj_header(object).refs == 2
				api.release(object)
			}
		}
		api.drain(pool)
		if !api.native { assert obj_header(object).refs == 1 && obj_header(queue).refs == 2 }
		api.release(object)
		assert api.message(queue, c'maxConcurrentOperationCount', 0, 0, 0) == 1 && api.text(stored) == 'original session'
		if !api.native { assert obj_header(queue).refs == 1 && obj_header(stored).refs == 1 }
		api.release(queue); api.release(stored)
	}
}

fn session_read_worker(api SessionApi, object u64) u64 {
	pool := api.pool()
	mut queue := u64(0)
	for _ in 0 .. 128 {
		got := api.message(object, c'delegateQueue', 0, 0, 0)
		if queue == 0 { queue = got } else { assert got == queue }
		assert api.message(got, c'maxConcurrentOperationCount', 0, 0, 0) == 1
		assert api.text(api.message(object, c'sessionDescription', 0, 0, 0)) == 'concurrent session'
	}
	api.drain(pool)
	return queue
}
fn session_concurrent_cases(api SessionApi) {
	pool := api.pool(); object := api.message(api.cls, c'new', 0, 0, 0)
	api.message(object, c'setSessionDescription:', api.string(c'concurrent session'), 0, 0)
	assert read64(object + 80) == 0
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn session_read_worker(api, object) }
	mut queue := u64(0)
	for worker in workers { got := worker.wait(); if queue == 0 { queue = got } else { assert got == queue } }
	unsafe { workers.free() }
	assert queue != 0 && read64(object + 80) == queue
	api.drain(pool)
	if !api.native { assert obj_header(queue).refs == 1 }
	api.release(object)
}
fn session_write_worker(api SessionApi, object u64, left u64, right u64, offset int) {
	pool := api.pool()
	for index in 0 .. 128 {
		api.message(object, c'setSessionDescription:', if (index + offset) & 1 == 0 { left } else { right }, 0, 0)
		got := api.text(api.message(object, c'sessionDescription', 0, 0, 0))
		assert got in ['left session', 'right session']!
	}
	api.drain(pool)
}

fn test_url_session_native() {
	$if macos {
		api := SessionApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSURLSession')), strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString')), queues: u64(C.objc_getClass(c'NSOperationQueue'))}
		assert C.class_getInstanceSize(unsafe { voidptr(api.cls) }) == 160
		assert C.class_getSuperclass(unsafe { voidptr(api.cls) }) == C.objc_getClass(c'NSObject')
		session_base_cases(api); session_concurrent_cases(api)
		println('IOS-URL-SESSION-NATIVE: base allocation/init identity, nil configuration/delegate, copied description at104, lazy serial delegate queue at80, retained-self copies and eight concurrent readers')
	}
}

fn test_url_session_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := session_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSURLSession')! == api.cls
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSURLSession')! == read64(api.cls)
		assert objc_class_size(api.cls) == 160 && objc_class_parent(api.cls) == ios_runtime.names['NSObject']
		for name, types in {'init': '@16@0:8', 'copy': '@16@0:8', 'delegate': '@16@0:8', 'delegateQueue': '@16@0:8', 'configuration': '@16@0:8', 'sessionDescription': '@16@0:8', 'setSessionDescription:': 'v24@0:8@16', 'copyWithZone:': '@24@0:8^{_NSZone=}16'} {
			method := objc_instance_method(api.cls, u64(name.str))
			assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
		assert ctext(u64(objc_method_types(objc_instance_method(read64(api.cls), u64(c'new'))))) == '@16@0:8'
		for index, name in ['_delegateQueue_ivar', '_sessionDescription_ivar', '_delegate_ivar', '_local_immutable_configuration_ivar', '_workQueue']! {
			ivar := objc_find_ivar(api.cls, unsafe { &char(name.str) })
			assert ivar != 0 && objc_ivar_offset(ivar) == [i64(80), 104, 96, 112, 120]![index]
			assert ctext(u64(objc_ivar_types(ivar))) == ['@"NSOperationQueue"', '@"NSString"', '@"<NSURLSessionDelegate>"', '@"NSURLSessionConfiguration"', '@"NSObject<OS_dispatch_queue>"']![index]
		}
		session_base_cases(api); session_concurrent_cases(api)
		assert ios_runtime.live == 0
		reentry_pool := api.pool(); session_initializer_owner = api.message(api.cls, c'new', 0, 0, 0)
		api.message(session_initializer_owner, c'setSessionDescription:', api.string(c'initializer reentry'), 0, 0)
		session_initializer_calls = 0
		previous := objc_method_implementation(api.queues, u64(c'init'))
		objc_replace_method(api.queues, u64(c'init'), u64(unsafe { voidptr(session_queue_initializer) }), c'@16@0:8')
		assert api.message(session_initializer_owner, c'delegateQueue', 0, 0, 0) != 0 && session_initializer_calls == 1
		assert previous != 0 && objc_replace_method(api.queues, u64(c'init'), previous, c'@16@0:8') == u64(unsafe { voidptr(session_queue_initializer) })
		api.release(session_initializer_owner); session_initializer_owner = 0; api.drain(reentry_pool)
		assert ios_runtime.live == 0
		pool := api.pool(); object := api.message(api.cls, c'new', 0, 0, 0)
		for selector in [c'sharedSession', c'sessionWithConfiguration:', c'sessionWithConfiguration:delegate:delegateQueue:']! {
			assert !objc_responds(api.cls, selector) && objc_instance_method(read64(api.cls), u64(selector)) == 0
		}
		for selector in [c'mutableCopy', c'mutableCopyWithZone:', c'finishTasksAndInvalidate', c'invalidateAndCancel', c'flushWithCompletionHandler:', c'resetWithCompletionHandler:', c'getTasksWithCompletionHandler:', c'getAllTasksWithCompletionHandler:', c'dataTaskWithRequest:', c'dataTaskWithURL:completionHandler:', c'initWithCoder:', c'encodeWithCoder:']! {
			assert !objc_responds(object, selector) && objc_instance_method(api.cls, u64(selector)) == 0
		}
		assert objc_add_method(api.cls, u64(c'getAllTasksWithCompletionHandler:'), u64(unsafe { voidptr(session_app_tasks) }), c'@24@0:8@16')
		assert objc_responds(object, c'getAllTasksWithCompletionHandler:')
		assert objc_instance_method(api.cls, u64(c'getAllTasksWithCompletionHandler:')) != 0
		app_api := SessionApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		assert app_api.message(object, c'getAllTasksWithCompletionHandler:', 0, 0, 0) == object
		left := api.retain(api.string(c'left session')); right := api.retain(api.string(c'right session'))
		mut writers := []thread{}
		for index in 0 .. 8 { writers << spawn session_write_worker(api, object, left, right, index) }
		writers.wait(); unsafe { writers.free() }
		api.release(left); api.release(right); api.release(object); api.drain(pool)
		assert ios_runtime.live == 0
		mut guarded := [22]u64{}
		guarded[0] = 0x1122334455667788; guarded[21] = 0x8877665544332211
		caller := objc_construct_instance(api.cls, u64(unsafe { &guarded[1] }))
		inner := api.pool(); assert api.message(caller, c'init', 0, 0, 0) == caller
		api.message(caller, c'setSessionDescription:', api.string(c'caller storage'), 0, 0)
		mut queue_weak := u64(0); mut description_weak := u64(0)
		objc_store_weak(unsafe { &queue_weak }, api.message(caller, c'delegateQueue', 0, 0, 0))
		objc_store_weak(unsafe { &description_weak }, api.message(caller, c'sessionDescription', 0, 0, 0))
		api.drain(inner); assert queue_weak != 0 && description_weak != 0
		assert objc_destruct_instance(caller) == caller
		assert queue_weak == 0 && description_weak == 0
		assert read64(caller + 80) == 0 && read64(caller + 104) == 0
		objc_destroy_weak(unsafe { &queue_weak }); objc_destroy_weak(unsafe { &description_weak })
		assert guarded[0] == 0x1122334455667788 && guarded[21] == 0x8877665544332211
		for _ in 0 .. 64 {
			inner2 := api.pool(); changed := api.message(api.cls, c'new', 0, 0, 0)
			api.message(changed, c'delegateQueue', 0, 0, 0); api.message(changed, c'setSessionDescription:', api.string(c'isa changed'), 0, 0)
			assert objc_set_class(changed, ios_runtime.names['NSObject']) == api.cls
			api.release(changed); api.drain(inner2)
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		// Leave the final base session and its property getter temporaries in the
		// root pool so runtime shutdown must retire all three owners itself.
		pooled := objc_autorelease(api.message(api.cls, c'new', 0, 0, 0))
		label := owned_string('shutdown session')
		api.message(pooled, c'setSessionDescription:', label, 0, 0); objc_release(label)
		mut pooled_weak := u64(0); mut queue_final_weak := u64(0); mut description_final_weak := u64(0)
		objc_store_weak(unsafe { &pooled_weak }, pooled)
		objc_store_weak(unsafe { &queue_final_weak }, api.message(pooled, c'delegateQueue', 0, 0, 0))
		objc_store_weak(unsafe { &description_final_weak }, api.message(pooled, c'sessionDescription', 0, 0, 0))
		objc_stop()
		assert pooled_weak == 0 && queue_final_weak == 0 && description_final_weak == 0
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-URL-SESSION: typed base ABI and metadata, immutable description snapshots, queue ownership, concurrent getters/setters, guarded caller storage,64 isa replacements and two drained runtimes')
}

fn test_url_session_rejections() {
	objc_start(); api := session_runtime_api()
	for mode in ['shared', 'configured', 'configured-delegate', 'task', 'upload', 'download', 'socket', 'cancel', 'finish', 'flush', 'reset', 'tasks', 'coding', 'mutable', 'description', 'bad-copy', 'subclass', 'caller-subclass', 'spoof']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := api.message(api.cls, c'new', 0, 0, 0)
			match mode {
				'shared' { api.message(api.cls, c'sharedSession', 0, 0, 0) }
				'configured' { api.message(api.cls, c'sessionWithConfiguration:', 0, 0, 0) }
				'configured-delegate' { api.message(api.cls, c'sessionWithConfiguration:delegate:delegateQueue:', 0, 0, 0) }
				'task' { api.message(object, c'dataTaskWithRequest:', 0, 0, 0) }
				'upload' { api.message(object, c'uploadTaskWithRequest:fromData:', 0, 0, 0) }
				'download' { api.message(object, c'downloadTaskWithURL:', 0, 0, 0) }
				'socket' { api.message(object, c'webSocketTaskWithURL:', 0, 0, 0) }
				'cancel' { api.message(object, c'invalidateAndCancel', 0, 0, 0) }
				'finish' { api.message(object, c'finishTasksAndInvalidate', 0, 0, 0) }
				'flush' { api.message(object, c'flushWithCompletionHandler:', 0, 0, 0) }
				'reset' { api.message(object, c'resetWithCompletionHandler:', 0, 0, 0) }
				'tasks' { api.message(object, c'getAllTasksWithCompletionHandler:', 0, 0, 0) }
				'coding' { api.message(object, c'initWithCoder:', 0, 0, 0) }
				'mutable' { api.message(object, c'mutableCopy', 0, 0, 0) }
				'description' { api.message(object, c'setSessionDescription:', objc_new(ios_runtime.names['NSObject']), 0, 0) }
				'bad-copy' {
					bad := objc_allocate_class(ios_runtime.names['NSString'], c'VinixSessionBadCopyString', 0)
					assert objc_add_method(bad, u64(c'copy'), u64(unsafe { voidptr(session_probe_bad_copy) }), c'@16@0:8'); objc_register_class(bad)
					api.message(object, c'setSessionDescription:', objc_new(bad), 0, 0)
				}
				'subclass', 'caller-subclass' {
					sub := objc_allocate_class(api.cls, c'VinixUnsupportedSessionSubclass', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) }
					else { mut storage := [20]u64{}; objc_construct_instance(sub, u64(unsafe { &storage[0] })) }
				}
				else {
					spoof_class := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSessionSpoof', 0)
					assert objc_add_ivar(spoof_class, c'bytes', 152, 3, c'[152C]'); objc_register_class(spoof_class)
					spoof := objc_new(spoof_class); objc_set_class(spoof, api.cls)
					api.message(spoof, c'delegateQueue', 0, 0, 0)
				}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'description' { 'URL session description must be a string' }
			'bad-copy' { 'URL session description copy must be a string' }
			'subclass', 'caller-subclass' { 'custom URL session subclass construction is not implemented' }
			'spoof' { 'URL session requires live base session storage' }
			else { 'URL session shared/configured sessions' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
		selector := match mode {
			'shared' { '+[NSURLSession sharedSession]' }
			'configured' { '+[NSURLSession sessionWithConfiguration:]' }
			'configured-delegate' { '+[NSURLSession sessionWithConfiguration:delegate:delegateQueue:]' }
			'task' { '-[NSURLSession dataTaskWithRequest:]' }
			'upload' { '-[NSURLSession uploadTaskWithRequest:fromData:]' }
			'download' { '-[NSURLSession downloadTaskWithURL:]' }
			'socket' { '-[NSURLSession webSocketTaskWithURL:]' }
			'cancel' { '-[NSURLSession invalidateAndCancel]' }
			'finish' { '-[NSURLSession finishTasksAndInvalidate]' }
			'flush' { '-[NSURLSession flushWithCompletionHandler:]' }
			'reset' { '-[NSURLSession resetWithCompletionHandler:]' }
			'tasks' { '-[NSURLSession getAllTasksWithCompletionHandler:]' }
			'coding' { '-[NSURLSession initWithCoder:]' }
			'mutable' { '-[NSURLSession mutableCopy]' }
			else { '' }
		}
		if selector != '' { assert output.contains(': ' + selector + '\n'), output }
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-URL-SESSION-REJECT: nineteen configured/shared/task/lifecycle/coding/mutability/type/copy/subclass/spoof cases fail explicitly')
}
