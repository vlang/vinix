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
	ifa_flags u32
	ifa_addr  &C.sockaddr
}

fn C.getifaddrs(&&C.ifaddrs) i32
fn C.freeifaddrs(&C.ifaddrs)

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
