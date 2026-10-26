// SPDX-License-Identifier: GPL-2.0-or-later
// Narrow account requests on a separate connected Unix stream, never the
// service lifetime channel. No Parcel object references cross this boundary.
module nativeaccountauth

import encoding.utf8
import time

const request_magic = 'VXA1'
const request_header_size = 20
const max_request_body = 64 * 1024
const max_request_string = 4096

pub enum Operation {
	get_accounts = 1
	add_account  = 2
}

pub enum ScalarKind {
	null_value
	text
	boolean
	int32
	int64
}

pub struct Scalar {
pub:
	kind    ScalarKind
	text    string
	boolean bool
	number  i64
}

pub struct Option {
pub:
	key   string
	value Scalar
}

pub struct Request {
pub:
	id              u64
	operation       Operation
	account_type    ?string
	auth_token_type ?string
	features        []string
	options         []Option
}

// Caller is derived independently from the accepted socket's kernel peer.
// These fields must replace identity options when dispatch is implemented.
pub struct AuthorizedRequest {
pub:
	caller  Caller
	request Request
}

fn reserved_option(key string) bool {
	return key in ['callerUid', 'callerPid', 'androidPackageName', 'accountAuthenticatorResponse',
		'android.accounts.AccountAuthenticatorResponse', 'vinixCaller', 'vinixSession']
}

fn request_text(value string, allow_empty bool) ! {
	if value.len > max_request_string || (!allow_empty && value.len == 0)
		|| value.contains('\x00') || !utf8.validate_str(value) {
		return error('invalid account request string')
	}
}

fn append_uint(mut bytes []u8, value u64, count int) {
	for offset in 0 .. count { bytes << u8(value >> ((count - offset - 1) * 8)) }
}

fn append_string(mut bytes []u8, value ?string) ! {
	if text := value {
		request_text(text, true)!
		append_uint(mut bytes, u64(text.len), 4)
		bytes << text.bytes()
	} else {
		append_uint(mut bytes, 0xffffffff, 4)
	}
}

fn validate_request(request Request) ! {
	if request.id == 0 { return error('account request ID must be nonzero') }
	if request.operation !in [.get_accounts, .add_account] {
		return error('unknown account operation')
	}
	if value := request.account_type { request_text(value, false)! }
	if value := request.auth_token_type { request_text(value, true)! }
	if request.operation == .get_accounts {
		if request.auth_token_type != none || request.features.len != 0 || request.options.len != 0 {
			return error('account query has addition fields')
		}
	} else if request.account_type == none {
		return error('account addition requires account type')
	}
	if request.features.len > 32 || request.options.len > 32 {
		return error('too many account request fields')
	}
	mut features := map[string]bool{}
	for feature in request.features {
		request_text(feature, false)!
		if feature in features { return error('duplicate account feature') }
		features[feature] = true
	}
	mut keys := map[string]bool{}
	for option in request.options {
		request_text(option.key, false)!
		if reserved_option(option.key) || option.key in keys {
			return error('reserved or duplicate account option')
		}
		keys[option.key] = true
		match option.value.kind {
			.null_value, .boolean, .int64 {}
			.text { request_text(option.value.text, true)! }
			.int32 {
				if option.value.number < -2147483648 || option.value.number > 2147483647 {
					return error('account option exceeds int32')
				}
			}
			else { return error('unknown account option type') }
		}
	}
}

// Version 1 uses network byte order, a fixed header, and bounded scalar options.
// The client must shutdown(SHUT_WR) after writing exactly this one frame. This
// allows a receiver to reject trailing data, including delayed second frames.
pub fn encode_request(request Request) ![]u8 {
	validate_request(request)!
	mut body := []u8{}
	append_string(mut body, request.account_type)!
	if request.operation == .add_account {
		append_string(mut body, request.auth_token_type)!
		body << u8(request.features.len)
		for feature in request.features { append_string(mut body, feature)! }
		body << u8(request.options.len)
		for option in request.options {
			append_string(mut body, option.key)!
			body << u8(option.value.kind)
			match option.value.kind {
				.null_value {}
				.text { append_string(mut body, option.value.text)! }
				.boolean { body << u8(option.value.boolean) }
				.int32 { append_uint(mut body, u64(u32(option.value.number)), 4) }
				.int64 { append_uint(mut body, u64(option.value.number), 8) }
			}
		}
	}
	if body.len > max_request_body { return error('account request body exceeds size limit') }
	mut frame := request_magic.bytes()
	append_uint(mut frame, 1, 2)
	append_uint(mut frame, u64(request.operation), 2)
	append_uint(mut frame, request.id, 8)
	append_uint(mut frame, u64(body.len), 4)
	frame << body
	return frame
}

// Verify the broker's kernel identity before sending application options.
// Sending and the write-half close share one bounded monotonic deadline.
pub fn send_request(fd int, request Request) ! {
	verify_root_channel(fd)!
	frame := encode_request(request)!
	flags := C.fcntl(i32(fd), C.F_GETFD)
	if flags < 0 || C.fcntl(i32(fd), C.F_SETFD, flags | C.FD_CLOEXEC) != 0 {
		return error('cannot protect account client descriptor')
	}
	mut send_flags := i32(C.MSG_DONTWAIT)
	$if linux {
		send_flags |= C.MSG_NOSIGNAL
	}
	$if macos {
		value := i32(1)
		if C.setsockopt(i32(fd), C.SOL_SOCKET, C.SO_NOSIGPIPE, &value, u32(sizeof(i32))) != 0 {
			return error('cannot suppress account socket SIGPIPE')
		}
	}
	deadline := time.sys_mono_now() + 5 * time.second
	mut offset := 0
	for offset < frame.len {
		remaining := (deadline - time.sys_mono_now()) / time.millisecond
		if remaining <= 0 { return error('account request send deadline expired') }
		mut ready := C.pollfd{ fd: i32(fd), events: C.POLLOUT }
		status := C.poll(&ready, 1, i32(remaining))
		if status < 0 && C.errno == C.EINTR { continue }
		if status != 1 || ready.revents & C.POLLOUT == 0 {
			return error('account request send unavailable')
		}
		n := unsafe { C.send(i32(fd), &frame[offset], uint(frame.len - offset), send_flags) }
		if n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
		if n <= 0 { return error('account request send failed') }
		offset += int(n)
	}
	if C.shutdown(i32(fd), C.SHUT_WR) != 0 {
		return error('cannot close account request write half')
	}
}

struct RequestReader {
	bytes []u8
mut:
	position int
}

struct NullableString {
	value ?string
}

fn (mut reader RequestReader) uint_value(count int) !u64 {
	if count <= 0 || reader.position > reader.bytes.len - count {
		return error('truncated account request')
	}
	mut value := u64(0)
	for _ in 0 .. count {
		value = (value << 8) | u64(reader.bytes[reader.position])
		reader.position++
	}
	return value
}

fn (mut reader RequestReader) string_value() !NullableString {
	length := reader.uint_value(4)!
	if length == 0xffffffff { return NullableString{} }
	if length > max_request_string || int(length) > reader.bytes.len - reader.position {
		return error('invalid account request string length')
	}
	value := reader.bytes[reader.position..reader.position + int(length)].bytestr()
	reader.position += int(length)
	request_text(value, true)!
	return NullableString{ value: value }
}

fn (mut reader RequestReader) required_string() !string {
	result := reader.string_value()!
	return result.value or { return error('null account request string') }
}

fn request_header(bytes []u8) !(Operation, u64, int) {
	if bytes.len != request_header_size || bytes[..4].bytestr() != request_magic {
		return error('invalid account request header')
	}
	mut reader := RequestReader{ bytes: bytes, position: 4 }
	if reader.uint_value(2)! != 1 { return error('unsupported account request version') }
	op := reader.uint_value(2)!
	if op !in [u64(1), 2] { return error('unknown account request operation') }
	id := reader.uint_value(8)!
	length := reader.uint_value(4)!
	if id == 0 || length > max_request_body { return error('invalid account request bound') }
	return unsafe { Operation(op) }, id, int(length)
}

fn decode_request(header []u8, body []u8) !Request {
	op, id, length := request_header(header)!
	if body.len != length { return error('account request body length mismatch') }
	mut reader := RequestReader{ bytes: body }
	account_type := reader.string_value()!.value
	mut auth_type := ?string(none)
	mut features := []string{}
	mut options := []Option{}
	if op == .add_account {
		auth_type = reader.string_value()!.value
		feature_count := reader.uint_value(1)!
		if feature_count > 32 { return error('too many account features') }
		for _ in 0 .. int(feature_count) { features << reader.required_string()! }
		option_count := reader.uint_value(1)!
		if option_count > 32 { return error('too many account options') }
		for _ in 0 .. int(option_count) {
			key := reader.required_string()!
			tag := reader.uint_value(1)!
			value := match tag {
				0 { Scalar{ kind: .null_value } }
				1 { Scalar{ kind: .text, text: reader.required_string()! } }
				2 {
					flag := reader.uint_value(1)!
					if flag > 1 { return error('invalid account boolean') }
					Scalar{ kind: .boolean, boolean: flag == 1 }
				}
				3 { Scalar{ kind: .int32, number: i64(i32(reader.uint_value(4)!)) } }
				4 { Scalar{ kind: .int64, number: i64(reader.uint_value(8)!) } }
				else { return error('unsupported account option tag') }
			}
			options << Option{key, value}
		}
	}
	if reader.position != body.len { return error('trailing account request fields') }
	request := Request{id, op, account_type, auth_type, features, options}
	validate_request(request)!
	return request
}

fn request_read_exact(fd int, mut bytes []u8, deadline i64) ! {
	mut offset := 0
	for offset < bytes.len {
		remaining := (deadline - time.sys_mono_now()) / time.millisecond
		if remaining <= 0 { return error('account request deadline expired') }
		mut ready := C.pollfd{ fd: i32(fd), events: C.POLLIN }
		status := C.poll(&ready, 1, i32(remaining))
		if status < 0 && C.errno == C.EINTR { continue }
		if status != 1 || ready.revents & (C.POLLIN | C.POLLHUP) == 0 {
			return error('account request unavailable')
		}
		n := unsafe { C.recv(i32(fd), &bytes[offset], uint(bytes.len - offset), C.MSG_DONTWAIT) }
		if n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
		if n <= 0 { return error('account request ended early') }
		offset += int(n)
	}
}

fn receive_request_frame(fd int, deadline i64) !Request {
	mut header := []u8{len: request_header_size}
	request_read_exact(fd, mut header, deadline)!
	_, _, length := request_header(header)!
	mut body := []u8{len: length}
	request_read_exact(fd, mut body, deadline)!
	// An actual EOF is mandatory. Merely peeking at currently queued bytes would
	// accept a delayed second frame and leave ambiguous connection ownership.
	mut extra := []u8{len: 1}
	for {
		remaining := (deadline - time.sys_mono_now()) / time.millisecond
		if remaining <= 0 { return error('account request write-half close deadline expired') }
		mut ready := C.pollfd{ fd: i32(fd), events: C.POLLIN }
		status := C.poll(&ready, 1, i32(remaining))
		if status < 0 && C.errno == C.EINTR { continue }
		if status != 1 || ready.revents & (C.POLLIN | C.POLLHUP) == 0 {
			return error('account request EOF unavailable')
		}
		n := C.recv(i32(fd), extra.data, 1, C.MSG_DONTWAIT)
		if n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
		if n != 0 { return error('trailing account request data') }
		break
	}
	return decode_request(header, body)
}

// The broker owns both descriptors. It must accept this request on its separate
// listener, never duplicate or pass the service lifetime endpoint here. This
// helper consumes one request but leaves the socket open for a future reply.
pub fn (registry Registry) receive_request(fd int, lifetime_fd int) !AuthorizedRequest {
	if C.getuid() != 0 || C.geteuid() != 0 {
		return error('account requests require the root broker process')
	}
	if lifetime_fd < 0 || fd == lifetime_fd {
		return error('account requests require a separate channel')
	}
	caller := registry.authenticate(fd, Claims{})!
	flags := C.fcntl(i32(fd), C.F_GETFD)
	if flags < 0 || C.fcntl(i32(fd), C.F_SETFD, flags | C.FD_CLOEXEC) != 0 {
		return error('cannot protect account request descriptor')
	}
	request := receive_request_frame(fd, time.sys_mono_now() + 5 * time.second)!
	return AuthorizedRequest{caller, request}
}
