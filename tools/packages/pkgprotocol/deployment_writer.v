// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import encoding.utf8
import json2

// Format 1 has no locked member, including when the pin array is empty.
struct DeploymentRootsWire {
	format       int
	architecture string
	packages     []string
}

fn deployment_wire_string(value string, limit int) bool {
	return value.len <= limit && utf8.validate_str(value)
}

// Encode the exact format-1 or format-2 schema accepted by the decoder. Fields
// are borrowed and array order is preserved; the returned JSON string is owned
// and has no trailing newline. Only wire shape, UTF-8 and allocation bounds are
// checked here. Identities, canonical versions, architecture, uniqueness, pins,
// catalog provenance and policy remain the package service's responsibility.
pub fn (document &DeploymentDocument) encode() !string {
	if document.format !in [1, 2]! || (document.format == 1 && document.locked.len != 0) {
		return error('unsupported or incompatible deployment format')
	}
	if !deployment_wire_string(document.architecture, 16) || document.packages.len > 4096
		|| document.locked.len > 4096 {
		return error('deployment exceeds its supported field or package limits')
	}
	for id in document.packages {
		if !deployment_wire_string(id, 128) { return error('invalid deployment root string') }
	}
	for pin in document.locked {
		if !deployment_wire_string(pin.id, 128) || !deployment_wire_string(pin.version, 29)
			|| !deployment_wire_string(pin.architecture, 16) || !deployment_wire_string(pin.repository, 128)
			|| !deployment_wire_string(pin.public_key, 64) || !deployment_wire_string(pin.metadata_sha256, 64) {
			return error('invalid locked deployment string')
		}
	}
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	if document.format == 1 {
		json2.encode_append(DeploymentRootsWire{ format: 1, architecture: document.architecture,
			packages: document.packages }, mut bytes)
	} else {
		json2.encode_append(*document, mut bytes)
	}
	if bytes.len > 8 * 1024 * 1024 { return error('deployment exceeds metadata limit') }
	return bytes.bytestr()
}
