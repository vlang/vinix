// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#include <ifaddrs.h>
#include <sys/socket.h>
#include <net/if.h>

struct C.sockaddr {
	sa_family u16
}

struct C.ifaddrs {
	ifa_next  &C.ifaddrs
	ifa_name  &char
	ifa_flags u32
	ifa_addr  &C.sockaddr
}

fn C.getifaddrs(&&C.ifaddrs) i32
fn C.freeifaddrs(&C.ifaddrs)
fn C.if_nametoindex(&char) u32
fn C.strncmp(&char, &char, usize) i32
fn C.sendto(i32, voidptr, usize, i32, voidptr, u32) isize

// Ask the kernel for configured default routes. No DNS lookup, packet to an
// Internet endpoint, or captive portal validation is performed here.
fn ws_network_default_interface() u32 {
	unsafe {
		fd := C.socket(16, 2 | 0x80000 | 0x800, 0)
		if fd < 0 { return 0 }
		defer { C.close(fd) }
		request := &u8(C.alloca(28))
		C.memset(request, 0, 28)
		*(&u32(request)) = 28
		*(&u16(request + 4)) = 26 // RTM_GETROUTE
		*(&u16(request + 6)) = 0x301 // REQUEST | DUMP
		*(&u32(request + 8)) = 1
		address := &u8(C.alloca(12))
		C.memset(address, 0, 12)
		*(&u16(address)) = 16 // AF_NETLINK, kernel port 0
		if C.sendto(fd, request, 28, 0, voidptr(address), 12) != 28 { return 0 }
		buffer := &u8(C.alloca(16384))
		for batch := 0; batch < 16; batch++ {
			mut ready := WsPoll{fd: fd, events: 1}
			if C.poll(voidptr(&ready), 1, 100) <= 0 { return 0 }
			length := C.recv(fd, buffer, 16384, 0x40)
			if length <= 0 { return 0 }
			mut offset := isize(0)
			for offset + 16 <= length {
				message := buffer + offset
				size := isize(*(&u32(message)))
				if size < 16 || size > length - offset { return 0 }
				kind := *(&u16(message + 4))
				if kind == 2 || kind == 3 { return 0 }
				if kind == 24 && size >= 28 && (message[16] == 2 || message[16] == 10)
					&& message[17] == 0 && message[20] == 254 && message[23] == 1 {
					mut at := isize(28)
					for at + 4 <= size {
						attr := message + at
						n := isize(*(&u16(attr)))
						if n < 4 || n > size - at { break }
						if *(&u16(attr + 2)) == 4 && n == 8 { return *(&u32(attr + 4)) }
						at += (n + 3) & ~isize(3)
					}
				}
				offset += (size + 3) & ~isize(3)
			}
		}
		return 0
	}
}

// Low byte: link configured (1), default route (2). Next byte: known Android
// transport + 1, or zero if unknown. Upper half: kernel interface index.
// Metering and Internet validation require services we do not currently have.
fn ws_network_state() i32 {
	unsafe {
		mut addresses := &C.ifaddrs(nil)
		if C.getifaddrs(&addresses) != 0 { return 0 }
		defer { C.freeifaddrs(addresses) }
		default_interface := ws_network_default_interface()
		mut chosen := &C.ifaddrs(nil)
		mut address := addresses
		for address != nil {
			flags := address.ifa_flags
			if flags & 0x41 == 0x41 && flags & 8 == 0 && address.ifa_addr != nil
				&& address.ifa_name != nil
				&& (address.ifa_addr.sa_family == 2 || address.ifa_addr.sa_family == 10) {
				if chosen == nil { chosen = address }
				if C.if_nametoindex(address.ifa_name) == default_interface { chosen = address; break }
			}
			address = address.ifa_next
		}
		if chosen == nil { return 0 }
		index := C.if_nametoindex(chosen.ifa_name)
		if index == 0 || index > 0xffff { return 0 }
		name := chosen.ifa_name
		mut transport := u32(0)
		if C.strncmp(name, c'wlan', 4) == 0 || C.strncmp(name, c'wl', 2) == 0 { transport = 2 }
		else if C.strncmp(name, c'eth', 3) == 0 || C.strncmp(name, c'en', 2) == 0 { transport = 4 }
		else if C.strncmp(name, c'rmnet', 5) == 0 || C.strncmp(name, c'wwan', 4) == 0 { transport = 1 }
		return i32((index << 16) | (transport << 8) | 1 | if index == default_interface { u32(2) } else { u32(0) })
	}
}

// Availability describes a configured, running non-loopback link. It does not
// claim that an Internet endpoint is reachable or that a captive portal passed.
fn ws_network_available() u8 {
	unsafe {
		mut addresses := &C.ifaddrs(nil)
		if C.getifaddrs(&addresses) != 0 { return 0 }
		defer { C.freeifaddrs(addresses) }
		mut address := addresses
		for address != nil {
			flags := address.ifa_flags
			if flags & 0x41 == 0x41 && flags & 8 == 0 && address.ifa_addr != nil
				&& (address.ifa_addr.sa_family == 2 || address.ifa_addr.sa_family == 10) {
				return 1
			}
			address = address.ifa_next
		}
		return 0
	}
}
