// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Frames on a descriptor.
module authproto

#include <unistd.h>
#include <errno.h>

fn read_exact(fd int, mut buffer []u8) ! {
	mut done := 0
	for done < buffer.len {
		got := C.read(fd, unsafe { &buffer[done] }, usize(buffer.len - done))
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
	read_exact(fd, mut header)!
	code, count := decode_header(header)!
	mut frame := Frame{
		code: code
	}
	for _ in 0 .. count {
		mut prefix := []u8{len: 4}
		read_exact(fd, mut prefix)!
		length := get_u32(prefix, 0)
		if length > u32(max_field) {
			frame.wipe()
			return error('field too long')
		}
		mut field := []u8{len: int(length)}
		if length > 0 {
			read_exact(fd, mut field) or {
				frame.wipe()
				return err
			}
		}
		frame.fields << field
	}
	return frame
}

pub fn write_frame(fd int, frame Frame) ! {
	mut data := encode(frame)!
	defer {
		for i in 0 .. data.len {
			data[i] = 0
		}
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
		done += int(put)
	}
}
