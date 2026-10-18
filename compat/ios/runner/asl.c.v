// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct AslClient {
mut:
	next     &AslClient = unsafe { nil }
	filter   u16        = 63
	options  u32
	ident    &char = unsafe { nil }
	facility &char = unsafe { nil }
}

struct AslPolicy {
mut:
	valid   bool
	filter  u16
	options u32
	ident   [256]u8
}

// Registry access holds the existing recursive runtime lock. Callers never
// dereference a client supplied by the application before finding it here.
fn asl_find(owner u64) &AslClient {
	mut current := system_data.asl_clients
	for current != unsafe { nil } {
		if u64(current) == owner { return current }
		current = current.next
	}
	return unsafe { nil }
}

fn darwin_asl_open(ident &char, facility &char, options u32) u64 {
	if system_data == unsafe { nil } { panic('iOS: ASL requires system initialization') }
	previous := unsafe { *C.ios_errno_address() }
	name := if ident == unsafe { nil } { c'Vinix' } else { ident }
	category := if facility == unsafe { nil } { c'user' } else { facility }
	a := darwin_strlen(name) + 1
	b := darwin_strlen(category) + 1
	if a > ~usize(0) - sizeof(AslClient) || b > ~usize(0) - sizeof(AslClient) - a {
		darwin_set_errno(12)
		return 0
	}
	mut client := unsafe { &AslClient(C.calloc(1, sizeof(AslClient) + a + b)) }
	if client == unsafe { nil } {
		darwin_set_errno(12)
		return 0
	}
	client.filter = 63
	client.options = options
	client.ident = unsafe { &char(u64(client) + sizeof(AslClient)) }
	client.facility = unsafe { &char(u64(client.ident) + u64(a)) }
	C.memcpy(client.ident, name, a)
	C.memcpy(client.facility, category, b)
	C.ios_objc_initialize_lock()
	client.next = system_data.asl_clients
	system_data.asl_clients = client
	C.ios_objc_initialize_unlock()
	darwin_set_errno(previous)
	return u64(client)
}

fn darwin_asl_close(owner u64) {
	if owner == 0 || system_data == unsafe { nil } { return }
	previous := unsafe { *C.ios_errno_address() }
	C.ios_objc_initialize_lock()
	mut link := unsafe { &system_data.asl_clients }
	for unsafe { *link } != unsafe { nil } && u64(unsafe { *link }) != owner {
		link = unsafe { &(*link).next }
	}
	client := unsafe { *link }
	if client != unsafe { nil } { unsafe { *link = client.next } }
	C.ios_objc_initialize_unlock()
	// Logging takes a value snapshot under the same lock; no reader retains
	// this allocation after releasing it. Descriptor ownership stays external.
	C.free(client)
	darwin_set_errno(previous)
}

fn darwin_asl_set_filter(owner u64, filter i32) i32 {
	if system_data == unsafe { nil } { return -1 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if owner == 0 {
		previous := system_data.asl_filter
		system_data.asl_filter = u16(filter)
		return i32(previous)
	}
	mut client := asl_find(owner)
	if client == unsafe { nil } { return -1 }
	previous := client.filter
	client.filter = u16(filter)
	return i32(previous)
}

fn darwin_asl_file(owner u64, _descriptor i32) i32 {
	if system_data == unsafe { nil } { return -1 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// The SDK marks legacy file attachments unsupported. Native libSystem
	// accepts any descriptor for nil/client objects, without touching it.
	return if owner == 0 || asl_find(owner) != unsafe { nil } { i32(0) } else { i32(-1) }
}

fn asl_policy(owner u64) AslPolicy {
	mut policy := AslPolicy{}
	if system_data == unsafe { nil } { return policy }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut ident := c'Vinix'
	if owner == 0 {
		policy.filter = system_data.asl_filter
	} else {
		client := asl_find(owner)
		if client == unsafe { nil } { return policy }
		policy.filter = client.filter
		policy.options = client.options
		ident = client.ident
	}
	for i in 0 .. 255 {
		value := unsafe { ident[i] }
		if value == 0 { break }
		policy.ident[i] = u8(value)
	}
	policy.valid = true
	return policy
}

fn asl_format_valid(format &char) bool {
	length := os_log_bytes(format, 65536)
	if length < 0 { return false }
	mut i := 0
	for i < length {
		if u8(unsafe { format[i] }) != `%` {
			i++
			continue
		}
		i++
		if i < length && u8(unsafe { format[i] }) == `%` {
			i++
			continue
		}
		for i < length && u8(unsafe { format[i] }) in [u8(`#`), `0`, `-`, ` `, `+`, `'`]! { i++ }
		if i < length && u8(unsafe { format[i] }) == `*` {
			i++
		} else {
			for i < length && u8(unsafe { format[i] }) >= `0` && u8(unsafe { format[i] }) <= `9` {
				i++
			}
		}
		if i < length && u8(unsafe { format[i] }) == `.` {
			i++
			if i < length && u8(unsafe { format[i] }) == `*` {
				i++
			} else {
				for i < length && u8(unsafe { format[i] }) >= `0` && u8(unsafe { format[i] }) <= `9` {
					i++
				}
			}
		}
		mut modifier := u8(0)
		mut doubled := false
		if i < length && u8(unsafe { format[i] }) in [u8(`h`), `l`, `j`, `z`, `t`]! {
			modifier = u8(unsafe { format[i] })
			i++
			if i < length && modifier in [u8(`h`), `l`]! && u8(unsafe { format[i] }) == modifier {
				doubled = true
				i++
			}
		}
		if i >= length { return false }
		conversion := u8(unsafe { format[i] })
		i++
		if conversion !in [u8(`d`), `i`, `o`, `u`, `x`, `X`, `f`, `F`, `e`, `E`, `g`, `G`, `a`,
			`A`, `c`, `s`, `p`]! {
			return false
		}
		if conversion in [u8(`c`), `s`, `p`]! && modifier != 0 { return false }
		if doubled && conversion in [u8(`f`), `F`, `e`, `E`, `g`, `G`, `a`, `A`]! { return false }
		if conversion in [u8(`f`), `F`, `e`, `E`, `g`, `G`, `a`, `A`]! && modifier !in [
			u8(0),
			`l`,
		]! {
			return false
		}
	}
	return true
}

// Darwin's anonymous arguments start at the incoming SP even when integer
// argument registers remain. A naked V entry tail-calls the fixed ABI body.
$if arm64 {
	$if macos {
		@[_naked]
		fn darwin_asl_log() {
			asm volatile arm64 { mov x4, sp
				b '_ios_asl_log_stack' }
		}
	} $else {
		@[_naked]
		fn darwin_asl_log() {
			asm volatile arm64 { mov x4, sp
				b 'ios_asl_log_stack' }
		}
	}
} $else {
	fn darwin_asl_log() { panic('iOS: ASL variadic calls require ARM64') }
}

@[export: 'ios_asl_log_stack']
fn darwin_asl_vlog(owner u64, message u64, level i32, format &char, stack voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	policy := asl_policy(owner)
	if !policy.valid || message != 0 { return -1 }
	kind := if level < 0 || level > 7 { u32(7) } else { u32(level) }
	// Vinix routes the filtered server stream to local stderr. Explicit
	// ASL_OPT_STDERR bypasses that filter, as measured on native libSystem.
	if policy.options & 1 == 0 && u32(policy.filter) & (u32(1) << kind) == 0 { return 0 }
	if !asl_format_valid(format) { return -1 }
	mut small := [4096]u8{}
	mut output := unsafe { &char(&small[0]) }
	mut allocated := false
	defer { if allocated { C.free(output) } }
	length := C.ios_vsnprintf(output, 4096, format, stack)
	if length < 0 || length > 1024 * 1024 { return -1 }
	if length >= 4096 {
		output = unsafe { &char(C.malloc(usize(length) + 1)) }
		if output == unsafe { nil } { return -1 }
		allocated = true
		darwin_set_errno(previous)
		if C.ios_vsnprintf(output, usize(length) + 1, format, stack) != length { return -1 }
	}
	sink := C.ios_host_stdio(2)
	C.flockfile(sink)
	defer { C.funlockfile(sink) }
	if C.fputs(unsafe { &char(&policy.ident[0]) }, sink) < 0 || C.fputs(c': ', sink) < 0
		|| C.fwrite(output, 1, usize(length), sink) != usize(length)
		|| C.fputc(10, sink) < 0 {
		return -1
	}
	return 0
}

fn asl_stop() {
	C.ios_objc_initialize_lock()
	mut current := system_data.asl_clients
	system_data.asl_clients = unsafe { nil }
	C.ios_objc_initialize_unlock()
	for current != unsafe { nil } {
		next := current.next
		C.free(current)
		current = next
	}
}

fn asl_symbol(symbol string) ?u64 {
	return match symbol {
		'_asl_open' { u64(unsafe { voidptr(darwin_asl_open) }) }
		'_asl_close' { u64(unsafe { voidptr(darwin_asl_close) }) }
		'_asl_set_filter' { u64(unsafe { voidptr(darwin_asl_set_filter) }) }
		'_asl_add_log_file', '_asl_remove_log_file' { u64(unsafe { voidptr(darwin_asl_file) }) }
		'_asl_log' { u64(unsafe { voidptr(darwin_asl_log) }) }
		'_asl_vlog' { u64(unsafe { voidptr(darwin_asl_vlog) }) }
		else { return none }
	}
}
