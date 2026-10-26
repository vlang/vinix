// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import accountipc
import encoding.utf8
import nativeaccountauth
import sync
import time

@[heap]
struct AuthSession {
	command accountipc.Command
	started i64
}

@[heap]
struct Authenticator {
mut:
	mutex sync.Mutex
	stream &accountipc.Stream = unsafe { nil }
	sessions map[u64]&AuthSession
	current &AuthSession = unsafe { nil }
	closed bool
	refs int = 1
	released bool
}

@[heap]
struct AuthResponse {
	owner &Authenticator = unsafe { nil }
	session u64
	capability []u8
	kind accountipc.Kind
mut:
	options []nativeaccountauth.Option
}

fn auth_session_free(s &AuthSession) {
	accountipc.dispose_command(s.command)
	unsafe { free(s) }
}

fn (mut a Authenticator) retire(id u64) {
	s := a.sessions[id] or { return }
	a.sessions.delete(id)
	if s != a.current { auth_session_free(s) }
}

fn (mut a Authenticator) clear_current() {
	if a.current != unsafe { nil } && a.current.command.session !in a.sessions {
		auth_session_free(a.current)
	}
	a.current = unsafe { nil }
}

fn same_capability(a []u8, b []u8) bool {
	if a.len != 32 || b.len != 32 { return false }
	mut difference := u8(0)
	for i in 0 .. 32 { difference |= a[i] ^ b[i] }
	return difference == 0
}

// A successful open consumes the dedicated root command fd. Failure does not.
@[export: 'vinix_android_authenticator_open']
pub fn auth_open(fd i32) voidptr {
	peer := nativeaccountauth.peer_credentials(int(fd)) or { return unsafe { nil } }
	if peer.uid != 0 { return unsafe { nil } }
	stream := accountipc.open_stream(int(fd)) or { return unsafe { nil } }
	return &Authenticator{stream: stream}
}

fn (mut a Authenticator) disconnect() {
	if a.closed { return }
	a.closed = true
	a.stream.close()
	a.clear_current()
	for _, s in a.sessions { auth_session_free(s) }
	a.sessions.clear()
}

@[export: 'vinix_android_authenticator_read']
pub fn auth_read(handle voidptr, session &u64, timeout i32) i32 {
	if handle == unsafe { nil } || session == unsafe { nil } { return -1 }
	mut a := unsafe { &Authenticator(handle) }
	a.mutex.lock()
	defer { a.mutex.unlock() }
	if a.closed { return -1 }
	a.clear_current()
	for id, value in a.sessions {
		if time.sys_mono_now() - value.started >= 5 * time.minute {
			a.retire(id)
			unsafe { *session = id }
			return 2
		}
	}
	packet := a.stream.read(int(timeout)) or { a.disconnect(); return -1 }
	if !packet.available { return 0 }
	defer { unsafe { packet.body.free() } }
	if packet.header.kind == .dispatch {
		command := accountipc.decode_command(packet.header, packet.body) or { a.disconnect(); return -1 }
		if a.sessions.len >= accountipc.max_sessions || command.session in a.sessions
			|| command.request.operation != .add_account || command.request.account_type == none {
			accountipc.dispose_command(command)
			a.disconnect(); return -1
		}
		value := &AuthSession{command: command, started: time.sys_mono_now()}
		a.sessions[command.session] = value
		a.current = value
		unsafe { *session = command.session }
		return 1
	}
	if packet.header.kind == .cancel {
		event := accountipc.decode_event(packet.header, packet.body, true) or { a.disconnect(); return -1 }
		defer { accountipc.dispose_event(event) }
		value := a.sessions[event.id] or { a.disconnect(); return -1 }
		if !same_capability(event.capability, value.command.capability) { a.disconnect(); return -1 }
		a.retire(event.id)
		unsafe { *session = event.id }
		return 2
	}
	a.disconnect()
	return -1
}

@[export: 'vinix_android_authenticator_close']
pub fn auth_close(handle voidptr) {
	if handle == unsafe { nil } { return }
	mut a := unsafe { &Authenticator(handle) }
	a.mutex.lock()
	if a.released { a.mutex.unlock(); return }
	a.released = true
	a.disconnect()
	a.refs--
	dispose := a.refs == 0
	a.mutex.unlock()
	if dispose { auth_free(mut a) }
}

fn auth_free(mut a Authenticator) {
	a.mutex.destroy()
	unsafe { a.sessions.free(); free(a.stream); free(a) }
}

fn auth_current(handle voidptr) &AuthSession {
	if handle == unsafe { nil } { return unsafe { nil } }
	a := unsafe { &Authenticator(handle) }
	return a.current
}

@[export: 'vinix_android_authenticator_caller_uid']
pub fn auth_caller_uid(handle voidptr) u32 {
	s := auth_current(handle)
	return if s == unsafe { nil } { 0 } else { s.command.caller.uid }
}

@[export: 'vinix_android_authenticator_caller_pid']
pub fn auth_caller_pid(handle voidptr) i32 {
	s := auth_current(handle)
	return if s == unsafe { nil } { 0 } else { i32(s.command.caller.pid) }
}

@[export: 'vinix_android_authenticator_caller_package']
pub fn auth_caller_package(handle voidptr) &char {
	s := auth_current(handle)
	return if s == unsafe { nil } { unsafe { nil } } else { &char(s.command.caller.package_name.str) }
}

@[export: 'vinix_android_authenticator_account_type']
pub fn auth_account_type(handle voidptr) &char {
	s := auth_current(handle)
	if s == unsafe { nil } { return unsafe { nil } }
	if value := s.command.request.account_type { return &char(value.str) }
	return unsafe { nil }
}

@[export: 'vinix_android_authenticator_auth_token_type']
pub fn auth_token_type(handle voidptr) &char {
	s := auth_current(handle)
	if s == unsafe { nil } { return unsafe { nil } }
	if value := s.command.request.auth_token_type { return &char(value.str) }
	return unsafe { nil }
}

@[export: 'vinix_android_authenticator_feature_count']
pub fn auth_feature_count(handle voidptr) u32 {
	s := auth_current(handle)
	return if s == unsafe { nil } { 0 } else { u32(s.command.request.features.len) }
}

@[export: 'vinix_android_authenticator_feature']
pub fn auth_feature(handle voidptr, index u32) &char {
	s := auth_current(handle)
	if s == unsafe { nil } || index >= u32(s.command.request.features.len) { return unsafe { nil } }
	return &char(s.command.request.features[index].str)
}

// Identity options are synthesized from the root-forwarded kernel caller.
// App-provided duplicates are rejected by the request decoder.
fn auth_option(handle voidptr, index u32) ?nativeaccountauth.Option {
	s := auth_current(handle)
	if s == unsafe { nil } { return none }
	options := s.command.request.options
	if index < u32(options.len) { return options[index] }
	caller := s.command.caller
	return match int(index) - options.len {
		0 { nativeaccountauth.Option{'callerUid', nativeaccountauth.Scalar{kind: .int32, number: caller.uid}} }
		1 { nativeaccountauth.Option{'callerPid', nativeaccountauth.Scalar{kind: .int32, number: caller.pid}} }
		2 { nativeaccountauth.Option{'androidPackageName', nativeaccountauth.Scalar{kind: .text, text: caller.package_name}} }
		else { none }
	}
}

@[export: 'vinix_android_authenticator_count']
pub fn auth_count(handle voidptr) u32 {
	s := auth_current(handle)
	return if s == unsafe { nil } { 0 } else { u32(s.command.request.options.len + 3) }
}

@[export: 'vinix_android_authenticator_key']
pub fn auth_key(handle voidptr, index u32) &char {
	option := auth_option(handle,index) or { return unsafe { nil } }
	return &char(option.key.str)
}

@[export: 'vinix_android_authenticator_tag']
pub fn auth_tag(handle voidptr, index u32) u16 {
	option := auth_option(handle,index) or { return 65535 }
	return u16(option.value.kind)
}

@[export: 'vinix_android_authenticator_text']
pub fn auth_text(handle voidptr, index u32) &char {
	option := auth_option(handle,index) or { return unsafe { nil } }
	return if option.value.kind == .text { &char(option.value.text.str) } else { unsafe { nil } }
}

@[export: 'vinix_android_authenticator_number']
pub fn auth_number(handle voidptr, index u32) i64 {
	option := auth_option(handle,index) or { return 0 }
	return if option.value.kind == .boolean { i64(option.value.boolean) } else { option.value.number }
}

@[export: 'vinix_android_authenticator_response']
pub fn auth_response(handle voidptr, session u64, kind u16) voidptr {
	if handle == unsafe { nil } || kind !in [u16(1),u16(2),u16(5)] { return unsafe { nil } }
	mut a := unsafe { &Authenticator(handle) }
	a.mutex.lock()
	defer { a.mutex.unlock() }
	if a.closed { return unsafe { nil } }
	s := a.sessions[session] or { return unsafe { nil } }
	a.refs++
	return &AuthResponse{owner: a, session: session, capability: s.command.capability.clone(), kind: unsafe { accountipc.Kind(kind) }, options: []nativeaccountauth.Option{cap:32}}
}

fn auth_cstring(value &char) !string {
	if value == unsafe { nil } { return error('missing text') }
	unsafe {
		mut length := 0
		for length <= 4096 && value[length] != 0 { length++ }
		if length > 4096 { return error('text exceeds limit') }
		text := value.vstring_with_len(length)
		if !utf8.validate_str(text) { return error('invalid UTF-8') }
		return text.clone()
	}
}

@[export: 'vinix_android_authenticator_response_option']
pub fn auth_response_option(handle voidptr, key &char, tag u16, text &char, number i64) i32 {
	if handle == unsafe { nil } || tag > 4 { return -1 }
	mut b := unsafe { &AuthResponse(handle) }
	if b.kind == .continued || b.options.len >= 32 { return -1 }
	name := auth_cstring(key) or { return -1 }
	if name.len == 0 || b.options.any(it.key == name) { unsafe { name.free() }; return -1 }
	value := match tag {
		0 { nativeaccountauth.Scalar{kind: .null_value} }
		1 { nativeaccountauth.Scalar{kind: .text, text: auth_cstring(text) or { unsafe { name.free() }; return -1 }} }
		2 {
			if number !in [i64(0),i64(1)] { unsafe { name.free() }; return -1 }
			nativeaccountauth.Scalar{kind: .boolean, boolean: number == 1}
		}
		3 {
			if number < -2147483648 || number > 2147483647 { unsafe { name.free() }; return -1 }
			nativeaccountauth.Scalar{kind: .int32, number: number}
		}
		else { nativeaccountauth.Scalar{kind: .int64, number: number} }
	}
	b.options << nativeaccountauth.Option{name,value}
	return 0
}

@[export: 'vinix_android_authenticator_response_send']
pub fn auth_response_send(handle voidptr) i32 {
	if handle == unsafe { nil } { return -1 }
	b := unsafe { &AuthResponse(handle) }
	mut a := b.owner
	a.mutex.lock()
	defer { a.mutex.unlock() }
	if a.closed { return -1 }
	s := a.sessions[b.session] or { return -1 }
	if !same_capability(b.capability,s.command.capability) { return -1 }
	wire := accountipc.encode_event(accountipc.Event{kind:b.kind,id:b.session,capability:b.capability,options:b.options},true) or { return -1 }
	defer { unsafe { wire.free() } }
	a.stream.enqueue(wire) or { a.disconnect(); return -1 }
	if accountipc.terminal(b.kind) { a.retire(b.session) }
	return 0
}

@[export: 'vinix_android_authenticator_response_free']
pub fn auth_response_free(handle voidptr) {
	if handle == unsafe { nil } { return }
	mut b := unsafe { &AuthResponse(handle) }
	mut a := b.owner
	a.mutex.lock()
	a.refs--
	dispose := a.refs == 0
	a.mutex.unlock()
	unsafe { b.capability.free() }
	for item in b.options { unsafe { item.key.free(); item.value.text.free() } }
	unsafe { b.options.free(); free(b) }
	if dispose { auth_free(mut a) }
}
