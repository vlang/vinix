// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type SearchCall = fn (u64, u64, bool) u64
type SearchSend = fn (u64, u64, u64) u64
type SearchName = fn (&char) u64
type SearchRetain = fn (u64) u64
type SearchPush = fn () u64
type SearchDrop = fn (u64)
struct SearchApi {
	native bool
	call SearchCall
	send SearchSend
	name SearchName
	class SearchName
	retain SearchRetain
	drop SearchDrop
	push SearchPush
	pop SearchDrop
}
fn search_api(native bool) SearchApi {
	$if macos { if native {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		obj := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		return SearchApi{native: true,
			call: unsafe { SearchCall(C.dlsym(foundation, c'NSSearchPathForDirectoriesInDomains')) },
			send: unsafe { SearchSend(C.dlsym(obj, c'objc_msgSend')) },
			name: unsafe { SearchName(C.dlsym(obj, c'sel_registerName')) },
			class: unsafe { SearchName(C.dlsym(obj, c'objc_getClass')) },
			retain: unsafe { SearchRetain(C.dlsym(obj, c'objc_retain')) },
			drop: unsafe { SearchDrop(C.dlsym(obj, c'objc_release')) },
			push: unsafe { SearchPush(C.dlsym(obj, c'objc_autoreleasePoolPush')) },
			pop: unsafe { SearchDrop(C.dlsym(obj, c'objc_autoreleasePoolPop')) }}
	} }
	entry := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_NSSearchPathForDirectoriesInDomains') or { panic(err) }
	return SearchApi{call: unsafe { SearchCall(voidptr(entry)) }, send: unsafe { SearchSend(voidptr(C.ios_objc_builtin)) },
		name: objc_selector, class: objc_get_class, retain: objc_retain, drop: objc_release, push: objc_pool_push, pop: objc_pool_pop}
}
fn search_message(api SearchApi, object u64, selector &char, arg u64) u64 {
	return api.send(object, api.name(selector), arg)
}
fn search_text(api SearchApi, object u64) string {
	return unsafe { (&char(search_message(api, object, c'UTF8String', 0))).vstring() }
}
fn search_case(api SearchApi, directory u64, expand bool, expected string, isolated bool) {
	baseline := if api.native || !isolated { i64(0) } else { ios_runtime.live }
	pool := api.push()
	array := api.call(directory, 1, expand)
	assert array != 0 && search_message(api, array, c'count', 0) == 1
	path := search_message(api, array, c'objectAtIndex:', 0)
	assert search_message(api, array, c'isKindOfClass:', api.class(c'NSArray')) == 1
	assert search_message(api, path, c'isKindOfClass:', api.class(c'NSString')) == 1
	assert search_text(api, path) == expected
	assert api.retain(array) == array
	assert api.retain(path) == path
	api.pop(pool)
	assert search_text(api, search_message(api, array, c'objectAtIndex:', 0)) == expected
	api.drop(array)
	assert search_text(api, path) == expected
	api.drop(path)
	if !api.native && isolated { assert ios_runtime.live == baseline }
}
fn search_worker(api SearchApi) {
	for _ in 0 .. 32 { search_case(api, 13, false, '~/Library/Caches', false) }
}
fn search_threads(api SearchApi) {
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn search_worker(api) }
	workers.wait()
	unsafe { workers.free() }
}
fn search_private(api SearchApi) {
	for item in [
		['/opt/ios/Fortnite.app', '', '/opt/ios', '/opt/ios/Documents']!,
		['/ignored/Fortnite.app', '/tmp/π 🎮/Save Data///', '/tmp/π 🎮', '/tmp/π 🎮/Save Data']!,
		['/Fortnite.app', '', '', '/Documents']!,
		['/', '', '', '/Documents']!,
		['/unused/Fortnite.app', '/', '', '/']!,
		['/opt//ios///Fortnite.app///', '', '/opt/ios', '/opt/ios/Documents']!
	]! {
		ios_runtime.bundle = item[0]; os.setenv('VINIX_IOS_DOCUMENTS', item[1], true)
		for pair in [['5', '/Library']!, ['9', '/Documents']!, ['13', '/Library/Caches']!, ['14', '/Library/Application Support']!]! {
			directory := pair[0].u64()
			expected := if directory == 9 { item[3] } else { item[2] + pair[1] }
			search_case(api, directory, true, expected, true)
			search_case(api, directory, false, '~' + pair[1], true)
		}
	}
	// Lookup must not mkdir: Foundation reports a path even when it is absent.
	base := '/tmp/vinix-search-' + os.getpid().str()
	ios_runtime.bundle = base + '/Fortnite.app'; os.unsetenv('VINIX_IOS_DOCUMENTS')
	assert !os.exists(base)
	search_case(api, 13, true, base + '/Library/Caches', true)
	search_case(api, 9, true, base + '/Documents', true)
	assert !os.exists(base)
	// Guard the end of a borrowed input against accidental C-string reads.
	page := usize(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != voidptr(-1)
	path := '/tmp/guarded/Fortnite.app'; start := u64(mapping) + u64(page) - u64(path.len)
	C.memcpy(voidptr(start), path.str, usize(path.len))
	assert C.mprotect(voidptr(u64(mapping) + u64(page)), page, C.PROT_NONE) == 0
	ios_runtime.bundle = unsafe { tos(&u8(start), path.len) }
	search_case(api, 13, true, '/tmp/guarded/Library/Caches', true)
	ios_runtime.bundle = ''; assert C.munmap(mapping, page * 2) == 0
	for invalid in ['', 'relative/Fortnite.app', '/tmp/./Fortnite.app', '/tmp/../Fortnite.app', '/tmp/embedded\x00NUL/Fortnite.app']! {
		ios_runtime.bundle = invalid
		if _ := ns_search_paths_checked(13, 1, true) { assert false }
	}
	invalid_utf8 := [u8(`/`), 0xff]!
	ios_runtime.bundle = unsafe { tos(&invalid_utf8[0], 2) }
	if _ := ns_search_paths_checked(13, 1, true) { assert false }
	ios_runtime.bundle = '/opt/ios/Fortnite.app'
	for pair in [[u64(0), 1]!, [u64(12), 1]!, [u64(5), 0]!, [u64(5), 2]!, [u64(5), 0xffff]!]! {
		if _ := ns_search_paths_checked(pair[0], pair[1], true) { assert false }
	}
	suffix := '/Library/Application Support'
	long_parent := '/' + 'a'.repeat(1022 - suffix.len)
	documents := long_parent + '/Documents'; os.setenv('VINIX_IOS_DOCUMENTS', documents, true)
	assert (long_parent + suffix).len == 1023
	search_case(api, 14, true, long_parent + suffix, true)
	os.setenv('VINIX_IOS_DOCUMENTS', long_parent + 'a/Documents', true)
	if _ := ns_search_paths_checked(14, 1, true) { assert false }
	os.setenv('VINIX_IOS_DOCUMENTS', '/' + 'a'.repeat(1023), true)
	if _ := ns_search_paths_checked(13, 1, true) { assert false }
	for invalid in ['relative/Documents', '/tmp/../Documents', '/tmp/./Documents']! {
		os.setenv('VINIX_IOS_DOCUMENTS', invalid, true)
		if _ := ns_search_paths_checked(13, 1, true) { assert false }
	}
	os.unsetenv('VINIX_IOS_DOCUMENTS')
}
fn test_ns_search_paths() {
	$if macos {
		api := search_api(true)
		for pair in [[u64(5), 0]!, [u64(9), 0]!, [u64(13), 0]!, [u64(14), 0]!]! {
			suffix := match pair[0] { 5 { '/Library' } 9 { '/Documents' } 13 { '/Library/Caches' } else { '/Library/Application Support' } }
			search_case(api, pair[0], false, '~' + suffix, true)
			pool := api.push(); paths := api.call(pair[0], 1, true)
			path := search_text(api, search_message(api, paths, c'objectAtIndex:', 0))
			assert path.starts_with('/') && path.ends_with(suffix)
			api.pop(pool)
		}
		search_threads(api)
		println('IOS-SEARCH-PATHS-NATIVE: C ABI, user Library/Documents/Caches/Application Support, tilde paths, +0 lifetime and concurrent readers PASS')
	}
	existed := C.getenv(c'VINIX_IOS_DOCUMENTS') != unsafe { nil }; saved := os.getenv('VINIX_IOS_DOCUMENTS')
	defer { if existed { os.setenv('VINIX_IOS_DOCUMENTS', saved, true) } else { os.unsetenv('VINIX_IOS_DOCUMENTS') }; unsafe { saved.free() } }
	if _ := ns_search_paths_checked(13, 1, true) { assert false }
	for _ in 0 .. 2 {
		objc_start(); api := search_api(false); search_private(api)
		os.unsetenv('VINIX_IOS_DOCUMENTS'); ios_runtime.bundle = '/opt/ios/Fortnite.app'; search_threads(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop(); if _ := ns_search_paths_checked(13, 1, true) { assert false }
	}
	println('IOS-SEARCH-PATHS: user application directories, Documents override, tilde expansion, bounded Unicode/root/borrowed paths, rejection, no filesystem effects, retained arrays, concurrent readers and two drained runtimes PASS')
}
