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
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type QueryItemFixtureSend = fn (u64, u64, u64, u64) u64
type QueryItemFixtureBytes = fn (u64, u64, u64, u64, u64) u64
struct QueryItemFixtureApi { native bool send u64 }
fn (api QueryItemFixtureApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api QueryItemFixtureApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api QueryItemFixtureApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { QueryItemFixtureSend(voidptr(api.send))(object, api.selector(name), a, b) }
}
fn (api QueryItemFixtureApi) string(value string) u64 {
	allocated := api.message(api.cls('NSString'), c'alloc', 0, 0)
	initialized := unsafe { QueryItemFixtureBytes(voidptr(api.send))(allocated, api.selector(c'initWithBytes:length:encoding:'), u64(value.str), u64(value.len), 4) }
	return api.message(initialized, c'autorelease', 0, 0)
}
fn (api QueryItemFixtureApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0)) }
fn (api QueryItemFixtureApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0) }
fn (api QueryItemFixtureApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api QueryItemFixtureApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api QueryItemFixtureApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api QueryItemFixtureApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api QueryItemFixtureApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api QueryItemFixtureApi) mutable_string(value string) u64 {
	return api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0), c'initWithString:', api.string(value), 0)
}
fn (api QueryItemFixtureApi) item(name u64, value u64) u64 { return api.message(api.cls('NSURLQueryItem'), c'queryItemWithName:value:', name, value) }
fn query_item_fixture_metadata(api QueryItemFixtureApi) {
	cls := api.cls('NSURLQueryItem'); assert cls != 0
	$if macos { if api.native { assert C.class_getInstanceSize(voidptr(cls)) == 24 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject') } }
	if !api.native { assert objc_class_size(cls) == 24 && objc_class_parent(cls) == api.cls('NSObject') }
	for i, name in ['_name', '_value']! {
		$if macos { if api.native {
			ivar := C.class_getInstanceVariable(voidptr(cls), name.str); assert ivar != unsafe { nil }
			assert C.ivar_getOffset(ivar) == 8 + i * 8 && unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == '@"NSString"'
		} }
		if !api.native { ivar := objc_find_ivar(cls, name.str); assert ivar != 0; assert objc_ivar_offset(ivar) == 8 + i * 8 && ctext(u64(objc_ivar_types(ivar))) == '@"NSString"' }
	}
	for name, types in {'queryItemWithName:value:': '@32@0:8@16@24', 'initWithName:value:': '@32@0:8@16@24', 'init': '@16@0:8', 'name': '@16@0:8', 'value': '@16@0:8', 'copy': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16'} {
		meta := name == 'queryItemWithName:value:'; mut actual := ''
		$if macos { if api.native {
			method := if meta { C.class_getClassMethod(voidptr(cls), voidptr(api.selector(name.str))) } else { C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(name.str))) }
			assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
		} }
		if !api.native { method := if meta { objc_class_method(cls, u64(name.str)) } else { objc_instance_method(cls, u64(name.str)) }; assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == types, name + ': ' + actual
	}
}
fn query_item_fixture_expect(api QueryItemFixtureApi, object u64, name string, value string, nil_value bool) {
	assert object != 0 && api.message(object, c'isKindOfClass:', api.cls('NSURLQueryItem'), 0) != 0
	assert api.text(api.message(object, c'name', 0, 0)) == name
	if nil_value { assert api.message(object, c'value', 0, 0) == 0 } else { assert api.text(api.message(object, c'value', 0, 0)) == value }
}
fn query_item_fixture_shared(api QueryItemFixtureApi) {
	pool := api.pool(); query_item_fixture_metadata(api); cls := api.cls('NSURLQueryItem')
	for construction in [c'new', c'alloc']! {
		mut object := api.message(cls, construction, 0, 0)
		if construction == c'alloc' { object = api.message(object, c'init', 0, 0) }
		query_item_fixture_expect(api, object, '', '', true); api.release(object)
	}
	for i, name in ['', 'plain', 'A & B=+#/%?😀 café é']! {
		for nil_value in [false, true]! {
			value := if nil_value { u64(0) } else { api.string(['', 'value', 'literal+%2F &=#?😀']![i]) }
			object := api.item(api.string(name), value)
			query_item_fixture_expect(api, object, name, ['', 'value', 'literal+%2F &=#?😀']![i], nil_value)
			initialized := api.message(api.message(cls, c'alloc', 0, 0), c'initWithName:value:', api.string(name), value)
			query_item_fixture_expect(api, initialized, name, ['', 'value', 'literal+%2F &=#?😀']![i], nil_value); api.release(initialized)
			for selector in [c'copy', c'copyWithZone:']! {
				copy := api.message(object, selector, 0, 0); assert copy != object
				query_item_fixture_expect(api, copy, name, ['', 'value', 'literal+%2F &=#?😀']![i], nil_value); api.release(copy)
			}
		}
	}
	query_item_fixture_expect(api, api.item(0, 0), '', '', true)
	query_item_fixture_expect(api, api.item(0, api.string('')), '', '', false)
	limit := 'x'.repeat(65536); query_item_fixture_expect(api, api.item(api.string(limit), api.string(limit)), limit, limit, false)
	// Embedded zero bytes belong to the pair; a C string comparison would hide
	// truncation. Check the public UTF8 pointer over the known byte lengths.
	zero_name := 'a\x00b'; zero_value := '\x00v'; zero_item := api.item(api.string(zero_name), api.string(zero_value))
	for object in [zero_item, api.message(zero_item, c'copy', 0, 0)]! {
		for i, selector in [c'name', c'value']! {
			field := api.message(object, selector, 0, 0); expected := if i == 0 { zero_name } else { zero_value }
			assert api.message(field, c'length', 0, 0) == u64(expected.len)
			assert unsafe { tos(&u8(api.message(field, c'UTF8String', 0, 0)), expected.len) } == expected
		}
		if object != zero_item { api.release(object) }
	}
	// Mutable caller strings can be changed and disposed after construction.
	inner := api.pool(); name := api.mutable_string('a mutable original query item name'); value := api.mutable_string('a mutable original query item value')
	mut weak_name := u64(0); mut weak_value := u64(0); api.weak(unsafe { &weak_name }, name); api.weak(unsafe { &weak_value }, value)
	item := api.retain(api.item(name, value)); copy := api.message(item, c'copy', 0, 0); assert copy != item
	api.message(name, c'setString:', api.string('changed name'), 0); api.message(value, c'setString:', api.string('changed value'), 0)
	api.release(name); api.release(value); api.drain(inner)
	assert weak_name == 0 && weak_value == 0
	query_item_fixture_expect(api, item, 'a mutable original query item name', 'a mutable original query item value', false)
	query_item_fixture_expect(api, copy, 'a mutable original query item name', 'a mutable original query item value', false)
	retained_name := api.retain(api.message(copy, c'name', 0, 0)); retained_value := api.retain(api.message(copy, c'value', 0, 0))
	api.release(item); api.release(copy); api.drain(pool)
	assert api.text(retained_name) == 'a mutable original query item name' && api.text(retained_value) == 'a mutable original query item value'
	api.release(retained_name); api.release(retained_value); api.destroy_weak(unsafe { &weak_name }); api.destroy_weak(unsafe { &weak_value })
}

fn query_item_runtime_api() QueryItemFixtureApi { return QueryItemFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
__global query_item_fixture_mode = ''
__global query_item_fixture_fired = false
__global query_item_fixture_string_calls = 0
__global query_item_fixture_fail_at = 0
__global query_item_fixture_name = u64(0)
__global query_item_fixture_value = u64(0)
__global query_item_fixture_source = u64(0)
__global query_item_fixture_weak_name = u64(0)
__global query_item_fixture_weak_value = u64(0)
__global query_item_fixture_weak_source = u64(0)
__global query_item_fixture_weak_result = u64(0)
__global query_item_fixture_weak_property = u64(0)
fn query_item_fixture_worker() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if query_item_fixture_name != 0 { objc_release(query_item_fixture_name) }
	if query_item_fixture_value != 0 { objc_release(query_item_fixture_value) }
	if query_item_fixture_source != 0 { objc_release(query_item_fixture_source) }
}
fn query_item_fixture_constructor(object u64, selector u64) u64 {
	if query_item_fixture_mode == '' || query_item_fixture_fired { return object }
	string_mode := query_item_fixture_mode in ['string-release-inputs', 'string-fail', 'receiver-release', 'receiver-release-fail', 'dispose-initializer']!
	if string_mode && read64(object) != ios_runtime.names['NSString'] {
		if query_item_fixture_mode == 'string-fail' && read64(object) == ios_runtime.names['NSURLQueryItem'] { objc_store_weak(unsafe { &query_item_fixture_weak_source }, object) }
		return object
	}
	if query_item_fixture_mode == 'string-fail' {
		query_item_fixture_string_calls++
		objc_store_weak(if query_item_fixture_string_calls == 1 { unsafe { &query_item_fixture_weak_name } } else { unsafe { &query_item_fixture_weak_value } }, object)
		if query_item_fixture_string_calls != query_item_fixture_fail_at { return object }
	}
	query_item_fixture_fired = true
	if query_item_fixture_mode in ['release-inputs', 'copy-release', 'string-release-inputs', 'receiver-release', 'receiver-release-fail']! { worker := spawn query_item_fixture_worker(); worker.wait() }
	if query_item_fixture_mode in ['string-fail', 'receiver-release-fail']! { return 0 }
	if query_item_fixture_mode == 'fail' {
		objc_store_weak(unsafe { &query_item_fixture_weak_result }, object)
		property := objc_new(ios_runtime.names['NSObject']); obj_header(object).fields[3] = property
		objc_store_weak(unsafe { &query_item_fixture_weak_property }, property)
		return 0
	}
	if query_item_fixture_mode == 'constructor-isa' { objc_set_class(object, ios_runtime.names['NSObject']) }
	if query_item_fixture_mode == 'constructor-storage' { obj_header(object).url_query_item_initialized = true }
	if query_item_fixture_mode == 'dispose-initializer' { objc_destruct_instance(query_item_fixture_source) }
	return object
}
fn query_item_fixture_hook(cls u64) { assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(query_item_fixture_constructor) }), c'@16@0:8') }
fn query_item_fixture_runtime_lifetimes(api QueryItemFixtureApi) {
	pool := api.pool(); cls := api.cls('NSURLQueryItem'); library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSURLQueryItem') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSURLQueryItem') or { panic(err) } == read64(cls)
	image_name := 'image query name'.clone(); image_value := 'image query value'.clone()
	mut image_name_record := [api.cls('NSString'), u64(0x7c8), u64(image_name.str), u64(image_name.len)]!
	mut image_value_record := [api.cls('NSString'), u64(0x7c8), u64(image_value.str), u64(image_value.len)]!
	image_name_address := u64(unsafe { &image_name_record[0] }); image_value_address := u64(unsafe { &image_value_record[0] })
	ios_runtime.constants[image_name_address] = true; ios_runtime.constants[image_value_address] = true
	image_item := api.item(image_name_address, image_value_address)
	ios_runtime.constants.delete(image_name_address); ios_runtime.constants.delete(image_value_address)
	unsafe { image_name.free(); image_value.free() }
	query_item_fixture_expect(api, image_item, 'image query name', 'image query value', false)
	mut guarded := [5]u64{}; guarded[0] = 0x1122334455667788; guarded[4] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	assert api.message(caller, c'initWithName:value:', api.string('caller'), api.string('storage')) == caller
	query_item_fixture_expect(api, caller, 'caller', 'storage', false)
	objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[4] == 0x8877665544332211
	for _ in 0 .. 32 {
		object := objc_retain(api.item(api.string('owned name'), api.string('owned value')))
		objc_set_class(object, api.cls('NSObject')); objc_release(object)
	}
	// Capture input bytes before destination constructors may free both inputs.
	name := owned_string('name before constructor'); value := owned_string('value before constructor')
	objc_store_weak(unsafe { &query_item_fixture_weak_name }, name); objc_store_weak(unsafe { &query_item_fixture_weak_value }, value)
	query_item_fixture_name = name; query_item_fixture_value = value; query_item_fixture_mode = 'release-inputs'; query_item_fixture_fired = false; query_item_fixture_hook(cls)
	item := api.item(name, value); query_item_fixture_mode = ''; query_item_fixture_name = 0; query_item_fixture_value = 0
	assert query_item_fixture_fired && query_item_fixture_weak_name == 0 && query_item_fixture_weak_value == 0
	query_item_fixture_expect(api, item, 'name before constructor', 'value before constructor', false)
	objc_destroy_weak(unsafe { &query_item_fixture_weak_name }); objc_destroy_weak(unsafe { &query_item_fixture_weak_value })
	// A copy snapshots both fields before a constructor can release its source.
	source := api.message(api.message(cls, c'alloc', 0, 0), c'initWithName:value:', api.string('copied name'), api.string('copied value'))
	objc_store_weak(unsafe { &query_item_fixture_weak_source }, source); query_item_fixture_source = source; query_item_fixture_mode = 'copy-release'; query_item_fixture_fired = false
	copy := api.message(source, c'copy', 0, 0); query_item_fixture_mode = ''; query_item_fixture_source = 0
	assert query_item_fixture_fired && query_item_fixture_weak_source == 0; query_item_fixture_expect(api, copy, 'copied name', 'copied value', false); objc_release(copy)
	objc_destroy_weak(unsafe { &query_item_fixture_weak_source })
	// Constructor rollback also tears down user properties and caller storage.
	valid := api.message(cls, c'new', 0, 0)
	for operation in 0 .. 3 {
		query_item_fixture_mode = 'fail'; query_item_fixture_fired = false
		result := if operation == 0 { api.item(api.string('rollback'), 0) } else if operation == 1 { api.message(valid, c'copy', 0, 0) } else { objc_construct_instance(cls, caller) }
		assert result == 0 && query_item_fixture_fired && query_item_fixture_weak_result == 0 && query_item_fixture_weak_property == 0
		objc_destroy_weak(unsafe { &query_item_fixture_weak_result }); objc_destroy_weak(unsafe { &query_item_fixture_weak_property })
		assert guarded[0] == 0x1122334455667788 && guarded[4] == 0x8877665544332211
	}
	query_item_fixture_mode = ''; objc_release(valid)
	// A name or value constructor failure consumes an allocated initializer
	// receiver and destroys both temporary strings.
	query_item_fixture_hook(api.cls('NSString'))
	for operation in 0 .. 2 {
		for fail_at in 1 .. 3 {
			before := ios_runtime.objects.len
			input_name := owned_string('rollback input name'); input_value := owned_string('rollback input value')
			mut receiver := u64(0)
			if operation == 1 { receiver = api.message(cls, c'alloc', 0, 0) }
			if receiver != 0 { objc_store_weak(unsafe { &query_item_fixture_weak_source }, receiver) }
			query_item_fixture_mode = 'string-fail'; query_item_fixture_fired = false; query_item_fixture_string_calls = 0; query_item_fixture_fail_at = fail_at
			result := if operation == 0 { api.item(input_name, input_value) } else { api.message(receiver, c'initWithName:value:', input_name, input_value) }
			query_item_fixture_mode = ''
			assert result == 0 && query_item_fixture_fired && query_item_fixture_string_calls == fail_at
			assert query_item_fixture_weak_source == 0 && query_item_fixture_weak_name == 0 && query_item_fixture_weak_value == 0
			objc_destroy_weak(unsafe { &query_item_fixture_weak_source }); objc_destroy_weak(unsafe { &query_item_fixture_weak_name }); objc_destroy_weak(unsafe { &query_item_fixture_weak_value })
			objc_release(input_name); objc_release(input_value)
			assert ios_runtime.objects.len == before
			assert guarded[0] == 0x1122334455667788 && guarded[4] == 0x8877665544332211
		}
	}
	// Input snapshots must already be detached before either string constructor.
	name2 := owned_string('string constructor name'); value2 := owned_string('string constructor value')
	objc_store_weak(unsafe { &query_item_fixture_weak_name }, name2); objc_store_weak(unsafe { &query_item_fixture_weak_value }, value2)
	allocated := api.message(cls, c'alloc', 0, 0)
	query_item_fixture_name = name2; query_item_fixture_value = value2; query_item_fixture_mode = 'string-release-inputs'; query_item_fixture_fired = false
	initialized := api.message(allocated, c'initWithName:value:', name2, value2)
	query_item_fixture_mode = ''; query_item_fixture_name = 0; query_item_fixture_value = 0
	assert query_item_fixture_fired && query_item_fixture_weak_name == 0 && query_item_fixture_weak_value == 0
	query_item_fixture_expect(api, initialized, 'string constructor name', 'string constructor value', false); objc_release(initialized)
	objc_destroy_weak(unsafe { &query_item_fixture_weak_name }); objc_destroy_weak(unsafe { &query_item_fixture_weak_value })
	api.drain(pool)
}
fn test_url_query_item_runtime() {
	for _ in 0 .. 2 {
		query_item_fixture_mode = ''; query_item_fixture_name = 0; query_item_fixture_value = 0; query_item_fixture_source = 0
		objc_start(); api := query_item_runtime_api(); query_item_fixture_shared(api); query_item_fixture_runtime_lifetimes(api)
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0 && ios_runtime.weak.len == 0
		objc_stop(); assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
	}
	println('IOS-URL-QUERY-ITEM: metadata, nil/empty distinctions, literal UTF8/NUL pairs, 65536 byte inputs, mutable snapshots, distinct copies, retained getters, joined-worker constructors, item/string rollback, guarded storage, 32 isa disposal paths and two drained runtimes')
}
fn test_url_query_item_rejections() {
	objc_start(); api := query_item_runtime_api(); cls := api.cls('NSURLQueryItem')
	for selector in [c'mutableCopy', c'mutableCopyWithZone:', c'encodeWithCoder:', c'initWithCoder:', c'isEqual:', c'hash', c'description', c'setName:', c'setValue:']! { assert !objc_responds(cls, selector) }
	modes := ['raw-getter', 'repeat-init', 'subclass', 'caller-subclass', 'spoof', 'isa-change', 'copy-provenance', 'name-type', 'value-type', 'name-class', 'name-custom', 'name-spoof', 'name-isa', 'name-raw', 'name-utf8', 'name-limit', 'value-limit', 'nonzero-zone', 'mutable-copy', 'coding', 'equal', 'hash', 'description', 'setter', 'constructor-storage', 'constructor-isa', 'dispose-initializer', 'receiver-release', 'receiver-release-fail', 'caller-name-failure', 'caller-value-failure']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); item := api.item(api.string('name'), api.string('value')); query_item_fixture_mode = ''; query_item_fixture_fired = false
			match mode {
				'raw-getter' { api.message(api.message(cls, c'alloc', 0, 0), c'name', 0, 0) }
				'repeat-init' { api.message(item, c'init', 0, 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'VinixUnsupportedQueryItem', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut bytes := [3]u64{}; objc_construct_instance(custom, u64(unsafe { &bytes[0] })) } }
				'spoof' { value := objc_new(api.cls('NSObject')); objc_set_class(value, cls); api.message(value, c'name', 0, 0) }
				'isa-change' { objc_set_class(item, api.cls('NSObject')); api.message(item, c'name', 0, 0) }
				'copy-provenance' { objc_set_class(item, api.cls('NSURLRequest')); objc_copy_value(item, false) }
				'name-type', 'value-type' { wrong := objc_new(api.cls('NSObject')); api.item(if mode == 'name-type' { wrong } else { api.string('name') }, if mode == 'value-type' { wrong } else { u64(0) }) }
				'name-class' { api.item(api.cls('NSString'), 0) }
				'name-custom', 'name-spoof', 'name-isa', 'name-raw', 'name-utf8' {
					mut name := if mode == 'name-raw' { objc_allocate(api.cls('NSMutableString')) } else { owned_string('input') }
					if mode == 'name-custom' { custom := objc_allocate_class(api.cls('NSString'), c'VinixUnsupportedQueryString', 0); objc_register_class(custom); objc_set_class(name, custom) }
					if mode == 'name-spoof' { objc_release(name); name = objc_new(api.cls('NSObject')); objc_set_class(name, api.cls('NSString')) }
					if mode == 'name-isa' { objc_set_class(name, api.cls('NSMutableString')) }
					if mode == 'name-utf8' { unsafe { obj_header(name).text[0] = char(0xff) } }
					api.item(name, 0)
				}
				'name-limit', 'value-limit' { large := 'x'.repeat(65537); input := api.string(large); api.item(if mode == 'name-limit' { input } else { u64(0) }, if mode == 'value-limit' { input } else { u64(0) }) }
				'nonzero-zone' { api.message(item, c'copyWithZone:', 1, 0) }
				'mutable-copy', 'coding', 'equal', 'hash', 'description', 'setter' { selector := match mode { 'mutable-copy' { c'mutableCopy' } 'coding' { c'encodeWithCoder:' } 'equal' { c'isEqual:' } 'hash' { c'hash' } 'description' { c'description' } else { c'setName:' } }; api.message(item, selector, item, 0) }
				'constructor-storage', 'constructor-isa' { query_item_fixture_hook(cls); query_item_fixture_mode = mode; api.message(item, c'copy', 0, 0) }
				'dispose-initializer', 'receiver-release', 'receiver-release-fail' { query_item_fixture_hook(api.cls('NSString')); query_item_fixture_source = api.message(cls, c'alloc', 0, 0); query_item_fixture_mode = mode; api.message(query_item_fixture_source, c'initWithName:value:', 0, 0) }
				'caller-name-failure', 'caller-value-failure' {
					mut storage := [3]u64{}; receiver := objc_construct_instance(cls, u64(unsafe { &storage[0] }))
					name := api.string('caller name'); value := api.string('caller value'); query_item_fixture_hook(api.cls('NSString'))
					query_item_fixture_mode = 'string-fail'; query_item_fixture_string_calls = 0; query_item_fixture_fail_at = if mode == 'caller-name-failure' { 1 } else { 2 }
					api.message(receiver, c'initWithName:value:', name, value)
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
	println('IOS-URL-QUERY-ITEM-REJECT:31 raw/reinitialized pairs, custom/spoof/isa storage, invalid string types/domain/limits, nonzero zones, mutable copying, coding, equality/hash/description/setters, constructor changes, lost receiver ownership and caller initializer failure fail explicitly')
}
fn test_url_query_item_native() {
	$if macos { api := QueryItemFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}; assert api.send != 0; query_item_fixture_shared(api); println('IOS-URL-QUERY-ITEM-NATIVE: public metadata, defaults, nil/empty distinctions, literal UTF8/NUL pairs, 65536 byte inputs, copied mutable inputs, distinct copies and retained getter lifetimes') }
}
