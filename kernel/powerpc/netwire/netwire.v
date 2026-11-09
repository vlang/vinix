// SPDX-License-Identifier: GPL-2.0-or-later
module netwire

pub fn be16(data &u8, at u32) u32 {
	unsafe { return u32(data[at]) << 8 | data[at + 1] }
}

pub fn be32(data &u8, at u32) u32 {
	return be16(data, at) << 16 | be16(data, at + 2)
}

pub fn put16(data &u8, at u32, value u32) {
	unsafe { data[at] = u8(value >> 8); data[at + 1] = u8(value) }
}

pub fn put32(data &u8, at u32, value u32) {
	put16(data, at, value >> 16)
	put16(data, at + 2, value)
}

pub fn checksum(data &u8, size u32, initial u32) u32 {
	mut sum := initial
	mut i := u32(0)
	for i + 1 < size { sum += be16(data, i); i += 2 }
	if i < size { unsafe { sum += u32(data[i]) << 8 } }
	for sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
	return ~sum & 0xffff
}

pub struct Ipv4 {
pub:
	valid bool
	header u32
	length u32
	protocol u8
	source u32
	destination u32
}

pub fn ipv4(data &u8, size u32) Ipv4 {
	if size < 34 || be16(data, 12) != 0x0800 { return Ipv4{} }
	unsafe {
		ihl := u32(data[14] & 15) * 4
		length := be16(data, 16)
		if data[14] >> 4 != 4 || ihl < 20 || ihl > size - 14 || length < ihl
			|| length > size - 14 || be16(data, 20) & 0xbfff != 0
			|| checksum(&data[14], ihl, 0) != 0 { return Ipv4{} }
		return Ipv4{true, ihl, length, data[23], be32(data, 26), be32(data, 30)}
	}
}

pub struct Dhcp {
pub:
	valid bool
	kind u8
	address u32
	server u32
	mask u32
	router u32
	lease u32
}

pub fn dhcp(data &u8, size u32, xid u32, mac &u8) Dhcp {
	ip := ipv4(data, size)
	if !ip.valid || ip.protocol != 17 || ip.length - ip.header < 248 { return Dhcp{} }
	udp := 14 + ip.header
	length := be16(data, udp + 4)
	if be16(data, udp) != 67 || be16(data, udp + 2) != 68 || length != ip.length - ip.header { return Dhcp{} }
	unsafe {
		pseudo := (ip.source >> 16) + (ip.source & 0xffff) + (ip.destination >> 16) + (ip.destination & 0xffff) + 17 + length
		if be16(data, udp + 6) != 0 && checksum(&data[udp], length, pseudo) != 0 { return Dhcp{} }
		boot := udp + 8
		if data[boot] != 2 || data[boot + 1] != 1 || data[boot + 2] != 6
			|| be32(data, boot + 4) != xid || be32(data, boot + 236) != 0x63825363 { return Dhcp{} }
		for i := u32(0); i < 6; i++ { if data[boot + 28 + i] != mac[i] { return Dhcp{} } }
		mut kind := u8(0)
		mut server := u32(0)
		mut mask := u32(0)
		mut router := u32(0)
		mut lease := u32(0)
		mut ended := false
		mut seen := u32(0)
		mut at := boot + 240
		end := udp + length
		for at < end {
			option := data[at]
			at++
			if option == 255 { ended = true; break }
			if option == 0 { continue }
			if at == end { return Dhcp{} }
			count := u32(data[at])
			at++
			if count > end - at || option == 52 { return Dhcp{} } // no overloaded fields
			bit := match option { 53 { u32(1) } 54 { u32(2) } 1 { u32(4) } 3 { u32(8) } 51 { u32(16) } else { u32(0) } }
			if seen & bit != 0 { return Dhcp{} }
			seen |= bit
			match option {
				53 { if count != 1 { return Dhcp{} }; kind = data[at] }
				54 { if count != 4 { return Dhcp{} }; server = be32(data, at) }
				1 { if count != 4 { return Dhcp{} }; mask = be32(data, at) }
				3 { if count < 4 || count % 4 != 0 { return Dhcp{} }; router = be32(data, at) }
				51 { if count != 4 { return Dhcp{} }; lease = be32(data, at) }
				else {}
			}
			at += count
		}
		address := be32(data, boot + 16)
		if !ended || (kind != 2 && kind != 5) || seen & 23 != 23 || address == 0 || server == 0
			|| mask == 0 || ((~mask + 1) & ~mask) != 0 || lease == 0 { return Dhcp{} }
		return Dhcp{true, kind, address, server, mask, router, lease}
	}
}
