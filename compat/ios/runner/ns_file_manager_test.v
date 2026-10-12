// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
#include <sys/stat.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.umask(u32) u32
type FileManagerSend = fn (u64, u64, u64, u64, u64, u64) u64
struct FileManagerApi { native bool send u64 cls u64 strings u64 dictionaries u64 numbers u64 urls u64 }
fn (api FileManagerApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api FileManagerApi) message(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { FileManagerSend(voidptr(api.send))(object, api.selector(name), a, b, c, d) }
}
fn (api FileManagerApi) string(text string) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(text.str), 0, 0, 0) }
fn (api FileManagerApi) text(object u64) string { return ctext(api.message(object, c'UTF8String', 0, 0, 0, 0)) }
fn (api FileManagerApi) release(object u64) { api.message(object, c'release', 0, 0, 0, 0) }
fn (api FileManagerApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0, 0) } }
	return objc_pool_push()
}
fn (api FileManagerApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}
fn (api FileManagerApi) permissions(mode u64) u64 {
	mut values := [1]u64{init: api.message(api.numbers, c'numberWithInteger:', mode, 0, 0, 0)}
	mut keys := [1]u64{init: api.string('NSFilePosixPermissions')}
	return api.message(api.dictionaries, c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &keys[0] }), 1, 0)
}

fn file_manager_cases(api FileManagerApi) ! {
	base := '/tmp/vinix-filemanager-' + os.getpid().str() + '-' + api.native.str()
	assert !os.exists(base); os.mkdir_all(base + '/existing')!
	defer { os.rmdir_all(base) or { panic(err) } }
	os.write_file(base + '/file', 'bytes')!; os.write_file(base + '/space é.txt', 'unicode')!
	os.symlink('file', base + '/file-link')!; os.symlink('existing', base + '/directory-link')!; os.symlink('missing', base + '/broken-link')!
	pool := api.pool()
	manager := api.message(api.cls, c'new', 0, 0, 0, 0)
	shared := api.message(api.cls, c'defaultManager', 0, 0, 0, 0)
	assert shared != 0 && shared != manager && api.message(api.cls, c'defaultManager', 0, 0, 0, 0) == shared;
	assert api.message(manager, c'init', 0, 0, 0, 0) == manager;
	assert api.message(manager, c'delegate', 0, 0, 0, 0) == 0;
	api.message(manager, c'setDelegate:', 0, 0, 0, 0)
	for index, suffix in ['existing', 'file', 'directory-link', 'file-link', 'broken-link', 'missing', 'space é.txt']! {
		path := api.string(base + '/' + suffix)
		mut guarded := [3]u8{init: 0xa5}
		found := api.message(manager, c'fileExistsAtPath:isDirectory:', path, u64(unsafe { &guarded[1] }), 0, 0)
		assert found == u64(index !in [4, 5]!);
		assert found == api.message(manager, c'fileExistsAtPath:', path, 0, 0, 0);
		assert guarded[0] == 0xa5 && guarded[2] == 0xa5;
		assert guarded[1] == if found == 0 { u8(0xa5) } else { u8(index in [0, 2]!) };
		for access_index, selector in [c'isReadableFileAtPath:', c'isWritableFileAtPath:', c'isExecutableFileAtPath:']! {
			result := api.message(manager, selector, path, 0, 0, 0)
			assert result == if access_index == 2 { u64(index in [0, 2]!) } else { found };
		}
	}
	for path in [u64(0), api.string('')]! {
		mut output := u8(0xa5)
		assert api.message(manager, c'fileExistsAtPath:isDirectory:', path, u64(unsafe { &output }), 0, 0) == 0 && output == 0xa5;
	}
	mut retained_error := u64(0)
	for item in ['leaf|0|1|0|0|leaf', 'leaf|1|1|0|0|leaf', 'existing|0|0|516|17|existing', 'existing|1|1|0|0|existing', 'file|0|0|516|17|file', 'file|1|0|516|17|file', 'file/child|1|0|512|20|file', 'broken-link|1|0|512|5|broken-link', 'directory-link|1|1|0|0|directory-link', 'absent/child|0|0|4|2|absent/child', 'parents/child|1|1|0|0|parents/child', 'parents/child|1|1|0|0|parents/child', '|0|0|4|2|', '|1|0|4|2|']! {
		parts := item.split('|')
		path := api.string(if parts[0] == '' { '' } else { base + '/' + parts[0] })
		sentinel := api.string('success must not replace me')
		mut error_object := sentinel
		result := api.message(manager, c'createDirectoryAtPath:withIntermediateDirectories:attributes:error:', path, parts[1].u64(), 0, u64(unsafe { &error_object }))
		assert result == parts[2].u64(), item;
		if result != 0 { assert error_object == sentinel; continue }
		assert error_object != 0 && error_object != sentinel;
		assert api.text(api.message(error_object, c'domain', 0, 0, 0, 0)) == 'NSCocoaErrorDomain';
		assert api.message(error_object, c'code', 0, 0, 0, 0) == parts[3].u64();
		info := api.message(error_object, c'userInfo', 0, 0, 0, 0)
		underlying := api.message(info, c'objectForKey:', api.string('NSUnderlyingError'), 0, 0, 0)
		assert api.text(api.message(underlying, c'domain', 0, 0, 0, 0)) == 'NSPOSIXErrorDomain';
		assert api.message(underlying, c'code', 0, 0, 0, 0) == parts[4].u64();
		error_path := api.message(info, c'objectForKey:', api.string('NSFilePath'), 0, 0, 0)
		assert api.text(error_path) == if parts[5] == '' { '' } else { base + '/' + parts[5] };
		if retained_error == 0 { retained_error = api.message(error_object, c'retain', 0, 0, 0, 0) }
	}
	attributes := api.permissions(0o777)
	mask := C.umask(0o077)
	assert api.message(manager, c'createDirectoryAtPath:withIntermediateDirectories:attributes:error:', api.string(base + '/explicit/child'), 1, attributes, 0) == 1;
	assert api.message(manager, c'createDirectoryAtPath:withIntermediateDirectories:attributes:error:', api.string(base + '/default/child'), 1, 0, 0) == 1;
	C.umask(mask)
	for name in ['explicit', 'explicit/child']! { assert os.stat(base + '/' + name)!.mode & 0o777 == 0o777; }
	for name in ['default', 'default/child']! { assert os.stat(base + '/' + name)!.mode & 0o777 == 0o700; }
	os.chmod(base + '/existing', 0o700)!
	assert api.message(manager, c'createDirectoryAtPath:withIntermediateDirectories:attributes:error:', api.string(base + '/existing'), 1, attributes, 0) == 1;
	assert os.stat(base + '/existing')!.mode & 0o777 == 0o700;
	if C.geteuid() != 0 {
		os.mkdir(base + '/denied')!; os.chmod(base + '/denied', 0)!
		mut denied_error := u64(0)
		result := api.message(manager, c'createDirectoryAtPath:withIntermediateDirectories:attributes:error:', api.string(base + '/denied/child'), 0, 0, u64(unsafe { &denied_error }))
		os.chmod(base + '/denied', 0o700)!
		assert result == 0 && api.message(denied_error, c'code', 0, 0, 0, 0) == 513;
	}
	url := api.message(api.urls, c'fileURLWithPath:', api.string(base + '/url/child'), 0, 0, 0)
	assert api.message(manager, c'createDirectoryAtURL:withIntermediateDirectories:attributes:error:', url, 1, 0, 0) == 1;
	api.release(manager); api.drain(pool)
	assert api.text(api.message(retained_error, c'domain', 0, 0, 0, 0)) == 'NSCocoaErrorDomain';
	assert api.message(retained_error, c'code', 0, 0, 0, 0) == 516;
	api.release(retained_error)
}

fn file_manager_runtime_api() FileManagerApi {
	return FileManagerApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSFileManager'], strings: ios_runtime.names['NSString'], dictionaries: ios_runtime.names['NSDictionary'], numbers: ios_runtime.names['NSNumber'], urls: ios_runtime.names['NSURL']}
}
fn test_file_manager_native() {
	$if macos {
		file_manager_cases(FileManagerApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSFileManager')), strings: u64(C.objc_getClass(c'NSString')), dictionaries: u64(C.objc_getClass(c'NSDictionary')), numbers: u64(C.objc_getClass(c'NSNumber')), urls: u64(C.objc_getClass(c'NSURL'))})!
		println('IOS-FILEMANAGER-NATIVE: singleton, path queries, fourteen directory cases, Cocoa/POSIX error paths, copied errors, umask and file URL creation')
	}
}
fn file_manager_worker(api FileManagerApi, shared u64) {
	for _ in 0 .. 1000 { assert api.message(api.cls, c'defaultManager', 0, 0, 0, 0) == shared; }
}
fn test_file_manager_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := file_manager_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSFileManager')! == api.cls;
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSFileManager')! == read64(api.cls);
		assert objc_class_size(api.cls) == 32 && objc_class_parent(api.cls) == ios_runtime.names['NSObject'];
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:']! {
			assert objc_instance_method(api.cls, u64(selector)) == 0;
		}
		method := objc_instance_method(api.cls, u64(c'createDirectoryAtPath:withIntermediateDirectories:attributes:error:'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'B44@0:8@16B24@28^@36';
		file_manager_cases(api)!
		assert ios_runtime.live == 1;
		shared := api.message(api.cls, c'defaultManager', 0, 0, 0, 0)
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn file_manager_worker(api, shared) }
		workers.wait()
		mut storage := [32]u8{}
		caller := objc_construct_instance(api.cls, u64(unsafe { &storage[0] }))
		assert api.message(caller, c'init', 0, 0, 0, 0) == caller;
		assert objc_destruct_instance(caller) == caller;
		for _ in 0 .. 100 { object := objc_new(api.cls); objc_set_class(object, ios_runtime.names['NSObject']); objc_release(object) }
		assert ios_runtime.live == 1 && ios_runtime.block_refs.len == 0;
		objc_stop(); assert ios_runtime.live == 0;
	}
	println('IOS-FILEMANAGER: real POSIX operations,8,000 concurrent singleton queries, caller storage,100 isa changes per cycle and two zero-live-object shutdowns')
}

fn test_file_manager_rejections() {
	objc_start(); api := file_manager_runtime_api()
	for mode in ['path-type', 'path-length', 'path-nul', 'attributes-type', 'attribute-key', 'permissions-type', 'permissions-value', 'http-url', 'copy', 'delegate']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork(); assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := objc_new(api.cls)
			match mode {
				'path-type' { api.message(object, c'fileExistsAtPath:', objc_new(ios_runtime.names['NSObject']), 0, 0, 0) }
				'path-length' { api.message(object, c'fileExistsAtPath:', owned_string('x'.repeat(1024)), 0, 0, 0) }
				'path-nul' { api.message(object, c'fileExistsAtPath:', owned_string('x\x00y'), 0, 0, 0) }
				'attributes-type' { ns_file_manager_mode(objc_new(ios_runtime.names['NSObject'])) }
				'attribute-key', 'permissions-type' {
					attributes := objc_allocate(api.dictionaries); mut header := obj_header(attributes)
					header.keys << owned_string(if mode == 'attribute-key' { 'UnsupportedAttribute' } else { 'NSFilePosixPermissions' })
					array_append(mut header, api.string('not a number')); ns_file_manager_mode(attributes)
				}
				'permissions-value' { ns_file_manager_mode(api.permissions(0o10000)) }
				'http-url' { api.message(object, c'createDirectoryAtURL:withIntermediateDirectories:attributes:error:', api.message(api.urls, c'URLWithString:', api.string('https://example.invalid/path'), 0, 0, 0), 1, 0, 0) }
				'copy' { api.message(object, c'copy', 0, 0, 0, 0) }
				'delegate' { api.message(object, c'setDelegate:', objc_new(ios_runtime.names['NSObject']), 0, 0, 0) }
				else {}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut buffer := [16384]u8{}; mut length := 0
		for { assert length < buffer.len; count := C.read(fds[0], unsafe { &buffer[length] }, usize(buffer.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&buffer[0], length) }
		reason := match mode { 'path-type' { 'file manager path requires NSString' } 'path-length', 'path-nul' { 'file manager path exceeds the bounded POSIX profile' } 'attributes-type' { 'directory attributes require NSDictionary' } 'attribute-key' { 'only POSIX directory permission attributes are implemented' } 'permissions-type' { 'directory permissions require NSNumber' } 'permissions-value' { 'directory permissions exceed POSIX mode bits' } 'http-url' { 'directory creation requires a file NSURL' } 'copy' { 'file manager copies are not implemented' } else { 'file manager delegate callbacks are not implemented' } }
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-FILEMANAGER-REJECT: ten invalid paths/attributes/permissions/URL/copy/delegate cases fail explicitly')
}
