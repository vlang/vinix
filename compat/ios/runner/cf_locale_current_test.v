// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

type LocaleCurrentCall = fn () u64
type LocaleCurrentDrop = fn (u64)
type LocaleCurrentKeep = fn (u64) u64
type LocaleCurrentProbe = fn (u64, u64, &u64)
type LocaleCurrentSend = fn (u64, u64, u64, u64) u64

fn locale_current_native_owned() u64 {
	$if macos {
		pool := C.objc_autoreleasePoolPush()
		locale := C.CFLocaleCopyCurrent()
		C.objc_autoreleasePoolPop(pool)
		return u64(locale)
	}
	return 0
}

fn locale_current_probe_emit(code u64) {
	// Protected argument/x8 pointers, preserved x20 and a callee-saved canary.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0003e2, 0xaa0003e3, 0xaa0003e4, 0xaa0003e5, 0xaa0003e6,
		0xaa0003e7, 0xaa0003e8, 0xaa0003f4, 0xd2824695, 0xd63f0200, 0xa9000660,
		0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn locale_current_raw(entry u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { LocaleCurrentProbe(voidptr(code))(entry, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn locale_current_message(object u64, selector &char) u64 {
	send := unsafe { LocaleCurrentSend(voidptr(C.ios_objc_builtin)) }
	return send(object, objc_selector(selector), 0, 0)
}

fn locale_current_text(object u64) string {
	return string_text(locale_current_message(object, c'localeIdentifier'))
}

fn locale_current_worker(entry u64, expected string) {
	copy := unsafe { LocaleCurrentCall(voidptr(entry)) }
	for _ in 0 .. 40 {
		pool := objc_pool_push()
		first := copy()
		second := copy()
		assert first != 0 && first == second
		assert locale_current_text(first) == expected
		objc_pool_pop(pool)
		assert locale_current_text(second) == expected
		objc_release(first)
		objc_release(second)
	}
}

fn locale_current_threads(entry u64, expected string) {
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn locale_current_worker(entry, expected) }
	workers.wait()
	unsafe { workers.free() }
}

fn locale_current_environment_cases() {
	$if linux {
		for item in [
			['', '', '', 'en_US']!, ['C', 'fr_FR', 'de_DE', 'en_US']!,
			['POSIX', '', 'ru_RU', 'en_US']!, ['C.UTF-8', '', '', 'en_US']!,
			['fr_FR.UTF-8', 'de_DE', 'ru_RU', 'fr_FR']!,
			['', 'de_DE.UTF-8@euro', 'ru_RU', 'de_DE']!,
			['', '', 'ru_RU.UTF-8', 'ru_RU']!,
			['sr_Latn_RS@latin', '', '', 'sr_Latn_RS']!,
			['es_419', '', '', 'es_419']!, ['ja_JP', '', '', 'ja_JP']!
		]! {
			for i, key in ['LC_ALL', 'LC_MESSAGES', 'LANG']! { os.setenv(key, item[i], true) }
			identifier := ns_locale_current_identifier()
			assert string_text(identifier) == item[3]
			objc_release(identifier)
			assert ios_runtime.live == 0
		}
		for key in ['LC_ALL', 'LC_MESSAGES', 'LANG']! { os.unsetenv(key) }
		identifier := ns_locale_current_identifier()
		assert string_text(identifier) == 'en_US'
		objc_release(identifier)
		// The bounded reader accepts 1023 identifier bytes and ignores a long
		// encoding suffix once '.' terminates the locale identifier.
		long := 'a'.repeat(1023)
		suffixed := 'fr_FR.' + 'x'.repeat(4096)
		for value in [long, suffixed]! {
			os.setenv('LC_ALL', value, true)
			actual := ns_locale_current_identifier()
			assert string_text(actual) == if value == long { long } else { 'fr_FR' }
			objc_release(actual)
		}
		unsafe { long.free(); suffixed.free() }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
}

fn test_cf_locale_current() {
	mut saved := []string{}
	mut existed := []bool{}
	for key in ['LC_ALL', 'LC_MESSAGES', 'LANG']! {
		existed << (C.getenv(unsafe { &char(key.str) }) != unsafe { nil })
		saved << os.getenv(key)
	}
	defer {
		for i, key in ['LC_ALL', 'LC_MESSAGES', 'LANG']! {
			if existed[i] { os.setenv(key, saved[i], true) } else { os.unsetenv(key) }
		}
		unsafe { saved.free(); existed.free() }
	}
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page * 2) == 0 }
	locale_current_probe_emit(u64(code))
	C.__builtin___clear_cache(code, voidptr(u64(code) + 88))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	mut expected := 'fr_FR'
	$if macos {
		native := voidptr(locale_current_raw(u64(unsafe { voidptr(locale_current_native_owned) }), u64(code), guard))
		mut bytes := [1024]u8{}
		assert C.CFStringGetCString(C.CFLocaleGetIdentifier(native), unsafe { &char(&bytes[0]) }, 1024, 0x08000100)
		expected = ctext(u64(unsafe { &bytes[0] })).clone()
		C.CFRelease(native)
		println('NATIVE-CF-LOCALE-CURRENT: no-argument owned result survives native autorelease drain and protected argument/x8 registers; identifier copied for bridge comparison')
	}
	defer { $if macos { unsafe { expected.free() } } }
	objc_start()
	locale_current_environment_cases()
	objc_stop()
	for iteration in 0 .. 2 {
		os.setenv('LC_ALL', 'fr_FR.UTF-8', true)
		objc_start()
		entry := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFLocaleCopyCurrent') or { panic(err) }
		copy := unsafe { LocaleCurrentCall(voidptr(entry)) }
		drop := unsafe { LocaleCurrentDrop(voidptr(runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFRelease') or { panic(err) })) }
		keep := unsafe { LocaleCurrentKeep(voidptr(runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFRetain') or { panic(err) })) }
		assert ios_runtime.locale == 0 && ios_runtime.live == 0
		if iteration == 0 { locale_current_threads(entry, expected) }
		pool := objc_pool_push()
		first := copy()
		second := locale_current_raw(entry, u64(code), guard)
		assert first != 0 && first == second && first == ios_runtime.locale
		assert locale_current_message(ios_runtime.names['NSLocale'], c'currentLocale') == first
		assert locale_current_text(first) == expected
		assert objc_is_kind(first, ios_runtime.names['NSLocale']) && obj_header(first).refs == 3
		assert keep(first) == first && obj_header(first).refs == 4
		drop(first)
		objc_pool_pop(pool)
		assert obj_header(first).refs == 3 && locale_current_text(first) == expected
		os.setenv('LC_ALL', 'ja_JP.UTF-8', true)
		third := copy()
		assert third == first && locale_current_text(third) == expected
		drop(third); drop(first); drop(second)
		assert obj_header(ios_runtime.locale).refs == 1 && ios_runtime.live == 2
		locale_current_threads(entry, expected)
		assert obj_header(ios_runtime.locale).refs == 1 && ios_runtime.live == 2
		identifier := obj_header(ios_runtime.locale).fields[0]
		assert obj_header(identifier).refs == 1
		mut weak_locale := u64(0)
		mut weak_identifier := u64(0)
		objc_store_weak(unsafe { &weak_locale }, ios_runtime.locale)
		objc_store_weak(unsafe { &weak_identifier }, identifier)
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFLocaleCopyCurrent') { assert false }
		}
		objc_stop()
		assert weak_locale == 0 && weak_identifier == 0
		assert ios_runtime.swift_concurrency_retired && ios_runtime.objects.len == 0 && ios_runtime.live == 0
	}
	println('IOS-CF-LOCALE-CURRENT: scoped no-argument C ABI, protected argument/x8 registers, preserved x20/x21, owned CF references shared with NSLocale currentLocale, copied native identifier or Vinix environment policy, cache stability, concurrent first publication/readers, autorelease independence and two released runtimes')
}
