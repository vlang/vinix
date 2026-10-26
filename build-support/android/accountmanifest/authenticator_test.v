// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import os

struct AuthTestAttribute {
	name  string
	text  string
	kind  u8 = 3
	value u32
	ns    string = android_namespace
}

struct AuthTestElement {
	name       string
	attributes []AuthTestAttribute
	children   []AuthTestElement
}

fn auth_test_u16(mut out []u8, value u16) { out << u8(value); out << u8(value >> 8) }
fn auth_test_u32(mut out []u8, value u32) { auth_test_u16(mut out, u16(value)); auth_test_u16(mut out, u16(value >> 16)) }

fn auth_test_chunk(kind u16, header u16, payload []u8) []u8 {
	mut out := []u8{}
	auth_test_u16(mut out, kind)
	auth_test_u16(mut out, header)
	auth_test_u32(mut out, u32(8 + payload.len))
	out << payload
	return out
}

fn auth_test_strings(element AuthTestElement, mut values []string) {
	if element.name !in values { values << element.name }
	for attribute in element.attributes {
		for value in [attribute.name, attribute.text, attribute.ns] {
			if value !in values { values << value }
		}
	}
	for child in element.children { auth_test_strings(child, mut values) }
}

fn auth_test_node(kind u16, payload []u8) []u8 {
	mut out := []u8{}
	auth_test_u32(mut out, 1)
	auth_test_u32(mut out, absent)
	out << payload
	return auth_test_chunk(kind, 16, out)
}

fn auth_test_element(element AuthTestElement, values []string, mut out []u8) {
	mut payload := []u8{}
	auth_test_u32(mut payload, absent)
	auth_test_u32(mut payload, u32(values.index(element.name)))
	for value in [u16(20), 20, u16(element.attributes.len), 0, 0, 0] { auth_test_u16(mut payload, value) }
	for attribute in element.attributes {
		auth_test_u32(mut payload, if attribute.ns == '' { absent } else { u32(values.index(attribute.ns)) })
		auth_test_u32(mut payload, u32(values.index(attribute.name)))
		auth_test_u32(mut payload, absent)
		auth_test_u16(mut payload, 8)
		payload << u8(0)
		payload << attribute.kind
		auth_test_u32(mut payload, if attribute.kind == 3 { u32(values.index(attribute.text)) } else { attribute.value })
	}
	out << auth_test_node(0x102, payload)
	for child in element.children { auth_test_element(child, values, mut out) }
	mut end := []u8{}
	auth_test_u32(mut end, absent)
	auth_test_u32(mut end, u32(values.index(element.name)))
	out << auth_test_node(0x103, end)
}

fn auth_test_xml(element AuthTestElement) []u8 {
	mut values := [android_namespace, 'android']
	auth_test_strings(element, mut values)
	mut strings := []u8{}
	mut offsets := []u8{}
	for value in values {
		assert value.len < 128
		auth_test_u32(mut offsets, u32(strings.len))
		strings << u8(value.len)
		strings << u8(value.len)
		strings << value.bytes()
		strings << u8(0)
	}
	for strings.len % 4 != 0 { strings << u8(0) }
	mut pool := []u8{}
	for value in [u32(values.len), 0, 0x100, u32(28 + offsets.len), 0] { auth_test_u32(mut pool, value) }
	pool << offsets
	pool << strings
	mut payload := auth_test_chunk(1, 28, pool)
	mut namespace := []u8{}
	auth_test_u32(mut namespace, 1)
	auth_test_u32(mut namespace, 0)
	payload << auth_test_node(0x100, namespace)
	auth_test_element(element, values, mut payload)
	payload << auth_test_node(0x101, namespace)
	return auth_test_chunk(3, 8, payload)
}

fn auth_test_manifest(service string, action string, metadata []AuthTestElement) []u8 {
	mut children := [AuthTestElement{name: 'intent-filter', children: [AuthTestElement{
		name: 'action', attributes: [AuthTestAttribute{name: 'name', text: action}]
	}]}]
	children << metadata
	return auth_test_xml(AuthTestElement{
		name: 'manifest'
		attributes: [AuthTestAttribute{name: 'package', text: 'com.example.auth', ns: ''}]
		children: [AuthTestElement{
			name: 'application'
			children: [AuthTestElement{
				name: 'service'
				attributes: [AuthTestAttribute{name: 'name', text: service}]
				children: children
			}]
		}]
	})
}

fn auth_test_metadata(value u32, kind u8) AuthTestElement {
	return AuthTestElement{name: 'meta-data', attributes: [
		AuthTestAttribute{name: 'name', text: 'android.accounts.AccountAuthenticator'},
		AuthTestAttribute{name: 'resource', kind: kind, value: value},
	]}
}

fn test_registered_service_action_and_exact_metadata_resource() {
	metadata := auth_test_metadata(0x7f190008, 1)
	data := auth_test_manifest('.Service', 'android.accounts.AccountAuthenticator', [metadata])
	assert authenticator_resource(data, 'com.example.auth', 'com.example.auth.Service')! == 0x7f190008
	for malformed in [
		auth_test_manifest('.Other', 'android.accounts.AccountAuthenticator', [metadata]),
		auth_test_manifest('.Service', 'com.example.Wrong', [metadata]),
		auth_test_manifest('.Service', 'android.accounts.AccountAuthenticator', []),
		auth_test_manifest('.Service', 'android.accounts.AccountAuthenticator', [metadata, metadata]),
		auth_test_manifest('.Service', 'android.accounts.AccountAuthenticator', [auth_test_metadata(0, 1)]),
		auth_test_manifest('.Service', 'android.accounts.AccountAuthenticator', [auth_test_metadata(0x7f190008, 0x10)]),
	] {
		mut rejected := false
		authenticator_resource(malformed, 'com.example.auth', 'com.example.auth.Service') or { rejected = true }
		assert rejected
	}
	mut rejected := false
	authenticator_resource(data, 'com.other.auth', 'com.example.auth.Service') or { rejected = true }
	assert rejected
}

fn test_authenticator_metadata_and_action_cannot_cross_service_boundaries() {
	metadata := auth_test_metadata(0x7f190008, 1)
	action := AuthTestElement{name: 'intent-filter', children: [AuthTestElement{
		name: 'action', attributes: [AuthTestAttribute{name: 'name', text: 'android.accounts.AccountAuthenticator'}]
	}]}
	for selected_children in [[metadata], [action]] {
		data := auth_test_xml(AuthTestElement{
			name: 'manifest'
			attributes: [AuthTestAttribute{name: 'package', text: 'com.example.auth', ns: ''}]
			children: [AuthTestElement{name: 'application', children: [
				AuthTestElement{name: 'service', attributes: [AuthTestAttribute{name: 'name', text: '.Service'}], children: selected_children},
				AuthTestElement{name: 'service', attributes: [AuthTestAttribute{name: 'name', text: '.Other'}], children: [metadata, action]},
			]}]
		})
		mut rejected := false
		authenticator_resource(data, 'com.example.auth', 'com.example.auth.Service') or { rejected = true }
		assert rejected
	}
}

fn test_compiled_authenticator_description_values_and_owned_strings() {
	attributes := [AuthTestAttribute{name: 'accountType', text: 'com.example.account'},
		AuthTestAttribute{name: 'label', kind: 1, value: 0x7f150001},
		AuthTestAttribute{name: 'icon', kind: 1, value: 0x7f080001},
		AuthTestAttribute{name: 'smallIcon', kind: 1, value: 0x7f080002},
		AuthTestAttribute{name: 'accountPreferences', kind: 1, value: 0x7f190002},
		AuthTestAttribute{name: 'customTokens', kind: 0x12, value: 0xffffffff}]
	data := auth_test_xml(AuthTestElement{name: 'account-authenticator', attributes: attributes})
	description := authenticator_description(data, 'com.example.auth', 'com.example.account')!
	assert description.account_type == 'com.example.account'
	assert description.package_name == 'com.example.auth'
	assert description.label_id == 0x7f150001 && description.icon_id == 0x7f080001
	assert description.small_icon_id == 0x7f080002 && description.account_preferences_id == 0x7f190002
	assert description.custom_tokens
	dispose_authenticator(description)
	minimal := auth_test_xml(AuthTestElement{name: 'account-authenticator', attributes: attributes[..1]})
	empty := authenticator_description(minimal, 'com.example.auth', 'com.example.account')!
	assert !empty.custom_tokens && empty.label_id == 0 && empty.account_preferences_id == 0
	dispose_authenticator(empty)
}

fn test_authenticator_rejects_forged_type_and_typed_metadata() {
	identity := AuthTestAttribute{name: 'accountType', text: 'com.example.account'}
	for root in [
		AuthTestElement{name: 'other', attributes: [identity]},
		AuthTestElement{name: 'account-authenticator', attributes: [AuthTestAttribute{name: 'accountType', text: 'com.other.account'}]},
		AuthTestElement{name: 'account-authenticator', attributes: [AuthTestAttribute{name: 'accountType', text: 'com.example.account', ns: ''}]},
		AuthTestElement{name: 'account-authenticator', attributes: [identity, identity]},
		AuthTestElement{name: 'account-authenticator', attributes: [identity, AuthTestAttribute{name: 'customTokens', kind: 0x10, value: 1}]},
		AuthTestElement{name: 'account-authenticator', attributes: [identity, AuthTestAttribute{name: 'icon', text: 'fake-icon'}]},
		AuthTestElement{name: 'account-authenticator', attributes: [identity], children: [AuthTestElement{name: 'account-authenticator', attributes: [identity]}]},
	] {
		mut rejected := false
		authenticator_description(auth_test_xml(root), 'com.example.auth', 'com.example.account') or { rejected = true }
		assert rejected
	}
}

fn test_authenticator_rejects_truncated_documents_and_malformed_suffix() {
	data := auth_test_xml(AuthTestElement{name: 'account-authenticator', attributes: [AuthTestAttribute{name: 'accountType', text: 'com.example.account'}]})
	for length in 0 .. data.len {
		mut rejected := false
		authenticator_description(data[..length], 'com.example.auth', 'com.example.account') or { rejected = true }
		assert rejected
		if length >= 8 {
			mut truncated := data[..length].clone()
			for byte in 0 .. 4 { truncated[4 + byte] = u8(u32(length) >> u32(byte * 8)) }
			mut suffix_rejected := false
			authenticator_description(truncated, 'com.example.auth', 'com.example.account') or { suffix_rejected = true }
			assert suffix_rejected
			unsafe { truncated.free() }
		}
	}
	mut malformed := data.clone()
	malformed[malformed.len - 1] = 0xff
	mut rejected := false
	authenticator_description(malformed, 'com.example.auth', 'com.example.account') or { rejected = true }
	assert rejected
}

// Optional retained production-APK regression. The path is external evidence;
// the expected values are assertions in a test, never a runtime provider stub.
fn test_retained_google_authenticator_metadata_when_apk_is_supplied() {
	apk := os.getenv('VINIX_AUTHENTICATOR_TEST_APK')
	if apk == '' { return }
	description := read_authenticator(apk, 'com.google.android.gms',
		'com.google.android.gms.auth.account.authenticator.GoogleAccountAuthenticatorService', 'com.google')!
	assert description.account_type == 'com.google' && description.package_name == 'com.google.android.gms'
	assert description.label_id == 0x7f1501f8 && description.icon_id == 0x7f080239
	assert description.small_icon_id == 0x7f08023a && description.account_preferences_id == 0
	assert description.custom_tokens
	dispose_authenticator(description)
}
