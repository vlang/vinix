// SPDX-License-Identifier: GPL-2.0-or-later
module file

import resource
import time

pub fn poll_for_checks(number int, requested int, block bool, selecting bool) int {
	mut descriptor := PollFD{fd: i32(number), events: i16(requested)}
	timeout := time.TimeSpec{}
	deadline := if block { unsafe { &time.TimeSpec(nil) } } else { unsafe { &timeout } }
	count, code := ppoll(unsafe { &descriptor }, 1, deadline, unsafe { nil }, selecting)
	assert code == 0 && count == if descriptor.revents != 0 { u64(1) } else { u64(0) }
	return int(descriptor.revents)
}

pub struct EpollWatchForChecks {
mut:
	entry EpollEntry
}

pub fn watch_for_checks(events u32) EpollWatchForChecks {
	return EpollWatchForChecks{entry: EpollEntry{events: events}}
}

pub fn (mut watch EpollWatchForChecks) sample(number int) u32 {
	mut fd := fd_from_fdnum(unsafe { nil }, number) or { panic('epoll fixture fd') }
	defer { fd.unref() }
	mut target := fd.handle.resource
	state := resource.poll_state(mut target, fd.handle.flags & resource.o_accmode, int(watch.entry.events))
	return epoll_ready_events(mut watch.entry, state)
}
