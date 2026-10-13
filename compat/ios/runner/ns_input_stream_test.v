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
type StreamSend = fn (u64, u64, u64, u64) u64
struct StreamApi { native bool send u64 cls u64 strings u64 data u64 mutable_data u64 urls u64 }
fn (api StreamApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api StreamApi) message(object u64, name &char, a u64, b u64) u64 { return unsafe { StreamSend(voidptr(api.send))(object, api.selector(name), a, b) } }
fn (api StreamApi) string(value string) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value.str), 0) }
fn (api StreamApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api StreamApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api StreamApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api StreamApi) mutable() u64 {
	$if macos { if api.native { return api.message(api.mutable_data, c'dataWithLength:', 3, 0) } }
	object := cf_data_mutable(0, 3); cf_data_set_length(object, 3)
	return objc_autorelease(object)
}
fn (api StreamApi) mutable_pointer(object u64) u64 {
	$if macos { if api.native { return api.message(object, c'mutableBytes', 0, 0) } }
	return data_pointer(object)
}
fn (api StreamApi) state(object u64, status u64, available bool) {
	actual := api.message(object, c'streamStatus', 0, 0)
	assert actual == status, 'native=' + api.native.str() + ' status=' + actual.str() + ' expected=' + status.str();
	assert api.message(object, c'hasBytesAvailable', 0, 0) == u64(available);
}
fn (api StreamApi) buffer(object u64, before bool) {
	mut pointers := [u64(0x1122334455667788), 0x1234, 0x8877665544332211]!
	mut lengths := [u64(0x1122334455667788), 0x5678, 0x8877665544332211]!
	assert api.message(object, c'getBuffer:length:', u64(unsafe { &pointers[1] }), u64(unsafe { &lengths[1] })) == u64(before);
	assert pointers[1] == if before { u64(0) } else { u64(0x1234) };
	assert lengths[1] == if before { ~u64(0) } else { u64(0) };
	assert pointers[0] == 0x1122334455667788 && pointers[2] == 0x8877665544332211;
	assert lengths[0] == 0x1122334455667788 && lengths[2] == 0x8877665544332211;
}
fn stream_cases(api StreamApi) {
	pool := api.pool()
	for content in ['abcde', '']! {
		for constructor in [false, true]! {
			data := api.message(api.data, c'dataWithBytes:length:', u64(content.str), u64(content.len))
			stream := if constructor { api.message(api.message(api.cls, c'allocWithZone:', 0, 0), c'initWithData:', data, 0) } else { api.message(api.cls, c'inputStreamWithData:', data, 0) }
			api.state(stream, 0, false); api.buffer(stream, true)
			mut output := [u8(0xa5), 0, 0, 0, 0, 0, 0, 0, 0, 0x5a]!
			assert i64(api.message(stream, c'read:maxLength:', u64(unsafe { &output[1] }), 2)) == -1;
			api.state(stream, 0, false); api.message(stream, c'open', 0, 0)
			api.state(stream, 2, content.len != 0); api.buffer(stream, false)
			api.message(stream, c'open', 0, 0); api.state(stream, if content.len == 0 { u64(5) } else { u64(2) }, content.len != 0)
			assert api.message(stream, c'read:maxLength:', u64(unsafe { &output[1] }), 0) == 0;
			api.state(stream, if content.len == 0 { u64(5) } else { u64(2) }, content.len != 0)
			count := api.message(stream, c'read:maxLength:', u64(unsafe { &output[1] }), 2)
			assert count == if content.len == 0 { u64(0) } else { u64(2) };
			if count != 0 { assert output[1] == `a` && output[2] == `b`; }
			count2 := api.message(stream, c'read:maxLength:', u64(unsafe { &output[1] }), 8)
			assert count2 == if content.len == 0 { u64(0) } else { u64(3) };
			if count2 != 0 { assert output[1] == `c` && output[2] == `d` && output[3] == `e`; }
			api.state(stream, 5, false); api.buffer(stream, false)
			assert api.message(stream, c'read:maxLength:', u64(unsafe { &output[1] }), 8) == 0;
			assert api.message(stream, c'streamError', 0, 0) == 0 && api.message(stream, c'delegate', 0, 0) == 0;
			key := api.string('NSStreamFileCurrentOffsetKey')
			assert api.message(stream, c'propertyForKey:', key, 0) == 0 && api.message(stream, c'setProperty:forKey:', 0, key) == 0;
			api.message(stream, c'close', 0, 0); api.state(stream, 6, false); api.message(stream, c'open', 0, 0); api.state(stream, 6, false)
			api.buffer(stream, true)
			assert i64(api.message(stream, c'read:maxLength:', u64(unsafe { &output[1] }), 2)) == -1;
			assert output[0] == 0xa5 && output[9] == 0x5a;
			if constructor { api.release(stream) }
		}
	}
	// Mutable input is snapshotted at initialization, independent of its pool.
	mut bytes := [u8(`a`), `b`, `c`]!
	mutable := api.mutable()
	pointer := api.mutable_pointer(mutable)
	unsafe { C.memcpy(voidptr(pointer), &bytes[0], 3) }
	stream := api.message(api.message(api.cls, c'alloc', 0, 0), c'initWithData:', mutable, 0)
	unsafe { *(&u8(pointer)) = `z` }
	api.drain(pool)
	api.message(stream, c'open', 0, 0); mut output := [8]u8{}
	assert api.message(stream, c'read:maxLength:', u64(unsafe { &output[0] }), 8) == 3 && output[0] == `a`;
	api.release(stream)
	path := '/tmp/vinix-inputstream-' + os.getpid().str() + if api.native { '-native' } else { '-runtime' }
	os.write_file(path, 'abcde') or { panic(err) }
	defer { os.rm(path) or { panic(err) } }
	zero_pool := api.pool(); zero_stream := api.message(api.cls, c'inputStreamWithFileAtPath:', api.string(path), 0)
	api.message(zero_stream, c'open', 0, 0)
	assert api.message(zero_stream, c'read:maxLength:', u64(unsafe { &output[0] }), 0) == 0;
	api.state(zero_stream, 5, false); api.drain(zero_pool)
	for kind in 0 .. 4 {
		inner := api.pool(); text := api.string(path)
		file_stream := match kind {
			0 { api.message(api.cls, c'inputStreamWithFileAtPath:', text, 0) }
			1 { api.message(api.message(api.cls, c'alloc', 0, 0), c'initWithFileAtPath:', text, 0) }
			2 { api.message(api.cls, c'inputStreamWithURL:', api.message(api.urls, c'fileURLWithPath:', text, 0), 0) }
			else { api.message(api.message(api.cls, c'alloc', 0, 0), c'initWithURL:', api.message(api.urls, c'fileURLWithPath:', text, 0), 0) }
		}
		api.state(file_stream, 0, false); api.buffer(file_stream, true)
		api.message(file_stream, c'retain', 0, 0); api.drain(inner)
		api.message(file_stream, c'open', 0, 0); api.state(file_stream, 2, true); api.buffer(file_stream, false)
		assert api.message(file_stream, c'read:maxLength:', u64(unsafe { &output[0] }), 2) == 2 && output[0] == `a` && output[1] == `b`;
		assert api.message(file_stream, c'read:maxLength:', u64(unsafe { &output[0] }), 8) == 3 && output[0] == `c` && output[2] == `e`;
		api.state(file_stream, 2, true)
		assert api.message(file_stream, c'read:maxLength:', u64(unsafe { &output[0] }), 8) == 0;
		api.state(file_stream, 5, false); api.message(file_stream, c'close', 0, 0); api.state(file_stream, 6, false)
		api.release(file_stream); if kind == 1 || kind == 3 { api.release(file_stream) }
	}
	for index, filename in [path + '-missing', '/tmp'] {
		inner := api.pool(); file_stream := api.message(api.cls, c'inputStreamWithFileAtPath:', api.string(filename), 0)
		api.message(file_stream, c'open', 0, 0)
		if index == 1 { api.state(file_stream, 2, true); assert i64(api.message(file_stream, c'read:maxLength:', u64(unsafe { &output[0] }), 8)) == -1; }
		api.state(file_stream, 7, false)
		api.buffer(file_stream, true)
		error_object := api.message(file_stream, c'streamError', 0, 0)
		assert error_object != 0 && api.message(error_object, c'code', 0, 0) == if index == 0 { u64(2) } else { u64(21) };
		assert ctext(api.message(api.message(error_object, c'domain', 0, 0), c'UTF8String', 0, 0)) == 'NSPOSIXErrorDomain';
		api.message(error_object, c'retain', 0, 0); api.message(file_stream, c'close', 0, 0); api.state(file_stream, 7, false)
		again := api.message(file_stream, c'streamError', 0, 0)
		assert api.message(again, c'code', 0, 0) == api.message(error_object, c'code', 0, 0);
		api.drain(inner); assert api.message(error_object, c'code', 0, 0) != 0; api.release(error_object)
	}
}
fn test_input_stream_native() {
	$if macos {
		stream_cases(StreamApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSInputStream')), strings: u64(C.objc_getClass(c'NSString')), data: u64(C.objc_getClass(c'NSData')), mutable_data: u64(C.objc_getClass(c'NSMutableData')), urls: u64(C.objc_getClass(c'NSURL'))})
		println('IOS-INPUTSTREAM-NATIVE: typed data/file/URL construction, mutable snapshot, guarded buffer/read ABI, EOF/status/errors and independent input/error lifetimes')
	}
}
fn test_input_stream_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := StreamApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSInputStream'], strings: ios_runtime.names['NSString'], data: ios_runtime.names['NSData'], mutable_data: ios_runtime.names['NSMutableData'], urls: ios_runtime.names['NSURL']}
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation']! {
			assert runtime_symbol(library, '_OBJC_CLASS_$_NSInputStream')! == api.cls;
			assert runtime_symbol(library, '_OBJC_METACLASS_$_NSInputStream')! == read64(api.cls);
		}
		assert objc_class_size(api.cls) == 136 && objc_class_parent(api.cls) == ios_runtime.names['NSStream'] && objc_class_size(ios_runtime.names['NSStream']) == 8;
		stream_cases(api); assert ios_runtime.live == 0;
		for name, types in {'read:maxLength:': 'q32@0:8*16Q24', 'getBuffer:length:': 'B32@0:8^*16^Q24', 'streamStatus': 'Q16@0:8', 'inputStreamWithFileAtPath:': '@24@0:8@16'} {
			method := if name.starts_with('inputStream') { objc_class_method(api.cls, u64(name.str)) } else { objc_instance_method(api.cls, u64(name.str)) }
			assert method != 0 && ctext(u64(objc_method_types(method))) == types;
		}
		pool := api.pool(); data := api.message(api.data, c'dataWithBytes:length:', u64(c'abc'), 3)
		mut caller_bytes := [19]u64{}; caller_bytes[0] = 0x123456789abcdef0; caller_bytes[18] = 0xfedcba9876543210
		caller := objc_construct_instance(api.cls, u64(unsafe { &caller_bytes[1] }))
		assert api.message(caller, c'initWithData:', data, 0) == caller;
		api.message(caller, c'open', 0, 0)
		assert objc_destruct_instance(caller) == caller && caller_bytes[0] == 0x123456789abcdef0 && caller_bytes[18] == 0xfedcba9876543210;
		path := '/tmp/vinix-inputstream-descriptor-' + os.getpid().str(); os.write_file(path, 'abc') or { panic(err) }
		for _ in 0 .. 100 {
			object := ns_input_stream_initialize(objc_allocate(api.cls), api.string(path), 1); ns_input_stream_open(object)
			fd := obj_header(object).input_stream_fd; assert fd >= 0;
			objc_set_class(object, ios_runtime.names['NSObject']); objc_release(object)
			assert C.fcntl(fd, C.F_GETFD) == -1 && unsafe { *C.ios_errno_address() } == C.EBADF;
		}
		os.rm(path) or { panic(err) }; api.drain(pool)
		assert ios_runtime.live == 0; objc_stop(); assert ios_runtime.live == 0;
	}
	println('IOS-INPUTSTREAM: synchronous snapshot/file reads, inherited ABI and CF reexports; guarded 136-byte caller storage,100 descriptor/isa retirements per cycle and two zero-live-object shutdowns')
}
fn test_input_stream_rejections() {
	objc_start(); cls := ios_runtime.names['NSInputStream']
	for mode in ['nil', 'type', 'url', 'reinit', 'uninitialized', 'buffer', 'length', 'delegate', 'seek', 'subclass', 'default', 'abstract']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork(); assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := objc_allocate(cls); data := cf_data_create(0, u64(c'abc'), 3)
			if mode !in ['nil', 'type', 'url', 'uninitialized', 'default', 'abstract', 'subclass']! { ns_input_stream_initialize(object, data, 0) }
			match mode {
				'nil' { ns_input_stream_initialize(object, 0, 0) }
				'type' { ns_input_stream_initialize(object, objc_new(ios_runtime.names['NSObject']), 0) }
				'url' { ns_input_stream_initialize(object, data, 2) }
				'reinit' { ns_input_stream_initialize(object, data, 0) }
				'uninitialized' { ns_input_stream_open(object) }
				'buffer' { ns_input_stream_read(object, 0, 1) }
				'length' { ns_input_stream_read(object, u64(c'abc'), ~u64(0)) }
				'delegate' { mut frame := RegisterFrame{}; ns_input_stream_dispatch(object, 'setDelegate:', mut frame) }
				'seek' { objc_release(object); file := ns_input_stream_initialize(objc_allocate(cls), owned_string('/tmp'), 1); mut frame := RegisterFrame{}; frame.x[2] = owned_string('NSStreamFileCurrentOffsetKey'); ns_input_stream_dispatch(file, 'propertyForKey:', mut frame) }
				'subclass' { subclass := objc_allocate_class(cls, c'UnsupportedInputStream', 0); objc_register_class(subclass); objc_allocate(subclass) }
				'default' { objc_new(cls) }
				else { objc_allocate(ios_runtime.names['NSStream']) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut buffer := [16384]u8{}; mut length := 0
		for { assert length < buffer.len; count := C.read(fds[0], unsafe { &buffer[length] }, usize(buffer.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&buffer[0], length) }
		reason := match mode { 'nil' { 'requires nonnil data or file path' } 'type' { 'requires NSData' } 'url' { 'requires a file NSURL' } 'reinit' { 'reinitialization is not implemented' } 'uninitialized' { 'is not initialized' } 'buffer', 'length' { 'invalid input stream read buffer' } 'delegate' { 'delegates, scheduling and coding are not implemented' } 'seek' { 'file seeking is not implemented' } 'subclass' { 'custom input stream subclass construction is not implemented' } 'default' { 'requires designated construction' } else { 'abstract NSStream construction is not implemented' } }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-INPUTSTREAM-REJECT: twelve nil/type/URL/reinit/uninitialized/buffer/length/delegate/seek/subclass/default/abstract cases fail explicitly')
}
