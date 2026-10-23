// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import encoding.utf8
import json2

fn policy_wire_string(value string, limit int) bool {
	return value.len <= limit && utf8.validate_str(value)
}

// Author the complete format-1 policy file. Caller fields are borrowed and
// list order is preserved; the result is an independently owned JSON string
// without a trailing newline. Unlike validate()/decode_policy_document(), this
// checks wire shape, UTF-8 and allocation bounds, not canonical presentation.
// The service remains responsible for architecture, entries, uniqueness,
// version ranges, reserve limits, canonicalization and review/apply authority.
pub fn (document &PolicyDocument) encode() !string {
	policy := document.policy
	if document.format != 1 { return error('unsupported policy document format') }
	if !policy_wire_string(document.architecture, 16) || policy.allowed.len > 4096
		|| policy.pins.len > 4096 || policy.permissions.len > 5 || policy.licenses.len > 4096 {
		return error('policy document exceeds its supported field or entry limits')
	}
	for value in policy.allowed {
		if !policy_wire_string(value, 128) { return error('invalid policy allowlist string') }
	}
	for pin in policy.pins {
		if !policy_wire_string(pin.id, 128) || !policy_wire_string(pin.minimum, 29)
			|| !policy_wire_string(pin.before, 29) {
			return error('invalid policy pin string')
		}
	}
	for value in policy.permissions {
		if !policy_wire_string(value, 16) { return error('invalid policy permission string') }
	}
	for value in policy.licenses {
		if !policy_wire_string(value, 256) { return error('invalid policy license string') }
	}
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(*document, mut bytes)
	if bytes.len > 8 * 1024 * 1024 { return error('policy document exceeds metadata limit') }
	return bytes.bytestr()
}
