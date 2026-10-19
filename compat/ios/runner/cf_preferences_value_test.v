// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist

$if macos {
	#define dispatch_sync vinix_native_header_dispatch_sync
	#include <CoreFoundation/CFPreferences.h>
	#include <CoreFoundation/CFPropertyList.h>
	#include <CoreFoundation/CFDictionary.h>
	#include <CoreFoundation/CFData.h>
	#include <CoreFoundation/CFNumber.h>
	#undef dispatch_sync
	fn C.CFPreferencesSetAppValue(voidptr, voidptr, voidptr)
	fn C.CFPreferencesCopyAppValue(voidptr, voidptr) voidptr
	fn C.CFPreferencesAppSynchronize(voidptr) u8
	fn C.CFPropertyListCreateWithData(voidptr, voidptr, u64, voidptr, voidptr) voidptr
	fn C.CFDataCreate(voidptr, &u8, i64) voidptr
	fn C.CFEqual(voidptr, voidptr) bool
	fn C.CFGetTypeID(voidptr) u64
	fn C.CFBooleanGetTypeID() u64
	fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr
}

const prefs_value_xml = '<plist version="1.0"><dict><key>text</key><string>&amp;&lt;✅🚀&gt;</string><key>integer</key><integer>-42</integer><key>real</key><real>1.25</real><key>boolean</key><true/><key>data</key><data>AAH/</data><key>array</key><array><string>child</string><false/></array><key>dictionary</key><dict><key>nested</key><integer>7</integer></dict></dict></plist>'

type PrefValueCopy = fn (u64, u64) u64
type PrefValueDrop = fn (u64)
type PrefValueSync = fn (u64) u8
type PrefValueSend = fn (u64, u64, u64, u64) u64
type PrefValueProbe = fn (u64, u64, u64, u64, &u64)

fn pref_value_message(object u64, selector &char, first u64, second u64) u64 {
	return unsafe { PrefValueSend(voidptr(C.ios_objc_builtin))(object, objc_selector(selector), first, second) }
}

fn pref_value_emit(code u64) {
	// key/application in x0/x1; x2..x8 contain a protected page address.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5,
		0xaa0203e6, 0xaa0203e7, 0xaa0203e8, 0xaa0203f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn pref_value_raw(entry u64, key u64, application u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { PrefValueProbe(voidptr(code))(entry, key, application, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn pref_value_native_copy(key u64, application u64) u64 {
	$if macos { return u64(C.CFPreferencesCopyAppValue(voidptr(key), voidptr(application))) }
	return 0
}

fn pref_value_native(root string, code u64, guard u64) {
	$if macos {
		pool := C.objc_autoreleasePoolPush()
		path := root + '/native-domain'
		defer { unsafe { path.free() } }
		domain := C.CFStringCreateWithCString(unsafe { nil }, unsafe { &char(path.str) }, 0x08000100)
		key := C.CFStringCreateWithCString(unsafe { nil }, c'vinix-isolated-key', 0x08000100)
		other_key := C.CFStringCreateWithCString(unsafe { nil }, c'vinix-isolated-key', 0x08000100)
		data := C.CFDataCreate(unsafe { nil }, prefs_value_xml.str, prefs_value_xml.len)
		profile := C.CFPropertyListCreateWithData(unsafe { nil }, data, 0, unsafe { nil }, unsafe { nil })
		C.CFRelease(data); assert profile != unsafe { nil }
		entry := u64(unsafe { voidptr(pref_value_native_copy) })
		assert pref_value_raw(entry, u64(key), u64(domain), code, guard) == 0
		C.CFPreferencesSetAppValue(key, profile, domain)
		copied := pref_value_raw(entry, u64(other_key), u64(domain), code, guard)
		assert copied != 0 && C.CFEqual(voidptr(copied), profile)
		boolean_key := C.CFStringCreateWithCString(unsafe { nil }, c'boolean', 0x08000100)
		assert C.CFGetTypeID(C.CFDictionaryGetValue(voidptr(copied), boolean_key)) == C.CFBooleanGetTypeID()
		C.CFRelease(boolean_key)
		C.CFPreferencesSetAppValue(key, unsafe { nil }, domain)
		assert pref_value_raw(entry, u64(key), u64(domain), code, guard) == 0
		assert C.CFPreferencesAppSynchronize(domain) == 1
		C.objc_autoreleasePoolPop(pool)
		assert C.CFEqual(voidptr(copied), profile)
		C.CFRelease(voidptr(copied)); C.CFRelease(profile); C.CFRelease(other_key); C.CFRelease(key); C.CFRelease(domain)
		println('NATIVE-CF-PREFERENCES-VALUE: guarded two-argument ABI, absent nil, equal key, seven plist types including CFBoolean, owned result after removal and native pool compared')
	}
}

fn pref_value_assert(object u64, expected plist.Value) {
	assert object != 0 && obj_header(object).refs >= 1
	match expected.kind {
		.string { assert cf_type_id(object) == cf_string_id() && string_text(object) == expected.text }
		.integer { assert cf_type_id(object) == cf_number_id() && !obj_header(object).is_real && obj_header(object).number == expected.integer }
		.real { assert cf_type_id(object) == cf_number_id() && obj_header(object).is_real && obj_header(object).real_number == expected.real }
		.boolean { assert cf_type_id(object) == cf_boolean_id() && cf_boolean_value(object) == expected.boolean }
		.data {
			assert cf_type_id(object) == cf_data_id() && data_length(object) == u64(expected.data.len)
			assert expected.data.len == 0 || C.memcmp(voidptr(data_pointer(object)), expected.data.data, usize(expected.data.len)) == 0
		}
		.array {
			header := obj_header(object)
			assert read64(object) == ios_runtime.names['NSArray'] && header.json_immutable && header.items.len == expected.values.len
			for i, item in expected.values { pref_value_assert(header.items[i], item) }
		}
		.dictionary {
			header := obj_header(object)
			assert read64(object) == ios_runtime.names['NSDictionary'] && header.json_immutable && header.keys.len == expected.fields.len
			for text, item in expected.fields {
				key := owned_string(text); index := dictionary_index(header, key); objc_release(key)
				assert index >= 0; pref_value_assert(header.items[index], item)
			}
		}
	}
}

fn pref_value_worker(copy PrefValueCopy, domain u64, key u64, expected plist.Value) {
	for _ in 0 .. 32 {
		object := copy(key, domain)
		pref_value_assert(object, expected)
		objc_release(object)
	}
}

fn test_cf_preferences_value() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page * 2) == 0 }
	pref_value_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	if _ := cf_preferences_value_checked(0, 0) { assert false }
	old_documents := os.getenv('VINIX_IOS_DOCUMENTS')
	defer { os.setenv('VINIX_IOS_DOCUMENTS', old_documents, true); unsafe { old_documents.free() } }
	root := os.join_path(os.temp_dir(), 'vinix-cf-preferences-value-' + os.getpid().str())
	assert !os.exists(root); os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or { panic(err) }; unsafe { root.free() } }
	bundle := root + '/Different.app'; os.mkdir(bundle) or { panic(err) }
	info_path := bundle + '/Info.plist'
	os.write_file(info_path, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.vinix.PreferenceValue</string></dict></plist>') or { panic(err) }
	documents := root + '/Documents'; directory := documents + '/Library/Preferences'; os.mkdir_all(directory) or { panic(err) }
	path := directory + '/com.vinix.PreferenceValue.plist'
	os.write_file(path, prefs_value_xml) or { panic(err) }
	defer { unsafe { path.free(); directory.free(); documents.free(); info_path.free(); bundle.free() } }
	expected := plist.parse(prefs_value_xml.bytes()) or { panic(err) }
	defer { expected.free() }
	lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
	for iteration in 0 .. 2 {
		pref_value_native(root, u64(code), guard)
		objc_start(); ios_runtime.bundle = bundle
		os.setenv('VINIX_IOS_DOCUMENTS', documents, true)
		entry := runtime_symbol(lib, '_CFPreferencesCopyAppValue') or { panic(err) }
		copy := unsafe { PrefValueCopy(voidptr(entry)) }
		drop := unsafe { PrefValueDrop(voidptr(runtime_symbol(lib, '_CFRelease') or { panic(err) })) }
		sync := unsafe { PrefValueSync(voidptr(runtime_symbol(lib, '_CFPreferencesAppSynchronize') or { panic(err) })) }
		current := read64(runtime_symbol(lib, '_kCFPreferencesCurrentApplication') or { panic(err) })
		domain := owned_string('com.vinix.PreferenceValue')
		missing := owned_string('missing'); assert pref_value_raw(entry, missing, current, u64(code), guard) == 0
		defaults := pref_value_message(ios_runtime.names['NSUserDefaults'], c'standardUserDefaults', 0, 0)
		pool := objc_pool_push()
		for text, item in expected.fields {
			key := owned_string(text)
			value := pref_value_raw(entry, key, domain, u64(code), guard)
			pref_value_assert(value, item)
			assert obj_header(value).refs == 1 && obj_header(key).refs == 1 && obj_header(domain).refs == 1
			assert value != pref_value_message(defaults, c'objectForKey:', key, 0)
			drop(value); objc_release(key)
		}
		// Both arguments can be image CFString constants without ObjHeaders.
		mut key_record := [ios_runtime.names['NSString'], u64(0x7c8), u64('text'.str), u64(4)]!
		mut domain_record := [ios_runtime.names['NSString'], u64(0x7c8), u64('kCFPreferencesCurrentApplication'.str), u64(32)]!
		key_address := u64(unsafe { &key_record[0] }); domain_address := u64(unsafe { &domain_record[0] })
		ios_runtime.constants[key_address] = true; ios_runtime.constants[domain_address] = true
		literal := pref_value_raw(entry, key_address, domain_address, u64(code), guard)
		assert string_text(literal) == '&<✅🚀>'; drop(literal)
		ios_runtime.constants.delete(key_address); ios_runtime.constants.delete(domain_address)
		// Registration participates in reads, while persistent values win.
		registered := objc_allocate(ios_runtime.names['NSMutableDictionary'])
		fallback := owned_string('registered-fallback'); text_key := owned_string('text'); fallback_text := owned_string('fallback')
		dictionary_put(registered, fallback, fallback_text); dictionary_put(registered, text_key, fallback_text)
		pref_value_message(defaults, c'registerDefaults:', registered, 0); objc_release(registered)
		registered_copy := copy(fallback, domain); assert string_text(registered_copy) == 'fallback'; drop(registered_copy)
		persistent := copy(text_key, current); assert string_text(persistent) == '&<✅🚀>'; drop(persistent)
		boolean_key := owned_string('setter-boolean')
		if iteration == 0 { pref_value_message(defaults, c'setBool:forKey:', 1, boolean_key) }
		boolean := copy(boolean_key, current); assert cf_type_id(boolean) == cf_boolean_id() && cf_boolean_value(boolean); drop(boolean)
		assert sync(domain) == 1
		bytes := os.read_bytes(path) or { panic(err) }; persisted := plist.parse(bytes) or { panic(err) }; unsafe { bytes.free() }
		assert 'registered-fallback' !in persisted.fields && persisted.fields['setter-boolean'].kind == .boolean; persisted.free()
		objc_pool_pop(pool)
		array_key := owned_string('array'); dictionary_key := owned_string('dictionary'); baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn pref_value_worker(copy, domain, dictionary_key, expected.fields['dictionary']) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline
		for _ in 0 .. 64 { value := copy(dictionary_key, domain); drop(value); assert copy(missing, current) == 0 }
		assert ios_runtime.live == baseline
		for invalid in [u64(0), guard, defaults, ios_runtime.names['NSString']]! {
			if _ := cf_preferences_value_checked(invalid, current) { assert false }
			if _ := cf_preferences_value_checked(array_key, invalid) { assert false }
		}
		other := owned_string('com.another.application')
		if _ := cf_preferences_value_checked(array_key, other) { assert false }; objc_release(other)
		// The copy owns its child after replacing the stored source and pool drain.
		owned := copy(array_key, current); child := obj_header(owned).items[0]
		mut weak_copy := u64(0); mut weak_child := u64(0)
		objc_store_weak(unsafe { &weak_copy }, owned); objc_store_weak(unsafe { &weak_child }, child)
		if iteration == 1 {
			pref_value_message(defaults, c'removeObjectForKey:', array_key, 0)
			assert copy(array_key, current) == 0
		} else { pref_value_message(defaults, c'setObject:forKey:', owned, array_key) }
		objc_pool_drain_all()
		assert string_text(child) == 'child' && weak_copy == owned && weak_child == child
		drop(owned); assert weak_copy == 0 && weak_child == 0
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFPreferencesCopyAppValue') { assert false }
		}
		for object in [domain, missing, fallback, text_key, fallback_text, boolean_key, array_key, dictionary_key]! { objc_release(object) }
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		if _ := cf_preferences_value_checked(0, current) { assert false }
	}
	println('IOS-CF-PREFERENCES-VALUE: owned immutable plist snapshots, registration fallback and persistent precedence, Boolean-preserving save/reload, absent nil, content-equal allocated/image keys and domains, guarded two-argument ABI, no autorelease growth, concurrent readers, replaced-source child lifetime and two drained runtimes')
}
