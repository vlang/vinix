// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <CoreFoundation/CFArray.h>
	fn C.CFLocaleCopyPreferredLanguages() voidptr
	fn C.CFArrayGetCount(voidptr) i64
	fn C.CFArrayGetValueAtIndex(voidptr, i64) voidptr
}

struct CFPreferredLanguageFailure {}
fn (_ &CFPreferredLanguageFailure) msg() string { return 'iOS: unsupported preferred-language configuration' }
fn (_ &CFPreferredLanguageFailure) code() int { return 1 }
__global cf_preferred_language_failure_value = CFPreferredLanguageFailure{}
fn cf_preferred_language_failure() IError { return unsafe { &cf_preferred_language_failure_value } }

// A bounded language/script/region/POSIX profile, not the ICU alias database.
// Work entirely in stack storage and borrow input substrings without copies.
fn cf_preferred_tag_checked(source string, output &u8) !int {
	if source.len == 0 || source.len > 128 { return cf_preferred_language_failure() }
	mut end := 0
	for end < source.len && source[end] !in [u8(`.`), `@`]! { end++ }
	if end == 0 { return cf_preferred_language_failure() }
	mut starts := [4]int{}
	mut lengths := [4]int{}
	mut parts := 0
	mut start := 0
	for i in 0 .. end + 1 {
		if i < end && source[i] !in [u8(`_`), `-`]! { continue }
		if parts == 4 || i == start { return cf_preferred_language_failure() }
		starts[parts] = start; lengths[parts] = i - start
		parts++; start = i + 1
	}
	if lengths[0] !in [2, 3]! { return cf_preferred_language_failure() }
	mut script := -1
	mut region := -1
	mut variant := -1
	for part in 0 .. parts {
		mut alpha := true
		mut digit := true
		for i in starts[part] .. starts[part] + lengths[part] {
			byte := source[i]
			alpha = alpha && ((byte >= `A` && byte <= `Z`) || (byte >= `a` && byte <= `z`))
			digit = digit && byte >= `0` && byte <= `9`
		}
		if part == 0 {
			if !alpha { return cf_preferred_language_failure() }
		} else if lengths[part] == 4 && alpha && script < 0 && region < 0 && variant < 0 {
			script = part
		} else if region < 0 && variant < 0 && ((lengths[part] == 2 && alpha) || (lengths[part] == 3 && digit)) {
			region = part
		} else if lengths[part] == 5 && alpha && variant < 0 {
			for i in 0 .. 5 { if (source[starts[part] + i] & ~u8(32)) != 'POSIX'[i] { return cf_preferred_language_failure() } }
			variant = part
		} else { return cf_preferred_language_failure() }
	}
	mut length := 0
	for part in 0 .. parts {
		if part > 0 { unsafe { output[length] = `-` }; length++ }
		for i in 0 .. lengths[part] {
			byte := source[starts[part] + i]
			lower := part == 0 || (part == script && i > 0)
			unsafe { output[length] = if lower && byte >= `A` && byte <= `Z` { byte | 32 } else if !lower && byte >= `a` && byte <= `z` { byte & ~u8(32) } else { byte } }
			length++
		}
	}
	language := unsafe { tos(output, lengths[0]) }
	alias := match language { 'iw' { 'he' } 'in' { 'id' } 'ji' { 'yi' } else { '' } }
	if alias != '' { C.memcpy(output, alias.str, 2) }
	// These native canonical forms are measured, including the distinction
	// between an explicit Chinese script and an inferred script from CN/TW.
	if language == 'zh' && script < 0 && region == 1 && parts == 2 {
		if C.memcmp(unsafe { output + 3 }, c'CN', 2) == 0 { C.memcpy(output, c'zh-Hans', 7); return 7 }
		if C.memcmp(unsafe { output + 3 }, c'TW', 2) == 0 { C.memcpy(output, c'zh-Hant', 7); return 7 }
	}
	if language == 'en' && script == 1 && C.memcmp(unsafe { output + 3 }, c'Latn', 4) == 0 {
		C.memmove(unsafe { output + 2 }, unsafe { output + 7 }, usize(length - 7))
		length -= 5
	}
	return length
}

fn cf_preferred_environment_checked() !string {
	value := C.getenv(c'LANGUAGE')
	if value == unsafe { nil } { return '' }
	for length in 0 .. 4096 {
		if unsafe { *(&u8(value) + length) } == 0 { return unsafe { tos(&u8(value), length) } }
	}
	return cf_preferred_language_failure()
}

fn cf_preferred_append_checked(array u64, source string) ! {
	mut bytes := [128]u8{}
	length := cf_preferred_tag_checked(source, unsafe { &bytes[0] })!
	text := unsafe { tos(&bytes[0], length) }
	mut header := obj_header(array)
	for item in header.items { if string_text(item) == text { return } }
	if header.items.len == 32 { return cf_preferred_language_failure() }
	value := owned_string(text)
	array_append(mut header, value)
	objc_release(value)
}

fn cf_locale_copy_preferred_languages_checked() !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_preferred_language_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut complete := false
	defer { if !complete { objc_release(array) } }
	$if macos {
		pool := C.objc_autoreleasePoolPush()
		defer { C.objc_autoreleasePoolPop(pool) }
		native := C.CFLocaleCopyPreferredLanguages()
		if native == unsafe { nil } { return cf_preferred_language_failure() }
		defer { C.CFRelease(native) }
		count := C.CFArrayGetCount(native)
		if count < 0 || count > 32 { return cf_preferred_language_failure() }
		for index := i64(0); index < count; index++ {
			mut bytes := [1024]u8{}
			if !C.CFStringGetCString(C.CFArrayGetValueAtIndex(native, index), unsafe { &char(&bytes[0]) }, 1024, 0x08000100) { return cf_preferred_language_failure() }
			value := owned_string(ctext(u64(unsafe { &bytes[0] })))
			array_append(mut obj_header(array), value)
			objc_release(value)
		}
		complete = true
		return array
	}
	$if linux {
		list := cf_preferred_environment_checked()!
		mut start := 0
		for index in 0 .. list.len + 1 {
			if index < list.len && list[index] != `:` { continue }
			if index > start { cf_preferred_append_checked(array, unsafe { tos(list.str + start, index - start) })! }
			start = index + 1
		}
		if obj_header(array).items.len == 0 {
			identifier := ns_locale_current_identifier()
			defer { objc_release(identifier) }
			cf_preferred_append_checked(array, string_text(identifier))!
		}
		complete = true
		return array
	}
	return cf_preferred_language_failure()
}

// One owned immutable array; each string is borrowed from that array until
// retained independently. New queries have independent snapshot lifetimes.
fn cf_locale_copy_preferred_languages() u64 {
	return cf_locale_copy_preferred_languages_checked() or { panic(err) }
}
