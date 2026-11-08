// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn pcap_word(data []u8, at int) u32 {
	return u32(data[at]) | u32(data[at + 1]) << 8 | u32(data[at + 2]) << 16 | u32(data[at + 3]) << 24
}

fn validate_packets(data []u8) ! {
	if data.len < 24 || pcap_word(data, 0) != 0xa1b2c3d4 || pcap_word(data, 20) != 1 {
		return error('Expected little-endian Ethernet pcap')
	}
	mut requests := map[u32][]u8{}
	mut replies := map[u32][]u8{}
	mut dhcp_tx := 0
	mut dhcp_rx := 0
	mut arp_tx := 0
	mut arp_rx := 0
	mut at := 24
	for at < data.len {
		if data.len - at < 16 { return error('Truncated pcap record') }
		size := pcap_word(data, at + 8)
		if size != pcap_word(data, at + 12) || size > u32(data.len - at - 16) { return error('Truncated packet') }
		at += 16
		packet := data[at..at + int(size)]
		at += int(size)
		if size >= 42 && packet[12] == 8 && packet[13] == 6 {
			if packet[20] == 0 && packet[21] == 1 { arp_tx++ }
			if packet[20] == 0 && packet[21] == 2 { arp_rx++ }
		}
		if size < 34 || packet[12] != 8 || packet[13] != 0 || packet[14] >> 4 != 4 { continue }
		header := int(packet[14] & 15) * 4
		length := int(packet[16]) * 256 + int(packet[17])
		if header < 20 || length < header + 8 || length > int(size) - 14 { return error('Invalid captured IPv4 packet') }
		payload := 14 + header
		if packet[23] == 17 {
			if packet[payload] == 0 && packet[payload + 1] == 68 && packet[payload + 3] == 67 { dhcp_tx++ }
			if packet[payload] == 0 && packet[payload + 1] == 67 && packet[payload + 3] == 68 { dhcp_rx++ }
		}
		if packet[23] != 1 || length - header != 40 || packet[payload + 4] != 0x56 || packet[payload + 5] != 0x49 { continue }
		sequence := u32(packet[payload + 6]) << 8 | packet[payload + 7]
		if packet[payload] == 8 { requests[sequence] = packet[payload + 8..payload + 40].clone() }
		if packet[payload] == 0 { replies[sequence] = packet[payload + 8..payload + 40].clone() }
	}
	if requests.len != 68 || replies.len != 68 || dhcp_tx < 2 || dhcp_rx < 2 || arp_tx < 68 || arp_rx < 68 {
		return error('Incomplete Ethernet evidence: echo ${requests.len}/${replies.len}, DHCP ${dhcp_tx}/${dhcp_rx}, ARP ${arp_tx}/${arp_rx}')
	}
	for sequence, payload in requests {
		if replies[sequence] != payload { return error('Captured ICMP payload mismatch for sequence ${sequence}') }
	}
	println('PASS independent Ethernet capture: DHCP, ARP, 68 matching ICMP request/reply pairs')
}
