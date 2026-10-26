// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.windowfb

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

fn C.fpathconf(int, int) i64

const input_magic = u32(0x31494e56)
const input_header = 24
const input_limit = 16

struct InputRecord {
mut:
	header       [input_header]u8
	payload      [windowfb.max_payload]u8
	length       int
	header_sent  bool
	payload_sent int
}

struct InputQueue {
mut:
	records [input_limit]InputRecord
	// Reuse the receive buffer: V can heap-box an address-taken local even
	// with -manualfree. Keeping it with the queue avoids per-event objects.
	event windowfb.Message
	head  int
	count int
}

fn prepare_input(fd int) ! {
	mut info := C.stat{}
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || flags & C.O_ACCMODE != C.O_WRONLY || C.fstat(fd, &info) != 0
		|| u32(info.st_mode) & C.S_IFMT != C.S_IFIFO
		|| C.fpathconf(fd, C._PC_PIPE_BUF) < input_header {
		return error('account UI input requires an atomic header pipe writer')
	}
	protect_fd(fd, true)!
}

fn (q &InputQueue) pending() bool { return q.count > 0 }

fn (mut q InputQueue) enqueue(m &windowfb.Message, width int, height int) ! {
	kind := match m.kind {
		.motion { u32(1) }
		.button_down { u32(2) }
		.button_up { u32(3) }
		.keys { u32(4) }
		.wheel { u32(5) }
		else { return }
	}
	if m.length < 0 || m.length > windowfb.max_payload || (kind != 4 && m.length != 0) {
		return error('invalid account UI input payload')
	}
	if kind == 4 && m.length == 0 { return }
	if q.count == input_limit { return error('account UI input queue is full') }
	i := (q.head + q.count) % input_limit
	mut r := unsafe { &q.records[i] }
	r.length = m.length
	r.header_sent = false
	r.payload_sent = 0
	windowfb.put_u32(&r.header[0], 0, input_magic)
	windowfb.put_u32(&r.header[0], 4, kind)
	windowfb.put_u32(&r.header[0], 8, u32(if m.x < 0 {
		0
	} else if m.x >= width {
		width - 1
	} else {
		int(m.x)
	}))
	windowfb.put_u32(&r.header[0], 12, u32(if m.y < 0 {
		0
	} else if m.y >= height {
		height - 1
	} else {
		int(m.y)
	}))
	windowfb.put_u32(&r.header[0], 16, u32(m.value))
	windowfb.put_u32(&r.header[0], 20, u32(m.length))
	unsafe { C.memcpy(&r.payload[0], &m.payload[0], usize(m.length)) }
	q.count++
}

// Nativews reads its fixed header in one read, then its optional key payload.
// The 24-byte pipe header is atomic. Its key payload may be delivered in
// several writes; nativews collects it in a loop. Keep both phases ordered
// and retry EAGAIN without sending a later event ahead of the blocked one.
fn write_atomic(fd int, bytes &u8, length int) !bool {
	for {
		n := C.write(fd, bytes, usize(length))
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK]! { return false }
		if n != length { return error('account UI input pipe disconnected or short write') }
		return true
	}
	return false
}

fn (mut q InputQueue) flush(fd int) ! {
	for q.count > 0 {
		mut r := unsafe { &q.records[q.head] }
		if !r.header_sent {
			if !write_atomic(fd, &r.header[0], input_header)! { return }
			r.header_sent = true
		}
		for r.payload_sent < r.length {
			n := unsafe { C.write(fd, &r.payload[r.payload_sent], usize(r.length - r.payload_sent)) }
			if n < 0 && C.errno == C.EINTR { continue }
			if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK]! { return }
			if n <= 0 { return error('account UI key pipe disconnected') }
			r.payload_sent += int(n)
		}
		// Do not retain typed credentials beyond delivery, including unused
		// payload space from a previous longer event in this ring slot.
		unsafe { C.memset(&r.payload[0], 0, usize(windowfb.max_payload)) }
		r.length = 0
		q.head = (q.head + 1) % input_limit
		q.count--
	}
}
