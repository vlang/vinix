// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

import accountmanifest

pub struct AuthenticatorDescription {
pub:
	account_type           string
	package_name           string
	label_id               u32
	icon_id                u32
	small_icon_id          u32
	account_preferences_id u32
	custom_tokens          bool
}

// Both strings and the array are owned by the producer, never registry borrows.
// This also disposes descriptions decoded independently from account IPC.
pub fn dispose_authenticator_descriptions(values []AuthenticatorDescription) {
	for value in values { unsafe { value.account_type.free(); value.package_name.free() } }
	unsafe { values.free() }
}

// Enumerate only the selected registered provider: this broker dispatches to
// that provider, not every package authorized to connect as an ordinary client.
// Account types remain administrator-attested; APK XML supplies presentation
// metadata only after its service/action/type match that attestation. The caller
// owns the resulting array and strings and must dispose them after serialization.
pub fn (registry Registry) authenticator_descriptions(selected Entry) ![]AuthenticatorDescription {
	entry := registry.verify_launch(selected.apk, selected.uid, selected.gid)!
	if entry != selected { return error('selected authenticator entry does not match registry snapshot') }
	mut values := []AuthenticatorDescription{cap: entry.services.len}
	mut success := false
	defer { if !success { dispose_authenticator_descriptions(values) } }
	for service in entry.services {
		if service.action != 'android.accounts.AccountAuthenticator' || service.account_type == '' { continue }
		parsed := accountmanifest.read_authenticator(entry.apk, entry.package_name, service.class_name, service.account_type)!
		for previous in values {
			if previous.account_type == parsed.account_type {
				accountmanifest.dispose_authenticator(parsed)
				return error('registered authenticator account type is ambiguous')
			}
		}
		// Transfer the parser's independently owned strings into the wire model.
		values << AuthenticatorDescription{parsed.account_type, parsed.package_name,
			parsed.label_id, parsed.icon_id, parsed.small_icon_id, parsed.account_preferences_id, parsed.custom_tokens}
	}
	// Parsing reopens only root-protected input paths. Recheck the pin afterwards
	// as well, so an administrator replacement cannot silently change metadata.
	registry.verify_launch(selected.apk, selected.uid, selected.gid)!
	success = true
	return values
}
