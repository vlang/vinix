// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Every operation is observable. No C macros or test-only production paths.
struct MockDevice {
mut:
	path               string = backlight_path
	reply              []u8
	position           int
	stream             bool
	chunk              int = 256
	open_error         DeviceError
	rw_error           DeviceError
	read_error         DeviceError
	write_error        DeviceError
	close_error        DeviceError
	stat_error         DeviceError
	character          bool = true
	interrupted_opens  int
	interrupted_reads  int
	interrupted_writes int
	short_write        bool
	opens              int
	closes             int
	reads              int
	writes             int
	stats              int
	live               bool
	write_open         bool
	written            []u8
}

fn (mut m MockDevice) open(path string, writable bool) (int, DeviceError) {
	assert path == m.path
	assert !m.live
	m.opens++
	if m.interrupted_opens > 0 {
		m.interrupted_opens--
		return -1, DeviceError.interrupted
	}
	if m.open_error != .none {
		return -1, m.open_error
	}
	if writable && m.rw_error != .none {
		return -1, m.rw_error
	}
	m.live = true
	m.write_open = writable
	m.position = 0
	return 42, DeviceError.none
}

fn (mut m MockDevice) read(fd int, mut buffer []u8) (int, DeviceError) {
	assert fd == 42 && m.live
	m.reads++
	if m.interrupted_reads > 0 {
		m.interrupted_reads--
		return -1, DeviceError.interrupted
	}
	if m.read_error != .none {
		return -1, m.read_error
	}
	start := if m.stream { m.position } else { 0 }
	mut n := m.reply.len - start
	if n > buffer.len {
		n = buffer.len
	}
	if n > m.chunk {
		n = m.chunk
	}
	for i in 0 .. n {
		buffer[i] = m.reply[start + i]
	}
	m.position += n
	return n, DeviceError.none
}

fn (mut m MockDevice) write(fd int, buffer []u8) (int, DeviceError) {
	assert fd == 42 && m.live && m.write_open
	m.writes++
	if m.interrupted_writes > 0 {
		m.interrupted_writes--
		return -1, DeviceError.interrupted
	}
	if m.write_error != .none {
		return -1, m.write_error
	}
	m.written = buffer.clone()
	return buffer.len - if m.short_write { 1 } else { 0 }, DeviceError.none
}

fn (mut m MockDevice) close(fd int) DeviceError {
	assert fd == 42 && m.live
	m.live = false
	m.closes++
	return m.close_error
}

fn (mut m MockDevice) is_character(fd int) (bool, DeviceError) {
	assert fd == 42 && m.live
	m.stats++
	return m.character, m.stat_error
}

const valid_backlight = 'requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\nonline=1\n'

fn mock_backlight() MockDevice {
	return MockDevice{ reply: valid_backlight.bytes() }
}
