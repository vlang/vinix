// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The runner has one application source, shared with standardUserDefaults.
// CF Boolean is an unsigned byte, independent of Objective-C BOOL.
fn cf_preferences_app_synchronize(application u64) u8 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Image CFString constants have validated storage but no ObjHeader.
	if application !in ios_runtime.constants {
		header := ios_runtime.objects[application] or { return 0 }
		if header.destroyed { return 0 }
	}
	if !objc_is_kind(application, ios_runtime.names['NSString']) { return 0 }
	defaults := defaults_start()
	name := string_text(application)
	if name != 'kCFPreferencesCurrentApplication' && name != string_text(obj_header(defaults).fields[3]) { return 0 }
	return u8(defaults_save(defaults))
}
