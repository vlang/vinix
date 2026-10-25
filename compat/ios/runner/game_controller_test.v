// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

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
		for i, name in ['GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad', 'GCDualSenseGamepad']! {
			cls := C.objc_getClass(name.str)
			assert cls != unsafe { nil } && C.class_getInstanceSize(cls) == [usize(680), 872, 896, 896]![i]
			parent := ['NSObject', 'GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCExtendedGamepad']![i]
			assert C.class_getSuperclass(cls) == C.objc_getClass(parent.str)
			assert C.dlsym(unsafe { voidptr(-2) }, ('OBJC_CLASS_$_' + name).str) == cls
			assert C.dlsym(unsafe { voidptr(-2) }, ('OBJC_METACLASS_$_' + name).str) == C.objc_getMetaClass(name.str)
		}
		println('IOS-GAMEPAD-NATIVE: physical, extended, DualShock and DualSense class imports, superclass links and 680/872/896/896-byte layouts')
	}
}

fn test_gamepad_runtime_hierarchy() {
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push()
		library := '/System/Library/Frameworks/GameController.framework/GameController'
		for i, name in ['GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad', 'GCDualSenseGamepad']! {
			cls := ios_runtime.names[name]; api := controller_api(cls)
			parent := ios_runtime.names[['NSObject', 'GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCExtendedGamepad']![i]]
			assert gamepad_family(cls) && !game_controller_family(cls)
			assert objc_class_size(cls) == [u32(680), 872, 896, 896]![i]
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
			for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'buttonA', c'touchpadButton', c'touchpadPrimary', c'touchpadSecondary', c'initWithController:', c'initWithIdentifier:', c'physicalInputProfile', c'controllers']! {
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
	println('IOS-GAMEPAD: four scoped class/metaclass imports, inherited metadata, honest method lookup, subclass overrides and two drained runtimes')
}

fn test_gamepad_rejections() {
	objc_start()
	for name in ['GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad', 'GCDualSenseGamepad']! {
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
	println('IOS-GAMEPAD-REJECT: 36 construction, caller storage, subclass, copying, coding and touchpad cases fail explicitly')
}

type ColorInitSend = fn (u64, u64, f32, f32, f32) u64
type ColorGetSend = fn (u64, u64) f32
fn (api ControllerApi) sel(selector &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(selector)) } }
	return u64(selector)
}
fn (api ControllerApi) color_init(object u64, values [3]u32) u64 {
	return unsafe { ColorInitSend(voidptr(api.send))(object, api.sel(c'initWithRed:green:blue:'), bits.f32_from_bits(values[0]), bits.f32_from_bits(values[1]), bits.f32_from_bits(values[2])) }
}
fn (api ControllerApi) color_bits(object u64, selector &char) u32 {
	return bits.f32_bits(unsafe { ColorGetSend(voidptr(api.send))(object, api.sel(selector)) })
}
fn color_values(api ControllerApi) {
	object := api.msg(api.cls, c'new', 0)
	for selector in [c'red', c'green', c'blue']! { assert api.color_bits(object, selector) == 0 }
	api.msg(object, c'release', 0)
	for values in [[u32(0x3e800000), 0x3f000000, 0x3f400000]!,
		[u32(0xbf800000), 0x40000000, 0x3f800000]!,
		[u32(0x7fc01234), 0x7f800000, 0xff800000]!,
		[u32(0x80000000), 0, 0x3f800000]!,
		[u32(1), 0x7f7fffff, 0xff7fffff]!] {
		for copier in [c'copy', c'copyWithZone:']! {
			source := api.color_init(api.msg(api.cls, c'alloc', 0), values)
			for i, selector in [c'red', c'green', c'blue']! { assert api.color_bits(source, selector) == values[i] }
			duplicate := api.msg(source, copier, 0)
			assert duplicate != 0 && duplicate != source && api.msg(duplicate, c'class', 0) == api.cls
			api.msg(source, c'release', 0)
			for i, selector in [c'red', c'green', c'blue']! { assert api.color_bits(duplicate, selector) == values[i] }
			api.msg(duplicate, c'release', 0)
		}
	}
	color := api.color_init(api.msg(api.cls, c'alloc', 0), [u32(0x3e800000), 0x3f000000, 0x3f400000]!)
	assert ctext(api.msg(api.msg(color, c'description', 0), c'UTF8String', 0)) == '<GCColor r=0.250000 g=0.500000 b=0.750000>'
	api.msg(color, c'release', 0)
}
fn color_red_override(object u64, selector &char) f32 { return f32(0.875) }
fn color_init_unexpected(object u64, selector &char, red f32, green f32, blue f32) u64 {
	panic('GCColor copy must not call the subclass initializer')
}
fn test_gc_color_native() {
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/GameController.framework/GameController', 2) != unsafe { nil }
		cls := u64(C.objc_getClass(c'GCColor'))
		assert cls != 0 && C.class_getInstanceSize(unsafe { voidptr(cls) }) == 24
		assert C.class_getSuperclass(unsafe { voidptr(cls) }) == C.objc_getClass(c'NSObject')
		api := ControllerApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: cls}
		pool := api.msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		color_values(api); api.msg(pool, c'drain', 0)
		println('IOS-GC-COLOR-NATIVE: 24-byte NSObject, zero default, exact RGB float bits, independent copies and description')
	}
}
fn test_gc_color_runtime() {
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push()
		cls := ios_runtime.names['GCColor']; api := controller_api(cls)
		library := '/System/Library/Frameworks/GameController.framework/GameController'
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			assert runtime_symbol(library, prefix + 'GCColor')! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['Foundation', 'UIKit']! {
				if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, prefix + 'GCColor') { assert false }
			}
		}
		assert objc_class_size(cls) == 24 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		for i, name in ['_red', '_green', '_blue']! {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0 && objc_ivar_offset(ivar) == 8 + 4 * i
			assert ctext(u64(objc_ivar_types(ivar))) == 'f' && ctext(u64(objc_ivar_name(ivar))) == name
		}
		for selector, types in {'initWithRed:green:blue:': '@28@0:8f16f20f24', 'red': 'f16@0:8', 'green': 'f16@0:8', 'blue': 'f16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16', 'description': '@16@0:8'} {
			method := objc_instance_method(cls, u64(selector.str))
			assert method != 0 && ctext(u64(objc_method_types(method))) == types
			signature := api.msg(cls, c'instanceMethodSignatureForSelector:', u64(selector.str))
			assert signature != 0
			assert api.msg(signature, c'methodReturnLength', 0) == if types.starts_with('f') { u64(4) } else { u64(8) }
			if selector == 'initWithRed:green:blue:' {
				assert api.msg(signature, c'numberOfArguments', 0) == 5
				for index in 2 .. 5 { assert ctext(api.msg(signature, c'getArgumentTypeAtIndex:', u64(index))) == 'f' }
			}
		}
		for selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'initWithColorPreset:']! {
			assert objc_instance_method(cls, u64(selector.str)) == 0 && objc_class_method(cls, u64(selector.str)) == 0
		}
		color_values(api)
		color := api.color_init(api.msg(cls, c'alloc', 0), [u32(0x3e800000), 0x3f000000, 0x3f400000]!)
		mut weak := u64(0); objc_store_weak(&weak, color)
		duplicate := api.msg(color, c'copy', 0); assert obj_header(duplicate).refs == 1
		api.msg(color, c'release', 0); assert weak == 0
		assert api.color_bits(duplicate, c'green') == 0x3f000000
		api.msg(duplicate, c'release', 0); objc_store_weak(&weak, 0)
		mut storage := [5]u64{}; storage[0] = 0x12345678; storage[4] = 0x87654321
		caller := u64(unsafe { &storage[1] })
		assert objc_construct_instance(cls, caller) == caller && api.msg(caller, c'init', 0) == caller
		assert api.color_bits(caller, c'red') == 0
		assert api.color_init(caller, [u32(0x80000000), 0x7fc01234, 0x40000000]!) == caller
		assert api.color_bits(caller, c'green') == 0x7fc01234
		objc_destruct_instance(caller)
		assert storage[0] == 0x12345678 && storage[4] == 0x87654321
		sub := objc_allocate_class(cls, c'VinixRGBColor', 0)
		assert objc_add_ivar(sub, c'_extra', 8, 3, c'Q'); objc_register_class(sub)
		child := api.color_init(api.msg(sub, c'alloc', 0), [u32(0x3e800000), 0x3f000000, 0x3f400000]!)
		unsafe { *(&u64(child + 24)) = 0x123456789abcdef0 }
		saved := objc_method_imp(objc_instance_method(cls, u64(c'red')))
		assert objc_add_method(sub, u64(c'red'), u64(unsafe { voidptr(color_red_override) }), c'f16@0:8')
		assert api.color_bits(child, c'red') == 0x3f600000
		assert bits.f32_bits(unsafe { ColorGetSend(voidptr(saved))(child, u64(c'red')) }) == 0x3e800000
		assert objc_add_method(sub, u64(c'initWithRed:green:blue:'), u64(unsafe { voidptr(color_init_unexpected) }), c'@28@0:8f16f20f24')
		child_copy := api.msg(child, c'copy', 0)
		assert read64(child_copy) == sub && api.color_bits(child_copy, c'blue') == 0x3f400000
		assert bits.f32_bits(unsafe { ColorGetSend(voidptr(saved))(child_copy, u64(c'red')) }) == 0x3e800000
		assert read64(child_copy + 24) == 0
		api.msg(child, c'release', 0); api.msg(child_copy, c'release', 0)
		objc_pool_pop(pool); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-GC-COLOR: scoped imports, float ABI and ivars, exact bits, copy ownership, caller storage, subclass overrides, saved IMP and two drained runtimes')
}
fn test_gc_color_rejections() {
	objc_start(); api := controller_api(ios_runtime.names['GCColor'])
	for mode in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'initWithColorPreset:', 'changed-isa', 'foreign-storage']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			if mode in ['changed-isa', 'foreign-storage']! {
				sub := objc_allocate_class(if mode == 'changed-isa' { api.cls } else { ios_runtime.names['NSObject'] }, c'VinixChangedColor', 0)
				if mode == 'foreign-storage' { assert objc_add_ivar(sub, c'_padding', 16, 3, c'[16C]') }
				objc_register_class(sub)
				object := objc_allocate(if mode == 'changed-isa' { api.cls } else { sub })
				objc_set_class(object, if mode == 'changed-isa' { sub } else { api.cls })
				api.msg(object, c'red', 0)
			} else { api.msg(if mode == 'supportsSecureCoding' { api.cls } else { objc_allocate(api.cls) }, mode.str, 0) }
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := if mode in ['changed-isa', 'foreign-storage']! { 'GCColor requires live owned color storage' } else { 'unsupported GCColor method: ' + mode }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GC-COLOR-REJECT: eight mutable copying, coding, preset and incompatible storage cases fail explicitly')
}

fn mouse_discovery(api ControllerApi) {
	for _ in 0 .. 3 {
		array := api.msg(api.cls, c'mice', 0)
		assert array != 0 && api.msg(array, c'count', 0) == 0
		assert api.msg(api.cls, c'current', 0) == 0
		assert api.msg(array, c'retain', 0) == array
		api.msg(array, c'release', 0)
	}
	for name in ['GCMouseDidConnectNotification', 'GCMouseDidDisconnectNotification',
		'GCMouseDidBecomeCurrentNotification', 'GCMouseDidStopBeingCurrentNotification']! {
		mut address := u64(0)
		$if macos { if api.native { address = u64(C.dlsym(unsafe { voidptr(-2) }, name.str)) } }
		if !api.native { address = runtime_symbol('/System/Library/Frameworks/GameController.framework/GameController', '_' + name) or { panic(err) } }
		assert address != 0
		object := read64(address)
		assert object != 0 && ctext(api.msg(object, c'UTF8String', 0)) == name
		assert api.msg(object, c'retain', 0) == object
		api.msg(object, c'release', 0)
		assert read64(address) == object
	}
}
fn mouse_worker(api ControllerApi, expected u64, cell u64) {
	pool := objc_pool_push()
	for _ in 0 .. 128 {
		assert api.msg(api.cls, c'mice', 0) == expected
		assert api.msg(expected, c'count', 0) == 0 && api.msg(api.cls, c'current', 0) == 0
		assert runtime_symbol('/System/Library/Frameworks/GameController.framework/GameController', '_GCMouseDidConnectNotification') or { panic(err) } == cell
		mouse_discovery(api)
	}
	objc_pool_pop(pool)
}
fn test_gc_mouse_native() {
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/GameController.framework/GameController', 2) != unsafe { nil }
		cls := u64(C.objc_getClass(c'GCMouse'))
		assert cls != 0 && C.class_getInstanceSize(unsafe { voidptr(cls) }) == 40
		assert C.class_getSuperclass(unsafe { voidptr(cls) }) == C.objc_getClass(c'NSObject')
		api := ControllerApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: cls}
		pool := api.msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		mouse_discovery(api); api.msg(pool, c'drain', 0)
		println('IOS-GC-MOUSE-NATIVE: 40-byte NSObject, empty discovery, nil current and four notification values')
	}
}
fn test_gc_mouse_runtime() {
	for _ in 0 .. 2 {
		objc_start(); pool := objc_pool_push()
		cls := ios_runtime.names['GCMouse']; api := controller_api(cls)
		library := '/System/Library/Frameworks/GameController.framework/GameController'
		assert game_mouse_family(cls) && !game_controller_family(cls) && !gamepad_family(cls)
		assert objc_class_size(cls) == 40 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			assert runtime_symbol(library, prefix + 'GCMouse')! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['Foundation', 'UIKit']! {
				if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, prefix + 'GCMouse') { assert false }
			}
		}
		for name in ['GCMouseDidConnectNotification', 'GCMouseDidDisconnectNotification',
			'GCMouseDidBecomeCurrentNotification', 'GCMouseDidStopBeingCurrentNotification']! {
			for wrong in ['Foundation', 'UIKit']! {
				if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, '_' + name) { assert false }
			}
		}
		for i, name in ['_creationSequence', '_vendorName', '_handlerQueue', '_mouseInput']! {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0 && objc_ivar_offset(ivar) == 8 + 8 * i
			assert ctext(u64(objc_ivar_types(ivar))) == ['I', '@"NSString"', '@"NSObject<OS_dispatch_queue>"', '@"GCMouseInput"']![i]
		}
		for selector in [c'mice', c'current']! {
			method := objc_class_method(cls, u64(selector))
			assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
			assert objc_responds(cls, selector) && objc_instance_method(cls, u64(selector)) == 0
			signature := api.msg(cls, c'methodSignatureForSelector:', u64(selector))
			assert signature != 0 && api.msg(signature, c'numberOfArguments', 0) == 2
			assert ctext(api.msg(signature, c'methodReturnType', 0)) == '@'
			assert api.msg(signature, c'methodReturnLength', 0) == 8
		}
		for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'initWithName:additionalButtons:', c'mouseInput', c'physicalInputProfile', c'controllers']! {
			assert !objc_responds(cls, selector)
			assert objc_class_method(cls, u64(selector)) == 0 && objc_instance_method(cls, u64(selector)) == 0
		}
		mouse_discovery(api); controller_constants(controller_api(ios_runtime.names['GCController']))
		array := api.msg(cls, c'mice', 0)
		assert array == api.msg(ios_runtime.names['GCController'], c'controllers', 0)
		assert api.msg(array, c'copy', 0) == array; api.msg(array, c'release', 0)
		assert !objc_responds(array, c'addObject:')
		cell := runtime_symbol(library, '_GCMouseDidConnectNotification')!
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn mouse_worker(api, array, cell) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline && ios_runtime.block_refs.len == 0
		sub := objc_allocate_class(cls, c'VinixDiscoveryMouse', 0); objc_register_class(sub)
		assert game_mouse_family(sub) && objc_class_size(sub) == 40
		assert api.msg(sub, c'mice', 0) == array && api.msg(sub, c'current', 0) == 0
		saved := objc_method_imp(objc_class_method(cls, u64(c'current')))
		assert objc_add_method(read64(sub), u64(c'current'), u64(unsafe { voidptr(controller_override) }), c'@16@0:8')
		assert api.msg(sub, c'current', 0) == sub
		assert unsafe { ControllerSend(voidptr(saved))(sub, u64(c'current'), 0) } == 0
		assert objc_add_method(read64(sub), u64(c'copy'), u64(unsafe { voidptr(controller_override) }), c'@16@0:8')
		assert objc_responds(sub, c'copy') && api.msg(sub, c'copy', 0) == sub
		objc_pool_pop(pool); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		assert ios_runtime.controller_constants_arena == 0
	}
	println('IOS-GC-MOUSE: scoped imports, typed class methods and ivars, immutable empty discovery, four constants, concurrent readers, subclass overrides, saved IMP and two drained runtimes')
}
fn test_gc_mouse_rejections() {
	objc_start(); api := controller_api(ios_runtime.names['GCMouse'])
	for mode in ['alloc', 'new', 'allocate', 'caller', 'subclass', 'copy', 'initWithCoder:', 'supportsSecureCoding', 'mouseInput']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'allocate' { objc_allocate(api.cls) }
				'caller' { mut storage := [5]u64{}; objc_construct_instance(api.cls, u64(unsafe { &storage[0] })) }
				'subclass' { sub := objc_allocate_class(api.cls, c'VinixPhysicalMouse', 0); objc_register_class(sub); objc_allocate(sub) }
				else { api.msg(api.cls, mode.str, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := if mode == 'mouseInput' { 'unimplemented Objective-C method' } else { 'GCMouse construction requires an implemented physical input profile' }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GC-MOUSE-REJECT: nine construction, caller storage, subclass, copying, coding and input cases fail explicitly')
}
