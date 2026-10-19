// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist
import math

$if macos {
	#define dispatch_sync vinix_native_header_dispatch_sync
	#include <CoreFoundation/CFPreferences.h>
	#include <CoreFoundation/CFPropertyList.h>
	#include <CoreFoundation/CFDictionary.h>
	#include <CoreFoundation/CFNumber.h>
	#undef dispatch_sync
	fn C.CFPreferencesSetAppValue(voidptr, voidptr, voidptr)
	fn C.CFPreferencesCopyAppValue(voidptr, voidptr) voidptr
	fn C.CFPreferencesAppSynchronize(voidptr) u8
	fn C.CFPropertyListCreateWithData(voidptr, voidptr, u64, voidptr, voidptr) voidptr
	fn C.CFDataCreate(voidptr, &u8, i64) voidptr
	fn C.CFEqual(voidptr, voidptr) bool
}

const pref_set_xml = '<plist version="1.0"><dict><key>text</key><string>&amp;&lt;✅🚀&gt;</string><key>integer</key><integer>-42</integer><key>real</key><real>1.25</real><key>boolean</key><true/><key>data</key><data>AAH/</data><key>array</key><array><string>child</string><false/></array><key>dictionary</key><dict><key>nested</key><integer>7</integer></dict></dict></plist>'

type PrefSet = fn (u64, u64, u64)
type PrefSetCopy = fn (u64, u64) u64
type PrefSetSync = fn (u64) u8
type PrefSetSend = fn (u64, u64, u64, u64) u64
type PrefSetProbe = fn (u64, u64, u64, u64, u64, &u64)

fn pref_set_message(object u64, selector &char, first u64, second u64) u64 {
	return unsafe { PrefSetSend(voidptr(C.ios_objc_builtin))(object, objc_selector(selector), first, second) }
}

fn pref_set_emit(code u64) {
	// key/value/application in x0..x2; x3..x8 contain a protected page.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0303e4, 0xaa0303e5,
		0xaa0303e6, 0xaa0303e7, 0xaa0303e8, 0xaa0303f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn pref_set_raw(entry u64, key u64, value u64, domain u64, code u64, guard u64) {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { PrefSetProbe(voidptr(code))(entry, key, value, domain, guard, &capture[1]) }
	// The API has no return value. x0/x1 are intentionally ignored.
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
}

fn pref_set_native_call(key u64, value u64, domain u64) {
	$if macos { C.CFPreferencesSetAppValue(voidptr(key), voidptr(value), voidptr(domain)) }
}

fn pref_set_native(root string, code u64, guard u64) {
	$if macos {
		pool := C.objc_autoreleasePoolPush()
		defer { C.objc_autoreleasePoolPop(pool) }
		path := root + '/native-domain'; defer { unsafe { path.free() } }
		domain := C.CFStringCreateWithCString(unsafe { nil }, unsafe { &char(path.str) }, 0x08000100)
		key := C.CFStringCreateWithCString(unsafe { nil }, c'vinix-native-key', 0x08000100)
		data := C.CFDataCreate(unsafe { nil }, pref_set_xml.str, pref_set_xml.len)
		profile := C.CFPropertyListCreateWithData(unsafe { nil }, data, 0, unsafe { nil }, unsafe { nil })
		C.CFRelease(data); assert profile != unsafe { nil }
		entry := u64(unsafe { voidptr(pref_set_native_call) })
		pref_set_raw(entry, u64(key), u64(profile), u64(domain), code, guard)
		copied := C.CFPreferencesCopyAppValue(key, domain)
		assert copied != unsafe { nil } && C.CFEqual(copied, profile)
		C.CFRelease(profile)
		pref_set_raw(entry, u64(key), 0, u64(domain), code, guard)
		pref_set_raw(entry, u64(key), 0, u64(domain), code, guard)
		assert C.CFPreferencesCopyAppValue(key, domain) == unsafe { nil } && C.CFPreferencesAppSynchronize(domain) == 1
		C.CFRelease(copied); C.CFRelease(key); C.CFRelease(domain)
		println('NATIVE-CF-PREFERENCES-SET: guarded three-pointer void ABI, seven plist types, caller ownership, replacement/removal and repeated missing-key removal compared')
	}
}

fn pref_set_assert(object u64, expected plist.Value) {
	assert object != 0
	header := obj_header(object)
	match expected.kind {
		.string { assert string_text(object) == expected.text }
		.integer { assert cf_type_id(object) == cf_number_id() && !header.is_real && header.number == expected.integer }
		.real { assert cf_type_id(object) == cf_number_id() && header.is_real && header.real_number == expected.real }
		.boolean { assert cf_type_id(object) == cf_boolean_id() && cf_boolean_value(object) == expected.boolean }
		.data { assert data_length(object) == u64(expected.data.len) && (expected.data.len == 0 || C.memcmp(voidptr(data_pointer(object)), expected.data.data, usize(expected.data.len)) == 0) }
		.array { assert read64(object) == ios_runtime.names['NSArray'] && header.json_immutable && header.items.len == expected.values.len; for i, item in expected.values { pref_set_assert(header.items[i], item) } }
		.dictionary {
			assert read64(object) == ios_runtime.names['NSDictionary'] && header.json_immutable && header.keys.len == expected.fields.len
			for text, item in expected.fields {
				key := owned_string(text); index := dictionary_index(header, key); objc_release(key)
				assert index >= 0; pref_set_assert(header.items[index], item)
			}
		}
	}
}

fn pref_set_worker(set PrefSet, copy PrefSetCopy, domain u64, key u64, value u64) {
	for _ in 0 .. 32 {
		set(key, value, domain)
		found := copy(key, domain); assert string_text(found) == string_text(value); objc_release(found)
		set(key, 0, domain); assert copy(key, domain) == 0
	}
}

fn pref_set_rejections(set PrefSet, copy PrefSetCopy, key u64, domain u64, guard u64) {
	baseline := ios_runtime.live
	for invalid in [u64(0), guard, ios_runtime.names['NSString']]! {
		if _ := cf_preferences_set_checked(invalid, 0, domain) { assert false }
		if _ := cf_preferences_set_checked(key, 0, invalid) { assert false }
	}
	for text in ['com.another.application', 'kCFPreferencesAnyApplication']! {
		other := owned_string(text); if _ := cf_preferences_set_checked(key, 0, other) { assert false }; objc_release(other)
	}
	if _ := cf_preferences_set_checked(key, guard, domain) { assert false }
	bad := objc_allocate(ios_runtime.names['NSObject'])
	array := objc_allocate(ios_runtime.names['NSMutableArray'])
	mut header := obj_header(array); array_append(mut header, key); array_append(mut header, bad)
	if _ := cf_preferences_set_checked(key, array, domain) { assert false }
	objc_release(array); objc_release(bad)
	raw := cf_dictionary_mutable(0, 0, 0, 0); cf_dictionary_set(raw, guard, guard)
	if _ := cf_preferences_set_checked(key, raw, domain) { assert false }; objc_release(raw)
	cycle := objc_allocate(ios_runtime.names['NSMutableArray']); mut cyclic := obj_header(cycle); array_append(mut cyclic, cycle)
	if _ := cf_preferences_set_checked(key, cycle, domain) { assert false }; collection_remove(mut cyclic, 0); objc_release(cycle)
	for real in [math.nan(), math.inf(1), math.inf(-1)]! {
		number := objc_allocate(ios_runtime.names['NSNumber']); mut h := obj_header(number); h.is_real = true; h.real_number = real
		if _ := cf_preferences_set_checked(key, number, domain) { assert false }; objc_release(number)
	}
	assert ios_runtime.live == baseline
	old := copy(key, domain); assert string_text(old) == 'unchanged'; objc_release(old)
	set(key, 0, domain)
}

fn test_cf_preferences_set() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }; defer { assert C.munmap(code, page * 2) == 0 }
	pref_set_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	if _ := cf_preferences_set_checked(0, 0, 0) { assert false }
	old_documents := os.getenv('VINIX_IOS_DOCUMENTS'); defer { os.setenv('VINIX_IOS_DOCUMENTS', old_documents, true); unsafe { old_documents.free() } }
	root := os.join_path(os.temp_dir(), 'vinix-cf-preferences-set-' + os.getpid().str())
	assert !os.exists(root); os.mkdir_all(root) or { panic(err) }; defer { os.rmdir_all(root) or { panic(err) }; unsafe { root.free() } }
	bundle := root + '/Different.app'; os.mkdir(bundle) or { panic(err) }
	info_path := bundle + '/Info.plist'; os.write_file(info_path, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.vinix.PreferenceSet</string></dict></plist>') or { panic(err) }
	documents := root + '/Documents'; path := documents + '/Library/Preferences/com.vinix.PreferenceSet.plist'
	defer { unsafe { path.free(); documents.free(); info_path.free(); bundle.free() } }
	expected := plist.parse(pref_set_xml.bytes()) or { panic(err) }; defer { expected.free() }
	lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
	for iteration in 0 .. 2 {
		pref_set_native(root, u64(code), guard)
		objc_start(); ios_runtime.bundle = bundle; os.setenv('VINIX_IOS_DOCUMENTS', documents, true)
		entry := runtime_symbol(lib, '_CFPreferencesSetAppValue') or { panic(err) }
		set := unsafe { PrefSet(voidptr(entry)) }
		copy := unsafe { PrefSetCopy(voidptr(runtime_symbol(lib, '_CFPreferencesCopyAppValue') or { panic(err) })) }
		sync := unsafe { PrefSetSync(voidptr(runtime_symbol(lib, '_CFPreferencesAppSynchronize') or { panic(err) })) }
		current := read64(runtime_symbol(lib, '_kCFPreferencesCurrentApplication') or { panic(err) })
		domain := owned_string('com.vinix.PreferenceSet')
		key := owned_string('profile'); absent := owned_string('absent'); fallback := owned_string('fallback')
		if iteration == 1 {
			reloaded := copy(key, domain); pref_set_assert(reloaded, expected); objc_release(reloaded)
			assert copy(absent, domain) == 0
		}
		value := plist_owned_object(expected)
		pref_set_raw(entry, key, value, domain, u64(code), guard)
		assert obj_header(value).refs == 1 && obj_header(key).refs == 1 && obj_header(domain).refs == 1
		objc_release(value)
		pref_set_raw(entry, absent, 0, current, u64(code), guard)
		if iteration == 0 { assert !os.exists(path) }
		defaults := pref_set_message(ios_runtime.names['NSUserDefaults'], c'standardUserDefaults', 0, 0)
		pref_set_assert(pref_set_message(defaults, c'objectForKey:', key, 0), expected)
		owned := copy(key, current); pref_set_assert(owned, expected)
		registration := objc_allocate(ios_runtime.names['NSMutableDictionary']); fallback_value := owned_string('registered')
		dictionary_put(registration, fallback, fallback_value); pref_set_message(defaults, c'registerDefaults:', registration, 0); objc_release(registration); objc_release(fallback_value)
		override := owned_string('override'); set(fallback, override, domain); objc_release(override)
		set(fallback, 0, current); found := copy(fallback, domain); assert string_text(found) == 'registered'; objc_release(found)
		// Mutable arrays are copied immediately, including their children.
		mutable := objc_allocate(ios_runtime.names['NSMutableArray']); mut source := obj_header(mutable)
		child := owned_string('child'); array_append(mut source, child); objc_release(child)
		set(absent, mutable, current); extra := owned_string('later'); array_append(mut source, extra); objc_release(extra); objc_release(mutable)
		copied := copy(absent, domain); assert obj_header(copied).items.len == 1 && string_text(obj_header(copied).items[0]) == 'child'; objc_release(copied)
		set(absent, 0, current); assert copy(absent, domain) == 0
		// Image constants can supply all three parameters, including nil removal.
		mut kr := [ios_runtime.names['NSString'], u64(0x7c8), u64('image-key'.str), u64(9)]!
		mut vr := [ios_runtime.names['NSString'], u64(0x7c8), u64('literal'.str), u64(7)]!
		mut ar := [ios_runtime.names['NSString'], u64(0x7c8), u64('kCFPreferencesCurrentApplication'.str), u64(32)]!
		ka := u64(unsafe { &kr[0] }); va := u64(unsafe { &vr[0] }); aa := u64(unsafe { &ar[0] })
		for object in [ka, va, aa]! { ios_runtime.constants[object] = true }
		pref_set_raw(entry, ka, va, aa, u64(code), guard); literal := copy(ka, domain); assert string_text(literal) == 'literal'; objc_release(literal)
		pref_set_raw(entry, ka, 0, aa, u64(code), guard); assert copy(ka, current) == 0
		for object in [ka, va, aa]! { ios_runtime.constants.delete(object) }
		unchanged := owned_string('unchanged'); set(absent, unchanged, domain); objc_release(unchanged)
		pref_set_rejections(set, copy, absent, domain, guard)
		baseline := ios_runtime.live
		mut workers := []thread{}; mut keys := [8]u64{}
		for i in 0 .. 8 { text := 'worker-' + i.str(); keys[i] = owned_string(text); unsafe { text.free() }; workers << spawn pref_set_worker(set, copy, domain, keys[i], key) }
		workers.wait(); unsafe { workers.free() }; for worker_key in keys { objc_release(worker_key) }
		assert ios_runtime.live == baseline
		if iteration == 0 {
			os.write_file(documents, 'blocked document root') or { panic(err) }
			assert sync(current) == 0
			still_staged := copy(key, current); pref_set_assert(still_staged, expected); objc_release(still_staged)
			os.rm(documents) or { panic(err) }
		}
		assert sync(domain) == 1
		bytes := os.read_bytes(path) or { panic(err) }; disk := plist.parse(bytes) or { panic(err) }; unsafe { bytes.free() }
		assert disk.fields['profile'].kind == .dictionary && disk.fields['profile'].fields['boolean'].kind == .boolean && 'fallback' !in disk.fields; disk.free()
		set(key, 0, current); assert copy(key, domain) == 0
		objc_pool_drain_all(); pref_set_assert(owned, expected); objc_release(owned)
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, '_CFPreferencesSetAppValue') { assert false } }
		for object in [domain, key, absent, fallback]! { objc_release(object) }
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		if _ := cf_preferences_set_checked(0, 0, current) { assert false }
	}
	println('IOS-CF-PREFERENCES-SET: staged immutable snapshots and nil removal, seven plist types and Boolean persistence, shared standard defaults and registration fallback, mutable-input isolation, allocated/image arguments, guarded three-pointer void ABI, unchanged rejected updates, concurrent replacements/removals, synchronization failure retry, retained snapshots and two drained runtimes')
}
