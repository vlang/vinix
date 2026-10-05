// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module file

import katomic
import proc
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

// Whether `t`'s process has told it to exit, as exit_group(2) and execve(2)
// tell every thread but their own.
fn thread_told_to_exit(t &proc.Thread) bool {
	return katomic.load(&t.must_exit)
}
