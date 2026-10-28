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
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
type TaskMessage = fn (u64, u64, u64) u64
type TaskPriorityGet = fn (u64, u64) f32
type TaskPrioritySet = fn (u64, u64, f32)
struct TaskApi { native bool send u64 cls u64 strings u64 mutable_strings u64 }
fn (api TaskApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api TaskApi) message(object u64, name &char, arg u64) u64 {
	return unsafe { TaskMessage(voidptr(api.send))(object, api.selector(name), arg) }
}
fn (api TaskApi) priority(object u64) f32 {
	return unsafe { TaskPriorityGet(voidptr(api.send))(object, api.selector(c'priority')) }
}
fn (api TaskApi) set_priority(object u64, value f32) {
	unsafe { TaskPrioritySet(voidptr(api.send))(object, api.selector(c'setPriority:'), value) }
}
fn (api TaskApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value)) }
fn (api TaskApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0)) }
fn (api TaskApi) release(object u64) { api.message(object, c'release', 0) }
fn (api TaskApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	return objc_pool_push()
}
fn (api TaskApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn task_string_copy(object u64, selector &char) u64 { return owned_string(string_text(object)) }
fn task_bad_copy(object u64, selector &char) u64 { return objc_new(ios_runtime.names['NSObject']) }
fn task_cancel_override(object u64, selector &char) u64 { return object }
fn task_runtime_api(cls u64) TaskApi {
	return TaskApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: cls,
		strings: ios_runtime.names['NSString'], mutable_strings: ios_runtime.names['VinixTaskMutableString']}
}
fn (api TaskApi) mutable_string() u64 {
	$if macos { if api.native { return api.message(api.message(api.mutable_strings, c'stringWithUTF8String:', u64(c'original task')), c'retain', 0) } }
	object := owned_string('original task'); objc_set_class(object, api.mutable_strings); return object
}
fn (api TaskApi) change_string(object u64) {
	$if macos { if api.native { api.message(object, c'setString:', api.string(c'changed input')); return } }
	mut header := obj_header(object); C.free(header.text)
	header.text = unsafe { &char(C.malloc(14)) }; assert header.text != unsafe { nil }
	unsafe { C.memcpy(header.text, c'changed input', 14) }; header.text_length = 13
}
fn task_base_cases(api TaskApi) {
	for construction in [c'alloc', c'new']! {
		pool := api.pool(); object := api.message(api.cls, construction, 0)
		assert object != 0 && api.message(object, c'class', 0) == api.cls
		for selector in [c'taskIdentifier', c'state', c'originalRequest', c'currentRequest', c'response', c'error', c'taskDescription', c'countOfBytesSent', c'countOfBytesReceived', c'countOfBytesExpectedToSend', c'countOfBytesExpectedToReceive']! {
			assert api.message(object, selector, 0) == 0
		}
		assert api.priority(object) == 0
		mut expected := f32(0)
		for value in [f32(-1), 0.25, 2, bits.f32_from_bits(0x7fc00000), bits.f32_from_bits(0x7f800000), bits.f32_from_bits(0xff800000), 1, 0]! {
			api.set_priority(object, value)
			if bits.f32_bits(value) & 0x7fffffff > 0x7f800000 || (value >= 0 && value <= 1) { expected = value }
			assert bits.f32_bits(api.priority(object)) == bits.f32_bits(expected)
			assert bits.f32_bits(unsafe { *(&f32(object + 116)) }) == bits.f32_bits(expected)
		}
		for index, getter in ['countOfBytesClientExpectsToSend', 'countOfBytesClientExpectsToReceive']! {
			setter := 'set' + getter[..1].to_upper() + getter[1..] + ':'
			assert api.message(object, getter.str, 0) == 0
			for value in [i64(-1), 42, -2, -0x7fffffffffffffff, 0x7fffffffffffffff]! {
				api.message(object, setter.str, u64(value))
				assert i64(api.message(object, getter.str, 0)) == value && i64(read64(object + 168 + u64(index * 8))) == value
			}
		}
		source := api.mutable_string()
		api.message(object, c'setTaskDescription:', source)
		stored := api.message(object, c'taskDescription', 0)
		assert stored != source && read64(object + 128) == stored && api.text(stored) == 'original task'
		api.change_string(source); api.release(source)
		assert api.text(api.message(object, c'taskDescription', 0)) == 'original task'
		assert api.message(stored, c'retain', 0) == stored
		api.message(object, c'setTaskDescription:', 0)
		assert read64(object + 128) == 0 && api.message(object, c'taskDescription', 0) == 0
		api.message(object, c'setTaskDescription:', stored)
		api.message(object, c'setTaskDescription:', api.message(object, c'taskDescription', 0))
		for _ in 0 .. 2 { assert api.message(object, c'init', 0) == object }
		assert api.message(object, c'taskDescription', 0) == stored
		for selector in [c'copy', c'copyWithZone:']! {
			assert api.message(object, selector, 0) == object
			if !api.native { assert obj_header(object).refs == 2 }
			api.release(object)
		}
		if !api.native {
			for zone in [false, true]! { assert objc_copy_value(object, zone) == object && obj_header(object).refs == 2; api.release(object) }
			get := objc_method_implementation(api.cls, u64(c'priority'))
			set := objc_method_implementation(api.cls, u64(c'setPriority:'))
			unsafe { TaskPrioritySet(voidptr(set))(object, u64(c'setPriority:'), 0.75) }
			assert unsafe { TaskPriorityGet(voidptr(get))(object, u64(c'priority')) } == 0.75
		}
		api.drain(pool); api.release(object)
		assert api.text(stored) == 'original task'
		if !api.native { assert obj_header(stored).refs == 1 }
		api.release(stored)
	}
}
fn task_writer(api TaskApi, object u64, left u64, right u64, offset int) {
	pool := api.pool()
	for index in 0 .. 128 {
		api.message(object, c'setTaskDescription:', if (index + offset) & 1 == 0 { left } else { right })
		assert api.text(api.message(object, c'taskDescription', 0)) in ['left task', 'right task']!
		api.set_priority(object, 0.5); assert api.priority(object) == 0.5
	}
	api.drain(pool)
}
fn test_session_task_native() {
	$if macos {
		for index, name in ['NSURLSessionTask', 'NSURLSessionDownloadTask', 'NSURLSessionDataTask', 'NSURLSessionUploadTask']! {
			cls := u64(C.objc_getClass(name.str))
			// Newer host Foundation adds one private tail pointer. The measured
			// public fields and Vinix's 720-byte compatibility layout stay fixed.
			tail := C.class_getInstanceVariable(unsafe { voidptr(cls) }, c'_sourceApplicationBundleIdentifierForMobileAsset')
			assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == if tail == unsafe { nil } { usize(720) } else { usize(728) }
			if tail != unsafe { nil } {
				assert C.ivar_getOffset(tail) == 720 && ctext(u64(C.ivar_getTypeEncoding(tail))) == '@"NSString"'
			}
			for ivar_name, offset in {'_priorityAPIStorage': 116, '_taskIdentifier': 120, '_taskDescription': 128, '_originalRequest': 144, '_currentRequest': 152, '_response': 160, '_countOfBytesClientExpectsToSend': 168, '_countOfBytesClientExpectsToReceive': 176, '_countOfBytesReceived': 184, '_countOfBytesSent': 208, '_countOfBytesExpectedToSend': 216, '_countOfBytesExpectedToReceive': 224, '_state': 232, '_error': 240} {
				ivar := C.class_getInstanceVariable(unsafe { voidptr(cls) }, ivar_name.str)
				assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == offset
			}
			parent := ['NSObject', 'NSURLSessionTask', 'NSURLSessionTask', 'NSURLSessionDataTask']![index]
			assert C.class_getSuperclass(unsafe { voidptr(cls) }) == C.objc_getClass(parent.str)
			task_base_cases(TaskApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: cls, strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString'))})
		}
		println('IOS-SESSION-TASK-NATIVE: four classes with measured public offsets and optional private tail pointer, hierarchy, base init/copy identity, copied description, signed client counts and float priority including nonfinite inputs')
	}
}
fn test_session_task_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		mutable := objc_allocate_class(ios_runtime.names['NSString'], c'VinixTaskMutableString', 0)
		assert objc_add_method(mutable, u64(c'copy'), u64(unsafe { voidptr(task_string_copy) }), c'@16@0:8'); objc_register_class(mutable)
		for index, name in ['NSURLSessionTask', 'NSURLSessionDownloadTask', 'NSURLSessionDataTask', 'NSURLSessionUploadTask']! {
			cls := ios_runtime.names[name]; api := task_runtime_api(cls)
			library := '/System/Library/Frameworks/Foundation.framework/Foundation'
			assert runtime_symbol(library, '_OBJC_CLASS_$_' + name)! == cls
			assert runtime_symbol(library, '_OBJC_METACLASS_$_' + name)! == read64(cls)
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				if _ := runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', prefix + name) { assert false }
			}
			assert objc_class_size(cls) == 720 && objc_class_parent(cls) == ios_runtime.names[['NSObject', 'NSURLSessionTask', 'NSURLSessionTask', 'NSURLSessionDataTask']![index]]
			for method, types in {'init': '@16@0:8', 'copy': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16', 'taskDescription': '@16@0:8', 'setTaskDescription:': 'v24@0:8@16', 'taskIdentifier': 'Q16@0:8', 'state': 'q16@0:8', 'priority': 'f16@0:8', 'setPriority:': 'v20@0:8f16', 'countOfBytesClientExpectsToSend': 'q16@0:8', 'setCountOfBytesClientExpectsToReceive:': 'v24@0:8q16'} {
				got := objc_instance_method(cls, u64(method.str)); assert got != 0 && ctext(u64(objc_method_types(got))) == types
			}
			assert ctext(u64(objc_method_types(objc_instance_method(read64(cls), u64(c'new'))))) == '@16@0:8'
			for ivar_index, ivar_name in ['_priorityAPIStorage', '_taskIdentifier', '_taskDescription', '_originalRequest', '_currentRequest', '_response', '_countOfBytesClientExpectsToSend', '_countOfBytesClientExpectsToReceive', '_countOfBytesReceived', '_countOfBytesSent', '_countOfBytesExpectedToSend', '_countOfBytesExpectedToReceive', '_state', '_error']! {
				ivar := objc_find_ivar(cls, ivar_name.str)
				assert ivar != 0 && objc_ivar_offset(ivar) == [i64(116), 120, 128, 144, 152, 160, 168, 176, 184, 208, 216, 224, 232, 240]![ivar_index]
				assert ctext(u64(objc_ivar_types(ivar))) == ['f', 'Q', '@"NSString"', '@"NSURLRequest"', '@"NSURLRequest"', '@"NSURLResponse"', 'q', 'q', 'q', 'q', 'q', 'q', 'q', '@"NSError"']![ivar_index]
			}
			task_base_cases(api); assert ios_runtime.live == 0
			pool := api.pool(); object := api.message(cls, c'new', 0)
			for selector in [c'resume', c'suspend', c'cancel', c'cancelByProducingResumeData:', c'delegate', c'setDelegate:', c'progress', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'setCountOfBytesSent:', c'setCountOfBytesReceived:', c'setCountOfBytesExpectedToSend:', c'setCountOfBytesExpectedToReceive:']! {
				assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
			}
			left := api.string(c'left task'); right := api.string(c'right task')
			mut workers := []thread{}
			for worker in 0 .. 8 { workers << spawn task_writer(api, object, left, right, worker) }
			workers.wait(); unsafe { workers.free() }
			api.release(object); api.drain(pool); assert ios_runtime.live == 0
			mut guarded := [92]u64{}; guarded[0] = 0x1122334455667788; guarded[91] = 0x8877665544332211
			caller := objc_construct_instance(cls, u64(unsafe { &guarded[1] }))
			inner := api.pool(); api.message(caller, c'setTaskDescription:', api.string(c'caller task'))
			mut weak := u64(0); objc_store_weak(unsafe { &weak }, api.message(caller, c'taskDescription', 0)); api.drain(inner)
			assert weak != 0 && objc_destruct_instance(caller) == caller && weak == 0 && read64(caller + 128) == 0
			objc_destroy_weak(unsafe { &weak }); assert guarded[0] == 0x1122334455667788 && guarded[91] == 0x8877665544332211
			for _ in 0 .. 64 {
				inner2 := api.pool(); changed := api.message(cls, c'new', 0)
				api.message(changed, c'setTaskDescription:', api.string(c'isa changed'))
				assert objc_set_class(changed, ios_runtime.names['NSObject']) == cls
				api.release(changed); api.drain(inner2)
			}
			if index == 3 {
				assert objc_add_method(cls, u64(c'cancel'), u64(unsafe { voidptr(task_cancel_override) }), c'@16@0:8')
				overridden := api.message(cls, c'new', 0)
				assert objc_responds(overridden, c'cancel') && objc_instance_method(cls, u64(c'cancel')) != 0
				assert api.message(overridden, c'cancel', 0) == overridden; api.release(overridden)
			}
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		api := task_runtime_api(ios_runtime.names['NSURLSessionTask'])
		pooled := objc_autorelease(api.message(api.cls, c'new', 0)); description := owned_string('shutdown task')
		api.message(pooled, c'setTaskDescription:', description); objc_release(description)
		mut task_weak := u64(0); mut text_weak := u64(0)
		objc_store_weak(unsafe { &task_weak }, pooled); objc_store_weak(unsafe { &text_weak }, api.message(pooled, c'taskDescription', 0))
		objc_stop(); assert task_weak == 0 && text_weak == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-SESSION-TASK: four class imports and metadata, typed float ABI and saved IMPs, copied properties, eight concurrent writers/readers, guarded caller storage, isa changes, overrides and two drained runtimes')
}
fn test_session_task_rejections() {
	objc_start(); api := task_runtime_api(ios_runtime.names['NSURLSessionTask'])
	for mode in ['resume', 'suspend', 'cancel', 'cancelByProducingResumeData:', 'delegate', 'progress', 'mutableCopy', 'initWithCoder:', 'setCountOfBytesSent:', 'description', 'bad-copy', 'subclass', 'caller-subclass', 'spoof']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); object := api.message(api.cls, c'new', 0)
			match mode {
				'description' { api.message(object, c'setTaskDescription:', objc_new(ios_runtime.names['NSObject'])) }
				'bad-copy' {
					bad := objc_allocate_class(ios_runtime.names['NSString'], c'VinixTaskBadCopyString', 0)
					assert objc_add_method(bad, u64(c'copy'), u64(unsafe { voidptr(task_bad_copy) }), c'@16@0:8'); objc_register_class(bad)
					api.message(object, c'setTaskDescription:', objc_new(bad))
				}
				'subclass', 'caller-subclass' {
					sub := objc_allocate_class(api.cls, c'VinixTaskUnsupportedSubclass', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { mut storage := [90]u64{}; objc_construct_instance(sub, u64(unsafe { &storage[0] })) }
				}
				'spoof' {
					cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixTaskSpoof', 0)
					assert objc_add_ivar(cls, c'bytes', 712, 3, c'[712C]'); objc_register_class(cls)
					spoof := objc_new(cls); objc_set_class(spoof, api.cls); api.message(spoof, c'priority', 0)
				}
				else { api.message(object, mode.str, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'description' { 'task description must be a string' }
			'bad-copy' { 'task description copy must be a string' }
			'subclass', 'caller-subclass' { 'custom URL session task subclass construction is not implemented' }
			'spoof' { 'URL session task requires live base task storage' }
			else { 'URL session task transfers, cancellation, delegates, progress and coding are not implemented' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
		if url_session_task_unsupported(mode) { assert output.contains('-[NSURLSessionTask ${mode}]'), output }
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-SESSION-TASK-REJECT: fourteen unsupported operation, type, copy, subclass and spoof cases fail explicitly')
}
