// SPDX-License-Identifier: GPL-2.0-or-later
module sessionipc

import desktop.sessioncore
import os
import net as _

pub struct SessionAddress {
pub mut:
	prefix [2]u8
	path   [100]u8
}

pub struct SessionCredentials {
pub:
	pid i32
	uid u32
	gid u32
}

pub struct SessionMessage {
pub mut:
	pid    int
	fields [24]sessioncore.Text
	count  int
}

pub fn session_runtime_directory() string {
	base := os.getenv_opt('VINIX_SESSION_RUNTIME') or { '/run' }
	defer { unsafe { base.free() } }
	mut writer := &sessioncore.Writer{}
	defer { unsafe { free(writer) } }
	writer.add(base)
	writer.add('/vinix-session.')
	writer.number(C.getuid())
	return writer.finish()
}

pub fn session_address(path string) ?SessionAddress {
	mut addr := SessionAddress{}
	if path.len >= addr.path.len { return none }
	$if macos {
		addr.prefix[0] = u8(sizeof(SessionAddress))
		addr.prefix[1] = u8(C.AF_UNIX)
	} $else {
		addr.prefix[0] = u8(C.AF_UNIX)
		addr.prefix[1] = u8(C.AF_UNIX >> 8)
	}
	for i, byte in path { addr.path[i] = byte }
	return addr
}

pub fn session_private_directory(directory string) bool {
	if unsafe { C.mkdir(&char(directory.str), u32(0o700)) } != 0 && C.errno != C.EEXIST {
		return false
	}
	mut info := &C.stat{}
	defer { unsafe { free(info) } }
	return unsafe { C.lstat(&char(directory.str), info) } == 0 && u32(info.st_mode) & C.S_IFMT == C.S_IFDIR
		&& u32(info.st_uid) == C.getuid() && u32(info.st_mode) & 0o077 == 0
}

pub fn session_connect() ?int {
	directory := session_runtime_directory()
	path := '${directory}/broker'
	defer {
		unsafe {
			directory.free()
			path.free()
		}
	}
	if !session_private_directory(directory) { return none }
	addr := session_address(path) or { return none }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return none }
	desktop_set_cloexec(fd, true)
	desktop_set_nonblocking(fd, true)
	connected := C.connect(fd, voidptr(&addr), u32(sizeof(SessionAddress)))
	if connected != 0 && C.errno != C.EINPROGRESS {
		desktop_close(fd)
		return none
	}
	if connected != 0 {
		mut readiness := C.pollfd{ fd: fd, events: C.POLLOUT }
		if C.poll(&readiness, 1, 100) <= 0 {
			desktop_close(fd)
			return none
		}
		mut error_code := 0
		mut length := u32(sizeof(int))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &error_code, &length) != 0 || error_code != 0 {
			desktop_close(fd)
			return none
		}
	}
	return fd
}

pub fn session_send(fd int, data string) bool {
	mut offset := 0
	deadline := monotonic_millis() + 100
	for offset < data.len {
		mut readiness := C.pollfd{ fd: fd, events: C.POLLOUT }
		remaining := deadline - monotonic_millis()
		if remaining <= 0 || C.poll(&readiness, 1, int(remaining)) <= 0 { return false }
		$if macos {
			signal_option := i32(1)
			C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &signal_option, u32(sizeof(i32)))
		}
		flags := $if macos { 0 } $else { C.MSG_NOSIGNAL }
		n := unsafe { C.send(fd, &data.str[offset], usize(data.len - offset), flags) }
		if n <= 0 { return false }
		offset += n
	}
	return true
}

pub fn session_receive(fd int) !string {
	return session_receive_timeout(fd, 100)
}

pub fn session_receive_timeout(fd int, timeout int) !string {
	mut header := [4]u8{}
	session_read_exact(fd, &header[0], 4, timeout)!
	length := int(u32(header[0]) | u32(header[1]) << 8 | u32(header[2]) << 16 | u32(header[3]) << 24)
	if length < 1 || length > 256 * 1024 { return error('invalid session message length') }
	mut bytes := []u8{len: length}
	defer { unsafe { bytes.free() } }
	session_read_exact(fd, bytes.data, length, timeout)!
	return unsafe { tos(bytes.data, length).clone() }
}

pub fn session_read_exact(fd int, bytes &u8, length int, timeout int) ! {
	mut count := 0
	deadline := monotonic_millis() + timeout
	for count < length {
		mut readiness := C.pollfd{ fd: fd, events: C.POLLIN }
		remaining := deadline - monotonic_millis()
		if remaining <= 0 || C.poll(&readiness, 1, int(remaining)) <= 0 {
			return error('session request timed out')
		}
		n := unsafe { C.recv(fd, &bytes[count], usize(length - count), 0) }
		if n <= 0 { return error('session connection closed') }
		count += n
	}
}

pub fn session_send_message(fd int, data string) bool {
	if data.len < 1 || data.len > 256 * 1024 { return false }
	length := u32(data.len)
	header := [u8(length), u8(length >> 8), u8(length >> 16), u8(length >> 24)]!
	return session_send(fd, unsafe { tos(&header[0], 4) }) && session_send(fd, data)
}

pub fn session_call(command string, arguments []string) !string {
	mut writer := sessioncore.Writer{}
	writer.add(command)
	for arg in arguments {
		writer.add('\t')
		writer.field(arg)
	}
	request := writer.finish()
	defer { unsafe { request.free() } }
	return session_request(request, if command in ['quiet', 'alarm', 'alarm.cancel', 'settings.set',
		'policy.set', 'service.enable', 'service.import', 'service.remove', 'dismiss'] {
		2000
	} else {
		300
	})
}

// Both normal text calls and raw clipboard records use the same capability.
fn session_request(request string, timeout int) !string {
	control := session_has_control()
	fd := if control {
		session_control_fd
	} else {
		session_connect() or { return error('session services unavailable') }
	}
	defer { if !control { desktop_close(fd) } }
	if control && session_control_pending {
		// Startup is asynchronous. Do not send a request (and start its reply
		// timeout) until the broker announces that initialization is complete.
		mut readiness := C.pollfd{ fd: fd, events: C.POLLIN }
		if C.poll(&readiness, 1, 0) <= 0 { return error('session services starting') }
		ready := session_receive(fd) or {
			session_close_control()
			return err
		}
		defer { unsafe { ready.free() } }
		if ready != 'ready' {
			session_close_control()
			return error('invalid session startup response')
		}
		session_control_pending = false
	}
	if !session_send_message(fd, request) {
		if control { session_close_control() }
		return error('could not send session request')
	}
	reply := session_receive_timeout(fd, timeout) or {
		// A timeout can leave a partial frame. Never reuse or reconnect a lost
		// control channel; a new broker needs a new inherited endpoint.
		if control { session_close_control() }
		return err
	}
	if reply.starts_with('error\t') {
		unsafe { reply.free() }
		return error('session request rejected')
	}
	return reply
}

pub fn session_call_ok(command string, arguments []string) bool {
	reply := session_call(command, arguments) or {
		session_discard_error(err)
		return false
	}
	defer { unsafe { reply.free() } }
	return reply == 'ok' || reply.starts_with('ok\t')
}

// IPC transport errors are owned results, unlike the broker's shared rules.
fn session_discard_error(err IError) {
	message := err.msg()
	unsafe {
		message.free()
		err.free()
	}
}

pub fn session_peer(fd int) ?SessionCredentials {
	$if macos {
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(fd, &uid, &gid) != 0 || uid != C.getuid() { return none }
		mut pid := 0
		mut length := u32(sizeof(int))
		if C.getsockopt(fd, C.SOL_LOCAL, C.LOCAL_PEERPID, &pid, &length) != 0 { return none }
		return SessionCredentials{ pid: pid, uid: uid, gid: gid }
	} $else {
		mut peer := SessionCredentials{}
		mut length := u32(sizeof(SessionCredentials))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_PEERCRED, &peer, &length) != 0 || length != sizeof(SessionCredentials) || peer.uid != C.getuid() {
			return none
		}
		return peer
	}
}
