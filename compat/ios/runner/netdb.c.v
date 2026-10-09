// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <netdb.h>

// Let the native C compiler lay this out. musl places ai_addr before
// ai_canonname; Darwin puts those pointers in the opposite order.
struct C.addrinfo {
mut:
	ai_flags i32
	ai_family i32
	ai_socktype i32
	ai_protocol i32
	ai_addrlen u32
	ai_canonname &char
	ai_addr voidptr
	ai_next &C.addrinfo
}

struct DarwinAddrinfo {
mut:
	flags i32
	family i32
	socktype i32
	protocol i32
	addrlen u32
	canonname &char
	address voidptr
	next &DarwinAddrinfo
}

fn C.getaddrinfo(&char, &char, &C.addrinfo, &&C.addrinfo) i32
fn C.freeaddrinfo(&C.addrinfo)
fn C.getnameinfo(voidptr, u32, &char, u32, &char, u32, i32) i32

fn netdb_error(result i32) i32 {
	if result == 0 { return 0 }
	$if linux {
		// musl uses EAI_NODATA for a numeric address of the wrong family;
		// the installed Darwin resolver reports EAI_NONAME for that case.
		if result == C.EAI_NODATA { return 8 }
	}
	if result == C.EAI_SYSTEM {
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
		return 11
	}
	return match result {
		C.EAI_AGAIN { 2 }
		C.EAI_BADFLAGS { 3 }
		C.EAI_FAIL { 4 }
		C.EAI_FAMILY { 5 }
		C.EAI_MEMORY { 6 }
		C.EAI_NODATA { 7 }
		C.EAI_NONAME, C.EAI_SERVICE { 8 }
		C.EAI_SOCKTYPE { 10 }
		C.EAI_OVERFLOW { 14 }
		else { 4 }
	}
}

// Numeric services must fit an unsigned 16-bit port. In particular, musl's
// service error and Darwin's EAI_NONAME have different values.
fn netdb_service_valid(service &char, flags i32) bool {
	if service == unsafe { nil } { return true }
	mut index := usize(0)
	unsafe {
		for u8(service[index]) == 32 || (u8(service[index]) >= 9 && u8(service[index]) <= 13) { index++ }
		negative := service[index] == 45
		if service[index] == 43 || negative { index++ }
		mut value := u32(0)
		mut digits := false
		for service[index] >= 48 && service[index] <= 57 {
			digits = true
			if value <= 65535 { value = value * 10 + u32(u8(service[index]) - 48) }
			index++
		}
		if service[index] == 0 && (digits || index == 0) {
			return value <= 65535 && (!negative || value == 0)
		}
	}
	return flags & 0x1000 == 0
}

fn darwin_freeaddrinfo(list &DarwinAddrinfo) {
	mut current := unsafe { list }
	for current != unsafe { nil } {
		next := current.next
		C.free(current.address)
		C.free(current.canonname)
		C.free(current)
		current = next
	}
}

fn darwin_getaddrinfo(node &char, service &char, hints &DarwinAddrinfo, output &&DarwinAddrinfo) i32 {
	previous := unsafe { *C.ios_errno_address() }
	mut system_error := false
	// musl's speculative IPv4 parsing can leave EINVAL after a successful
	// IPv6 lookup. Only EAI_SYSTEM publishes the native resolver's errno.
	defer { if !system_error { darwin_set_errno(previous) } }
	if output == unsafe { nil } { return 12 }
	unsafe { *output = nil }
	if node == unsafe { nil } && service == unsafe { nil } { return 8 }
	mut flags := i32(0)
	mut family := i32(0)
	mut kind := i32(0)
	mut protocol := i32(0)
	if hints != unsafe { nil } {
		flags = hints.flags; family = hints.family
		kind = hints.socktype; protocol = hints.protocol
	}
	if family !in [i32(0), 2, 30] { return 5 }
	if kind < 0 || kind > 3 { return 12 }
	if protocol !in [i32(0), 1, 6, 17, 58] { return 12 }
	if (kind == 1 && protocol !in [i32(0), 6]) || (kind == 2 && protocol !in [i32(0), 17]) { return 12 }
	if (protocol == 1 && family == 30) || (protocol == 58 && family == 2) { return 8 }
	if flags & ~i32(7 | 0x100 | 0x200 | 0x400 | 0x800 | 0x1000 | 0x10000000) != 0 { return 3 }
	if !netdb_service_valid(service, flags) { return 8 }
	mut native_flags := i32(0)
	for pair in [[i32(1), i32(C.AI_PASSIVE)]!, [i32(2), i32(C.AI_CANONNAME)]!,
		[i32(4), i32(C.AI_NUMERICHOST)]!, [i32(0x100), i32(C.AI_ALL)]!,
		[i32(0x400), i32(C.AI_ADDRCONFIG)]!, [i32(0x1000), i32(C.AI_NUMERICSERV)]!]! {
		if flags & pair[0] != 0 { native_flags |= pair[1] }
	}
	if flags & (0x200 | 0x800) != 0 { native_flags |= i32(C.AI_V4MAPPED) }
	if flags == 0 { native_flags |= i32(C.AI_ADDRCONFIG) | i32(C.AI_V4MAPPED) }
	// Darwin treats SOCK_RAW with protocol zero as an unspecified type. With
	// a specified protocol, it selects UDP/TCP or an ICMP raw socket.
	if kind == 3 { kind = 0 }
	if protocol == 1 || protocol == 58 { kind = 3 }
	if family == 0 && protocol == 1 { family = 2 }
	if family == 0 && protocol == 58 { family = 30 }
	raw := kind == 3
	// musl's resolver accepts TCP/UDP hints only. Resolve the actual address
	// and service through it, then supply Darwin's requested raw metadata.
	// A named service may exist for just one of UDP or TCP.
	mut native_hints := C.addrinfo{
		ai_flags: native_flags
		ai_family: i32(socket_native_family(family))
		ai_socktype: if raw { i32(2) } else { kind }
		ai_protocol: if raw { i32(17) } else { protocol }
	}
	mut native_list := unsafe { &C.addrinfo(nil) }
	mut result := C.getaddrinfo(node, service, unsafe { &native_hints }, unsafe { &native_list })
	if raw && result == C.EAI_SERVICE {
		native_hints.ai_socktype = 1; native_hints.ai_protocol = 6
		result = C.getaddrinfo(node, service, unsafe { &native_hints }, unsafe { &native_list })
	}
	system_error = result == C.EAI_SYSTEM
	if result != 0 { return netdb_error(result) }
	defer { C.freeaddrinfo(native_list) }
	mut numeric := false
	if node != unsafe { nil } {
		mut bytes := [16]u8{}
		numeric = C.inet_pton(C.AF_INET, node, unsafe { &bytes[0] }) == 1 || C.inet_pton(C.AF_INET6, node, unsafe { &bytes[0] }) == 1
	}
	mut head := unsafe { &DarwinAddrinfo(nil) }
	mut tail := unsafe { &DarwinAddrinfo(nil) }
	mut current := native_list
	for current != unsafe { nil } {
		if current.ai_family !in [i32(C.AF_INET), i32(C.AF_INET6)] || current.ai_addrlen > 128 || current.ai_addr == unsafe { nil } {
			darwin_freeaddrinfo(head)
			return 5
		}
		mut entry := unsafe { &DarwinAddrinfo(C.calloc(1, sizeof(DarwinAddrinfo))) }
		if entry == unsafe { nil } { darwin_freeaddrinfo(head); return 6 }
		if head == unsafe { nil } { head = entry } else { tail.next = entry }
		tail = entry
		entry.family = if current.ai_family == C.AF_INET { 2 } else { 30 }
		entry.socktype = if raw { i32(3) } else { current.ai_socktype }
		entry.protocol = if raw { protocol } else { current.ai_protocol }
		entry.addrlen = current.ai_addrlen
		entry.address = C.malloc(entry.addrlen)
		if entry.address == unsafe { nil } { darwin_freeaddrinfo(head); return 6 }
		mut storage := [16]u64{}
		unsafe { C.memcpy(&storage[0], current.ai_addr, entry.addrlen) }
		socket_address_out(unsafe { &storage[0] }, entry.addrlen, entry.address, &entry.addrlen)
		if flags & 2 != 0 && !numeric && current.ai_canonname != unsafe { nil } {
			entry.canonname = C.strdup(current.ai_canonname)
			if entry.canonname == unsafe { nil } { darwin_freeaddrinfo(head); return 6 }
		}
		current = current.ai_next
	}
	if head == unsafe { nil } { return 8 }
	unsafe { *output = head }
	return 0
}

fn darwin_getnameinfo(address voidptr, length u32, host &char, host_length u32, service &char, service_length u32, flags i32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	mut system_error := false
	defer { if !system_error { darwin_set_errno(previous) } }
	if address == unsafe { nil } || length < 2 { return 5 }
	family := unsafe { (&u8(address))[1] }
	if family !in [u8(2), 30] { return 5 }
	if (family == 2 && length != 16) || (family == 30 && length != 28) { return 5 }
	if flags & ~i32(1 | 2 | 4 | 8 | 16 | 32 | 256) != 0 { return 3 }
	mut native_flags := i32(0)
	for pair in [[i32(1), i32(C.NI_NOFQDN)]!, [i32(2), i32(C.NI_NUMERICHOST)]!,
		[i32(4), i32(C.NI_NAMEREQD)]!, [i32(8), i32(C.NI_NUMERICSERV)]!,
		[i32(16), i32(C.NI_DGRAM)]!, [i32(256), i32(C.NI_NUMERICSCOPE)]!]! {
		if flags & pair[0] != 0 { native_flags |= pair[1] }
	}
	// Modern native resolvers include a nonzero IPv6 scope already.
	mut storage := [16]u64{}
	if !socket_address_in(address, length, unsafe { &storage[0] }) { return 5 }
	want_host := host != unsafe { nil } && host_length != 0
	want_service := service != unsafe { nil } && service_length != 0
	if !want_host && !want_service { return 0 }
	mut host_buffer := [1025]char{}
	mut service_buffer := [32]char{}
	result := C.getnameinfo(unsafe { voidptr(&storage[0]) }, length,
		if want_host { unsafe { &host_buffer[0] } } else { unsafe { nil } }, if want_host { 1025 } else { 0 },
		if want_service { unsafe { &service_buffer[0] } } else { unsafe { nil } }, if want_service { 32 } else { 0 }, native_flags)
	system_error = result == C.EAI_SYSTEM
	if result != 0 { return netdb_error(result) }
	// Darwin copies host first. A host overflow writes neither output; a
	// service overflow leaves a successfully written host intact.
	if want_host {
		size := darwin_strlen(unsafe { &host_buffer[0] }) + 1
		if size > host_length { return 14 }
		unsafe { C.memcpy(host, &host_buffer[0], size) }
	}
	if want_service {
		size := darwin_strlen(unsafe { &service_buffer[0] }) + 1
		if size > service_length { return 14 }
		unsafe { C.memcpy(service, &service_buffer[0], size) }
	}
	return 0
}

fn netdb_symbol(symbol string) ?u64 {
	return match symbol {
		'_getaddrinfo' { u64(unsafe { voidptr(darwin_getaddrinfo) }) }
		'_freeaddrinfo' { u64(unsafe { voidptr(darwin_freeaddrinfo) }) }
		'_getnameinfo' { u64(unsafe { voidptr(darwin_getnameinfo) }) }
		else { none }
	}
}
