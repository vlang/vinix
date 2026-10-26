// SPDX-License-Identifier: GPL-2.0-or-later
module main

import nativeaccountauth
import desktop.windowfb

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

struct BridgePoll {
mut:
	fd      i32
	events  i16
	revents i16
}

fn protect_fd(fd int, nonblocking bool) ! {
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) < 0 {
		return error('cannot protect account UI descriptor')
	}
	if nonblocking {
		flags := C.fcntl(fd, C.F_GETFL)
		if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0 {
			return error('cannot configure account UI descriptor')
		}
	}
}

fn authorize_lifetime(fd int) ! {
	if C.getuid() != C.geteuid() || C.getgid() != C.getegid() {
		return error('account UI helper must not be setuid or setgid')
	}
	peer := nativeaccountauth.peer_credentials(fd)!
	if peer.uid != 0 { return error('account UI requires a root broker lifetime peer') }
	protect_fd(fd, true)!
}

fn lifetime_alive(fd int) !bool {
	mut byte := u8(0)
	for {
		n := C.recv(fd, &byte, 1, C.MSG_PEEK | C.MSG_DONTWAIT)
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK]! { return true }
		if n == 0 { return false }
		return error('invalid account UI lifetime channel')
	}
	return false
}

fn wait_bridge(window &windowfb.Window, input int, lifetime int, pending bool) ! {
	mut descriptors := [
		BridgePoll{
			fd:     i32(window.event_fd())
			events: i16(C.POLLIN | if window.connection.wants_write() {
				C.POLLOUT
			} else {
				0
			})
		},
		BridgePoll{ fd: i32(lifetime), events: i16(C.POLLIN) },
		BridgePoll{ fd: i32(input), events: if pending { i16(C.POLLOUT) } else { i16(0) } },
	]!
	result := unsafe { C.poll(&C.pollfd(&descriptors[0]), 3, 16) }
	if result < 0 && C.errno != C.EINTR { return error('account UI poll failed') }
	for p in descriptors {
		if p.revents & C.POLLNVAL != 0 { return error('account UI descriptor closed') }
	}
}
