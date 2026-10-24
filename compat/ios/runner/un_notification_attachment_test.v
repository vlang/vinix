// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework UserNotifications
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
fn C.objc_storeWeak(&u64, voidptr) voidptr
type AttachmentSend = fn (u64, u64, u64, u64, u64, u64) u64
struct AttachmentApi { native bool send u64 }
fn attachment_api() AttachmentApi { return AttachmentApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api AttachmentApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api AttachmentApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api AttachmentApi) msg(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { AttachmentSend(voidptr(api.send))(object, api.sel(name), a, b, c, d) }
}
fn (api AttachmentApi) release(object u64) { api.msg(object, c'release', 0, 0, 0, 0) }
fn (api AttachmentApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0, 0) } }
	return objc_pool_push()
}
fn (api AttachmentApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api AttachmentApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api AttachmentApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api AttachmentApi) string(value string, mutable bool) u64 {
	return api.msg(api.msg(api.cls(if mutable { 'NSMutableString' } else { 'NSString' }), c'alloc', 0, 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4, 0)
}
fn (api AttachmentApi) text(object u64) string {
	assert object != 0
	length := api.msg(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0, 0)
	bytes := api.msg(object, c'UTF8String', 0, 0, 0, 0); assert bytes != 0
	return if length == 0 { '' } else { unsafe { tos(&u8(voidptr(bytes)), int(length)) } }
}
fn (api AttachmentApi) url(http bool) u64 {
	text := api.string(if http { 'https://example.invalid/a.png' } else { '/tmp/vinix-attachment.png' }, false)
	url := api.msg(api.cls('NSURL'), if http { c'URLWithString:' } else { c'fileURLWithPath:' }, text, 0, 0, 0)
	api.release(text); return api.msg(url, c'retain', 0, 0, 0, 0)
}
fn (api AttachmentApi) create(identifier u64, url u64, kind u64) u64 {
	return api.msg(api.msg(api.cls('UNNotificationAttachment'), c'alloc', 0, 0, 0, 0), c'initWithIdentifier:URL:type:options:', identifier, url, kind, 0)
}
fn attachment_metadata(api AttachmentApi) {
	cls := api.cls('UNNotificationAttachment'); assert cls != 0
	$if macos { if api.native {
		assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 64
		assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == api.cls('NSObject')
	} }
	if !api.native { assert objc_class_size(cls) == 64 && objc_class_parent(cls) == api.cls('NSObject') }
	for i, key in un_attachment_ivars() {
		expected := un_attachment_ivar_types()[i]
		$if macos { if api.native {
			ivar := C.class_getInstanceVariable(unsafe { voidptr(cls) }, key.str)
			assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == isize(8 + 8 * i)
			assert unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == expected
		} }
		if !api.native { ivar := objc_find_ivar(cls, key.str); assert ivar != 0 && objc_ivar_offset(ivar) == i64(8 + 8 * i) && ctext(u64(objc_ivar_types(ivar))) == expected }
	}
	for selector in ['init', 'initWithIdentifier:URL:type:options:', 'copy', 'copyWithZone:', 'identifier', 'URL', 'type', 'options', 'userInfo']! {
		expected := un_attachment_types('UNNotificationAttachment', false, selector) or { panic(selector) }
		mut actual := ''
		$if macos { if api.native {
			method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(selector.str)) })
			assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
		} }
		if !api.native { method := objc_instance_method(cls, u64(selector.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == expected, selector + ': ' + actual
	}
}
fn attachment_shared(api AttachmentApi) {
	pool := api.pool(); attachment_metadata(api)
	for http in [false, true]! {
		url := api.url(http)
		for value in ['', 'preview', 'é😀', 'a\x00' + 'b']! {
			identifier := api.string(value, true); kind := api.string(value, true)
			object := api.create(identifier, url, kind); assert object != 0
			for item in [identifier, kind]! { replacement := api.string('changed', false); api.msg(item, c'setString:', replacement, 0, 0, 0); api.release(replacement); api.release(item) }
			assert api.text(api.msg(object, c'identifier', 0, 0, 0, 0)) == value
			assert api.text(api.msg(object, c'type', 0, 0, 0, 0)) == value
			assert api.msg(object, c'URL', 0, 0, 0, 0) == url
			assert api.msg(object, c'options', 0, 0, 0, 0) == 0 && api.msg(object, c'userInfo', 0, 0, 0, 0) == 0
			for selector in [c'copy', c'copyWithZone:']! { assert api.msg(object, selector, 0, 0, 0, 0) == object; api.release(object) }
			if !api.native { for offset := u64(8); offset < 64; offset += 8 { assert read64(object + offset) == if offset == 32 { api.msg(object, c'identifier', 0, 0, 0, 0) } else if offset == 40 { url } else if offset == 48 { api.msg(object, c'type', 0, 0, 0, 0) } else { u64(0) } } }
			api.release(object)
		}
		first := api.create(0, url, 0); second := api.create(0, url, 0)
		a := api.text(api.msg(first, c'identifier', 0, 0, 0, 0)); b := api.text(api.msg(second, c'identifier', 0, 0, 0, 0))
		assert a.len == 36 && a != b
		for i, byte in a.bytes() { assert if i in [8, 13, 18, 23]! { byte == `-` } else { byte.is_hex_digit() } }
		assert api.text(api.msg(first, c'type', 0, 0, 0, 0)) == 'public.item'
		api.release(first); api.release(second); api.release(url)
	}
	api.pop(pool)
	// Drain autoreleased property reads before testing final ownership.
	inner := api.pool(); url := api.url(false); object := api.create(0, url, 0)
	mut weak_url := u64(0); mut weak_id := u64(0); mut weak_type := u64(0)
	api.weak(unsafe { &weak_url }, url); api.weak(unsafe { &weak_id }, api.msg(object, c'identifier', 0, 0, 0, 0)); api.weak(unsafe { &weak_type }, api.msg(object, c'type', 0, 0, 0, 0))
	copy := api.msg(object, c'copy', 0, 0, 0, 0); api.release(object); api.release(url); api.pop(inner)
	assert weak_url != 0 && weak_id != 0 && weak_type != 0
	api.release(copy); assert weak_url == 0 && weak_id == 0
	// Native public.item may be an immortal constant string.
	if !api.native { assert weak_type == 0 }
	api.weak_destroy(unsafe { &weak_url }); api.weak_destroy(unsafe { &weak_id }); api.weak_destroy(unsafe { &weak_type })
}

__global attachment_callback_mode = ''
__global attachment_callback_count = 0
__global attachment_callback_id = u64(0)
__global attachment_callback_type = u64(0)
__global attachment_callback_url = u64(0)
__global attachment_callback_destination = u64(0)
fn attachment_worker() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	api := attachment_api()
	for source in [attachment_callback_id, attachment_callback_type]! {
		if source != 0 { replacement := api.string('callback mutation', false); api.msg(source, c'setString:', replacement, 0, 0, 0); api.release(replacement); api.release(source) }
	}
	if attachment_callback_url != 0 { api.release(attachment_callback_url) }
}
fn attachment_constructor(object u64, _selector &char) u64 {
	if attachment_callback_mode == '' { return object }
	attachment_callback_count++
	if attachment_callback_count == 1 {
		match attachment_callback_mode {
			'isa' { objc_set_class(attachment_callback_destination, ios_runtime.names['NSObject']) }
			'body' { unsafe { *(&u64(attachment_callback_destination + 16)) = u64(1) << 40 } }
			'state' { obj_header(attachment_callback_destination).un_attachment_initialized = true }
			'busy' { obj_header(attachment_callback_destination).un_attachment_initializing = false }
			'destroy' { objc_destruct_instance(attachment_callback_destination) }
			'reinit' { un_attachment_initialize(attachment_callback_destination, 0, attachment_callback_url, 0, 0) }
			else { mode := attachment_callback_mode; attachment_callback_mode = ''; worker := spawn attachment_worker(); worker.wait(); attachment_callback_mode = mode }
		}
	}
	if (attachment_callback_mode == 'fail-first' && attachment_callback_count == 1) || (attachment_callback_mode == 'fail-second' && attachment_callback_count == 2) { return 0 }
	return object
}
fn attachment_override(_object u64, _selector &char) u64 { return 99 }
fn attachment_runtime(api AttachmentApi) {
	cls := api.cls('UNNotificationAttachment'); library := '/System/Library/Frameworks/UserNotifications.framework/UserNotifications'
	assert runtime_symbol(library, '_OBJC_CLASS_$_UNNotificationAttachment') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_UNNotificationAttachment') or { panic(err) } == read64(cls)
	assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(attachment_constructor) }), c'@16@0:8')
	for mode in ['success', 'fail-first', 'fail-second']! {
		pool := api.pool(); before := ios_runtime.live
		identifier := api.string('before id', true); kind := api.string('before type', true); url := api.url(false)
		object := objc_allocate(cls); mut weak := u64(0); api.weak(unsafe { &weak }, object)
		attachment_callback_id = identifier; attachment_callback_type = kind; attachment_callback_url = url; attachment_callback_destination = object
		attachment_callback_count = 0; attachment_callback_mode = mode
		result := un_attachment_initialize(object, identifier, url, kind, 0); attachment_callback_mode = ''
		attachment_callback_id = 0; attachment_callback_type = 0; attachment_callback_url = 0
		if mode == 'success' { assert result == object && weak == object; assert api.text(api.msg(object, c'identifier', 0, 0, 0, 0)) == 'before id' && api.text(api.msg(object, c'type', 0, 0, 0, 0)) == 'before type'; assert api.msg(object, c'URL', 0, 0, 0, 0) == url; api.release(object) } else { assert result == 0 }
		assert weak == 0; api.weak_destroy(unsafe { &weak }); api.pop(pool); assert ios_runtime.live == before
	}
	pool := api.pool(); url := api.url(false)
	object := api.create(0, url, 0)
	for selector in [c'mutableCopy', c'supportsSecureCoding', c'initWithCoder:', c'encodeWithCoder:', c'description', c'hash', c'isEqual:', c'family', c'enterSecurityScope']! { assert objc_instance_method(cls, u64(selector)) == 0 && !objc_responds(object, selector) }
	assert objc_copy_value(object, false) == object; api.release(object)
	mut weak := u64(0); api.weak(unsafe { &weak }, api.msg(object, c'identifier', 0, 0, 0, 0))
	objc_set_class(object, api.cls('NSObject')); api.release(object); assert weak == 0; api.weak_destroy(unsafe { &weak })
	mut guarded := [10]u64{}; guarded[0] = 0x1122334455667788; guarded[9] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	assert un_attachment_initialize(caller, 0, url, 0, 0) == caller
	assert objc_destruct_instance(caller) == caller && caller !in ios_runtime.objects
	assert guarded[0] == 0x1122334455667788 && guarded[9] == 0x8877665544332211
	assert objc_add_method(cls, u64(c'description'), u64(unsafe { voidptr(attachment_override) }), c'@16@0:8')
	overridden := api.create(0, url, 0); assert objc_responds(overridden, c'description') && api.msg(overridden, c'description', 0, 0, 0, 0) == 99
	api.release(overridden); api.release(url); api.pop(pool)
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
}
fn test_un_notification_attachment() {
	$if macos {
		native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }
		attachment_shared(AttachmentApi{true, u64(native_send)})
		println('IOS-UN-ATTACHMENT-NATIVE: layout, encodings, UTF8 snapshots, UUID defaults, retained URLs and immutable copies PASS')
	}
	for _ in 0 .. 2 { objc_start(); system_data_start()!; api := attachment_api(); attachment_shared(api); attachment_runtime(api); objc_stop(); assert ios_runtime.live == 0; system_data_stop() }
	println('IOS-UN-ATTACHMENT: native parity, reentrant and failed constructors, caller storage, isa cleanup, associated copies, native overrides and two balanced lifetimes PASS')
}
fn test_un_notification_attachment_rejections() {
	objc_start(); system_data_start()!; api := attachment_api()
	modes := ['raw', 'raw-copy', 'new', 'init', 'spoof', 'isa', 'raw-isa', 'body', 'padding', 'identifier', 'copy-zone', 'subclass', 'caller-subclass', 'wrong-string', 'raw-string', 'oversize', 'invalid-utf8', 'nil-url', 'wrong-url', 'raw-url', 'url-isa', 'url-field', 'options', 'reinit', 'constructor-isa', 'constructor-body', 'constructor-state', 'constructor-busy', 'constructor-destroy', 'constructor-reinit', 'caller-failure', 'mutableCopy', 'encodeWithCoder:', 'description', 'family', 'attachmentWithIdentifier:URL:options:error:', 'enterSecurityScope', '_encodableURL', 'initWithIdentifier:URL:type:options:userInfo:']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			cls := api.cls('UNNotificationAttachment'); url := api.url(false); object := api.create(0, url, 0)
			match mode {
				'raw', 'raw-copy' { api.msg(objc_allocate(cls), if mode == 'raw' { c'identifier' } else { c'copy' }, 0, 0, 0, 0) }
				'new' { api.msg(cls, c'new', 0, 0, 0, 0) }
				'init' { api.msg(object, c'init', 0, 0, 0, 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'identifier', 0, 0, 0, 0) }
				'isa', 'raw-isa' { if mode == 'isa' { objc_set_class(object, api.cls('NSObject')) } else { unsafe { *(&u64(object)) = api.cls('NSObject') } }; api.msg(object, c'identifier', 0, 0, 0, 0) }
				'body', 'padding', 'identifier' { offset := if mode == 'body' { 8 } else if mode == 'padding' { 16 } else { 32 }; unsafe { *(&u64(object + u64(offset))) = u64(1) << 40 }; api.msg(object, c'identifier', 0, 0, 0, 0) }
				'copy-zone' { api.msg(object, c'copyWithZone:', 1, 0, 0, 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'UnsupportedAttachment', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut storage := [8]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } }
				'wrong-string', 'raw-string', 'oversize', 'invalid-utf8' { value := match mode { 'wrong-string' { objc_new(api.cls('NSObject')) } 'raw-string' { objc_allocate(api.cls('NSMutableString')) } 'oversize' { api.string('x'.repeat(65537), false) } else { owned_string('\xff') } }; api.create(value, url, 0) }
				'nil-url', 'wrong-url', 'raw-url' { value := if mode == 'nil-url' { u64(0) } else if mode == 'wrong-url' { objc_new(api.cls('NSObject')) } else { objc_allocate(api.cls('NSURL')) }; api.create(0, value, 0) }
				'url-isa', 'url-field' { if mode == 'url-isa' { objc_set_class(url, api.cls('NSObject')) } else { obj_header(url).fields[0] = 1 }; api.msg(object, c'URL', 0, 0, 0, 0) }
				'options' { un_attachment_initialize(objc_allocate(cls), 0, url, 0, objc_new(api.cls('NSObject'))) }
				'reinit' { un_attachment_initialize(object, 0, url, 0, 0) }
				'caller-failure' { mut storage := [8]u64{}; caller := objc_construct_instance(cls, u64(unsafe { &storage[0] })); assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(attachment_constructor) }), c'@16@0:8'); attachment_callback_mode = 'fail-first'; attachment_callback_count = 0; un_attachment_initialize(caller, 0, url, 0, 0) }
				else {
					if mode.starts_with('constructor-') {
						assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(attachment_constructor) }), c'@16@0:8')
						attachment_callback_destination = objc_allocate(cls); attachment_callback_url = url; attachment_callback_count = 0; attachment_callback_mode = mode.all_after('constructor-'); un_attachment_initialize(attachment_callback_destination, 0, url, 0, 0)
					} else { api.msg(if mode.starts_with('attachmentWith') { cls } else { object }, mode.str, 0, 0, 0, 0) }
				}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-UN-ATTACHMENT-REJECT: ' + modes.len.str() + ' invalid values, provenance, constructors, copies and unsupported API cases PASS')
}
