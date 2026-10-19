// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

struct CFPreferencesSetFailure {}
fn (_ &CFPreferencesSetFailure) msg() string { return 'iOS: unsupported preference value update' }
fn (_ &CFPreferencesSetFailure) code() int { return 1 }
__global cf_preferences_set_failure_value = CFPreferencesSetFailure{}
fn cf_preferences_set_failure() IError { return unsafe { &cf_preferences_set_failure_value } }

// Validate the complete supported tree before copying or changing the store.
// Raw CF collections can contain arbitrary pointers rather than plist objects.
fn cf_preferences_set_object_valid(object u64, depth int) bool {
	if depth > 64 || (object !in ios_runtime.objects && object !in ios_runtime.constants) { return false }
	if cf_preferences_string_valid(object) { return true }
	header := ios_runtime.objects[object] or { return false }
	if header.destroyed { return false }
	if objc_is_kind(object, ios_runtime.names['NSNumber']) { return !header.is_real || math.is_finite(header.real_number) }
	if objc_is_kind(object, ios_runtime.names['NSData']) { return data_length(object) <= 16777216 }
	if header.cf_raw_keys || header.cf_raw_values { return false }
	if objc_is_kind(object, ios_runtime.names['NSArray']) {
		for item in header.items { if !cf_preferences_set_object_valid(item, depth + 1) { return false } }
		return true
	}
	if objc_is_kind(object, ios_runtime.names['NSDictionary']) {
		if header.keys.len != header.items.len { return false }
		for i, key in header.keys {
			if !cf_preferences_string_valid(key) || !cf_preferences_set_object_valid(header.items[i], depth + 1) { return false }
		}
		return true
	}
	return false
}

fn cf_preferences_set_checked(key u64, value u64, application u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_preferences_set_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !cf_preferences_string_valid(key) || !cf_preferences_string_valid(application)
		|| (value != 0 && !cf_preferences_set_object_valid(value, 0)) { return cf_preferences_set_failure() }
	defaults := defaults_start()
	name := string_text(application)
	if name != 'kCFPreferencesCurrentApplication' && name != string_text(obj_header(defaults).fields[3]) { return cf_preferences_set_failure() }
	dictionary := obj_header(defaults).fields[0]
	if value == 0 { dictionary_put(dictionary, key, 0); return }
	plist_value := object_plist(value, 0)!
	defer { plist_value.free() }
	snapshot := plist_owned_object(plist_value)
	defer { objc_release(snapshot) }
	copied_key := owned_string(string_text(key))
	defer { objc_release(copied_key) }
	// Stage only the application source. Synchronization performs the write;
	// registered fallbacks stay separate and become visible again on removal.
	dictionary_put(dictionary, copied_key, snapshot)
}

fn cf_preferences_set_app_value(key u64, value u64, application u64) {
	cf_preferences_set_checked(key, value, application) or { panic(err) }
}
