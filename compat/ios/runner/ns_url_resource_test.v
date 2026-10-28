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
	// Compare against Foundation on the host's normal filesystem. The HFS RAM
	// volume also caches symlink metadata independently of the target URL.
	root := os.join_path(if a.native { '/tmp' } else { os.temp_dir() }, 'ios-url-resource-' + os.getpid().str() + if a.native { '-native' } else { '-runtime' })
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
			a.msg(url, c'removeAllCachedResourceValues', 0, 0, 0)
			value := a.msg(a.cls(c'NSNumber'), c'numberWithBool:', u64(flag), 0, 0)
			mut error_object := u64(0x12345678)
			assert a.msg(url, c'setResourceValue:forKey:error:', value, key, u64(unsafe { &error_object })) == 1
			assert error_object == 0x12345678
			url_resource_attr(path, flag)
			// Fresh URLs and a direct IMP must operate on the same filesystem state.
			fresh := a.file_url(path)
			a.msg(fresh, c'removeAllCachedResourceValues', 0, 0, 0)
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
		item := a.file_url(root + '/file')
		a.msg(item, c'removeAllCachedResourceValues', 0, 0, 0)
		assert a.msg(item, c'setResourceValue:forKey:error:', value, key, 0) == 1
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
		url_resource_values_shared(UrlResourceApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))})!
		println('IOS-URL-RESOURCE-VALUES-NATIVE: metadata, IMP, filesystem values, cache invalidation, errors and ownership PASS')
	}
}
fn test_url_resource_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		url_resource_shared(UrlResourceApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})!
		url_resource_values_shared(UrlResourceApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})!
		url_resource_values_concurrent()!
		url_resource_values_reentrant()!
		assert ios_runtime.live == 2 && ios_runtime.objects.len == 2
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	$if !ios_url_resource_values ? {
		println('IOS-URL-RESOURCE: metadata, IMP, filesystem bytes, symlinks, errors, ownership, ignored keys and two balanced lifetimes PASS')
	}
	println('IOS-URL-RESOURCE-VALUES: metadata, IMP, filesystem values, cache invalidation, errors, concurrent publication, reentrant invalidation, isa cleanup and two balanced lifetimes PASS')
}

fn (a UrlResourceApi) resource(url u64, key string) u64 {
	mut value := u64(0x12345678)
	mut error_object := u64(0x12345678)
	assert a.msg(url, c'getResourceValue:forKey:error:', u64(unsafe { &value }), a.string_object(key), u64(unsafe { &error_object })) == 1
	assert value != 0x12345678 && error_object == 0x12345678
	return value
}

fn url_resource_values_shared(a UrlResourceApi) ! {
	root := os.join_path(if a.native { '/tmp' } else { os.temp_dir() }, 'ios-url-resource-values-' + os.getpid().str() + if a.native { '-native' } else { '-runtime' })
	assert !os.exists(root)
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	os.write_file(root + '/file', 'original')!
	os.mkdir(root + '/directory')!
	os.symlink(root + '/file', root + '/link')!
	os.symlink(root + '/missing', root + '/dangling')!
	pool := a.pool()
	cls := a.cls(c'NSURL')
	selector := a.sel(c'getResourceValue:forKey:error:')
	mut imp := u64(0)
	$if macos { if a.native {
		method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
		assert method != unsafe { nil }
		assert ctext(u64(C.method_getTypeEncoding(method))) == 'B40@0:8o^@16@24o^@32'
		imp = u64(C.method_getImplementation(method))
	} }
	if !a.native {
		method := objc_instance_method(cls, selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'B40@0:8o^@16@24o^@32'
		assert objc_class_method(cls, selector) == 0
		imp = objc_method_imp(method)
	}
	url := a.file_url(root + '/file')
	assert a.msg(url, c'respondsToSelector:', selector, 0, 0) == 1
	signature := a.msg(url, c'methodSignatureForSelector:', selector, 0, 0)
	assert a.msg(signature, c'numberOfArguments', 0, 0, 0) == 5
	assert a.msg(signature, c'methodReturnLength', 0, 0, 0) == 1
	assert ctext(a.msg(signature, c'getArgumentTypeAtIndex:', 2, 0, 0)) == 'o^@'
	assert ctext(a.msg(signature, c'getArgumentTypeAtIndex:', 4, 0, 0)) == 'o^@'
	for name in [c'removeCachedResourceValueForKey:', c'removeAllCachedResourceValues'] {
		assert a.msg(url, c'respondsToSelector:', a.sel(name), 0, 0) == 1
	}
	for path in [root + '/file', root + '/directory', root + '/link', root + '/dangling'] {
		item := a.file_url(path)
		size := a.resource(item, 'NSURLFileSizeKey')
		if path.ends_with('/directory') { assert size == 0 } else {
			expected := if path.ends_with('/file') { 8 } else if path.ends_with('/link') { (root + '/file').len } else { (root + '/missing').len }
			assert a.msg(size, c'integerValue', 0, 0, 0) == u64(expected)
		}
		regular := a.resource(item, 'NSURLIsRegularFileKey')
		assert a.msg(regular, c'boolValue', 0, 0, 0) == u64(path.ends_with('/file'))
		date := a.resource(item, 'NSURLCreationDateKey')
		$if macos { assert date != 0 && a.msg(date, c'isKindOfClass:', a.cls(c'NSDate'), 0, 0) == 1 }
		$if linux { assert date == 0 }
		total := a.msg(a.resource(item, 'NSURLVolumeTotalCapacityKey'), c'integerValue', 0, 0, 0)
		assert total > 0 && total < u64(0x7fffffffffffffff)
		for key in ['NSURLVolumeAvailableCapacityKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey'] {
			value := a.resource(item, key)
			assert value != 0 && a.msg(value, c'integerValue', 0, 0, 0) <= total
		}
	}
	mut value := u64(0)
	assert unsafe { UrlResourceSend(voidptr(imp))(url, selector, u64(&value), a.string_object('NSURLFileSizeKey'), 0) } == 1
	assert a.msg(value, c'integerValue', 0, 0, 0) == 8
	os.write_file(root + '/file', 'originalchanged')!
	assert a.msg(a.resource(url, 'NSURLFileSizeKey'), c'integerValue', 0, 0, 0) == 8
	assert a.msg(a.resource(a.file_url(root + '/file'), 'NSURLFileSizeKey'), c'integerValue', 0, 0, 0) == 15
	a.msg(url, c'removeCachedResourceValueForKey:', a.string_object('NSURLFileSizeKey'), 0, 0)
	assert a.msg(a.resource(url, 'NSURLFileSizeKey'), c'integerValue', 0, 0, 0) == 15
	os.write_file(root + '/file', 'original')!
	a.msg(url, c'removeAllCachedResourceValues', 0, 0, 0)
	assert a.msg(a.resource(url, 'NSURLFileSizeKey'), c'integerValue', 0, 0, 0) == 8
	for i, flag in [false, true, false] {
		path := root + '/backup-' + i.str()
		os.write_file(path, 'backup')!
		os.symlink(path, path + '-link')!
		item := a.file_url(path)
		number := a.msg(a.cls(c'NSNumber'), c'numberWithBool:', u64(flag), 0, 0)
		assert a.msg(item, c'setResourceValue:forKey:error:', number, a.string_object('NSURLIsExcludedFromBackupKey'), 0) == 1
		url_resource_attr(path, flag)
		url_resource_attr(path + '-link', flag)
		for fresh in [a.file_url(path), a.file_url(path + '-link')] {
			assert a.msg(a.resource(fresh, 'NSURLIsExcludedFromBackupKey'), c'boolValue', 0, 0, 0) == u64(flag)
		}
	}
	if !a.native {
		// Successful writes must retire the receiver's previously cached flag.
		assert a.msg(a.resource(url, 'NSURLIsExcludedFromBackupKey'), c'boolValue', 0, 0, 0) == 0
		for flag in [true, false] {
			number := a.msg(a.cls(c'NSNumber'), c'numberWithBool:', u64(flag), 0, 0)
			assert a.msg(url, c'setResourceValue:forKey:error:', number, a.string_object('NSURLIsExcludedFromBackupKey'), 0) == 1
			assert a.msg(a.resource(url, 'NSURLIsExcludedFromBackupKey'), c'boolValue', 0, 0, 0) == u64(flag)
		}
	}
	for i, payload in ['', 'com.apple.backupd', '<plist version="1.0"><string>other</string></plist>',
		'<plist version="1.0"><string>com.apple.backupd</string></plist>', '<plist version="1.0"><true/></plist>',
		'<plist version="1.0"><array><string>com.apple.backupd</string></array></plist>', 'x'.repeat(4096)] {
		path := root + '/attribute-' + i.str()
		os.write_file(path, 'attribute')!
		$if macos { assert C.setxattr(path.str, c'com.apple.metadata:com_apple_backup_excludeItem', payload.str, usize(payload.len), 0, 0) == 0 }
		$if linux { assert C.syscall(C.SYS_setxattr, path.str, c'user.com.apple.metadata:com_apple_backup_excludeItem', payload.str, payload.len, 0) == 0 }
		assert a.msg(a.resource(a.file_url(path), 'NSURLIsExcludedFromBackupKey'), c'boolValue', 0, 0, 0) == u64(payload.len > 0)
	}
	missing := a.file_url(root + '/missing')
	assert a.msg(a.resource(missing, 'NSURLIsExcludedFromBackupKey'), c'boolValue', 0, 0, 0) == 0
	for key in ['NSURLFileSizeKey', 'NSURLIsRegularFileKey', 'NSURLCreationDateKey', 'NSURLVolumeAvailableCapacityKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey', 'NSURLVolumeTotalCapacityKey'] {
		mut untouched := u64(0x12345678)
		mut error_object := u64(0x12345678)
		assert a.msg(missing, c'getResourceValue:forKey:error:', u64(unsafe { &untouched }), a.string_object(key), u64(unsafe { &error_object })) == 0
		assert untouched == 0x12345678
		assert a.text(a.msg(error_object, c'domain', 0, 0, 0)) == 'NSCocoaErrorDomain'
		assert a.msg(error_object, c'code', 0, 0, 0) == 260
		info := a.msg(error_object, c'userInfo', 0, 0, 0)
		assert a.msg(info, c'objectForKey:', a.string_object('NSURL'), 0, 0) == missing
		assert a.text(a.msg(info, c'objectForKey:', a.string_object('NSFilePath'), 0, 0)) == root + '/missing'
		underlying := a.msg(info, c'objectForKey:', a.string_object('NSUnderlyingError'), 0, 0)
		assert a.text(a.msg(underlying, c'domain', 0, 0, 0)) == 'NSPOSIXErrorDomain'
		assert a.msg(underlying, c'code', 0, 0, 0) == 2
		assert a.msg(missing, c'getResourceValue:forKey:error:', u64(unsafe { &untouched }), a.string_object(key), 0) == 0
		assert untouched == 0x12345678
	}
	// Failed queries are not cached. The same URL must recover after creation.
	os.write_file(root + '/missing', 'new')!
	assert a.msg(a.resource(missing, 'NSURLFileSizeKey'), c'integerValue', 0, 0, 0) == 3
	http := a.msg(cls, c'URLWithString:', a.string_object('https://example.invalid/resource'), 0, 0)
	for item in [url, missing, http] { assert a.resource(item, 'UnknownResourceKey') == 0 }
	for key in ['NSURLFileSizeKey', 'NSURLCreationDateKey', 'NSURLVolumeAvailableCapacityKey'] { assert a.resource(http, key) == 0 }
	// Caller retention must outlive both the URL and the producing pool.
	kept := a.msg(a.resource(url, 'NSURLFileSizeKey'), c'retain', 0, 0, 0)
	a.drain(pool)
	assert a.msg(kept, c'integerValue', 0, 0, 0) == 8
	a.msg(kept, c'release', 0, 0, 0)
}

fn url_resource_values_worker(url u64) u64 {
	api := UrlResourceApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	pool := api.pool()
	defer { api.drain(pool) }
	mut first := u64(0)
	for _ in 0 .. 32 {
		value := api.resource(url, 'NSURLFileSizeKey')
		assert api.msg(value, c'integerValue', 0, 0, 0) == 8
		if first == 0 { first = value } else { assert value == first }
	}
	return first
}

fn url_resource_values_concurrent() ! {
	pool := objc_pool_push()
	defer { objc_pool_pop(pool) }
	path := os.join_path(os.temp_dir(), 'ios-url-resource-concurrent-' + os.getpid().str())
	assert !os.exists(path)
	os.write_file(path, 'original')!
	defer { os.rm(path) or { panic(err) } }
	url := ui_file_url(path)
	mut threads := []thread u64{}
	for _ in 0 .. 8 { threads << spawn url_resource_values_worker(url) }
	values := threads.wait()
	for value in values { assert value == values[0] }
	mut weak := u64(0)
	objc_store_weak(unsafe { &weak }, values[0])
	// The metadata is allocation-owned even if callers change the public isa.
	objc_set_class(url, ios_runtime.names['NSObject'])
	objc_release(url)
	assert weak == 0
	objc_destroy_weak(unsafe { &weak })
}

fn test_url_resource_values_rejections() {
	objc_start()
	for mode in ['nil-output', 'nil-key', 'wrong-key', 'long-path']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			api := UrlResourceApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
			url := ui_file_url(if mode == 'long-path' { '/' + 'x'.repeat(1024) } else { '/tmp/no-resource-output' })
			key := if mode == 'nil-key' { u64(0) } else if mode == 'wrong-key' { objc_new(ios_runtime.names['NSObject']) } else { api.string_object('NSURLFileSizeKey') }
			mut value := u64(0)
			api.msg(url, c'getResourceValue:forKey:error:', if mode == 'nil-output' { u64(0) } else { u64(unsafe { &value }) }, key, 0)
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0; length += int(count)
		}
		C.close(fds[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'nil-output' { 'URL resource value output is required' }
			'long-path' { 'file manager path exceeds the bounded POSIX profile' }
			else { 'URL resource key requires NSString' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	assert ios_runtime.live == 0
	objc_stop()
	println('IOS-URL-RESOURCE-VALUES-REJECT: four output/key/path cases fail explicitly')
}

__global url_resource_constructor_url = u64(0)
__global url_resource_constructor_active = false
fn url_resource_constructor_worker() {
	url := url_resource_constructor_url
	path := string_text(obj_header(url).fields[0])
	os.write_file(path, 'originalchanged') or { panic(err) }
	ns_url_resource_clear(url, 1)
}
fn url_resource_constructor(object u64, selector &char) u64 {
	if url_resource_constructor_active {
		url_resource_constructor_active = false
		worker := spawn url_resource_constructor_worker()
		worker.wait()
	}
	return object
}
fn url_resource_values_reentrant() ! {
	api := UrlResourceApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	path := os.join_path(os.temp_dir(), 'ios-url-resource-reentrant-' + os.getpid().str())
	assert !os.exists(path)
	os.write_file(path, 'original')!
	defer { os.rm(path) or { panic(err) } }
	pool := api.pool()
	url := ui_file_url(path)
	assert objc_add_method(ios_runtime.names['NSNumber'], u64(c'.cxx_construct'), u64(unsafe { voidptr(url_resource_constructor) }), c'@16@0:8')
	url_resource_constructor_url = url
	url_resource_constructor_active = true
	value := api.resource(url, 'NSURLFileSizeKey')
	assert !url_resource_constructor_active
	assert api.msg(value, c'integerValue', 0, 0, 0) == 8
	assert obj_header(url).url_resource_mask == 0
	assert api.msg(api.resource(url, 'NSURLFileSizeKey'), c'integerValue', 0, 0, 0) == 15
	objc_release(url)
	url_resource_constructor_url = 0
	api.drain(pool)
}
