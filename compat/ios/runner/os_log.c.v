// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.flockfile(voidptr)
fn C.funlockfile(voidptr)
fn C.strcmp(&char, &char) i32

// Private, runtime-owned handles. The exported default/disabled symbols name
// these objects directly, not pointer cells. ObjC retain/release recognizes
// them without claiming support for the native OS_os_log class's methods.
struct OsLogHandle {
mut:
	next &OsLogHandle = unsafe { nil }
	subsystem [256]u8
	category [256]u8
}

fn os_log_bytes(text &char, limit int) int {
	if text == unsafe { nil } { return -1 }
	for i in 0 .. limit {
		if unsafe { text[i] } == 0 { return i }
	}
	return -1
}

fn darwin_os_log_create(subsystem &char, category &char) u64 {
	a := os_log_bytes(subsystem, 256); b := os_log_bytes(category, 256)
	if a < 0 || b < 0 { panic('iOS: OS log labels exceed 255 bytes or are null') }
	if system_data == unsafe { nil } { panic('iOS: OS logging requires system initialization') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut current := system_data.logs
	for current != unsafe { nil } {
		if C.strcmp(unsafe { &char(&current.subsystem[0]) }, subsystem) == 0 && C.strcmp(unsafe { &char(&current.category[0]) }, category) == 0 { return u64(current) }
		current = current.next
	}
	if system_data.log_count == 256 { panic('iOS: OS log handle limit exceeded') }
	mut handle := unsafe { &OsLogHandle(C.calloc(1, sizeof(OsLogHandle))) }
	if handle == unsafe { nil } { panic('iOS: cannot allocate OS log handle') }
	C.memcpy(unsafe { &handle.subsystem[0] }, subsystem, usize(a))
	C.memcpy(unsafe { &handle.category[0] }, category, usize(b))
	handle.next = system_data.logs
	system_data.logs = handle
	system_data.log_count++
	return u64(handle)
}

fn os_log_is_handle(owner u64) bool {
	if owner == 0 || system_data == unsafe { nil } { return false }
	if owner == u64(unsafe { &system_data.log_default[0] }) || owner == u64(unsafe { &system_data.log_disabled[0] }) { return true }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut current := system_data.logs
	for current != unsafe { nil } {
		if u64(current) == owner { return true }
		current = current.next
	}
	return false
}

fn darwin_os_log_type_enabled(owner u64, kind u8) bool {
	if !os_log_is_handle(owner) { panic('iOS: unknown OS log handle') }
	// Local stderr policy: default/info/error/fault enabled, debug disabled.
	return owner != u64(unsafe { &system_data.log_disabled[0] }) && kind in [u8(0), 1, 0x10, 0x11]!
}

fn os_log_stop() {
	mut current := system_data.logs
	system_data.logs = unsafe { nil }
	system_data.log_count = 0
	for current != unsafe { nil } {
		next := current.next
		C.free(current)
		current = next
	}
}

fn os_log_append(output &[4096]u8, used &int, text &u8, length int) bool {
	if length < 0 || unsafe { *used } > 4095 - length { return false }
	unsafe { C.memcpy(&output[*used], text, usize(length)); *used += length }
	return true
}

fn os_log_public_object(owner u64, output &[4096]u8, used &int) bool {
	if owner == 0 { return os_log_append(output, used, c'(null)', 6) }
	// A user description may itself log. Call it outside the handle registry
	// and sink locks, and drain its autoreleased temporaries after copying.
	pool := objc_pool_push()
	defer { objc_pool_pop(pool) }
	imp := native_method(objc_class(owner), 'description')
	mut description := u64(0)
	if imp != 0 { description = unsafe { ObjInit(voidptr(imp))(owner, c'description') } }
	else { description = objc_autorelease(cf_copy_description(owner)) }
	if description == 0 || !objc_is_kind(description, ios_runtime.names['NSString']) { return false }
	text := string_text(description)
	length := if text.len > 1024 { 1024 } else { text.len }
	if !os_log_append(output, used, text.str, length) { return false }
	return text.len <= 1024 || os_log_append(output, used, c'...', 3)
}

// Clang's OS logging buffer is a two-byte header followed by descriptor,
// payload-size and little-endian payload records. It is not a va_list.
// Validate the entire envelope before looking through any public pointers.
fn os_log_render(format &char, records &u8, size u32, output &[4096]u8) int {
	if os_log_render_pass(format, records, size, output, true) < 0 { return -1 }
	return os_log_render_pass(format, records, size, output, false)
}

fn os_log_render_pass(format &char, records &u8, size u32, output &[4096]u8, validate bool) int {
	length := os_log_bytes(format, 1024)
	if length < 0 || records == unsafe { nil } || size < 2 || size > 4096 { return -1 }
	count := int(unsafe { records[1] })
	if count > 64 || unsafe { records[0] } & ~u8(3) != 0 { return -1 }
	mut end := 2
	mut flags := u8(0)
	for _ in 0 .. count {
		if end > int(size) - 2 { return -1 }
		descriptor := unsafe { records[end] }; width := int(unsafe { records[end + 1] })
		tag := descriptor >> 4
		if descriptor & 15 > 2 || tag !in [u8(0), 2, 4]! || (tag == 0 && width !in [1, 2, 4, 8]!) || (tag != 0 && width != 8) || width > int(size) - end - 2 { return -1 }
		if descriptor & 15 == 1 { flags |= 1 }
		if tag != 0 { flags |= 2 }
		end += width + 2
	}
	if end != int(size) || flags != unsafe { records[0] } { return -1 }
	mut used := 0; mut position := 0; mut cursor := 2; mut consumed := 0
	for position < length {
		if u8(unsafe { format[position] }) != `%` {
			if !os_log_append(output, &used, unsafe { &u8(&format[position]) }, 1) { return -1 }
			position++; continue
		}
		position++
		if position < length && u8(unsafe { format[position] }) == `%` {
			if !os_log_append(output, &used, c'%', 1) { return -1 }; position++; continue
		}
		mut privacy := u8(0)
		if position < length && u8(unsafe { format[position] }) == `{` {
			if position + 8 <= length && C.memcmp(unsafe { &format[position] }, c'{public}', 8) == 0 { privacy = 2; position += 8 }
			else if position + 9 <= length && C.memcmp(unsafe { &format[position] }, c'{private}', 9) == 0 { privacy = 1; position += 9 }
			else { return -1 }
		}
		mut modifier := u8(0)
		if position < length && u8(unsafe { format[position] }) in [u8(`l`), `z`, `t`, `j`]! {
			modifier = u8(unsafe { format[position] }); position++
			if position < length && modifier == `l` && u8(unsafe { format[position] }) == modifier { position++ }
		}
		if position >= length || consumed == count { return -1 }
		conversion := u8(unsafe { format[position] }); position++
		descriptor := unsafe { records[cursor] }; width := int(unsafe { records[cursor + 1] }); tag := descriptor >> 4
		if descriptor & 15 != privacy { return -1 }
		if (conversion == `s` && (tag != 2 || modifier != 0)) || (conversion == `@` && (tag != 4 || modifier != 0)) || (conversion !in [`s`, `@`]! && tag != 0) { return -1 }
		if conversion !in [`s`, `@`, `d`, `i`, `u`, `x`, `X`, `o`, `p`, `c`, `f`, `e`, `g`]! { return -1 }
		if conversion in [`d`, `i`, `u`, `x`, `X`, `o`]! && width != (if modifier == 0 { 4 } else { 8 }) { return -1 }
		if conversion == `c` && (modifier != 0 || width != 4) { return -1 }
		if conversion == `p` && (modifier != 0 || width != 8) { return -1 }
		if conversion in [`f`, `e`, `g`]! && (width != 8 || modifier !in [u8(0), `l`]!) { return -1 }
		mut value := u64(0)
		for i in 0 .. width { value |= u64(unsafe { records[cursor + 2 + i] }) << (u32(i) * 8) }
		cursor += width + 2; consumed++
		if validate { continue }
		if privacy == 1 || (privacy == 0 && tag != 0) {
			if !os_log_append(output, &used, c'<private>', 9) { return -1 }; continue
		}
		if conversion == `s` {
			if value == 0 { if !os_log_append(output, &used, c'(null)', 6) { return -1 }; continue }
			mut n := 0
			for n < 1024 && unsafe { *(&u8(value + u64(n))) } != 0 { n++ }
			if !os_log_append(output, &used, unsafe { &u8(value) }, n) { return -1 }
			if n == 1024 && !os_log_append(output, &used, c'...', 3) { return -1 }
		} else if conversion == `@` {
			if !os_log_public_object(value, output, &used) { return -1 }
		} else {
			mut scratch := [128]u8{}
			mut n := i32(0)
			if conversion in [`d`, `i`]! {
				signed := i64(value << u32(64 - width * 8)) >> u32(64 - width * 8)
				n = unsafe { i32(C.snprintf(&char(&scratch[0]), 128, c'%lld', signed)) }
			} else if conversion in [`u`, `x`, `X`, `o`]! {
				spec := match conversion { `u` { c'%llu' } `x` { c'%llx' } `X` { c'%llX' } else { c'%llo' } }
				n = unsafe { i32(C.snprintf(&char(&scratch[0]), 128, spec, value)) }
			} else if conversion == `p` {
				if width != 8 || modifier != 0 { return -1 }
				n = unsafe { i32(C.snprintf(&char(&scratch[0]), 128, c'%p', voidptr(value))) }
			} else if conversion == `c` {
				if modifier != 0 { return -1 }; scratch[0] = u8(value); n = 1
			} else {
				if width != 8 || modifier !in [u8(0), `l`]! { return -1 }
				mut real := f64(0); unsafe { C.memcpy(&real, &value, 8) }
				spec := match conversion { `f` { c'%f' } `e` { c'%e' } else { c'%g' } }
				n = unsafe { i32(C.snprintf(&char(&scratch[0]), 128, spec, real)) }
			}
			if n < 0 || n >= 128 || !os_log_append(output, &used, unsafe { &scratch[0] }, int(n)) { return -1 }
		}
	}
	return if consumed == count { used } else { -1 }
}

fn darwin_os_log_impl(_dso u64, owner u64, kind u8, format &char, records &u8, size u32) {
	if !darwin_os_log_type_enabled(owner, kind) { return }
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut output := [4096]u8{}
	length := os_log_render(format, records, size, unsafe { &output })
	if length < 0 { panic('iOS: unsupported or malformed OS log record') }
	output[length] = `\n`
	sink := C.ios_host_stdio(2)
	C.flockfile(sink)
	defer { C.funlockfile(sink) }
	if C.fwrite(unsafe { &output[0] }, 1, usize(length + 1), sink) != usize(length + 1) { panic('iOS: OS log output failed') }
}

fn swift_os_log_error_type() u8 { return 0x10 }

fn os_log_symbol(symbol string) ?u64 {
	return match symbol {
		'__os_log_default' { u64(unsafe { &system_data.log_default[0] }) }
		'__os_log_disabled' { u64(unsafe { &system_data.log_disabled[0] }) }
		'_os_log_create' { u64(unsafe { voidptr(darwin_os_log_create) }) }
		'_os_log_type_enabled' { u64(unsafe { voidptr(darwin_os_log_type_enabled) }) }
		'__os_log_impl', '__os_log_error_impl', '__os_log_debug_impl', '__os_log_fault_impl' { u64(unsafe { voidptr(darwin_os_log_impl) }) }
		else { return none }
	}
}
