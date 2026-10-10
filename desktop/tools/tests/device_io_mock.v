// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

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
	ioctl_error        DeviceError
	close_error        DeviceError
	stat_error         DeviceError
	character          bool = true
	// What the file's mode says about writing it.
	mode_writable      bool = true
	interrupted_opens  int
	interrupted_reads  int
	interrupted_writes int
	interrupted_ioctls int
	short_write        bool
	opens              int
	closes             int
	reads              int
	writes             int
	ioctls             int
	stats              int
	lists              int
	live               bool
	write_open         bool
	written            []u8
	ioctl_written      []u8
	ioctl_request      u64
	wifi_status_reply  []u8
	wifi_network_reply []u8
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

fn (mut m MockDevice) ioctl(fd int, request u64, mut buffer []u8) DeviceError {
	assert fd == 42 && m.live
	m.ioctls++
	m.ioctl_request = request
	if m.interrupted_ioctls > 0 {
		m.interrupted_ioctls--
		return .interrupted
	}
	if m.ioctl_error != .none {
		return m.ioctl_error
	}
	if request == wifi_ioctl_status || request == wifi_ioctl_networks {
		reply := if request == wifi_ioctl_status {
			m.wifi_status_reply
		} else {
			m.wifi_network_reply
		}
		if reply.len != buffer.len {
			return .io
		}
		for i, byte in reply {
			buffer[i] = byte
		}
	} else {
		m.ioctl_written = buffer.clone()
	}
	return .none
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

fn (mut m MockDevice) is_writable(fd int) (bool, DeviceError) {
	assert fd == 42 && m.live
	m.stats++
	return m.mode_writable, m.stat_error
}

// One device has no directory beside it: there is nothing in /sys to list.
fn (mut m MockDevice) list(path string, mut names DeviceNames) DeviceError {
	assert path.len > 0
	m.lists++
	names.count = 0
	return .unavailable
}

const valid_backlight = 'requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\nonline=1\n'

fn mock_backlight() MockDevice {
	return MockDevice{ reply: valid_backlight.bytes() }
}

// A few files by path, for the clients that read /sys. One descriptor is open
// at a time, so a client that leaks one, or closes one twice, fails here.
struct MockNode {
mut:
	path        string
	text        string
	// What the file's mode says; a write can be refused all the same.
	writable    bool = true
	// A device ends at the end of its text. A file of /sys does not: it
	// makes the whole text afresh for every read.
	stream      bool
	position    int
	open_error  DeviceError
	read_error  DeviceError
	write_error DeviceError
	close_error DeviceError
	written     []string
	reads       int
}

struct MockTree {
mut:
	// The directory list() answers for, and what it lists.
	directory          string
	entries            []string
	list_error         DeviceError
	nodes              []MockNode
	interrupted_opens  int
	interrupted_reads  int
	interrupted_writes int
	short_write        bool
	opens              int
	closes             int
	reads              int
	writes             int
	lists              int
	stats              int
	live               int = -1
	write_open         bool
	// Every write in order, as `path=text`.
	log                []string
	// Called after a write is taken, to change what the other files say the
	// way the kernel does.
	on_write           fn (mut tree MockTree, path string, text string) = unsafe { nil }
}

fn (t &MockTree) index(path string) int {
	for i, node in t.nodes {
		if node.path == path {
			return i
		}
	}
	return -1
}

// put makes a file, or replaces what an existing one says.
fn (mut t MockTree) put(path string, text string) {
	index := t.index(path)
	if index >= 0 {
		t.nodes[index].text = text
		return
	}
	t.nodes << MockNode{
		path: path
		text: text
	}
}

fn (mut t MockTree) remove(path string) {
	index := t.index(path)
	if index >= 0 {
		t.nodes.delete(index)
	}
}

fn (mut t MockTree) node(path string) &MockNode {
	index := t.index(path)
	assert index >= 0, 'no mock file ${path}'
	return &t.nodes[index]
}

fn (mut t MockTree) open(path string, writable bool) (int, DeviceError) {
	assert t.live < 0, 'opened ${path} with a descriptor still open'
	t.opens++
	if t.interrupted_opens > 0 {
		t.interrupted_opens--
		return -1, DeviceError.interrupted
	}
	index := t.index(path)
	if index < 0 {
		return -1, DeviceError.unavailable
	}
	if t.nodes[index].open_error != .none {
		return -1, t.nodes[index].open_error
	}
	t.live = index
	t.write_open = writable
	t.nodes[index].position = 0
	return 100 + index, DeviceError.none
}

fn (mut t MockTree) read(fd int, mut buffer []u8) (int, DeviceError) {
	assert t.live >= 0 && fd == 100 + t.live
	t.reads++
	if t.interrupted_reads > 0 {
		t.interrupted_reads--
		return -1, DeviceError.interrupted
	}
	t.nodes[t.live].reads++
	if t.nodes[t.live].read_error != .none {
		return -1, t.nodes[t.live].read_error
	}
	text := t.nodes[t.live].text
	start := if t.nodes[t.live].stream { t.nodes[t.live].position } else { 0 }
	mut n := text.len - start
	if n > buffer.len {
		n = buffer.len
	}
	for i in 0 .. n {
		buffer[i] = text[start + i]
	}
	t.nodes[t.live].position += n
	return n, DeviceError.none
}

fn (mut t MockTree) write(fd int, buffer []u8) (int, DeviceError) {
	assert t.live >= 0 && fd == 100 + t.live && t.write_open
	t.writes++
	if t.interrupted_writes > 0 {
		t.interrupted_writes--
		return -1, DeviceError.interrupted
	}
	if t.nodes[t.live].write_error != .none {
		return -1, t.nodes[t.live].write_error
	}
	text := buffer.bytestr()
	t.nodes[t.live].written << text
	t.log << '${t.nodes[t.live].path}=${text}'
	if t.on_write != unsafe { nil } {
		t.on_write(mut t, t.nodes[t.live].path, text)
	}
	return buffer.len - if t.short_write { 1 } else { 0 }, DeviceError.none
}

// Nothing read from /sys here takes an ioctl.
fn (mut t MockTree) ioctl(fd int, request u64, mut buffer []u8) DeviceError {
	assert false, 'ioctl ${request} on descriptor ${fd} with ${buffer.len} bytes'
	return .io
}

fn (mut t MockTree) close(fd int) DeviceError {
	assert t.live >= 0 && fd == 100 + t.live
	result := t.nodes[t.live].close_error
	t.live = -1
	t.closes++
	return result
}

fn (mut t MockTree) is_character(fd int) (bool, DeviceError) {
	assert t.live >= 0 && fd == 100 + t.live
	t.stats++
	return false, DeviceError.none
}

fn (mut t MockTree) is_writable(fd int) (bool, DeviceError) {
	assert t.live >= 0 && fd == 100 + t.live
	t.stats++
	return t.nodes[t.live].writable, DeviceError.none
}

fn (mut t MockTree) list(path string, mut names DeviceNames) DeviceError {
	t.lists++
	names.count = 0
	if t.list_error != .none {
		return t.list_error
	}
	if path != t.directory {
		return .unavailable
	}
	for entry in t.entries {
		names.add(entry.bytes())
	}
	return .none
}
