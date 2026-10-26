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
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
type ProcessInfoSend = fn (u64, u64, u64) u64
type ProcessInfoThermal = fn (u64, u64) i64
type ProcessInfoVersion = fn (u64, u64) IosOperatingSystemVersion
type ProcessInfoCompare = fn (u64, u64, IosOperatingSystemVersion) bool
struct ProcessInfoApi { native bool send u64 cls u64 }
fn (api ProcessInfoApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ProcessInfoApi) message(object u64, name &char, argument u64) u64 {
	return unsafe { ProcessInfoSend(voidptr(api.send))(object, api.selector(name), argument) }
}
fn (api ProcessInfoApi) version(object u64) IosOperatingSystemVersion {
	return unsafe { ProcessInfoVersion(voidptr(api.send))(object, api.selector(c'operatingSystemVersion')) }
}
fn (api ProcessInfoApi) at_least(object u64, version IosOperatingSystemVersion) bool {
	return unsafe { ProcessInfoCompare(voidptr(api.send))(object, api.selector(c'isOperatingSystemAtLeastVersion:'), version) }
}
fn (api ProcessInfoApi) thermal(object u64, entry u64) i64 {
	return unsafe { ProcessInfoThermal(voidptr(entry))(object, api.selector(c'thermalState')) }
}
fn process_info_thermal_cases(api ProcessInfoApi, cls u64, object u64) {
	selector := api.selector(c'thermalState')
	assert api.message(object, c'respondsToSelector:', selector) == 1
	assert api.message(cls, c'respondsToSelector:', selector) == 0
	mut imp := u64(0)
	$if macos { if api.native {
		method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
		assert method != unsafe { nil } && ctext(u64(C.method_getTypeEncoding(method))) == 'q16@0:8'
		imp = u64(C.method_getImplementation(method))
	} }
	if !api.native {
		method := objc_instance_method(cls, selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'q16@0:8'
		assert objc_instance_method(read64(cls), selector) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0
	signature := api.message(object, c'methodSignatureForSelector:', selector)
	assert signature != 0
	assert api.message(signature, c'numberOfArguments', 0) == 2
	assert api.message(signature, c'methodReturnLength', 0) == 8
	assert ctext(api.message(signature, c'methodReturnType', 0)) == 'q'
	for entry in [api.send, imp]! {
		state := api.thermal(object, entry)
		// Native state may change with host load; all four enum values are valid.
		if api.native { assert state >= 0 && state <= 3 } else { assert state == 0 }
	}
}
fn process_info_cases(api ProcessInfoApi, expected []string) {
	singleton := api.message(api.cls, c'processInfo', 0)
	assert singleton != 0 && api.message(api.cls, c'processInfo', 0) == singleton;
	fresh := api.message(api.cls, c'new', 0)
	allocated := api.message(api.cls, c'allocWithZone:', 0)
	assert fresh != singleton && allocated != singleton && allocated != fresh;
	assert api.message(allocated, c'init', 0) == allocated;
	for object in [singleton, fresh, allocated]! {
		state := api.thermal(object, api.send)
		if api.native { assert state >= 0 && state <= 3 } else { assert state == 0 }
		memory := api.message(object, c'physicalMemory', 0)
		assert memory == u64(C.sysconf(C._SC_PHYS_PAGES)) * u64(C.getpagesize()) && memory > 0;
		version := api.version(object)
		assert version.major > 0 && version.minor >= 0 && version.patch >= 0;
		for requested in [version, IosOperatingSystemVersion{major: version.major - 1, minor: 99, patch: 99}, IosOperatingSystemVersion{major: -1, minor: 0, patch: 0}]! { assert api.at_least(object, requested); }
		for requested in [IosOperatingSystemVersion{major: version.major + 1}, IosOperatingSystemVersion{major: version.major, minor: version.minor + 1}, IosOperatingSystemVersion{major: version.major, minor: version.minor, patch: version.patch + 1}]! { assert !api.at_least(object, requested); }
		if !api.native { assert version == IosOperatingSystemVersion{major: 17}; }
		assert api.message(object, c'isiOSAppOnMac', 0) == 0;
		assert api.message(object, c'isMacCatalystApp', 0) == 0;
		arguments := api.message(object, c'arguments', 0)
		assert arguments != 0;
		// Native Foundation may return a fresh immutable array on each call.
		if !api.native { assert api.message(object, c'arguments', 0) == arguments; }
		assert api.message(arguments, c'count', 0) == u64(expected.len);
		for index, text in expected {
			value := api.message(arguments, c'objectAtIndex:', u64(index))
			assert ctext(api.message(value, c'UTF8String', 0)) == text;
		}
	}
	assert api.message(singleton, c'arguments', 0) != api.message(fresh, c'arguments', 0);
	retained := api.message(api.message(fresh, c'arguments', 0), c'retain', 0)
	api.message(fresh, c'release', 0)
	assert api.message(retained, c'count', 0) == u64(expected.len);
	api.message(retained, c'release', 0); api.message(allocated, c'release', 0)
}
fn process_info_worker(api ProcessInfoApi, singleton u64, arguments u64, thermal_imp u64) {
	for _ in 0 .. 1000 {
		assert api.message(api.cls, c'processInfo', 0) == singleton;
		assert api.message(singleton, c'arguments', 0) == arguments;
		assert api.version(singleton) == IosOperatingSystemVersion{major: 17};
		assert api.message(singleton, c'physicalMemory', 0) == u64(C.sysconf(C._SC_PHYS_PAGES)) * u64(C.getpagesize());
		assert api.thermal(singleton, api.send) == 0 && api.thermal(singleton, thermal_imp) == 0;
	}
}
fn test_process_info_native() {
	$if macos {
		api := ProcessInfoApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSProcessInfo'))}
		pool := api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		method := C.class_getInstanceMethod(unsafe { voidptr(api.cls) }, C.sel_registerName(c'physicalMemory'))
		assert method != unsafe { nil } && ctext(u64(C.method_getTypeEncoding(method))) == 'Q16@0:8';
		process_info_cases(api, os.args)
		process_info_thermal_cases(api, api.cls, api.message(api.cls, c'processInfo', 0))
		api.message(pool, c'drain', 0)
		println('IOS-PROCESSINFO-NATIVE: distinct allocation, singleton instance, owned argument snapshots, typed 24-byte version ABI and signed comparisons')
		println('IOS-PROCESSINFO-MEMORY-NATIVE: unsigned 64-bit scalar matches physical pages times page size')
		println('IOS-PROCESSINFO-THERMAL-NATIVE: signed 64-bit enum, instance reflection, signature and direct IMP PASS')
	}
}
fn test_process_info_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		mut executable := '/opt/ios/Fortnite'.clone()
		ns_process_info_start([executable, '-log', 'space é']!)
		unsafe { executable.free() }
		api := ProcessInfoApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSProcessInfo']}
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSProcessInfo')! == api.cls;
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSProcessInfo')! == read64(api.cls);
		assert objc_class_size(api.cls) == 48 && objc_class_parent(api.cls) == ios_runtime.names['NSObject'];
		process_info_cases(api, ['/opt/ios/Fortnite', '-log', 'space é']!)
		singleton := api.message(api.cls, c'processInfo', 0)
		arguments := api.message(singleton, c'arguments', 0)
		pool := objc_pool_push()
		process_info_thermal_cases(api, api.cls, singleton)
		subclass := objc_allocate_class(api.cls, c'VinixThermalProcessInfo', 0)
		objc_register_class(subclass)
		inherited := objc_allocate(subclass)
		process_info_thermal_cases(api, subclass, inherited)
		objc_release(inherited)
		objc_pool_pop(pool)
		baseline := ios_runtime.live
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'environment', c'setArguments:', c'setThermalState:', c'beginActivityWithOptions:reason:']! {
			assert !objc_responds(singleton, selector);
			assert objc_instance_method(api.cls, u64(selector)) == 0;
		}
		for name, types in {'operatingSystemVersion': '{?=qqq}16@0:8', 'physicalMemory': 'Q16@0:8', 'isOperatingSystemAtLeastVersion:': 'B40@0:8{?=qqq}16', 'arguments': '@16@0:8', 'isiOSAppOnMac': 'B16@0:8'} {
			method := objc_instance_method(api.cls, u64(name.str))
			assert method != 0 && ctext(u64(objc_method_types(method))) == types;
		}
		mut guarded := [u64(0x1122334455667788), 0, 0, 0, 0x8877665544332211]!
		mut frame := RegisterFrame{}
		frame.x[8] = u64(unsafe { &guarded[1] })
		assert ns_process_info_dispatch(singleton, 'operatingSystemVersion', mut frame);
		assert guarded == [u64(0x1122334455667788), 17, 0, 0, 0x8877665544332211]!;
		assert objc_responds(singleton, c'physicalMemory') && !objc_responds(api.cls, c'physicalMemory');
		darwin_set_errno(37)
		assert ns_process_info_dispatch(singleton, 'physicalMemory', mut frame);
		assert frame.x[0] == u64(C.sysconf(C._SC_PHYS_PAGES)) * u64(C.getpagesize());
		assert unsafe { *C.ios_errno_address() } == 37;
		assert guarded == [u64(0x1122334455667788), 17, 0, 0, 0x8877665544332211]!;
		for index in 0 .. frame.x.len { if index != 8 { frame.x[index] = u64(index + 100) } }
		for index in 0 .. frame.q.len { frame.q[index] = u64(index + 200) }
		frame.stack = 0x12345678
		before := frame
		assert ns_process_info_dispatch(singleton, 'thermalState', mut frame) && frame.x[0] == 0;
		for index in 1 .. frame.x.len { assert frame.x[index] == before.x[index]; }
		assert frame.q == before.q && frame.stack == before.stack;
		assert guarded == [u64(0x1122334455667788), 17, 0, 0, 0x8877665544332211]!;
		assert unsafe { *C.ios_errno_address() } == 37;
		thermal_imp := objc_method_imp(objc_instance_method(api.cls, u64(c'thermalState')))
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn process_info_worker(api, singleton, arguments, thermal_imp) }
		workers.wait()
		for _ in 0 .. 100 {
			object := api.message(api.cls, c'new', 0)
			api.message(object, c'arguments', 0)
			objc_set_class(object, ios_runtime.names['NSObject']); objc_release(object)
		}
		mut storage := [48]u8{}
		caller := objc_construct_instance(api.cls, u64(unsafe { &storage[0] }))
		assert api.message(caller, c'init', 0) == caller;
		api.message(caller, c'arguments', 0)
		assert api.thermal(caller, api.send) == 0 && api.thermal(caller, thermal_imp) == 0;
		assert objc_destruct_instance(caller) == caller;
		assert ios_runtime.live == baseline;
		objc_stop(); assert ios_runtime.live == 0;
	}
	println('IOS-PROCESSINFO: copied app arguments, guarded version result, 8,000 concurrent queries, caller storage, isa changes and two zero-live-object shutdowns')
	println('IOS-PROCESSINFO-MEMORY: reflected scalar ABI, preserved indirect buffer and errno, 8,000 concurrent queries without new objects')
	println('IOS-PROCESSINFO-THERMAL: nominal fallback, signed ABI, instance reflection, signature, direct IMP, subclass, preserved registers and errno, concurrent readers and zero-live teardown PASS')
}
fn test_process_info_rejections() {
	objc_start(); cls := ios_runtime.names['NSProcessInfo']
	for mode in ['late-arguments', 'copy', 'version-result', 'version-argument', 'array-mutation']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork(); assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := ns_process_info_default(); mut frame := RegisterFrame{}
			match mode {
				'late-arguments' { ns_process_info_start(['late']) }
				'copy' { ns_process_info_dispatch(object, 'copy', mut frame) }
				'version-result' { ns_process_info_dispatch(object, 'operatingSystemVersion', mut frame) }
				'array-mutation' { frame.x[2] = owned_string('mutation'); foundation_dispatch(ns_process_info_arguments(object), 'addObject:', mut frame) }
				else { ns_process_info_dispatch(object, 'isOperatingSystemAtLeastVersion:', mut frame) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut buffer := [16384]u8{}; mut length := 0
		for { assert length < buffer.len; count := C.read(fds[0], unsafe { &buffer[length] }, usize(buffer.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&buffer[0], length) }
		reason := match mode { 'late-arguments' { 'process arguments must be configured before process info queries' } 'copy' { 'process info copies are not implemented' } 'version-result' { 'process info version requires an indirect result buffer' } 'array-mutation' { 'process argument snapshot is read-only' } else { 'process info comparison requires an indirect version argument' } }
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-PROCESSINFO-REJECT: late argument replacement, unsupported copies, missing aggregate buffers and snapshot mutation fail explicitly')
}
