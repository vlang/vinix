// SPDX-License-Identifier: GPL-2.0-or-later
module accountipc

// The service leg names a retained object in the selected service process.
// The client leg carries only a separately minted broker redemption ticket.
// Java objects, PendingIntent records and Parcel object indexes stay local.
pub struct Interaction {
pub:
	handle         []u8
	target_package string
	target_class   string
}

pub struct Launch {
pub:
	session     u64
	capability  []u8
	interaction Interaction
}

fn empty_interaction(value Interaction) bool {
	return value.handle.len == 0 && value.target_package.len == 0 && value.target_class.len == 0
}

fn nonzero_handle(value []u8) bool {
	if value.len != 32 { return false }
	mut any := u8(0)
	for byte in value { any |= byte }
	return any != 0
}

fn interaction_bytes(mut body []u8, value Interaction, service bool) ! {
	if !nonzero_handle(value.handle) { return error('invalid account interaction handle') }
	body << value.handle
	if service {
		text(value.target_package, false)!
		text(value.target_class, false)!
		string_bytes(mut body, value.target_package)!
		string_bytes(mut body, value.target_class)!
	} else if value.target_package.len != 0 || value.target_class.len != 0 {
		return error('public account interaction must contain only a ticket')
	}
}

fn (mut r Reader) interaction(service bool) !Interaction {
	handle := r.take(32)!
	mut package_name := ''
	mut class_name := ''
	mut complete := false
	defer {
		if !complete { dispose_interaction(Interaction{handle, package_name, class_name}) }
	}
	if !nonzero_handle(handle) { return error('invalid account interaction handle') }
	if service {
		package_name = r.string_value()!
		class_name = r.string_value()!
		text(package_name, false)!
		text(class_name, false)!
	}
	complete = true
	return Interaction{handle, package_name, class_name}
}

pub fn encode_launch(value Launch) ![]u8 {
	if value.capability.len != 32 { return error('invalid account launch capability') }
	mut body := []u8{cap: max_payload}
	defer { unsafe { body.free() } }
	body << value.capability
	interaction_bytes(mut body, value.interaction, true)!
	return frame(.launch, value.session, body)
}

pub fn decode_launch(header Header, bytes []u8) !Launch {
	if header.kind != .launch || header.session == 0 || bytes.len != header.length || bytes.len > max_payload {
		return error('invalid account launch command')
	}
	mut reader := Reader{ bytes: bytes }
	capability := reader.take(32)!
	mut interaction := Interaction{}
	mut complete := false
	defer {
		if !complete {
			unsafe { capability.free() }
			dispose_interaction(interaction)
		}
	}
	interaction = reader.interaction(true)!
	if reader.index != bytes.len { return error('trailing account launch fields') }
	complete = true
	return Launch{header.session, capability, interaction}
}

pub fn dispose_interaction(value Interaction) {
	unsafe {
		value.handle.free()
		value.target_package.free()
		value.target_class.free()
	}
}

pub fn dispose_launch(value Launch) {
	unsafe { value.capability.free() }
	dispose_interaction(value.interaction)
}
