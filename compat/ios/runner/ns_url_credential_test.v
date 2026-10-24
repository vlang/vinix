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

type CredentialFixtureSend = fn (u64, u64, u64, u64, u64) u64
struct CredentialFixtureApi { native bool send u64 }
fn (api CredentialFixtureApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api CredentialFixtureApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api CredentialFixtureApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { CredentialFixtureSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api CredentialFixtureApi) string(value string) u64 {
	allocated := api.message(api.cls('NSString'), c'alloc', 0, 0, 0)
	return api.message(api.message(allocated, c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4), c'autorelease', 0, 0, 0)
}
fn (api CredentialFixtureApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api CredentialFixtureApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api CredentialFixtureApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api CredentialFixtureApi) credential(user u64, password u64, persistence u64) u64 {
	return api.message(api.cls('NSURLCredential'), c'credentialWithUser:password:persistence:', user, password, persistence)
}
fn credential_fixture_metadata(api CredentialFixtureApi) {
	cls := api.cls('NSURLCredential'); assert cls != 0
	$if macos { if api.native {
		assert C.class_getInstanceSize(voidptr(cls)) == 16 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject')
		ivar := C.class_getInstanceVariable(voidptr(cls), c'_internal'); assert ivar != unsafe { nil }
		assert C.ivar_getOffset(ivar) == 8 && unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == '@"NSURLCredentialInternal"'
	} }
	if !api.native {
		assert objc_class_size(cls) == 16 && objc_class_parent(cls) == api.cls('NSObject')
		ivar := objc_find_ivar(cls, c'_internal'); assert ivar != 0
		assert objc_ivar_offset(ivar) == 8 && ctext(u64(objc_ivar_types(ivar))) == '@"NSURLCredentialInternal"'
	}
	for name, types in {'credentialWithUser:password:persistence:': '@40@0:8@16@24Q32', 'initWithUser:password:persistence:': '@40@0:8@16@24Q32', 'user': '@16@0:8', 'password': '@16@0:8', 'hasPassword': 'B16@0:8', 'persistence': 'Q16@0:8', 'identity': '^{__SecIdentity=}16@0:8', 'certificates': '@16@0:8', 'copy': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16'} {
		meta := name == 'credentialWithUser:password:persistence:'; mut actual := ''
		$if macos { if api.native {
			method := if meta { C.class_getClassMethod(voidptr(cls), voidptr(api.selector(name.str))) } else { C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(name.str))) }
			assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
		} }
		if !api.native { method := if meta { objc_class_method(cls, u64(name.str)) } else { objc_instance_method(cls, u64(name.str)) }; assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == types, name + ': ' + actual
	}
}
fn credential_fixture_expect(api CredentialFixtureApi, object u64, user string, password string, nil_user bool, nil_password bool, persistence u64) {
	assert object != 0 && api.message(object, c'isKindOfClass:', api.cls('NSURLCredential'), 0, 0) != 0
	for i, selector in [c'user', c'password']! {
		field := api.message(object, selector, 0, 0, 0); absent := if i == 0 { nil_user } else { nil_password }
		if absent { assert field == 0 } else {
			expected := if i == 0 { user } else { password }; assert field != 0
			pointer := api.message(field, c'UTF8String', 0, 0, 0)
			assert unsafe { tos(&u8(pointer), expected.len) } == expected
			assert unsafe { (&u8(pointer))[expected.len] } == 0
		}
	}
	assert api.message(object, c'hasPassword', 0, 0, 0) == u64(!nil_password)
	assert api.message(object, c'persistence', 0, 0, 0) == persistence
	assert api.message(object, c'identity', 0, 0, 0) == 0 && api.message(object, c'certificates', 0, 0, 0) == 0
}
fn credential_fixture_shared(api CredentialFixtureApi) {
	pool := api.pool(); credential_fixture_metadata(api); cls := api.cls('NSURLCredential')
	for persistence in [u64(0), 1, 2, 3, 99]! {
		for i, value in ['', 'alice', '😀 café é', 'a\x00b']! {
			for nil_user in [false, true]! { for nil_password in [false, true]! {
				user := if nil_user { u64(0) } else { api.string(value) }; password := if nil_password { u64(0) } else { api.string(value) }
				object := api.credential(user, password, persistence)
				credential_fixture_expect(api, object, value, value, nil_user, nil_password, persistence)
				initialized := api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithUser:password:persistence:', user, password, persistence)
				credential_fixture_expect(api, initialized, value, value, nil_user, nil_password, persistence); api.release(initialized)
				for selector in [c'copy', c'copyWithZone:']! { copied := api.message(object, selector, 0, 0, 0); assert copied == object; api.release(copied) }
			} }
		}
	}
	large := 'x'.repeat(65536); credential_fixture_expect(api, api.credential(api.string(large), api.string(large), 2), large, large, false, false, 2)
	user := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0, 0), c'initWithString:', api.string('mutable user'), 0, 0)
	password := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0, 0), c'initWithString:', api.string('mutable password'), 0, 0)
	object := api.message(api.credential(user, password, 3), c'retain', 0, 0, 0)
	api.message(user, c'setString:', api.string('changed user'), 0, 0); api.message(password, c'setString:', api.string('changed password'), 0, 0)
	api.release(user); api.release(password); api.drain(pool)
	credential_fixture_expect(api, object, 'mutable user', 'mutable password', false, false, 3); api.release(object)
}
fn credential_runtime_api() CredentialFixtureApi { return CredentialFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
__global credential_fixture_mode = ''
__global credential_fixture_calls = 0
__global credential_fixture_fail_at = 0
__global credential_fixture_user = u64(0)
__global credential_fixture_password = u64(0)
__global credential_fixture_receiver = u64(0)
fn credential_fixture_worker() {
	// Joining a different thread proves constructors run without the runtime lock.
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if credential_fixture_user != 0 { objc_release(credential_fixture_user) }
	if credential_fixture_password != 0 { objc_release(credential_fixture_password) }
	if credential_fixture_mode == 'receiver-release' { objc_release(credential_fixture_receiver) }
}
fn credential_fixture_constructor(object u64, selector u64) u64 {
	if credential_fixture_mode == '' { return object }
	credential_fixture_calls++
	if credential_fixture_calls == 1 {
		if credential_fixture_mode in ['release-inputs', 'receiver-release']! { worker := spawn credential_fixture_worker(); worker.wait() }
		if credential_fixture_mode == 'dispose-initializer' { objc_destruct_instance(credential_fixture_receiver) }
		if credential_fixture_mode == 'constructor-isa' { objc_set_class(credential_fixture_receiver, ios_runtime.names['NSObject']) }
		if credential_fixture_mode == 'constructor-storage' { unsafe { *(&u64(credential_fixture_receiver + 8)) = 1 } }
	}
	if credential_fixture_mode == 'fail' && credential_fixture_calls == credential_fixture_fail_at { return 0 }
	return object
}
fn credential_fixture_hook() { assert objc_add_method(ios_runtime.names['NSString'], u64(c'.cxx_construct'), u64(unsafe { voidptr(credential_fixture_constructor) }), c'@16@0:8') }
fn credential_fixture_thread(object u64) {
	api := credential_runtime_api(); pool := api.pool()
	for _ in 0 .. 100 { copied := api.message(object, c'copy', 0, 0, 0); assert copied == object; credential_fixture_expect(api, copied, 'thread user', 'thread password', false, false, 2); api.release(copied) }
	api.drain(pool)
}
fn credential_fixture_runtime(api CredentialFixtureApi) {
	pool := api.pool(); cls := api.cls('NSURLCredential'); library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSURLCredential') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSURLCredential') or { panic(err) } == read64(cls)
	for wrong in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '/usr/lib/libobjc.A.dylib', '/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony']! {
		if _ := runtime_symbol(wrong, '_OBJC_CLASS_$_NSURLCredential') { assert false }
	}
	mut guarded := [u64(0x1122334455667788), 0, 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	assert api.message(caller, c'initWithUser:password:persistence:', api.string('caller'), api.string('storage'), 99) == caller
	credential_fixture_expect(api, caller, 'caller', 'storage', false, false, 99)
	objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
	assert guarded[0] == 0x1122334455667788 && guarded[2] == 0 && guarded[3] == 0x8877665544332211
	for _ in 0 .. 32 { object := objc_retain(api.credential(api.string('owned user'), api.string('owned password'), 1)); objc_set_class(object, api.cls('NSObject')); objc_release(object) }
	object := api.credential(api.string('thread user'), api.string('thread password'), 2)
	assert objc_copy_value(object, false) == object; objc_release(object)
	a := spawn credential_fixture_thread(object); b := spawn credential_fixture_thread(object); c := spawn credential_fixture_thread(object); d := spawn credential_fixture_thread(object); a.wait(); b.wait(); c.wait(); d.wait()
	credential_fixture_hook()
	for operation in 0 .. 2 { for fail_at in 1 .. 3 {
		before := ios_runtime.objects.len; user := owned_string('rollback user'); password := owned_string('rollback password')
		receiver := if operation == 0 { u64(0) } else { objc_allocate(cls) }
		credential_fixture_mode = 'fail'; credential_fixture_calls = 0; credential_fixture_fail_at = fail_at
		result := if operation == 0 { api.credential(user, password, 2) } else { api.message(receiver, c'initWithUser:password:persistence:', user, password, 2) }
		credential_fixture_mode = ''; assert result == 0 && credential_fixture_calls == fail_at
		objc_release(user); objc_release(password); assert ios_runtime.objects.len == before
	} }
	user := owned_string('snapshotted user'); password := owned_string('snapshotted password')
	credential_fixture_user = user; credential_fixture_password = password; credential_fixture_calls = 0; credential_fixture_mode = 'release-inputs'
	initialized := api.message(objc_allocate(cls), c'initWithUser:password:persistence:', user, password, 3)
	credential_fixture_mode = ''; credential_fixture_user = 0; credential_fixture_password = 0
	assert credential_fixture_calls == 2; credential_fixture_expect(api, initialized, 'snapshotted user', 'snapshotted password', false, false, 3); objc_release(initialized)
	api.drain(pool)
}
fn test_credential_runtime() {
	for _ in 0 .. 2 { credential_fixture_mode = ''; objc_start(); api := credential_runtime_api(); credential_fixture_shared(api); credential_fixture_runtime(api); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0; objc_stop(); assert ios_runtime.live == 0 }
	println('IOS-CREDENTIAL: native parity, immutable snapshots/copies, callback rollback/reentry, concurrency, guarded storage, isa cleanup and two balanced lifetimes PASS')
}
fn test_credential_rejections() {
	objc_start(); api := credential_runtime_api(); cls := api.cls('NSURLCredential')
	for selector in [c'init', c'initWithTrust:', c'initWithIdentity:certificates:persistence:', c'encodeWithCoder:', c'initWithCoder:', c'mutableCopy', c'isEqual:', c'hash', c'description']! { assert !objc_responds(cls, selector); assert objc_instance_method(cls, u64(selector)) == 0 }
	modes := ['raw-getter', 'default-new', 'repeat-init', 'subclass', 'caller-subclass', 'factory-subclass', 'spoof', 'isa-change', 'raw-isa', 'body-tamper', 'copy-provenance', 'user-type', 'password-type', 'user-class', 'user-custom', 'user-spoof', 'user-isa', 'user-raw', 'user-utf8', 'user-limit', 'password-limit', 'nonzero-zone', 'mutable-copy', 'coding', 'trust', 'identity', 'equal', 'hash', 'description', 'constructor-storage', 'constructor-isa', 'dispose-initializer', 'receiver-release', 'caller-user-failure', 'caller-password-failure']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); pool := api.pool()
			object := api.credential(api.string('user'), api.string('password'), 2); credential_fixture_mode = ''; credential_fixture_calls = 0
			match mode {
				'raw-getter' { api.message(objc_allocate(cls), c'user', 0, 0, 0) }
				'default-new' { objc_new(cls) }
				'repeat-init' { api.message(object, c'initWithUser:password:persistence:', 0, 0, 0) }
				'subclass', 'caller-subclass', 'factory-subclass' { custom := objc_allocate_class(cls, c'VinixUnsupportedCredential', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else if mode == 'factory-subclass' { api.message(custom, c'credentialWithUser:password:persistence:', 0, 0, 0) } else { mut bytes := [2]u64{}; objc_construct_instance(custom, u64(unsafe { &bytes[0] })) } }
				'spoof' { wrong := objc_new(api.cls('NSObject')); objc_set_class(wrong, cls); api.message(wrong, c'user', 0, 0, 0) }
				'isa-change', 'raw-isa', 'body-tamper' { if mode == 'isa-change' { objc_set_class(object, api.cls('NSObject')) } else if mode == 'raw-isa' { unsafe { *(&u64(object)) = api.cls('NSObject') } } else { unsafe { *(&u64(object + 8)) = 1 } }; api.message(object, c'user', 0, 0, 0) }
				'copy-provenance' { objc_set_class(object, api.cls('NSURLRequest')); objc_copy_value(object, false) }
				'user-type', 'password-type' { wrong := objc_new(api.cls('NSObject')); api.credential(if mode == 'user-type' { wrong } else { u64(0) }, if mode == 'password-type' { wrong } else { u64(0) }, 0) }
				'user-class' { api.credential(api.cls('NSString'), 0, 0) }
				'user-custom', 'user-spoof', 'user-isa', 'user-raw', 'user-utf8' {
					mut user := if mode == 'user-raw' { objc_allocate(api.cls('NSMutableString')) } else { owned_string('input') }
					if mode == 'user-custom' { custom := objc_allocate_class(api.cls('NSString'), c'VinixUnsupportedCredentialString', 0); objc_register_class(custom); objc_set_class(user, custom) }
					if mode == 'user-spoof' { objc_release(user); user = objc_new(api.cls('NSObject')); objc_set_class(user, api.cls('NSString')) }
					if mode == 'user-isa' { objc_set_class(user, api.cls('NSMutableString')) }
					if mode == 'user-utf8' { unsafe { obj_header(user).text[0] = char(0xff) } }
					api.credential(user, 0, 0)
				}
				'user-limit', 'password-limit' { input := api.string('x'.repeat(65537)); api.credential(if mode == 'user-limit' { input } else { u64(0) }, if mode == 'password-limit' { input } else { u64(0) }, 0) }
				'nonzero-zone' { api.message(object, c'copyWithZone:', 1, 0, 0) }
				'mutable-copy', 'coding', 'trust', 'identity', 'equal', 'hash', 'description' { selector := match mode { 'mutable-copy' { c'mutableCopy' } 'coding' { c'encodeWithCoder:' } 'trust' { c'initWithTrust:' } 'identity' { c'initWithIdentity:certificates:persistence:' } 'equal' { c'isEqual:' } 'hash' { c'hash' } else { c'description' } }; api.message(object, selector, 0, 0, 0) }
				'constructor-storage', 'constructor-isa', 'dispose-initializer', 'receiver-release', 'caller-user-failure', 'caller-password-failure' {
					mut storage := [2]u64{}; credential_fixture_receiver = if mode.starts_with('caller-') { objc_construct_instance(cls, u64(unsafe { &storage[0] })) } else { objc_allocate(cls) }
					user := api.string('input user'); password := api.string('input password'); credential_fixture_hook()
					credential_fixture_mode = if mode.starts_with('caller-') { 'fail' } else { mode }; credential_fixture_fail_at = if mode == 'caller-password-failure' { 2 } else { 1 }
					api.message(credential_fixture_receiver, c'initWithUser:password:persistence:', user, password, 2)
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
	println('IOS-CREDENTIAL-REJECT: 35 invalid storage, subclasses, strings, unsupported APIs and constructor lifetime violations PASS')
}
fn test_credential_native() {
	$if macos { api := CredentialFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}; assert api.send != 0; credential_fixture_shared(api); println('IOS-CREDENTIAL-NATIVE: layout, encodings, nil/empty/UTF8/NUL passwords, persistence, snapshots and retained self copies PASS') }
}
