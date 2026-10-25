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
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char

type ResourceFixtureSend = fn (u64, u64, u64, u64, u64) u64
type ResourceFixtureDouble = fn (u64, u64) f64
type ResourceFixtureSetDouble = fn (u64, u64, f64)
struct ResourceFixtureApi { native bool send u64 }
fn (api ResourceFixtureApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api ResourceFixtureApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ResourceFixtureApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { ResourceFixtureSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api ResourceFixtureApi) priority(object u64) f64 {
	return unsafe { ResourceFixtureDouble(voidptr(api.send))(object, api.selector(c'loadingPriority')) }
}
fn (api ResourceFixtureApi) set_priority(object u64, value f64) {
	unsafe { ResourceFixtureSetDouble(voidptr(api.send))(object, api.selector(c'setLoadingPriority:'), value) }
}
fn (api ResourceFixtureApi) string(value string) u64 {
	return api.message(api.message(api.cls('NSString'), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4)
}
fn (api ResourceFixtureApi) tags(item u64) u64 {
	set := api.message(api.message(api.cls('NSMutableSet'), c'alloc', 0, 0, 0), c'init', 0, 0, 0)
	if item != 0 { api.message(set, c'addObject:', item, 0, 0) }
	return set
}
fn (api ResourceFixtureApi) request(tags u64, bundle u64, explicit bool) u64 {
	return api.message(api.message(api.cls('NSBundleResourceRequest'), c'alloc', 0, 0, 0), if explicit { c'initWithTags:bundle:' } else { c'initWithTags:' }, tags, bundle, 0)
}
fn (api ResourceFixtureApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api ResourceFixtureApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api ResourceFixtureApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn resource_fixture_metadata(api ResourceFixtureApi) {
	cls := api.cls('NSBundleResourceRequest'); assert cls != 0
	$if macos { if api.native { assert C.class_getInstanceSize(voidptr(cls)) == 48 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject') } }
	if !api.native { assert objc_class_size(cls) == 48 && objc_class_parent(cls) == api.cls('NSObject') }
	for i, pair in [['_tags', '@"NSSet"']!, ['_priority', 'd']!, ['_bundle', '@"NSBundle"']!, ['_progress', '@"NSProgress"']!, ['_fetchState', 'q']!]! {
		$if macos { if api.native {
			ivar := C.class_getInstanceVariable(voidptr(cls), pair[0].str); assert ivar != unsafe { nil }
			assert C.ivar_getOffset(ivar) == 8 + i * 8 && unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == pair[1]
		} }
		if !api.native { ivar := objc_find_ivar(cls, pair[0].str); assert ivar != 0; assert objc_ivar_offset(ivar) == 8 + i * 8 && ctext(u64(objc_ivar_types(ivar))) == pair[1] }
	}
	for name, types in {'initWithTags:': '@24@0:8@16', 'initWithTags:bundle:': '@32@0:8@16@24', 'tags': '@16@0:8', 'bundle': '@16@0:8', 'loadingPriority': 'd16@0:8', 'setLoadingPriority:': 'v24@0:8d16'} {
		mut actual := ''
		$if macos { if api.native { method := C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(name.str))); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
		if !api.native { method := objc_instance_method(cls, u64(name.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == types, name + ': ' + actual
	}
}
fn resource_fixture_shared(api ResourceFixtureApi) {
	pool := api.pool(); resource_fixture_metadata(api)
	bundle := api.message(api.cls('NSBundle'), c'mainBundle', 0, 0, 0); assert bundle != 0
	for explicit in [false, true]! { for nil_tags in [false, true]! {
		tags := if nil_tags { u64(0) } else { api.tags(0) }
		object := api.request(tags, 0, explicit); assert object != 0
		assert api.message(object, c'bundle', 0, 0, 0) == (if explicit { u64(0) } else { bundle }) && api.priority(object) == 0.5
		copied := api.message(object, c'tags', 0, 0, 0)
		if nil_tags { assert copied == 0 } else { assert copied != 0 && copied != tags && api.message(copied, c'count', 0, 0, 0) == 0 }
		for i, value in [f64(-1), 0.0, 0.75, 1.0, 2.0]! { api.set_priority(object, value); assert api.priority(object) == [f64(0), 0, 0.75, 1, 1]![i] }
		api.release(tags); api.release(object)
	} }
	for text in ['', 'missing-tag', '😀 café é', 'a\x00b', 'x'.repeat(65536)] {
		item := api.string(text); tags := api.tags(item); object := api.request(tags, bundle, true)
		copied := api.message(object, c'tags', 0, 0, 0)
		assert api.message(copied, c'count', 0, 0, 0) == 1 && api.message(copied, c'anyObject', 0, 0, 0) == item
		api.message(tags, c'removeAllObjects', 0, 0, 0); api.release(tags); api.release(item)
		assert api.message(copied, c'count', 0, 0, 0) == 1 && api.message(object, c'bundle', 0, 0, 0) == bundle
		pointer := api.message(api.message(copied, c'anyObject', 0, 0, 0), c'UTF8String', 0, 0, 0)
		assert unsafe { tos(&u8(pointer), text.len) } == text && unsafe { (&u8(pointer))[text.len] } == 0
		api.release(object)
	}
	initial := api.string('before'); item := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0, 0), c'initWithString:', initial, 0, 0); api.release(initial)
	tags := api.tags(item); object := api.request(tags, bundle, true); changed := api.string('after')
	api.message(item, c'setString:', changed, 0, 0); api.release(changed); api.release(item); api.release(tags); api.drain(pool)
	copied := api.message(object, c'tags', 0, 0, 0); assert api.message(copied, c'anyObject', 0, 0, 0) == item
	pointer := api.message(item, c'UTF8String', 0, 0, 0); assert unsafe { tos(&u8(pointer), 5) } == 'after'
	assert api.message(object, c'bundle', 0, 0, 0) == bundle; api.release(object)
}
fn resource_runtime_api() ResourceFixtureApi { return ResourceFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
__global resource_fixture_mode = ''
__global resource_fixture_calls = 0
__global resource_fixture_tags = u64(0)
__global resource_fixture_item = u64(0)
__global resource_fixture_receiver = u64(0)
fn resource_fixture_worker() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if resource_fixture_tags != 0 { objc_release(resource_fixture_tags) }
	if resource_fixture_item != 0 { objc_release(resource_fixture_item) }
	if resource_fixture_mode == 'receiver-release' { objc_release(resource_fixture_receiver) }
}
fn resource_fixture_constructor(object u64, selector u64) u64 {
	if resource_fixture_mode == '' { return object }
	resource_fixture_calls++
	if resource_fixture_calls == 1 {
		if resource_fixture_mode in ['release-inputs', 'receiver-release', 'bundle-reentry']! { worker := spawn resource_fixture_worker(); worker.wait() }
		if resource_fixture_mode == 'dispose-initializer' { objc_destruct_instance(resource_fixture_receiver) }
		if resource_fixture_mode == 'constructor-isa' { objc_set_class(resource_fixture_receiver, ios_runtime.names['NSObject']) }
		if resource_fixture_mode == 'constructor-storage' { unsafe { *(&u64(resource_fixture_receiver + 8)) = 1 } }
	}
	if resource_fixture_mode == 'fail' { return 0 }
	return object
}
fn resource_fixture_hooks() {
	for name in ['NSBundle', 'NSSet']! { assert objc_add_method(ios_runtime.names[name], u64(c'.cxx_construct'), u64(unsafe { voidptr(resource_fixture_constructor) }), c'@16@0:8') }
}
fn resource_fixture_thread(object u64) {
	api := resource_runtime_api()
	for _ in 0 .. 100 { api.set_priority(object, 0.75); assert api.priority(object) == 0.75 && api.message(object, c'bundle', 0, 0, 0) != 0 }
}
fn resource_fixture_bootstrap(api ResourceFixtureApi) {
	resource_fixture_hooks(); before := ios_runtime.objects.len
	resource_fixture_mode = 'fail'; resource_fixture_calls = 0
	assert api.request(0, 0, false) == 0; resource_fixture_mode = ''
	assert resource_fixture_calls == 1 && ios_runtime.bundle_object == 0 && ios_runtime.objects.len == before
	resource_fixture_mode = 'bundle-reentry'; resource_fixture_calls = 0
	object := api.request(0, 0, false); resource_fixture_mode = ''
	assert object != 0 && resource_fixture_calls == 1; api.release(object)
}
fn resource_fixture_runtime(api ResourceFixtureApi) {
	pool := api.pool(); cls := api.cls('NSBundleResourceRequest'); library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSBundleResourceRequest') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSBundleResourceRequest') or { panic(err) } == read64(cls)
	for wrong in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '/usr/lib/libobjc.A.dylib']! { if _ := runtime_symbol(wrong, '_OBJC_CLASS_$_NSBundleResourceRequest') { assert false } }
	mut guarded := [u64(0x1122334455667788), 0, 0, 0, 0, 0, 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	assert api.message(caller, c'initWithTags:', 0, 0, 0) == caller && api.priority(caller) == 0.5
	objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
	assert guarded[0] == 0x1122334455667788 && guarded[7] == 0x8877665544332211
	for i in 2 .. 7 { assert guarded[i] == 0 }
	for _ in 0 .. 32 { object := api.request(0, 0, false); objc_set_class(object, api.cls('NSObject')); objc_release(object) }
	object := api.request(0, 0, false)
	a := spawn resource_fixture_thread(object); b := spawn resource_fixture_thread(object); c := spawn resource_fixture_thread(object); d := spawn resource_fixture_thread(object); a.wait(); b.wait(); c.wait(); d.wait(); api.release(object)
	item := api.string('snapshot'); tags := api.tags(item); before := ios_runtime.objects.len
	resource_fixture_mode = 'fail'; resource_fixture_calls = 0; assert api.request(tags, 0, false) == 0; resource_fixture_mode = ''
	assert resource_fixture_calls == 1 && ios_runtime.objects.len == before
	resource_fixture_tags = tags; resource_fixture_item = item; resource_fixture_calls = 0; resource_fixture_mode = 'release-inputs'
	initialized := api.request(tags, 0, false); resource_fixture_mode = ''; resource_fixture_tags = 0; resource_fixture_item = 0
	assert initialized != 0 && resource_fixture_calls == 1
	copied := api.message(initialized, c'tags', 0, 0, 0); assert api.message(copied, c'anyObject', 0, 0, 0) == item; api.release(initialized)
	api.drain(pool)
}
fn test_resource_runtime() {
	for _ in 0 .. 2 {
		resource_fixture_mode = ''; objc_start(); api := resource_runtime_api(); resource_fixture_bootstrap(api); resource_fixture_shared(api); resource_fixture_runtime(api)
		assert ios_runtime.live == 1 && ios_runtime.objects.len == 1 && ios_runtime.weak.len == 0
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-BUNDLE-RESOURCE: native parity, constructor rollback/reentry, shallow tag snapshots, 400 concurrent priorities, guarded storage, 32 isa replacements and two balanced lifetimes PASS')
}
fn test_resource_rejections() {
	objc_start(); api := resource_runtime_api(); cls := api.cls('NSBundleResourceRequest')
	for selector in [c'init', c'progress', c'beginAccessingResourcesWithCompletionHandler:', c'conditionallyBeginAccessingResourcesWithCompletionHandler:', c'endAccessingResources', c'copy', c'encodeWithCoder:']! { assert !objc_responds(cls, selector); assert objc_instance_method(cls, u64(selector)) == 0 }
	modes := ['raw-getter', 'default-new', 'repeat-init', 'subclass', 'caller-subclass', 'spoof', 'isa-change', 'raw-isa', 'body-tamper', 'copy-provenance', 'tags-type', 'tags-class', 'tags-raw', 'tags-custom', 'tags-spoof', 'tags-isa', 'member-type', 'member-custom', 'member-spoof', 'member-isa', 'member-raw', 'member-utf8', 'member-limit', 'wrong-bundle', 'progress', 'begin', 'conditional', 'end', 'copy', 'coding', 'nan', 'infinity', 'constructor-storage', 'constructor-isa', 'dispose-initializer', 'receiver-release', 'caller-failure']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); pool := api.pool()
			object := api.request(0, 0, false); resource_fixture_mode = ''; resource_fixture_calls = 0
			match mode {
				'raw-getter' { api.message(objc_allocate(cls), c'tags', 0, 0, 0) }
				'default-new' { objc_new(cls) }
				'repeat-init' { api.message(object, c'initWithTags:', 0, 0, 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'VinixUnsupportedResource', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut bytes := [6]u64{}; objc_construct_instance(custom, u64(unsafe { &bytes[0] })) } }
				'spoof' { wrong := objc_new(api.cls('NSObject')); objc_set_class(wrong, cls); api.message(wrong, c'tags', 0, 0, 0) }
				'isa-change', 'raw-isa', 'body-tamper' { if mode == 'isa-change' { objc_set_class(object, api.cls('NSObject')) } else if mode == 'raw-isa' { unsafe { *(&u64(object)) = api.cls('NSObject') } } else { unsafe { *(&u64(object + 8)) = 1 } }; api.message(object, c'tags', 0, 0, 0) }
				'copy-provenance' { objc_set_class(object, api.cls('NSURLRequest')); objc_copy_value(object, false) }
				'tags-type', 'tags-class', 'tags-raw', 'tags-custom', 'tags-spoof', 'tags-isa' {
					mut tags := api.tags(0)
					if mode == 'tags-type' { tags = objc_new(api.cls('NSObject')) }
					if mode == 'tags-class' { tags = api.cls('NSSet') }
					if mode == 'tags-raw' { tags = objc_allocate(api.cls('NSSet')) }
					if mode == 'tags-custom' { custom := objc_allocate_class(api.cls('NSSet'), c'VinixUnsupportedResourceSet', 0); objc_register_class(custom); objc_set_class(tags, custom) }
					if mode == 'tags-spoof' { tags = objc_new(api.cls('NSObject')); objc_set_class(tags, api.cls('NSSet')) }
					if mode == 'tags-isa' { objc_set_class(tags, api.cls('NSSet')) }
					api.request(tags, 0, false)
				}
				'member-type', 'member-custom', 'member-spoof', 'member-isa', 'member-raw', 'member-utf8', 'member-limit' {
					item := api.string(if mode == 'member-limit' { 'x'.repeat(65537) } else { 'tag' }); tags := api.tags(item)
					if mode == 'member-type' { objc_set_class(item, api.cls('NSObject')) }
					if mode == 'member-custom' { custom := objc_allocate_class(api.cls('NSString'), c'VinixUnsupportedResourceString', 0); objc_register_class(custom); objc_set_class(item, custom) }
					if mode == 'member-spoof' { wrong := objc_new(api.cls('NSObject')); objc_set_class(wrong, api.cls('NSString')); obj_header(tags).items[0] = wrong }
					if mode == 'member-isa' { objc_set_class(item, api.cls('NSMutableString')) }
					if mode == 'member-raw' { obj_header(tags).items[0] = objc_allocate(api.cls('NSMutableString')) }
					if mode == 'member-utf8' { unsafe { obj_header(item).text[0] = char(0xff) } }
					api.request(tags, 0, false)
				}
				'wrong-bundle' { api.request(0, objc_new(api.cls('NSObject')), true) }
				'progress', 'begin', 'conditional', 'end', 'copy', 'coding' { selector := match mode { 'progress' { c'progress' } 'begin' { c'beginAccessingResourcesWithCompletionHandler:' } 'conditional' { c'conditionallyBeginAccessingResourcesWithCompletionHandler:' } 'end' { c'endAccessingResources' } 'copy' { c'copy' } else { c'encodeWithCoder:' } }; api.message(object, selector, 0, 0, 0) }
				'nan', 'infinity' { value := if mode == 'nan' { u64(0x7ff8000000000000) } else { u64(0x7ff0000000000000) }; api.set_priority(object, unsafe { *(&f64(&value)) }) }
				'constructor-storage', 'constructor-isa', 'dispose-initializer', 'receiver-release', 'caller-failure' {
					mut bytes := [6]u64{}; resource_fixture_receiver = if mode == 'caller-failure' { objc_construct_instance(cls, u64(unsafe { &bytes[0] })) } else { objc_allocate(cls) }
					tags := api.tags(0); resource_fixture_hooks(); resource_fixture_mode = if mode == 'caller-failure' { 'fail' } else { mode }
					api.message(resource_fixture_receiver, c'initWithTags:', tags, 0, 0)
				}
				else {}
			}
			api.drain(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0
	println('IOS-BUNDLE-RESOURCE-REJECT: 37 invalid storage, tags, bundles, subclasses, nonfinite priorities, unsupported access and constructor lifetime violations PASS')
}
fn test_resource_native() {
	$if macos { api := ResourceFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}; assert api.send != 0; resource_fixture_shared(api); println('IOS-BUNDLE-RESOURCE-NATIVE: 48-byte layout, five ivars, six encodings, nil/empty/UTF8/NUL tags, shallow copies, retained bundle and clamped priorities PASS') }
}
