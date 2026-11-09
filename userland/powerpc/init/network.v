// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.netwire as wire

__global net_tx [1536]u8
__global net_rx [1536]u8
__global net_info [16]u8
__global net_clock [64]u8
__global net_peer [6]u8
__global net_ip u32
__global net_mask u32
__global net_gateway u32
__global net_lease u32
__global net_started u32
__global net_xid u32
__global net_sequence u32

fn seconds() u32 {
	if C.vinix_user_syscall(116, u32(unsafe { &net_clock[0] }), 0, 0) != 0 { return 0 }
	return wire.be32(unsafe { &net_clock[0] }, 0)
}

fn ip_text(ip u32) {
	for i := u32(0); i < 4; i++ {
		if i > 0 { print_text(c'.') }
		number((ip >> (24 - i * 8)) & 255)
	}
}

fn ethernet(kind u32, broadcast bool) {
	for i in 0 .. 1536 { net_tx[i] = 0 }
	for i in 0 .. 6 { net_tx[i] = if broadcast { u8(255) } else { net_peer[i] }; net_tx[i + 6] = net_info[i] }
	wire.put16(unsafe { &net_tx[0] }, 12, kind)
}

fn ip_header(protocol u8, source u32, destination u32, size u32) {
	data := unsafe { &net_tx[0] }
	net_tx[14] = 0x45
	wire.put16(data, 16, size + 20)
	wire.put16(data, 18, net_sequence)
	net_tx[22] = 64
	net_tx[23] = protocol
	wire.put32(data, 26, source)
	wire.put32(data, 30, destination)
	wire.put16(data, 24, wire.checksum(unsafe { &net_tx[14] }, 20, 0))
}

fn net_send(fd i32, size u32) bool {
	return C.vinix_user_syscall(4, u32(fd), u32(unsafe { &net_tx[0] }), size) == int(size)
}

fn dhcp_send(fd i32, kind u8, offered u32, server u32) bool {
	ethernet(0x0800, true)
	data := unsafe { &net_tx[0] }
	wire.put16(data, 34, 68)
	wire.put16(data, 36, 67)
	// BOOTP starts at Ethernet + IPv4 + UDP = 42.
	net_tx[42] = 1
	net_tx[43] = 1
	net_tx[44] = 6
	wire.put32(data, 46, net_xid)
	wire.put16(data, 52, 0x8000)
	for i in 0 .. 6 { net_tx[70 + i] = net_info[i] }
	wire.put32(data, 278, 0x63825363)
	net_tx[282] = 53; net_tx[283] = 1; net_tx[284] = kind
	net_tx[285] = 55; net_tx[286] = 3; net_tx[287] = 1; net_tx[288] = 3; net_tx[289] = 51
	mut at := u32(290)
	if kind == 3 {
		net_tx[at] = 50; net_tx[at + 1] = 4; wire.put32(data, at + 2, offered); at += 6
		net_tx[at] = 54; net_tx[at + 1] = 4; wire.put32(data, at + 2, server); at += 6
	}
	net_tx[at] = 255
	// BOOTP's traditional minimum is 300 bytes, padded with zero options.
	wire.put16(data, 38, 308)
	ip_header(17, 0, 0xffffffff, 308)
	return net_send(fd, 342)
}

fn dhcp_receive(fd i32, kind u8, server u32, address u32) wire.Dhcp {
	begin := seconds()
	for seconds() - begin < 3 {
		count := C.vinix_user_syscall(3, u32(fd), u32(unsafe { &net_rx[0] }), 1536)
		if count < 0 && count != -11 && count != -90 { break }
		if count <= 0 { continue }
		reply := wire.dhcp(unsafe { &net_rx[0] }, u32(count), net_xid, unsafe { &net_info[0] })
		if reply.valid && reply.kind == kind && (server == 0 || reply.server == server)
			&& (address == 0 || reply.address == address) { return reply }
	}
	return wire.Dhcp{}
}

fn configure_network(fd i32) bool {
	if C.vinix_user_syscall(54, u32(fd), 0x564e0001, u32(unsafe { &net_info[0] })) != 0 {
		print_text(c'net: device information unavailable\n'); return false
	}
	if wire.be32(unsafe { &net_info[0] }, 8) == 0 { print_text(c'net: link down\n'); return false }
	if net_ip != 0 && seconds() - net_started < net_lease { return true }
	net_ip = 0
	net_xid = 0x56494e58 ^ wire.be32(unsafe { &net_info[0] }, 2) ^ seconds()
	for _ in 0 .. 3 {
		if !dhcp_send(fd, 1, 0, 0) { break }
		offer := dhcp_receive(fd, 2, 0, 0)
		if !offer.valid { continue }
		if !dhcp_send(fd, 3, offer.address, offer.server) { break }
		ack := dhcp_receive(fd, 5, offer.server, offer.address)
		if !ack.valid { continue }
		net_ip = ack.address
		net_mask = ack.mask
		net_gateway = ack.router
		net_lease = ack.lease
		net_started = seconds()
		print_text(c'DHCP: '); ip_text(net_ip)
		print_text(c' gateway '); ip_text(net_gateway); print_text(c'\n')
		return true
	}
	print_text(c'net: DHCP timed out\n')
	return false
}

fn arp_send(fd i32, target u32, reply bool) bool {
	ethernet(0x0806, !reply)
	data := unsafe { &net_tx[0] }
	wire.put16(data, 14, 1); wire.put16(data, 16, 0x0800)
	net_tx[18] = 6; net_tx[19] = 4
	wire.put16(data, 20, if reply { u32(2) } else { u32(1) })
	for i in 0 .. 6 { net_tx[22 + i] = net_info[i]; if reply { net_tx[32 + i] = net_peer[i] } }
	wire.put32(data, 28, net_ip); wire.put32(data, 38, target)
	return net_send(fd, 42)
}

fn arp_valid(count int) bool {
	data := unsafe { &net_rx[0] }
	return count >= 42 && wire.be16(data, 12) == 0x0806 && wire.be16(data, 14) == 1
		&& wire.be16(data, 16) == 0x0800 && net_rx[18] == 6 && net_rx[19] == 4
}

fn resolve(fd i32, target u32) bool {
	data := unsafe { &net_rx[0] }
	for _ in 0 .. 3 {
		if !arp_send(fd, target, false) { return false }
		begin := seconds()
		for seconds() - begin < 2 {
			count := C.vinix_user_syscall(3, u32(fd), u32(data), 1536)
			if !arp_valid(count) || wire.be16(data, 20) != 2 || wire.be32(data, 28) != target
				|| wire.be32(data, 38) != net_ip || net_rx[22] & 1 != 0 { continue }
			mut matched := true
			for i in 0 .. 6 { if net_rx[32 + i] != net_info[i] || net_rx[6 + i] != net_rx[22 + i] { matched = false } }
			if !matched { continue }
			for i in 0 .. 6 { net_peer[i] = net_rx[22 + i] }
			return true
		}
	}
	return false
}

fn echo_reply(fd i32, target u32) bool {
	data := unsafe { &net_rx[0] }
	begin := seconds()
	for seconds() - begin < 3 {
		count := C.vinix_user_syscall(3, u32(fd), u32(data), 1536)
		if count <= 0 { continue }
		if arp_valid(count) && wire.be16(data, 20) == 1 && wire.be32(data, 38) == net_ip {
			for i in 0 .. 6 { net_peer[i] = net_rx[22 + i] }
			arp_send(fd, wire.be32(data, 28), true)
			continue
		}
		ip := wire.ipv4(data, u32(count))
		if !ip.valid || ip.protocol != 1 || ip.source != target || ip.destination != net_ip || ip.length - ip.header != 40 { continue }
		at := 14 + ip.header
		if net_rx[at] != 0 || net_rx[at + 1] != 0 || wire.be16(data, at + 4) != 0x5649
			|| wire.be16(data, at + 6) != (net_sequence & 0xffff)
			|| wire.checksum(unsafe { &data[at] }, 40, 0) != 0 { continue }
		mut matched := true
		for i := u32(0); i < 32; i++ { if net_rx[at + 8 + i] != u8(i ^ net_sequence) { matched = false } }
		if matched { return true }
	}
	return false
}

fn ping_address(text &char) u32 {
	mut result := u32(0)
	mut at := u32(0)
	unsafe {
		for part in 0 .. 4 {
			mut value := u32(0)
			mut digits := 0
			for text[at] >= `0` && text[at] <= `9` {
				value = value * 10 + u32(u8(text[at]) - u8(48)); at++; digits++
				if digits > 3 || value > 255 { return 0 }
			}
			if digits == 0 || (part < 3 && u8(text[at]) != 46) || (part == 3 && text[at] != 0) { return 0 }
			result = result << 8 | value
			if part < 3 { at++ }
		}
	}
	return if result >> 24 >= 224 { u32(0) } else { result }
}

fn network_command(argument &char, ping bool) {
	fd := C.vinix_user_syscall(5, u32(c'/dev/net0'), 2, 0)
	if fd < 0 { print_text(c'net: Ethernet device unavailable\n'); return }
	defer { close(fd) }
	// Exercise the packet device's user boundary before sending any traffic.
	if C.vinix_user_syscall(3, u32(fd), 0x40000000, 64) != -14
		|| C.vinix_user_syscall(4, u32(fd), 0x02000000, 64) != -14
		|| C.vinix_user_syscall(4, u32(fd), u32(unsafe { &net_tx[0] }), 1515) != -90
		|| C.vinix_user_syscall(54, u32(fd), 0x564e0001, 0x40000000) != -14
		|| C.vinix_user_syscall(54, u32(fd), 0, 0) != -25
		|| C.vinix_user_syscall(141, u32(fd), u32(unsafe { &net_rx[0] }), 1536) != -20 { failed_check() }
	if !configure_network(fd) { return }
	if !ping {
		print_text(c'net0: '); ip_text(net_ip); print_text(c' mask '); ip_text(net_mask); print_text(c'\n')
		return
	}
	target := if unsafe { argument[0] == 0 } { net_gateway } else { ping_address(argument) }
	if target == 0 { print_text(c'ping: expected an IPv4 address\n'); return }
	next := if target & net_mask == net_ip & net_mask { target } else { net_gateway }
	if next == 0 { print_text(c'ping: no route\n'); return }
	mut replies := u32(0)
	for _ in 0 .. 4 {
		if !resolve(fd, next) { break }
		ethernet(0x0800, false)
		net_sequence++
		ip_header(1, net_ip, target, 40)
		net_tx[34] = 8
		wire.put16(unsafe { &net_tx[0] }, 38, 0x5649)
		wire.put16(unsafe { &net_tx[0] }, 40, net_sequence)
		for i := u32(0); i < 32; i++ { net_tx[42 + i] = u8(i ^ net_sequence) }
		wire.put16(unsafe { &net_tx[0] }, 36, wire.checksum(unsafe { &net_tx[34] }, 40, 0))
		if net_send(fd, 74) && echo_reply(fd, target) { replies++ }
	}
	print_text(c'ping: '); number(replies); print_text(c'/4 replies from '); ip_text(target); print_text(c'\n')
}
