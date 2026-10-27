// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.class_getClassMethod(voidptr, voidptr) voidptr
	fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
	fn C.method_getTypeEncoding(voidptr) &char
	fn C.method_getImplementation(voidptr) voidptr
	#include <dlfcn.h>
	fn C.dlsym(voidptr, &char) voidptr
}

type LocaleLanguagesSend = fn (u64, u64, u64) u64
struct LocaleLanguagesApi { native bool send u64 }
fn (api LocaleLanguagesApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api LocaleLanguagesApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api LocaleLanguagesApi) msg(object u64, name &char, arg u64) u64 {
	return unsafe { LocaleLanguagesSend(voidptr(api.send))(object, api.sel(name), arg) }
}
fn (api LocaleLanguagesApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api LocaleLanguagesApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn locale_languages_values(api LocaleLanguagesApi, array u64, expected []string) {
	assert array != 0 && api.msg(array, c'isKindOfClass:', api.cls('NSArray')) == 1
	assert api.msg(array, c'isKindOfClass:', api.cls('NSMutableArray')) == 0
	assert api.msg(array, c'count', 0) == u64(expected.len)
	for i, tag in expected {
		item := api.msg(array, c'objectAtIndex:', u64(i))
		assert api.msg(item, c'isKindOfClass:', api.cls('NSString')) == 1
		assert unsafe { (&char(voidptr(api.msg(item, c'UTF8String', 0)))).vstring() } == tag
	}
}
fn locale_languages_case(api LocaleLanguagesApi, expected []string, imp u64) {
	pool := api.pool()
	cls := api.cls('NSLocale')
	first := api.msg(cls, c'preferredLanguages', 0)
	second := unsafe { LocaleLanguagesSend(voidptr(imp))(cls, api.sel(c'preferredLanguages'), 0) }
	locale_languages_values(api, first, expected)
	locale_languages_values(api, second, expected)
	api.msg(first, c'retain', 0)
	api.msg(second, c'retain', 0)
	mut retained := u64(0)
	if expected.len > 0 { retained = api.msg(api.msg(first, c'objectAtIndex:', 0), c'retain', 0) }
	api.drain(pool)
	locale_languages_values(api, first, expected)
	locale_languages_values(api, second, expected)
	api.msg(first, c'release', 0)
	api.msg(second, c'release', 0)
	if retained != 0 {
		assert unsafe { (&char(voidptr(api.msg(retained, c'UTF8String', 0)))).vstring() } == expected[0]
		api.msg(retained, c'release', 0)
	}
}
fn locale_languages_worker(api LocaleLanguagesApi, expected []string, imp u64) {
	for _ in 0 .. 64 { locale_languages_case(api, expected, imp) }
}
fn locale_languages_shared(api LocaleLanguagesApi, expected []string) {
	pool := api.pool()
	cls := api.cls('NSLocale'); selector := api.sel(c'preferredLanguages')
	assert api.msg(cls, c'respondsToSelector:', selector) == 1
	assert api.msg(cls, c'respondsToSelector:', api.sel(c'vinixMissingPreferredLanguages')) == 0
	mut imp := u64(0)
	$if macos { if api.native {
		method := C.class_getClassMethod(voidptr(cls), voidptr(selector))
		assert method != unsafe { nil } && C.class_getInstanceMethod(voidptr(cls), voidptr(selector)) == unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8'
		imp = u64(C.method_getImplementation(method))
	} }
	if !api.native {
		method := objc_instance_method(read64(cls), selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
		assert objc_instance_method(cls, selector) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0
	signature := api.msg(cls, c'methodSignatureForSelector:', selector)
	assert signature != 0 && api.msg(signature, c'numberOfArguments', 0) == 2
	assert api.msg(signature, c'methodReturnLength', 0) == 8
	assert unsafe { (&char(voidptr(api.msg(signature, c'methodReturnType', 0)))).vstring() } == '@'
	api.drain(pool)
	locale_languages_case(api, expected, imp)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn locale_languages_worker(api, expected, imp) }
	workers.wait()
	unsafe { workers.free() }
}
fn locale_languages_native_values() []string {
	mut expected := []string{}
	$if macos {
		native := C.CFLocaleCopyPreferredLanguages()
		assert native != unsafe { nil }
		defer { C.CFRelease(native) }
		count := C.CFArrayGetCount(native)
		assert count >= 0 && count <= 32
		for i := i64(0); i < count; i++ {
			mut bytes := [1024]u8{}
			assert C.CFStringGetCString(C.CFArrayGetValueAtIndex(native, i), unsafe { &char(&bytes[0]) }, 1024, 0x08000100)
			expected << ctext(u64(unsafe { &bytes[0] })).clone()
		}
	}
	return expected
}
fn test_locale_languages_native() {
	$if macos {
		expected := locale_languages_native_values()
		defer { unsafe { expected.free() } }
		api := LocaleLanguagesApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		locale_languages_shared(api, expected)
		println('IOS-NSLOCALE-PREFERRED-NATIVE: exact CF order, immutable array, metadata, signature, direct IMP, eight workers and retained values after pool drain PASS')
	}
}
fn test_locale_languages_runtime() {
	mut saved := []string{}
	mut existed := []bool{}
	for key in ['LANGUAGE', 'LC_ALL', 'LC_MESSAGES', 'LANG']! {
		existed << (C.getenv(unsafe { &char(key.str) }) != unsafe { nil }); saved << os.getenv(key)
	}
	defer {
		for i, key in ['LANGUAGE', 'LC_ALL', 'LC_MESSAGES', 'LANG']! {
			if existed[i] { os.setenv(key, saved[i], true) } else { os.unsetenv(key) }
		}
		unsafe { saved.free(); existed.free() }
	}
	api := LocaleLanguagesApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for _ in 0 .. 2 {
		objc_start()
		mut expected := ['fr-FR', 'de-DE', 'es-419']
		$if macos { unsafe { expected.free() }; expected = locale_languages_native_values() }
		os.setenv('LANGUAGE', 'fr_FR:de_DE:fr-FR:es_419', true)
		locale_languages_shared(api, expected)
		unsafe { expected.free() }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		$if linux {
			pool := api.pool()
			first := api.msg(api.cls('NSLocale'), c'preferredLanguages', 0)
			os.setenv('LANGUAGE', 'ja_JP:zh_TW:iw_IL', true)
			second := api.msg(api.cls('NSLocale'), c'preferredLanguages', 0)
			assert first != second
			locale_languages_values(api, first, ['fr-FR', 'de-DE', 'es-419'])
			locale_languages_values(api, second, ['ja-JP', 'zh-Hant', 'he-IL'])
			os.setenv('LANGUAGE', '', true); os.setenv('LC_ALL', 'ru_RU.UTF-8', true)
			locale_languages_values(api, api.msg(api.cls('NSLocale'), c'preferredLanguages', 0), ['ru-RU'])
			api.drain(pool)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-NSLOCALE-PREFERRED: ordered immutable language snapshots, metadata, signature, direct IMP, eight workers, retained values, locale fallback and two balanced runtimes PASS')
}
