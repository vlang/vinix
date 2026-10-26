// SPDX-License-Identifier: GPL-2.0-or-later
// Typed account events and root-authorized authenticator commands. No Parcel
// object indexes or process-local pointers are serialized.
module accountipc

import encoding.utf8
import nativeaccountauth

pub const header_size = 20
pub const max_payload = 128 * 1024
pub const max_sessions = 32

pub enum Kind {
	result      = 1
	failure     = 2
	accounts    = 3
	interaction = 4
	continued   = 5
	dispatch    = 6
	cancel      = 7
	launch      = 8
}

pub struct Header {
pub:
	kind    Kind
	session u64
	length  int
}

pub struct Account {
pub:
	name         string
	account_type string
}

pub struct Event {
pub:
	kind        Kind
	id          u64
	capability  []u8
	options     []nativeaccountauth.Option
	accounts    []Account
	interaction Interaction
}

pub struct Command {
pub:
	session    u64
	capability []u8
	caller     nativeaccountauth.Caller
	request    nativeaccountauth.Request
}

fn text(value string, empty bool) ! {
	if value.len > 4096 || (!empty && value.len == 0) || value.contains('\x00') || !utf8.validate_str(value) {
		return error('invalid account IPC text')
	}
}

fn uint_bytes(mut out []u8, value u64, size int) {
	for index in 0 .. size { out << u8(value >> ((size - index - 1) * 8)) }
}

fn string_bytes(mut out []u8, value string) ! {
	text(value, true)!
	uint_bytes(mut out, u64(value.len), 4)
	out << unsafe { value.str.vbytes(value.len) }
}

struct Reader {
	bytes []u8
mut:
	index int
}

fn (mut r Reader) number(size int) !u64 {
	if size < 1 || size > 8 || r.index > r.bytes.len - size {
		return error('truncated account IPC number')
	}
	mut value := u64(0)
	for _ in 0 .. size {
		value = (value << 8) | u64(r.bytes[r.index])
		r.index++
	}
	return value
}

fn (mut r Reader) take(size int) ![]u8 {
	if size < 0 || r.index > r.bytes.len - size { return error('truncated account IPC bytes') }
	result := r.bytes[r.index..r.index + size].clone()
	r.index += size
	return result
}

fn (mut r Reader) string_value() !string {
	length := r.number(4)!
	if length > 4096 { return error('account IPC string exceeds limit') }
	if r.index > r.bytes.len - int(length) { return error('truncated account IPC text') }
	value := r.bytes[r.index..r.index + int(length)].bytestr()
	r.index += int(length)
	text(value, true) or {
		unsafe { value.free() }
		return err
	}
	return value
}

fn options_bytes(mut out []u8, options []nativeaccountauth.Option) ! {
	if options.len > 32 { return error('too many account IPC options') }
	out << u8(options.len)
	mut keys := map[string]bool{}
	defer { unsafe { keys.free() } }
	for option in options {
		text(option.key, false)!
		if option.key in keys { return error('duplicate account IPC option') }
		keys[option.key] = true
		string_bytes(mut out, option.key)!
		out << u8(option.value.kind)
		match option.value.kind {
			.null_value {}
			.text { string_bytes(mut out, option.value.text)! }
			.boolean { out << u8(option.value.boolean) }
			.int32 {
				if option.value.number < -2147483648 || option.value.number > 2147483647 {
					return error('account IPC int32 overflow')
				}
				uint_bytes(mut out, u64(u32(option.value.number)), 4)
			}
			.int64 { uint_bytes(mut out, u64(option.value.number), 8) }
		}
	}
	if out.len > max_payload { return error('account IPC payload exceeds limit') }
}

fn (mut r Reader) options() ![]nativeaccountauth.Option {
	count := r.number(1)!
	if count > 32 { return error('too many account IPC options') }
	mut result := []nativeaccountauth.Option{cap: 32}
	mut keys := map[string]bool{}
	mut complete := false
	defer {
		unsafe { keys.free() }
		if !complete { nativeaccountauth.dispose_options(result) }
	}
	for _ in 0 .. int(count) {
		key := r.string_value()!
		text(key, false) or {
			unsafe { key.free() }
			return err
		}
		if key in keys {
			unsafe { key.free() }
			return error('duplicate account IPC option')
		}
		keys[key] = true
		value := r.scalar() or {
			unsafe { key.free() }
			return err
		}
		result << nativeaccountauth.Option{key, value}
	}
	complete = true
	return result
}

fn (mut r Reader) scalar() !nativeaccountauth.Scalar {
	tag := r.number(1)!
	return match tag {
		0 { nativeaccountauth.Scalar{ kind: .null_value } }
		1 { nativeaccountauth.Scalar{ kind: .text, text: r.string_value()! } }
		2 {
			flag := r.number(1)!
			if flag > 1 { return error('invalid account IPC boolean') }
			nativeaccountauth.Scalar{ kind: .boolean, boolean: flag == 1 }
		}
		3 { nativeaccountauth.Scalar{ kind: .int32, number: i64(i32(r.number(4)!)) } }
		4 { nativeaccountauth.Scalar{ kind: .int64, number: i64(r.number(8)!) } }
		else { return error('unknown account IPC scalar') }
	}
}

pub fn encode_header(header Header) ![]u8 {
	if header.kind !in [.result, .failure, .accounts, .interaction, .continued, .dispatch, .cancel,
		.launch]
		|| header.session == 0 || header.length < 0 || header.length > max_payload {
		return error('invalid account IPC header')
	}
	mut bytes := []u8{cap: header_size}
	bytes << u8(`V`)
	bytes << u8(`X`)
	bytes << u8(`A`)
	bytes << u8(`R`)
	uint_bytes(mut bytes, 1, 2)
	uint_bytes(mut bytes, u64(header.kind), 2)
	uint_bytes(mut bytes, header.session, 8)
	uint_bytes(mut bytes, u64(header.length), 4)
	return bytes
}

pub fn decode_header(bytes []u8) !Header {
	if bytes.len != header_size || bytes[0] != `V` || bytes[1] != `X` || bytes[2] != `A` || bytes[3] != `R` {
		return error('invalid account IPC header magic')
	}
	mut r := Reader{ bytes: bytes, index: 4 }
	if r.number(2)! != 1 { return error('unsupported account IPC version') }
	kind := r.number(2)!
	if kind < 1 || kind > 8 { return error('unknown account IPC event kind') }
	session := r.number(8)!
	length := r.number(4)!
	if session == 0 || length > max_payload { return error('invalid account IPC bound') }
	return Header{unsafe { Kind(kind) }, session, int(length)}
}

fn frame(kind Kind, id u64, payload []u8) ![]u8 {
	header := encode_header(Header{kind, id, payload.len})!
	defer { unsafe { header.free() } }
	mut result := []u8{cap: header_size + payload.len}
	result << header
	result << payload
	return result
}

pub fn terminal(kind Kind) bool { return kind in [.result, .failure, .accounts] }

pub fn encode_event(event Event, service bool) ![]u8 {
	if event.kind !in [.result, .failure, .accounts, .interaction, .continued, .cancel] {
		return error('not an account result event')
	}
	if event.kind != .interaction && !empty_interaction(event.interaction) {
		return error('unexpected account interaction fields')
	}
	mut body := []u8{cap: max_payload}
	defer { unsafe { body.free() } }
	if service {
		if event.capability.len != 32 { return error('invalid account response capability') }
		body << event.capability
	} else if event.capability.len != 0 {
		return error('client event must not expose response capability')
	}
	match event.kind {
		.result, .failure {
			if event.accounts.len != 0 { return error('unexpected account event snapshot') }
			options_bytes(mut body, event.options)!
		}
		.accounts {
			if event.accounts.len > 256 || event.options.len != 0 {
				return error('invalid account snapshot')
			}
			uint_bytes(mut body, u64(event.accounts.len), 2)
			mut names := map[string]bool{}
			defer { unsafe { names.free() } }
			for account in event.accounts {
				text(account.name, false)!
				text(account.account_type, false)!
				key := account.name + '\x00' + account.account_type
				if key in names {
					unsafe { key.free() }
					return error('duplicate account snapshot entry')
				}
				names[key] = true
				unsafe { key.free() }
				string_bytes(mut body, account.name)!
				string_bytes(mut body, account.account_type)!
			}
		}
		.interaction {
			if event.options.len != 0 || event.accounts.len != 0 {
				return error('unexpected account interaction result fields')
			}
			interaction_bytes(mut body, event.interaction, service)!
		}
		.continued, .cancel {
			if event.options.len != 0 || event.accounts.len != 0 {
				return error('unexpected account event fields')
			}
		}
		else { return error('invalid account event') }
	}
	return frame(event.kind, event.id, body)
}

pub fn decode_event(header Header, bytes []u8, service bool) !Event {
	if bytes.len != header.length || bytes.len > max_payload || header.session == 0
		|| header.kind !in [.result, .failure, .accounts, .interaction, .continued, .cancel] {
		return error('invalid account event body')
	}
	mut r := Reader{ bytes: bytes }
	capability := if service { r.take(32)! } else { []u8{} }
	mut options := []nativeaccountauth.Option{}
	mut accounts := []Account{cap: 256}
	mut interaction := Interaction{}
	mut complete := false
	defer {
		if !complete {
			dispose_event(Event{ capability: capability, options: options, accounts: accounts, interaction: interaction })
		}
	}
	match header.kind {
		.result, .failure { options = r.options()! }
		.accounts {
			count := r.number(2)!
			if count > 256 { return error('account snapshot exceeds limit') }
			mut names := map[string]bool{}
			defer { unsafe { names.free() } }
			for _ in 0 .. int(count) {
				name := r.string_value()!
				account_type := r.string_value() or {
					unsafe { name.free() }
					return err
				}
				text(name, false) or {
					unsafe {
						name.free()
						account_type.free()
					}
					return err
				}
				text(account_type, false) or {
					unsafe {
						name.free()
						account_type.free()
					}
					return err
				}
				key := name + '\x00' + account_type
				if key in names {
					unsafe {
						key.free()
						name.free()
						account_type.free()
					}
					return error('duplicate account snapshot entry')
				}
				names[key] = true
				unsafe { key.free() }
				accounts << Account{name, account_type}
			}
		}
		.interaction { interaction = r.interaction(service)! }
		.continued, .cancel {}
		else { return error('invalid account event kind') }
	}
	if r.index != bytes.len { return error('trailing account event fields') }
	complete = true
	return Event{ kind: header.kind, id: header.session, capability: capability, options: options, accounts: accounts, interaction: interaction }
}

fn valid_caller(caller nativeaccountauth.Caller) ! {
	if caller.uid < 10000 || caller.uid > 19999 || caller.gid < 10000 || caller.gid > 19999 || caller.pid <= 0 {
		return error('invalid root-forwarded account caller')
	}
	text(caller.package_name, false)!
	for hash in [caller.apk_sha256, caller.certificate_sha256]! {
		if hash.len != 64 {
			return error('invalid root-forwarded APK identity')
		}
		for value in hash {
			if !((value >= `0` && value <= `9`) || (value >= `a` && value <= `f`)) {
				return error('invalid root-forwarded APK identity')
			}
		}
	}
}

pub fn encode_command(command Command) ![]u8 {
	valid_caller(command.caller)!
	if command.capability.len != 32 { return error('invalid account session capability') }
	request := nativeaccountauth.encode_request(command.request)!
	defer { unsafe { request.free() } }
	mut body := []u8{cap: max_payload}
	defer { unsafe { body.free() } }
	body << command.capability
	uint_bytes(mut body, command.caller.uid, 4)
	uint_bytes(mut body, command.caller.gid, 4)
	uint_bytes(mut body, u64(command.caller.pid), 4)
	for value in [command.caller.package_name, command.caller.apk_sha256,
		command.caller.certificate_sha256]! {
		string_bytes(mut body, value)!
	}
	body << request
	return frame(.dispatch, command.session, body)
}

pub fn decode_command(header Header, bytes []u8) !Command {
	if header.kind != .dispatch || bytes.len != header.length || bytes.len > max_payload {
		return error('invalid authenticator command')
	}
	mut r := Reader{ bytes: bytes }
	capability := r.take(32)!
	mut caller := nativeaccountauth.Caller{}
	mut complete := false
	defer {
		if !complete {
			unsafe {
				capability.free()
				caller.package_name.free()
				caller.apk_sha256.free()
				caller.certificate_sha256.free()
			}
		}
	}
	uid := u32(r.number(4)!)
	gid := u32(r.number(4)!)
	pid := int(r.number(4)!)
	package_name := r.string_value()!
	caller = nativeaccountauth.Caller{ package_name: package_name, uid: uid, gid: gid, pid: pid }
	apk := r.string_value()!
	caller = nativeaccountauth.Caller{ ...caller, apk_sha256: apk }
	certificate := r.string_value()!
	caller = nativeaccountauth.Caller{ ...caller, certificate_sha256: certificate }
	valid_caller(caller)!
	request := nativeaccountauth.decode_request_bytes(bytes[r.index..])!
	complete = true
	return Command{header.session, capability, caller, request}
}

pub fn failure(id u64, code int, message string) Event {
	return Event{
		kind:    .failure
		id:      id
		options: [
			nativeaccountauth.Option{'errorCode', nativeaccountauth.Scalar{ kind: .int32, number: code }},
			nativeaccountauth.Option{'errorMessage', nativeaccountauth.Scalar{ kind: .text, text: message }},
		]
	}
}

// Only decoder results own these values. Encoding borrows the input object.
pub fn dispose_event(event Event) {
	unsafe { event.capability.free() }
	nativeaccountauth.dispose_options(event.options)
	for account in event.accounts {
		unsafe {
			account.name.free()
			account.account_type.free()
		}
	}
	unsafe { event.accounts.free() }
	dispose_interaction(event.interaction)
}

pub fn dispose_command(command Command) {
	unsafe {
		command.capability.free()
		command.caller.package_name.free()
		command.caller.apk_sha256.free()
		command.caller.certificate_sha256.free()
	}
	nativeaccountauth.dispose_request(command.request)
}
