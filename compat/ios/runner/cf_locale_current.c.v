// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFLocale.h>
	#include <CoreFoundation/CFString.h>
	@[c_extern]
	fn C.objc_autoreleasePoolPush() voidptr
	@[c_extern]
	fn C.objc_autoreleasePoolPop(voidptr)
	fn C.CFLocaleCopyCurrent() voidptr
	fn C.CFLocaleGetIdentifier(voidptr) voidptr
	fn C.CFStringGetCString(voidptr, &char, i64, u32) bool
	fn C.CFRelease(voidptr)
}

fn ns_locale_current_identifier() u64 {
	$if macos {
		pool := C.objc_autoreleasePoolPush()
		defer { C.objc_autoreleasePoolPop(pool) }
		locale := C.CFLocaleCopyCurrent()
		if locale == unsafe { nil } { panic('iOS: native current locale is unavailable') }
		defer { C.CFRelease(locale) }
		mut bytes := [1024]u8{}
		if !C.CFStringGetCString(C.CFLocaleGetIdentifier(locale), unsafe { &char(&bytes[0]) }, 1024, 0x08000100) {
			panic('iOS: current locale identifier exceeds supported UTF-8 profile')
		}
		return owned_string(ctext(u64(unsafe { &bytes[0] })))
	}
	// Preserve Vinix's existing NSLocale environment precedence and default.
	// Read borrowed bytes only until the identifier terminator, then copy them
	// into the runtime's NSString. Configuration precedes worker startup.
	for name in [c'LC_ALL', c'LC_MESSAGES', c'LANG']! {
		value := C.getenv(name)
		if value == unsafe { nil } || unsafe { *value } == 0 { continue }
		for length in 0 .. 1024 {
			byte := unsafe { *(&u8(value) + length) }
			if byte !in [u8(0), `.`, `@`]! { continue }
			text := unsafe { tos(&u8(value), length) }
			return owned_string(if text in ['', 'C', 'POSIX']! { 'en_US' } else { text })
		}
		panic('iOS: current locale identifier exceeds supported UTF-8 profile')
	}
	return owned_string('en_US')
}

fn ns_locale_current() u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		panic('iOS: current locale outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.locale == 0 {
		identifier := ns_locale_current_identifier()
		locale := objc_allocate(ios_runtime.names['NSLocale'])
		store_field(locale, 0, identifier)
		objc_release(identifier)
		ios_runtime.locale = locale
	}
	return ios_runtime.locale
}

// A no-argument C entry returning one owned, toll-free bridged reference.
// The runtime keeps its separate cached reference until objc_stop().
fn cf_locale_copy_current() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return objc_retain(ns_locale_current())
}
