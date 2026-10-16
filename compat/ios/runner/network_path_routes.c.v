// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

$if macos {
	#include <sys/sockio.h>
	#include <net/if_media.h>
}
type NWSCAll = fn () u64
type NWSCGet = fn (u64) u64
type NWSCLength = fn (u64) i64
type NWSCAt = fn (u64, i64) u64
type NWSCCString = fn (u64, &char, i64, u32) bool
type NWSCEq = fn (u64, u64) bool
type NWSCRelease = fn (u64)
struct C.ifmediareq {
mut:
	ifm_name [16]char
	ifm_current i32
}
struct NWRoute { family u32 index u32 }
struct NWRoutes {
mut:
	count int
	entries [64]NWRoute
}
struct NWLink { name [64]u8 index u32 kind u32 families u32 }
struct NWSnapshot {
mut:
	status u32 = 2
	dns bool
	ipv4 bool
	ipv6 bool
	count int
	links [64]NWLink
}

fn nw_route_add(mut routes NWRoutes, family u32, index u32) bool {
	if index == 0 { return true }
	for i in 0 .. routes.count {
		if routes.entries[i].family == family && routes.entries[i].index == index { return true }
	}
	if routes.count == routes.entries.len { return false }
	routes.entries[routes.count] = NWRoute{family, index}
	routes.count++
	return true
}

// Read actual unicast default routes. The netlink socket, BSD dump and native
// interface list are temporary, including malformed or timed-out query paths.
fn nw_default_routes() ?NWRoutes {
	mut routes := NWRoutes{}
	$if linux {
		fd := C.socket(16, 2, 0)
		if fd < 0 { return none }
		defer { C.close(fd) }
		mut request := [28]u8{}
		request[0] = 28; request[4] = 26; request[6] = 1; request[7] = 3; request[8] = 1
		mut destination := [12]u8{}; destination[0] = 16
		if C.sendto(fd, unsafe { &request[0] }, 28, C.MSG_DONTWAIT, unsafe { voidptr(&destination[0]) }, 12) != 28 { return none }
		mut buffer := [4096]u64{}
		base := u64(unsafe { &buffer[0] }); deadline := darwin_mach_absolute_time() + 1000000000
		for _ in 0 .. 64 {
			now := darwin_mach_absolute_time(); if now >= deadline { return none }
			mut wait := C.pollfd{fd: fd, events: 1}
			if C.poll(unsafe { &wait }, 1, i32((deadline - now + 999999) / 1000000)) != 1 || wait.revents & 1 == 0 { return none }
			received := C.recv(fd, unsafe { &buffer[0] }, sizeof(buffer), C.MSG_TRUNC | C.MSG_DONTWAIT)
			if received < 16 || received > isize(sizeof(buffer)) { return none }
			mut cursor := u64(0)
			for cursor + 16 <= u64(received) {
				length := u64(reachability_word(base, cursor, 4)); kind := reachability_word(base, cursor + 4, 2)
				if length < 16 || length > u64(received) - cursor { return none }
				if kind == 3 { return routes }
				if kind == 2 { return none }
				if kind == 24 && length >= 28 && reachability_word(base, cursor + 17, 2) == 0 && reachability_word(base, cursor + 23, 1) == 1 {
					family := reachability_word(base, cursor + 16, 1)
					mut table := reachability_word(base, cursor + 20, 1); mut index := u32(0); mut is_default := true
					mut at := cursor + 28
					for at + 4 <= cursor + length {
						size := u64(reachability_word(base, at, 2)); tag := reachability_word(base, at + 2, 2)
						if size < 4 || size > cursor + length - at { return none }
						if tag == 4 && size >= 8 { index = reachability_word(base, at + 4, 4) }
						if tag == 15 && size >= 8 { table = reachability_word(base, at + 4, 4) }
						if tag == 1 && !reachability_zero(base + at, 4, u32(size - 4)) { is_default = false }
						at += (size + 3) & ~u64(3)
					}
					if family in [u32(2), 10]! && table == 254 && is_default && !nw_route_add(mut routes, family, index) { return none }
				}
				cursor += (length + 3) & ~u64(3)
			}
		}
		return none
	}
	$if macos {
		mut mib := [i32(C.CTL_NET), i32(C.PF_ROUTE), i32(0), i32(0), i32(C.NET_RT_DUMP2), i32(0)]!
		mut size := usize(0)
		if C.sysctl(unsafe { &mib[0] }, 6, unsafe { nil }, unsafe { &size }, unsafe { nil }, 0) != 0 || size > 4194304 { return none }
		if size == 0 { return routes }
		data := C.malloc(size); if data == unsafe { nil } { return none }; defer { C.free(data) }
		if C.sysctl(unsafe { &mib[0] }, 6, data, unsafe { &size }, unsafe { nil }, 0) != 0 { return none }
		base := u64(data); mut cursor := u64(0)
		for cursor + sizeof(C.rt_msghdr2) <= size {
			header := unsafe { &C.rt_msghdr2(base + cursor) }; length := u64(header.rtm_msglen)
			if length < sizeof(C.rt_msghdr2) || length > size - cursor { return none }
			if header.rtm_flags & 1 != 0 && header.rtm_flags & (4 | 8 | 0x1000) == 0 && header.rtm_addrs & 5 == 5 {
				mut at := cursor + sizeof(C.rt_msghdr2); mut family := u32(0); mut mask := false
				for bit in 0 .. 8 {
					if header.rtm_addrs & (1 << bit) == 0 { continue }
					if at + 2 > cursor + length { return none }
					bytes := reachability_word(base, at, 1); af := reachability_word(base, at + 1, 1)
					if u64(bytes) > cursor + length - at { return none }
					if bit == 0 {
						if af == 2 && bytes >= 8 && reachability_zero(base + at, 4, 4) { family = 2 }
						if af == 30 && bytes >= 24 && reachability_zero(base + at, 8, 16) { family = 30 }
					}
					if bit == 2 { mask = bytes <= 2 || reachability_zero(base + at, 2, bytes - 2) }
					at += if bytes == 0 { u64(4) } else { u64((bytes + 3) & ~u32(3)) }
				}
				// rtm_index is the native unsigned-short at offset 4 in rt_msghdr2.
				if family != 0 && mask && !nw_route_add(mut routes, family, reachability_word(base, cursor + 4, 2)) { return none }
			}
			cursor += length
		}
		return routes
	}
	return none
}

fn nw_link_kind(list &C.ifaddrs, name &char, flags u32) u32 {
	if flags & u32(C.IFF_LOOPBACK) != 0 { return 4 }
	$if macos {
		// Wi-Fi drivers can report Ethernet media through SIOCGIFMEDIA. Use
		// the BSD-name mapping for this Mac backend; Vinix uses native ioctls.
		sc := C.dlopen(c'/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration', 2)
		cf := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		defer { if sc != unsafe { nil } { C.dlclose(sc) }; if cf != unsafe { nil } { C.dlclose(cf) } }
		interfaces := if sc != unsafe { nil } && cf != unsafe { nil } { unsafe { NWSCAll(C.dlsym(sc, c'SCNetworkInterfaceCopyAll'))() } } else { u64(0) }
		if interfaces != 0 {
			release := unsafe { NWSCRelease(C.dlsym(cf, c'CFRelease')) }
			defer { release(interfaces) }
			count := unsafe { NWSCLength(C.dlsym(cf, c'CFArrayGetCount'))(interfaces) }
			if count >= 0 && count <= 512 {
				for i in i64(0) .. count {
					link := unsafe { NWSCAt(C.dlsym(cf, c'CFArrayGetValueAtIndex'))(interfaces, i) }
					bsd := unsafe { NWSCGet(C.dlsym(sc, c'SCNetworkInterfaceGetBSDName'))(link) }
					mut text := [64]char{}
					if bsd != 0 && unsafe { NWSCCString(C.dlsym(cf, c'CFStringGetCString'))(bsd, &text[0], 64, 0x08000100) } && C.strcmp(unsafe { &text[0] }, name) == 0 {
						kind := unsafe { NWSCGet(C.dlsym(sc, c'SCNetworkInterfaceGetInterfaceType'))(link) }
						if unsafe { NWSCEq(C.dlsym(cf, c'CFEqual'))(kind, read64(u64(C.dlsym(sc, c'kSCNetworkInterfaceTypeIEEE80211')))) } { return 1 }
						if unsafe { NWSCEq(C.dlsym(cf, c'CFEqual'))(kind, read64(u64(C.dlsym(sc, c'kSCNetworkInterfaceTypeEthernet')))) } { return 3 }
						return 0
					}
				}
			}
		}
	}
	fd := C.socket(C.AF_INET, C.SOCK_DGRAM, 0)
	if fd >= 0 {
		defer { C.close(fd) }
		$if macos {
			mut request := C.ifmediareq{}
			unsafe { C.memcpy(&request.ifm_name[0], name, C.strnlen(name, 15)) }
			if C.ioctl(fd, u64(C.SIOCGIFMEDIA), unsafe { &request }) == 0 {
				if request.ifm_current & C.IFM_TMASK == C.IFM_IEEE80211 { return 1 }
				if request.ifm_current & C.IFM_TMASK == C.IFM_ETHER { return 3 }
			}
		}
		$if linux {
			mut request := [32]u8{}
			unsafe { C.memcpy(&request[0], name, C.strnlen(name, 15)) }
			if C.ioctl(fd, 0x8b01, unsafe { &request[0] }) == 0 { return 1 } // SIOCGIWNAME
		}
	}
	mut current := unsafe { list }
	for current != unsafe { nil } {
		address := current.ifa_addr
		if address != unsafe { nil } && C.strcmp(current.ifa_name, name) == 0 {
			$if linux { if reachability_word(u64(address), 0, 2) == 17 && reachability_word(u64(address), 8, 2) == 1 { return 3 } }
			$if macos { if reachability_word(u64(address), 1, 1) == 18 && reachability_word(u64(address), 4, 1) == 6 { return 3 } }
		}
		current = current.ifa_next
	}
	return 0
}

fn nw_dns_configured() bool {
	file := C.fopen(c'/etc/resolv.conf', c'r')
	if file == unsafe { nil } { return false }; defer { C.fclose(file) }
	mut line := [512]char{}; mut address := [16]u8{}
	for _ in 0 .. 256 {
		if C.fgets(unsafe { &line[0] }, 512, file) == unsafe { nil } { break }
		mut at := 0
		for at < 510 && line[at] in [char(32), 9]! { at++ }
		if at + 11 >= 512 || C.strncmp(unsafe { &line[at] }, c'nameserver', 10) != 0 || line[at + 10] !in [char(32), 9]! { continue }
		at += 10; for at < 511 && line[at] in [char(32), 9]! { at++ }; start := at
		for at < 511 && line[at] !in [char(0), 9, 10, 13, 32, 35, 59]! { at++ }
		line[at] = 0
		if C.inet_pton(C.AF_INET, unsafe { &line[start] }, unsafe { &address[0] }) == 1 || C.inet_pton(C.AF_INET6, unsafe { &line[start] }, unsafe { &address[0] }) == 1 { return true }
	}
	return false
}

fn nw_snapshot() ?NWSnapshot {
	routes := nw_default_routes() or { return none }; mut result := NWSnapshot{}
	mut list := unsafe { &C.ifaddrs(nil) }
	if C.getifaddrs(unsafe { &list }) != 0 { return none }; defer { C.freeifaddrs(list) }
	mut current := list
	for current != unsafe { nil } {
		entry := current; current = current.ifa_next; address := entry.ifa_addr
		if address == unsafe { nil } || entry.ifa_flags & u32(C.IFF_UP | C.IFF_RUNNING) != u32(C.IFF_UP | C.IFF_RUNNING) { continue }
		mut family := u32(0)
		$if macos { family = reachability_word(u64(address), 1, 1) }
		$if linux { family = reachability_word(u64(address), 0, 2) }
		if family != u32(C.AF_INET) && family != u32(C.AF_INET6) { continue }
		offset := if family == u32(C.AF_INET) { u32(4) } else { u32(8) }; length := if family == u32(C.AF_INET) { u32(4) } else { u32(16) }
		if reachability_zero(u64(address), offset, length) { continue }
		if family == u32(C.AF_INET6) && reachability_word(u64(address), 8, 1) == 0xfe && reachability_word(u64(address), 9, 1) & 0xc0 == 0x80 { continue }
		index := C.if_nametoindex(entry.ifa_name); mut routed := false
		for i in 0 .. routes.count { if routes.entries[i].family == family && routes.entries[i].index == index { routed = true; break } }
		if !routed { continue }
		name_length := C.strnlen(entry.ifa_name, 64); if name_length == 0 || name_length >= 64 { return none }
		mut at := 0; for at < result.count && result.links[at].index < index { at++ }
		bit := if family == u32(C.AF_INET) { u32(1) } else { u32(2) }
		if at < result.count && result.links[at].index == index {
			previous := result.links[at]; result.links[at] = NWLink{previous.name, index, previous.kind, previous.families | bit}
		} else {
			if result.count == result.links.len { return none }
			mut name := [64]u8{}; unsafe { C.memcpy(&name[0], entry.ifa_name, name_length) }
			mut tail := result.count; for tail > at { result.links[tail] = result.links[tail - 1]; tail-- }
			result.links[at] = NWLink{name, index, nw_link_kind(list, entry.ifa_name, entry.ifa_flags), bit}; result.count++
		}
		if bit == 1 { result.ipv4 = true } else { result.ipv6 = true }
	}
	if result.ipv4 || result.ipv6 { result.status = 1; result.dns = nw_dns_configured() }
	return result
}

fn nw_snapshot_equal(a &NWSnapshot, b &NWSnapshot) bool {
	if a.status != b.status || a.dns != b.dns || a.ipv4 != b.ipv4 || a.ipv6 != b.ipv6 || a.count != b.count { return false }
	for i in 0 .. a.count {
		if a.links[i].index != b.links[i].index || a.links[i].kind != b.links[i].kind || a.links[i].families != b.links[i].families || a.links[i].name != b.links[i].name { return false }
	}
	return true
}
