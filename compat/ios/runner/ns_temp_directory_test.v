// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
type TempCall = fn () u64
type TempProbe = fn (u64,u64,&u64)
type TempSend = fn (u64,u64,u64,u64) u64
type TempName = fn (&char) u64
type TempRetain = fn (u64) u64
type TempDrop = fn (u64)
struct TempApi {
	native bool
	entry u64
	probe u64
	guard u64
	strings u64
	manager u64
	send TempSend
	selector TempName
	retain TempRetain
	drop TempDrop
	push TempCall
	pop TempDrop
}
fn temp_api(native bool,probe u64,guard u64) TempApi {
	$if macos {if native {
		foundation:=C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2);obj:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		cls:=unsafe{TempName(C.dlsym(obj,c'objc_getClass'))}
		return TempApi{native:true,entry:u64(C.dlsym(foundation,c'NSTemporaryDirectory')),probe:probe,guard:guard,strings:cls(c'NSString'),manager:cls(c'NSFileManager'),
			send:unsafe{TempSend(C.dlsym(obj,c'objc_msgSend'))},selector:unsafe{TempName(C.dlsym(obj,c'sel_registerName'))},retain:unsafe{TempRetain(C.dlsym(obj,c'objc_retain'))},drop:unsafe{TempDrop(C.dlsym(obj,c'objc_release'))},
			push:unsafe{TempCall(C.dlsym(obj,c'objc_autoreleasePoolPush'))},pop:unsafe{TempDrop(C.dlsym(obj,c'objc_autoreleasePoolPop'))}}
	}}
	return TempApi{entry:runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation','_NSTemporaryDirectory') or {panic(err)},probe:probe,guard:guard,strings:ios_runtime.names['NSString'],manager:ios_runtime.names['NSFileManager'],
		send:unsafe{TempSend(voidptr(C.ios_objc_builtin))},selector:objc_selector,retain:objc_retain,drop:objc_release,push:objc_pool_push,pop:objc_pool_pop}
}
fn temp_probe_emit(code u64) {
	// Ordinary no-argument C call, with protected x0-x8/x20 and a canary in
	// x21. Callee-saved registers occupy a separate frame. Capture x0 and the
	// preserved contexts; x1 is unspecified for this one-word result.
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0203f3,0xaa0003f0,
		0xaa0103e0,0xaa0003e2,0xaa0003e3,0xaa0003e4,0xaa0003e5,0xaa0003e6,0xaa0003e7,0xaa0003e8,0xaa0003f4,0xd2824695,
		0xd63f0200,0xa9000660,0xa9015674,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
}
fn temp_message(api TempApi,object u64,selector &char,a u64) u64 {return api.send(object,api.selector(selector),a,0)}
fn temp_text(api TempApi,object u64) string {return unsafe{(&char(temp_message(api,object,c'UTF8String',0))).vstring()}}
fn temp_raw(api TempApi) u64 {
	mut capture:=[u64(0xcafe),0,0,0,0,0xbeef]!
	unsafe{TempProbe(voidptr(api.probe))(api.entry,api.guard,&capture[1])}
	assert capture[0]==0xcafe&&capture[3]==api.guard&&capture[4]==0x1234&&capture[5]==0xbeef
	return capture[1]
}
fn temp_case(api TempApi,expected string,isolated bool) {
	baseline:=if api.native || !isolated {i64(0)}else{ios_runtime.live}
	pool:=api.push();first:=unsafe{TempCall(voidptr(api.entry))()};second:=temp_raw(api)
	assert first!=0&&second!=0
	assert temp_message(api,first,c'isKindOfClass:',api.strings)==1
	assert temp_text(api,first)==expected&&temp_text(api,second)==expected
	if !api.native && isolated {assert first!=second&&obj_header(first).refs==1&&obj_header(second).refs==1}
	assert api.retain(first)==first
	api.pop(pool)
	if !api.native && isolated {assert first in ios_runtime.objects&&obj_header(first).refs==1&&second !in ios_runtime.objects}
	assert temp_text(api,first)==expected;api.drop(first)
	if !api.native && isolated {assert ios_runtime.live==baseline}
}
fn temp_worker(api TempApi,expected string) {pool:=api.push();for _ in 0..32 {temp_case(api,expected,false)};api.pop(pool)}
fn temp_threads(api TempApi,expected string) {
	mut workers:=[]thread{};for _ in 0..8 {workers<<spawn temp_worker(api,expected)};workers.wait();unsafe{workers.free()}
}
fn temp_private_cases(api TempApi) {
	// macOS expands /tmp to /private/tmp before applying PATH_MAX.
	base := os.real_path('/tmp') + '/vinix-temp-directory-' + os.getpid().str()
	assert !os.exists(base)
	defer { os.rmdir_all(base) or { panic(err) } }
	for item in [
		[base + '/Fortnite.app', '', base + '/tmp/']!,
		[base + '/Fortnite.app', base + '/Data/Documents', base + '/Data/tmp/']!,
		[base + '/Fortnite.app', base + '/π 🎮/Documents///', base + '/π 🎮/tmp/']!,
		[base + '/Fortnite.app', base + '//Data//Documents', base + '/Data/tmp/']!,
		['/Fortnite.app', '', '/tmp/']!, ['/', '', '/tmp/']!,
		[base + '/Fortnite.app', '/', '/tmp/']!
	]! {
		ios_runtime.bundle = item[0]; os.setenv('VINIX_IOS_DOCUMENTS', item[1], true)
		temp_case(api, item[2], true)
		assert os.is_dir(item[2])
	}
	os.unsetenv('VINIX_IOS_DOCUMENTS'); ios_runtime.bundle = base + '/Fortnite.app'
	os.setenv('TMPDIR', base + '/ignored-env', true)
	temp_case(api, base + '/tmp/', true); assert !os.exists(base + '/ignored-env')
	file := base + '/tmp/owned-file'; os.write_file(file, 'temporary file') or { panic(err) }
	assert os.read_file(file) or { panic(err) } == 'temporary file'; os.rm(file) or { panic(err) }
	temp_threads(api, base + '/tmp/')
	// Preserve byte extents: the bundle's borrowed parent is not NUL terminated.
	page := usize(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert mapping != voidptr(-1)
	path := base + '/Guard/Fortnite.app'; start := u64(mapping) + u64(page) - u64(path.len)
	C.memcpy(voidptr(start), path.str, usize(path.len))
	assert C.mprotect(mapping, page, C.PROT_READ) == 0 && C.mprotect(voidptr(u64(mapping) + u64(page)), page, C.PROT_NONE) == 0
	ios_runtime.bundle = unsafe { tos(&u8(start), path.len) }; temp_case(api, base + '/Guard/tmp/', true); ios_runtime.bundle = ''
	assert C.munmap(mapping, page * 2) == 0
	// Boundary applies to the complete path, including the trailing separator.
	piece := 'x'.repeat(200); prefix := base + '/' + piece + '/' + piece + '/' + piece + '/' + piece
	tail := 'y'.repeat(1018 - prefix.len - 1); parent := prefix + '/' + tail
	ios_runtime.bundle = parent + '/A'; temp_case(api, parent + '/tmp/', true)
	assert (parent + '/tmp/').len == 1023 && os.is_dir(parent + '/tmp')
	ios_runtime.bundle = parent + 'z/A'; if _ := ns_temp_directory_checked() { assert false }
	for invalid in ['', 'relative/Fortnite.app', '/tmp/./Fortnite.app', '/tmp/../Fortnite.app', '/tmp/embedded\x00NUL/Fortnite.app']! {
		ios_runtime.bundle = invalid; if _ := ns_temp_directory_checked() { assert false }
	}
	invalid_utf8 := [u8(`/`), 0xff]!
	ios_runtime.bundle = unsafe { tos(&invalid_utf8[0], 2) }; if _ := ns_temp_directory_checked() { assert false }
	ios_runtime.bundle = base + '/Fortnite.app'
	too_long := '/' + 'q'.repeat(1023); os.setenv('VINIX_IOS_DOCUMENTS', too_long, true)
	if _ := ns_temp_directory_checked() { assert false }; os.unsetenv('VINIX_IOS_DOCUMENTS')
	// A non-directory parent fails without leaking a result or an NSError.
	os.write_file(base + '/blocked', 'file') or { panic(err) }; ios_runtime.bundle = base + '/blocked/Fortnite.app'
	if _ := ns_temp_directory_checked() { assert false }
	for library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, '_NSTemporaryDirectory') { assert false } }
	ios_runtime.bundle = ''
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
}
fn test_ns_temp_directory() {
	page := usize(C.getpagesize()); code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert code != voidptr(-1)
	defer { assert C.munmap(code, page * 2) == 0 }
	temp_probe_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 88)); assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		api := temp_api(true, u64(code), guard); pool := api.push(); manager := temp_message(api, api.manager, c'defaultManager', 0)
		url := temp_message(api, manager, c'temporaryDirectory', 0); path := temp_text(api, temp_message(api, url, c'path', 0))
		expected := (if path.ends_with('/') { path } else { path + '/' }).clone(); assert expected.starts_with('/') && os.is_dir(expected)
		temp_case(api, expected, true); temp_threads(api, expected); api.pop(pool); unsafe { expected.free() }
		println('IOS-TEMP-DIRECTORY-NATIVE: no-argument C ABI, protected arguments and x8, preserved contexts, file-manager path with trailing separator, +0 retain/pool ownership and eight concurrent workers')
	}
	doc_existed := C.getenv(c'VINIX_IOS_DOCUMENTS') != unsafe { nil }; saved_doc := os.getenv('VINIX_IOS_DOCUMENTS')
	tmp_existed := C.getenv(c'TMPDIR') != unsafe { nil }; saved_tmp := os.getenv('TMPDIR')
	defer {
		if doc_existed { os.setenv('VINIX_IOS_DOCUMENTS', saved_doc, true) } else { os.unsetenv('VINIX_IOS_DOCUMENTS') }
		if tmp_existed { os.setenv('TMPDIR', saved_tmp, true) } else { os.unsetenv('TMPDIR') }
		unsafe { saved_doc.free(); saved_tmp.free() }
	}
	if _ := ns_temp_directory_checked() { assert false }
	for _ in 0 .. 2 {
		objc_start(); api := temp_api(false, u64(code), guard); temp_private_cases(api)
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		if _ := ns_temp_directory_checked() { assert false }
	}
	println('IOS-TEMP-DIRECTORY: Foundation-only export, copied autoreleased app-container tmp paths, provisioned writable directories, guarded ABI and borrowed prefixes, Documents override, Unicode/space/root/separator/1023-byte cases, ignored TMPDIR, failure cleanup, concurrent readers and two drained runtimes')
}
