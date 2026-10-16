// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Frames on a descriptor.
module authproto

#include <unistd.h>
#include <errno.h>

fn read_exact(fd int, buffer voidptr, length int) ! {
	mut done := 0
	for done < length {
		got := C.read(fd, unsafe { &u8(buffer) + done }, usize(length - done))
		if got < 0 {
			if C.errno == C.EINTR {
				continue
			}
			return error('read failed')
		}
		if got == 0 {
			return error('connection closed')
		}
		done += int(got)
	}
}

pub fn read_frame(fd int) !Frame {
	mut header := []u8{len: header_bytes}
	defer { unsafe { header.free() } }
	read_exact(fd, header.data, header.len)!
	code, count := decode_header(header)!
	mut frame := Frame{
		code: code
		fields: [][]u8{cap: count}
	}
	unsafe { frame.fields.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { frame.close() } }
	mut prefix := []u8{len: 4}
	defer { unsafe { prefix.free() } }
	for _ in 0 .. count {
		read_exact(fd, prefix.data, prefix.len)!
		length := get_u32(prefix, 0)
		if length > u32(max_field) {
			return error('field too long')
		}
		mut field := []u8{len: int(length)}
		// The frame owns even a partially received field, so an interrupted
		// read wipes and retires it through the same failure cleanup.
		unsafe { frame.fields.push_many(&field, 1) }
		if length > 0 {
			read_exact(fd, field.data, field.len)!
		}
	}
	accepted = true
	return frame
}

pub fn write_frame(fd int, frame Frame) ! {
	mut data := encode(frame)!
	defer {
		wipe_bytes(data.data, data.len)
		unsafe { data.free() }
	}
	mut done := 0
	for done < data.len {
		put := C.write(fd, unsafe { &data[done] }, usize(data.len - done))
		if put < 0 {
			if C.errno == C.EINTR {
				continue
			}
			return error('write failed')
		}
		if put == 0 { return error('write failed') }
		done += int(put)
	}
}
