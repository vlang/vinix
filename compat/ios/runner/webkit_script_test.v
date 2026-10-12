// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework WebKit
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.dlsym(voidptr, &char) voidptr

type ScriptSend = fn (u64, u64, u64, u64, u64, u64) u64

struct ScriptApi {
	native bool
	send u64
	script u64
	controller u64
	world u64
	string_class u64
	configuration u64
}

fn (api ScriptApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}

fn (api ScriptApi) message(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { ScriptSend(voidptr(api.send))(object, api.selector(name), a, b, c, d) }
}

fn (api ScriptApi) string_value(value &char) u64 {
	return api.message(api.string_class, c'stringWithUTF8String:', u64(value), 0, 0, 0)
}

fn (api ScriptApi) text(object u64) string { return ctext(api.message(object, c'UTF8String', 0, 0, 0, 0)) }
fn (api ScriptApi) release(object u64) { api.message(object, c'release', 0, 0, 0, 0) }
fn (api ScriptApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0, 0, 0) }

fn (api ScriptApi) create(source u64, injection u64, main_only u64, world u64) u64 {
	object := api.message(api.script, c'alloc', 0, 0, 0, 0)
	return if world == 0 { api.message(object, c'initWithSource:injectionTime:forMainFrameOnly:', source, injection, main_only, 0) }
		else { api.message(object, c'initWithSource:injectionTime:forMainFrameOnly:inContentWorld:', source, injection, main_only, world) }
}

fn script_cases(api ScriptApi) {
	page := api.message(api.world, c'pageWorld', 0, 0, 0, 0)
	client := api.message(api.world, c'defaultClientWorld', 0, 0, 0, 0)
	assert page != 0 && client != 0 && page != client
	assert page == api.message(api.world, c'pageWorld', 0, 0, 0, 0)
	assert client == api.message(api.world, c'defaultClientWorld', 0, 0, 0, 0)
	assert api.message(page, c'name', 0, 0, 0, 0) == 0 && api.message(client, c'name', 0, 0, 0, 0) == 0
	named := api.message(api.world, c'worldWithName:', api.string_value(c'fixture-world'), 0, 0, 0)
	assert named != page && named != client
	assert api.text(api.message(named, c'name', 0, 0, 0, 0)) == 'fixture-world'
	assert named == api.message(api.world, c'worldWithName:', api.string_value(c'fixture-world'), 0, 0, 0)
	empty_world := api.message(api.world, c'worldWithName:', api.string_value(c''), 0, 0, 0)
	assert empty_world != page && api.message(empty_world, c'name', 0, 0, 0, 0) != 0
	first := api.create(api.string_value(c'window.fixture=1;'), 0, 0, 0)
	second := api.create(api.string_value(c'window.fixture=2;'), 1, 1, named)
	empty := api.create(api.string_value(c''), 0, 1, client)
	assert api.text(api.message(empty, c'source', 0, 0, 0, 0)) == ''
	api.release(empty)
	assert api.text(api.message(first, c'source', 0, 0, 0, 0)) == 'window.fixture=1;'
	assert api.message(first, c'injectionTime', 0, 0, 0, 0) == 0 && api.message(first, c'isForMainFrameOnly', 0, 0, 0, 0) == 0
	assert api.message(second, c'injectionTime', 0, 0, 0, 0) == 1 && api.message(second, c'isForMainFrameOnly', 0, 0, 0, 0) == 1
	for selector in [c'copy', c'copyWithZone:']! {
		duplicate := api.message(first, selector, 0, 0, 0, 0)
		assert duplicate == first
		api.release(duplicate)
	}
	controller := api.message(api.controller, c'new', 0, 0, 0, 0)
	view := api.retain(api.message(controller, c'userScripts', 0, 0, 0, 0))
	assert api.message(view, c'count', 0, 0, 0, 0) == 0
	assert view == api.message(controller, c'userScripts', 0, 0, 0, 0)
	assert api.message(view, c'respondsToSelector:', api.selector(c'addObject:'), 0, 0, 0) == 0
	api.message(controller, c'addUserScript:', first, 0, 0, 0)
	api.message(controller, c'addUserScript:', second, 0, 0, 0)
	api.message(controller, c'addUserScript:', first, 0, 0, 0)
	assert api.message(view, c'count', 0, 0, 0, 0) == 3
	for index, script in [first, second, first]! { assert api.message(view, c'objectAtIndex:', u64(index), 0, 0, 0) == script }
	assert api.message(view, c'firstObject', 0, 0, 0, 0) == first
	copied_view := api.message(view, c'copyWithZone:', 0, 0, 0, 0)
	assert copied_view == view
	api.retain(first)
	api.release(first)
	api.release(second)
	api.message(controller, c'removeAllUserScripts', 0, 0, 0, 0)
	assert api.message(view, c'count', 0, 0, 0, 0) == 0 && api.message(copied_view, c'count', 0, 0, 0, 0) == 0
	assert api.text(api.message(first, c'source', 0, 0, 0, 0)) == 'window.fixture=1;'
	api.message(controller, c'addUserScript:', first, 0, 0, 0)
	api.release(first)
	api.release(controller)
	assert api.message(view, c'count', 0, 0, 0, 0) == 1
	assert api.text(api.message(api.message(view, c'firstObject', 0, 0, 0, 0), c'source', 0, 0, 0, 0)) == 'window.fixture=1;'
	api.release(copied_view)
	api.release(view)
	// A copied configuration shares the controller and its registration list.
	configuration := api.message(api.configuration, c'new', 0, 0, 0, 0)
	shared_controller := api.message(configuration, c'userContentController', 0, 0, 0, 0)
	script := api.create(api.string_value(c'shared-registration'), 1, 0, page)
	api.message(shared_controller, c'addUserScript:', script, 0, 0, 0)
	api.release(script)
	copy_config := api.message(configuration, c'copy', 0, 0, 0, 0)
	assert api.message(copy_config, c'userContentController', 0, 0, 0, 0) == shared_controller
	api.release(configuration)
	assert api.message(api.message(shared_controller, c'userScripts', 0, 0, 0, 0), c'count', 0, 0, 0, 0) == 1
	api.release(copy_config)
}

fn test_script_native_webkit() {
	$if macos {
		api := ScriptApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')),
			script: u64(C.objc_getClass(c'WKUserScript')), controller: u64(C.objc_getClass(c'WKUserContentController')),
			world: u64(C.objc_getClass(c'WKContentWorld')), string_class: u64(C.objc_getClass(c'NSString')),
			configuration: u64(C.objc_getClass(c'WKWebViewConfiguration'))}
		for index, cls in [api.script, api.world, u64(C.objc_getClass(c'WKNSArray'))]! {
			assert C.class_getInstanceSize(voidptr(cls)) == [usize(128), 80, 40]![index]
		}
		pool := api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0, 0)
		script_cases(api)
		mutable := api.message(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(c'original'), 0, 0, 0)
		script := api.create(mutable, 0, 1, 0)
		world := api.message(api.world, c'worldWithName:', mutable, 0, 0, 0)
		api.message(mutable, c'appendString:', api.string_value(c'-changed'), 0, 0, 0)
		assert api.text(api.message(script, c'source', 0, 0, 0, 0)) == 'original'
		assert api.text(api.message(world, c'name', 0, 0, 0, 0)) == 'original'
		api.release(script)
		api.release(pool)
		println('IOS-SCRIPT-NATIVE: copied sources/world names, immutable copies, ordered duplicate registrations, live read-only arrays and retained-list lifetimes passed')
	}
}

fn script_override_copy(object u64, selector &char) u64 { return objc_retain(object) }

fn test_script_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start()
		api := ScriptApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), script: ios_runtime.names['WKUserScript'],
			controller: ios_runtime.names['WKUserContentController'], world: ios_runtime.names['WKContentWorld'],
			string_class: ios_runtime.names['NSString'], configuration: ios_runtime.names['WKWebViewConfiguration']}
		for name in ['WKUserScript', 'WKContentWorld', 'WKNSArray']! {
			cls := ios_runtime.names[name]
			assert objc_class_size(cls) == webkit_size(name)
			assert runtime_symbol('/System/Library/Frameworks/WebKit.framework/WebKit', '_OBJC_CLASS_$_' + name) or { panic(err) } == cls
			assert runtime_symbol('/System/Library/Frameworks/WebKit.framework/WebKit', '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(cls)
		}
		assert objc_class_parent(ios_runtime.names['WKNSArray']) == ios_runtime.names['NSArray']
		assert objc_ivar_offset(objc_find_ivar(api.script, c'_userScript')) == 8
		assert objc_ivar_offset(objc_find_ivar(api.world, c'_contentWorld')) == 8
		assert ctext(u64(objc_method_types(objc_instance_method(api.script, u64(c'initWithSource:injectionTime:forMainFrameOnly:inContentWorld:'))))) == '@44@0:8@16q24B32@36'
		pool := objc_pool_push()
		script_cases(api)
		objc_pool_pop(pool)
		baseline := ios_runtime.live // Only interned worlds/names and the default store.
		for _ in 0 .. 100 {
			controller := objc_new(api.controller)
			source := owned_string('mutable')
			script := api.create(source, 0, 1, 0)
			unsafe { obj_header(source).text[0] = char(`z`) }
			assert api.text(api.message(script, c'source', 0, 0, 0, 0)) == 'mutable'
			objc_release(source)
			api.message(controller, c'addUserScript:', script, 0, 0, 0)
			api.message(controller, c'addUserScript:', script, 0, 0, 0)
			objc_release(script)
			view := objc_retain(api.message(controller, c'userScripts', 0, 0, 0, 0))
			objc_set_class(controller, ios_runtime.names['NSObject'])
			objc_release(controller)
			assert api.message(view, c'count', 0, 0, 0, 0) == 2
			objc_set_class(view, ios_runtime.names['NSObject'])
			objc_release(view)
			assert ios_runtime.live == baseline
		}
		source := owned_string('caller-storage')
		storage := u64(C.calloc(1, 128))
		assert objc_construct_instance(api.script, storage) == storage
		assert api.message(storage, c'initWithSource:injectionTime:forMainFrameOnly:', source, 1, 0, 0) == storage
		objc_release(source)
		objc_set_class(storage, ios_runtime.names['NSObject'])
		assert objc_destruct_instance(storage) == storage
		C.free(unsafe { voidptr(storage) })
		assert ios_runtime.live == baseline
		// Explicit app methods must remain discoverable on WebKit classes and
		// subclasses even where the native profile has no copy implementation.
		assert objc_instance_method(api.controller, u64(c'copy')) == 0
		assert objc_add_method(api.controller, u64(c'copy'), u64(unsafe { voidptr(script_override_copy) }), c'@16@0:8')
		method := objc_instance_method(api.controller, u64(c'copy'))
		assert objc_method_imp(method) == u64(unsafe { voidptr(script_override_copy) })
		child := objc_allocate_class(api.controller, c'FixtureContentController', 0)
		assert child != 0
		objc_register_class(child)
		assert objc_instance_method(child, u64(c'copy')) == method
		webkit_stop()
		assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-SCRIPT: shared trampoline fixtures, 128/80/40-byte layouts, imports/types, balanced release/isa/caller-storage lifetimes and overridden-method discovery passed')
}

fn test_script_profile_rejections() {
	objc_start()
	api := ScriptApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), script: ios_runtime.names['WKUserScript'],
		controller: ios_runtime.names['WKUserContentController'], world: ios_runtime.names['WKContentWorld'], string_class: ios_runtime.names['NSString']}
	pool := objc_pool_push()
	wrong := objc_new(ios_runtime.names['NSNumber'])
	controller := objc_new(api.controller)
	for operation in 0 .. 6 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0]); assert C.dup2(descriptors[1], 2) == 2; C.close(descriptors[1])
			match operation {
				0 { api.create(wrong, 0, 0, 0) }
				1 { api.create(api.string_value(c'x'), 2, 0, 0) }
				2 { api.message(controller, c'addUserScript:', wrong, 0, 0, 0) }
				3 { api.message(api.message(controller, c'userScripts', 0, 0, 0, 0), c'addObject:', wrong, 0, 0, 0) }
				4 { api.message(api.world, c'worldWithName:', wrong, 0, 0, 0) }
				else { api.message(api.create(api.string_value(c'x'), 0, 0, 0), c'_apiObject', 0, 0, 0, 0) }
			}
			C._exit(0)
		}
		C.close(descriptors[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(descriptors[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains(['WebKit script source must be a string', 'WebKit script injection time is outside the implemented profile',
			'WebKit registration requires an initialized user script', 'mutation of a read-only WebKit script array',
			'WebKit world name must be a string', 'unimplemented Objective-C method WKUserScript _apiObject']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	for selector in [c'_apiObject', c'_contentWorld', c'encodeWithCoder:']! { assert !objc_responds(api.script, selector) }
	objc_release(controller); objc_release(wrong)
	objc_pool_pop(pool)
	webkit_stop()
	assert ios_runtime.live == 0
	objc_stop()
	println('IOS-SCRIPT-REJECT: wrong source/script/world types, unimplemented injection values, array mutation and private engine access reject explicitly')
}
