// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import os

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

// Descriptions own their two strings. No document or ZIP storage is retained.
pub fn dispose_authenticator(description AuthenticatorDescription) {
	unsafe { description.account_type.free(); description.package_name.free() }
}

struct AuthAttribute {
	namespace string
	name      string
	text      string
	kind      u8
	value     u32
}

struct AuthElement {
	name       XmlName
	depth      int
	parent     int
	attributes []AuthAttribute
}

struct AuthDocument {
mut:
	pool     []string
	elements []AuthElement
}

fn (document AuthDocument) dispose() {
	for element in document.elements { unsafe { element.attributes.free() } }
	unsafe { document.elements.free(); document.pool.free() }
}

fn (element AuthElement) attribute(namespace string, name string) ?AuthAttribute {
	for attribute in element.attributes {
		if attribute.namespace == namespace && attribute.name == name { return attribute }
	}
	return none
}

fn auth_attributes(chunk []u8, pool []string, namespaces []Namespace, resources []u32) ![]AuthAttribute {
	start, stride, count := int(le16(chunk, 24)), int(le16(chunk, 26)), int(le16(chunk, 28))
	if start < 20 || stride != 20 || count > 4096 || 16 + start > chunk.len
		|| count > (chunk.len - 16 - start) / stride { return error('invalid authenticator attribute bounds') }
	for at := 30; at <= 34; at += 2 {
		if int(le16(chunk, at)) > count { return error('invalid authenticator attribute index') }
	}
	mut attributes := []AuthAttribute{cap: count}
	mut success := false
	defer { if !success { unsafe { attributes.free() } } }
	for i in 0 .. count {
		at := 16 + start + i * stride
		namespace := pool_value(pool, le32(chunk, at), true)!
		index := le32(chunk, at + 4)
		name := pool_value(pool, index, false)!
		if name == '' || !namespace_bound(namespaces, pool, namespace) {
			return error('unbound authenticator attribute namespace')
		}
		for previous in attributes {
			if previous.namespace == namespace && previous.name == name { return error('duplicate authenticator attribute') }
		}
		if le16(chunk, at + 12) != 8 || chunk[at + 14] != 0 { return error('invalid authenticator typed value') }
		kind, value := chunk[at + 15], le32(chunk, at + 16)
		if kind > 8 && !(kind >= 0x10 && kind <= 0x1f) { return error('unsupported authenticator typed value') }
		raw := le32(chunk, at + 8)
		mut text := pool_value(pool, raw, true)!
		if kind == 3 {
			typed := pool_value(pool, value, false)!
			if raw != absent && text != typed { return error('inconsistent authenticator string attribute') }
			text = typed
		}
		if namespace == android_namespace {
			expected := match name {
				'name' { u32(0x01010003) }
				'resource' { u32(0x01010025) }
				'label' { u32(0x01010001) }
				'icon' { u32(0x01010002) }
				'accountType' { u32(0x0101028f) }
				'smallIcon' { u32(0x0101029e) }
				'accountPreferences' { u32(0x0101029f) }
				'customTokens' { u32(0x0101033b) }
				else { u32(0) }
			}
			if expected != 0 && int(index) < resources.len && resources[int(index)] != 0
				&& resources[int(index)] != expected { return error('authenticator attribute resource ID mismatch') }
		}
		attributes << AuthAttribute{namespace, name, text, kind, value}
	}
	success = true
	return attributes
}

// All returned names/values borrow the document pool. Parse the entire suffix
// before accepting any service or metadata; malformed trailing nodes fail closed.
fn auth_document(data []u8) !AuthDocument {
	if data.len < 8 || data.len > manifest_limit || le16(data, 0) != 3
		|| le16(data, 2) != 8 || int(le32(data, 4)) != data.len { return error('invalid authenticator binary XML') }
	mut document := AuthDocument{}
	mut success := false
	defer { if !success { document.dispose() } }
	mut resources := []u32{}
	mut stack := []int{}
	mut namespaces := []Namespace{}
	defer { unsafe { resources.free(); stack.free(); namespaces.free() } }
	mut has_pool := false
	mut has_resources := false
	mut nodes_started := false
	mut roots := 0
	mut cursor := 8
	for cursor < data.len {
		if data.len - cursor < 8 { return error('truncated authenticator XML chunk') }
		kind, header := le16(data, cursor), int(le16(data, cursor + 2))
		size := int(le32(data, cursor + 4))
		if header < 8 || size < header || size > data.len - cursor || size % 4 != 0 {
			return error('invalid authenticator XML chunk bounds')
		}
		chunk := data[cursor..cursor + size]
		if kind == 1 {
			if has_pool || nodes_started || has_resources { return error('misplaced authenticator string pool') }
			document.pool = string_pool(chunk, header)!
			has_pool = true
		} else if kind == 0x180 {
			if !has_pool || has_resources || nodes_started || header != 8 || (size - 8) / 4 > document.pool.len {
				return error('invalid authenticator resource map')
			}
			for at := 8; at < size; at += 4 { resources << le32(chunk, at) }
			has_resources = true
		} else {
			if !has_pool || header != 16 || size < 24 { return error('invalid authenticator XML node') }
			_ := pool_value(document.pool, le32(chunk, 12), true)!
			nodes_started = true
			match kind {
				0x100, 0x101 {
					if size != 24 { return error('invalid authenticator namespace node') }
					prefix, uri := le32(chunk, 16), le32(chunk, 20)
					_ := pool_value(document.pool, prefix, true)!
					if pool_value(document.pool, uri, false)! == '' { return error('empty authenticator namespace URI') }
					if kind == 0x100 {
						if namespaces.len >= 256 || roots > 0 && stack.len == 0 { return error('misplaced authenticator namespace') }
						for scope in namespaces {
							if scope.depth == stack.len && scope.prefix == prefix { return error('duplicate authenticator namespace prefix') }
						}
						namespaces << Namespace{prefix, uri, stack.len}
					} else {
						if namespaces.len == 0 { return error('unmatched authenticator namespace end') }
						last := namespaces.last()
						if last.prefix != prefix || last.uri != uri || last.depth != stack.len { return error('mismatched authenticator namespace end') }
						namespaces.delete_last()
					}
				}
				0x102 {
					if size < 36 || stack.len >= 256 || document.elements.len >= 65536 { return error('invalid authenticator element start') }
					name := XmlName{pool_value(document.pool, le32(chunk, 16), true)!, pool_value(document.pool, le32(chunk, 20), false)!}
					if name.name == '' || !namespace_bound(namespaces, document.pool, name.namespace) { return error('unbound authenticator element namespace') }
					if stack.len == 0 {
						roots++
						if roots != 1 { return error('duplicate authenticator XML root') }
					}
					attributes := auth_attributes(chunk, document.pool, namespaces, resources)!
					parent := if stack.len > 0 { stack.last() } else { -1 }
					document.elements << AuthElement{name, stack.len, parent, attributes}
					stack << document.elements.len - 1
				}
				0x103 {
					if size != 24 || stack.len == 0 { return error('unmatched authenticator element end') }
					name := XmlName{pool_value(document.pool, le32(chunk, 16), true)!, pool_value(document.pool, le32(chunk, 20), false)!}
					if document.elements[stack.last()].name != name { return error('mismatched authenticator element end') }
					stack.delete_last()
					for scope in namespaces {
						if scope.depth > stack.len { return error('unclosed authenticator namespace scope') }
					}
				}
				0x104 {
					if size != 28 || stack.len == 0 || le16(chunk, 20) != 8 || chunk[22] != 0 { return error('invalid authenticator text node') }
					_ := pool_value(document.pool, le32(chunk, 16), false)!
					if chunk[23] > 8 && !(chunk[23] >= 0x10 && chunk[23] <= 0x1f) { return error('unsupported authenticator text value') }
					if chunk[23] == 3 { _ := pool_value(document.pool, le32(chunk, 24), false)! }
				}
				else { return error('unsupported authenticator XML chunk') }
			}
		}
		cursor += size
	}
	if roots != 1 || stack.len != 0 || namespaces.len != 0 { return error('incomplete authenticator XML document') }
	success = true
	return document
}

fn auth_literal(element AuthElement, namespace string, name string) !string {
	attribute := element.attribute(namespace, name) or { return error('missing authenticator identity attribute') }
	if attribute.kind != 3 || attribute.text == '' || attribute.text.len > 4096 { return error('authenticator identity must be a literal string') }
	return attribute.text
}

// Always return an owned name, including when the manifest already uses a FQN.
// Validate segments in place to avoid allocating split strings on every query.
fn auth_class_name(value string, package_name string) !string {
	full := if value.starts_with('.') { package_name + value }
		else if !value.contains('.') { package_name + '.' + value }
		else { value.clone() }
	mut accepted := false
	defer { if !accepted { unsafe { full.free() } } }
	if full.len == 0 || full.len > 2048 { return error('invalid authenticator service class name') }
	mut first := true
	for c in full {
		if c == `.` {
			if first { return error('invalid authenticator service class name') }
			first = true
		} else {
			if !(c.is_letter() || c in [`_`, `$`] || (!first && c.is_digit())) {
				return error('invalid authenticator service class name')
			}
			first = false
		}
	}
	if first { return error('invalid authenticator service class name') }
	accepted = true
	return full
}

fn authenticator_resource(data []u8, package_name string, service_name string) !u32 {
	document := auth_document(data)!
	defer { document.dispose() }
	if document.elements.len == 0 || document.elements[0].name != XmlName{'', 'manifest'}
		|| auth_literal(document.elements[0], '', 'package')! != package_name { return error('authenticator manifest package mismatch') }
	target := auth_class_name(service_name, package_name)!
	defer { unsafe { target.free() } }
	mut applications := 0
	mut service_count := 0
	mut selected_service := -1
	mut action_found := false
	mut resource := u32(0)
	for index in 1 .. document.elements.len {
		element := document.elements[index]
		if element.parent == 0 && element.name == XmlName{'', 'application'} {
			applications++
			if enabled := element.attribute(android_namespace, 'enabled') {
				if enabled.kind != 0x12 || enabled.value == 0 { return error('authenticator application is disabled or unresolved') }
			}
		}
		if element.depth == 2 && element.name == XmlName{'', 'service'}
			&& document.elements[element.parent].name == XmlName{'', 'application'} {
			declared := auth_class_name(auth_literal(element, android_namespace, 'name')!, package_name)!
			matches := declared == target
			unsafe { declared.free() }
			if !matches { continue }
			service_count++
			if enabled := element.attribute(android_namespace, 'enabled') {
				if enabled.kind != 0x12 || enabled.value == 0 { return error('authenticator service is disabled or unresolved') }
			}
			selected_service = index
		}
		if selected_service < 0 { continue }
		if element.depth == 4 && element.name == XmlName{'', 'action'}
			&& document.elements[element.parent].name == XmlName{'', 'intent-filter'}
			&& document.elements[element.parent].parent == selected_service {
			if auth_literal(element, android_namespace, 'name')! == 'android.accounts.AccountAuthenticator' { action_found = true }
		}
		if element.parent == selected_service && element.name == XmlName{'', 'meta-data'}
			&& auth_literal(element, android_namespace, 'name')! == 'android.accounts.AccountAuthenticator' {
			if resource != 0 { return error('duplicate authenticator metadata') }
			attribute := element.attribute(android_namespace, 'resource') or { return error('missing authenticator XML resource') }
			if attribute.kind != 1 || attribute.value == 0 { return error('authenticator metadata must reference XML') }
			resource = attribute.value
		}
	}
	if applications != 1 || service_count != 1 || !action_found || resource == 0 { return error('registered authenticator service metadata is absent or ambiguous') }
	return resource
}

fn auth_resource_id(element AuthElement, name string) !u32 {
	attribute := element.attribute(android_namespace, name) or { return u32(0) }
	if attribute.kind != 1 || attribute.value == 0 { return error('authenticator presentation attribute must be a resource reference') }
	return attribute.value
}

fn authenticator_description(data []u8, package_name string, expected_type string) !AuthenticatorDescription {
	document := auth_document(data)!
	defer { document.dispose() }
	if document.elements.len != 1 || document.elements[0].name != XmlName{'', 'account-authenticator'} { return error('invalid account-authenticator root') }
	root := document.elements[0]
	account_type := auth_literal(root, android_namespace, 'accountType')!
	if account_type != expected_type { return error('authenticator account type does not match registry attestation') }
	label_id := auth_resource_id(root, 'label')!
	icon_id := auth_resource_id(root, 'icon')!
	small_icon_id := auth_resource_id(root, 'smallIcon')!
	account_preferences_id := auth_resource_id(root, 'accountPreferences')!
	mut custom_tokens := false
	if attribute := root.attribute(android_namespace, 'customTokens') {
		if attribute.kind != 0x12 { return error('authenticator customTokens must be a literal boolean') }
		custom_tokens = attribute.value != 0
	}
	return AuthenticatorDescription{account_type.clone(), package_name.clone(), label_id, icon_id, small_icon_id, account_preferences_id, custom_tokens}
}

// The caller authenticates the APK path/hash. This parser neither grants account
// authority nor trusts manifest accountType over the administrator's attestation.
pub fn read_authenticator(apk string, package_name string, service_name string, expected_type string) !AuthenticatorDescription {
	if package_name == '' || expected_type == '' || expected_type.len > 4096 || os.file_size(apk) > 1024 * 1024 * 1024 { return error('invalid authenticator parser input') }
	mut archive := os.open(apk)!
	defer { archive.close() }
	manifest := read_authenticator_zip_entry(mut archive, 'AndroidManifest.xml', u64(manifest_limit))!
	defer { unsafe { manifest.free() } }
	resource_id := authenticator_resource(manifest, package_name, service_name)!
	table := read_authenticator_zip_entry(mut archive, 'resources.arsc', u64(128 * 1024 * 1024))!
	defer { unsafe { table.free() } }
	path := resource_file(table, resource_id)!
	defer { unsafe { path.free() } }
	xml := read_authenticator_zip_entry(mut archive, path, u64(manifest_limit))!
	defer { unsafe { xml.free() } }
	return authenticator_description(xml, package_name, expected_type)
}
