// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

$if macos {
	fn C.CFLocaleCreateCanonicalLanguageIdentifierFromString(voidptr, voidptr) voidptr
	fn C.CFStringCreateWithCString(voidptr, &char, u32) voidptr
}

type PreferredCopy = fn () u64
type PreferredCount = fn (u64) i64
type PreferredAt = fn (u64, i64) u64
type PreferredKeep = fn (u64) u64
type PreferredDrop = fn (u64)
type PreferredText = fn (u64, u64, i64, u32) bool
type PreferredProbe = fn (u64, u64, &u64)

struct PreferredApi {
	entry u64
	copy PreferredCopy
	count PreferredCount
	at PreferredAt
	keep PreferredKeep
	drop PreferredDrop
	text PreferredText
}

fn preferred_api() PreferredApi {
	library := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
	entry := runtime_symbol(library, '_CFLocaleCopyPreferredLanguages') or { panic(err) }
	return PreferredApi{
		entry: entry
		copy: unsafe { PreferredCopy(voidptr(entry)) }
		count: unsafe { PreferredCount(voidptr(runtime_symbol(library, '_CFArrayGetCount') or { panic(err) })) }
		at: unsafe { PreferredAt(voidptr(runtime_symbol(library, '_CFArrayGetValueAtIndex') or { panic(err) })) }
		keep: unsafe { PreferredKeep(voidptr(runtime_symbol(library, '_CFRetain') or { panic(err) })) }
		drop: unsafe { PreferredDrop(voidptr(runtime_symbol(library, '_CFRelease') or { panic(err) })) }
		text: unsafe { PreferredText(voidptr(runtime_symbol(library, '_CFStringGetCString') or { panic(err) })) }
	}
}

fn preferred_probe_emit(code u64) {
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0003e2, 0xaa0003e3, 0xaa0003e4, 0xaa0003e5, 0xaa0003e6,
		0xaa0003e7, 0xaa0003e8, 0xaa0003f4, 0xd2824695, 0xd63f0200, 0xa9000660,
		0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn preferred_raw(entry u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { PreferredProbe(voidptr(code))(entry, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn preferred_native_owned() u64 {
	$if macos {
		pool := C.objc_autoreleasePoolPush()
		array := C.CFLocaleCopyPreferredLanguages()
		C.objc_autoreleasePoolPop(pool)
		return u64(array)
	}
	return 0
}

fn test_preferred_tag_profile() {
	for sample in [
		['en_US', 'en-US']!, ['fr_FR', 'fr-FR']!, ['sr_Latn_RS', 'sr-Latn-RS']!,
		['es_419', 'es-419']!, ['zh_CN', 'zh-Hans']!, ['zh_TW', 'zh-Hant']!,
		['zh_Hant_TW', 'zh-Hant-TW']!, ['EN_us', 'en-US']!, ['iw_IL', 'he-IL']!,
		['in_ID', 'id-ID']!, ['ji', 'yi']!, ['en_US_POSIX', 'en-US-POSIX']!,
		['de_DE@euro', 'de-DE']!, ['abc_XY', 'abc-XY']!, ['en-Latn-US', 'en-US']!
	]! {
		mut output := [160]u8{init: 0xa5}
		length := cf_preferred_tag_checked(sample[0], unsafe { &output[16] }) or { panic(err) }
		assert unsafe { tos(&output[16], length) } == sample[1]
		for i in 0 .. 16 { assert output[i] == 0xa5 && output[144 + i] == 0xa5 }
		$if macos {
			original := C.CFStringCreateWithCString(unsafe { nil }, unsafe { &char(sample[0].str) }, 0x08000100)
			native := C.CFLocaleCreateCanonicalLanguageIdentifierFromString(unsafe { nil }, original)
			mut bytes := [1024]u8{}
			assert native != unsafe { nil } && C.CFStringGetCString(native, unsafe { &char(&bytes[0]) }, 1024, 0x08000100)
			assert ctext(u64(unsafe { &bytes[0] })) == sample[1]
			C.CFRelease(native); C.CFRelease(original)
		}
	}
	mut bytes := [128]u8{}
	for invalid in ['', 'C', 'POSIX', 'english', 'en_', 'en__US', 'en-1', 'en-US-1996',
		'en-Latn-Latn', 'en-US-US', 'en-POSIX-Latn', 'en-US-POSIX-US', 'fr:de', 'fr/FR', 'eñ_ES']! {
		if _ := cf_preferred_tag_checked(invalid, unsafe { &bytes[0] }) { assert false, invalid }
	}
	page := usize(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != unsafe { voidptr(-1) }
	defer { assert C.munmap(mapping, page * 2) == 0 }
	input := u64(mapping) + u64(page) - 5
	C.memcpy(voidptr(input), c'fr_FR', 5)
	assert C.mprotect(mapping, page, C.PROT_READ) == 0 && C.mprotect(voidptr(u64(mapping) + u64(page)), page, C.PROT_NONE) == 0
	assert cf_preferred_tag_checked(unsafe { tos(&u8(input), 5) }, unsafe { &bytes[0] }) or { panic(err) } == 5
	assert unsafe { tos(&bytes[0], 5) } == 'fr-FR'
}

fn preferred_check(api PreferredApi, array u64, expected []string) {
	assert api.count(array) == expected.len && objc_is_kind(array, ios_runtime.names['NSArray'])
	for i, tag in expected {
		value := api.at(array, i64(i))
		mut bytes := [1024]u8{}
		assert api.text(value, u64(unsafe { &bytes[0] }), 1024, 0x08000100)
		assert ctext(u64(unsafe { &bytes[0] })) == tag
		assert objc_is_kind(value, ios_runtime.names['NSString'])
	}
}

fn preferred_case(api PreferredApi, expected []string, code u64, guard u64) {
	pool := objc_pool_push()
	first := api.copy()
	second := preferred_raw(api.entry, code, guard)
	assert first != 0 && second != 0 && first != second
	preferred_check(api, first, expected); preferred_check(api, second, expected)
	assert obj_header(first).refs == 1 && obj_header(second).refs == 1
	assert api.keep(first) == first
	objc_pool_pop(pool)
	assert obj_header(first).refs == 2
	api.drop(first)
	mut retained := u64(0)
	if expected.len > 0 { retained = api.keep(api.at(first, 0)) }
	api.drop(first)
	preferred_check(api, second, expected)
	api.drop(second)
	if retained != 0 {
		assert string_text(retained) == expected[0] && obj_header(retained).refs == 1
		api.drop(retained)
	}
}

fn preferred_worker(api PreferredApi, expected []string, code u64, guard u64) {
	for _ in 0 .. 24 { preferred_case(api, expected, code, guard) }
}

fn preferred_threads(api PreferredApi, expected []string, code u64, guard u64) {
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn preferred_worker(api, expected, code, guard) }
	workers.wait()
	unsafe { workers.free() }
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
}

fn preferred_environment_cases(api PreferredApi, code u64, guard u64) {
	$if linux {
		for item in [
			['fr_FR:de_DE:fr-FR:es_419', 'ja_JP', '', '', 'fr-FR:de-DE:es-419']!,
			['sr_Latn_RS::zh_TW:iw_IL', '', '', '', 'sr-Latn-RS:zh-Hant:he-IL']!,
			[':EN_us:en-US:in_ID:', '', '', '', 'en-US:id-ID']!,
			['', 'fr_FR.UTF-8', 'de_DE', 'ru_RU', 'fr-FR']!,
			['', '', 'de_DE@euro', 'ru_RU', 'de-DE']!,
			['', '', '', 'ru_RU.UTF-8', 'ru-RU']!,
			['::', 'C.UTF-8', '', '', 'en-US']!,
			['', '', '', '', 'en-US']!
		]! {
			for i, key in ['LANGUAGE', 'LC_ALL', 'LC_MESSAGES', 'LANG']! { os.setenv(key, item[i], true) }
			expected := item[4].split(':')
			preferred_case(api, expected, code, guard)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
			unsafe { expected.free() }
		}
		for key in ['LANGUAGE', 'LC_ALL', 'LC_MESSAGES', 'LANG']! { os.unsetenv(key) }
		preferred_case(api, ['en-US'], code, guard)
		mut tags := []string{}
		for i in 0 .. 33 {
			mut tag := [u8(`e`), `n`, `-`, u8(`A` + i / 26), u8(`A` + i % 26)]!
			tags << unsafe { tos(&tag[0], 5) }.clone()
		}
		allowed := tags[..32].join(':')
		os.setenv('LANGUAGE', allowed, true)
		preferred_case(api, tags[..32], code, guard)
		too_many := tags.join(':')
		too_long := 'a'.repeat(4096)
		for invalid in ['fr_FR:english', 'fr_FR:en-US-1996', 'fr_FR:en__US', too_many, too_long]! {
			os.setenv('LANGUAGE', invalid, true)
			if _ := cf_locale_copy_preferred_languages_checked() { assert false }
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		unsafe { allowed.free(); too_many.free(); too_long.free(); tags.free() }
		os.setenv('LANGUAGE', 'fr_FR:de_DE', true)
		first := api.copy()
		os.setenv('LANGUAGE', 'ja_JP', true)
		second := api.copy()
		preferred_check(api, first, ['fr-FR', 'de-DE'])
		preferred_check(api, second, ['ja-JP'])
		api.drop(first); api.drop(second)
		assert ios_runtime.live == 0
	}
}

fn test_cf_preferred_languages() {
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
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page * 2) == 0 }
	preferred_probe_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 88))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	mut expected := ['fr-FR', 'de-DE']
	$if macos {
		unsafe { expected.free() }; expected = []string{}
		native := voidptr(preferred_raw(u64(unsafe { voidptr(preferred_native_owned) }), u64(code), guard))
		count := C.CFArrayGetCount(native)
		assert count >= 0 && count <= 32
		for i := i64(0); i < count; i++ {
			mut bytes := [1024]u8{}
			assert C.CFStringGetCString(C.CFArrayGetValueAtIndex(native, i), unsafe { &char(&bytes[0]) }, 1024, 0x08000100)
			expected << ctext(u64(unsafe { &bytes[0] })).clone()
		}
		C.CFRelease(native)
		println('NATIVE-CF-PREFERRED-LANGUAGES: no-argument owned array after native pool drain, protected argument/x8 registers, exact complete preferred-language order and native canonical tag profile compared')
	}
	defer { unsafe { expected.free() } }
	if _ := cf_locale_copy_preferred_languages_checked() { assert false }
	for _ in 0 .. 2 {
		os.setenv('LANGUAGE', 'fr_FR:de_DE', true)
		objc_start()
		api := preferred_api()
		preferred_case(api, expected, u64(code), guard)
		preferred_threads(api, expected, u64(code), guard)
		preferred_environment_cases(api, u64(code), guard)
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFLocaleCopyPreferredLanguages') { assert false }
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
		if _ := cf_locale_copy_preferred_languages_checked() { assert false }
	}
	println('IOS-CF-PREFERRED-LANGUAGES: scoped no-argument owned immutable array and copied strings, full native order or bounded Vinix priority list and locale fallback, canonical tags/deduplication, protected ABI, independent snapshots, retained elements, 32-entry/error cleanup, concurrent calls and two drained runtimes')
}
