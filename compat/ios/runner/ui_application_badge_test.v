// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr

type BadgeTestSend = fn (u64, u64, u64) u64
struct BadgeApi { native bool send u64 }

fn (api BadgeApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api BadgeApi) message(object u64, name &char, argument u64) u64 {
	return unsafe { BadgeTestSend(voidptr(api.send))(object, api.selector(name), argument) }
}
fn badge_cases(api BadgeApi, cls u64, application u64) {
	assert application != 0
	assert api.message(application, c'applicationIconBadgeNumber', 0) == 0
	assert api.message(0, c'applicationIconBadgeNumber', 0) == 0
	api.message(0, c'setApplicationIconBadgeNumber:', u64(i64(-1)))
	for index, name in [c'applicationIconBadgeNumber', c'setApplicationIconBadgeNumber:']! {
		selector := api.selector(name)
		assert api.message(application, c'respondsToSelector:', selector) == 1
		assert api.message(cls, c'respondsToSelector:', selector) == 0
		expected := ['q16@0:8', 'v24@0:8q16']![index]
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == expected
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == expected
			assert objc_instance_method(read64(cls), selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0
		signature := api.message(application, c'methodSignatureForSelector:', selector)
		assert signature != 0
		assert api.message(signature, c'numberOfArguments', 0) == u64(index + 2)
		assert api.message(signature, c'methodReturnLength', 0) == if index == 0 { u64(8) } else { u64(0) }
		assert ctext(api.message(signature, c'methodReturnType', 0)) == if index == 0 { 'q' } else { 'v' }
		if index == 1 { assert ctext(api.message(signature, c'getArgumentTypeAtIndex:', 2)) == 'q' }
		for value in [i64(0), -1]! {
			result := unsafe { BadgeTestSend(voidptr(imp))(application, selector, u64(value)) }
			if index == 0 { assert result == 0 }
			assert api.message(application, c'applicationIconBadgeNumber', 0) == 0
		}
	}
	assert api.message(application, c'respondsToSelector:', api.selector(c'vinixMissingBadgeSelector')) == 0
	for _ in 0 .. 256 {
		for value in [i64(0), -1]! {
			api.message(application, c'setApplicationIconBadgeNumber:', u64(value))
			assert api.message(application, c'applicationIconBadgeNumber', 0) == 0
		}
	}
}
fn test_application_badge_native() {
	$if macos {
		assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
		api := BadgeApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		pool := api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		cls := u64(C.objc_getClass(c'UIApplication'))
		mut application := api.message(cls, c'sharedApplication', 0)
		// No UIApplicationMain or notification authorization: this checks only
		// isolated default/clear behavior and metadata, not displaying a badge.
		if application == 0 { application = api.message(cls, c'alloc', 0) }
		badge_cases(api, cls, application)
		api.message(pool, c'drain', 0)
		println('IOS-APPLICATION-BADGE-NATIVE: isolated default/zero/minus-one clears, 64-bit instance metadata, signatures and direct IMP PASS; badge authorization/display unverified')
	}
}
fn test_application_badge_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		api := BadgeApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		cls := ios_runtime.names['UIApplication']
		application := objc_allocate(cls)
		badge_cases(api, cls, application)
		api.message(application, c'setIdleTimerDisabled:', 1)
		for value in [i64(0), -1]! {
			api.message(application, c'setApplicationIconBadgeNumber:', u64(value))
			assert api.message(application, c'isIdleTimerDisabled', 0) == 1
		}
		objc_release(application)
		subclass := objc_allocate_class(cls, c'VinixBadgeApplication', 0)
		objc_register_class(subclass)
		inherited := objc_allocate(subclass)
		badge_cases(api, subclass, inherited)
		objc_release(inherited)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-APPLICATION-BADGE: absent badge getter, zero/minus-one clears, metadata, signatures, direct IMP, subclass, idle timer independence and two drained runtimes PASS')
}
fn test_application_badge_rejections() {
	objc_start()
	api := BadgeApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	application := objc_allocate(ios_runtime.names['UIApplication'])
	for value in [i64(1), -2, -42, i64(2147483648), i64(4294967295), i64(9223372036854775807), i64(-9223372036854775807) - 1]! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			api.message(application, c'setApplicationIconBadgeNumber:', u64(value))
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains('application icon badge count ${value} requires a badge backend'), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(application); objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-APPLICATION-BADGE-REJECT: counts outside zero/minus-one fail explicitly across signed 64-bit boundaries without a badge backend PASS')
}
