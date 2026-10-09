// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <net/if.h>
#include <ifaddrs.h>

struct C.ifaddrs {
mut:
	ifa_next &C.ifaddrs
	ifa_name &char
	ifa_flags u32
	ifa_addr voidptr
	ifa_netmask voidptr
	ifa_dstaddr voidptr
	ifa_data voidptr
}

struct DarwinIfaddrs {
mut:
	next &DarwinIfaddrs
	name &char
	flags u32
	address voidptr
	netmask voidptr
	destination voidptr
	data voidptr
}

fn C.getifaddrs(&&C.ifaddrs) i32
fn C.freeifaddrs(&C.ifaddrs)
fn C.if_nametoindex(&char) u32

fn darwin_if_nametoindex(name &char) u32 {
	if name == unsafe { nil } { darwin_set_errno(14); return 0 }
	previous := unsafe { *C.ios_errno_address() }
	index := C.if_nametoindex(name)
	if index == 0 {
		err := unsafe { *C.ios_errno_address() }
		darwin_set_errno(if err == C.ENODEV || err == C.ENXIO { 6 } else { darwin_native_error(err) })
	} else { darwin_set_errno(previous) }
	return index
}

// Linux sockaddr_ll -> Darwin sockaddr_dl. Both the interface identity and
// hardware address come from the native interface snapshot, never a registry
// of fabricated iOS names. sockaddr_dl embeds its non-NUL-terminated name.
fn ifaddrs_link_address(address voidptr, name &char) voidptr {
	name_length := darwin_strlen(name)
	index := read32(u64(address) + 4)
	kind := unsafe { *(&u16(u64(address) + 8)) }
	address_length := if kind == 772 { usize(0) } else { usize(unsafe { (&u8(address))[11] }) }
	if index > 65535 || address_length > 8 || name_length + address_length > 247 {
		darwin_set_errno(84); return unsafe { nil }
	}
	mut size := (8 + name_length + address_length + 3) & ~usize(3)
	if size > 255 { darwin_set_errno(84); return unsafe { nil } }
	if size < 20 { size = 20 }
	mut result := unsafe { &u8(C.calloc(1, size)) }
	if result == unsafe { nil } { darwin_set_errno(12); return unsafe { nil } }
	unsafe {
		result[0] = u8(size); result[1] = 18
		*(&u16(result + 2)) = u16(index)
		result[4] = if kind == 772 { u8(24) } else if kind == 1 { u8(6) } else { u8(1) }
		result[5] = u8(name_length); result[6] = u8(address_length)
		C.memcpy(result + 8, name, name_length)
		if address_length != 0 { C.memcpy(result + 8 + name_length, voidptr(u64(address) + 12), address_length) }
	}
	return result
}

fn ifaddrs_address_copy(address voidptr, name &char) voidptr {
	if address == unsafe { nil } { return unsafe { nil } }
	$if macos {
		// Darwin netmasks may be shorter than sockaddr_in (lo0 has sa_len=5),
		// and an absent peer may have sa_len=0. Keep the native header and
		// zero-fill enough storage to safely read the entire address value.
		length := usize(unsafe { *(&u8(address)) })
		size := if length < 28 { usize(28) } else { length }
		result := C.calloc(1, size)
		if result == unsafe { nil } { darwin_set_errno(12); return result }
		unsafe { C.memcpy(result, address, if length < 2 { usize(2) } else { length }) }
		return result
	}
	family := unsafe { *(&u16(address)) }
	if family == 17 { return ifaddrs_link_address(address, name) }
	if family !in [u16(2), 10] { darwin_set_errno(47); return unsafe { nil } }
	mut size := if family == 2 { u32(16) } else { u32(28) }
	result := C.malloc(size)
	if result == unsafe { nil } { darwin_set_errno(12); return result }
	mut storage := [16]u64{}
	unsafe { C.memcpy(&storage[0], address, size) }
	socket_address_out(unsafe { &storage[0] }, size, result, unsafe { &size })
	return result
}

fn darwin_freeifaddrs(list &DarwinIfaddrs) {
	mut current := unsafe { list }
	for current != unsafe { nil } {
		next := current.next
		C.free(current.name)
		C.free(current.address)
		C.free(current.netmask)
		C.free(current.destination)
		C.free(current.data)
		C.free(current)
		current = next
	}
}

fn darwin_getifaddrs(output &&DarwinIfaddrs) i32 {
	if output == unsafe { nil } { darwin_set_errno(14); return -1 }
	unsafe { *output = nil }
	previous := unsafe { *C.ios_errno_address() }
	mut native := unsafe { &C.ifaddrs(nil) }
	if C.getifaddrs(unsafe { &native }) != 0 {
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
		return -1
	}
	defer { C.freeifaddrs(native) }
	mut head := unsafe { &DarwinIfaddrs(nil) }
	mut tail := unsafe { &DarwinIfaddrs(nil) }
	mut current := native
	for current != unsafe { nil } {
		mut entry := unsafe { &DarwinIfaddrs(C.calloc(1, sizeof(DarwinIfaddrs))) }
		if entry == unsafe { nil } { darwin_freeifaddrs(head); darwin_set_errno(12); return -1 }
		if head == unsafe { nil } { head = entry } else { tail.next = entry }
		tail = entry
		entry.name = C.strdup(current.ifa_name)
		if entry.name == unsafe { nil } { darwin_freeifaddrs(head); darwin_set_errno(12); return -1 }
		entry.flags = current.ifa_flags
		$if linux {
			entry.flags = current.ifa_flags & 0x3ff
			if current.ifa_flags & u32(C.IFF_MULTICAST) != 0 { entry.flags |= 0x8000 }
		}
		entry.address = ifaddrs_address_copy(current.ifa_addr, entry.name)
		entry.netmask = ifaddrs_address_copy(current.ifa_netmask, entry.name)
		entry.destination = ifaddrs_address_copy(current.ifa_dstaddr, entry.name)
		if (current.ifa_addr != unsafe { nil } && entry.address == unsafe { nil }) ||
			(current.ifa_netmask != unsafe { nil } && entry.netmask == unsafe { nil }) ||
			(current.ifa_dstaddr != unsafe { nil } && entry.destination == unsafe { nil }) {
			darwin_freeifaddrs(head); return -1
		}
		$if macos {
			if current.ifa_data != unsafe { nil } {
				entry.data = C.malloc(96)
				if entry.data == unsafe { nil } { darwin_freeifaddrs(head); darwin_set_errno(12); return -1 }
				unsafe { C.memcpy(entry.data, current.ifa_data, 96) }
			}
		}
		current = current.ifa_next
	}
	unsafe { *output = head }
	darwin_set_errno(previous)
	return 0
}

fn interfaces_symbol(symbol string) ?u64 {
	return match symbol {
		'_getifaddrs' { u64(unsafe { voidptr(darwin_getifaddrs) }) }
		'_freeifaddrs' { u64(unsafe { voidptr(darwin_freeifaddrs) }) }
		'_if_nametoindex' { u64(unsafe { voidptr(darwin_if_nametoindex) }) }
		else { none }
	}
}
