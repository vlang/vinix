// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only container/native comparison; extracted AIR is not shader execution.
module main

import crypto.sha256
import metallib
import os
import strconv

$if macos {
	#flag -framework Foundation
	#flag -framework Metal
	#include <dlfcn.h>
	#include <objc/runtime.h>
	fn C.dlsym(voidptr, &char) voidptr
	fn C.dlopen(&char, int) voidptr
	fn C.dlclose(voidptr) int
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
}

type NativeSend = fn (u64, u64, u64, u64) u64
type NativeDevice = fn () u64

struct Native {
	send u64
}

fn (api Native) msg(object u64, selector &char, x u64, y u64) u64 {
	$if macos { return unsafe { NativeSend(voidptr(api.send))(object, u64(C.sel_registerName(selector)), x, y) } }
	return 0
}

fn native_compare(path string, library metallib.Library) ! {
	$if macos {
		metal := C.dlopen(c'/System/Library/Frameworks/Metal.framework/Metal', 2)
		if metal == unsafe { nil } { return error('cannot load native Metal') }
		defer { C.dlclose(metal) }
		api := Native{send: u64(C.dlsym(voidptr(-2), c'objc_msgSend'))}
		pool := api.msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0)
		defer { api.msg(pool, c'drain', 0, 0) }
		device := unsafe { NativeDevice(C.dlsym(metal, c'MTLCreateSystemDefaultDevice'))() }
		if device == 0 { return error('native Metal device unavailable') }
		defer { api.msg(device, c'release', 0, 0) }
		name := api.msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(path.str), 0)
		mut error_object := u64(0)
		native_library := api.msg(device, c'newLibraryWithFile:error:', name, u64(unsafe { &error_object }))
		if native_library == 0 { return error('native Metal rejects library') }
		defer { api.msg(native_library, c'release', 0, 0) }
		array := api.msg(native_library, c'functionNames', 0, 0)
		count := api.msg(array, c'count', 0, 0)
		if count != u64(library.functions.len) { return error('native function count differs') }
		// This array owns its strings; the parser's names borrow file bytes.
		mut expected := library.functions.map(it.name.clone())
		defer { unsafe { expected.free() } }
		mut actual := []string{cap: int(count)}
		defer { unsafe { actual.free() } }
		for i in 0 .. int(count) {
			text := api.msg(array, c'objectAtIndex:', u64(i), 0)
			actual << unsafe { tos_clone(&char(api.msg(text, c'UTF8String', 0, 0))) }
		}
		expected.sort(); actual.sort()
		if actual != expected { return error('native function names differ') }
		for function in library.functions {
			if function.kind > 2 { continue }
			text := api.msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(function.name.str), 0)
			instance := api.msg(native_library, c'newFunctionWithName:', text, 0)
			if instance == 0 { return error('native function lookup failed') }
			type_id := api.msg(instance, c'functionType', 0, 0)
			api.msg(instance, c'release', 0, 0)
			if type_id != u64(function.kind) + 1 { return error('native function type differs') }
		}
		println('Native Metal function names/count/types: PASS')
	} $else { return error('native comparison requires macOS') }
}

fn main() {
	if os.args.len < 3 || os.args[1] !in ['inspect', 'native', 'extract']
		|| (os.args[1] == 'extract' && os.args.len != 5) || (os.args[1] != 'extract' && os.args.len != 3) {
		panic('usage: metallib-inspect inspect|native FILE | extract FILE MODULE_INDEX FRESH_OUT.bc')
	}
	path := os.real_path(os.args[2])
	if os.file_size(path) > metallib.max_library_size { panic('library exceeds input limit') }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	library := metallib.parse(data)!
	defer { library.free() }
	println('MTLB: version=${library.major}.${library.minor} platform=0x${library.platform.hex()} functions=${library.functions.len} modules=${library.modules.len} bytes=${data.len}')
	for function in library.functions {
		println('FUNCTION: ${function.name} kind=${function.kind} module=${function.module} AIR=${function.versions[0]}.${function.versions[1]} MSL=${function.versions[2]}.${function.versions[3]}')
	}
	if os.args[1] == 'native' { native_compare(path, library)! }
	if os.args[1] == 'extract' {
		if os.args.len != 5 { panic('extract requires module index and fresh output') }
		index := strconv.atoi(os.args[3])!
		if index < 0 || index >= library.modules.len { panic('module index out of range') }
		out := os.abs_path(os.args[4])
		if os.exists(out) || os.is_link(out) || out == os.getwd() || out.starts_with(os.getwd() + '/') { panic('requires fresh external output') }
		range := library.modules[index].bitcode
		os.write_file_array(out, data[int(range.offset)..int(range.offset + range.size)])!
	}
	mut hash := sha256.new()
	defer { unsafe { hash.free(); free(hash) } }
	hash.write(data)!
	sum := hash.sum([]u8{})
	defer { unsafe { sum.free() } }
	println('Container SHA-256: ' + sum.hex() + '; all indexed AIR module checksums match; shader execution unverified')
}
