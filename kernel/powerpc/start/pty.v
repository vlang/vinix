// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.runtime

struct PtyQueue {
mut:
	head u32
	size u32
	data [8192]u8
}

struct Pty {
mut:
	masters u32
	slaves u32
	locked bool
	ever_opened bool
	input PtyQueue
	output PtyQueue
	winsize [8]u8
	termios [44]u8
}

__global ptys [4]Pty

fn pty_open(length int, flags u32) int {
	master := path_equal(c'/dev/ptmx', length)
	mut index := -1
	if !master {
		if length != 10 || io_buffer[9] < `0` || io_buffer[9] > `3` { return -2 }
		for i in 0 .. 9 { if io_buffer[i] != unsafe { u8(c'/dev/pts/'[i]) } { return -2 } }
		index = int(io_buffer[9] - `0`)
	}
	if flags & 3 != 2 { return -13 }
	mut fd := -1
	for i in 3 .. 64 { if !descriptors[i].used { fd = i; break } }
	if fd < 0 { return -24 }
	if master {
		for i in 0 .. 4 { if ptys[i].masters == 0 && ptys[i].slaves == 0 { index = i; break } }
		if index < 0 { return -28 }
		ptys[index] = Pty{locked: true}
		ptys[index].termios[7] = 3 // PPC OPOST | ONLCR, raw input
	} else if ptys[index].masters == 0 { return -2 }
	else if ptys[index].locked { return -5 }
	if !install_fd(fd, Descriptor{used: true, writable: true, file: if master { -10 } else { -11 }, pty: index + 1, flags: flags}) { return -24 }
	if master { ptys[index].masters++ } else { ptys[index].slaves++; ptys[index].ever_opened = true }
	return fd
}

fn pty_close(d &Descriptor) {
	if d.file == -10 { ptys[d.pty - 1].masters-- } else { ptys[d.pty - 1].slaves-- }
}

fn pty_read(fd u32, address u32, requested u32) int {
	d := descriptors[fd]
	mut p := unsafe { &ptys[d.pty - 1] }
	mut queue := if d.file == -10 { unsafe { &p.output } } else { unsafe { &p.input } }
	count := if requested < 4096 { requested } else { u32(4096) }
	if !user_space.accessible(address, count, true) { return -14 }
	if count == 0 { return 0 }
	if queue.size == 0 {
		if d.file == -10 && p.slaves == 0 && p.ever_opened { return -5 }
		if d.file == -11 && p.masters == 0 { return 0 }
		return if d.flags & 0x800 != 0 { -11 } else { restart_call }
	}
	size := if count < queue.size { count } else { queue.size }
	for i := u32(0); i < size; i++ { io_buffer[i] = queue.data[(queue.head + i) & 8191] }
	if !copy_to_user(address, unsafe { &io_buffer[0] }, size) { return -14 }
	queue.head = (queue.head + size) & 8191; queue.size -= size
	return int(size)
}

fn pty_write(fd u32, address u32, requested u32) int {
	d := descriptors[fd]
	mut p := unsafe { &ptys[d.pty - 1] }
	mut queue := if d.file == -10 { unsafe { &p.input } } else { unsafe { &p.output } }
	count := if requested < 4096 { requested } else { u32(4096) }
	if !user_space.accessible(address, count, false) { return -14 }
	if count == 0 { return 0 }
	if (d.file == -10 && p.slaves == 0) || (d.file == -11 && p.masters == 0) { return -5 }
	if queue.size == 8192 { return if d.flags & 0x800 != 0 { -11 } else { restart_call } }
	if !copy_from_user(unsafe { &io_buffer[0] }, address, count) { return -14 }
	mut consumed := u32(0)
	for consumed < count {
		byte := io_buffer[consumed]
		newline := d.file == -11 && p.termios[7] & 3 == 3 && byte == `\n`
		needed := if newline { u32(2) } else { u32(1) }
		if 8192 - queue.size < needed { break }
		if newline { queue.data[(queue.head + queue.size) & 8191] = `\r`; queue.size++ }
		queue.data[(queue.head + queue.size) & 8191] = byte
		queue.size++; consumed++
	}
	return if consumed != 0 { int(consumed) } else if d.flags & 0x800 != 0 { -11 } else { restart_call }
}

fn pty_events(d &Descriptor) u16 {
	p := unsafe { &ptys[d.pty - 1] }
	input := if d.file == -10 { unsafe { &p.output } } else { unsafe { &p.input } }
	output := if d.file == -10 { unsafe { &p.input } } else { unsafe { &p.output } }
	mut mask := if input.size > 0 { u16(0x41) } else { u16(0) }
	if output.size < 8192 { mask |= 0x104 }
	if (d.file == -10 && p.slaves == 0 && p.ever_opened) || (d.file == -11 && p.masters == 0) { mask |= 0x10 }
	return mask
}

fn pty_ioctl(fd u32, request u32, address u32) int {
	d := descriptors[fd]
	mut p := unsafe { &ptys[d.pty - 1] }
	match request {
		0x40045430 { // TIOCGPTN
			buffer_word(0, u32(d.pty - 1))
			return if copy_to_user(address, unsafe { &io_buffer[0] }, 4) { 0 } else { -14 }
		}
		0x80045431 {
			mut locked_word := u32(0)
			if d.file != -10 { return -25 }
			if !copy_from_user(unsafe { &u8(&locked_word) }, address, 4) { return -14 }
			p.locked = locked_word != 0
			return 0
		}
		0x80087467 { return if copy_from_user(unsafe { &p.winsize[0] }, address, 8) { 0 } else { -14 } }
		0x40087468 { return if copy_to_user(address, unsafe { &p.winsize[0] }, 8) { 0 } else { -14 } }
		0x402c7413 { return if copy_to_user(address, unsafe { &p.termios[0] }, 44) { 0 } else { -14 } }
		0x802c7414, 0x802c7415, 0x802c7416 {
			if !copy_from_user(unsafe { &io_buffer[0] }, address, 44) { return -14 }
			// This initial PTY serves the native shell, which edits and echoes
			// its input. Refuse unsupported canonical/echo/signal processing.
			if io_buffer[0] != 0 || io_buffer[1] != 0 || io_buffer[2] != 0 || io_buffer[3] != 0
				|| io_buffer[4] != 0 || io_buffer[5] != 0 || io_buffer[6] != 0 || io_buffer[7] & ~u8(3) != 0
				|| io_buffer[12] != 0 || io_buffer[13] != 0 || io_buffer[14] != 0 || io_buffer[15] != 0 { return -95 }
			runtime.copy(unsafe { &p.termios[0] }, unsafe { &io_buffer[0] }, 44)
			return 0
		}
		0x540e { return if d.file == -11 { 0 } else { -25 } }
		else { return -25 }
	}
}
