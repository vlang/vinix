// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.objc_getMetaClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
type ControllerSend = fn (u64, u64, u64) u64
struct ControllerApi { native bool send u64 cls u64 }
fn (api ControllerApi) msg(object u64, selector &char, arg u64) u64 {
	mut sel := u64(selector)
	$if macos { if api.native { sel = u64(C.sel_registerName(selector)) } }
	return unsafe { ControllerSend(voidptr(api.send))(object, sel, arg) }
}
fn controller_api(cls u64) ControllerApi {
	return ControllerApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: cls}
}
fn controller_discovery(api ControllerApi) {
	for _ in 0 .. 3 {
		array := api.msg(api.cls, c'controllers', 0)
		assert array != 0 && api.msg(array, c'count', 0) == 0
		assert api.msg(api.cls, c'current', 0) == 0
		assert api.msg(array, c'retain', 0) == array
		api.msg(array, c'release', 0)
	}
	assert u8(api.msg(api.cls, c'shouldMonitorBackgroundEvents', 0)) == 0
	for value in [u64(1), 0, 1, 0]! {
		api.msg(api.cls, c'setShouldMonitorBackgroundEvents:', value)
		assert u8(api.msg(api.cls, c'shouldMonitorBackgroundEvents', 0)) == value
	}
}
fn controller_constants(api ControllerApi) {
	for name in ['GCControllerDidBecomeCurrentNotification', 'GCControllerDidConnectNotification', 'GCControllerDidDisconnectNotification']! {
		mut address := u64(0)
		$if macos { if api.native { address = u64(C.dlsym(unsafe { voidptr(-2) }, name.str)) } }
		if !api.native {
			address = runtime_symbol('/System/Library/Frameworks/GameController.framework/GameController', '_' + name) or { panic(err) }
			assert address == runtime_symbol('/System/Library/Frameworks/GameController.framework/GameController', '_' + name) or { panic(err) }
		}
		assert address != 0
		object := read64(address)
		assert object != 0 && ctext(api.msg(object, c'UTF8String', 0)) == name
		assert api.msg(object, c'retain', 0) == object
		api.msg(object, c'release', 0)
		assert read64(address) == object && ctext(api.msg(object, c'UTF8String', 0)) == name
	}
}
fn controller_worker(api ControllerApi, expected u64, cell u64) {
	pool := objc_pool_push()
	for _ in 0 .. 128 {
		assert api.msg(api.cls, c'controllers', 0) == expected
		assert api.msg(expected, c'count', 0) == 0 && api.msg(api.cls, c'current', 0) == 0
		assert runtime_symbol('/System/Library/Frameworks/GameController.framework/GameController', '_GCControllerDidConnectNotification') or { panic(err) } == cell
		api.msg(api.cls, c'setShouldMonitorBackgroundEvents:', 1)
		assert api.msg(api.cls, c'shouldMonitorBackgroundEvents', 0) == 1
	}
	objc_pool_pop(pool)
}
fn controller_override(object u64, selector &char) u64 { return object }
fn test_game_controller_native() {
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/GameController.framework/GameController', 2) != unsafe { nil }
		cls := u64(C.objc_getClass(c'GCController'))
		assert cls != 0 && C.class_getInstanceSize(unsafe { voidptr(cls) }) == 232
		assert C.class_getSuperclass(unsafe { voidptr(cls) }) == C.objc_getClass(c'NSObject')
		api := ControllerApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: cls}
		pool := api.msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		controller_discovery(api); controller_constants(api)
		api.msg(pool, c'drain', 0)
		println('IOS-GAME-CONTROLLER-NATIVE: 232-byte NSObject class, empty discovery, nil current, background flag and three notification values')
	}
}
fn test_game_controller_runtime() {
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push()
		cls := ios_runtime.names['GCController']; api := controller_api(cls)
		library := '/System/Library/Frameworks/GameController.framework/GameController'
		assert runtime_symbol(library, '_OBJC_CLASS_$_GCController')! == cls
		assert runtime_symbol(library, '_OBJC_METACLASS_$_GCController')! == read64(cls)
		assert objc_class_size(cls) == 232 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		for symbol in ['_OBJC_CLASS_$_GCController', '_OBJC_METACLASS_$_GCController', '_GCControllerDidBecomeCurrentNotification', '_GCControllerDidConnectNotification', '_GCControllerDidDisconnectNotification']! {
			for wrong in ['Foundation', 'UIKit']! {
				if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, symbol) { assert false }
			}
		}
		if _ := game_controller_symbol('_GCControllerUnknownNotification') { assert false }
		for selector, types in {'controllers': '@16@0:8', 'current': '@16@0:8', 'shouldMonitorBackgroundEvents': 'B16@0:8', 'setShouldMonitorBackgroundEvents:': 'v20@0:8B16'} {
			method := objc_class_method(cls, u64(selector.str))
			assert method != 0 && ctext(u64(objc_method_types(method))) == types
			assert objc_responds(cls, selector.str) && objc_instance_method(cls, u64(selector.str)) == 0
			signature := api.msg(cls, c'methodSignatureForSelector:', u64(selector.str))
			assert signature != 0
			setter := selector == 'setShouldMonitorBackgroundEvents:'
			assert api.msg(signature, c'numberOfArguments', 0) == if setter { u64(3) } else { u64(2) }
			assert ctext(api.msg(signature, c'methodReturnType', 0)) == types[..1]
			assert api.msg(signature, c'methodReturnLength', 0) == if setter { u64(0) } else if selector == 'shouldMonitorBackgroundEvents' { u64(1) } else { u64(8) }
			if setter { assert ctext(api.msg(signature, c'getArgumentTypeAtIndex:', 2)) == 'B' }
		}
		for selector in [c'alloc', c'new', c'copy', c'init', c'supportsSecureCoding', c'controllerWithExtendedGamepad', c'controllerWithMicroGamepad', c'snapshotWithProfile:', c'startWirelessControllerDiscoveryWithCompletionHandler:', c'stopWirelessControllerDiscovery']! {
			assert !objc_responds(cls, selector) && objc_class_method(cls, u64(selector)) == 0
		}
		controller_discovery(api); controller_constants(api)
		array := api.msg(cls, c'controllers', 0)
		cell := runtime_symbol(library, '_GCControllerDidConnectNotification')!
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn controller_worker(api, array, cell) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline && ios_runtime.block_refs.len == 0
		sub := objc_allocate_class(cls, c'VinixDiscoveryController', 0); objc_register_class(sub)
		assert api.msg(sub, c'controllers', 0) == array && api.msg(sub, c'shouldMonitorBackgroundEvents', 0) == 1
		api.msg(sub, c'setShouldMonitorBackgroundEvents:', 0)
		assert api.msg(cls, c'shouldMonitorBackgroundEvents', 0) == 0
		saved := objc_method_imp(objc_class_method(cls, u64(c'current')))
		assert objc_add_method(read64(sub), u64(c'current'), u64(unsafe { voidptr(controller_override) }), c'@16@0:8')
		assert api.msg(sub, c'current', 0) == sub && objc_responds(sub, c'current')
		assert unsafe { ControllerSend(voidptr(saved))(sub, u64(c'current'), 0) } == 0
		objc_pool_pop(pool); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		assert ios_runtime.controller_constants_arena == 0
	}
	println('IOS-GAME-CONTROLLER: scoped imports, typed class methods, immutable empty discovery, notification constants, four concurrent readers, inherited state, overrides, saved IMP and two drained runtimes')
}
fn test_game_controller_rejections() {
	objc_start(); api := controller_api(ios_runtime.names['GCController'])
	for mode in ['alloc', 'new', 'allocate', 'caller', 'subclass', 'copy', 'supportsSecureCoding', 'controllerWithExtendedGamepad', 'startWirelessControllerDiscoveryWithCompletionHandler:', 'stopWirelessControllerDiscovery']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'allocate' { objc_allocate(api.cls) }
				'caller' { mut storage := [29]u64{}; objc_construct_instance(api.cls, u64(unsafe { &storage[0] })) }
				'subclass' { sub := objc_allocate_class(api.cls, c'VinixPhysicalController', 0); objc_register_class(sub); objc_allocate(sub) }
				else { api.msg(api.cls, mode.str, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := if mode in ['controllerWithExtendedGamepad', 'startWirelessControllerDiscoveryWithCompletionHandler:', 'stopWirelessControllerDiscovery']! { 'unimplemented Objective-C method' } else { 'GCController construction requires an implemented physical input profile' }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	objc_stop(); assert ios_runtime.live == 0
	println('IOS-GAME-CONTROLLER-REJECT: ten construction, caller storage, subclass, copying, coding, factory and wireless discovery cases fail explicitly')
}

fn test_gamepad_native_hierarchy() {
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/GameController.framework/GameController', 2) != unsafe { nil }
		for i, name in ['GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad']! {
			cls := C.objc_getClass(name.str)
			assert cls != unsafe { nil } && C.class_getInstanceSize(cls) == [usize(680), 872, 896]![i]
			parent := ['NSObject', 'GCPhysicalInputProfile', 'GCExtendedGamepad']![i]
			assert C.class_getSuperclass(cls) == C.objc_getClass(parent.str)
			assert C.dlsym(unsafe { voidptr(-2) }, ('OBJC_CLASS_$_' + name).str) == cls
			assert C.dlsym(unsafe { voidptr(-2) }, ('OBJC_METACLASS_$_' + name).str) == C.objc_getMetaClass(name.str)
		}
		println('IOS-GAMEPAD-NATIVE: physical, extended and DualShock class imports, superclass links and 680/872/896-byte layouts')
	}
}

fn test_gamepad_runtime_hierarchy() {
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push()
		library := '/System/Library/Frameworks/GameController.framework/GameController'
		for i, name in ['GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad']! {
			cls := ios_runtime.names[name]; api := controller_api(cls)
			parent := ios_runtime.names[['NSObject', 'GCPhysicalInputProfile', 'GCExtendedGamepad']![i]]
			assert gamepad_family(cls) && !game_controller_family(cls)
			assert objc_class_size(cls) == [u32(680), 872, 896]![i]
			assert objc_class_parent(cls) == parent && objc_class_parent(read64(cls)) == read64(parent)
			assert ctext(u64(objc_class_name(cls))) == name
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol(library, symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
				for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib']! {
					if _ := runtime_symbol(wrong, symbol) { assert false }
				}
			}
			assert api.msg(cls, c'class', 0) == cls
			assert api.msg(cls, c'respondsToSelector:', u64(c'class')) == 1
			signature := api.msg(cls, c'methodSignatureForSelector:', u64(c'class'))
			assert signature != 0 && ctext(api.msg(signature, c'methodReturnType', 0)) == '#'
			for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'buttonA', c'touchpadButton', c'physicalInputProfile', c'controllers']! {
				assert !objc_responds(cls, selector)
				assert objc_class_method(cls, u64(selector)) == 0 && objc_instance_method(cls, u64(selector)) == 0
				assert api.msg(cls, c'methodSignatureForSelector:', u64(selector)) == 0
				assert api.msg(cls, c'instanceMethodSignatureForSelector:', u64(selector)) == 0
			}
			sub := objc_allocate_class(cls, ('Vinix' + name).str, 0); objc_register_class(sub)
			assert gamepad_family(sub) && objc_class_size(sub) == objc_class_size(cls)
			assert !objc_responds(sub, c'copy')
			assert objc_add_method(read64(sub), u64(c'copy'), u64(unsafe { voidptr(controller_override) }), c'@16@0:8')
			assert objc_responds(sub, c'copy') && api.msg(sub, c'copy', 0) == sub
		}
		if _ := game_controller_symbol('_OBJC_CLASS_$_GCUnknownGamepad') { assert false }
		if _ := game_controller_symbol('_OBJC_METACLASS_$_GCUnknownGamepad') { assert false }
		objc_pool_pop(pool); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-GAMEPAD: three scoped class/metaclass imports, inherited metadata, honest method lookup, subclass overrides and two drained runtimes')
}

fn test_gamepad_rejections() {
	objc_start()
	for name in ['GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad']! {
		api := controller_api(ios_runtime.names[name])
		for mode in ['alloc', 'new', 'allocate', 'caller', 'subclass', 'copy', 'initWithCoder:', 'supportsSecureCoding', 'touchpadButton']! {
			mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
			pid := C.fork(); assert pid >= 0
			if pid == 0 {
				C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
				match mode {
					'allocate' { objc_allocate(api.cls) }
					'caller' { mut storage := [112]u64{}; objc_construct_instance(api.cls, u64(unsafe { &storage[0] })) }
					'subclass' { sub := objc_allocate_class(api.cls, c'VinixUnimplementedGamepad', 0); objc_register_class(sub); objc_allocate(sub) }
					else { api.msg(api.cls, mode.str, 0) }
				}
				C._exit(0)
			}
			C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
			for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
			C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
			output := unsafe { tos(&bytes[0], length) }
			reason := if mode == 'touchpadButton' { 'unimplemented Objective-C method' } else { 'gamepad construction requires an implemented physical input profile' }
			assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
		}
	}
	objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GAMEPAD-REJECT: 27 construction, caller storage, subclass, copying, coding and touchpad cases fail explicitly')
}
