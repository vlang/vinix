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
fn C.class_copyIvarList(voidptr, &u32) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type UserActivityFixtureSend = fn (u64, u64, u64, u64) u64
type UserActivityFixtureBytes = fn (u64, u64, u64, u64, u64) u64
type UserActivityFixtureWeakLoad = fn (&u64) u64

struct UserActivityFixtureApi {
	native bool
	send   u64
}

fn (api UserActivityFixtureApi) cls(name string) u64 {
	$if macos {
		if api.native { return u64(C.objc_getClass(name.str)) }
	}
	return ios_runtime.names[name]
}

fn (api UserActivityFixtureApi) selector(name &char) u64 {
	$if macos {
		if api.native { return u64(C.sel_registerName(name)) }
	}
	return u64(name)
}

fn (api UserActivityFixtureApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { UserActivityFixtureSend(voidptr(api.send))(object, api.selector(name), a, b) }
}

fn (api UserActivityFixtureApi) string(value string) u64 {
	allocated := api.message(api.cls('NSString'), c'alloc', 0, 0)
	initialized := unsafe { UserActivityFixtureBytes(voidptr(api.send))(allocated, api.selector(c'initWithBytes:length:encoding:'), u64(value.str), u64(value.len), 4) }
	return api.message(initialized, c'autorelease', 0, 0)
}

fn (api UserActivityFixtureApi) text(object u64) string {
	assert object != 0
	return ctext(api.message(object, c'UTF8String', 0, 0))
}

fn (api UserActivityFixtureApi) expect_bytes(object u64, value string) {
	assert object != 0
	assert api.message(object, c'lengthOfBytesUsingEncoding:', 4, 0) == u64(value.len)
	assert unsafe { tos(&u8(api.message(object, c'UTF8String', 0, 0)), value.len) } == value
}

fn (api UserActivityFixtureApi) retain(object u64) u64 {
	return api.message(object, c'retain', 0, 0)
}

fn (api UserActivityFixtureApi) release(object u64) { api.message(object, c'release', 0, 0) }

fn (api UserActivityFixtureApi) activity(value u64) u64 {
	return api.message(api.message(api.cls('NSUserActivity'), c'alloc', 0, 0), c'initWithActivityType:', value, 0)
}

fn (api UserActivityFixtureApi) url(value string) u64 {
	return api.message(api.cls('NSURL'), c'URLWithString:', api.string(value), 0)
}

fn (api UserActivityFixtureApi) pool() u64 {
	$if macos {
		if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0) }
	}
	return objc_pool_push()
}

fn (api UserActivityFixtureApi) drain(pool u64) {
	$if macos {
		if api.native {
			api.message(pool, c'drain', 0, 0)
			return
		}
	}
	objc_pool_pop(pool)
}

fn (api UserActivityFixtureApi) weak(slot &u64, object u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { voidptr(object) })
			return
		}
	}
	objc_store_weak(slot, object)
}

fn (api UserActivityFixtureApi) destroy_weak(slot &u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { nil })
			return
		}
	}
	objc_destroy_weak(slot)
}

fn (api UserActivityFixtureApi) weak_alive(slot &u64) bool {
	mut retained := u64(0)
	$if macos {
		if api.native {
			load := C.dlsym(unsafe { voidptr(-2) }, c'objc_loadWeakRetained')
			assert load != unsafe { nil }
			retained = unsafe { UserActivityFixtureWeakLoad(load)(slot) }
		}
	}
	if !api.native { retained = objc_load_weak(slot) }
	alive := retained != 0
	api.release(retained)
	return alive
}

fn user_activity_fixture_metadata(api UserActivityFixtureApi) {
	cls := api.cls('NSUserActivity')
	assert cls != 0
	mut count := u32(99)
	$if macos {
		if api.native {
			assert C.class_getInstanceSize(voidptr(cls)) == 32 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject')
			ivars := C.class_copyIvarList(voidptr(cls), &count)
			assert count == 3
			unsafe { C.free(ivars) }
		}
	}
	if !api.native {
		assert objc_class_size(cls) == 32 && objc_class_parent(cls) == api.cls('NSObject')
		ivars := objc_copy_ivars(cls, &count)
		assert count == 3
		unsafe { C.free(ivars) }
	}
	for i, name in ['_internal', '_delegate', '_frameworkDelegate']! {
		$if macos {
			if api.native {
				ivar := C.class_getInstanceVariable(voidptr(cls), name.str)
				assert ivar != unsafe { nil }
				assert C.ivar_getOffset(ivar) == 8 + i * 8 && unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == '@'
			}
		}
		if !api.native {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0 && objc_ivar_offset(ivar) == 8 + i * 8 && ctext(u64(objc_ivar_types(ivar))) == '@'
		}
	}
	for name, types in {
		'initWithActivityType:': '@24@0:8@16'
		'activityType':          '@16@0:8'
		'webpageURL':            '@16@0:8'
		'setWebpageURL:':        'v24@0:8@16'
		'referrerURL':           '@16@0:8'
	} {
		mut actual := ''
		$if macos {
			if api.native {
				method := C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(name.str)))
				assert method != unsafe { nil }
				actual = unsafe { C.method_getTypeEncoding(method).vstring() }
			}
		}
		if !api.native {
			method := objc_instance_method(cls, u64(name.str))
			assert method != 0
			actual = ctext(u64(objc_method_types(method)))
		}
		assert actual == types, name + ': ' + actual
	}
}

fn user_activity_fixture_shared(api UserActivityFixtureApi) {
	pool := api.pool()
	user_activity_fixture_metadata(api)
	object := api.activity(api.string('NSUserActivityTypeBrowsingWeb'))
	assert object != 0 && api.message(object, c'isKindOfClass:', api.cls('NSUserActivity'), 0) != 0
	assert api.text(api.message(object, c'activityType', 0, 0)) == 'NSUserActivityTypeBrowsingWeb'
	assert api.message(object, c'webpageURL', 0, 0) == 0 && api.message(object, c'referrerURL', 0, 0) == 0
	url := api.url('https://example.invalid/fortnite/continue?value=a%20b#fragment')
	assert url != 0
	api.message(object, c'setWebpageURL:', url, 0)
	assert api.text(api.message(api.message(object, c'webpageURL', 0, 0), c'absoluteString', 0, 0)) == 'https://example.invalid/fortnite/continue?value=a%20b#fragment'
	api.message(object, c'setWebpageURL:', 0, 0)
	assert api.message(object, c'webpageURL', 0, 0) == 0 && api.message(object, c'referrerURL', 0, 0) == 0
	api.release(object)
	for value in ['com.vinix.é.😀', 'a\x00b', 'x'.repeat(65536)] {
		activity := api.activity(api.string(value))
		api.expect_bytes(api.message(activity, c'activityType', 0, 0), value)
		api.release(activity)
	}
	inner := api.pool()
	input := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0), c'initWithString:', api.string('mutable activity type before mutation é😀'), 0)
	mut weak_input := u64(0)
	api.weak(unsafe { &weak_input }, input)
	snapshot := api.activity(input)
	api.message(input, c'setString:', api.string('changed'), 0)
	api.release(input)
	api.drain(inner)
	assert !api.weak_alive(unsafe { &weak_input })
	api.expect_bytes(api.message(snapshot, c'activityType', 0, 0), 'mutable activity type before mutation é😀')
	api.destroy_weak(unsafe { &weak_input })
	for address in ['http://example.invalid/first', 'HTTPS://example.invalid/second']! {
		replacement := api.url(address)
		api.message(snapshot, c'setWebpageURL:', replacement, 0)
		api.message(snapshot, c'setWebpageURL:', replacement, 0)
		assert api.message(snapshot, c'webpageURL', 0, 0) == replacement
		api.expect_bytes(api.message(api.message(snapshot, c'webpageURL', 0, 0), c'absoluteString', 0, 0), address)
		assert api.message(snapshot, c'referrerURL', 0, 0) == 0
	}
	saved_type := api.retain(api.message(snapshot, c'activityType', 0, 0))
	saved_url := api.retain(api.message(snapshot, c'webpageURL', 0, 0))
	api.release(snapshot)
	api.drain(pool)
	last_pool := api.pool()
	api.expect_bytes(saved_type, 'mutable activity type before mutation é😀')
	api.expect_bytes(api.message(saved_url, c'absoluteString', 0, 0), 'HTTPS://example.invalid/second')
	api.release(saved_type)
	api.release(saved_url)
	api.drain(last_pool)
	// Release setup ownership before the getters create +0 values which must
	// survive the activity's last release through their own pool's lifetime.
	setup := api.pool()
	long_type := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
	type_input := unsafe { UserActivityFixtureBytes(voidptr(api.send))(api.message(api.cls('NSString'), c'alloc', 0, 0), api.selector(c'initWithBytes:length:encoding:'), u64(long_type.str), u64(long_type.len), 4) }
	lifetime := api.activity(type_input)
	api.release(type_input)
	url_input := api.string('https://example.invalid/abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
	owned_url := api.message(api.message(api.cls('NSURL'), c'alloc', 0, 0), c'initWithString:', url_input, 0)
	api.message(lifetime, c'setWebpageURL:', owned_url, 0)
	api.release(owned_url)
	api.drain(setup)
	output_pool := api.pool()
	returned_type := api.message(lifetime, c'activityType', 0, 0)
	returned_url := api.message(lifetime, c'webpageURL', 0, 0)
	mut weak_type := u64(0)
	mut weak_url := u64(0)
	mut weak_activity := u64(0)
	api.weak(unsafe { &weak_type }, returned_type)
	api.weak(unsafe { &weak_url }, returned_url)
	api.weak(unsafe { &weak_activity }, lifetime)
	api.release(lifetime)
	assert !api.weak_alive(unsafe { &weak_activity }) && api.weak_alive(unsafe { &weak_type }) && api.weak_alive(unsafe { &weak_url })
	api.expect_bytes(returned_type, long_type)
	assert api.message(returned_url, c'absoluteString', 0, 0) != 0
	api.drain(output_pool)
	assert !api.weak_alive(unsafe { &weak_activity })
	// Native Foundation may keep its own payload references after this pool.
	// The local runtime owns no such cache and must release both properties.
	if !api.native {
		assert !api.weak_alive(unsafe { &weak_type }) && !api.weak_alive(unsafe { &weak_url })
	}
	api.destroy_weak(unsafe { &weak_type })
	api.destroy_weak(unsafe { &weak_url })
	api.destroy_weak(unsafe { &weak_activity })
}

fn user_activity_runtime_api() UserActivityFixtureApi {
	return UserActivityFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
}

__global user_activity_fixture_mode = ''
__global user_activity_fixture_fired = false
__global user_activity_fixture_target = u64(0)
__global user_activity_fixture_input = u64(0)
__global user_activity_fixture_receiver = u64(0)
__global user_activity_fixture_replacement = u64(0)
__global user_activity_fixture_weak_input = u64(0)
__global user_activity_fixture_weak_receiver = u64(0)
__global user_activity_fixture_weak_result = u64(0)
__global user_activity_fixture_weak_property = u64(0)

fn user_activity_fixture_worker() {
	C.ios_objc_initialize_lock()
	C.ios_objc_initialize_unlock()
	if user_activity_fixture_mode == 'replace-reenter' {
		api := user_activity_runtime_api()
		pool := api.pool()
		assert api.message(user_activity_fixture_receiver, c'webpageURL', 0, 0) == user_activity_fixture_replacement
		api.release(user_activity_fixture_receiver)
		api.drain(pool)
	} else {
		if user_activity_fixture_input != 0 { objc_release(user_activity_fixture_input) }
		if user_activity_fixture_receiver != 0 { objc_release(user_activity_fixture_receiver) }
	}
}

fn user_activity_fixture_constructor(object u64, selector u64) u64 {
	if user_activity_fixture_mode == '' || user_activity_fixture_fired || read64(object) != user_activity_fixture_target {
		return object
	}
	user_activity_fixture_fired = true
	if user_activity_fixture_mode in ['release-input', 'receiver-release', 'receiver-release-fail']! {
		worker := spawn user_activity_fixture_worker()
		worker.wait()
	}
	if user_activity_fixture_mode in ['fail', 'receiver-release-fail']! {
		objc_store_weak(unsafe { &user_activity_fixture_weak_result }, object)
		property := objc_new(ios_runtime.names['NSObject'])
		obj_header(object).fields[3] = property
		objc_store_weak(unsafe { &user_activity_fixture_weak_property }, property)
		return 0
	}
	if user_activity_fixture_mode == 'constructor-isa' {
		objc_set_class(object, ios_runtime.names['NSObject'])
	}
	if user_activity_fixture_mode == 'constructor-storage' {
		obj_header(object).user_activity.initialized = true
	}
	if user_activity_fixture_mode == 'constructor-fields' {
		obj_header(user_activity_fixture_receiver).fields[1] = objc_new(ios_runtime.names['NSObject'])
	}
	if user_activity_fixture_mode == 'dispose-initializer' {
		objc_destruct_instance(user_activity_fixture_receiver)
	}
	return object
}

fn user_activity_fixture_url_destructor(object u64, selector &char) {
	if user_activity_fixture_mode != 'replace-reenter' || object != user_activity_fixture_target || user_activity_fixture_fired {
		return
	}
	user_activity_fixture_fired = true
	worker := spawn user_activity_fixture_worker()
	worker.wait()
}

fn user_activity_fixture_activate(mode string, cls u64) {
	user_activity_fixture_mode = mode
	user_activity_fixture_target = cls
	user_activity_fixture_fired = false
}

fn user_activity_fixture_runtime_lifetimes(api UserActivityFixtureApi) {
	pool := api.pool()
	cls := api.cls('NSUserActivity')
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSUserActivity') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSUserActivity') or { panic(err) } == read64(cls)
	image_text := 'image activity é😀'.clone()
	mut image_record := [api.cls('NSString'), u64(0x7c8), u64(image_text.str), u64(image_text.len)]!
	image_address := u64(unsafe { &image_record[0] })
	ios_runtime.constants[image_address] = true
	image_activity := api.activity(image_address)
	ios_runtime.constants.delete(image_address)
	unsafe { image_text.free() }
	api.expect_bytes(api.message(image_activity, c'activityType', 0, 0), 'image activity é😀')
	api.release(image_activity)
	mut guarded := [u64(0x1122334455667788), 0, 0, 0, 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] })
	assert objc_construct_instance(cls, caller) == caller
	assert api.message(caller, c'initWithActivityType:', api.string('caller'), 0) == caller
	api.message(caller, c'setWebpageURL:', api.url('https://example.invalid/caller'), 0)
	assert read64(caller + 8) == 0 && read64(caller + 16) == 0 && read64(caller + 24) == 0
	objc_set_class(caller, api.cls('NSObject'))
	assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[5] == 0x8877665544332211
	for _ in 0 .. 32 {
		object := api.activity(api.string('owned type'))
		api.message(object, c'setWebpageURL:', api.url('https://example.invalid/owned'), 0)
		objc_set_class(object, api.cls('NSObject'))
		api.release(object)
	}
	for name in ['NSUserActivity', 'NSString']! {
		assert objc_add_method(api.cls(name), u64(c'.cxx_construct'), u64(unsafe { voidptr(user_activity_fixture_constructor) }), c'@16@0:8')
	}
	// The initializer detaches input bytes before an NSString constructor can
	// acquire the lock on another thread and release the sole input ownership.
	input := owned_string('input survives constructor é😀')
	receiver := api.message(cls, c'alloc', 0, 0)
	objc_store_weak(unsafe { &user_activity_fixture_weak_input }, input)
	user_activity_fixture_input = input
	user_activity_fixture_activate('release-input', api.cls('NSString'))
	assert api.message(receiver, c'initWithActivityType:', input, 0) == receiver
	user_activity_fixture_mode = ''
	user_activity_fixture_input = 0
	assert user_activity_fixture_fired && user_activity_fixture_weak_input == 0
	api.expect_bytes(api.message(receiver, c'activityType', 0, 0), 'input survives constructor é😀')
	objc_destroy_weak(unsafe { &user_activity_fixture_weak_input })
	api.release(receiver)
	// Generic construction failure removes sidecars, constructor properties,
	// weak references and headers for both allocator and guarded caller storage.
	for operation in 0 .. 2 {
		before := ios_runtime.objects.len
		user_activity_fixture_activate('fail', cls)
		result := if operation == 0 {
			api.message(cls, c'alloc', 0, 0)
		} else {
			objc_construct_instance(cls, caller)
		}
		user_activity_fixture_mode = ''
		assert result == 0 && user_activity_fixture_fired && user_activity_fixture_weak_result == 0 && user_activity_fixture_weak_property == 0
		assert ios_runtime.objects.len == before && guarded[0] == 0x1122334455667788 && guarded[5] == 0x8877665544332211
		objc_destroy_weak(unsafe { &user_activity_fixture_weak_result })
		objc_destroy_weak(unsafe { &user_activity_fixture_weak_property })
	}
	// A failed copied-type constructor consumes the allocated initializer
	// receiver; its temporary property and both weak references disappear.
	failure_input := owned_string('failure input')
	before := ios_runtime.objects.len
	failed_receiver := api.message(cls, c'alloc', 0, 0)
	objc_store_weak(unsafe { &user_activity_fixture_weak_receiver }, failed_receiver)
	user_activity_fixture_activate('fail', api.cls('NSString'))
	assert api.message(failed_receiver, c'initWithActivityType:', failure_input, 0) == 0
	user_activity_fixture_mode = ''
	assert user_activity_fixture_fired && user_activity_fixture_weak_receiver == 0 && user_activity_fixture_weak_result == 0 && user_activity_fixture_weak_property == 0
	assert ios_runtime.objects.len == before
	objc_destroy_weak(unsafe { &user_activity_fixture_weak_receiver })
	objc_destroy_weak(unsafe { &user_activity_fixture_weak_result })
	objc_destroy_weak(unsafe { &user_activity_fixture_weak_property })
	api.release(failure_input)
	// Releasing the previous URL may reenter and drop the receiver's last
	// ownership. The new property must be committed and the lock released first.
	assert objc_add_method(api.cls('NSURL'), u64(c'.cxx_destruct'), u64(unsafe { voidptr(user_activity_fixture_url_destructor) }), c'v16@0:8')
	setup := api.pool()
	activity := api.activity(api.string('replacement callback'))
	old_url := api.url('https://example.invalid/old')
	api.message(activity, c'setWebpageURL:', old_url, 0)
	api.drain(setup)
	new_url := api.url('https://example.invalid/new')
	objc_store_weak(unsafe { &user_activity_fixture_weak_receiver }, activity)
	user_activity_fixture_receiver = activity
	user_activity_fixture_replacement = new_url
	user_activity_fixture_activate('replace-reenter', old_url)
	api.message(activity, c'setWebpageURL:', new_url, 0)
	user_activity_fixture_mode = ''
	user_activity_fixture_receiver = 0
	user_activity_fixture_replacement = 0
	assert user_activity_fixture_fired && user_activity_fixture_weak_receiver == 0
	objc_destroy_weak(unsafe { &user_activity_fixture_weak_receiver })
	api.drain(pool)
}

fn test_user_activity_runtime() {
	for _ in 0 .. 2 {
		user_activity_fixture_mode = ''
		user_activity_fixture_input = 0
		user_activity_fixture_receiver = 0
		objc_start()
		api := user_activity_runtime_api()
		user_activity_fixture_shared(api)
		user_activity_fixture_runtime_lifetimes(api)
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0 && ios_runtime.weak.len == 0
		objc_stop()
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
	}
	println('IOS-USER-ACTIVITY: metadata, Unicode/NUL/65536 byte type snapshots, HTTP(S) URL ownership, +0 getter lifetimes, joined-worker constructors and URL replacement reentry, allocation/initializer rollback, guarded storage, 32 isa disposal paths and two drained runtimes')
}

fn test_user_activity_rejections() {
	objc_start()
	api := user_activity_runtime_api()
	cls := api.cls('NSUserActivity')
	for selector in [c'copy', c'new', c'init', c'becomeCurrent', c'resignCurrent', c'invalidate',
		c'setReferrerURL:', c'encodeWithCoder:']! {
		assert !objc_responds(cls, selector)
	}
	modes := ['raw-getter', 'repeat-init', 'subclass', 'caller-subclass', 'spoof', 'isa-change',
		'copy-provenance', 'tombstone', 'nil-type', 'empty-type', 'type-object', 'type-class',
		'type-custom', 'type-spoof', 'type-isa', 'type-raw', 'type-utf8', 'type-limit', 'url-object',
		'url-class', 'url-custom', 'url-spoof', 'url-isa', 'url-raw', 'url-tombstone', 'url-file',
		'opaque-internal', 'opaque-delegate', 'opaque-framework', 'new', 'init', 'copy', 'coding',
		'equality', 'hash', 'description', 'referrer-set', 'publish', 'resign', 'invalidate',
		'constructor-storage', 'constructor-isa', 'string-constructor-isa', 'constructor-fields',
		'dispose-initializer', 'receiver-release', 'receiver-release-fail', 'caller-init-failure']!
	for mode in modes {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0])
			assert C.dup2(fds[1], 2) == 2
			C.close(fds[1])
			pool := api.pool()
			object := api.activity(api.string('valid type'))
			user_activity_fixture_mode = ''
			user_activity_fixture_fired = false
			match mode {
				'raw-getter' { api.message(objc_allocate(cls), c'activityType', 0, 0) }
				'repeat-init' {
					api.message(object, c'initWithActivityType:', api.string('again'), 0)
				}
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(cls, c'VinixUnsupportedActivity', 0)
					objc_register_class(custom)
					if mode == 'subclass' {
						objc_allocate(custom)
					} else {
						mut bytes := [4]u64{}
						objc_construct_instance(custom, u64(unsafe { &bytes[0] }))
					}
				}
				'spoof' {
					wrong := objc_new(api.cls('NSObject'))
					objc_set_class(wrong, cls)
					api.message(wrong, c'activityType', 0, 0)
				}
				'isa-change' {
					objc_set_class(object, api.cls('NSObject'))
					api.message(object, c'activityType', 0, 0)
				}
				'copy-provenance' {
					objc_set_class(object, api.cls('NSURLRequest'))
					objc_copy_value(object, false)
				}
				'tombstone' {
					mut bytes := [4]u64{}
					caller := objc_construct_instance(cls, u64(unsafe { &bytes[0] }))
					api.message(caller, c'initWithActivityType:', api.string('caller'), 0)
					objc_destruct_instance(caller)
					api.message(caller, c'activityType', 0, 0)
				}
				'nil-type' { api.activity(0) }
				'empty-type' { api.activity(api.string('')) }
				'type-object', 'type-class' {
					api.activity(if mode == 'type-class' {
						api.cls('NSString')
					} else {
						objc_new(api.cls('NSObject'))
					})
				}
				'type-custom', 'type-spoof', 'type-isa', 'type-raw', 'type-utf8' {
					mut input := if mode == 'type-raw' {
						objc_allocate(api.cls('NSMutableString'))
					} else {
						owned_string('input')
					}
					if mode == 'type-custom' {
						custom := objc_allocate_class(api.cls('NSString'), c'VinixUnsupportedActivityString', 0)
						objc_register_class(custom)
						objc_set_class(input, custom)
					}
					if mode == 'type-spoof' {
						objc_release(input)
						input = objc_new(api.cls('NSObject'))
						objc_set_class(input, api.cls('NSString'))
					}
					if mode == 'type-isa' { objc_set_class(input, api.cls('NSMutableString')) }
					if mode == 'type-utf8' { unsafe { obj_header(input).text[0] = char(0xff) } }
					api.activity(input)
				}
				'type-limit' { api.activity(api.string('x'.repeat(65537))) }
				'url-object', 'url-class', 'url-custom', 'url-spoof', 'url-isa', 'url-raw',
				'url-tombstone', 'url-file' {
					mut url := if mode == 'url-class' {
						api.cls('NSURL')
					} else if mode == 'url-object' {
						objc_new(api.cls('NSObject'))
					} else if mode == 'url-raw' {
						objc_allocate(api.cls('NSURL'))
					} else if mode == 'url-file' {
						api.url('file:///tmp/activity')
					} else {
						api.url('https://example.invalid/url')
					}
					if mode == 'url-custom' {
						custom := objc_allocate_class(api.cls('NSURL'), c'VinixUnsupportedActivityURL', 0)
						objc_register_class(custom)
						objc_set_class(url, custom)
					}
					if mode == 'url-spoof' {
						url = objc_new(api.cls('NSObject'))
						objc_set_class(url, api.cls('NSURL'))
					}
					if mode == 'url-isa' { objc_set_class(url, api.cls('NSObject')) }
					if mode == 'url-tombstone' {
						mut bytes := [16]u64{}
						url = objc_construct_instance(api.cls('NSURL'), u64(unsafe { &bytes[0] }))
						objc_destruct_instance(url)
					}
					api.message(object, c'setWebpageURL:', url, 0)
				}
				'opaque-internal', 'opaque-delegate', 'opaque-framework' {
					offset := if mode == 'opaque-internal' {
						8
					} else if mode == 'opaque-delegate' {
						16
					} else {
						24
					}
					unsafe { *(&u64(voidptr(object + u64(offset)))) = 1 }
					api.message(object, c'activityType', 0, 0)
				}
				'new' { api.message(cls, c'new', 0, 0) }
				'init' { api.message(api.message(cls, c'alloc', 0, 0), c'init', 0, 0) }
				'copy' { api.message(object, c'copy', 0, 0) }
				'coding' { api.message(object, c'encodeWithCoder:', 0, 0) }
				'equality' { api.message(object, c'isEqual:', object, 0) }
				'hash' { api.message(object, c'hash', 0, 0) }
				'description' { api.message(object, c'description', 0, 0) }
				'referrer-set' { api.message(object, c'setReferrerURL:', 0, 0) }
				'publish' { api.message(object, c'becomeCurrent', 0, 0) }
				'resign' { api.message(object, c'resignCurrent', 0, 0) }
				'invalidate' { api.message(object, c'invalidate', 0, 0) }
				'constructor-storage', 'constructor-isa', 'string-constructor-isa',
				'constructor-fields', 'dispose-initializer', 'receiver-release',
				'receiver-release-fail', 'caller-init-failure' {
					mut receiver := u64(0)
					mut storage := [4]u64{}
					if mode == 'caller-init-failure' {
						receiver = objc_construct_instance(cls, u64(unsafe { &storage[0] }))
					}
					if mode !in ['constructor-storage', 'constructor-isa', 'caller-init-failure']! {
						receiver = api.message(cls, c'alloc', 0, 0)
					}
					input := api.string('constructor input')
					target := if mode in ['constructor-storage', 'constructor-isa']! {
						cls
					} else {
						api.cls('NSString')
					}
					assert objc_add_method(target, u64(c'.cxx_construct'), u64(unsafe { voidptr(user_activity_fixture_constructor) }), c'@16@0:8')
					user_activity_fixture_receiver = receiver
					user_activity_fixture_activate(if mode == 'caller-init-failure' {
						'fail'
					} else if mode == 'string-constructor-isa' {
						'constructor-isa'
					} else {
						mode
					}, target)
					if receiver == 0 { receiver = api.message(cls, c'alloc', 0, 0) }
					api.message(receiver, c'initWithActivityType:', input, 0)
				}
				else {
					assert false
				}
			}
			api.drain(pool)
			C.exit(73)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-USER-ACTIVITY-REJECT:' + modes.len.str() + ' provenance, raw/reinitialized/opaque storage, invalid types/URLs/limits, unsupported defaults/copy/publication and constructor ownership/state failures are explicit')
}

fn test_user_activity_native() {
	$if macos {
		api := UserActivityFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		user_activity_fixture_shared(api)
		println('IOS-USER-ACTIVITY-NATIVE: public layout/encodings, explicit Unicode/NUL/max type snapshots, HTTP(S) URL copy ownership, nil referrer, retained getters and isolated +0 getter weak lifetimes')
	}
}
