// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework GameController
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
type KeyboardSend = fn (u64, u64, u64) u64

fn keyboard_message(object u64, selector &char, arg u64) u64 {
	return unsafe { KeyboardSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), arg) }
}

fn test_keyboard_native_discovery() {
	$if macos {
		cls := C.objc_getClass(c'GCKeyboard')
		assert cls != unsafe { nil }
		assert C.class_getInstanceSize(cls) == 32
		assert C.class_getSuperclass(cls) == C.objc_getClass(c'NSObject')
		selector := C.sel_registerName(c'coalescedKeyboard')
		method := C.class_getClassMethod(cls, selector)
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8'
		connected := unsafe { KeyboardSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(u64(cls), u64(selector), 0) }
		// The host may have a physical keyboard; discovery is hardware-dependent.
		println('IOS-KEYBOARD-NATIVE: size32 NSObject parent; coalescedKeyboard object ABI; connected=' + (connected != 0).str())
	}
}

fn keyboard_discovery_loop(cls u64) {
	for _ in 0 .. 1000 { assert keyboard_message(cls, c'coalescedKeyboard', 0) == 0 }
}

fn test_keyboard_runtime_discovery() {
	for _ in 0 .. 2 {
		objc_start()
		cls := ios_runtime.names['GCKeyboard']
		library := '/System/Library/Frameworks/GameController.framework/GameController'
		assert runtime_symbol(library, '_OBJC_CLASS_$_GCKeyboard')! == cls
		assert runtime_symbol(library, '_OBJC_METACLASS_$_GCKeyboard')! == read64(cls)
		assert objc_class_size(cls) == 32 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert objc_responds(cls, c'coalescedKeyboard')
		method := objc_class_method(cls, u64(c'coalescedKeyboard'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
		assert !objc_responds(cls, c'keyboardInput')
		assert !objc_responds(ios_runtime.names['NSObject'], c'coalescedKeyboard')
		assert framework_symbol(library, '_OBJC_CLASS_$_GCKeyboardInput') == none
		assert framework_symbol(library, '_OBJC_CLASS_$_GCMouse') == none
		assert framework_symbol(library, '_GCKeyboardDidConnectNotification') != none
		assert framework_symbol(library, '_GCKeyboardDidDisconnectNotification') != none
		// Notification strings are runtime-owned; discovery itself owns nothing.
		baseline := ios_runtime.live
		keyboard_discovery_loop(cls)
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn keyboard_discovery_loop(cls) }
		workers.wait()
		assert ios_runtime.live == baseline && ios_runtime.block_refs.len == 0
		subclass := objc_allocate_class(cls, c'VinixKeyboardDiscoveryFixture', 0)
		objc_register_class(subclass)
		assert objc_responds(subclass, c'coalescedKeyboard')
		assert keyboard_message(subclass, c'coalescedKeyboard', 0) == 0
		// Raw Objective-C storage keeps the measured opaque layout. It does not
		// initialize a keyboard profile, and private native ivars are not exposed.
		mut bytes := [32]u8{}
		object := objc_construct_instance(cls, u64(unsafe { &bytes[0] }))
		assert object != 0 && !objc_responds(object, c'coalescedKeyboard')
		assert objc_destruct_instance(object) == object && read64(object) == cls
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-KEYBOARD: class/meta imports, measured metadata, inherited and concurrent nil discovery, caller storage and two zero-live-object shutdown cycles')
}

fn test_keyboard_reject_profiles() {
	objc_start()
	cls := ios_runtime.names['GCKeyboard']
	for mode in ['new-message', 'new-export', 'init', 'copy', 'profile', 'queue']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			if mode == 'new-export' { objc_new(cls) }
			if mode == 'new-message' { keyboard_message(cls, c'new', 0) }
			object := objc_allocate(cls)
			selector := match mode { 'copy' { c'copy' } 'profile' { c'keyboardInput' } 'queue' { c'setHandlerQueue:' } else { c'init' } }
			keyboard_message(object, selector, 0)
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
		assert output.contains('iOS: GCKeyboard construction requires an implemented physical input profile'), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	assert ios_runtime.live == 0
	objc_stop()
	println('IOS-KEYBOARD-REJECT: six construction/profile/queue operations reject explicitly; physical key delivery remains unsupported')
}
