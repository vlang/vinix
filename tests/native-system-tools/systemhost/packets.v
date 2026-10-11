// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import os

const guest_mac = [u8(0x52), 0x54, 0, 0x12, 0x34, 0x56]

fn be(data []u8, at int, size int) u32 {
	mut result := u32(0)
	for byte in data[at..at + size] { result = (result << 8) | byte }
	return result
}

pub fn capture_frames(path string) ![][]u8 {
	data := os.read_bytes(path)!
	if data.len < 24 { return [][]u8{} }
	little := data[..4] in [[u8(0xd4), 0xc3, 0xb2, 0xa1], [u8(0x4d), 0x3c, 0xb2, 0xa1]]
	mut frames := [][]u8{}
	mut at := u64(24)
	for at + 16 <= u64(data.len) {
		begin := int(at)
		included := if little {
			u32(data[begin + 8]) | (u32(data[begin + 9]) << 8) | (u32(data[begin + 10]) << 16) | (u32(data[begin + 11]) << 24)
		} else {
			be(data, begin + 8, 4)
		}
		end := at + 16 + u64(included)
		frames << data[begin + 16..if end > u64(data.len) { data.len } else { int(end) }].clone()
		at = end
	}
	return frames
}

pub fn close_pairs(values []u32, modulus u64, within u64) int {
	mut count := 0
	for index in 1 .. values.len {
		distance := (u64(values[index]) + modulus - u64(values[index - 1])) % modulus
		if distance > 0 && distance <= within { count++ }
	}
	return count
}

pub fn security_packets(frames [][]u8) []string {
	mut ids := []u32{}
	mut ports := []u32{}
	mut isns := []u32{}
	mut seen := map[u32]bool{}
	mut datagrams := []u32{}
	for frame in frames {
		if frame.len < 34 || frame[6..12] != guest_mac || frame[12..14] != [u8(8), 0] { continue }
		ip := frame[14..]
		ids << be(ip, 4, 2)
		header := int(ip[0] & 15) * 4
		if header > ip.len { continue }
		transport := ip[header..]
		if ip[16..20] != [u8(10), 0, 2, 2] || transport.len < 8 || be(transport, 2, 2) != 9 {
			continue
		}
		source := be(transport, 0, 2)
		if ip[9] == 6 && transport.len >= 14 && transport[13] & 18 == 2 {
			if source !in seen {
				seen[source] = true
				ports << source
				isns << be(transport, 4, 4)
			}
		} else if ip[9] == 17 {
			datagrams << source
		}
	}
	if ids.len < 16 { return ['the capture has only ' + ids.len.str() + ' packets from the guest'] }
	sequential := close_pairs(ids, 65536, 64)
	mut problems := []string{}
	threshold := if ids.len / 20 > 2 { ids.len / 20 } else { 2 }
	if sequential > threshold {
		problems << sequential.str() + ' of ' + (ids.len - 1).str() + ' IP IDs follow the one before'
	}
	if ports.len < 4 { problems << 'only ' + ports.len.str() + ' SYNs reached the capture' }
	mut near := 0
	for index in 1 .. isns.len {
		distance := (u64(isns[index]) + 4294967296 - u64(isns[index - 1])) % 4294967296
		reverse := (u64(isns[index - 1]) + 4294967296 - u64(isns[index])) % 4294967296
		if distance < 16777216 || reverse < 16777216 { near++ }
	}
	if near > 1 {
		problems << near.str() + ' of ' + (isns.len - 1).str() + ' initial sequence numbers are near the last'
	}
	for index, values in [ports, datagrams] {
		name := if index == 0 { 'TCP' } else { 'UDP' }
		if values.any(it < 49152) {
			problems << 'a ' + name + ' source port is outside the ephemeral range: ' + values.str()
		}
		if close_pairs(values, 65536, 1) > 2 {
			problems << name + ' source ports are handed out in sequence: ' + values.str()
		}
	}
	println('==> capture: ' + ids.len.str() + ' guest packets, ' + sequential.str() + ' IDs in sequence, ' + isns.len.str() + ' SYNs, ' + near.str() + ' close ISNs, ' + datagrams.len.str() + ' datagrams')
	return problems
}

pub fn ipv6_packets(frames [][]u8) []string {
	mut outgoing := map[u8]int{}
	mut incoming := map[u8]int{}
	mut protocols := map[u8]bool{}
	for frame in frames {
		if frame.len < 14 { continue }
		if frame[12..14] == [u8(0x86), 0xdd] && frame.len >= 54 {
			packet := frame[14..]
			mut kind := packet[6]
			mut at := 40
			if kind == 0 && packet.len >= 48 {
				kind = packet[40]
				at = 48
			}
			if kind == 58 && packet.len > at {
				if frame[6..12] == guest_mac {
					outgoing[packet[at]]++
				} else {
					incoming[packet[at]]++
				}
			}
			if frame[6..12] == guest_mac && kind in [u8(6), 17] { protocols[kind] = true }
		} else if frame.len >= 34 && frame[12..14] == [u8(8), 0] && frame[23] == 2 {
			outgoing[2]++
		}
	}
	println('==> IPv6 packet checks: outbound ICMPv6/IGMP=' + outgoing.str() + ', inbound ICMPv6=' + incoming.str() + ', protocols=' + protocols.keys().str())
	mut problems := []string{}
	for kind, name in {
		u8(133): 'router solicitation'
		135:     'neighbor solicitation'
		131:     'MLD report'
		2:       'IGMP report'
	} {
		if outgoing[kind] == 0 { problems << 'no outbound ' + name }
	}
	for kind, name in {
		u8(134): 'router advertisement'
		136:     'neighbor advertisement'
	} {
		if incoming[kind] == 0 { problems << 'no inbound ' + name }
	}
	if protocols.len != 2 { problems << 'missing physical IPv6 TCP or UDP' }
	return problems
}
