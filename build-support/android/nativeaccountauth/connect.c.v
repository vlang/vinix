// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

import os
import time

fn authenticator_connected(fd i32) ! {
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for {
		now := time.sys_mono_now()
		if now >= deadline { return error('authenticator connection timed out') }
		mut ready := C.pollfd{fd: fd, events: C.POLLOUT}
		status := C.poll(&ready, 1, i32((deadline - now + u64(time.millisecond) - 1) / u64(time.millisecond)))
		if status < 0 && C.errno == C.EINTR { continue }
		if status != 1 || ready.revents & C.POLLOUT == 0 {
			return error('authenticator connection failed')
		}
		mut problem := i32(0)
		mut size := u32(sizeof(problem))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &problem, &size) != 0
			|| size != sizeof(problem) || problem != 0 {
			return error('authenticator connection failed')
		}
		return
	}
}

// Connect after the irreversible identity drop, separately from service EOF.
pub fn connect_authenticator(path string) !int {
	mut address := C.sockaddr_un{}
	if !os.is_abs_path(path) || os.norm_path(path) != path || path.contains('\x00')
		|| path.len >= address.sun_path.len || path.ends_with('/') {
		return error('authenticator socket path must be absolute and canonical')
	}
	$if macos { address.sun_len = u8(sizeof(C.sockaddr_un)) }
	address.sun_family = C.AF_UNIX
	for index, byte in path { address.sun_path[index] = char(byte) }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create authenticator channel') }
	if fd < 3 { C.close(fd); return error('authenticator channel requires a private descriptor') }
	mut keep := false
	defer { if !keep { C.close(fd) } }
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) != 0
		|| C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 {
		return error('cannot protect authenticator channel')
	}
	if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		if C.errno !in [C.EINPROGRESS, C.EALREADY, C.EINTR] {
			return error('cannot connect authenticator channel')
		}
		authenticator_connected(fd)!
	}
	peer := peer_credentials(int(fd))!
	if peer.uid != 0 || peer.gid != 0 {
		return error('authenticator command channel requires a Unix root peer')
	}
	keep = true
	return int(fd)
}
