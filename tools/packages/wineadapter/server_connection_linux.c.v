// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import time

#define vinix_wine_connect_socket socket
#define vinix_wine_connect_address(fd, address, length) connect((fd), (const struct sockaddr *)(address), (length))
fn C.vinix_wine_connect_socket(i32, i32, i32) i32
fn C.vinix_wine_connect_address(i32, voidptr, u32) i32

fn (endpoint &ServerEndpoint) connect_linux(server &ServerDirectory, guard &LaunchGuard, data string, child i32, timeout_ms int) !ServerConnection {
	if timeout_ms < 1 || timeout_ms > 5000 { return error('Wine connect wait must be between 1 and 5000 milliseconds') }
	endpoint.recheck(server, guard, data)!
	// Refuse foreign/unowned lock state before contacting any listener.
	verify_server_owner(server.lock_fd, child)!
	mut connection := ServerConnection{child: child}
	mut accepted := false
	defer { if !accepted { connection.close() } }
	connection.endpoint.directory = C.vinix_wine_guard_fcntl(endpoint.directory, C.F_DUPFD_CLOEXEC, 3)
	if connection.endpoint.directory < 0 { return error('cannot retain Wine connection directory') }
	connection.endpoint.node = C.vinix_wine_guard_fcntl(endpoint.node, C.F_DUPFD_CLOEXEC, 3)
	if connection.endpoint.node < 0 { return error('cannot retain Wine connection endpoint') }
	connection.fd = C.vinix_wine_connect_socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0)
	if connection.fd < 3 { return error('cannot create private Wine connection socket') }
	text := connection.endpoint.node.str()
	route := '/proc/self/fd/' + text
	defer { unsafe { text.free(); route.free() } }
	if route.len >= 108 { return error('Wine descriptor connection address is too long') }
	mut address := C.vinix_wine_peer_address{sun_family: u16(C.AF_UNIX)}
	unsafe { vmemcpy(&address.sun_path[0], route.str, route.len) }
	deadline := time.sys_mono_now() + i64(timeout_ms) * time.millisecond
	mut pending := false
	for {
		now := time.sys_mono_now()
		if now >= deadline { return error('Wine server connect timed out') }
		if !pending {
			if C.vinix_wine_connect_address(connection.fd, unsafe { &address }, u32(2 + route.len + 1)) == 0 { break }
			failure := C.errno
			if failure == C.EISCONN { break }
			if failure == C.EAGAIN || failure == C.EWOULDBLOCK || failure == C.EINTR {
				time.sleep(time.millisecond)
				continue
			}
			if failure != C.EINPROGRESS && failure != C.EALREADY { return error('cannot connect to retained Wine endpoint') }
			pending = true
		}
		mut ready := ServerPoll{fd: connection.fd, events: i16(C.POLLOUT)}
		wait_now := time.sys_mono_now()
		if wait_now >= deadline { return error('Wine server connect timed out') }
		wait_ms := i32((deadline - wait_now + 999999) / 1000000)
		result := C.vinix_wine_peer_poll(unsafe { &ready }, 1, wait_ms)
		if result < 0 && C.errno == C.EINTR { continue }
		if result == 0 { return error('Wine server connect timed out') }
		if result < 0 || ready.revents & i16(C.POLLHUP | C.POLLERR | C.POLLNVAL) != 0
			|| ready.revents & i16(C.POLLOUT) == 0 { return error('Wine server connection failed while pending') }
		mut failure := i32(0)
		mut size := u32(sizeof(i32))
		if C.vinix_wine_peer_getsockopt(connection.fd, C.SOL_SOCKET, C.SO_ERROR, unsafe { &failure }, &size) != 0
			|| size != sizeof(i32) || failure != 0 { return error('Wine server connection failed while pending') }
		break
	}
	connection.recheck(server, guard, data)!
	// Nonblocking mode bounds connection setup. The retained protocol stream
	// is blocking, as a normal Wine server socket is; CLOEXEC stays set.
	status := C.vinix_wine_guard_fcntl(connection.fd, C.F_GETFL)
	if status < 0 || C.vinix_wine_guard_fcntl(connection.fd, C.F_SETFL, status & ~i32(C.O_NONBLOCK)) != 0 {
		return error('cannot restore blocking Wine protocol socket')
	}
	if time.sys_mono_now() >= deadline { return error('Wine server connect timed out') }
	accepted = true
	return connection
}
