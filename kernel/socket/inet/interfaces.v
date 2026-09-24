// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module inet

import errno
import usercopy

// The network interfaces, as rtnetlink and the SIOCGIF* ioctls describe them:
// lo, and eth0 once a driver has attached. There is one stack, configured by
// DHCP, so these are only ever read.

pub const arphrd_ether = u16(1)
pub const arphrd_loopback = u16(772)

// IFF_UP | IFF_LOOPBACK | IFF_RUNNING | IFF_LOWER_UP
const lo_flags = u32(0x10049)
// IFF_UP | IFF_BROADCAST | IFF_RUNNING | IFF_MULTICAST | IFF_LOWER_UP
const ether_flags = u32(0x11043)

// Addresses are as lwIP keeps them, in network byte order, so writing one out
// little-endian gives its bytes in the order both interfaces want.
pub struct Interface {
pub:
	index   u32
	name    string
	kind    u16
	flags   u32
	mtu     u32
	txqlen  u32
	mac     [6]u8
	address u32
	netmask u32
	gateway u32
}

pub fn interfaces() []Interface {
	mut list := []Interface{cap: 2}
	list << Interface{
		index:   1
		name:    'lo'
		kind:    arphrd_loopback
		flags:   lo_flags
		mtu:     65536
		address: 0x0100007f
		netmask: 0x000000ff
	}
	mut mac := [6]u8{}
	mut mtu := u32(0)
	if link_info(mut mac, mut mtu) {
		mut address := u32(0)
		mut netmask := u32(0)
		mut gateway := u32(0)
		dns := [3]u32{}
		configuration(&address, &netmask, &gateway, &dns)
		list << Interface{
			index:   2
			name:    'eth0'
			kind:    arphrd_ether
			flags:   ether_flags
			mtu:     mtu
			txqlen:  1000
			mac:     mac
			address: address
			netmask: netmask
			gateway: gateway
		}
	}
	return list
}

pub fn prefix_length(netmask u32) u8 {
	mut bits := u8(0)
	mut rest := netmask
	for rest != 0 {
		bits += u8(rest & 1)
		rest >>= 1
	}
	return bits
}

const siocgifname = u64(0x8910)
const siocgifconf = u64(0x8912)
const siocgifflags = u64(0x8913)
const siocgifaddr = u64(0x8915)
const siocgifbrdaddr = u64(0x8919)
const siocgifnetmask = u64(0x891b)
const siocgifmetric = u64(0x891d)
const siocgifmtu = u64(0x8921)
const siocgifhwaddr = u64(0x8927)
const siocgifindex = u64(0x8933)
const siocgiftxqlen = u64(0x8942)
const siocgifmap = u64(0x8970)

const ifnamsiz = 16
const ifreq_size = 40
const eaddrnotavail = u64(99)

// struct ifreq: the interface name, then a 24-byte union.
struct IfReq {
mut:
	name  [ifnamsiz]u8
	value [24]u8
}

// struct ifconf on a 64-bit ABI: a length, padding and the buffer pointer.
struct IfConf {
mut:
	len    i32
	pad    i32
	buffer u64
}

pub fn is_interface_ioctl(request u64) bool {
	return request in [siocgifname, siocgifconf, siocgifflags, siocgifaddr, siocgifbrdaddr,
		siocgifnetmask, siocgifmetric, siocgifmtu, siocgifhwaddr, siocgifindex, siocgiftxqlen,
		siocgifmap]
}

fn put_sockaddr_in(mut req IfReq, address u32) {
	req.value = [24]u8{}
	req.value[0] = 2 // AF_INET
	req.value[4] = u8(address)
	req.value[5] = u8(address >> 8)
	req.value[6] = u8(address >> 16)
	req.value[7] = u8(address >> 24)
}

fn put_int(mut req IfReq, value u32) {
	req.value = [24]u8{}
	req.value[0] = u8(value)
	req.value[1] = u8(value >> 8)
	req.value[2] = u8(value >> 16)
	req.value[3] = u8(value >> 24)
}

fn name_matches(req &IfReq, name string) bool {
	for i in 0 .. ifnamsiz {
		c := req.name[i]
		if i == name.len {
			return c == 0
		}
		if c != name[i] {
			return false
		}
	}
	return false
}

// SIOCGIFCONF: an ifreq for each interface with an address, or, given no
// buffer, how much room they need.
fn interface_list_ioctl(argp voidptr) ?int {
	mut conf := IfConf{}
	if !usercopy.copy_from_user(voidptr(&conf), u64(argp), sizeof(IfConf)) {
		errno.set(errno.efault)
		return none
	}
	list := interfaces()
	defer {
		unsafe { list.free() }
	}
	mut written := 0
	for iface in list {
		if iface.address == 0 {
			continue
		}
		if conf.buffer != 0 {
			if written + ifreq_size > conf.len {
				break
			}
			mut req := IfReq{}
			for i in 0 .. iface.name.len {
				req.name[i] = iface.name[i]
			}
			put_sockaddr_in(mut req, iface.address)
			if !usercopy.copy_to_user(conf.buffer + u64(written), voidptr(&req), sizeof(IfReq)) {
				errno.set(errno.efault)
				return none
			}
		}
		written += ifreq_size
	}
	conf.len = written
	if !usercopy.copy_to_user(u64(argp), voidptr(&conf), sizeof(IfConf)) {
		errno.set(errno.efault)
		return none
	}
	return 0
}

// The SIOCGIF* queries ifconfig, `ip` and the C library's if_nametoindex ask
// about one interface, named in the ifreq (or, for SIOCGIFNAME, numbered).
pub fn interface_ioctl(request u64, argp voidptr) ?int {
	if request == siocgifconf {
		return interface_list_ioctl(argp)
	}
	mut req := IfReq{}
	if !usercopy.copy_from_user(voidptr(&req), u64(argp), sizeof(IfReq)) {
		errno.set(errno.efault)
		return none
	}
	list := interfaces()
	defer {
		unsafe { list.free() }
	}
	mut found := -1
	for i, iface in list {
		matches := if request == siocgifname {
			u32(req.value[0]) | (u32(req.value[1]) << 8) | (u32(req.value[2]) << 16) | (u32(req.value[3]) << 24) == iface.index
		} else {
			name_matches(&req, iface.name)
		}
		if matches {
			found = i
			break
		}
	}
	if found < 0 {
		errno.set(errno.enodev)
		return none
	}
	iface := list[found]
	match request {
		siocgifname {
			req.name = [ifnamsiz]u8{}
			for i in 0 .. iface.name.len {
				req.name[i] = iface.name[i]
			}
		}
		siocgifflags {
			put_int(mut req, iface.flags & 0xffff)
		}
		siocgifaddr, siocgifbrdaddr, siocgifnetmask {
			if iface.address == 0 {
				errno.set(eaddrnotavail)
				return none
			}
			put_sockaddr_in(mut req, match request {
				siocgifaddr { iface.address }
				siocgifnetmask { iface.netmask }
				else { iface.address | ~iface.netmask }
			})
		}
		siocgifmetric, siocgifmap {
			put_int(mut req, 0)
		}
		siocgifmtu {
			put_int(mut req, iface.mtu)
		}
		siocgifhwaddr {
			req.value = [24]u8{}
			req.value[0] = u8(iface.kind)
			req.value[1] = u8(iface.kind >> 8)
			for i in 0 .. 6 {
				req.value[2 + i] = iface.mac[i]
			}
		}
		siocgifindex {
			put_int(mut req, iface.index)
		}
		siocgiftxqlen {
			put_int(mut req, iface.txqlen)
		}
		else {}
	}
	if !usercopy.copy_to_user(u64(argp), voidptr(&req), sizeof(IfReq)) {
		errno.set(errno.efault)
		return none
	}
	return 0
}
