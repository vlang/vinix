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
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
type DataURLSend = fn (u64, u64, u64) u64
struct DataURLApi { native bool send u64 }
fn (api DataURLApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn (api DataURLApi) msg(object u64, name &char, argument u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { DataURLSend(voidptr(api.send))(object, selector, argument) }
}
fn (api DataURLApi) url(path string) u64 {
	string_object := api.msg(api.cls(c'NSString'), c'stringWithUTF8String:', u64(path.str))
	return api.msg(api.cls(c'NSURL'), c'fileURLWithPath:', string_object)
}
fn (api DataURLApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls(c'NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api DataURLApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn data_url_bytes(api DataURLApi, data u64, bytes []u8) {
	assert data != 0 && api.msg(data, c'length', 0) == u64(bytes.len);
	if bytes.len != 0 { assert C.memcmp(unsafe { voidptr(api.msg(data, c'bytes', 0)) }, bytes.data, usize(bytes.len)) == 0; }
}
fn data_url_cases(api DataURLApi) {
	path := '/tmp/vinix-data-url-' + os.getpid().str() + if api.native { '-native é' } else { '-runtime é' }
	os.mkdir(path) or { panic(err) }
	defer { os.rmdir_all(path) or { panic(err) } }
	mut bytes := []u8{len: 8193}
	for i in 0 .. bytes.len { bytes[i] = u8(i % 251) }
	for content in [[]u8{}, [u8(0), 255, 10, 128], bytes] {
		filename := path + '/binary data'
		os.write_file_array(filename, content) or { panic(err) }
		for name in [c'NSData', c'NSMutableData']! {
			pool := api.pool()
			data := api.msg(api.cls(name), c'dataWithContentsOfURL:', api.url(filename))
			data_url_bytes(api, data, content)
			if name == c'NSMutableData' && content.len != 0 {
				pointer := api.msg(data, c'mutableBytes', 0)
				unsafe { *&u8(voidptr(pointer)) = 42 }
				assert unsafe { *&u8(voidptr(api.msg(data, c'bytes', 0))) } == 42;
			}
			api.msg(data, c'retain', 0); api.drain(pool)
			os.write_file(filename, 'replacement') or { panic(err) }
			assert api.msg(data, c'length', 0) == u64(content.len);
			if name == c'NSData' { data_url_bytes(api, data, content) }
			api.msg(data, c'release', 0)
			os.write_file_array(filename, content) or { panic(err) }
		}
	}
	pool := api.pool()
	for filename in [path, path + '/missing']! {
		assert api.msg(api.cls(c'NSData'), c'dataWithContentsOfURL:', api.url(filename)) == 0;
	}
	api.drain(pool)
}
fn test_data_url_native() {
	$if macos {
		api := DataURLApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		method := C.class_getClassMethod(unsafe { voidptr(api.cls(c'NSData')) }, C.sel_registerName(c'dataWithContentsOfURL:'))
		assert method != unsafe { nil } && ctext(u64(C.method_getTypeEncoding(method))) == '@24@0:8@16';
		data_url_cases(api)
		println('IOS-DATA-URL-NATIVE: reflected factory ABI, empty and binary files, chunk boundary, Unicode paths, missing files, directories, mutable results and retained snapshots')
	}
}
fn data_url_worker(api DataURLApi, path string) {
	for _ in 0 .. 50 {
		pool := api.pool()
		data := api.msg(api.cls(c'NSData'), c'dataWithContentsOfURL:', api.url(path))
		data_url_bytes(api, data, [u8(0), 255, 10, 128])
		api.drain(pool)
	}
}
fn test_data_url_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		api := DataURLApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		data_url_cases(api)
		assert ios_runtime.live == 0;
		for name in [c'NSData', c'NSMutableData']! {
			cls := api.cls(name)
			assert objc_responds(cls, c'dataWithContentsOfURL:');
			method := objc_class_method(cls, u64(c'dataWithContentsOfURL:'))
			assert method != 0 && ctext(u64(objc_method_types(method))) == '@24@0:8@16';
			object := objc_new(cls)
			assert !objc_responds(object, c'dataWithContentsOfURL:');
			objc_release(object)
		}
		path := '/tmp/vinix-data-url-thread-' + os.getpid().str()
		os.write_file_array(path, [u8(0), 255, 10, 128]) or { panic(err) }
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn data_url_worker(api, path) }
		workers.wait()
		assert ios_runtime.live == 0;
		fd := C.open(path.str, C.O_WRONLY)
		assert fd >= 0 && C.ftruncate(fd, 16777217) == 0;
		C.close(fd)
		pool := api.pool()
		assert api.msg(api.cls(c'NSData'), c'dataWithContentsOfURL:', api.url(path)) == 0;
		api.drain(pool); os.rm(path) or { panic(err) }
		objc_stop(); assert ios_runtime.live == 0;
	}
	println('IOS-DATA-URL: native file cases, inherited reflection, 200 concurrent loads per cycle, 16 MiB bound and two zero-live-object shutdowns')
}
fn test_data_url_rejections() {
	objc_start()
	for mode in ['nil', 'wrong-class']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork(); assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			mut frame := RegisterFrame{}
			if mode == 'wrong-class' { frame.x[2] = owned_string('not a URL') }
			ns_data_url_dispatch(ios_runtime.names['NSData'], 'dataWithContentsOfURL:', mut frame)
			C._exit(0)
		}
		C.close(fds[1]); mut buffer := [16384]u8{}; mut length := 0
		for { assert length < buffer.len; count := C.read(fds[0], unsafe { &buffer[length] }, usize(buffer.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&buffer[0], length) }
		reason := 'data loading requires NSURL'
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	objc_stop(); assert ios_runtime.live == 0;
	println('IOS-DATA-URL-REJECT: nil and wrong-class URLs fail explicitly')
}
