// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct Pipe {
mut:
	readers u32
	writers u32
	head u32
	size u32
	data [65536]u8
}

__global pipes [16]Pipe

fn sys_pipe(address u32, flags u32) int {
	if flags & ~u32(0x80800) != 0 { return -22 }
	if !user_space.accessible(address, 8, true) { return -14 }
	mut pair := [2]u32{}
	mut found := 0
	for fd in 0 .. 64 {
		if !descriptors[fd].used { pair[found] = u32(fd); found++; if found == 2 { break } }
	}
	if found != 2 { return -24 }
	for i in 0 .. 16 {
		if pipes[i].readers != 0 || pipes[i].writers != 0 { continue }
		pipes[i].head = 0; pipes[i].size = 0
		if !install_fd(int(pair[0]), Descriptor{used: true, file: -9, pipe: i + 1, flags: flags}) { return -24 }
		pipes[i].readers = 1
		if !install_fd(int(pair[1]), Descriptor{used: true, writable: true, file: -9, pipe: i + 1, flags: flags | 1}) {
			sys_close(pair[0]); return -24
		}
		pipes[i].writers = 1
		copy_to_user(address, unsafe { &u8(&pair[0]) }, 8)
		return 0
	}
	return -23
}

fn close_pipe(d &Descriptor) {
	mut p := unsafe { &pipes[d.pipe - 1] }
	if d.writable { p.writers-- } else { p.readers-- }
}

fn pipe_read(fd u32, address u32, count u32) int {
	d := descriptors[fd]
	if d.writable { return -9 }
	if !user_space.accessible(address, count, true) { return -14 }
	if count == 0 { return 0 }
	mut p := unsafe { &pipes[d.pipe - 1] }
	if p.size == 0 {
		if p.writers == 0 { return 0 }
		return if d.flags & 0x800 != 0 { -11 } else { restart_call }
	}
	size := if count < p.size { count } else { p.size }
	for i := u32(0); i < size; i++ { io_buffer[i] = p.data[(p.head + i) & 65535] }
	if !copy_to_user(address, unsafe { &io_buffer[0] }, size) { return -14 }
	p.head = (p.head + size) & 65535; p.size -= size
	return int(size)
}

fn pipe_write(fd u32, address u32, requested u32) int {
	d := descriptors[fd]
	if !d.writable { return -9 }
	count := if requested > 4096 { u32(4096) } else { requested }
	if !user_space.accessible(address, count, false) { return -14 }
	if count == 0 { return 0 }
	mut p := unsafe { &pipes[d.pipe - 1] }
	if p.readers == 0 { return -32 }
	// Preserve PIPE_BUF atomicity, even for nonblocking writers.
	if 65536 - p.size < count { return if d.flags & 0x800 != 0 { -11 } else { restart_call } }
	if !copy_from_user(unsafe { &io_buffer[0] }, address, count) { return -14 }
	for i := u32(0); i < count; i++ { p.data[(p.head + p.size + i) & 65535] = io_buffer[i] }
	p.size += count
	return int(count)
}

fn pipe_events(d &Descriptor) u16 {
	p := unsafe { &pipes[d.pipe - 1] }
	if d.writable { return if p.readers == 0 { u16(8) } else if p.size <= 65536 - 4096 { u16(0x104) } else { u16(0) } }
	return (if p.size > 0 { u16(0x41) } else { u16(0) }) | if p.writers == 0 { u16(0x10) } else { u16(0) }
}
