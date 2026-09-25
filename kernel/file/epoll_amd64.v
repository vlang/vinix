// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module file

import usercopy

// x86-64's struct epoll_event is packed: events, then data straight after it
// at offset 4 -- 12 bytes. Read with aarch64's padded layout, a program found
// the low half of its data word shifted into the high half: the X server took
// the pointer it had stored for its listening socket back as 0x80000000000 and
// crashed on the first client that connected.
const epoll_event_size = u64(12)

fn read_epoll_event(address u64) ?EpollEvent {
	mut raw := [12]u8{}
	if !usercopy.copy_from_user(voidptr(&raw[0]), address, epoll_event_size) {
		return none
	}
	mut event := EpollEvent{}
	unsafe {
		event.events = *&u32(&raw[0])
		event.data = *&u64(&raw[4])
	}
	return event
}

fn write_epoll_event(address u64, event EpollEvent) bool {
	mut raw := [12]u8{}
	unsafe {
		*&u32(&raw[0]) = event.events
		*&u64(&raw[4]) = event.data
	}
	return usercopy.copy_to_user(address, voidptr(&raw[0]), epoll_event_size)
}
