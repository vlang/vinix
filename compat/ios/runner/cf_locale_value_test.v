// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

type ValueGet = fn (u64, u64) u64
type ValueKeep = fn (u64) u64
type ValueDrop = fn (u64)
type ValueCopy = fn () u64
type ValueProbe = fn (u64, u64, u64, u64, &u64)
type ValueSend = fn (u64, u64, u64, u64) u64

struct ValueApi {
	entry u64
	get ValueGet
	keep ValueKeep
	drop ValueDrop
	copy ValueCopy
	language u64
	country u64
	identifier u64
}

fn value_api() ValueApi {
	lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
	entry := runtime_symbol(lib, '_CFLocaleGetValue') or { panic(err) }
	return ValueApi{
		entry: entry
		get: unsafe { ValueGet(voidptr(entry)) }
		keep: unsafe { ValueKeep(voidptr(runtime_symbol(lib, '_CFRetain') or { panic(err) })) }
		drop: unsafe { ValueDrop(voidptr(runtime_symbol(lib, '_CFRelease') or { panic(err) })) }
		copy: unsafe { ValueCopy(voidptr(runtime_symbol(lib, '_CFLocaleCopyCurrent') or { panic(err) })) }
		language: read64(runtime_symbol(lib, '_kCFLocaleLanguageCode') or { panic(err) })
		country: read64(runtime_symbol(lib, '_kCFLocaleCountryCode') or { panic(err) })
		identifier: read64(runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_NSLocaleIdentifier') or { panic(err) })
	}
}

fn value_emit(code u64) {
	// Real locale/key in x0/x1; x2..x8 point at PROT_NONE memory.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5,
		0xaa0203e6, 0xaa0203e7, 0xaa0203e8, 0xaa0203f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn value_raw(entry u64, locale u64, key u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { ValueProbe(voidptr(code))(entry, locale, key, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn value_native(locale u64, key u64) u64 {
	$if macos { return u64(C.CFLocaleGetValue(voidptr(locale), voidptr(key))) }
	return 0
}

fn test_locale_component_profile() {
	for item in [
		['', '', '']!, ['C', 'c', '']!, ['POSIX', 'posix', '']!, ['en', 'en', '']!,
		['EN_us', 'en', 'US']!, ['fr_FR', 'fr', 'FR']!, ['es_419', 'es', '419']!,
		['zh_CN', 'zh', 'CN']!, ['zh-Hant-TW', 'zh', 'TW']!, ['sr_Latn_RS', 'sr', 'RS']!,
		['en_US_POSIX', 'en', 'US']!, ['en__POSIX', 'en', '']!, ['iw_IL', 'he', 'IL']!,
		['in_ID', 'id', 'ID']!, ['ji', 'yi', '']!
	]! {
		mut bytes := [32]u8{init: 0xa5}
		parts := cf_locale_parts_checked(item[0], unsafe { &bytes[8] }) or { panic(err) }
		assert unsafe { tos(&bytes[8], parts.language_length) } == item[1]
		assert unsafe { tos(&bytes[16], parts.country_length) } == item[2]
		for i in 0 .. 8 { assert bytes[i] == 0xa5 && bytes[24 + i] == 0xa5 }
	}
	mut output := [16]u8{}
	for invalid in ['english', 'abc_XY', 'en_', 'en__US', 'en-US-US', 'en-POSIX',
		'en-Latn-Latn', 'en_US_OTHER', 'en_US.UTF-8', 'de_DE@currency=EUR', 'fr/FR', 'éé_FR']! {
		if _ := cf_locale_parts_checked(invalid, unsafe { &output[0] }) { assert false, invalid }
	}
	page := usize(C.getpagesize())
	memory := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert memory != unsafe { voidptr(-1) }
	defer { assert C.munmap(memory, page * 2) == 0 }
	input := u64(memory) + u64(page) - 5
	C.memcpy(voidptr(input), c'fr_FR', 5)
	assert C.mprotect(memory, page, C.PROT_READ) == 0 && C.mprotect(voidptr(u64(memory) + u64(page)), page, C.PROT_NONE) == 0
	parts := cf_locale_parts_checked(unsafe { tos(&u8(input), 5) }, unsafe { &output[0] }) or { panic(err) }
	assert parts.language_length == 2 && parts.country_length == 2
}

fn value_locale(identifier string) u64 {
	locale := objc_allocate(ios_runtime.names['NSLocale'])
	name := owned_string(identifier)
	store_field(locale, 0, name); objc_release(name)
	return locale
}

fn value_message(locale u64, key u64) u64 {
	return unsafe { ValueSend(voidptr(C.ios_objc_builtin))(locale, objc_selector(c'objectForKey:'), key, 0) }
}

fn value_case(api ValueApi, item [3]string, code u64, guard u64) {
	baseline := ios_runtime.live
	pool := objc_pool_push()
	locale := value_locale(item[0])
	assert api.get(locale, api.identifier) == obj_header(locale).fields[0]
	assert !obj_header(locale).valid && ios_runtime.live == baseline + 2
	$if macos {
		native_pool := C.objc_autoreleasePoolPush()
		name := C.CFStringCreateWithCString(unsafe { nil }, unsafe { &char(item[0].str) }, 0x08000100)
		native := C.CFLocaleCreate(unsafe { nil }, name)
		for i, key in [voidptr(C.kCFLocaleLanguageCode), voidptr(C.kCFLocaleCountryCode)]! {
			value := value_raw(u64(unsafe { voidptr(value_native) }), u64(native), u64(key), code, guard)
			if i == 1 && item[2] == '<nil>' { assert value == 0; continue }
			mut bytes := [1024]u8{}
			assert value != 0 && C.CFStringGetCString(voidptr(value), unsafe { &char(&bytes[0]) }, 1024, 0x08000100)
			assert ctext(u64(unsafe { &bytes[0] })) == item[i + 1]
		}
		C.CFRelease(native); C.CFRelease(name); C.objc_autoreleasePoolPop(native_pool)
	}
	language := value_raw(api.entry, locale, api.language, code, guard)
	country := api.get(locale, api.country)
	assert language != 0 && string_text(language) == item[1]
	if item[2] == '<nil>' { assert country == 0 } else { assert country != 0 && string_text(country) == item[2] }
	assert obj_header(locale).valid && obj_header(language).refs == 1 && obj_header(locale).refs == 1
	if country != 0 { assert obj_header(country).refs == 1 }
	before := ios_runtime.live
	for _ in 0 .. 32 {
		assert api.get(locale, api.language) == language && api.get(locale, api.country) == country
		assert value_message(locale, api.language) == language && value_message(locale, api.country) == country
	}
	assert ios_runtime.live == before
	alias := owned_string('kCFLocaleCountryCodeKey')
	assert api.get(locale, alias) == country; objc_release(alias)
	assert value_message(locale, api.identifier) == obj_header(locale).fields[0]
	mut weak_owner := u64(0); mut weak_language := u64(0); mut weak_country := u64(0)
	objc_store_weak(unsafe { &weak_owner }, locale)
	objc_store_weak(unsafe { &weak_language }, language)
	objc_store_weak(unsafe { &weak_country }, country)
	assert api.keep(language) == language
	objc_pool_pop(pool)
	assert api.get(locale, api.language) == language && obj_header(language).refs == 2
	api.drop(locale)
	assert weak_owner == 0 && weak_country == 0 && weak_language == language && obj_header(language).refs == 1
	assert string_text(language) == item[1]
	api.drop(language)
	assert weak_language == 0 && ios_runtime.live == baseline
}

fn value_worker(api ValueApi, locale u64) {
	for _ in 0 .. 80 {
		language := api.get(locale, api.language)
		country := api.get(locale, api.country)
		assert language != 0 && value_message(locale, api.language) == language
		assert value_message(locale, api.country) == country
	}
}

fn value_rejections(api ValueApi) {
	baseline := ios_runtime.live
	locale := value_locale('fr_FR')
	unknown := owned_string('not-a-locale-key')
	assert api.get(locale, unknown) == 0 && !obj_header(locale).valid
	objc_release(unknown)
	for text in ['kCFLocaleScriptCodeKey', 'calendar', 'currency', 'kCFLocaleUsesMetricSystemKey']! {
		key := owned_string(text)
		if _ := cf_locale_value_checked(locale, key) { assert false }
		assert !obj_header(locale).valid; objc_release(key)
	}
	for receiver in [u64(0), api.language, ios_runtime.names['NSLocale']]! {
		if _ := cf_locale_value_checked(receiver, api.language) { assert false }
	}
	if _ := cf_locale_value_checked(locale, 0) { assert false }
	if _ := cf_locale_value_checked(locale, locale) { assert false }
	objc_release(locale)
	uninitialized := objc_allocate(ios_runtime.names['NSLocale'])
	if _ := cf_locale_value_checked(uninitialized, api.language) { assert false }
	objc_release(uninitialized)
	$if linux {
		for text in ['abc_XY', 'fr_FR@currency=EUR', 'en__US']! {
			bad := value_locale(text)
			if _ := cf_locale_value_checked(bad, api.country) { assert false }
			assert !obj_header(bad).valid && obj_header(bad).fields[1] == 0 && obj_header(bad).fields[2] == 0
			objc_release(bad)
		}
	}
	assert ios_runtime.live == baseline
}

fn test_cf_locale_value() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page * 2) == 0 }
	value_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	if _ := cf_locale_value_checked(0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		api := value_api()
		for item in [['', '', '<nil>']!, ['c', 'c', '<nil>']!, ['posix', 'posix', '<nil>']!,
			['en', 'en', '<nil>']!, ['en_US', 'en', 'US']!, ['fr_FR', 'fr', 'FR']!,
			['de_DE', 'de', 'DE']!, ['ru_RU', 'ru', 'RU']!, ['es_419', 'es', '419']!,
			['zh_CN', 'zh', 'CN']!, ['zh-Hant-TW', 'zh', 'TW']!, ['sr-Latn_RS', 'sr', 'RS']!,
			['en_US_POSIX', 'en', 'US']!, ['en__POSIX', 'en', '<nil>']!, ['he_IL', 'he', 'IL']!,
			['id_ID', 'id', 'ID']!, ['yi', 'yi', '<nil>']!]! {
			value_case(api, item, u64(code), guard)
		}
		$if macos { println('NATIVE-CF-LOCALE-VALUE: guarded two-argument ABI, full language/country matrix including root and absent region, aliases, scripts, numeric regions and POSIX compared') }
		value_rejections(api)
		locale := api.copy()
		assert !obj_header(locale).valid
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn value_worker(api, locale) }
		workers.wait(); unsafe { workers.free() }
		language := api.get(locale, api.language); country := api.get(locale, api.country)
		assert obj_header(locale).refs == 2 && obj_header(language).refs == 1
		if country != 0 { assert obj_header(country).refs == 1 }
		mut weak_language := u64(0)
		objc_store_weak(unsafe { &weak_language }, language)
		api.drop(locale)
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFLocaleGetValue') { assert false }
		}
		objc_stop()
		assert weak_language == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
		if _ := cf_locale_value_checked(locale, api.language) { assert false }
	}
	println('IOS-CF-LOCALE-VALUE: scoped borrowed identifier/language/country values, native snapshots or bounded Vinix components, cached absent country, key-content equality and unknown nil, protected ABI, NSLocale objectForKey integration, retained-child lifetime, explicit unsupported queries, concurrent cold cache and two drained runtimes')
}
