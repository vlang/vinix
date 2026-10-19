// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct CFPreferencesValueFailure {}
fn (_ &CFPreferencesValueFailure) msg() string { return 'iOS: unsupported preference value query' }
fn (_ &CFPreferencesValueFailure) code() int { return 1 }
__global cf_preferences_value_failure_value = CFPreferencesValueFailure{}
fn cf_preferences_value_failure() IError { return unsafe { &cf_preferences_value_failure_value } }

// Caller holds the runtime lock. Image strings have no ObjHeader.
fn cf_preferences_string_valid(object u64) bool {
	if object !in ios_runtime.constants {
		header := ios_runtime.objects[object] or { return false }
		if header.destroyed { return false }
	}
	return objc_is_kind(object, ios_runtime.names['NSString'])
}

fn cf_preferences_value_checked(key u64, application u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_preferences_value_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !cf_preferences_string_valid(key) || !cf_preferences_string_valid(application) { return cf_preferences_value_failure() }
	defaults := defaults_start()
	name := string_text(application)
	if name != 'kCFPreferencesCurrentApplication' && name != string_text(obj_header(defaults).fields[3]) { return cf_preferences_value_failure() }
	// Persistent values take precedence over registered fallback defaults.
	for dictionary in [obj_header(defaults).fields[0], obj_header(defaults).fields[1]]! {
		stored := obj_header(dictionary)
		index := dictionary_index(stored, key)
		if index < 0 { continue }
		value := object_plist(stored.items[index], 0)!
		defer { value.free() }
		return plist_owned_object(value)
	}
	return 0
}

fn cf_preferences_copy_app_value(key u64, application u64) u64 {
	return cf_preferences_value_checked(key, application) or { panic(err) }
}
