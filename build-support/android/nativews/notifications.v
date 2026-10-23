// SPDX-License-Identifier: GPL-2.0-or-later
// Android notification IDs map to keyed notices owned by the kernel peer PID
// in Vinix's native session broker. No display toolkit or DBus is involved.
@[translated]
module atlframework

#include <sys/socket.h>
#include <errno.h>

enum WsNoticeResult {
	failed
	unavailable
	ok
}

struct WsNoticeAddress {
mut:
	family u16
	path   [108]u8
}

fn C.socket(i32, i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.send(i32, voidptr, usize, i32) isize
fn C.recv(i32, voidptr, usize, i32) isize
fn C.getuid() u32
fn C.strcmp(&char, &char) i32

fn ws_notice_transfer(fd i32, bytes &u8, length usize, send bool) bool {
	unsafe {
		mut used := usize(0)
		deadline := ws_millis() + 1000
		for used < length {
			remaining := deadline - ws_millis()
			if remaining <= 0 { return false }
			mut readiness := WsPoll{ fd: fd, events: if send { i16(4) } else { i16(1) } }
			if C.poll(voidptr(&readiness), 1, i32(remaining)) <= 0 { return false }
			n := if send {
				C.send(fd, &bytes[used], length - used, 0x4000)
			} else {
				C.recv(fd, &bytes[used], length - used, 0)
			}
			if n <= 0 { return false }
			used += usize(n)
		}
		return true
	}
}

fn ws_notice_request(payload &u8, length usize) WsNoticeResult {
	unsafe {
		if length == 0 || length > 8192 { return .failed }
		fd := C.socket(1, 1 | 0x800 | 0x80000, 0)
		if fd < 0 { return .failed }
		defer { C.close(fd) }
		address := &WsNoticeAddress(C.alloca(sizeof(WsNoticeAddress)))
		C.memset(address, 0, sizeof(WsNoticeAddress))
		address.family = 1
		mut directory := C.getenv(c'VINIX_SESSION_RUNTIME')
		if directory == nil { directory = c'/run' }
		count := C.snprintf(&char(&address.path[0]), 108, c'%s/vinix-session.%u/broker', directory, C.getuid())
		if count < 0 || count >= 108 { return .failed }
		if C.connect(fd, voidptr(address), u32(sizeof(WsNoticeAddress))) != 0 {
			code := *C.__errno_location()
			if code == C.ENOENT || code == C.ECONNREFUSED { return .unavailable }
			if code != C.EINPROGRESS { return .failed }
			mut ready := WsPoll{ fd: fd, events: 4 }
			mut error := i32(0)
			mut size := u32(sizeof(i32))
			if C.poll(voidptr(&ready), 1, 1000) <= 0 || C.getsockopt(fd, 1, 4, &error, &size) != 0 {
				return .failed
			}
			if error == C.ENOENT || error == C.ECONNREFUSED { return .unavailable }
			if error != 0 { return .failed }
		}
		header := &u8(C.alloca(4))
		for i := 0; i < 4; i++ { header[i] = u8(length >> (i * 8)) }
		if !ws_notice_transfer(fd, header, 4, true) || !ws_notice_transfer(fd, payload, length, true)
			|| !ws_notice_transfer(fd, header, 4, false) {
			return .failed
		}
		response_length := u32(header[0]) | (u32(header[1]) << 8) | (u32(header[2]) << 16) | (u32(header[3]) << 24)
		if response_length == 0 || response_length > 512 { return .failed }
		response := &u8(C.alloca(513))
		if !ws_notice_transfer(fd, response, response_length, false) { return .failed }
		response[response_length] = 0
		if C.strcmp(&char(response), c'ok') != 0 {
			C.printf(c'ANDROID-WS-NOTIFICATION-SERVICE %s\n', response)
			return .failed
		}
		return .ok
	}
}

// Session arguments are hex fields, not raw tab-separated app text.
fn ws_notice_field(buffer &u8, used &usize, capacity usize, value &char, limit usize) bool {
	unsafe {
		full := C.strlen(value)
		mut length := if full > limit { limit } else { full }
		for length > 0 && length < full && u8(value[length]) & 0xc0 == 0x80 { length-- }
		if *used + length * 2 + 1 >= capacity { return false }
		buffer[*used] = `\t`
		(*used)++
		for i := usize(0); i < length; i++ {
			byte := u8(value[i])
			hi, lo := byte >> 4, byte & 15
			buffer[*used] = if hi < 10 { `0` + hi } else { `a` + hi - 10 }
			(*used)++
			buffer[*used] = if lo < 10 { `0` + lo } else { `a` + lo - 10 }
			(*used)++
		}
		return true
	}
}

fn ws_notification_cancel_key(e voidptr, key &char) {
	unsafe {
		buffer := &u8(C.alloca(512))
		C.memcpy(buffer, c'notify.cancel', 13)
		used := &usize(C.alloca(sizeof(usize)))
		*used = 13
		if !ws_notice_field(buffer, used, 512, key, 128) {
			throw(e, c'java/lang/IllegalStateException', c'Vinix notification service unavailable')
			return
		}
		result := ws_notice_request(buffer, *used)
		// There is no peer-owned notice to remove when the optional broker is absent.
		if result == .unavailable {
			C.printf(c'ANDROID-WS-NOTIFICATION-CANCEL key=%s native-service=absent\n', key)
			return
		}
		if result != .ok {
			throw(e, c'java/lang/IllegalStateException', c'Vinix notification service unavailable')
			return
		}
		C.printf(c'ANDROID-WS-NOTIFICATION-CANCEL key=%s native-service=ok\n', key)
	}
}

fn ws_notification_cancel(e voidptr, id i32) {
	unsafe {
		key := &char(C.alloca(64))
		C.snprintf(key, 64, c'android:%d', id)
		ws_notification_cancel_key(e, key)
	}
}

fn ws_notification_show(e voidptr, id i32, title voidptr, text voidptr, intent_type i32) {
	if intent_type != -1 {
		throw(e, c'java/lang/UnsupportedOperationException', c'Notification PendingIntent actions are not implemented')
		return
	}
	unsafe {
		key := &char(C.alloca(64))
		C.snprintf(key, 64, c'android:%d', id)
		headline, body := ws_utf(e, title), ws_utf(e, text)
		defer {
			ws_release(e, title, headline)
			ws_release(e, text, body)
		}
		buffer := &u8(C.alloca(4096))
		C.memcpy(buffer, c'notify', 6)
		used := &usize(C.alloca(sizeof(usize)))
		*used = 6
		mut valid := ws_notice_field(buffer, used, 4096, key, 128)
		if C.strlen(headline) > 0 {
			valid = valid && ws_notice_field(buffer, used, 4096, headline, 128)
		} else {
			valid = valid && ws_notice_field(buffer, used, 4096, c'Android', 128)
		}
		valid = valid && ws_notice_field(buffer, used, 4096, body, 511)
			&& ws_notice_field(buffer, used, 4096, c'1', 1)
			&& ws_notice_field(buffer, used, 4096, c'-1', 2)
			&& ws_notice_field(buffer, used, 4096, c'', 0)
		if !valid || ws_notice_request(buffer, *used) != .ok {
			throw(e, c'java/lang/IllegalStateException', c'Vinix notification service unavailable')
			return
		}
		C.printf(c'ANDROID-WS-NOTIFICATION-POST id=%d native-service=ok\n', id)
	}
}
