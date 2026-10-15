// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct NSLogFailure {}
fn (_ &NSLogFailure) msg() string { return 'iOS: unsupported or excessive NSLog format/arguments' }
fn (_ &NSLogFailure) code() int { return 1 }
__global ns_log_failure_value = NSLogFailure{}
fn ns_log_failure() IError { return unsafe { &ns_log_failure_value } }

// Copy the borrowed NSString while its runtime registry and bytes are locked.
// Foundation's stderr sink uses the prefix before the first embedded NUL.
fn ns_logv_snapshot(format u64) !string {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if format == 0 || (format !in ios_runtime.objects && format !in ios_runtime.constants)
		|| !objc_is_kind(format, ios_runtime.names['NSString']) { return ns_log_failure() }
	text := string_text(format)
	if text.len > 65536 { return ns_log_failure() }
	mut length := 0
	for length < text.len && text[length] != 0 { length++ }
	bytes := C.malloc(usize(length + 1))
	if bytes == unsafe { nil } { return ns_log_failure() }
	C.memcpy(bytes, text.str, usize(length))
	unsafe { *(&u8(u64(bytes) + u64(length))) = 0 }
	return unsafe { tos(&u8(bytes), length) }
}

// Resolve a description once, outside the sink lock. Its +0 result remains
// in this call's autorelease pool until the bytes have been copied. A guest
// description may reenter logging or resolve imports on another thread.
fn ns_logv_object(owner u64, output u64, capacity int) !int {
	if owner == 0 {
		if capacity < 6 { return ns_log_failure() }
		C.memcpy(unsafe { voidptr(output) }, c'(null)', 6)
		return 6
	}
	C.ios_objc_initialize_lock()
	if owner !in ios_runtime.objects && owner !in ios_runtime.constants {
		C.ios_objc_initialize_unlock()
		return ns_log_failure()
	}
	objc_retain(owner)
	is_string := objc_is_kind(owner, ios_runtime.names['NSString'])
	C.ios_objc_initialize_unlock()
	defer { objc_release(owner) }
	mut description := owner
	if !is_string {
		imp := native_method(objc_class(owner), 'description')
		description = if imp != 0 { unsafe { ObjInit(voidptr(imp))(owner, c'description') } }
			else { objc_autorelease(cf_copy_description(owner)) }
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if description == 0 || (description !in ios_runtime.objects && description !in ios_runtime.constants)
		|| !objc_is_kind(description, ios_runtime.names['NSString']) { return ns_log_failure() }
	text := string_text(description)
	if text.len > capacity { return ns_log_failure() }
	C.memcpy(unsafe { voidptr(output) }, text.str, usize(text.len))
	return text.len
}

// Darwin ARM64 va_list is a pointer to eight-byte anonymous argument slots.
// Validate all syntax before reading any slot or invoking a description.
// The caller owns the readable argument and %s spans, as for native NSLogv.
fn ns_logv_pass(text string, stack u64, output u64, validate bool) !int {
	mut index := 0
	mut word := 0
	mut used := 0
	specifier := u64(C.__builtin_alloca(66))
	arguments := u64(C.__builtin_alloca(24))
	for index < text.len {
		if text[index] != `%` || (index + 1 < text.len && text[index + 1] == `%`) {
			if !validate {
				if used == 1024 * 1024 { return ns_log_failure() }
				unsafe { *(&u8(output + u64(used))) = text[index] }
				used++
			}
			index += if text[index] == `%` { 2 } else { 1 }
			continue
		}
		start := index
		index++
		for index < text.len && text[index] in [`#`, `0`, `-`, ` `, `+`]! { index++ }
		mut stars := 0
		mut width_star := false
		mut precision := -1
		mut precision_star := false
		for field in 0 .. 2 {
			if field == 1 {
				if index >= text.len || text[index] != `.` { break }
				index++
				precision = 0
			}
			if index < text.len && text[index] == `*` {
				stars++
				if field == 0 { width_star = true }
				precision_star = field == 1
				index++
			} else {
				mut magnitude := 0
				for index < text.len && text[index] >= `0` && text[index] <= `9` {
					magnitude = magnitude * 10 + int(text[index] - `0`)
					if magnitude > 1024 * 1024 { return ns_log_failure() }
					index++
				}
				if field == 1 { precision = magnitude }
			}
		}
		modifier := index
		if index < text.len && text[index] in [`h`, `l`, `z`, `t`, `j`]! {
			index++
			if index < text.len && text[index] == text[modifier] && text[modifier] in [`h`, `l`]! { index++ }
		}
		if index >= text.len || index - start > 64 { return ns_log_failure() }
		conversion := text[index]
		index++
		if conversion !in [`@`, `d`, `i`, `u`, `x`, `X`, `o`, `f`, `F`, `e`, `E`, `g`, `G`, `a`, `A`, `c`, `s`, `p`]!
			|| (conversion == `@` && index - start != 2)
			|| (conversion in [`c`, `s`, `p`]! && index - 1 != modifier)
			|| (conversion in [`f`, `F`, `e`, `E`, `g`, `G`, `a`, `A`]! && index - 1 != modifier
				&& !(index - 1 == modifier + 1 && text[modifier] == `l`)) { return ns_log_failure() }
		if word + stars + 1 > 512 { return ns_log_failure() }
		if validate { word += stars + 1; continue }
		if stack == 0 || stack & 7 != 0 || stack > ~u64(0) - 4096 { return ns_log_failure() }
		C.memcpy(unsafe { voidptr(arguments) }, unsafe { voidptr(stack + u64(word * 8)) }, usize((stars + 1) * 8))
		for i in 0 .. stars {
			value := i32(read64(arguments + u64(i * 8)))
			if value < -1024 * 1024 || value > 1024 * 1024 { return ns_log_failure() }
			if precision_star && i == stars - 1 { precision = int(value) }
		}
		value := read64(arguments + u64(stars * 8))
		if conversion == `@` {
			used += ns_logv_object(value, output + u64(used), 1024 * 1024 - used)!
		} else {
			if conversion == `s` {
				// Measured CF formatting ignores a negative dynamic string
				// width; numeric conversions retain printf's left padding rule.
				if width_star && i32(read64(arguments)) < 0 { unsafe { *(&u64(arguments)) = 0 } }
				if value == 0 {
					unsafe { *(&u64(arguments + u64(stars * 8))) = u64(c'(null)') }
				} else {
					limit := if precision >= 0 { precision } else { 1024 * 1024 }
					mut length := 0
					for length < limit && unsafe { *(&u8(value + u64(length))) } != 0 { length++ }
					if precision < 0 && length == limit { return ns_log_failure() }
				}
			}
			C.memcpy(unsafe { voidptr(specifier) }, unsafe { text.str + start }, usize(index - start))
			unsafe { *(&u8(specifier + u64(index - start))) = 0 }
			count := C.ios_vsnprintf(unsafe { &char(output + u64(used)) }, usize(1024 * 1024 - used + 1), unsafe { &char(specifier) }, unsafe { voidptr(arguments) })
			if count < 0 || count > 1024 * 1024 - used { return ns_log_failure() }
			// Native NSString formatting omits a zero %c character.
			if conversion == `c` && u8(value) == 0 {
				for i in 0 .. count { if unsafe { *(&u8(output + u64(used + i))) } == 0 { C.memmove(unsafe { voidptr(output + u64(used + i)) }, unsafe { voidptr(output + u64(used + i + 1)) }, usize(count - i - 1)); break } }
				used += count - 1
			} else { used += count }
		}
		word += stars + 1
	}
	return if validate { word } else { used }
}

fn ns_logv_checked(format u64, stack u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return ns_log_failure() }
	text := ns_logv_snapshot(format)!
	defer { C.free(text.str) }
	ns_logv_pass(text, 0, 0, true)!
	pool := objc_pool_push()
	defer { objc_pool_pop(pool) }
	message := u64(C.malloc(1024 * 1024 + 1))
	if message == 0 { return ns_log_failure() }
	defer { C.free(unsafe { voidptr(message) }) }
	length := ns_logv_pass(text, stack, message, false)!
	mut end := 0
	for end < length && unsafe { *(&u8(message + u64(end))) } != 0 { end++ }
	if end == 0 || unsafe { *(&u8(message + u64(end - 1))) } != `\n` {
		unsafe { *(&u8(message + u64(end))) = `\n` }
		end++
	}
	sink := C.ios_host_stdio(2)
	C.flockfile(sink)
	defer { C.funlockfile(sink) }
	if C.fwrite(unsafe { voidptr(message) }, 1, usize(end), sink) != usize(end) { return ns_log_failure() }
}

fn ns_logv(format u64, stack u64) { ns_logv_checked(format, stack) or { panic(err) } }
