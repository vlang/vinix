// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module file

import usercopy

// aarch64's struct epoll_event is not packed: events, four bytes of padding,
// then data -- 16 bytes, the kernel's own layout.
const epoll_event_size = u64(16)

fn read_epoll_event(address u64) ?EpollEvent {
	mut event := EpollEvent{}
	if !usercopy.copy_from_user(voidptr(&event), address, sizeof(EpollEvent)) {
		return none
	}
	return event
}

fn write_epoll_event(address u64, event EpollEvent) bool {
	return usercopy.copy_to_user(address, voidptr(&event), sizeof(EpollEvent))
}
