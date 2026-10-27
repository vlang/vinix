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
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.getxattr(&char, &char, voidptr, usize, u32, int) i64

type UrlResourceSend = fn (u64, u64, u64, u64, u64) u64
struct UrlResourceApi { native bool send u64 }
fn (a UrlResourceApi) cls(name &char) u64 {
	$if macos { if a.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (a UrlResourceApi) sel(name &char) u64 {
	$if macos { if a.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (a UrlResourceApi) msg(object u64, name &char, x u64, y u64, z u64) u64 {
	return unsafe { UrlResourceSend(voidptr(a.send))(object, a.sel(name), x, y, z) }
}
fn (a UrlResourceApi) string_object(text string) u64 {
	return a.msg(a.cls(c'NSString'), c'stringWithUTF8String:', u64(text.str), 0, 0)
}
fn (a UrlResourceApi) text(object u64) string {
	return ctext(a.msg(object, c'UTF8String', 0, 0, 0))
}
fn (a UrlResourceApi) pool() u64 {
	$if macos { if a.native { return a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (a UrlResourceApi) drain(pool u64) {
	$if macos { if a.native { a.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (a UrlResourceApi) file_url(path string) u64 {
	return a.msg(a.cls(c'NSURL'), c'fileURLWithPath:', a.string_object(path), 0, 0)
}
fn url_resource_attr(path string, excluded bool) {
	mut bytes := [128]u8{}
	mut n := i64(-1)
	$if macos {
		n = C.getxattr(path.str, c'com.apple.metadata:com_apple_backup_excludeItem', unsafe { &bytes[0] }, 128, 0, 0)
	} $else $if linux {
		n = C.syscall(C.SYS_getxattr, path.str, c'user.com.apple.metadata:com_apple_backup_excludeItem', unsafe { &bytes[0] }, 128)
	}
	if excluded {
		assert n == 61
		assert bytes[..int(n)].hex() == '62706c69737430305f1011636f6d2e6170706c652e6261636b75706408000000000000010100000000000000010000000000000000000000000000001c'
	} else {
		assert n == -1
		$if macos { assert unsafe { *C.ios_errno_address() } == C.ENOATTR }
		$if linux { assert unsafe { *C.ios_errno_address() } == C.ENODATA }
	}
}
fn url_resource_error(a UrlResourceApi, error_object u64, url u64, path string) {
	assert error_object != 0 && error_object != 0x12345678
	assert a.text(a.msg(error_object, c'domain', 0, 0, 0)) == 'NSCocoaErrorDomain'
	assert a.msg(error_object, c'code', 0, 0, 0) == 512
	info := a.msg(error_object, c'userInfo', 0, 0, 0)
	assert a.msg(info, c'objectForKey:', a.string_object('NSURL'), 0, 0) == url
	assert a.text(a.msg(info, c'objectForKey:', a.string_object('NSFilePath'), 0, 0)) == path
	underlying := a.msg(info, c'objectForKey:', a.string_object('NSUnderlyingError'), 0, 0)
	assert a.text(a.msg(underlying, c'domain', 0, 0, 0)) == 'NSOSStatusErrorDomain'
	assert a.msg(underlying, c'code', 0, 0, 0) == 100002
}
fn url_resource_shared(a UrlResourceApi) ! {
	root := os.join_path(os.temp_dir(), 'ios-url-resource-' + os.getpid().str() + if a.native { '-native' } else { '-runtime' })
	assert !os.exists(root)
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	os.write_file(root + '/file', 'original')!
	os.mkdir(root + '/directory')!
	os.symlink(root + '/file', root + '/link')!
	os.symlink(root + '/missing', root + '/dangling')!
	pool := a.pool()
	cls := a.cls(c'NSURL')
	selector := a.sel(c'setResourceValue:forKey:error:')
	mut imp := u64(0)
	$if macos { if a.native {
		method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == 'B40@0:8@16@24^@32'
		imp = u64(C.method_getImplementation(method))
	} }
	if !a.native {
		method := objc_instance_method(cls, selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'B40@0:8@16@24^@32'
		assert objc_class_method(cls, selector) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0
	key := if a.native {
		$if macos { read64(u64(C.dlsym(unsafe { voidptr(-2) }, c'NSURLIsExcludedFromBackupKey'))) } $else { u64(0) }
	} else { read64(ns_url_resource_key_symbol('_NSURLIsExcludedFromBackupKey') or { panic('missing resource key') }) }
	for path in [root + '/file', root + '/directory', root + '/link'] {
		url := a.file_url(path)
		assert a.msg(url, c'respondsToSelector:', selector, 0, 0) == 1
		signature := a.msg(url, c'methodSignatureForSelector:', selector, 0, 0)
		assert a.msg(signature, c'numberOfArguments', 0, 0, 0) == 5
		assert a.msg(signature, c'methodReturnLength', 0, 0, 0) == 1
		assert ctext(a.msg(signature, c'getArgumentTypeAtIndex:', 4, 0, 0)) == '^@'
		for flag in [false, true, true, false, false] {
			value := a.msg(a.cls(c'NSNumber'), c'numberWithBool:', u64(flag), 0, 0)
			mut error_object := u64(0x12345678)
			assert a.msg(url, c'setResourceValue:forKey:error:', value, key, u64(unsafe { &error_object })) == 1
			assert error_object == 0x12345678
			url_resource_attr(path, flag)
			// Fresh URLs and a direct IMP must operate on the same filesystem state.
			fresh := a.file_url(path)
			assert unsafe { UrlResourceSend(voidptr(imp))(fresh, selector, value, key, 0) } == 1
			url_resource_attr(path, flag)
		}
	}
	for path in [root + '/missing', root + '/dangling'] {
		for flag in [false, true] {
			inner := a.pool()
			url := a.file_url(path)
			value := a.msg(a.cls(c'NSNumber'), c'numberWithBool:', u64(flag), 0, 0)
			mut error_object := u64(0x12345678)
			assert a.msg(url, c'setResourceValue:forKey:error:', value, key, u64(unsafe { &error_object })) == 0
			assert a.msg(url, c'setResourceValue:forKey:error:', value, key, 0) == 0
			a.msg(error_object, c'retain', 0, 0, 0)
			a.drain(inner)
			url_resource_error(a, error_object, url, path)
			a.msg(error_object, c'release', 0, 0, 0)
		}
	}
	for text in ['', 'YES', 'NO', '0', '1', '  YES', 'false', 'true', '+1', '-1', '0001', '0x1', '0Y', '+YES', '01no', '1.0', '0.1'] {
		flag := text in ['YES', '1', '  YES', 'true', '+1', '-1', '0001', '01no', '1.0']
		value := if text == '' { u64(0) } else { a.string_object(text) }
		assert a.msg(a.file_url(root + '/file'), c'setResourceValue:forKey:error:', value, key, 0) == 1
		url_resource_attr(root + '/file', flag)
	}
	for url in [a.file_url(root + '/missing'), a.file_url(root + '/file'), a.msg(cls, c'URLWithString:', a.string_object('https://example.invalid/file'), 0, 0)] {
		for other in ['NSURLFileSizeKey', 'UnrecognizedResourceKey'] {
			mut error_object := u64(0x12345678)
			assert a.msg(url, c'setResourceValue:forKey:error:', 0, a.string_object(other), u64(unsafe { &error_object })) == 1
			assert error_object == 0x12345678
		}
	}
	http := a.msg(cls, c'URLWithString:', a.string_object('https://example.invalid/file'), 0, 0)
	mut error_object := u64(0x12345678)
	assert a.msg(http, c'setResourceValue:forKey:error:', a.msg(a.cls(c'NSNumber'), c'numberWithBool:', 1, 0, 0), key, u64(unsafe { &error_object })) == 1
	assert error_object == 0x12345678 && os.read_file(root + '/file')! == 'original'
	a.drain(pool)
}
fn test_url_resource_native() {
	$if macos {
		url_resource_shared(UrlResourceApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))})!
		println('IOS-URL-RESOURCE-NATIVE: metadata, IMP, filesystem bytes, symlinks, errors, ownership and ignored keys PASS')
	}
}
fn test_url_resource_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		url_resource_shared(UrlResourceApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})!
		assert ios_runtime.live == 2 && ios_runtime.objects.len == 2
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-URL-RESOURCE: metadata, IMP, filesystem bytes, symlinks, errors, ownership, ignored keys and two balanced lifetimes PASS')
}
