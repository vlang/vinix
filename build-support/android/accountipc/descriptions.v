// SPDX-License-Identifier: GPL-2.0-or-later
module accountipc

import nativeaccountauth

// Only the root broker produces this snapshot, from its attested APK registry.
// Resource IDs retain all 32 bits; zero denotes an absent optional resource.
fn valid_authenticator(value nativeaccountauth.AuthenticatorDescription) ! {
	text(value.account_type, false)!
	text(value.package_name, false)!
	if value.account_type.len > 255 || value.package_name.len > 255 {
		return error('authenticator identity exceeds limit')
	}
}

fn authenticator_bytes(mut out []u8, values []nativeaccountauth.AuthenticatorDescription) ! {
	if values.len > 16 { return error('too many authenticator descriptions') }
	uint_bytes(mut out, u64(values.len), 2)
	mut types := map[string]bool{}
	defer { unsafe { types.free() } }
	for value in values {
		valid_authenticator(value)!
		if value.account_type in types { return error('duplicate authenticator type') }
		types[value.account_type] = true
		string_bytes(mut out, value.account_type)!
		string_bytes(mut out, value.package_name)!
		for resource in [value.label_id, value.icon_id, value.small_icon_id, value.account_preferences_id]! {
			uint_bytes(mut out, u64(resource), 4)
		}
		out << u8(value.custom_tokens)
	}
}

fn (mut r Reader) authenticator() !nativeaccountauth.AuthenticatorDescription {
	kind := r.string_value()!
	mut package := ''
	mut complete := false
	defer {
		if !complete { unsafe { kind.free(); package.free() } }
	}
	package = r.string_value()!
	value := nativeaccountauth.AuthenticatorDescription{
		account_type: kind
		package_name: package
		label_id: u32(r.number(4)!)
		icon_id: u32(r.number(4)!)
		small_icon_id: u32(r.number(4)!)
		account_preferences_id: u32(r.number(4)!)
		custom_tokens: r.authenticator_boolean()!
	}
	valid_authenticator(value)!
	complete = true
	return value
}

fn (mut r Reader) authenticator_boolean() !bool {
	flag := r.number(1)!
	if flag > 1 { return error('invalid authenticator customTokens boolean') }
	return flag == 1
}

fn (mut r Reader) authenticators() ![]nativeaccountauth.AuthenticatorDescription {
	count := r.number(2)!
	if count > 16 { return error('too many authenticator descriptions') }
	mut result := []nativeaccountauth.AuthenticatorDescription{cap: int(count)}
	mut complete := false
	defer {
		if !complete { nativeaccountauth.dispose_authenticator_descriptions(result) }
	}
	for _ in 0 .. int(count) {
		value := r.authenticator()!
		if result.any(it.account_type == value.account_type) {
			unsafe { value.account_type.free(); value.package_name.free() }
			return error('duplicate authenticator type')
		}
		result << value
	}
	complete = true
	return result
}
