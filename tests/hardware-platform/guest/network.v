// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Whether the machine's network card works, asked of something that needs
// nothing outside QEMU: its built-in TFTP server, which serves the file the
// controller put in the scenario's state directory. One read request out and
// one data block back is a frame transmitted and a frame received, each
// through the card's descriptor rings and buffers -- which is the point when
// what is being tested is who may reach that memory.
module main

#include <sys/socket.h>
#include <poll.h>

fn C.socket(domain int, kind int, protocol int) int
fn C.sendto(fd int, data voidptr, length usize, flags int, address voidptr, address_length u32) isize
fn C.recvfrom(fd int, data voidptr, length usize, flags int, address voidptr, address_length voidptr) isize
fn C.poll(fds voidptr, count u64, timeout int) int

const af_inet = 2
const sock_dgram = 2
const pollin = i16(1)

// What the controller's probe file holds, and what it is called.
const tftp_file = 'hwtest-probe'
const tftp_text = 'hwtest-okay'

struct PollFd {
mut:
	// As C lays struct pollfd out: `int` here is wider than C's.
	fd      i32
	events  i16
	revents i16
}

// Sends `request` to 10.0.2.2:`port` over UDP and waits up to a second for an
// answer. The answer's length, or -1.
fn udp_exchange(port u16, request []u8, mut reply []u8) int {
	fd := C.socket(af_inet, sock_dgram, 0)
	if fd < 0 {
		return -1
	}
	defer {
		C.close(fd)
	}
	// struct sockaddr_in: family, port and address in network order, padding.
	address := [u8(af_inet), 0, u8(port >> 8), u8(port), 10, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0]!
	if C.sendto(fd, request.data, usize(request.len), 0, voidptr(&address[0]), 16) < 0 {
		return -1
	}
	mut waiting := PollFd{
		fd:     i32(fd)
		events: pollin
	}
	if C.poll(voidptr(&waiting), 1, 1000) <= 0 {
		return -1
	}
	return int(C.recvfrom(fd, reply.data, usize(reply.len), 0, unsafe { nil }, unsafe { nil }))
}

// One TFTP read request for the probe file, answered with its first block.
fn tftp_answers() bool {
	mut request := [u8(0), 1]
	request << tftp_file.bytes()
	request << 0
	request << 'octet'.bytes()
	request << 0
	mut reply := []u8{len: 600}
	count := udp_exchange(69, request, mut reply)
	// Opcode 3 is data, block 1, then the file.
	return count >= 4 + tftp_text.len && reply[1] == 3 && reply[3] == 1
		&& reply[4..4 + tftp_text.len].bytestr() == tftp_text
}

// Whether the network works, allowing it `seconds` to come up: the kernel
// asks for its address when the card is bound.
fn network_works(seconds int) bool {
	for _ in 0 .. seconds * 2 {
		if tftp_answers() {
			return true
		}
		sleep_ms(500)
	}
	return false
}
