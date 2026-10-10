// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <poll.h>

struct C.pollfd {
mut:
	fd i32
	events i16
	revents i16
}

struct DarwinPollFD {
mut:
	fd i32
	events i16
	revents i16
}

fn C.poll(&C.pollfd, usize, i32) i32
fn C.pipe(&i32) i32

fn darwin_pipe(output &i32) i32 {
	if output == unsafe { nil } { darwin_set_errno(14); return -1 }
	previous := unsafe { *C.ios_errno_address() }
	result := C.pipe(output)
	darwin_set_errno(if result < 0 { darwin_native_error(unsafe { *C.ios_errno_address() }) } else { previous })
	return result
}

fn poll_pipe_access(fd i32) i32 {
	// Vinix exposes a shared pipe readiness state. Restrict that state to
	// the end's actual access mode, so a read end cannot appear writable.
	$if linux {
		status := C.fcntl(fd, C.F_GETFL, usize(0))
		if status < 0 || status & 3 == 2 { return -1 }
		mut fields := [20]u64{}
		if C.ios_stat_info(unsafe { nil }, fd, 2, unsafe { &fields[0] }) == 0 && fields[1] & 0xf000 == 0x1000 {
			return status & 3
		}
	}
	return -1
}

fn poll_unix_stream(fd i32) bool {
	$if linux {
		// Query type/address without reading SO_ERROR, which would consume an
		// error that belongs to the application's next getsockopt call.
		mut kind := i32(0)
		mut length := u32(sizeof(kind))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_TYPE, unsafe { &kind }, unsafe { &length }) != 0 || kind != C.SOCK_STREAM { return false }
		mut address := [128]u8{}
		length = u32(sizeof(address))
		return C.getsockname(fd, unsafe { voidptr(&address[0]) }, unsafe { &length }) == 0 && length >= 2 &&
			(u16(address[0]) | (u16(address[1]) << 8)) == u16(C.AF_UNIX)
	}
	return false
}

fn darwin_poll(output &DarwinPollFD, count u32, timeout i32) i32 {
	// Vinix's native poll ABI has this descriptor ceiling. Validate before
	// touching app memory or allocating an attacker-sized translation array.
	$if linux {
		if count > 4096 { darwin_set_errno(22); return -1 }
	} $else {
		if count > 10240 { darwin_set_errno(22); return -1 }
	}
	if count != 0 && output == unsafe { nil } { darwin_set_errno(14); return -1 }
	previous := unsafe { *C.ios_errno_address() }
	mut stack := [32]C.pollfd{}
	mut native := unsafe { &stack[0] }
	if count > 32 {
		native = unsafe { &C.pollfd(C.malloc(usize(count) * sizeof(C.pollfd))) }
		if native == unsafe { nil } { darwin_set_errno(12); return -1 }
	}
	defer { if count > 32 { C.free(native) } }
	mut active := false
	unsafe {
		for i := u32(0); i < count; i++ {
			entry := &output[i]
			native[i] = C.pollfd{fd: -1}
			if entry.fd < 0 { continue }
			// Darwin vnode change notifications have no native poll equivalent.
			if u16(entry.events) & ~u16(0x01ff) != 0 {
				darwin_set_errno(45)
				return -1
			}
			mut events := i16(0)
			if entry.events & 0x41 != 0 { events |= i16(C.POLLIN) }
			if entry.events & 0x82 != 0 { events |= i16(C.POLLPRI) }
			// Measured Darwin POLLWRBAND follows ordinary write readiness.
			if entry.events & 0x104 != 0 { events |= i16(C.POLLOUT) }
			access := poll_pipe_access(entry.fd)
			if access == 0 { events &= ~i16(C.POLLOUT) }
			if access == 1 { events &= ~i16(C.POLLIN | C.POLLPRI) }
			// Darwin ignores descriptors with no requested readiness filters,
			// including closed descriptors and pipe EOF.
			if entry.events & 0x1c7 != 0 {
				native[i].fd = entry.fd
				native[i].events = events
				active = true
			}
		}
	}
	result := if active { C.poll(native, usize(count), timeout) } else { C.poll(unsafe { nil }, 0, timeout) }
	if result < 0 {
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
		return -1
	}
	mut ready := i32(0)
	unsafe {
		for i := u32(0); i < count; i++ {
			mut entry := &output[i]
			mut status := native[i].revents
			if status & i16(C.POLLERR) != 0 && poll_pipe_access(entry.fd) == 1 {
				// Linux reports a broken pipe writer as POLLERR; the Mac reports
				// the peer's departure as POLLHUP for either readiness filter.
				status = (status & ~i16(C.POLLERR)) | i16(C.POLLHUP)
			}
			if status & i16(C.POLLERR | C.POLLHUP) == i16(C.POLLERR | C.POLLHUP) && poll_unix_stream(entry.fd) {
				// Vinix marks a Unix stream's closed peer as both error and EOF;
				// Darwin reports EOF. Keep actual socket errors owned by libc.
				status &= ~i16(C.POLLERR)
			}
			mut events := status & i16(C.POLLERR | C.POLLHUP | C.POLLNVAL)
			if status & i16(C.POLLIN) != 0 { events |= entry.events & 0x41 }
			if status & i16(C.POLLPRI) != 0 { events |= entry.events & 0x82 }
			if status & i16(C.POLLOUT) != 0 { events |= entry.events & 0x104 }
			if status & i16(C.POLLHUP) != 0 {
				// Darwin EOF is readable even after a pipe's last byte is drained;
				// a hung-up socket no longer reports its writable filters.
				events = (events & ~i16(0x104)) | (entry.events & 0x41)
			}
			entry.revents = events
			if events != 0 { ready++ }
		}
	}
	darwin_set_errno(previous)
	return ready
}
